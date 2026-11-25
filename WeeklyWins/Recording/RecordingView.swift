import SwiftUI

struct RecordingView: View {
    var searchFocused: FocusState<Bool>.Binding
    var onStartRecording: (() -> Void)?
    @ObservedObject private var recorder = RecordingService.shared
    @State private var selectedRecording: Recording?
    @State private var query = ""
    @State private var period: ReportPeriod?
    @State private var periodDate = Date.now
    @State private var error: String?
    @State private var isScrolling = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let recordInset: CGFloat = 20

    private var showsRecordButton: Bool {
        onStartRecording != nil && !recorder.isRecording && !searchFocused.wrappedValue
    }

    private var recordingsByDay: [Date: [Recording]] {
        let calendar = ReportQuery.calendar
        let interval = period.flatMap { calendar.dateInterval(of: $0.component, for: periodDate) }
        let matching = recorder.recordings.filter { recording in
            if let interval, recording.recordedAt < interval.start || recording.recordedAt >= interval.end {
                return false
            }
            return RecordingSearch.matches(recording, query: query)
        }
        return Dictionary(grouping: matching) { calendar.startOfDay(for: $0.recordedAt) }
    }

    var body: some View {
        let groups = recordingsByDay
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Записи").font(.largeTitle.bold())
                Spacer()
                SettingsButton()
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(StudioTheme.secondary)
                TextField("Текст или дата", text: $query)
                    .accessibilityIdentifier("recording-search")
                    .focused(searchFocused)
                    .submitLabel(.search)
                    .onSubmit { searchFocused.wrappedValue = false }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Очистить поиск")
                }
            }
            .frame(minHeight: 48)
            .padding(.leading, 14)
            .padding(.trailing, query.isEmpty ? 14 : 0)
            .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: StudioTheme.cornerRadius))
            periodControls
            if groups.isEmpty {
                ContentUnavailableView(
                    query.isEmpty && period != nil ? "За этот период нет записей"
                        : query.isEmpty ? "Пока нет записей" : "Ничего не найдено",
                    systemImage: query.isEmpty ? "waveform" : "magnifyingglass",
                    description: Text(query.isEmpty ? "Начните голосовую запись кнопкой внизу." : "Попробуйте другое слово или дату.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(PeriodSwipe(onShift: shiftPeriod), isEnabled: period != nil)
            } else {
                List {
                    ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                        Section {
                            Text(day.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "ru_RU"))))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(StudioTheme.secondary)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.top, 8)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            ForEach(groups[day] ?? []) { recording in
                                recordingRow(recording)
                            }
                        }
                        .listSectionSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .listRowSpacing(12)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(.bottom, showsRecordButton ? DayRecordButton.diameter + recordInset + 4 : 0,
                                for: .scrollContent)
                .onScrollPhaseChange { _, phase in
                    isScrolling = phase == .interacting || phase == .decelerating || phase == .animating
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showsRecordButton, let onStartRecording {
                DayRecordButton(isScrolling: isScrolling, isStarting: recorder.isStarting, action: onStartRecording)
                    .padding(.leading, recordInset)
                    .padding(.bottom, recordInset)
            }
        }
        .padding(20).background(StudioTheme.background).foregroundStyle(StudioTheme.text)
        .onAppear { recorder.refreshRecordings() }
        .sheet(item: $selectedRecording) { recording in
            TranscriptView(recording: recording, recordingService: recorder)
        }
        .alert("Не удалось удалить запись", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("Готово") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var periodControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                Button("Все записи") { period = nil }
                ForEach([ReportPeriod.week, .month]) { option in
                    Button(option.title) {
                        if period == nil { periodDate = .now }
                        period = option
                    }
                }
            } label: {
                Label(period?.title ?? "Все записи", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("recording-period-mode")

            if let period {
                HStack(spacing: 4) {
                    periodArrow(-1, label: "Предыдущий период", icon: "chevron.left")
                    Text(ReportQuery.periodTitle(period: period, date: periodDate))
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("recording-period-range")
                    periodArrow(1, label: "Следующий период", icon: "chevron.right")
                }
                .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: StudioTheme.cornerRadius))
                .contentShape(Rectangle())
                .simultaneousGesture(PeriodSwipe(onShift: shiftPeriod))
            }
        }
    }

    private func periodArrow(_ offset: Int, label: String, icon: String) -> some View {
        Button { shiftPeriod(offset) } label: {
            Image(systemName: icon)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func shiftPeriod(_ offset: Int) {
        guard let period, let shifted = ReportQuery.shiftedDate(periodDate, period: period, offset: offset) else { return }
        periodDate = shifted
    }

    private func openRecording(_ recording: Recording) {
        searchFocused.wrappedValue = false
        selectedRecording = recording
    }

    private func recordingRow(_ recording: Recording) -> some View {
        let row = RecordingRow(recording: recording)
        return Button {
            openRecording(recording)
        } label: {
            row.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.accessibilitySummary)
        .accessibilityIdentifier("recording-row")
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                searchFocused.wrappedValue = false
                do { try recorder.deleteRecording(id: recording.id) }
                catch { self.error = error.localizedDescription }
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            .tint(StudioTheme.coral)
            .accessibilityIdentifier("recording-swipe-delete")
        }
    }
}

private struct RecordingRow: View {
    let recording: Recording
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var accessibilitySummary: String {
        var parts = [title, durationText, statusText]
        if let transcript = recording.transcript {
            let preview = transcript.prefix(110).trimmingCharacters(in: .whitespacesAndNewlines)
            if !preview.isEmpty { parts.append(preview + (transcript.count > 110 ? "…" : "")) }
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "waveform").font(.title2).foregroundStyle(StudioTheme.mint)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .accessibilityIdentifier("recording-title-\(recording.id.uuidString)")
                    Text("Аудио · \(durationText)").font(.caption).foregroundStyle(StudioTheme.secondary)
                    if let text = recording.transcript, !text.isEmpty {
                        Text(text).lineLimit(2).font(.subheadline).foregroundStyle(StudioTheme.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .padding(.bottom, 2)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(recording.errorMessage == nil ? StudioTheme.secondary : StudioTheme.coral)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    StudioTheme.neutralCategorySurface,
                    in: StudioTheme.bottomStripeShape
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: StudioTheme.cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: StudioTheme.cornerRadius))
    }

    private var title: String {
        "Запись в \(recording.recordedAt.formatted(.dateTime.hour().minute()))"
    }

    private var durationText: String {
        guard let duration = recording.duration, duration.isFinite else { return "длительность не определена" }
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var statusText: String {
        if recording.audioDeletedAt != nil { return "Аудио удалено" }
        let processingStatus: String
        if recording.state != .saved {
            processingStatus = recording.state.displayName
        } else {
            switch recording.processingState {
            case .pending: processingStatus = recording.automaticTranscriptionPending == true ? "Ожидает расшифровки" : "Готова к расшифровке"
            case .processing: processingStatus = "Расшифровывается"
            case .completed: processingStatus = "Расшифрована · \(eventCountText)"
            case .failed: processingStatus = "Не удалось расшифровать"
            }
        }
        return processingStatus
    }

    private var eventCountText: String {
        let count = recording.events?.count ?? 0
        let lastTwoDigits = count % 100
        let lastDigit = count % 10
        let noun: String
        if (11...14).contains(lastTwoDigits) {
            noun = "событий"
        } else {
            switch lastDigit {
            case 1: noun = "событие"
            case 2...4: noun = "события"
            default: noun = "событий"
            }
        }
        return "\(count) \(noun)"
    }
}
