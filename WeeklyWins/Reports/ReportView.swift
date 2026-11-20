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
    @State private var isDayScrolling = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let isToday: Bool
    var onStartRecording: (() -> Void)? = nil

    private var showsDayRecordButton: Bool {
        isToday && onStartRecording != nil && !service.isRecording
    }

    private var entries: [ReportEntry] {
        let items = ReportQuery.events(in: service.recordings, period: isToday ? .day : period, date: date)
            .filter { category == nil || $0.event.category == category }
        return isToday ? items.sorted { $0.date < $1.date } : items
    }

    var body: some View {
        let items = entries
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: isToday ? 12 : 18) {
                    if isToday {
                        dayNavigation
                    } else {
                        HStack {
                            Text("Отчёты").font(.largeTitle.bold())
                            Spacer()
                            SettingsButton()
                        }
                    }
                    CategoryFilter(category: $category)
                    if isToday { processingRecordings }
                    if !isToday {
                        reportPeriodPicker
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
                        if !items.isEmpty {
                            switch period {
                            case .day:
                                EmptyView()
                            case .week:
                                durationChart(items).frame(height: 170)
                            case .month:
                                monthCalendar(items)
                            }
                            durationSummary(items)
                        }
                    }
                    if items.isEmpty {
                        if isToday {
                            ContentUnavailableView("Нет событий", systemImage: "list.bullet", description: Text("Расскажите, что уже сделали. События появятся после расшифровки."))
                        } else {
                            ContentUnavailableView("За этот период нет событий", systemImage: "chart.bar")
                        }
                    }
                    LazyVStack(spacing: isToday ? 8 : 16) {
                        ForEach(items) { eventRow($0) }
                    }
                }.padding(20)
            }
            .accessibilityIdentifier(isToday ? "day-timeline" : "period-report")
            .contentMargins(.bottom, showsDayRecordButton ? 58 : 0, for: .scrollContent)
            .onScrollPhaseChange { _, phase in
                if isToday {
                    isDayScrolling = phase == .interacting || phase == .decelerating || phase == .animating
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if showsDayRecordButton, let onStartRecording {
                    DayRecordButton(isScrolling: isDayScrolling, isStarting: service.isStarting, action: onStartRecording)
                        .padding(.leading, 20)
                        .padding(.bottom, 6)
                }
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
                    ScrollView {
                        DatePicker("Дата", selection: Binding(get: { date }, set: {
                            date = $0
                            if isToday { followsToday = Calendar.current.isDateInToday($0) }
                        }), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(StudioTheme.mint)
                        .padding(.horizontal, 20)
                    }
                    .background(StudioTheme.background)
                    .navigationTitle("Выбор даты")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Готово") { showCalendar = false } }
                }
                .environment(\.calendar, ReportQuery.calendar)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .presentationDetents([.medium, .large])
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

    private var reportPeriodPicker: some View {
        HStack(spacing: 4) {
            ForEach(ReportPeriod.allCases) { choice in
                Button {
                    parentReport = nil
                    period = choice
                } label: {
                    Text(choice.title)
                        .font(.subheadline.weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(period == choice ? StudioTheme.background : StudioTheme.text)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(period == choice ? StudioTheme.mint : Color.clear, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(period == choice ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .background(StudioTheme.surface, in: Capsule())
    }

    private var dayNavigation: some View {
        let selectedTitle = ReportQuery.periodTitle(period: .day, date: date)
        let dayPicker = Button { showCalendar = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar").font(.system(size: 18)).foregroundStyle(StudioTheme.mint)
                    .accessibilityHidden(true)
                Text(selectedTitle).font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(StudioTheme.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Выбрать день")
        .accessibilityValue(selectedTitle)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                dayPicker
                Spacer(minLength: 0)
                SettingsButton()
            }
            if !Calendar.current.isDateInToday(date) {
                HStack {
                    dayArrow(-1, icon: "chevron.left", label: "Предыдущий день")
                    dayArrow(1, icon: "chevron.right", label: "Следующий день")
                    Spacer(minLength: 4)
                    Button("Сегодня") {
                        followsToday = true
                        date = .now
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("return-to-today")
                }
            }
        }
    }

    private func dayArrow(_ offset: Int, icon: String, label: String) -> some View {
        Button { moveDate(offset) } label: {
            Image(systemName: icon).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func eventRow(_ entry: ReportEntry) -> some View {
        if isToday { dayEventRow(entry) }
        else { reportEventRow(entry) }
    }

    private func dayEventRow(_ entry: ReportEntry) -> some View {
        let time = entry.date.formatted(.dateTime.hour().minute())
        let timestamp = entry.event.occurredAt == nil ? "Запись \(time)" : time
        return HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 0) {
            Button { selectedEntry = entry } label: {
                eventDetails(entry, timestamp: timestamp)
                    .padding(.leading, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
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
            .padding(.top, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
            .accessibilityLabel("Открыть аудио: \(entry.event.text)")
        }
        .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func eventDetails(_ entry: ReportEntry, timestamp: String? = nil) -> some View {
        let metadata = [timestamp, entry.event.category.title, StudioTheme.duration(entry.event.duration)]
            .compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 5) {
            Text(entry.event.text).font(.headline).multilineTextAlignment(.leading)
            Text(metadata).font(isToday ? .caption2 : .caption).foregroundStyle(StudioTheme.secondary)
            if entry.event.completion == .notCompleted {
                Text("Не сделано").font(.caption).foregroundStyle(StudioTheme.secondary)
            }
        }
    }

    private func reportEventRow(_ entry: ReportEntry) -> some View {
        let dotColor = StudioTheme.categoryColor(entry.event.category)
        let stacked = dynamicTypeSize.isAccessibilitySize
        let dot = Circle().fill(dotColor).frame(width: 8, height: 8).accessibilityHidden(true)
        let row = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
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
            .frame(width: stacked ? nil : 60, alignment: .leading)
            if !stacked { dot.padding(.top, 6) }
            Button { selectedEntry = entry } label: {
                HStack(spacing: 10) {
                    if !stacked {
                        Image(systemName: entry.event.category == .home ? "house" : "briefcase")
                            .font(.title2).foregroundStyle(dotColor)
                            .accessibilityHidden(true)
                    }
                    eventDetails(entry)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(StudioTheme.mint)
                        .accessibilityHidden(true)
                }.padding(15)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 20))
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

    private func durationSummary(_ items: [ReportEntry]) -> some View {
        let completedCount = items.filter { $0.event.completion == .completed }.count
        let unknownCount = items.filter { $0.event.duration == nil }.count
        let groups = Dictionary(grouping: items) { $0.event.category }
        let completed = reportCount("Выполнено дел", value: completedCount.formatted(), id: "report-completed-count")
        let unknown = reportCount("Без длительности", value: unknownCount.formatted(), id: "report-unknown-duration-count")
            .foregroundStyle(StudioTheme.secondary)
        return VStack(alignment: .leading, spacing: 10) {
            if period == .day { completed }
            reportCount("Известная длительность", value: StudioTheme.duration(ReportQuery.knownDuration(items)), id: "report-total-duration")
                .font(.headline)
            if period == .day && unknownCount > 0 { unknown }
            ForEach([EventCategory.work, .home, .unclassified]) { group in
                if let groupItems = groups[group] {
                    Button { category = group } label: {
                        LabeledContent {
                            HStack(spacing: 8) {
                                Text(StudioTheme.duration(ReportQuery.knownDuration(groupItems))).bold()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .accessibilityHidden(true)
                            }
                        } label: {
                            Label(group.title, systemImage: categoryIcon(group))
                                .foregroundStyle(StudioTheme.categoryColor(group))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("report-category-\(group.rawValue)")
                }
            }
            if period != .day {
                if unknownCount > 0 { unknown }
                completed
            }
        }
    }

    private func reportCount(_ title: String, value: String, id: String) -> some View {
        LabeledContent(title, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityIdentifier(id)
    }

    private func categoryIcon(_ category: EventCategory) -> String {
        switch category {
        case .work: "laptopcomputer"
        case .home: "house"
        case .unclassified: "tag"
        }
    }

    private func durationChart(_ items: [ReportEntry]) -> some View {
        let calendar = ReportQuery.calendar
        let days = ReportQuery.days(period: .week, date: date, calendar: calendar)
        let byDay = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        let durations = days.map { ReportQuery.knownDuration(byDay[$0] ?? []) }
        let weekdayFormat = Date.FormatStyle.dateTime.weekday(.abbreviated).locale(Locale(identifier: "ru_RU"))
        let labels = days.map { $0.formatted(weekdayFormat) }
        let showsHours = (durations.max() ?? 0) >= 3600
        let unit: Double = showsHours ? 3600 : 60
        let unitLabel = showsHours ? "ч" : "мин"
        let axisFont = Font.system(size: dynamicTypeSize.isAccessibilitySize ? 14 : 11)
        return Chart {
            ForEach(days.indices, id: \.self) { index in
                BarMark(x: .value("День", labels[index]), y: .value("Длительность", durations[index] / unit))
                    .foregroundStyle(StudioTheme.mint)
                    .cornerRadius(4)
            }
        }
        .accessibilityIdentifier("report-chart")
        .accessibilityChildren {
            ForEach(days.indices, id: \.self) { index in
                Button(ReportQuery.periodTitle(period: .day, date: days[index])) { openReportDay(days[index]) }
                    .accessibilityValue(StudioTheme.duration(durations[index]))
            }
        }
        .chartXScale(domain: labels)
        .chartXAxis {
            AxisMarks(values: labels) { axis in
                if let day = axis.as(String.self) {
                    AxisValueLabel { Text(day).font(axisFont) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { axis in
                AxisGridLine()
                if let value = axis.as(Double.self) {
                    AxisValueLabel {
                        Text(value.formatted(.number.precision(.significantDigits(1...3))) + " " + unitLabel)
                            .font(axisFont)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Color.clear.contentShape(Rectangle()).accessibilityHidden(true)
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let frame = geometry[plotFrame]
                        guard frame.contains(location),
                              let label = proxy.value(atX: location.x - frame.minX, as: String.self),
                              let index = labels.firstIndex(of: label) else { return }
                        openReportDay(days[index])
                    }
            }
        }
    }

    private func monthCalendar(_ items: [ReportEntry]) -> some View {
        let calendar = ReportQuery.calendar
        let days = ReportQuery.days(period: .month, date: date, calendar: calendar)
        let firstWeekday = days.first.map { calendar.component(.weekday, from: $0) } ?? calendar.firstWeekday
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        let byDay = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 4) {
            ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { weekday in
                Text(weekday)
                    .font(.caption2)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(StudioTheme.secondary)
                    .accessibilityHidden(true)
            }
            ForEach(0..<offset, id: \.self) { _ in
                Color.clear.frame(height: 44).accessibilityHidden(true)
            }
            ForEach(days, id: \.self) { day in
                let count = byDay[day]?.count ?? 0
                Button { openReportDay(day) } label: {
                    VStack(spacing: 2) {
                        Text(calendar.component(.day, from: day).formatted())
                            .font(.subheadline.monospacedDigit())
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        Circle().fill(count > 0 ? StudioTheme.mint : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(count > 0 ? StudioTheme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ReportQuery.periodTitle(period: .day, date: day))
                .accessibilityValue("Дел: \(count)")
                .accessibilityIdentifier("report-month-day")
            }
        }
    }

    private func openReportDay(_ selected: Date) {
        parentReport = (period, date)
        date = ReportQuery.calendar.startOfDay(for: selected)
        period = .day
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
        guard let shifted = ReportQuery.shiftedDate(date, period: isToday ? .day : period, offset: direction) else { return }
        date = shifted
        if isToday { followsToday = Calendar.current.isDateInToday(shifted) }
    }
}

private struct DayRecordButton: View {
    let isScrolling: Bool
    let isStarting: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showsTranslucentBackground = false

    private var isTranslucent: Bool { showsTranslucentBackground && !reduceTransparency }

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(isTranslucent ? StudioTheme.mint : StudioTheme.background)
                .shadow(color: isTranslucent ? StudioTheme.background : .clear, radius: 1, y: 1)
                .frame(width: 48, height: 48)
                .background(StudioTheme.mint.opacity(isTranslucent ? 0.16 : 1), in: Circle())
                .overlay {
                    Circle().strokeBorder(StudioTheme.mint.opacity(isTranslucent ? 0.47 : 0), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isStarting ? "Запускается…" : "Записать")
        .accessibilityIdentifier("day-floating-record")
        .disabled(isStarting)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isTranslucent)
        .task(id: isScrolling) {
            if isScrolling {
                showsTranslucentBackground = true
            } else if showsTranslucentBackground {
                do { try await Task.sleep(for: .milliseconds(280)) }
                catch { return }
                guard !Task.isCancelled else { return }
                showsTranslucentBackground = false
            }
        }
    }
}
