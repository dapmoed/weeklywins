#include <Arduino.h>
#include <ESP_I2S.h>
#include <SD.h>
#include <SPI.h>
#include <Preferences.h>
#include <WebServer.h>
#include <WiFi.h>
#include <esp_random.h>
#include <sys/time.h>
#include <time.h>

#include "RecorderButton.h"
#include "RecordingFileName.h"

namespace {
const int clockPin = 7;
const int wordSelectPin = 8;
const int dataPin = 9;
const int bootButtonPin = 0;
const int switchPin = 6;
const int ledPin = 48;
const int sdChipSelectPin = 10;
const int sdMosiPin = 11;
const int sdClockPin = 12;
const int sdMisoPin = 13;
const uint32_t sdFrequencyHz = 4000000;
const int sampleRate = 16000;
const size_t maxAudioBytes = 90 * sampleRate * sizeof(int16_t);
const size_t fileSystemReserve = 64 * 1024;
const time_t earliestTime = 1704067200;  // 2024-01-01 UTC
const time_t latestTime = 4102444800;    // 2100-01-01 UTC
const char *requestHeader = "X-WeeklyWins-Recorder";
const char *recordingDirectory = "/weeklywins";
const char *partialPath = "/weeklywins/capture.part";

I2SClass microphone;
WebServer server(80);
File capture;
String finalPath;
size_t audioBytes = 0;
size_t audioLimit = 0;
bool initialized = false;
RecorderButton recordButton;

struct WavHeader {
    char riff[4] = {'R', 'I', 'F', 'F'};
    uint32_t riffSize = 36;
    char format[8] = {'W', 'A', 'V', 'E', 'f', 'm', 't', ' '};
    uint32_t formatSize = 16;
    uint16_t encoding = 1;
    uint16_t channels = 1;
    uint32_t sampleRateHz = sampleRate;
    uint32_t byteRate = sampleRate * sizeof(int16_t);
    uint16_t alignment = sizeof(int16_t);
    uint16_t bits = 16;
    char data[4] = {'d', 'a', 't', 'a'};
    uint32_t dataSize = 0;
};
static_assert(sizeof(WavHeader) == 44, "WAV header layout");

void indicator(uint8_t red, uint8_t green, uint8_t blue) {
    rgbLedWrite(ledPin, red, green, blue);
}

void signalFailure(const char *message) {
    Serial.println(message);
    indicator(24, 10, 0);
}

String generateID() {
    uint8_t bytes[16];
    esp_fill_random(bytes, sizeof(bytes));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    char id[37];
    snprintf(id, sizeof(id), "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
             bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
             bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]);
    return id;
}

void startCapture() {
    const time_t now = time(nullptr);
    if (now < earliestTime || now >= latestTime) {
        signalFailure("Set the clock from WeeklyWins before recording.");
        return;
    }
    const uint64_t totalBytes = SD.totalBytes();
    const uint64_t usedBytes = SD.usedBytes();
    const uint64_t freeBytes = totalBytes > usedBytes ? totalBytes - usedBytes : 0;
    if (freeBytes < fileSystemReserve + sampleRate * sizeof(int16_t)) {
        signalFailure("Storage full. Import recordings to free space.");
        return;
    }

    capture = SD.open(partialPath, FILE_WRITE);
    const WavHeader header;
    if (!capture || capture.write(reinterpret_cast<const uint8_t *>(&header), sizeof(header)) != sizeof(header)) {
        capture.close();
        SD.remove(partialPath);
        signalFailure("Can't allocate a recording.");
        return;
    }
    if (!microphone.begin(I2S_MODE_STD, sampleRate, I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_STEREO)) {
        capture.close();
        SD.remove(partialPath);
        signalFailure("Can't start the microphone.");
        return;
    }
    finalPath = String(recordingDirectory) + "/" + generateID() + "_" + String(static_cast<unsigned long>(now)) + ".wav";
    audioBytes = 0;
    audioLimit = static_cast<size_t>(min<uint64_t>(maxAudioBytes, freeBytes - fileSystemReserve));
    indicator(24, 0, 0);
}

void finishCapture() {
    microphone.end();
    WavHeader header;
    header.riffSize += audioBytes;
    header.dataSize = audioBytes;
    bool finalized = audioBytes > 0 && capture.seek(0)
        && capture.write(reinterpret_cast<const uint8_t *>(&header), sizeof(header)) == sizeof(header);
    capture.close();
    if (!finalized || !SD.rename(partialPath, finalPath)) {
        SD.remove(partialPath);
        signalFailure("Can't finalize the recording.");
        return;
    }
    indicator(0, 0, 0);
}

void captureSamples() {
    int32_t stereo[256 * 2];
    int16_t mono[256];
    const size_t readBytes = microphone.readBytes(reinterpret_cast<char *>(stereo), sizeof(stereo));
    if (readBytes == 0) {
        finishCapture();
        return;
    }
    const size_t frames = readBytes / (2 * sizeof(int32_t));
    const size_t count = min(frames, (audioLimit - audioBytes) / sizeof(int16_t));
    for (size_t index = 0; index < count; ++index) {
        // INMP441 uses the left slot. Give speech 18 dB of gain before reducing to PCM16.
        const int32_t sample = stereo[index * 2] >> 13;
        mono[index] = static_cast<int16_t>(constrain(sample, -32768, 32767));
    }
    if (capture.write(reinterpret_cast<const uint8_t *>(mono), count * sizeof(int16_t)) != count * sizeof(int16_t)) {
        // Keep only frames that were fully written before the error.
        finishCapture();
        return;
    }
    audioBytes += count * sizeof(int16_t);
    if (audioLimit - audioBytes < sizeof(int16_t)) finishCapture();
}

