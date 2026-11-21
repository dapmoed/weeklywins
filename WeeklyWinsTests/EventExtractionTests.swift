import XCTest
@testable import WeeklyWins

final class EventExtractionTests: XCTestCase {
    func testNaturalUnpunctuatedDiarySpeechKeepsEachActivitySeparate() {
        // The fixture uses an authored script, with the formatting observed in Apple's transcript.
        let text = "вчера после работы я зашёл в магазин у дома и купил хлеб яйца и корм для кота молоко забыл поэтому сегодня утром вернулся за ним дома я приготовил ужин и убрал на кухне на это ушло около 20 минут посуду вечером не мыл оставил её до утра сегодня в 05:30 позвонил Анне и подтвердил встречу на четверг ещё нужно отправить документы и забрать посылку сначала проверю почту потом заеду домой на выходных хочу разобрать коробки в прихожей но ремонт пока начинать не буду"
        let expected: [(String, EventCompletion)] = [
            ("вчера после работы", .completed), ("купил хлеб", .completed),
            ("поэтому сегодня утром вернулся", .completed), ("дома я приготовил ужин", .completed),
            ("убрал на кухне", .completed), ("посуду вечером не мыл", .notCompleted),
            ("сегодня в", .completed), ("ещё нужно отправить документы", .notCompleted),
            ("забрать посылку", .notCompleted), ("сначала проверю почту", .notCompleted),
            ("заеду домой", .notCompleted), ("на выходных хочу разобрать коробки", .notCompleted),
            ("но ремонт пока начинать не буду", .notCompleted),
        ]
        for input in [text, text.replacingOccurrences(of: "05:30", with: "половине шестого")] {
            let id = UUID()
            let events = EventExtractor.extract(input, recordingID: id)
            XCTAssertEqual(events.count, expected.count)
            XCTAssertEqual(events.map(\.completion), expected.map { $0.1 })
            for (event, expected) in zip(events, expected) {
                XCTAssertTrue(event.text.hasPrefix(expected.0), event.text)
                XCTAssertTrue(input.contains(event.sourceText), event.sourceText)
                XCTAssertEqual(event.recordingID, id)
            }
        }
    }

    func testPendingListKeepsActionsWithinAnExplanationTogether() {
        let text = "Нужно проверить почему попросили забрать посылку и отправить документы"
        let events = EventExtractor.extract(text, recordingID: UUID())
        XCTAssertEqual(events.map(\.sourceText), [text])
        XCTAssertEqual(events.map(\.completion), [.notCompleted])
    }

    func testSubordinateDescriptionDoesNotChangeMainTaskStatus() {
        for text in ["Проверил как прошла встреча", "Проверил почему сервис не работал"] {
            let events = EventExtractor.extract(text, recordingID: UUID())
            XCTAssertEqual(events.map(\.text), [text])
            XCTAssertEqual(events.first?.completion, .completed)
        }
        for text in ["Чтобы не мешать коллегам, не позвонил клиенту", "Не проверил как прошла встреча"] {
            let events = EventExtractor.extract(text, recordingID: UUID())
            XCTAssertEqual(events.map(\.text), [text])
            XCTAssertEqual(events.first?.completion, .notCompleted)
        }
    }

