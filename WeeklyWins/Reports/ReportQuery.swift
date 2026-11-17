import Foundation

enum ReportPeriod: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return "День"
        case .week: return "Неделя"
        case .month: return "Месяц"
        }
    }
    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
}

struct ReportEntry: Identifiable {
    let event: DiaryEvent
    let recording: Recording
    var id: UUID { event.id }
    var date: Date { event.occurredAt ?? recording.recordedAt }
}

enum ReportQuery {
    static var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func preservingCalendarDate(_ date: Date, from previous: Calendar, to current: Calendar) -> Date? {
        var components = previous.dateComponents([.era, .year, .month, .day], from: date)
        components.hour = 12
        return current.date(from: components)
    }

    static func days(period: ReportPeriod, date: Date, calendar: Calendar = ReportQuery.calendar) -> [Date] {
        guard let interval = calendar.dateInterval(of: period.component, for: date) else { return [] }
        var day = interval.start
        var dates: [Date] = []
        while day < interval.end {
            dates.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return dates
    }

    static func shiftedDate(_ date: Date, period: ReportPeriod, offset: Int, calendar: Calendar = ReportQuery.calendar) -> Date? {
        guard let interval = calendar.dateInterval(of: period.component, for: date) else { return nil }
        return calendar.date(byAdding: period.component, value: offset, to: interval.start)
    }

    static func periodTitle(period: ReportPeriod, date: Date, calendar: Calendar = ReportQuery.calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if period == .month {
            formatter.dateFormat = "LLLL yyyy"
            return formatter.string(from: date).capitalized
        }
        formatter.dateFormat = "d MMMM"
        guard period == .week, let interval = calendar.dateInterval(of: .weekOfYear, for: date),
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else {
            return formatter.string(from: date)
        }
        if calendar.isDate(interval.start, equalTo: last, toGranularity: .month) {
            return "\(calendar.component(.day, from: interval.start))–\(formatter.string(from: last))"
        }
        if calendar.component(.year, from: interval.start) != calendar.component(.year, from: last) {
            formatter.dateFormat = "d MMMM yyyy"
        }
        return "\(formatter.string(from: interval.start)) — \(formatter.string(from: last))"
    }
    static func events(in recordings: [Recording], period: ReportPeriod, date: Date, calendar: Calendar = ReportQuery.calendar) -> [ReportEntry] {
        guard let interval = calendar.dateInterval(of: period.component, for: date) else { return [] }
        return recordings.filter { $0.deletedAt == nil }.flatMap { recording in
            (recording.events ?? []).map { ReportEntry(event: $0, recording: recording) }
        }
        .filter { $0.date >= interval.start && $0.date < interval.end }
        .sorted { $0.date > $1.date }
    }

    static func knownDuration(_ entries: [ReportEntry]) -> TimeInterval {
        entries.filter { $0.event.completion == .completed }.compactMap(\.event.duration).reduce(0, +)
    }
}
