import XCTest
@testable import WeeklyWins

final class ReportTests: XCTestCase {
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
