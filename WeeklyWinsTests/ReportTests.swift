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
        let recording = try store.beginRecording(startedAt: date)
        try Data([1, 2, 3]).write(to: store.fileURL(for: recording))
        try store.finalizeRecording(id: recording.id, duration: 1)

        let newer = DiaryEvent(recordingID: recording.id, sourceText: "Отчёт", text: "Отчёт",
                               category: .work, occurredAt: date, duration: 3600)
        let older = DiaryEvent(recordingID: recording.id, sourceText: "Покупки", text: "Покупки",
                               category: .home, occurredAt: date.addingTimeInterval(-3600), duration: 900)
        let sameWeek = DiaryEvent(recordingID: recording.id, sourceText: "Созвон", text: "Созвон",
                                  occurredAt: date.addingTimeInterval(-2 * 86400), duration: 600)
        let sameMonth = DiaryEvent(recordingID: recording.id, sourceText: "Ремонт", text: "Ремонт",
                                   occurredAt: date.addingTimeInterval(-6 * 86400), duration: 300)
        let baseline = [older, sameMonth, newer, sameWeek]
        try store.saveEvents(recordingID: recording.id, events: baseline)

        var edited = newer
        edited.category = .home
        edited.duration = 1800
        let periods: [(ReportPeriod, [DiaryEvent], TimeInterval)] = [
            (.day, [], 0), (.week, [sameWeek], 600), (.month, [sameWeek, sameMonth], 900)
        ]
        for (period, earlierEvents, extraDuration) in periods {
            let report = ReportQuery.events(in: store.recordings, period: period, date: date, calendar: calendar)
            XCTAssertEqual(report.map(\.id), [newer.id, older.id] + earlierEvents.map(\.id), period.rawValue)
            XCTAssertEqual(ReportQuery.knownDuration(report), 4500 + extraDuration, period.rawValue)
        }

        try store.saveEvents(recordingID: recording.id, events: [edited, sameWeek, sameMonth], expectedEvents: baseline)
        let restored = RecordingStore(directory: directory)
        for (period, earlierEvents, extraDuration) in periods {
            let report = ReportQuery.events(in: restored.recordings, period: period, date: date, calendar: calendar)
            XCTAssertEqual(report.map(\.id), [newer.id] + earlierEvents.map(\.id), period.rawValue)
            XCTAssertEqual(report.first?.event.category, .home, period.rawValue)
            XCTAssertEqual(ReportQuery.knownDuration(report), 1800 + extraDuration, period.rawValue)
        }
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

    func testLocalDayUsesEventTimeAndExcludesUnknownAndIncompleteDuration() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 5 * 3600)!
        let date = ISO8601DateFormatter().date(from: "2026-11-16T20:00:00Z")!
        let id = UUID()
        var recording = Recording(id: id, recordedAt: date, fileName: "fixture.m4a", state: .saved)
        recording.events = [
            DiaryEvent(recordingID: id, sourceText: "Работал час", text: "Работал", category: .work, duration: 3600),
            DiaryEvent(recordingID: id, sourceText: "Купил продукты", text: "Продукты", category: .home),
            DiaryEvent(recordingID: id, sourceText: "Не сделал", text: "Не сделал", completion: .notCompleted, duration: 100),
            DiaryEvent(recordingID: id, sourceText: "Вчера", text: "Вчера", occurredAt: date.addingTimeInterval(-86400), duration: 200)
        ]
        let report = ReportQuery.events(in: [recording], period: .day, date: date, calendar: calendar)
        XCTAssertEqual(report.count, 3)
        XCTAssertEqual(ReportQuery.knownDuration(report), 3600)
        XCTAssertEqual(ReportQuery.events(in: [recording], period: .week, date: date, calendar: calendar).count, 4)
    }
}
