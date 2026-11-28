#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

enum class RecorderCommand : uint8_t { clock = 1, list = 2, open = 3, read = 4, acknowledge = 5 };
enum class RecorderReply : uint8_t { success = 0, invalid = 1, busy = 2, storage = 3, changed = 4 };

inline std::size_t recorderBLEFrame(uint8_t *out, uint8_t tag, uint8_t status, uint16_t offset,
                                    const uint8_t *bytes, std::size_t length) {
    out[0] = tag;
    out[1] = status;
    out[2] = static_cast<uint8_t>(offset);
    out[3] = static_cast<uint8_t>(offset >> 8);
    if (length) std::memcpy(out + 4, bytes, length);
    return length + 4;
}

inline uint32_t recorderReadUInt32(const uint8_t *data) {
    return uint32_t(data[0]) | uint32_t(data[1]) << 8 | uint32_t(data[2]) << 16 | uint32_t(data[3]) << 24;
}

inline void recorderWriteUInt32(uint8_t *data, uint32_t value) {
    for (int i = 0; i < 4; ++i) data[i] = static_cast<uint8_t>(value >> (8 * i));
}

inline uint8_t recorderHexValue(char value) {
    return value <= '9' ? value - '0' : (value | 0x20) - 'a' + 10;
}

inline void recorderParseUUID(const char *text, uint8_t *bytes) {
    for (int i = 0, j = 0; i < 16; ++i, j += 2) {
        if (text[j] == '-') ++j;
        bytes[i] = static_cast<uint8_t>((recorderHexValue(text[j]) << 4) | recorderHexValue(text[j + 1]));
    }
}
