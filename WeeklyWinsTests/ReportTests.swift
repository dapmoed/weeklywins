import XCTest
@testable import WeeklyWins

final class ReportTests: XCTestCase {
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
