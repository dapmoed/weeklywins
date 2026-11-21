import SwiftUI

struct ReportView: View {
    @ObservedObject private var service = RecordingService.shared
    @State private var choice: ReportChoice = .week
    @State private var date = Date.now
    @State private var customStart: Date
    @State private var customEnd: Date
    @State private var category: EventCategory?
    @State private var showCalendar = false
    @State private var selectedEntry: ReportEntry?
    @State private var selectedRecording: Recording?
    @State private var followsToday = true
    @State private var selectedTimeZone = TimeZone.current
    @State private var reportScrollPosition = ScrollPosition(edge: .top)
    @State private var textScrollPosition = ScrollPosition(edge: .top)
    @State private var isDayScrolling = false
    @State private var showDayFailures = false
    @State private var swipedDayEventID: UUID?
    @State private var draggedDayEventID: UUID?
    @State private var daySwipeTranslation: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isToday: Bool
    var onStartRecording: (() -> Void)? = nil
    var onDeleteEvent: ((DiaryEvent) -> Void)? = nil

    private let dayRecordInset: CGFloat = 20

    init(isToday: Bool, onStartRecording: (() -> Void)? = nil, onDeleteEvent: ((DiaryEvent) -> Void)? = nil) {
        self.isToday = isToday
        self.onStartRecording = onStartRecording
        self.onDeleteEvent = onDeleteEvent
        let calendar = ReportQuery.calendar
        let week = calendar.dateInterval(of: .weekOfYear, for: .now)
        _customStart = State(initialValue: week?.start ?? .now)
        _customEnd = State(initialValue: week.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? .now)
    }

    private enum ReportChoice: String, CaseIterable, Identifiable {
        case day, week, month, custom
        var id: String { rawValue }
    }

    private var showsDayRecordButton: Bool {
        isToday && onStartRecording != nil && !service.isRecording
    }

