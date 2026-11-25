#pragma once

#include <string_view>

inline bool isRecordingFileName(std::string_view name) {
    if (name.size() != 51 || name[36] != '_' || name.substr(47) != ".wav") return false;

    for (std::size_t i = 0; i < 36; ++i) {
        const char c = name[i];
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (c != '-') return false;
        } else if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
            return false;
        }
    }
    // Generated Unix timestamps are ten decimal digits and cannot start with zero.
    if (name[37] == '0') return false;
    for (std::size_t i = 37; i < 47; ++i) {
        if (name[i] < '0' || name[i] > '9') return false;
    }
    return true;
}
