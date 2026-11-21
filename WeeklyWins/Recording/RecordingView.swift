import SwiftUI

struct RecordingView: View {
    var searchFocused: FocusState<Bool>.Binding
    var onStartRecording: (() -> Void)?
    @ObservedObject private var recorder = RecordingService.shared
    @State private var selectedRecording: Recording?
    @State private var deletionCandidate: Recording?
    @State private var showDeleteConfirmation = false
    @State private var query = ""
    @State private var error: String?
    @State private var isScrolling = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let recordInset: CGFloat = 20

    private var showsRecordButton: Bool {
        onStartRecording != nil && !recorder.isRecording && !searchFocused.wrappedValue
    }

    private var recordingsByDay: [Date: [Recording]] {
        let calendar = Calendar.current
        let matching = recorder.recordings.filter { RecordingSearch.matches($0, query: query) }
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
            .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            if groups.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "Пока нет записей" : "Ничего не найдено",
                    systemImage: query.isEmpty ? "waveform" : "magnifyingglass",
                    description: Text(query.isEmpty ? "Начните голосовую запись кнопкой внизу." : "Попробуйте другое слово или дату.")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                            Text(day.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "ru_RU"))))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(StudioTheme.secondary)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.top, 8)
                            ForEach(groups[day] ?? []) { recording in
                                let row = RecordingRow(recording: recording)
                                HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 0) {
                                    Button {
                                        openRecording(recording)
                                    } label: {
                                        row
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(row.accessibilitySummary)
                                    .accessibilityIdentifier("recording-row")
                                    Menu {
                                        Button("Открыть запись") { openRecording(recording) }
                                        Button("Удалить запись", role: .destructive) {
                                            searchFocused.wrappedValue = false
                                            deletionCandidate = recording
                                            showDeleteConfirmation = true
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 18))
                                            .frame(width: 44, height: 54)
                                    }
                                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
                                    .accessibilityLabel("Действия записи")
                                }
                                .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                            }
                        }
                    }
                }
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
        .confirmationDialog("Удалить запись?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить запись", role: .destructive) {
                guard let recording = deletionCandidate else { return }
                do { try recorder.deleteRecording(id: recording.id) }
                catch { self.error = error.localizedDescription }
                deletionCandidate = nil
            }
        } message: {
            Text("Аудио, расшифровка и \(deletionCandidate?.events?.count ?? 0) связанных событий будут удалены.")
        }
        .alert("Не удалось удалить запись", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("Готово") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func openRecording(_ recording: Recording) {
        searchFocused.wrappedValue = false
        selectedRecording = recording
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
        HStack(spacing: 12) {
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
                Text(statusText).font(.caption).foregroundStyle(recording.errorMessage == nil ? StudioTheme.secondary : StudioTheme.coral)
            }
            Spacer(minLength: 0)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
        if recording.state != .saved { return recording.state.displayName }
        switch recording.processingState {
        case .pending: return recording.automaticTranscriptionPending == true ? "Ожидает расшифровки" : "Готова к расшифровке"
        case .processing: return "Расшифровывается"
        case .completed: return "Расшифрована · \(recording.events?.count ?? 0) событий"
        case .failed: return "Не удалось расшифровать"
        }
    }
}
