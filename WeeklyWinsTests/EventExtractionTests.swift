import XCTest
@testable import WeeklyWins

final class EventExtractionTests: XCTestCase {
    @MainActor
    func testCompleteMinuteAppleTranscriptPersistsSeparateWorkAndHouseholdTasks() throws {
        // Full output from final-ru-one-minute.native-report.json, including ASR errors.
        let text = "Сегодня запишу несколько рабочих и домашних дел прошла встреча по микро сервису вайфая авторизации обсудили проблему с доступом и решили что нужно ответить в информационную безопасность встреча длилась 01:00 после встречи починил сервис по вайфая авторизации была проблема с паролем теперь подключение проходит успешно затем поменяла пароль в сервисе SNS паблишер проверил что сообщения отправляются на обед сходил в магазин купил хлеб молоко и яблоки дома помыл посуду его не мусор на это ушло 15 минут в конце оставляю контрольную фразу в ежедневнике сохранены последние заметки"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let recording = try store.beginRecording()
        try Data([1, 2, 3]).write(to: store.fileURL(for: recording))
        try store.finalizeRecording(id: recording.id, duration: 60)
        try store.updateTranscription(recordingID: recording.id, transcript: text, processingState: .completed, errorMessage: nil)

        let restored = RecordingStore(directory: directory)
        let stored = try XCTUnwrap(restored.recordings.first)
        XCTAssertEqual(stored.transcript, text)
        let events = try XCTUnwrap(stored.events)
        XCTAssertEqual(events.map(\.completion), [.completed, .notCompleted, .completed, .completed, .completed, .completed])
        XCTAssertEqual(events.map(\.duration), [3600, nil, nil, nil, nil, 900])
        for prefix in ["на обед сходил в магазин", "дома помыл посуду"] {
            XCTAssertTrue(events.contains { $0.text.hasPrefix(prefix) }, prefix)
        }
        XCTAssertTrue(events.allSatisfy { $0.recordingID == recording.id && $0.occurredAt == nil })
        let entries = ReportQuery.events(in: restored.recordings, period: .day, date: recording.recordedAt)
        XCTAssertEqual(entries.count, 6)
        XCTAssertEqual(ReportQuery.knownDuration(entries), 4500)
    }

    func testHouseholdTransitionKeepsLeadingTimeAndNegation() {
        let text = "Вчера дома не помыл посуду"
        let events = EventExtractor.extract(text, recordingID: UUID())
        XCTAssertEqual(events.map(\.text), [text])
        XCTAssertEqual(events.first?.completion, .notCompleted)
    }

    func testNegationAfterSubjectStillMarksTheTaskPending() {
        for text in ["Встреча не состоялась", "Работа не завершилась", "Задача не выполнена", "Письмо не отправлено"] {
            XCTAssertEqual(EventExtractor.extract(text, recordingID: UUID()).first?.completion, .notCompleted, text)
        }
    }

