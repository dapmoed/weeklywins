#pragma once

#include <cstdint>

class RecorderButton {
public:
    enum Action : std::uint8_t {
        none = 0,
        toggleRecording = 1,
        openPairingWindow = 2,
    };

    Action update(bool bootPressed, bool switchPressed, std::uint32_t timeMs, bool recording = false) {
        const bool pressed = bootPressed || switchPressed;
        if (pressed != reading) {
            reading = pressed;
            lastChange = timeMs;
        }

        if (reading != stable && elapsed(timeMs, lastChange) >= debounceMs) {
            stable = reading;
            if (stable) {
                gestureStarted = timeMs;
                pairingGesture = switchPressed && !bootPressed;
                pairingTriggered = false;
            } else {
                const bool wasPairing = pairingTriggered;
                pairingGesture = false;
                pairingTriggered = false;
                return wasPairing ? none : toggleRecording;
            }
        }

        if (stable && switchPressed && !bootPressed && pairingGesture && !recording
            && !pairingTriggered && elapsed(timeMs, gestureStarted) >= pairingHoldMs) {
            pairingTriggered = true;
            return openPairingWindow;
        }

        return none;
    }

private:
    static std::uint32_t elapsed(std::uint32_t now, std::uint32_t then) {
        return now - then;
    }

    static constexpr std::uint32_t debounceMs = 30;
    static constexpr std::uint32_t pairingHoldMs = 5000;
    std::uint32_t lastChange = 0;
    std::uint32_t gestureStarted = 0;
    bool reading = false;
    bool stable = false;
    bool pairingGesture = false;
    bool pairingTriggered = false;
};
