import XCTest
@testable import WeeklyWins

final class RecordingManagementTests: XCTestCase {
    @MainActor
    func testStartupCompletesDraftCleanupAfterInterruptedDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let event = DiaryEvent(recordingID: id, sourceText: "Секретный черновик", text: "Черновик")
        let drafts = EventDraftStore()
        defer { drafts.remove(id: event.id) }
        try drafts.save(event)
        var tombstone = Recording(id: id, recordedAt: .now, fileName: "deleted.m4a", state: .saved)
        tombstone.deletedAt = .now
        tombstone.deletedEventIDs = [event.id]
        try JSONEncoder().encode([tombstone]).write(to: directory.appendingPathComponent("recordings.json"))
        _ = RecordingStore(directory: directory)
        XCTAssertNil(drafts.load(for: event))
    }

    @MainActor
    func testRelaunchReleasesInterruptedTranscriptionForDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let pending = try store.beginRecording()
        try Data([1, 2, 3]).write(to: store.fileURL(for: pending))
        let recording = try store.finalizeRecording(id: pending.id, duration: 2)
        try store.updateTranscription(recordingID: recording.id, transcript: nil, processingState: .processing, errorMessage: nil)
        let restored = RecordingStore(directory: directory)
        XCTAssertEqual(restored.recordings.first?.processingState, .failed)
        XCTAssertNoThrow(try restored.deleteRecording(id: recording.id))
    }

    @MainActor
    func testDeletionRemovesAudioAndEventsWithoutImportingThemAgain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let pending = try store.beginRecording()
        try Data([1, 2, 3]).write(to: store.fileURL(for: pending))
        let recording = try store.finalizeRecording(id: pending.id, duration: 2)
        try store.updateTranscription(recordingID: recording.id, transcript: "Подготовил отчёт", processingState: .completed, errorMessage: nil)
        try store.deleteRecording(id: recording.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: recording).path))
        let restored = RecordingStore(directory: directory)
        XCTAssertTrue(restored.recordings.filter { $0.deletedAt == nil }.isEmpty)
        XCTAssertTrue(ReportQuery.events(in: restored.recordings, period: .month, date: .now).isEmpty)
        XCTAssertNil(restored.recordings.first?.transcript)
    }

    @MainActor
    func testActiveRecordingCannotBeDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let recording = try store.beginRecording()
        XCTAssertThrowsError(try store.deleteRecording(id: recording.id))
        XCTAssertNil(store.recordings.first?.deletedAt)
    }

    func testSearchMatchesTranscriptEventsAndRussianDate() {
        let id = UUID()
        var recording = Recording(id: id, recordedAt: Date(timeIntervalSince1970: 1_794_911_400), fileName: "audio.m4a", state: .saved)
        recording.transcript = "Подготовил годовой отчёт"
        recording.events = [DiaryEvent(recordingID: id, sourceText: "Источник", text: "Обсудил бюджет", category: .work)]
        XCTAssertTrue(RecordingSearch.matches(recording, query: "ОТЧЕТ"))
        XCTAssertTrue(RecordingSearch.matches(recording, query: "бюджет"))
        XCTAssertTrue(RecordingSearch.matches(recording, query: "ноября"))
        XCTAssertFalse(RecordingSearch.matches(recording, query: "отпуск"))
    }
}
