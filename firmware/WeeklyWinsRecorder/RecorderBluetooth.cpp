#include "RecorderBluetooth.h"

#include <BLEDevice.h>
#include <BLESecurity.h>
#include <atomic>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <host/ble_att.h>
#include <host/ble_gatt.h>
#include <host/ble_hs.h>
#if defined(CONFIG_BLUEDROID_ENABLED)
#include <esp_gatt_defs.h>
#endif

namespace RecorderBluetooth {
namespace {
constexpr char serviceUUID[] = "5C802E33-A13B-4272-B674-BF48F1663900";
constexpr char commandUUID[] = "5C802E33-A13B-4272-B674-BF48F1663901";
constexpr char responseUUID[] = "5C802E33-A13B-4272-B674-BF48F1663902";
constexpr uint32_t disconnected = UINT32_MAX;
constexpr uint16_t packetLimit = 244;
constexpr uint32_t pairingWindowDurationMs = 60'000;

std::atomic<uint32_t> connection{disconnected};
std::atomic<uint32_t> pairingWindowStartedAt{0};
std::atomic<bool> pairingWindowOpen{false};
std::atomic<bool> currentConnectionBonded{false};
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

bool isPairingWindowOpen() {
    if (!pairingWindowOpen.load()) return false;
    if (static_cast<uint32_t>(millis() - pairingWindowStartedAt.load()) < pairingWindowDurationMs) return true;
    pairingWindowOpen.store(false);
    return false;
}

class SecurityCallbacks final : public BLESecurityCallbacks {
    bool onSecurityRequest() override {
        return isPairingWindowOpen() || currentConnectionBonded.load();
    }

    void onAuthenticationComplete(ble_gap_conn_desc *descriptor) override {
        if (descriptor != nullptr && descriptor->sec_state.bonded) {
            currentConnectionBonded.store(true);
            pairingWindowOpen.store(false);
        }
    }
};

class ServerCallbacks final : public BLEServerCallbacks {
    void onConnect(BLEServer *server, ble_gap_conn_desc *descriptor) override {
        if (connection.load() != disconnected) {
            server->disconnect(descriptor->conn_handle);
            return;
        }
        const bool bonded = descriptor->sec_state.bonded;
        if (!bonded && !isPairingWindowOpen()) {
            server->disconnect(descriptor->conn_handle);
            return;
        }
        currentConnectionBonded.store(bonded);
        ++generation;
        connection.store(uint32_t(generation) << 16 | descriptor->conn_handle);
        // Units are 1.25 ms for the connection interval and 10 ms for supervision.
        server->updateConnParams(descriptor->conn_handle, 12, 24, 0, 500);
    }

    void onDisconnect(BLEServer *server, ble_gap_conn_desc *descriptor) override {
        const uint32_t current = connection.load();
        if (current != disconnected && static_cast<uint16_t>(current) == descriptor->conn_handle) {
            connection.store(disconnected);
            currentConnectionBonded.store(false);
        }
    }
};

class CommandCallbacks final : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *characteristic, ble_gap_conn_desc *descriptor) override {
        const uint32_t current = connection.load();
        const size_t size = characteristic->getLength();
        if (current == disconnected || static_cast<uint16_t>(current) != descriptor->conn_handle
            || !descriptor->sec_state.encrypted
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
SecurityCallbacks securityCallbacks;

bool notify(uint32_t target, const uint8_t *bytes, size_t size) {
    if (target != connection.load()) return false;
    auto *packet = ble_hs_mbuf_from_flat(bytes, size);
    if (!packet) return false;
    return ble_gatts_notify_custom(static_cast<uint16_t>(target), responseCharacteristic->getHandle(), packet) == 0;
}
}  // namespace

bool begin() {
    requests = xQueueCreate(1, sizeof(Request));
    if (!requests) return false;

    char name[24];
    snprintf(name, sizeof(name), "WeeklyWins-%06lX", static_cast<unsigned long>(ESP.getEfuseMac() & 0xFFFFFF));
    BLEDevice::init(name);
    BLEDevice::setMTU(247);
    BLEDevice::setSecurityCallbacks(&securityCallbacks);
    BLESecurity::setCapability(ESP_IO_CAP_NONE);
    BLESecurity::setAuthenticationMode(true, false, true);

    BLEServer *server = BLEDevice::createServer();
    server->setCallbacks(&serverCallbacks);
    server->advertiseOnDisconnect(true);
    BLEService *service = server->createService(serviceUUID);
    uint32_t commandProperties = BLECharacteristic::PROPERTY_WRITE;
#if defined(CONFIG_NIMBLE_ENABLED)
    commandProperties |= BLECharacteristic::PROPERTY_WRITE_ENC;
#endif
    auto *command = service->createCharacteristic(commandUUID, commandProperties);
#if defined(CONFIG_BLUEDROID_ENABLED)
    command->setAccessPermissions(ESP_GATT_PERM_WRITE_ENCRYPTED);
#endif
    command->setCallbacks(&commandCallbacks);
    responseCharacteristic = service->createCharacteristic(responseUUID, BLECharacteristic::PROPERTY_NOTIFY);
    service->start();
    BLEAdvertising *advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(serviceUUID);
    advertising->setScanResponse(true);
    BLEDevice::startAdvertising();
    return true;
}

void openPairingWindow() {
    pairingWindowStartedAt.store(millis());
    pairingWindowOpen.store(true);
}

void closePairingWindow() {
    pairingWindowOpen.store(false);
}

bool pairingWindowActive() {
    return isPairingWindowOpen();
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
