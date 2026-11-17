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
    static func events(in recordings: [Recording], period: ReportPeriod, date: Date, calendar: Calendar = .current) -> [ReportEntry] {
        guard let interval = calendar.dateInterval(of: period.component, for: date) else { return [] }
        return recordings.flatMap { recording in
            (recording.events ?? []).map { ReportEntry(event: $0, recording: recording) }
        }
        .filter { $0.date >= interval.start && $0.date < interval.end }
        .sorted { $0.date > $1.date }
    }

    static func knownDuration(_ entries: [ReportEntry]) -> TimeInterval {
        entries.filter { $0.event.completion == .completed }.compactMap(\.event.duration).reduce(0, +)
    }
}
