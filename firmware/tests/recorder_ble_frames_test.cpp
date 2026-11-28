#include "../WeeklyWinsRecorder/RecorderBLEFrames.h"
#include <cassert>

int main() {
    const uint8_t chunk[]{7, 0, 19};
    uint8_t buffer[7]{};
    const auto length = recorderBLEFrame(buffer, 42, 0x80, 300, chunk, sizeof(chunk));
    assert(length == sizeof(buffer));
    assert(buffer[0] == 42 && buffer[1] == 0x80);
    assert(buffer[2] == 44 && buffer[3] == 1);
    assert(buffer[4] == 7 && buffer[5] == 0 && buffer[6] == 19);
    assert(recorderBLEFrame(buffer, 1, 0x80, 0, nullptr, 0) == 4);
}
