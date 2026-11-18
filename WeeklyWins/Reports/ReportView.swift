import SwiftUI
import Charts

struct ReportView: View {
    @ObservedObject private var service = RecordingService.shared
    @State private var period: ReportPeriod = .day
    @State private var date = Date.now
    @State private var category: EventCategory?
    @State private var showCalendar = false
    @State private var selectedEntry: ReportEntry?
    @State private var selectedRecording: Recording?
    @State private var followsToday = true
    @State private var selectedTimeZone = TimeZone.current
    @State private var parentReport: (period: ReportPeriod, date: Date)?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var timeWidth = 60.0
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
                        Text(isToday ? Calendar.current.isDateInToday(date) ? "Сегодня" : "День" : "Отчёты").font(.largeTitle.bold())
                        Spacer()
                        SettingsButton()
                    }
                    if isToday {
                        HStack {
                            Button { showCalendar = true } label: {
                                Text(ReportQuery.periodTitle(period: .day, date: date)).foregroundStyle(StudioTheme.secondary)
                            }.buttonStyle(.plain).accessibilityLabel("Выбрать день")
                            Spacer()
                            if !Calendar.current.isDateInToday(date) {
                                Button("Сегодня") { followsToday = true; date = .now }
                            }
                        }
                    }
                    CategoryFilter(category: $category)
                    if isToday { processingRecordings }
                    if !isToday {
                        Picker("Период", selection: Binding(get: { period }, set: {
                            parentReport = nil
                            period = $0
                        })) {
                            ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                        HStack {
                            Button { moveDate(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                                .accessibilityLabel("Предыдущий период")
                            Spacer()
                            Button { showCalendar = true } label: {
                                Text(ReportQuery.periodTitle(period: period, date: date)).font(.headline)
                            }.accessibilityLabel("Выбрать период")
                                .accessibilityValue(ReportQuery.periodTitle(period: period, date: date))
                            Spacer()
                            Button { moveDate(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                                .accessibilityLabel("Следующий период")
                        }
                        if let parentReport {
                            Button("Вернуться к отчёту за \(parentReport.period == .week ? "неделю" : "месяц")") {
                                period = parentReport.period
                                date = parentReport.date
                                self.parentReport = nil
                            }
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
                    let items = entries
                    LazyVStack(spacing: isToday ? 12 : 16) {
                        ForEach(items) { entry in
                            eventRow(entry, hasPrevious: entry.id != items.first?.id, hasNext: entry.id != items.last?.id)
                        }
                    }
                }.padding(20)
            }
            .background(StudioTheme.background).foregroundStyle(StudioTheme.text)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { service.refreshRecordings(); refreshCalendarContext() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refreshCalendarContext() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshFollowingToday() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                refreshCalendarContext()
                service.refreshRecordings()
            }
            .sheet(isPresented: $showCalendar) {
                NavigationStack {
                    DatePicker("Дата", selection: Binding(get: { date }, set: {
                        date = $0
                        if isToday { followsToday = Calendar.current.isDateInToday($0) }
                    }), displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .toolbar { Button("Готово") { showCalendar = false } }
                }.presentationDetents([.medium])
            }
            .sheet(item: $selectedEntry) { entry in
                NavigationStack { EventDetailView(entry: entry, service: service) }
                    .preferredColorScheme(.dark).tint(StudioTheme.mint)
            }
            .sheet(item: $selectedRecording) { recording in
                TranscriptView(recording: recording, recordingService: service)
            }
        }
    }

    private func eventRow(_ entry: ReportEntry, hasPrevious: Bool, hasNext: Bool) -> some View {
        let columnWidth = min(timeWidth, 92)
        let dotColor = StudioTheme.categoryColor(entry.event.category)
        let stacked = dynamicTypeSize.isAccessibilitySize
        let dot = Circle().fill(dotColor).frame(width: 8, height: 8).accessibilityHidden(true)
        let row = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: isToday ? .center : .top, spacing: isToday ? 8 : 12))
        let timestamp = stacked
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        return row {
            timestamp {
                if stacked { dot }
                if entry.event.occurredAt == nil { Text("Записано").font(.caption2) }
                Text(entry.date.formatted(.dateTime.hour().minute())).font(.caption.monospacedDigit())
            }
            .foregroundStyle(StudioTheme.secondary)
            .frame(width: stacked ? nil : isToday ? columnWidth : 60, alignment: .leading)
            if !stacked { dot.padding(.top, isToday ? 0 : 6) }
            HStack(alignment: stacked ? .top : .center, spacing: 0) {
                Button { selectedEntry = entry } label: {
                    HStack(spacing: 10) {
                        if !stacked {
                            Image(systemName: entry.event.category == .home ? "house" : isToday ? "laptopcomputer" : "briefcase")
                                .font(.title2).foregroundStyle(dotColor)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.event.text).font(.headline).multilineTextAlignment(.leading)
                            Text("\(entry.event.category.title) · \(StudioTheme.duration(entry.event.duration))")
                                .font(.caption).foregroundStyle(StudioTheme.secondary)
                            if entry.event.completion == .notCompleted {
                                Text("Не сделано").font(.caption).foregroundStyle(StudioTheme.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if !isToday {
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(StudioTheme.mint)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.leading, isToday ? 12 : 15)
                    .padding(.trailing, isToday ? 0 : 15)
                    .padding(.vertical, isToday ? 12 : 15)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                if isToday {
                    Button { selectedRecording = entry.recording } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(StudioTheme.mint)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.06), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                    .padding(.top, stacked ? 8 : 0)
                    .accessibilityLabel("Открыть аудио: \(entry.event.text)")
                }
            }
            .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: isToday ? 16 : 20))
        }
        .background {
            if isToday && !stacked && (hasPrevious || hasNext) {
                GeometryReader { proxy in
                    let x = columnWidth + 12
                    let center = proxy.size.height / 2
                    Path { line in
                        line.move(to: CGPoint(x: x, y: hasPrevious ? 0 : center))
                        line.addLine(to: CGPoint(x: x, y: hasNext ? proxy.size.height + 12 : center))
                    }.stroke(StudioTheme.secondary.opacity(0.32), lineWidth: 1)
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
        }
    }

    private var processingRecordings: some View {
        let recordings = service.recordings.filter {
            Calendar.current.isDate($0.recordedAt, inSameDayAs: date)
                && ($0.automaticTranscriptionPending == true || $0.processingState == .processing || $0.processingState == .failed)
                && $0.state != .recording && $0.state != .failed
        }
        return ForEach(recordings) { recording in
            HStack(alignment: .top, spacing: 12) {
                Button { selectedRecording = recording } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(processingTitle(for: recording)) \(recording.recordedAt.formatted(.dateTime.hour().minute()))")
                            .font(.subheadline.weight(.semibold))
                        if let message = recording.errorMessage {
                            Text(message).font(.footnote).multilineTextAlignment(.leading)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                if recording.processingState == .failed {
                    Button {
                        Task { _ = try? await service.transcribe(recordingID: recording.id) }
                    } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Повторить расшифровку")
                    .disabled(!service.transcribingRecordingIDs.isEmpty)
                }
            }
            .foregroundStyle(recording.processingState == .failed ? StudioTheme.coral : StudioTheme.mint)
            .padding(14).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func processingTitle(for recording: Recording) -> String {
        switch recording.processingState {
        case .processing: return "Расшифровывается запись"
        case .failed: return "Ошибка расшифровки"
        case .pending, .completed: return "Ожидает расшифровки"
        }
    }

    private var durationChart: some View {
        let calendar = ReportQuery.calendar
        let days = ReportQuery.days(period: period, date: date, calendar: calendar)
        return Chart {
            ForEach(days, id: \.self) { day in
                let dayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
                BarMark(x: .value("День", day, unit: .day), y: .value("Часы", ReportQuery.knownDuration(dayEntries) / 3600))
                    .foregroundStyle(StudioTheme.mint).cornerRadius(4)
            }
        }
        .accessibilityIdentifier("report-chart")
        .chartYAxisLabel("ч")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Color.clear.contentShape(Rectangle()).accessibilityHidden(true)
                    .onTapGesture { location in
                        guard period != .day, let plotFrame = proxy.plotFrame else { return }
                        let frame = geometry[plotFrame]
                        guard frame.contains(location),
                              let selected = proxy.value(atX: location.x - frame.minX, as: Date.self) else { return }
                        parentReport = (period, date)
                        date = calendar.startOfDay(for: selected)
                        period = .day
                    }
            }
        }
    }

    private func refreshCalendarContext() {
        let newZone = TimeZone.current
        if selectedTimeZone != newZone {
            var previous = ReportQuery.calendar
            previous.timeZone = selectedTimeZone
            let current = ReportQuery.calendar
            if !(isToday && followsToday) {
                date = ReportQuery.preservingCalendarDate(date, from: previous, to: current) ?? date
            }
            if let parentReport {
                self.parentReport = (parentReport.period,
                    ReportQuery.preservingCalendarDate(parentReport.date, from: previous, to: current) ?? parentReport.date)
            }
            selectedTimeZone = newZone
        }
        refreshFollowingToday()
    }

    private func refreshFollowingToday() {
        if isToday && followsToday { date = .now }
    }

    private func moveDate(_ direction: Int) {
        date = ReportQuery.shiftedDate(date, period: period, offset: direction) ?? date
    }
}