    func testFiveMinuteAppleTranscriptKeepsNamedWorkAndHomeActivitiesSeparate() throws {
        let text = #"""
        Сегодня запишем событие рабочего и домашнего дня утром проверил календарь открыл рабочую почту и посмотрел сообщение команды ответил на короткие вопрос коллеги настройки сервиса на этот ответ ушло примерно 5 минут потом посмотрел список незавершенных задачей выбрал то которое мешало остальным участникам команды продолжать работу прошла встреча по микро service вайфая авторизации мы обсудили почему часть пользователей не могла подключиться к сети проверили описание ошибки сравнили настройки на двух устройствах решили что нужно ответить в информационную безопасности согласовать порядок смены паролей сама встреча длилась 01:00 отдельно записала это поручение потому что ответ ещё предстоит подготовить после встречи починил сервис по Wi-Fi авторизации была проблема с паролем сначала проверил журнал ошибок потом сравнил значение в настройках приложения в хранилище секретов нашел расхождение исправил настройку и повторил подключение проверил обычный вход повторный вход и поведение после перезапуска сервиса пользователи снова смогли подключаться на исправлении и проверку потратил 40 минут затем поменял пароли в сервисе ССНС поближе обновил настройки перезапустил рабочий процесс и отправил текстовое сообщение убедился что сообщение дошло до получателя сохранил короткую запись о выполненном изменении для коллег длительности этого дела точно не помню поэтому оставляю её Неизвестный после этого ответил на два небольших вопросов в рабочем чате перед обедом подготовил черновик ответа для информационной безопасности описал найденную причину и перечислил выполненные проверки само письмо ещё не отправлял потому что жду подтверждения коллеги затем проверила исправление в соседнем сервисе и написал результат в задаче это проверка заняла 20 минут после обеда обсудил с коллегой дальнейшую работу над проектом разговор длился примерно полчаса во второй половине дня разобрал несколько мелких задач нашел нужный документ уточнил название параметры и помог коллеге воспроизвести ошибку ещё обновила описание запуска в рабочие инструкции в конце рабочего дня проверил что новые ошибки не появились посмотрел результаты Тестов и записал какие вопросы остаются на завтра большая задача завершена а не небольшую согласование пока остается открытым по дороге домой зашёл в магазин купил хлеб молоко яблоки продукты на ужин проверил список покупок чтобы ничего не забыть в магазине провёл около 20 минут до дома разобрал сумку убрал продукты в холодильник и поставил чайник потом помыл посуду протёр стол и вынес мусор эти небольшие дела вместе заняли примерно 15 минут вечером приготовил ужин пока готовилась еда разобрал несколько домашних бумаг и нашел квитанцию которую искал на прошлой неделе проверил показания счётчиков и записал их в заметку оплачивать квитанцию сегодня не стал потому что сначала нужно уточнить сумму после уже на немного погулял прогулка заняла 40 минут вернувшись домой подготовил вещи на завтра теперь подведу итог дня самыми крупными рабочими делами были встреча исправления авторизацией смена паролей кроме них было несколько коротких ответов проверок и уточнений дома успел купить продукты навести порядок и приготовить еду время выполнения некоторых дел известно точно а для других я его не называл такие длительности нужно сохранить неизвестными в конце оставляю контрольную фразу в ежедневнике сохранены последнюю заметки
        """#
        let events = EventExtractor.extract(text, recordingID: UUID())
        let expectations: [(start: String, contains: String, completion: EventCompletion)] = [
            ("прошла встреча", "по микро service", .completed),
            ("решили что нужно ответить", "смены паролей", .notCompleted),
            ("после встречи починил сервис", "по Wi-Fi", .completed),
            ("перед обедом подготовил черновик", "выполненные проверки", .completed),
            ("само письмо ещё не отправлял", "подтверждения коллеги", .notCompleted),
            ("проверила исправление", "соседнем сервисе", .completed),
            ("после обеда обсудил", "дальнейшую работу", .completed),
            ("по дороге домой зашёл", "купил хлеб", .completed),
            ("до дома разобрал", "в холодильник", .completed),
            ("вечером приготовил ужин", "ужин", .completed),
            ("оплачивать квитанцию", "не стал", .notCompleted),
            ("погулял", "прогулка заняла 40 минут", .completed),
            ("вернувшись домой", "вещи на завтра", .completed),
        ]
        let matched = expectations.compactMap { expected -> DiaryEvent? in
            let event = events.first { $0.text.lowercased().hasPrefix(expected.start) }
            XCTAssertNotNil(event, expected.start)
            if let event {
                XCTAssertTrue(event.text.contains(expected.contains), expected.start)
                XCTAssertEqual(event.completion, expected.completion, expected.start)
            }
            return event
        }
        XCTAssertEqual(matched.count, expectations.count)
        XCTAssertEqual(Set(matched.map(\.id)).count, matched.count)
    }

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
        for prefix in ["на обед сходил в магазин", "дома помыл посуду"] {
            XCTAssertTrue(events.contains { $0.text.hasPrefix(prefix) }, prefix)
        }
        XCTAssertTrue(events.allSatisfy { $0.recordingID == recording.id })
        let entries = ReportQuery.events(in: restored.recordings, period: .day, date: recording.recordedAt)
        XCTAssertEqual(entries.count, 6)
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
        XCTAssertTrue(try XCTUnwrap(events.first).sourceText.contains("встреча длилась 01:00"))
        XCTAssertTrue(events.contains { $0.text.hasPrefix("после встречи починил") })
        XCTAssertTrue(events.contains { $0.text.hasPrefix("поменяла пароль") })
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
        XCTAssertTrue(meeting.sourceText.contains("Часовая встреча"))
        let followUp = try XCTUnwrap(events.last)
        XCTAssertEqual(followUp.text, "Решили что нужно ответить в инфосеке")
        XCTAssertEqual(followUp.completion, .notCompleted)
    }

    func testDurationMentionMergesIntoMentionedEventWithoutValue() {
        let events = EventExtractor.extract("Прошла встреча по проекту. Двухчасовая встреча", recordingID: UUID())
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events.first?.sourceText.contains("Двухчасовая встреча") == true)
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
        }
    }

    func testClarificationTargetsMatchingMeetingAndPreservesOtherTask() {
        let text = "Прошла встреча по проекту. Починил сервис. Часовая встреча"
        let events = EventExtractor.extract(text, recordingID: UUID())
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.first?.sourceText.contains("Часовая встреча") == true)
        XCTAssertEqual(events.last?.text, "Починил сервис")
    }

    func testConflictingOrRepeatedDurationClarificationKeepsOneEvent() {
        for text in ["Встреча длилась час. Часовая встреча", "Встреча длилась два часа. Часовая встреча"] {
            let events = EventExtractor.extract(text, recordingID: UUID())
            XCTAssertEqual(events.count, 1, text)
            XCTAssertTrue(events.first?.sourceText.contains("Часовая встреча") == true, text)
        }
    }

    func testIncidentalFollowUpMentionDoesNotReceiveMeetingDuration() {
        let events = EventExtractor.extract(
            "Прошла встреча. Нужно отправить протокол встречи. Часовая встреча",
            recordingID: UUID()
        )
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.first?.sourceText.contains("Часовая встреча") == true)
        XCTAssertEqual(events.last?.completion, .notCompleted)
    }

    func testRepeatedClarificationKeepsOneEvent() {
        let events = EventExtractor.extract(
            "Встреча длилась два часа. Часовая встреча. Часовая встреча",
            recordingID: UUID()
        )
        XCTAssertEqual(events.count, 1)
    }

    func testStandaloneDurationDescriptionCreatesAnEvent() {
        for text in ["Часовая встреча", "Получасовой созвон", "Двухчасовое обсуждение"] {
            let events = EventExtractor.extract(text, recordingID: UUID())
            XCTAssertEqual(events.count, 1, text)
        }
    }

    @MainActor
    func testUserNotesPersistAndReportCompletedMeeting() throws {
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

    func testReviewDraftUndoKeepsOriginalOrderAfterReopening() throws {
        let suite = "review-drafts-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recordingID = UUID()
        let original = (1...23).map { index in
            DiaryEvent(recordingID: recordingID, sourceText: "Дело \(index)", text: "Дело \(index)")
        }
        var draft = EventReviewDraft(baseline: original, events: original)
        draft.deleteEvent(id: original[1].id)
        draft.deleteEvent(id: original[2].id)
        var merged = original[0]
        merged.text += ". " + original[3].text
        XCTAssertTrue(draft.confirmMerge(merged, mergingEventID: original[3].id))
        let added = DiaryEvent(recordingID: recordingID, sourceText: "Новое дело", text: "Новое дело")
        draft.addEvent(added)

        let store = EventReviewDraftStore(defaults: defaults)
        try store.save(draft, recordingID: recordingID)
        var restored = try XCTUnwrap(store.load(recordingID: recordingID))
        XCTAssertEqual(restored.undoDeletion(), original[2].id)
        XCTAssertEqual(restored.undoDeletion(), original[1].id)
        XCTAssertFalse(restored.hasDeletedEvents)
        XCTAssertEqual(restored.events, [merged, original[1], original[2]] + Array(original.dropFirst(4)) + [added])
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

    func testClockStyleReferencesStayInOneEvent() {
        for text in ["Работал 1.5 часа", "Работал 1,5 часа", "Позвонил в 10.30", "Позвонил в 2 часа"] {
            let events = EventExtractor.extract(text, recordingID: UUID())
            XCTAssertEqual(events.count, 1, text)
            XCTAssertEqual(events.first?.text, text, text)
        }
    }

    func testRelativeAndClockReferencesStayInOneEvent() {
        for text in [
            "Два часа назад отправил письмо", "Полчаса назад купил хлеб",
            "Позвонил час спустя", "Встреча с 10 часов до 12 часов",
            "Через два часа позвоню", "Позвонил в час дня",
            "Через два часа 15 минут позвоню", "Позвонил в два часа пятнадцать минут",
            "С 10 до 12 часов работал 30 минут", "Работал два часа тридцать пять минут",
            "Работал примерно два часа"
        ] {
            let events = EventExtractor.extract(text, recordingID: UUID())
            XCTAssertEqual(events.count, 1, text)
            XCTAssertEqual(events.first?.text, text, text)
        }
    }

    func testNegatedActionsAreNotCompleted() {
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
    }

    func testNegationIsPreservedForReview() {
        let events = EventExtractor.extract("Не успел отправить письмо. Починил дверь.", recordingID: UUID())
        XCTAssertEqual(events.first?.text, "Не успел отправить письмо")
        XCTAssertEqual(events.first?.completion, .notCompleted)
        XCTAssertEqual(events.last?.completion, .completed)
    }

    func testContrastKeepsCompletedAndUnfinishedActionsSeparate() {
        for (text, second) in [
            ("Не отправил отчёт, но подготовил инструкцию", "подготовил инструкцию"),
            ("Не отправил отчёт но подготовил инструкцию", "подготовил инструкцию"),
            ("Не отправил отчёт, но я подготовил инструкцию", "я подготовил инструкцию")
        ] {
            let events = EventExtractor.extract(text, recordingID: UUID())
            XCTAssertEqual(events.map(\.sourceText), ["Не отправил отчёт", second])
            XCTAssertEqual(events.map(\.completion), [.notCompleted, .completed])
        }
        let explanation = "Проверил почему коллега не отправил отчёт, но подготовил инструкцию"
        XCTAssertEqual(EventExtractor.extract(explanation, recordingID: UUID()).map(\.sourceText), [explanation])
    }

    func testRelativeDayTransitionPreservesBothDescriptionsWithoutInventingTimes() {
        let note = "Я вчера починил авторизацию я сегодня поменял пароль сегодня проверил доступ"
        let events = EventExtractor.extract(note, recordingID: UUID())
        XCTAssertEqual(events.map(\.sourceText), ["Я вчера починил авторизацию", "я сегодня поменял пароль", "сегодня проверил доступ"])

        let explanation = "Вчера проверил почему коллега сегодня подготовил отчёт"
        XCTAssertEqual(EventExtractor.extract(explanation, recordingID: UUID()).map(\.sourceText), [explanation])
    }

    func testSplitsSequenceAndKeepsDurationWording() {
        let events = EventExtractor.extract("Работал над проектом два часа, потом купил продукты и помыл посуду.", recordingID: UUID())
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.first?.text, "Работал над проектом два часа")
        XCTAssertEqual(events.last?.text, "помыл посуду")
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
