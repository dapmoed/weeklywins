#include "../WeeklyWinsRecorder/RecorderButton.h"
#include <cassert>
#include <cstdint>

int main() {
    RecorderButton button;
    assert(!button.update(false, false, 0));
    assert(!button.update(false, true, 10));
    assert(!button.update(false, false, 14));
    assert(!button.update(false, true, 17));
    assert(!button.update(false, true, 46));
    assert(button.update(false, true, 47));
    assert(!button.update(false, true, 200));

    // Pressing BOOT while the external switch is held is still one gesture.
    assert(!button.update(true, true, 230));
    assert(!button.update(true, false, 250));
    assert(!button.update(false, false, 280));
    assert(!button.update(false, false, 310));

    assert(!button.update(true, false, 320));
    assert(button.update(true, false, 350));
    assert(!button.update(true, false, 500));

    RecorderButton ticker;
    assert(!ticker.update(false, true, UINT32_MAX - 10));
    assert(ticker.update(false, true, 19));
}
