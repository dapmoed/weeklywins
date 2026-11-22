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
        let reviewDrafts = EventReviewDraftStore()
        defer { reviewDrafts.remove(recordingID: id) }
        try reviewDrafts.save(EventReviewDraft(baseline: [event], events: []), recordingID: id)
        var tombstone = Recording(id: id, recordedAt: .now, fileName: "deleted.m4a", state: .saved)
        tombstone.deletedAt = .now
        tombstone.deletedEventIDs = [event.id]
        try JSONEncoder().encode([tombstone]).write(to: directory.appendingPathComponent("recordings.json"))
        _ = RecordingStore(directory: directory)
        XCTAssertNil(drafts.load(for: event))
        XCTAssertNil(reviewDrafts.load(recordingID: id))
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

    @MainActor
    func testStartupDeletesRecordingsWithoutUsefulContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        func makeRecording(duration: TimeInterval, transcript: String?, processingState: RecordingProcessingState = .completed) throws -> Recording {
            let pending = try store.beginRecording()
            try Data([1, 2, 3]).write(to: store.fileURL(for: pending))
            let recording = try store.finalizeRecording(id: pending.id, duration: duration)
            try store.updateTranscription(recordingID: recording.id, transcript: transcript, processingState: processingState, errorMessage: nil)
            return recording
        }
        let zeroDuration = try makeRecording(duration: 0, transcript: nil, processingState: .pending)
        let emptyTranscript = try makeRecording(duration: 5, transcript: "… !")
        let kept = try makeRecording(duration: 5, transcript: "Купил хлеб")
        let pendingTranscription = try makeRecording(duration: 7, transcript: nil, processingState: .pending)

        let service = RecordingService(recordingDirectory: directory, transcriber: StubTranscriber(), isApplicationActive: { false })

        XCTAssertFalse(service.recordings.contains(where: { $0.id == zeroDuration.id }))
        XCTAssertFalse(service.recordings.contains(where: { $0.id == emptyTranscript.id }))
        XCTAssertTrue(service.recordings.contains(where: { $0.id == kept.id }))
        XCTAssertTrue(service.recordings.contains(where: { $0.id == pendingTranscription.id }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: zeroDuration).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: emptyTranscript).path))
        let leftover = ReportQuery.events(in: service.recordings, period: .month, date: .now)
        XCTAssertEqual(Set(leftover.map(\.recording.id)), [kept.id])
    }

    @MainActor
    func testAudioStorageListsExistingAudioAndTotalsItsSize() throws {
        let directory = try makeAudioStorageDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let first = try makeAudioStorageRecording(store: store, at: .now, audioBytes: 7,
                                                  transcript: "Купил хлеб")
        let second = try makeAudioStorageRecording(store: store, at: .now.addingTimeInterval(-60), audioBytes: 11,
                                                   transcript: "Подготовил отчёт")

        let items = store.audioStorageItems()

        XCTAssertEqual(Set(items.map(\.id)), [first.id, second.id])
        XCTAssertEqual(items.reduce(Int64.zero) { $0 + $1.byteCount }, 18)
    }

    @MainActor
    func testDeletingAudioKeepsTranscriptAndEvents() throws {
        let directory = try makeAudioStorageDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let recording = try makeAudioStorageRecording(store: store, at: .now, audioBytes: 9,
                                                      transcript: "Купил хлеб")
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let removedBytes = try store.deleteAudio(recordingID: recording.id, at: deletedAt)
        let restoredStore = RecordingStore(directory: directory)
        let restored = try XCTUnwrap(restoredStore.recordings.first { $0.id == recording.id })

        XCTAssertEqual(removedBytes, 9)
        XCTAssertFalse(FileManager.default.fileExists(atPath: restoredStore.fileURL(for: restored).path))
        XCTAssertEqual(restored.audioDeletedAt, deletedAt)
        XCTAssertEqual(restored.transcript, "Купил хлеб")
        XCTAssertEqual(restored.events?.map(\.text), ["Купил хлеб"])
        XCTAssertTrue(restoredStore.audioStorageItems().isEmpty)
    }

    @MainActor
    func testRetentionDeletesOnlyEligibleOlderAudio() throws {
        let directory = try makeAudioStorageDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = try makeAudioStorageRecording(store: store, at: now.addingTimeInterval(-31 * 86_400),
                                                audioBytes: 5, transcript: "Подготовил отчёт")
        let recent = try makeAudioStorageRecording(store: store, at: now.addingTimeInterval(-3 * 86_400),
                                                   audioBytes: 13, transcript: "Купил хлеб")
        let processing = try makeAudioStorageRecording(store: store, at: now.addingTimeInterval(-40 * 86_400),
                                                       audioBytes: 17, transcript: nil)
        try store.updateTranscription(recordingID: processing.id, transcript: nil,
                                      processingState: .processing, errorMessage: nil)
        let cutoff = now.addingTimeInterval(-30 * 86_400)

        let deletedIDs = try store.deleteAudio(olderThan: cutoff, at: now)
        let recordsByID = Dictionary(uniqueKeysWithValues: store.recordings.map { ($0.id, $0) })

        XCTAssertEqual(deletedIDs, [old.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: old).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: recent).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: processing).path))
        XCTAssertEqual(recordsByID[old.id]?.transcript, "Подготовил отчёт")
        XCTAssertEqual(recordsByID[old.id]?.events?.count, 1)
        XCTAssertNil(recordsByID[recent.id]?.audioDeletedAt)
        XCTAssertNil(recordsByID[processing.id]?.audioDeletedAt)
    }

    @MainActor
    func testServiceRetentionIsOptInAndRefreshesPreservedRecording() throws {
        let directory = try makeAudioStorageDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = try makeAudioStorageRecording(store: store, at: now.addingTimeInterval(-31 * 86_400),
                                                audioBytes: 5, transcript: "Подготовил отчёт")
        let service = RecordingService(recordingDirectory: directory, transcriber: StubTranscriber(),
                                       isApplicationActive: { false })

        XCTAssertTrue(try service.applyAudioRetention(enabled: false, days: 30, now: now).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: old).path))

        let deletedIDs = try service.applyAudioRetention(enabled: true, days: 30, now: now)
        let refreshed = try XCTUnwrap(service.recordings.first { $0.id == old.id })

        XCTAssertEqual(deletedIDs, [old.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: old).path))
        XCTAssertEqual(refreshed.audioDeletedAt, now)
        XCTAssertEqual(refreshed.transcript, "Подготовил отчёт")
        XCTAssertEqual(refreshed.events?.count, 1)
    }

    @MainActor
    private func makeAudioStorageRecording(
        store: RecordingStore,
        at date: Date,
        audioBytes: Int,
        transcript: String?
    ) throws -> Recording {
        let pending = try store.beginRecording(startedAt: date)
        try Data(repeating: 1, count: audioBytes).write(to: store.fileURL(for: pending))
        let saved = try store.finalizeRecording(id: pending.id, duration: 1)
        try store.updateTranscription(recordingID: saved.id, transcript: transcript,
                                      processingState: transcript == nil ? .pending : .completed,
                                      errorMessage: nil)
        return try XCTUnwrap(store.recordings.first { $0.id == saved.id })
    }

    private func makeAudioStorageDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor StubTranscriber: Transcriber {
    nonisolated let canTranscribeWithoutAuthorizationPrompt = false
    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String { "" }
}
