import XCTest
@testable import WeeklyWins

final class ReportTests: XCTestCase {
    @MainActor
    func testEventEditsAndDeletionReachAllReportPeriodsAfterReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z"))
        var calendar = ReportQuery.calendar
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 5 * 3600))

        func addEvent(_ sourceText: String, at recordingDate: Date,
                      category: EventCategory = .unclassified) throws -> DiaryEvent {
            let recording = try store.beginRecording(startedAt: recordingDate)
            try Data([1, 2, 3]).write(to: store.fileURL(for: recording))
            try store.finalizeRecording(id: recording.id, duration: 1)
            let event = DiaryEvent(recordingID: recording.id, sourceText: sourceText, text: sourceText, category: category)
            try store.saveEvents(recordingID: recording.id, events: [event])
            return event
        }
        let newer = try addEvent("Отчёт", at: date, category: .work)
        let older = try addEvent("Покупки", at: date.addingTimeInterval(-3600), category: .home)
        let sameWeek = try addEvent("Созвон", at: date.addingTimeInterval(-2 * 86400))
        let sameMonth = try addEvent("Ремонт", at: date.addingTimeInterval(-6 * 86400), category: .work)

        let periods: [(ReportPeriod, [DiaryEvent])] = [
            (.day, [newer, older]), (.week, [newer, older, sameWeek]), (.month, [newer, older, sameWeek, sameMonth])
        ]
        for (period, expected) in periods {
            let report = ReportQuery.events(in: store.recordings, period: period, date: date, calendar: calendar)
            XCTAssertEqual(report.map(\.id), expected.map(\.id), period.rawValue)
        }

        var edited = newer
        edited.category = .home
        try store.saveEvents(recordingID: newer.recordingID, events: [edited], expectedEvents: [newer])
        try store.saveEvents(recordingID: older.recordingID, events: [], expectedEvents: [older])
        let restored = RecordingStore(directory: directory)
        let editedPeriods: [(ReportPeriod, [DiaryEvent])] = [
            (.day, [newer]), (.week, [newer, sameWeek]), (.month, [newer, sameWeek, sameMonth])
        ]
        for (period, expected) in editedPeriods {
            let report = ReportQuery.events(in: restored.recordings, period: period, date: date, calendar: calendar)
            XCTAssertEqual(report.map(\.id), expected.map(\.id), period.rawValue)
        }
        XCTAssertEqual(restored.recordings.first(where: { $0.id == newer.recordingID })?.events?.first?.category, .home)
    }

    func testSelectedCalendarDateStaysInSameMonthAfterZoneChange() throws {
        var previous = Calendar(identifier: .gregorian)
        previous.timeZone = TimeZone(secondsFromGMT: 5 * 3600)!
        var current = previous
        current.timeZone = TimeZone(secondsFromGMT: 0)!
        let selected = try XCTUnwrap(previous.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        let rebased = try XCTUnwrap(ReportQuery.preservingCalendarDate(selected, from: previous, to: current))
        XCTAssertEqual(current.component(.month, from: rebased), 11)
        XCTAssertEqual(current.component(.day, from: rebased), 1)
    }

    func testWeekTitleAndDaysRespectSelectedPeriod() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let date = ISO8601DateFormatter().date(from: "2026-11-17T12:00:00Z")!
        XCTAssertEqual(ReportQuery.periodTitle(period: .week, date: date, calendar: calendar), "16–22 ноября")
        XCTAssertEqual(ReportQuery.periodTitle(period: .month, date: date, calendar: calendar), "Ноябрь 2026")
    }

    func testMonthNavigationStartsAtPeriodBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = ISO8601DateFormatter().date(from: "2026-01-31T12:00:00Z")!
        let february = try XCTUnwrap(ReportQuery.shiftedDate(january, period: .month, offset: 1, calendar: calendar))
        XCTAssertEqual(calendar.component(.month, from: february), 2)
        XCTAssertEqual(calendar.component(.day, from: february), 1)
        XCTAssertEqual(ReportQuery.days(period: .month, date: february, calendar: calendar).count, 28)
    }

    func testReportWeekIsMondayThroughSunday() throws {
        let calendar = ReportQuery.calendar
        let date = ISO8601DateFormatter().date(from: "2026-11-17T12:00:00Z")!
        let days = ReportQuery.days(period: .week, date: date, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(days.first)), 2)
        XCTAssertEqual(calendar.component(.weekday, from: try XCTUnwrap(days.last)), 1)
    }

    func testDayGroupingTracksTimeZoneChange() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var yekaterinburg = utc
        yekaterinburg.timeZone = TimeZone(secondsFromGMT: 5 * 3600)!
        let eventDate = ISO8601DateFormatter().date(from: "2026-11-16T22:00:00Z")!
        let requestedDate = ISO8601DateFormatter().date(from: "2026-11-17T12:00:00Z")!
        let id = UUID()
        var recording = Recording(id: id, recordedAt: eventDate, fileName: "fixture.m4a", state: .saved)
        recording.events = [DiaryEvent(recordingID: id, sourceText: "Дело", text: "Дело")]
        XCTAssertEqual(ReportQuery.events(in: [recording], period: .day, date: requestedDate, calendar: utc).count, 0)
        XCTAssertEqual(ReportQuery.events(in: [recording], period: .day, date: requestedDate, calendar: yekaterinburg).count, 1)
    }

    func testLocalDayUsesRecordingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 5 * 3600)!
        let date = ISO8601DateFormatter().date(from: "2026-11-16T20:00:00Z")!
        let id = UUID()
        var recording = Recording(id: id, recordedAt: date, fileName: "fixture.m4a", state: .saved)
        recording.events = [
            DiaryEvent(recordingID: id, sourceText: "Работал час", text: "Работал", category: .work),
            DiaryEvent(recordingID: id, sourceText: "Купил продукты", text: "Продукты", category: .home),
            DiaryEvent(recordingID: id, sourceText: "Не сделал", text: "Не сделал", completion: .notCompleted)
        ]
        let report = ReportQuery.events(in: [recording], period: .day, date: date, calendar: calendar)
        XCTAssertEqual(report.count, 3)
        XCTAssertEqual(ReportQuery.events(in: [recording], period: .week, date: date, calendar: calendar).count, 3)
    }

    func testEventsInCustomRangeIncludeEndDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 5 * 3600)!
        calendar.firstWeekday = 2
        func recording(_ text: String, at iso: String) -> Recording {
            var recording = Recording(id: UUID(), recordedAt: ISO8601DateFormatter().date(from: iso)!,
                                      fileName: "fixture.m4a", state: .saved)
            recording.events = [DiaryEvent(recordingID: recording.id, sourceText: text, text: text)]
            return recording
        }
        let recordings = [
            recording("Пн", at: "2026-11-16T07:00:00Z"),
            recording("Вт", at: "2026-11-17T07:00:00Z"),
            recording("Пн2", at: "2026-11-23T07:00:00Z")
        ]
        let start = calendar.startOfDay(for: ISO8601DateFormatter().date(from: "2026-11-16T00:00:00Z")!)
        let endExclusive = calendar.date(byAdding: .day, value: 1,
                                         to: calendar.startOfDay(for: ISO8601DateFormatter().date(from: "2026-11-17T00:00:00Z")!))!
        let report = ReportQuery.events(in: recordings, from: start, to: endExclusive, calendar: calendar)
        XCTAssertEqual(report.map { $0.event.text }, ["Вт", "Пн"])
    }

    func testShareTextGroupsByDayForWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 5 * 3600)!
        calendar.firstWeekday = 2
        func recording(at iso: String, events: [(String, String, EventCategory?, EventCompletion?)]) -> Recording {
            let id = UUID()
            var recording = Recording(id: id, recordedAt: ISO8601DateFormatter().date(from: iso)!,
                                      fileName: "fixture.m4a", state: .saved)
            recording.events = events.map { sourceText, text, category, completion in
                DiaryEvent(recordingID: id, sourceText: sourceText, text: text,
                           category: category ?? .unclassified,
                           completion: completion ?? .completed)
            }
            return recording
        }
        let first = recording(at: "2026-11-16T05:00:00Z",
                              events: [("Созвон", "Созвон", .work, nil)])
        let second = recording(at: "2026-11-17T05:00:00Z",
                               events: [("Продукты", "Продукты", .home, nil),
                                        ("Отчёт", "Отчёт", .work, .notCompleted)])
        let entries = ReportQuery.events(in: [first, second], period: .week,
                                         date: ISO8601DateFormatter().date(from: "2026-11-17T12:00:00Z")!,
                                         calendar: calendar)
        let text = ReportQuery.shareText(entries: entries, title: "Неделя 16–22 ноября",
                                         grouping: .day, calendar: calendar)
        XCTAssertEqual(text, """
            Неделя 16–22 ноября

            Дел: 3 · выполнено: 2

            16 ноября, Понедельник
            • Созвон

            17 ноября, Вторник
            • Продукты
            • Отчёт — не сделано
            """)
    }

    func testShareTextGroupsByWeekForMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 5 * 3600)!
        calendar.firstWeekday = 2
        func recording(_ text: String, at iso: String) -> Recording {
            var recording = Recording(id: UUID(), recordedAt: ISO8601DateFormatter().date(from: iso)!,
                                      fileName: "fixture.m4a", state: .saved)
            recording.events = [DiaryEvent(recordingID: recording.id, sourceText: text, text: text)]
            return recording
        }
        let recordings = [
            recording("Пн", at: "2026-11-16T05:00:00Z"),
            recording("Пн2", at: "2026-11-23T05:00:00Z")
        ]
        let entries = ReportQuery.events(in: recordings, period: .month,
                                         date: ISO8601DateFormatter().date(from: "2026-11-17T12:00:00Z")!,
                                         calendar: calendar)
        let text = ReportQuery.shareText(entries: entries, title: "Дела за Ноябрь 2026",
                                         grouping: .week, calendar: calendar)
        XCTAssertEqual(text, """
            Дела за Ноябрь 2026

            Дел: 2 · выполнено: 2

            16–22 ноября
            • Пн

            23–29 ноября
            • Пн2
            """)
    }
}
