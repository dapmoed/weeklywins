import XCTest
@testable import WeeklyWins

final class EventExtractionTests: XCTestCase {
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
