#pragma once

#include <cstdint>

class RecorderButton {
public:
    bool update(bool bootPressed, bool switchPressed, std::uint32_t timeMs) {
        const bool pressed = bootPressed || switchPressed;
        if (pressed != reading) {
            reading = pressed;
            lastChange = timeMs;
        }
        if (reading == stable || timeMs - lastChange < debounceMs) return false;
        stable = reading;
        return stable;
    }

private:
    static constexpr std::uint32_t debounceMs = 30;
    std::uint32_t lastChange = 0;
    bool reading = false;
    bool stable = false;
};
