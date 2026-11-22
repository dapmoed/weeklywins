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
    var date: Date { recording.recordedAt }
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
        return events(in: recordings, from: interval.start, to: interval.end, calendar: calendar)
    }

    static func events(in recordings: [Recording], from start: Date, to end: Date, calendar: Calendar = ReportQuery.calendar) -> [ReportEntry] {
        recordings.filter { $0.deletedAt == nil }.flatMap { recording in
            (recording.events ?? []).map { ReportEntry(event: $0, recording: recording) }
        }
        .filter { $0.date >= start && $0.date < end }
        .sorted { $0.date > $1.date }
    }

    enum ReportGrouping { case day, week }

    static func shareText(entries: [ReportEntry], title: String, grouping: ReportGrouping,
                          calendar: Calendar = ReportQuery.calendar) -> String {
        var lines = [title, ""]
        lines.append("Дел: \(entries.count)")
        lines.append("")
        let ordered = entries.sorted { $0.date < $1.date }
        let groups: [(String, [ReportEntry])]
        switch grouping {
        case .day:
            let byDay = Dictionary(grouping: ordered) { calendar.startOfDay(for: $0.date) }
            groups = byDay.keys.sorted().map {
                (dayTitle($0, calendar: calendar), byDay[$0]?.sorted { $0.date < $1.date } ?? [])
            }
        case .week:
            var weeks: [(start: Date, entries: [ReportEntry])] = []
            for entry in ordered {
                let day = calendar.startOfDay(for: entry.date)
                if let index = weeks.lastIndex(where: { calendar.isDate($0.start, inSameDayAs: weekStart(of: day, calendar: calendar)) }) {
                    weeks[index].entries.append(entry)
                } else {
                    weeks.append((weekStart(of: day, calendar: calendar), [entry]))
                }
            }
            groups = weeks.sorted { $0.start < $1.start }.map { (weekTitle($0.start, calendar: calendar), $0.entries) }
        }
        for (groupTitle, groupEntries) in groups {
            lines.append(groupTitle)
            for entry in groupEntries {
                lines.append("• \(entryLine(entry))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    private static func entryLine(_ entry: ReportEntry) -> String {
        entry.event.text
    }

    private static func dayTitle(_ day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMMM"
        let datePart = formatter.string(from: day)
        formatter.dateFormat = "EEEE"
        let weekday = formatter.string(from: day)
        return "\(datePart), \(weekday.prefix(1).uppercased())\(weekday.dropFirst())"
    }

    private static func weekStart(of day: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
    }

    private static func weekTitle(_ weekStart: Date, calendar: Calendar) -> String {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart),
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return dayTitle(weekStart, calendar: calendar) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMMM"
        if calendar.component(.month, from: interval.start) == calendar.component(.month, from: last) {
            return "\(calendar.component(.day, from: interval.start))–\(formatter.string(from: last))"
        }
        if calendar.component(.year, from: interval.start) == calendar.component(.year, from: last) {
            return "\(formatter.string(from: interval.start)) — \(formatter.string(from: last))"
        }
        formatter.dateFormat = "d MMMM yyyy"
        return "\(formatter.string(from: interval.start)) — \(formatter.string(from: last))"
    }
}

enum ReportPromptPreferences {
    static let key = "weeklywins.reportModelPrompt"
    static let defaultPrompt = """
    Ты — редактор отчёта из моего голосового дневника. Преврати сырой отчёт ниже в ясный и компактный текст на русском. В моих записях чаще встречаются рабочие и домашние дела, иногда хобби.

    Сохраняй даты, важные факты, имена, числа, договорённости и дальнейшие шаги. Группируй связанные дела внутри дня и объединяй только очевидные повторы. Исправляй ошибки распознавания речи только тогда, когда правильный вариант однозначен; иначе не угадывай.

    Сохраняй планы, намерения и отрицания из исходного текста. Не добавляй отметки «сделано / не сделано», не выдумывай категории, длительности, результаты, причины или оценки продуктивности. Если категория явно указана, сохрани её; если нет — не определяй её по догадке.

    Используй короткий заголовок и понятные разделы с маркированными пунктами. Сохрани исходную хронологию. Заверши одним коротким итогом только если он прямо следует из записей. Верни только готовый отчёт без вступления и объяснений.
    """

    static func combinedText(instruction: String, report: String) -> String {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return report }
        return "\(instruction)\n\n---\n\nИсходный отчёт:\n\(report)"
    }
}
