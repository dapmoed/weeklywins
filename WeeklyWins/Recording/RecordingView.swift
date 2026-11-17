import SwiftUI

struct RecordingView: View {
    @ObservedObject private var recorder = RecordingService.shared
    @State private var selectedRecording: Recording?
    @State private var deletionCandidate: Recording?
    @State private var showDeleteConfirmation = false
    @State private var query = ""
    @State private var error: String?

    private var filtered: [Recording] {
        recorder.recordings.filter { RecordingSearch.matches($0, query: query) }
    }

    private var days: [Date] {
        Array(Set(filtered.map { Calendar.current.startOfDay(for: $0.recordedAt) })).sorted(by: >)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Записи").font(.largeTitle.bold())
                Spacer()
                SettingsButton()
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(StudioTheme.secondary)
                TextField("Текст или дата", text: $query)
                    .accessibilityIdentifier("recording-search")
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Очистить поиск")
                }
            }
            .padding(14).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            if filtered.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "Пока нет записей" : "Ничего не найдено",
                    systemImage: query.isEmpty ? "waveform" : "magnifyingglass",
                    description: Text(query.isEmpty ? "Начните голосовую запись кнопкой внизу." : "Попробуйте другое слово или дату.")
                ).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(days, id: \.self) { day in
                            Text(day.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "ru_RU"))))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(StudioTheme.secondary)
                                .padding(.top, 8)
                            ForEach(filtered.filter { Calendar.current.isDate($0.recordedAt, inSameDayAs: day) }) { recording in
                                HStack(spacing: 0) {
                                    Button { selectedRecording = recording } label: {
                                        RecordingRow(recording: recording)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("recording-row")
                                    Menu {
                                        Button("Открыть запись") { selectedRecording = recording }
                                        Button("Удалить запись", role: .destructive) {
                                            deletionCandidate = recording
                                            showDeleteConfirmation = true
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis").frame(width: 44, height: 54)
                                    }.accessibilityLabel("Действия записи")
                                }
                                .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                            }
                        }
                    }
                }.scrollDismissesKeyboard(.interactively)
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
}

private struct RecordingRow: View {
    let recording: Recording
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform").font(.title2).foregroundStyle(StudioTheme.mint)
            VStack(alignment: .leading, spacing: 6) {
                Text("Запись в \(recording.recordedAt.formatted(.dateTime.hour().minute()))")
                    .font(.headline)
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

    private var durationText: String {
        guard let duration = recording.duration, duration.isFinite else { return "длительность не определена" }
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var statusText: String {
        if let error = recording.errorMessage { return error }
        if recording.state != .saved { return recording.state.displayName }
        switch recording.processingState {
        case .pending: return "Готова к расшифровке"
        case .processing: return "Расшифровывается"
        case .completed: return "Расшифрована · \(recording.events?.count ?? 0) событий"
        case .failed: return "Не удалось расшифровать"
        }
    }
}
