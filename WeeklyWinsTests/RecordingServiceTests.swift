import XCTest
@testable import WeeklyWins

final class RecordingServiceTests: XCTestCase {
    @MainActor
    func testShortcutIntentStartsThenStopsRecording() async throws {
        let service = RecordingService.shared
        service.stop()

        _ = try await ToggleRecordingIntent().perform()
        XCTAssertTrue(service.isRecording)

        _ = try await ToggleRecordingIntent().perform()
        XCTAssertFalse(service.isRecording)
    }
}
