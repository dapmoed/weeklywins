import SwiftUI
import Charts

struct ReportView: View {
    @ObservedObject private var service = RecordingService.shared
    @State private var period: ReportPeriod = .day
    @State private var date = Date.now
    @State private var category: EventCategory?
    @State private var showCalendar = false
    @State private var selectedEntry: ReportEntry?
    let isToday: Bool

    private var entries: [ReportEntry] {
        let items = ReportQuery.events(in: service.recordings, period: isToday ? .day : period, date: date)
            .filter { category == nil || $0.event.category == category }
        return isToday ? items.sorted { $0.date < $1.date } : items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text(isToday ? "Сегодня" : "Отчёты").font(.largeTitle.bold())
                        Spacer()
                        SettingsButton()
                    }
                    if isToday {
                        Button { showCalendar = true } label: {
                            Text(date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU"))))
                                .foregroundStyle(StudioTheme.secondary)
                        }.buttonStyle(.plain)
                    }
                    CategoryFilter(category: $category)
                    if !isToday {
                        Picker("Период", selection: $period) {
                            ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                        HStack {
                            Button { moveDate(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            Spacer()
                            DatePicker("Дата отчёта", selection: $date, displayedComponents: .date).labelsHidden()
                            Spacer()
                            Button { moveDate(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        }
                        if !entries.isEmpty { durationChart.frame(height: 170) }
                        Text("Известная длительность").font(.title2.bold())
                        ForEach(EventCategory.allCases) { group in
                            let items = entries.filter { $0.event.category == group }
                            if !items.isEmpty {
                                HStack {
                                    Image(systemName: group == .home ? "house" : "briefcase")
                                        .foregroundStyle(StudioTheme.categoryColor(group))
                                    Text(group.title)
                                    Spacer()
                                    Text(StudioTheme.duration(ReportQuery.knownDuration(items))).bold()
                                }
                                .padding(16).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                            }
                        }
                        let unknown = entries.filter { $0.event.duration == nil }.count
                        if unknown > 0 {
                            Label("\(unknown) дел без длительности", systemImage: "info.circle")
                                .foregroundStyle(StudioTheme.secondary)
                        }
                    }
                    if entries.isEmpty {
                        ContentUnavailableView("Нет событий", systemImage: "list.bullet", description: Text("Расскажите, что уже сделали. События появятся после расшифровки."))
                    }
                    LazyVStack(spacing: 16) {
                        ForEach(entries) { entry in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    if entry.event.occurredAt == nil { Text("Записано").font(.caption2) }
                                    Text(entry.date.formatted(.dateTime.hour().minute())).font(.caption.monospacedDigit())
                                }.foregroundStyle(StudioTheme.secondary).frame(width: 60, alignment: .leading)
                                Circle().fill(StudioTheme.categoryColor(entry.event.category)).frame(width: 8, height: 8).padding(.top, 6)
                                Button { selectedEntry = entry } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: entry.event.category == .home ? "house" : "briefcase")
                                            .font(.title2).foregroundStyle(StudioTheme.categoryColor(entry.event.category))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(entry.event.text).font(.headline).multilineTextAlignment(.leading)
                                            Text("\(entry.event.category.title) · \(StudioTheme.duration(entry.event.duration))")
                                                .font(.caption).foregroundStyle(StudioTheme.secondary)
                                            if entry.event.completion == .notCompleted {
                                                Text("Не сделано").font(.caption).foregroundStyle(StudioTheme.secondary)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(StudioTheme.mint)
                                    }
                                    .padding(15).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(20)
            }
            .background(StudioTheme.background).foregroundStyle(StudioTheme.text)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { service.refreshRecordings() }
            .sheet(isPresented: $showCalendar) {
                NavigationStack {
                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .toolbar { Button("Готово") { showCalendar = false } }
                }.presentationDetents([.medium])
            }
            .sheet(item: $selectedEntry) { entry in
                NavigationStack { EventDetailView(entry: entry, service: service) }
                    .preferredColorScheme(.dark).tint(StudioTheme.mint)
            }
        }
    }

    private var durationChart: some View {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: period.component, for: date)
        let start = interval?.start ?? calendar.startOfDay(for: date)
        let count = period == .month ? (calendar.range(of: .day, in: .month, for: date)?.count ?? 30) : period == .week ? 7 : 1
        return Chart {
            ForEach(0..<count, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                let dayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
                BarMark(x: .value("День", day, unit: .day), y: .value("Часы", ReportQuery.knownDuration(dayEntries) / 3600))
                    .foregroundStyle(StudioTheme.mint).cornerRadius(4)
            }
        }
        .chartYAxisLabel("ч")
    }

    private func moveDate(_ direction: Int) {
        date = Calendar.current.date(byAdding: period.component, value: direction, to: date) ?? date
    }
}