    private var entries: [ReportEntry] {
        let items: [ReportEntry]
        if isToday || choice == .day {
            items = ReportQuery.events(in: service.recordings, period: .day, date: date)
        } else if choice == .custom {
            let calendar = ReportQuery.calendar
            let start = calendar.startOfDay(for: customStart)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd)) ?? customEnd
            items = ReportQuery.events(in: service.recordings, from: start, to: end)
        } else {
            items = ReportQuery.events(in: service.recordings, period: choice == .month ? .month : .week, date: date)
        }
        return items.filter { category == nil || $0.event.category == category }
    }

    var body: some View {
        let items = entries
        return NavigationStack {
            Group {
                if isToday { todayContent } else { reportsContent(items) }
            }
            .background(StudioTheme.background).foregroundStyle(StudioTheme.text)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { service.refreshRecordings(); refreshCalendarContext() }
            .onChange(of: date) { previous, current in
                if !Calendar.current.isDate(previous, inSameDayAs: current) {
                    showDayFailures = false
                    swipedDayEventID = nil
                }
            }
            .onChange(of: category) { swipedDayEventID = nil }
            .onChange(of: choice) { textScrollPosition.scrollTo(edge: .top) }
            .onChange(of: customStart) { newValue in
                if newValue > customEnd { customEnd = newValue }
            }
            .onChange(of: customEnd) { newValue in
                if newValue < customStart { customStart = newValue }
            }
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

    // MARK: - Отчёты

    private func reportsContent(_ items: [ReportEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Отчёты").font(.largeTitle.bold())
                Spacer()
                SettingsButton()
            }
            periodMenu
            if choice == .custom { customRangePickers }
            CategoryFilter(category: $category, compact: true)
            if items.isEmpty {
                ContentUnavailableView("За этот период нет событий", systemImage: "chart.bar")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(shareText(items))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(StudioTheme.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .accessibilityIdentifier("report-share-text")
                }
                .scrollPosition($textScrollPosition)
                .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(20)
        .accessibilityIdentifier("period-report")
        .overlay(alignment: .bottomTrailing) {
            if !items.isEmpty {
                ShareLink(item: shareText(items)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(StudioTheme.background)
                        .frame(width: 48, height: 48)
                        .background(StudioTheme.mint, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("report-share-button")
                .padding(20)
            }
        }
    }

    private var periodMenu: some View {
        Menu {
            Button("День") {
                choice = .day
                showCalendar = true
            }
            Button("Неделя (текущая)") {
                choice = .week
                date = .now
            }
            Button("Месяц") {
                choice = .month
                date = .now
            }
            Button("Свой период…") {
                choice = .custom
            }
        } label: {
            HStack(spacing: 6) {
                Text(periodMenuTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StudioTheme.mint)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .background(StudioTheme.surface, in: Capsule())
        }
        .accessibilityLabel("Выбрать период")
        .accessibilityValue(periodMenuTitle)
    }

    private var periodMenuTitle: String {
        switch choice {
        case .day: return ReportQuery.periodTitle(period: .day, date: date)
        case .week: return "Неделя \(ReportQuery.periodTitle(period: .week, date: date))"
        case .month: return ReportQuery.periodTitle(period: .month, date: date)
        case .custom: return "Свой период"
        }
    }

    private var customRangePickers: some View {
        HStack(spacing: 12) {
            Text("С").font(.subheadline).foregroundStyle(StudioTheme.secondary)
            DatePicker("С", selection: $customStart, displayedComponents: .date)
                .labelsHidden()
                .tint(StudioTheme.mint)
            Text("По").font(.subheadline).foregroundStyle(StudioTheme.secondary)
            DatePicker("По", selection: $customEnd, displayedComponents: .date)
                .labelsHidden()
                .tint(StudioTheme.mint)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 12)
        .background(StudioTheme.surface, in: Capsule())
        .environment(\.calendar, ReportQuery.calendar)
        .environment(\.locale, Locale(identifier: "ru_RU"))
    }

    private var shareGrouping: ReportQuery.ReportGrouping {
        switch choice {
        case .month: return .week
        case .custom:
            let calendar = ReportQuery.calendar
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: customStart),
                                                to: calendar.startOfDay(for: customEnd)).day ?? 0
            return days > 6 ? .week : .day
        case .day, .week: return .day
        }
    }

    private func shareText(_ items: [ReportEntry]) -> String {
        ReportQuery.shareText(entries: items, title: shareTitle, grouping: shareGrouping)
    }

    private var shareTitle: String {
        switch choice {
        case .day: return "Дела за \(ReportQuery.periodTitle(period: .day, date: date))"
        case .week: return "Неделя \(ReportQuery.periodTitle(period: .week, date: date))"
        case .month: return "Дела за \(ReportQuery.periodTitle(period: .month, date: date))"
        case .custom: return "Дела за \(customRangeTitle)"
        }
    }

    private var customRangeTitle: String {
        let calendar = ReportQuery.calendar
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMMM"
        let start = formatter.string(from: customStart)
        let end = formatter.string(from: customEnd)
        if calendar.component(.year, from: customStart) != calendar.component(.year, from: customEnd) {
            formatter.dateFormat = "d MMMM yyyy"
            return "\(formatter.string(from: customStart)) — \(formatter.string(from: customEnd))"
        }
        return "\(start) — \(end)"
    }

    // MARK: - Лента дня

    private var todayContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                dayNavigation
                CategoryFilter(category: $category, compact: true)
                processingRecordings
                if entries.isEmpty { dayEmptyState }
                LazyVStack(spacing: 8) {
                    ForEach(entries) { dayEventRow($0) }
                }
            }.padding(20)
        }
        .accessibilityIdentifier("day-timeline")
        .scrollPosition($reportScrollPosition)
        .contentMargins(.bottom, showsDayRecordButton ? DayRecordButton.diameter + dayRecordInset + 4 : 0,
                        for: .scrollContent)
        .onScrollPhaseChange { _, phase in
            isDayScrolling = phase == .interacting || phase == .decelerating || phase == .animating
            if phase == .interacting && draggedDayEventID == nil { swipedDayEventID = nil }
        }
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if showsDayRecordButton, let onStartRecording {
                DayRecordButton(isScrolling: isDayScrolling, isStarting: service.isStarting, action: onStartRecording)
                    .padding(.leading, dayRecordInset)
                    .padding(.bottom, dayRecordInset)
            }
        }
    }

    @ViewBuilder
    private var dayEmptyState: some View {
        if category != nil {
            ContentUnavailableView("Нет дел в этой категории", systemImage: "line.3.horizontal.decrease",
                                   description: Text("Выберите другую категорию или сбросьте фильтр."))
        } else if Calendar.current.isDateInToday(date) {
            ContentUnavailableView("Нет событий", systemImage: "list.bullet",
                                   description: Text("Расскажите, что уже сделали. События появятся после расшифровки."))
        } else {
            ContentUnavailableView("В этот день нет событий", systemImage: "list.bullet")
        }
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

    private func dayEventRow(_ entry: ReportEntry) -> some View {
        let time = entry.date.formatted(.dateTime.hour().minute())
        let timestamp = "Запись \(time)"
        let isRevealed = swipedDayEventID == entry.id
        let isDragging = draggedDayEventID == entry.id
        let actionWidth: CGFloat = 84
        let offset = min(0, max(-actionWidth, (isRevealed ? -actionWidth : 0) + (isDragging ? daySwipeTranslation : 0)))
        return HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 0) {
            Button {
                guard draggedDayEventID == nil else { return }
                let wasRevealed = swipedDayEventID != nil
                swipedDayEventID = nil
                if !wasRevealed { selectedEntry = entry }
            } label: {
                eventDetails(entry, timestamp: timestamp)
                    .padding(.leading, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAction(named: Text("Удалить дело")) { deleteDayEvent(entry.event) }
            Button {
                guard draggedDayEventID == nil else { return }
                let wasRevealed = swipedDayEventID != nil
                swipedDayEventID = nil
                if !wasRevealed { selectedRecording = entry.recording }
            } label: {
                Image(systemName: "waveform")
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
        .background(StudioTheme.surface)
        .offset(x: offset)
        .background(alignment: .trailing) {
            if isRevealed || isDragging {
                Button(role: .destructive) {
                    deleteDayEvent(entry.event)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash").font(.system(size: 20, weight: .medium))
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("Удалить").font(.caption)
                        }
                    }
                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 14 : 0)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center)
                    .foregroundStyle(StudioTheme.background)
                    .background(StudioTheme.coral)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Удалить дело")
                .accessibilityIdentifier("day-swipe-delete")
                .accessibilityHidden(isDragging)
                .allowsHitTesting(!isDragging)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .gesture(DayCardPan { state, translation in
            switch state {
            case .began, .changed:
                if draggedDayEventID != entry.id, swipedDayEventID != entry.id { swipedDayEventID = nil }
                draggedDayEventID = entry.id
                daySwipeTranslation = translation
            case .ended, .cancelled, .failed:
                let wasRevealed = swipedDayEventID == entry.id
                let shouldReveal = state == .ended ? translation < (wasRevealed ? 32 : -32) : wasRevealed
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    swipedDayEventID = shouldReveal ? entry.id : nil
                    draggedDayEventID = nil
                    daySwipeTranslation = 0
                }
            default: break
            }
        })
    }

    private func deleteDayEvent(_ event: DiaryEvent) {
        swipedDayEventID = nil
        onDeleteEvent?(event)
    }

    private func eventDetails(_ entry: ReportEntry, timestamp: String? = nil) -> some View {
        let metadata = [timestamp, entry.event.category.title]
            .compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 5) {
            Text(entry.event.text).font(isToday ? .body : .headline).multilineTextAlignment(.leading)
            Text(metadata).font(isToday ? .caption2 : .caption).foregroundStyle(StudioTheme.secondary)
            if entry.event.completion == .notCompleted {
                Text("Не сделано").font(.caption).foregroundStyle(StudioTheme.secondary)
            }
        }
    }

    @ViewBuilder
    private var processingRecordings: some View {
        let recordings = service.recordings.filter {
            Calendar.current.isDate($0.recordedAt, inSameDayAs: date)
                && ($0.automaticTranscriptionPending == true || $0.processingState == .processing || $0.processingState == .failed)
                && $0.state != .recording && $0.state != .failed
        }
        let failures = recordings.filter { $0.processingState == .failed }
        ForEach(recordings.filter { $0.processingState != .failed }) { processingRow($0) }
        if failures.count > 1 {
            failureSummary(count: failures.count)
        }
        if failures.count == 1 || showDayFailures {
            ForEach(failures) { processingRow($0) }
        }
    }

    private func failureSummary(count: Int) -> some View {
        let lastDigit = count % 10
        let hasTeenEnding = (11...14).contains(count % 100)
        let title: String
        if !hasTeenEnding && lastDigit == 1 {
            title = "\(count) запись требует внимания"
        } else if !hasTeenEnding && (2...4).contains(lastDigit) {
            title = "\(count) записи требуют внимания"
        } else {
            title = "\(count) записей требуют внимания"
        }
        return Button { showDayFailures.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 16))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: showDayFailures ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .foregroundStyle(StudioTheme.coral)
            .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(showDayFailures ? "Развёрнуто" : "Свёрнуто")
        .accessibilityHint("Ошибки расшифровки")
        .accessibilityIdentifier("day-transcription-failures")
    }

    private func processingRow(_ recording: Recording) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { selectedRecording = recording } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(processingTitle(for: recording)) \(recording.recordedAt.formatted(.dateTime.hour().minute()))")
                        .font(.subheadline.weight(.semibold))
                    if recording.processingState == .failed {
                        Text("Можно повторить расшифровку.")
                            .font(.footnote).multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
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

    private func processingTitle(for recording: Recording) -> String {
        switch recording.processingState {
        case .processing: return "Расшифровывается запись"
        case .failed: return "Ошибка расшифровки"
        case .pending, .completed: return "Ожидает расшифровки"
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
            if let rebasedStart = ReportQuery.preservingCalendarDate(customStart, from: previous, to: current) {
                customStart = rebasedStart
            }
            if let rebasedEnd = ReportQuery.preservingCalendarDate(customEnd, from: previous, to: current) {
                customEnd = rebasedEnd
            }
            selectedTimeZone = newZone
        }
        refreshFollowingToday()
    }

    private func refreshFollowingToday() {
        if isToday && followsToday { date = .now }
    }

    private func moveDate(_ direction: Int) {
        guard let shifted = ReportQuery.shiftedDate(date, period: .day, offset: direction) else { return }
        date = shifted
        if isToday { followsToday = Calendar.current.isDateInToday(shifted) }
    }
}

private struct DayCardPan: UIGestureRecognizerRepresentable {
    let action: (UIGestureRecognizer.State, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        action(recognizer.state, recognizer.translation(in: recognizer.view).x)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.3
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer is UITapGestureRecognizer || otherGestureRecognizer.view is UIScrollView
        }
    }
}

struct DayRecordButton: View {
    static let diameter: CGFloat = 48
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
                .frame(width: Self.diameter, height: Self.diameter)
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
