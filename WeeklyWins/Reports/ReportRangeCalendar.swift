import SwiftUI

struct ReportRangeCalendar: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var dayHeight = 44.0
    @State private var month: Date
    @State private var start: Date?

    private let calendar = ReportQuery.calendar
    private let locale = Locale(identifier: "ru_RU")
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7)
    private let onSelect: (ClosedRange<Date>) -> Void

    private var rowHeight: CGFloat { min(dayHeight, 64) }

    init(initialDate: Date, onSelect: @escaping (ClosedRange<Date>) -> Void) {
        let calendar = ReportQuery.calendar
        _month = State(initialValue: calendar.dateInterval(of: .month, for: initialDate)?.start ?? initialDate)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text(start == nil ? "Выберите начало периода" : "Выберите конец периода")
                        .font(.subheadline)
                        .foregroundStyle(StudioTheme.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                    monthNavigation
                    monthGrid
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StudioTheme.background)
            .foregroundStyle(StudioTheme.text)
            .navigationTitle("Свой период")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .tint(StudioTheme.mint)
    }

    private var monthNavigation: some View {
        HStack(spacing: 0) {
            monthButton(-1, icon: "chevron.left", label: "Предыдущий месяц")
            Text(ReportQuery.periodTitle(period: .month, date: month, calendar: calendar))
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            monthButton(1, icon: "chevron.right", label: "Следующий месяц")
        }
    }

    private var monthGrid: some View {
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        let weekdays = localizedCalendar.shortStandaloneWeekdaySymbols
        let offset = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7

        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<7) { index in
                Text(weekdays[(calendar.firstWeekday - 1 + index) % 7])
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(StudioTheme.secondary)
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .accessibilityHidden(true)
            }
            ForEach(0..<offset, id: \.self) { _ in
                Color.clear.frame(height: rowHeight)
                    .accessibilityHidden(true)
            }
            ForEach(ReportQuery.days(period: .month, date: month, calendar: calendar), id: \.self) { date in
                dayButton(date)
            }
        }
        .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: StudioTheme.cornerRadius))
    }

    private func monthButton(_ offset: Int, icon: String, label: String) -> some View {
        Button {
            if let shifted = ReportQuery.shiftedDate(month, period: .month, offset: offset, calendar: calendar) {
                month = shifted
            }
        } label: {
            Image(systemName: icon)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(StudioTheme.mint)
        .accessibilityLabel(label)
    }

    private func dayButton(_ date: Date) -> some View {
        let day = calendar.component(.day, from: date)
        let selected = start == date

        return Button {
            if let start {
                onSelect(min(start, date)...max(start, date))
                dismiss()
            } else {
                start = date
            }
        } label: {
            Text(String(day))
                .font(.body.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(selected ? StudioTheme.background : StudioTheme.text)
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, minHeight: rowHeight)
                .background {
                    if selected { Circle().fill(StudioTheme.mint).padding(3) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("report-range-day-\(day)")
    }
}
