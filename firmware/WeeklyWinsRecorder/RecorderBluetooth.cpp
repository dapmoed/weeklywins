#include "RecorderBluetooth.h"

#include <BLEDevice.h>
#include <BLESecurity.h>
#include <Preferences.h>
#include <atomic>
#include <esp_random.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <host/ble_att.h>
#include <host/ble_gatt.h>
#include <host/ble_hs.h>

namespace RecorderBluetooth {
namespace {
constexpr char serviceUUID[] = "5C802E33-A13B-4272-B674-BF48F1663900";
constexpr char commandUUID[] = "5C802E33-A13B-4272-B674-BF48F1663901";
constexpr char responseUUID[] = "5C802E33-A13B-4272-B674-BF48F1663902";
constexpr uint32_t disconnected = UINT32_MAX;
constexpr uint16_t packetLimit = 244;

std::atomic<uint32_t> connection{disconnected};
uint16_t generation = 0;
QueueHandle_t requests;
BLECharacteristic *responseCharacteristic;
uint8_t response[maxWindow];
uint32_t responseSession = disconnected;
uint32_t authorizedSession = disconnected;
uint16_t responseLength = 0;
uint16_t responseOffset = 0;
uint8_t responseTag = 0;
RecorderReply responseStatus;
bool responsePending = false;
bool haveNewRecording = false;

class ServerCallbacks final : public BLEServerCallbacks {
    void onConnect(BLEServer *server, ble_gap_conn_desc *descriptor) override {
        if (connection.load() != disconnected) {
            server->disconnect(descriptor->conn_handle);
            return;
        }
        ++generation;
        connection.store(uint32_t(generation) << 16 | descriptor->conn_handle);
        // Units are 1.25 ms for the connection interval and 10 ms for supervision.
        server->updateConnParams(descriptor->conn_handle, 12, 24, 0, 500);
    }

    void onDisconnect(BLEServer *server, ble_gap_conn_desc *descriptor) override {
        const uint32_t current = connection.load();
        if (current != disconnected && static_cast<uint16_t>(current) == descriptor->conn_handle) {
            connection.store(disconnected);
        }
    }
};

class CommandCallbacks final : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *characteristic, ble_gap_conn_desc *descriptor) override {
        const uint32_t current = connection.load();
        const size_t size = characteristic->getLength();
        if (current == disconnected || static_cast<uint16_t>(current) != descriptor->conn_handle
            || !descriptor->sec_state.encrypted || !descriptor->sec_state.authenticated
            || size < 2 || size > sizeof(Request::bytes)) return;
        Request request{};
        request.session = current;
        request.size = size;
        memcpy(request.bytes, characteristic->getData(), size);
        if (request.bytes[0] != 0) xQueueSend(requests, &request, 0);
    }
};

ServerCallbacks serverCallbacks;
CommandCallbacks commandCallbacks;

bool notify(uint32_t target, const uint8_t *bytes, size_t size) {
    if (target != connection.load()) return false;
    auto *packet = ble_hs_mbuf_from_flat(bytes, size);
    if (!packet) return false;
    return ble_gatts_notify_custom(static_cast<uint16_t>(target), responseCharacteristic->getHandle(), packet) == 0;
}
}  // namespace

bool begin(Preferences &preferences) {
    uint32_t pin = preferences.getUInt("ble-pin", 0);
    if (pin < 100000 || pin > 999999) {
        pin = 100000 + esp_random() % 900000;
        if (!preferences.putUInt("ble-pin", pin)) return false;
    }
    requests = xQueueCreate(1, sizeof(Request));
    if (!requests) return false;

    char name[24];
    snprintf(name, sizeof(name), "WeeklyWins-%06lX", static_cast<unsigned long>(ESP.getEfuseMac() & 0xFFFFFF));
    BLEDevice::init(name);
    BLEDevice::setMTU(247);
    BLESecurity::setCapability(ESP_IO_CAP_OUT);
    BLESecurity::setAuthenticationMode(true, true, true);
    BLESecurity::setPassKey(true, pin);

    BLEServer *server = BLEDevice::createServer();
    server->setCallbacks(&serverCallbacks);
    server->advertiseOnDisconnect(true);
    BLEService *service = server->createService(serviceUUID);
    auto *command = service->createCharacteristic(commandUUID,
        BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_AUTHEN);
    command->setCallbacks(&commandCallbacks);
    responseCharacteristic = service->createCharacteristic(responseUUID, BLECharacteristic::PROPERTY_NOTIFY);
    service->start();
    BLEAdvertising *advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(serviceUUID);
    advertising->setScanResponse(true);
    BLEDevice::startAdvertising();
    Serial.printf("Bluetooth: %s  Pairing PIN: %06lu\n", name, static_cast<unsigned long>(pin));
    return true;
}

uint32_t session() { return connection.load(); }

bool receive(Request &request) {
    if (responsePending || xQueueReceive(requests, &request, 0) != pdTRUE) return false;
    if (request.session != connection.load()) return false;
    authorizedSession = request.session;
    return true;
}

uint8_t *responseBuffer() { return response; }

void reply(const Request &request, RecorderReply status, uint16_t length) {
    responseSession = request.session;
    responseTag = request.bytes[0];
    responseStatus = status;
    responseLength = length;
    responseOffset = 0;
    responsePending = true;
}

void recordingAvailable() { haveNewRecording = true; }

void poll() {
    const uint32_t current = connection.load();
    if (responsePending && responseSession != current) responsePending = false;
    if (current == disconnected || authorizedSession != current) return;

    if (responsePending) {
        const uint16_t mtu = ble_att_mtu(static_cast<uint16_t>(current));
        if (mtu < 23) return;
        const uint16_t capacity = min<uint16_t>(packetLimit, mtu - 3) - 4;
        const uint16_t length = min<uint16_t>(responseLength - responseOffset, capacity);
        const bool final = responseOffset + length == responseLength;
        uint8_t packet[packetLimit];
        const size_t wireLength = recorderBLEFrame(packet, responseTag,
            static_cast<uint8_t>(responseStatus) | (final ? 0x80 : 0),
            responseOffset, response + responseOffset, length);
        if (notify(current, packet, wireLength)) {
            responseOffset += length;
            if (final) responsePending = false;
        }
    } else if (haveNewRecording) {
        uint8_t packet[4];
        recorderBLEFrame(packet, 0, 0x80 | static_cast<uint8_t>(RecorderReply::changed), 0, nullptr, 0);
        if (notify(current, packet, sizeof(packet))) haveNewRecording = false;
    }
}
}  // namespace RecorderBluetooth
