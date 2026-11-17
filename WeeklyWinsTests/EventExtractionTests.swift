import XCTest
@testable import WeeklyWins

final class EventExtractionTests: XCTestCase {
    func testReviewDraftPreservesAnEmptyListAndItsBaseline() throws {
        let suite = "review-drafts-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let original = DiaryEvent(recordingID: id, sourceText: "Купил хлеб", text: "Купил хлеб")
        let draft = EventReviewDraft(baseline: [original], events: [])
        let store = EventReviewDraftStore(defaults: defaults)
        try store.save(draft, recordingID: id)
        XCTAssertEqual(store.load(recordingID: id), draft)
        var mergeDraft = draft
        mergeDraft.mergeProposal = original
        mergeDraft.mergingEventID = original.id
        try store.save(mergeDraft, recordingID: id)
        XCTAssertEqual(store.load(recordingID: id), mergeDraft)
        XCTAssertNil(store.load(recordingID: UUID()))
        store.remove(recordingID: id)
        XCTAssertNil(store.load(recordingID: id))
    }

    @MainActor
    func testStaleReviewCannotOverwriteNewerEventChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let recording = try store.beginRecording()
        let original = DiaryEvent(recordingID: recording.id, sourceText: "Текст", text: "Дело")
        try store.saveEvents(recordingID: recording.id, events: [original])
        let individualDrafts = EventDraftStore()
        defer { individualDrafts.remove(id: original.id) }
        try individualDrafts.save(original)
        var updated = original
        updated.category = .home
        try store.saveEvents(recordingID: recording.id, events: [updated])
        XCTAssertNil(individualDrafts.load(for: updated))
        XCTAssertThrowsError(try store.saveEvents(recordingID: recording.id, events: [], expectedEvents: [original]))
        XCTAssertEqual(store.recordings.first?.events, [updated])
        try store.saveEvents(recordingID: recording.id, events: [], expectedEvents: [updated])
        XCTAssertEqual(store.recordings.first?.events, [])
    }

    func testIndividualDraftOnlyRestoresAgainstItsOriginalBaseline() throws {
        let suite = "event-baseline-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = DiaryEvent(recordingID: UUID(), sourceText: "Текст", text: "Исходное дело")
        var edited = original
        edited.text = "Черновик"
        let store = EventDraftStore(defaults: defaults)
        try store.save(edited, baseline: original)
        XCTAssertEqual(store.load(for: original), edited)
        var newer = original
        newer.category = .home
        XCTAssertNil(store.load(for: newer))
    }

    func testEventDraftSurvivesReopeningAndCanBeDiscarded() throws {
        let suite = "event-drafts-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = DiaryEvent(recordingID: UUID(), sourceText: "Купил хлеб", text: "Купил хлеб")
        var edited = original
        edited.text = "Купил хлеб и молоко"
        try EventDraftStore(defaults: defaults).save(edited)
        let restoredStore = EventDraftStore(defaults: defaults)
        XCTAssertEqual(restoredStore.load(for: original)?.text, edited.text)
        restoredStore.remove(id: original.id)
        XCTAssertNil(restoredStore.load(for: original))
    }

    @MainActor
    func testAllSavePathsRejectEmptyEventTitle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let recording = try store.beginRecording()
        let event = DiaryEvent(recordingID: recording.id, sourceText: "Текст", text: "  \n  ")
        XCTAssertThrowsError(try store.saveEvents(recordingID: recording.id, events: [event]))
        XCTAssertNil(store.recordings.first?.events)
    }

    func testClockTimesAreNotDurationsAndNegativesAreNotCompleted() {
        for text in ["Позвонил в 2 часа", "Через два часа позвоню"] {
            XCTAssertNil(EventExtractor.extract(text, recordingID: UUID()).first?.duration)
        }
        for text in ["Не помыл посуду", "Не позвонил клиенту", "Не подготовил отчёт"] {
            XCTAssertEqual(EventExtractor.extract(text, recordingID: UUID()).first?.completion, .notCompleted)
        }
    }

    @MainActor
    func testCorrectingTranscriptRefreshesUntouchedSuggestionsAndPreservesEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let record = try store.beginRecording()
        try store.updateTranscription(recordingID: record.id, transcript: "Купил хлеб", processingState: .completed, errorMessage: nil)
        try store.updateTranscription(recordingID: record.id, transcript: "Купил молоко", processingState: .completed, errorMessage: nil)
        XCTAssertEqual(store.recordings.first?.events?.first?.text, "Купил молоко")
        var events = try XCTUnwrap(store.recordings.first?.events)
        events[0].category = .home
        try store.saveEvents(recordingID: record.id, events: events)
        try store.updateTranscription(recordingID: record.id, transcript: "Купил продукты", processingState: .completed, errorMessage: nil)
        XCTAssertEqual(store.recordings.first?.events?.first?.text, "Купил молоко")
        XCTAssertEqual(store.recordings.first?.events?.first?.category, .home)
    }

    func testSplitsMentionedTasksAndPreservesSource() {
        let id = UUID()
        let events = EventExtractor.extract("Подготовил отчёт. Купил продукты; помыл посуду.", recordingID: id)
        XCTAssertEqual(events.count, 3)
        XCTAssertTrue(events.allSatisfy { $0.recordingID == id })
        XCTAssertTrue(events.allSatisfy { !$0.sourceText.isEmpty })
        XCTAssertTrue(events.allSatisfy { $0.occurredAt == nil && $0.duration == nil })
    }

    func testNegationIsPreservedForReview() {
        let events = EventExtractor.extract("Не успел отправить письмо. Починил дверь.", recordingID: UUID())
        XCTAssertEqual(events.first?.text, "Не успел отправить письмо")
        XCTAssertEqual(events.first?.completion, .notCompleted)
        XCTAssertEqual(events.last?.completion, .completed)
    }

    func testSplitsSequenceAndReadsExplicitDuration() {
        let events = EventExtractor.extract("Работал над проектом два часа, потом купил продукты и помыл посуду.", recordingID: UUID())
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.first?.duration, 7200)
        XCTAssertNil(events.last?.duration)
    }

    @MainActor
    func testEventEditsPersistAcrossRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let recording = try store.beginRecording()
        var events = EventExtractor.extract("Подготовил отчёт. Купил продукты.", recordingID: recording.id)
        events[0].category = .work
        events[0].text = "Подготовил годовой отчёт"
        try store.saveEvents(recordingID: recording.id, events: events)
        let restored = RecordingStore(directory: directory)
        XCTAssertEqual(restored.recordings.first?.events?.first?.category, .work)
        XCTAssertEqual(restored.recordings.first?.events?.first?.text, "Подготовил годовой отчёт")
    }
}
