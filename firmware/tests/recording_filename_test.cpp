#include "../WeeklyWinsRecorder/RecordingFileName.h"
#include <cassert>

int main() {
    assert(isRecordingFileName("9fa9e63a-75bc-4074-913a-c821b291970b_1795622000.wav"));
    assert(isRecordingFileName("9FA9E63A-75BC-4074-913A-C821B291970B_1795622000.wav"));
    assert(!isRecordingFileName("capture.part"));
    assert(!isRecordingFileName("9fa9e63a-75bc-4074-913a-c821b291970b_179562200x.wav"));
    assert(!isRecordingFileName("9fa9e63a-75bc-4074-913a-c821b291970b_1795622000.txt"));
    assert(!isRecordingFileName(R"(9fa9e63a-75bc-4074-913a-c821b291970"_1795622000.wav)"));
    assert(!isRecordingFileName("/weeklywins/9fa9e63a-75bc-4074-913a-c821b291970b_1795622000.wav"));
}
