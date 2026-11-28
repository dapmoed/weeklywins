#pragma once

#include <Arduino.h>
#include "RecorderBLEFrames.h"

namespace RecorderBluetooth {
constexpr uint16_t maxWindow = 8192;
constexpr uint8_t pageSize = 16;
constexpr uint8_t entrySize = 20;

struct Request {
    uint32_t session;
    uint8_t size;
    uint8_t bytes[20];  // Request tag, operation, then arguments.
};

bool begin();
void openPairingWindow();
void closePairingWindow();
bool pairingWindowActive();
uint32_t session();
bool receive(Request &request);
uint8_t *responseBuffer();
void reply(const Request &request, RecorderReply status, uint16_t length = 0);
void recordingAvailable();
void poll();
}
