import XCTest
@testable import WeeklyWins

final class TranscriptImportTests: XCTestCase {
    @MainActor
    private func makeStore() -> (RecordingStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (RecordingStore(directory: directory), directory)
    }

    private func entry(id: UUID? = UUID(), at seconds: TimeInterval = 2_000,
                       transcript: String? = "Купил хлеб", duration: TimeInterval? = 60) -> TranscriptExport.Entry {
        TranscriptExport.Entry(id: id, recordedAt: Date(timeIntervalSince1970: seconds),
                               duration: duration, transcript: transcript)
    }

    @MainActor
    func testSkipsEntriesWithExistingActiveID() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = entry()
        try store.importRecordings([existing])
        let summary = try store.importRecordings([existing, entry()])

        XCTAssertEqual(summary, ImportSummary(imported: 1, skippedDuplicates: 1))
        XCTAssertEqual(store.recordings.filter { $0.id == existing.id }.count, 1)
    }

    @MainActor
    func testImportWithoutIDAssignsFreshUUID() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let summary = try store.importRecordings([entry(id: nil)])

        XCTAssertEqual(summary.imported, 1)
        XCTAssertNotNil(store.recordings.first?.id)
    }

    @MainActor
    func testImportWithTranscriptExtractsEvents() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.importRecordings([entry()])

        let recording = try XCTUnwrap(store.recordings.first)
        XCTAssertEqual(recording.state, .saved)
        XCTAssertEqual(recording.processingState, .completed)
        XCTAssertNotNil(recording.transcriptUpdatedAt)
        XCTAssertFalse(try XCTUnwrap(recording.events).isEmpty)
        XCTAssertEqual(recording.events?.first?.recordingID, recording.id)
    }

    @MainActor
    func testImportWithoutTranscriptMarksFailed() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.importRecordings([entry(transcript: nil)])

        let recording = try XCTUnwrap(store.recordings.first)
        XCTAssertEqual(recording.processingState, .failed)
        XCTAssertNotEqual(recording.automaticTranscriptionPending, true)
        XCTAssertNil(recording.events)
    }

    @MainActor
    func testDeletedRecordingWithSameIDCanBeRestored() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = entry()
        try store.importRecordings([original])
        try store.deleteRecording(id: try XCTUnwrap(original.id))

        let summary = try store.importRecordings([original])
        XCTAssertEqual(summary, ImportSummary(imported: 1, skippedDuplicates: 0))
        XCTAssertEqual(store.recordings.first(where: { $0.id == original.id })?.deletedAt, nil)
    }

    @MainActor
    func testImportedRecordingsPersist() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.importRecordings([entry(), entry(id: nil, at: 3_000)])

        let restored = RecordingStore(directory: directory)
        XCTAssertEqual(restored.recordings.count, 2)
    }
}