    func testUnpunctuatedAppleTranscriptSeparatesMeetingFollowUpAndRepairs() throws {
        // Contiguous excerpt from the controlled one-minute Apple Speech report.
        let text = "прошла встреча по микро сервису вайфая авторизации обсудили проблему с доступом и решили что нужно ответить в информационную безопасность встреча длилась 01:00 после встречи починил сервис по вайфая авторизации была проблема с паролем теперь подключение проходит успешно затем поменяла пароль в сервисе SNS паблишер"
        let events = EventExtractor.extract(text, recordingID: UUID())

        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.map(\.completion), [.completed, .notCompleted, .completed, .completed])
        XCTAssertEqual(events.map(\.duration), [3600, nil, nil, nil])
        XCTAssertTrue(try XCTUnwrap(events.first).sourceText.contains("встреча длилась 01:00"))
        XCTAssertTrue(events.contains { $0.text.hasPrefix("после встречи починил") })
        XCTAssertTrue(events.contains { $0.text.hasPrefix("поменяла пароль") })
    }

    func testClockStyleDurationRequiresAnExplicitDurationVerb() {
        XCTAssertEqual(EventExtractor.extract("Встреча длилась 01:25", recordingID: UUID()).first?.duration, 5100)
        XCTAssertNil(EventExtractor.extract("Встреча началась в 01:25", recordingID: UUID()).first?.duration)
        XCTAssertNil(EventExtractor.extract("Встреча длилась около 01:25", recordingID: UUID()).first?.duration)
        XCTAssertNil(EventExtractor.extract("Встреча длилась 01:25–02:00", recordingID: UUID()).first?.duration)
        XCTAssertNil(EventExtractor.extract("Встреча длилась 01:75", recordingID: UUID()).first?.duration)
        for prefix in ["Сегодня", "Сама"] {
            let events = EventExtractor.extract("\(prefix) встреча длилась 01:25", recordingID: UUID())
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events.first?.duration, 5100)
        }
    }

    func testDecisionKeepsItsSubjectAndNegationTogether() {
        for text in ["Я решил что нужно отправить письмо", "Я не решил что нужно отправить"] {
            let events = EventExtractor.extract(text, recordingID: UUID())
            XCTAssertEqual(events.map(\.text), [text])
            XCTAssertEqual(events.first?.completion, .notCompleted)
        }
    }

    func testAfterMeetingPhraseKeepsItsLeadingModifier() {
        let text = "Сразу после встречи подготовил письмо"
        XCTAssertEqual(EventExtractor.extract(text, recordingID: UUID()).map(\.text), [text])
    }

    func testUserMeetingLinksDurationClarificationAndRetainsPendingFollowUp() throws {
        let transcript = "Прошла встреча по микросервису вай Фай  аторизация. Решили что нужно ответить в инфосеке. Часовая встреча"
        let events = EventExtractor.extract(transcript, recordingID: UUID())
        XCTAssertEqual(events.count, 2)
        let meeting = try XCTUnwrap(events.first)
        XCTAssertEqual(meeting.text, "Прошла встреча по микросервису вай Фай  аторизация")
        XCTAssertEqual(meeting.completion, .completed)
        XCTAssertEqual(meeting.duration, 3600)
        XCTAssertTrue(meeting.sourceText.contains("Часовая встреча"))
        let followUp = try XCTUnwrap(events.last)
        XCTAssertEqual(followUp.text, "Решили что нужно ответить в инфосеке")
        XCTAssertEqual(followUp.completion, .notCompleted)
        XCTAssertNil(followUp.duration)
    }

    func testUserServiceNotesKeepUnknownDurationAndOriginalWording() throws {
        for text in [
            "Починил сервис по вай фай авторизации была проблема с паролем",
            "Поменя пароли в сервисе снс паблишер"
        ] {
            let events = EventExtractor.extract(text, recordingID: UUID())
            XCTAssertEqual(events.count, 1)
            let event = try XCTUnwrap(events.first)
            XCTAssertEqual(event.text, text)
            XCTAssertEqual(event.sourceText, text)
            XCTAssertEqual(event.completion, .completed)
            XCTAssertNil(event.duration)
            XCTAssertNil(event.occurredAt)
        }
    }

    func testClarificationTargetsMatchingMeetingAndPreservesOtherTask() {
        let text = "Прошла встреча по проекту. Починил сервис. Часовая встреча"
        let events = EventExtractor.extract(text, recordingID: UUID())
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.duration, 3600)
        XCTAssertEqual(events.last?.text, "Починил сервис")
        XCTAssertNil(events.last?.duration)
    }

    func testKnownOrConflictingDurationClarificationKeepsOneEvent() {
        let same = EventExtractor.extract("Встреча длилась час. Часовая встреча", recordingID: UUID())
        XCTAssertEqual(same.count, 1)
        XCTAssertEqual(same.first?.duration, 3600)
        let conflicting = EventExtractor.extract("Встреча длилась два часа. Часовая встреча", recordingID: UUID())
        XCTAssertEqual(conflicting.count, 1)
        XCTAssertNil(conflicting.first?.duration)
        XCTAssertTrue(conflicting.first?.sourceText.contains("два часа. Часовая встреча") == true)
    }

    func testIncidentalFollowUpMentionDoesNotReceiveMeetingDuration() {
        let events = EventExtractor.extract(
            "Прошла встреча. Нужно отправить протокол встречи. Часовая встреча",
            recordingID: UUID()
        )
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.duration, 3600)
        XCTAssertEqual(events.last?.completion, .notCompleted)
        XCTAssertNil(events.last?.duration)
    }

    func testRepeatedClarificationKeepsDurationConflictUnknown() {
        let events = EventExtractor.extract(
            "Встреча длилась два часа. Часовая встреча. Часовая встреча",
            recordingID: UUID()
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events.first?.duration)
    }

    func testStandaloneDurationDescriptionCreatesAnEvent() {
        for (text, duration) in [("Часовая встреча", 3600.0), ("Получасовой созвон", 1800.0), ("Двухчасовое обсуждение", 7200.0)] {
            let events = EventExtractor.extract(text, recordingID: UUID())
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events.first?.duration, duration)
        }
    }

    func testPluralMeetingDescriptionKeepsTotalDurationUnknown() {
        let events = EventExtractor.extract("Встречи проходили весь день. Часовые встречи", recordingID: UUID())
        XCTAssertTrue(events.allSatisfy { $0.duration == nil })
    }

    @MainActor
    func testUserNotesPersistAndReportOneCompletedMeetingHour() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        for text in [
            "Прошла встреча по микросервису вай Фай  аторизация. Решили что нужно ответить в инфосеке. Часовая встреча",
            "Починил сервис по вай фай авторизации была проблема с паролем",
            "Поменя пароли в сервисе снс паблишер"
        ] {
            let recording = try store.beginRecording()
            try Data([1, 2, 3]).write(to: store.fileURL(for: recording))
            try store.finalizeRecording(id: recording.id, duration: 1)
            try store.updateTranscription(recordingID: recording.id, transcript: text, processingState: .completed, errorMessage: nil)
        }
        let restored = RecordingStore(directory: directory)
        let entries = ReportQuery.events(in: restored.recordings, period: .day, date: .now)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries.filter { $0.event.completion == .completed }.count, 3)
        XCTAssertEqual(ReportQuery.knownDuration(entries), 3600)
        XCTAssertTrue(entries.allSatisfy { $0.event.occurredAt == nil })
    }

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

    func testDecimalDurationsAndClockTimesStayInOneEvent() throws {
        for text in ["Работал 1.5 часа.", "Работал 1,5 часа."] {
            let events = EventExtractor.extract(text, recordingID: UUID())
            XCTAssertEqual(events.count, 1, text)
            XCTAssertEqual(events.first?.duration, 5400, text)
        }
        let clock = EventExtractor.extract("Позвонил в 10.30.", recordingID: UUID())
        XCTAssertEqual(clock.count, 1)
        XCTAssertNil(clock.first?.duration)
    }

    func testCompoundAndWordDurationsAreSummedWithinOnePhrase() {
        let cases: [(String, TimeInterval)] = [
            ("Работал два часа тридцать пять минут", 9300),
            ("Работал 2 часа 15 минут", 8100),
            ("Готовил час и 30 минут", 5400),
            ("Убирался полтора часа", 5400),
            ("Проверял отчёт пятнадцать минут", 900),
            ("Готовил полчаса", 1800),
            ("Работал сто двадцать пять минут", 7500),
            ("Работал тридцать\tпять минут", 2100)
        ]
        for (text, duration) in cases {
            XCTAssertEqual(EventExtractor.extract(text, recordingID: UUID()).first?.duration, duration, text)
        }
    }

    func testRelativeAndClockReferencesDoNotBecomeDurations() {
        for text in [
            "Два часа назад отправил письмо", "Полчаса назад купил хлеб",
            "Позвонил час спустя", "Встреча с 10 часов до 12 часов",
            "Через два часа позвоню", "Позвонил в час дня",
            "Через два часа 15 минут позвоню", "Позвонил в два часа пятнадцать минут"
        ] {
            XCTAssertNil(EventExtractor.extract(text, recordingID: UUID()).first?.duration, text)
        }
        XCTAssertEqual(EventExtractor.extract("С 10 до 12 часов работал 30 минут", recordingID: UUID()).first?.duration, 1800)
    }

    func testAmbiguousOrUnsupportedQuantitiesStayUnknown() {
        for text in [
            "Работал двадцать-тридцать минут", "Работал 20–30 минут",
            "Работал тысячу двести минут", "Работал час-полтора",
            "Работал два или три часа", "Работал примерно два часа"
        ] {
            XCTAssertNil(EventExtractor.extract(text, recordingID: UUID()).first?.duration, text)
        }
        for text in ["Работал — два часа", "Работал два часа — проверял документы"] {
            XCTAssertEqual(EventExtractor.extract(text, recordingID: UUID()).first?.duration, 7200, text)
        }
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