bool authorized() {
    if (server.header(requestHeader) == "1") return true;
    server.send(403);
    return false;
}

String nextRecordingPath(File &directory) {
    bool isDirectory = false;
    for (String path = directory.getNextFileName(&isDirectory); !path.isEmpty();
         path = directory.getNextFileName(&isDirectory)) {
        const int separator = path.lastIndexOf('/');
        if (!isDirectory && isRecordingFileName(path.c_str() + (separator + 1))) return path;
    }
    return "";
}

String pathForID(const String &id) {
    if (id.length() != 36) return "";
    File directory = SD.open(recordingDirectory);
    for (String path = nextRecordingPath(directory); !path.isEmpty(); path = nextRecordingPath(directory)) {
        const unsigned int start = path.lastIndexOf('/') + 1;
        if (path.substring(start, start + 36).equalsIgnoreCase(id)) return path;
    }
    return "";
}

void setClock() {
    if (!authorized()) return;
    String value = server.arg("unix");
    char *end;
    const time_t seconds = strtoll(value.c_str(), &end, 10);
    if (*end || seconds < earliestTime || seconds >= latestTime) {
        server.send(400);
        return;
    }
    const timeval timeOfDay = {seconds, 0};
    server.send(settimeofday(&timeOfDay, nullptr) == 0 ? 204 : 500);
}

void listRecordings() {
    if (!authorized()) return;
    File directory = SD.open(recordingDirectory);
    if (!directory || !directory.isDirectory()) {
        server.send(500);
        return;
    }
    server.setContentLength(CONTENT_LENGTH_UNKNOWN);
    server.send(200, "application/json", "");
    server.sendContent("[");
    bool first = true;
    for (String path = nextRecordingPath(directory); !path.isEmpty(); path = nextRecordingPath(directory)) {
        const unsigned int start = path.lastIndexOf('/') + 1;
        const String item = (first ? "{" : ",{") + String("\"id\":\"") + path.substring(start, start + 36)
            + "\",\"recordedAt\":" + path.substring(start + 37, start + 47) + "}";
        server.sendContent(item);
        first = false;
    }
    server.sendContent("]");
    server.sendContent("");
}

void downloadRecording() {
    if (!authorized()) return;
    const String path = pathForID(server.arg("id"));
    if (path.isEmpty()) {
        server.send(404);
        return;
    }
    File audio = SD.open(path, FILE_READ);
    if (!audio) {
        server.send(500);
        return;
    }
    server.streamFile(audio, "audio/wav");
}

void acknowledgeRecording() {
    if (!authorized()) return;
    const String path = pathForID(server.arg("id"));
    server.send(path.isEmpty() || SD.remove(path) ? 204 : 500);
}

bool startServer(Preferences &preferences) {
    char ssid[24];
    snprintf(ssid, sizeof(ssid), "WeeklyWins-%06lX", static_cast<unsigned long>(ESP.getEfuseMac() & 0xFFFFFF));
    String password = preferences.getString("wifi-password");
    if (password.isEmpty()) {
        char generated[17];
        snprintf(generated, sizeof(generated), "%08lX%08lX",
                 static_cast<unsigned long>(esp_random()), static_cast<unsigned long>(esp_random()));
        if (!preferences.putString("wifi-password", generated)) return false;
        password = generated;
    }
    WiFi.mode(WIFI_AP);
    if (!WiFi.softAP(ssid, password.c_str())) return false;
    Serial.printf("Wi-Fi: %s  Password: %s\n", ssid, password.c_str());
    const char *headers[] = {requestHeader};
    server.collectHeaders(headers, 1);
    server.on("/clock", HTTP_POST, setClock);
    server.on("/recordings", HTTP_GET, listRecordings);
    server.on("/recording", HTTP_GET, downloadRecording);
    server.on("/recording", HTTP_DELETE, acknowledgeRecording);
    server.begin();
    return true;
}

void checkButton() {
    const bool bootPressed = digitalRead(bootButtonPin) == LOW;
    const bool switchPressed = digitalRead(switchPin) == LOW;
    if (!recordButton.update(bootPressed, switchPressed, millis())) return;

    if (capture) finishCapture();
    else startCapture();
}
}  // namespace

void setup() {
    Serial.begin(115200);
    pinMode(bootButtonPin, INPUT_PULLUP);
    pinMode(switchPin, INPUT_PULLUP);
    indicator(0, 0, 0);
    SPI.begin(sdClockPin, sdMisoPin, sdMosiPin, sdChipSelectPin);
    if (!SD.begin(sdChipSelectPin, SPI, sdFrequencyHz, "/sd", 5, false)) {
        signalFailure("Can't mount microSD. Insert a FAT32 card and restart.");
        return;
    }
    if (!SD.exists(recordingDirectory) && !SD.mkdir(recordingDirectory)) {
        signalFailure("Can't create the WeeklyWins directory on microSD.");
        return;
    }
    if (SD.exists(partialPath) && !SD.remove(partialPath)) {
        signalFailure("Can't remove the unfinished recording on microSD.");
        return;
    }
    Preferences preferences;
    if (!preferences.begin("weeklywins")) {
        signalFailure("Can't open recorder settings.");
        return;
    }
    if (!startServer(preferences)) {
        signalFailure("Can't start the Wi-Fi access point.");
        return;
    }
    microphone.setPins(clockPin, wordSelectPin, -1, dataPin);
    initialized = true;
}

void loop() {
    if (!initialized) {
        delay(50);
        return;
    }
    checkButton();
    if (capture) captureSamples();
    else {
        server.handleClient();
        delay(1);
    }
}
