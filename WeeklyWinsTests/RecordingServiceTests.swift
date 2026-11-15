import XCTest
@testable import WeeklyWins

final class RecordingServiceTests: XCTestCase {
    func testRecordingLibraryListsSavedAudioNewestFirst() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_700_000_100)
        let olderURL = directory.appendingPathComponent("recording-old.m4a")
        let newerURL = directory.appendingPathComponent("recording-new.m4a")
        try Data([0]).write(to: olderURL)
        try Data([0]).write(to: newerURL)
        try Data([0]).write(to: directory.appendingPathComponent("not-a-recording.txt"))
        try FileManager.default.setAttributes([.modificationDate: olderDate], ofItemAtPath: olderURL.path)
        try FileManager.default.setAttributes([.modificationDate: newerDate], ofItemAtPath: newerURL.path)

        let recordings = RecordingLibrary.scan(directory: directory)

        XCTAssertEqual(recordings.map { $0.fileURL.lastPathComponent }, ["recording-new.m4a", "recording-old.m4a"])
        XCTAssertEqual(recordings.first?.recordedAt, newerDate)
    }

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
