#include "../WeeklyWinsRecorder/RecorderButton.h"
#include <cassert>
#include <cstdint>

constexpr int noAction = 0;
constexpr int toggleRecording = 1;
constexpr int openPairingWindow = 2;

int main() {
    RecorderButton button;

    // A short external-switch tap toggles recording only after release.
    assert(button.update(false, false, 0) == noAction);
    assert(button.update(false, true, 10) == noAction);
    assert(button.update(false, true, 40) == noAction);
    assert(button.update(false, false, 50) == noAction);
    assert(button.update(false, false, 80) == toggleRecording);

    // Holding the external switch for five seconds opens pairing once.
    assert(button.update(false, true, 100) == noAction);
    assert(button.update(false, true, 130) == noAction);
    assert(button.update(false, true, 5129) == noAction);
    assert(button.update(false, true, 5130) == openPairingWindow);
    assert(button.update(false, true, 8000) == noAction);
    assert(button.update(false, false, 8010) == noAction);
    assert(button.update(false, false, 8040) == noAction);

    // The built-in BOOT button remains a record toggle, never pairing.
    assert(button.update(true, false, 9000) == noAction);
    assert(button.update(true, false, 9030) == noAction);
    assert(button.update(true, false, 14030) == noAction);
    assert(button.update(false, false, 14040) == noAction);
    assert(button.update(false, false, 14070) == toggleRecording);

    // Hold timing remains correct across millis() wraparound.
    RecorderButton wraparound;
    assert(wraparound.update(false, true, UINT32_MAX - 20) == noAction);
    assert(wraparound.update(false, true, 9) == noAction);
    assert(wraparound.update(false, true, 5009) == openPairingWindow);
}
