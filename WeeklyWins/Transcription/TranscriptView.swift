import SwiftUI

struct TranscriptView: View {
    let recording: Recording
    @ObservedObject var recordingService: RecordingService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var transcript: String
    @State private var savedText: String
    @State private var isTranscribing = false
    @State private var errorMessage: String?
    @State private var confirmClose = false
    @State private var confirmTranscription = false
    @State private var editingTranscript: Bool
    @FocusState private var editorFocused: Bool
    @State private var showEvents = false
    @State private var showSettings = false
    @State private var confirmDeletion = false
    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0
    private let drafts = TranscriptDraftStore()

    init(recording: Recording, recordingService: RecordingService) {
        self.recording = recording
        self.recordingService = recordingService
        let savedText = recording.transcript ?? ""
        let draft = TranscriptDraftStore().load(recordingID: recording.id) ?? savedText
        _savedText = State(initialValue: savedText)
        _transcript = State(initialValue: draft)
        _editingTranscript = State(initialValue: draft != savedText)
    }

    private var isBusy: Bool { isTranscribing || recordingService.transcribingRecordingIDs.contains(recording.id) }
    private var hasChanges: Bool { transcript != savedText }
    private var isLoaded: Bool { recordingService.playingRecordingID == recording.id }
    private var editorTitleInContent: Bool { editingTranscript && dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if editingTranscript { editor } else { details }
            }
            .padding(20)
            .background(StudioTheme.background)
            .foregroundStyle(StudioTheme.text)
            .navigationTitle(editorTitleInContent ? "" : editingTranscript ? "Расшифровка" : "Запись")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showEvents) {
                EventReviewView(recording: currentRecording, service: recordingService)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if editingTranscript {
                        Button("Отмена") {
                            editorFocused = false
                            if hasChanges { confirmClose = true }
                            else { editingTranscript = false }
                        }
                    } else if !showEvents {
                        Button {
                            recordingService.resumeAutomaticTranscription()
                            dismiss()
                        } label: {
                            Label("Назад", systemImage: "chevron.backward")
                        }
                        .accessibilityIdentifier("recording-details-back")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if editingTranscript {
                        Button("Сохранить") {
                            if saveTranscript() { closeEditor() }
                        }
                        .disabled(isBusy || !hasChanges)
                        .accessibilityIdentifier("save-transcript")
                    } else if !showEvents {
                        Menu {
                            Button("Удалить запись", role: .destructive) { confirmDeletion = true }
                                .disabled(isBusy)
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Действия записи")
                        .accessibilityIdentifier("recording-details-actions")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if editorFocused {
                        Button("Готово") { editorFocused = false }
                            .accessibilityIdentifier("transcript-keyboard-done")
                    }
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onChange(of: transcript) { previous, _ in persistDraft(previousText: previous) }
            .onChange(of: recordingService.transcribingRecordingIDs) { _, ids in
                if !ids.contains(recording.id), !hasChanges {
                    let text = currentRecording.transcript ?? ""
                    savedText = text
                    transcript = text
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .background { persistDraft() } }
            .onDisappear { recordingService.stopPlayback() }
            .confirmationDialog("Сохранить изменения?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Сохранить") { if saveTranscript() { closeEditor() } }
                Button("Отбросить изменения", role: .destructive) {
                    drafts.remove(recordingID: recording.id, matching: transcript)
                    transcript = savedText
                    closeEditor()
                    recordingService.resumeAutomaticTranscription()
                }
                Button("Продолжить редактирование", role: .cancel) {}
            }
            .confirmationDialog("Удалить запись?", isPresented: $confirmDeletion, titleVisibility: .visible) {
                Button("Удалить запись", role: .destructive) {
                    do {
                        try recordingService.deleteRecording(id: recording.id)
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
            } message: {
                Text("Аудио, расшифровка и связанные события будут удалены.")
            }
            .confirmationDialog("Расшифровать запись заново?", isPresented: $confirmTranscription, titleVisibility: .visible) {
                Button("Расшифровать заново", role: .destructive) { Task { await transcribe() } }
            } message: {
                Text("Текст расшифровки и предложения могут обновиться. События, которые вы добавили или изменили вручную, сохранятся.")
            }
        }.tint(StudioTheme.mint).preferredColorScheme(.dark)
    }

    private var currentRecording: Recording {
        recordingService.recordings.first(where: { $0.id == recording.id }) ?? recording
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Записано \(recording.recordedAt.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier: "ru_RU"))))")
                    .font(.subheadline).foregroundStyle(StudioTheme.secondary)
                player
                VStack(alignment: .leading, spacing: 12) {
                    Text("Расшифровка").font(.headline).accessibilityAddTraits(.isHeader)
                    Text(savedText.isEmpty ? "Здесь появится расшифровка записи" : savedText)
                        .foregroundStyle(savedText.isEmpty ? StudioTheme.secondary : StudioTheme.text)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("transcript-preview")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                if let message = errorMessage ?? currentRecording.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(StudioTheme.coral)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { transcriptActions }
                    VStack(alignment: .leading, spacing: 8) { transcriptActions }
                }
                if isBusy {
                    ProgressView("Расшифровывается…")
                        .frame(minHeight: 44)
                } else {
                    Button(savedText.isEmpty ? "Расшифровать" : "Расшифровать заново") {
                        if savedText.isEmpty && !hasChanges { Task { await transcribe() } }
                        else { confirmTranscription = true }
                    }
                    .frame(minHeight: 44)
                }
                if currentRecording.processingState == .failed {
                    Button("Настройки распознавания") { showSettings = true }
                        .frame(minHeight: 44)
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptActions: some View {
        Button {
            editingTranscript = true
        } label: {
            Text("Изменить текст")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StudioTheme.background)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(StudioTheme.mint, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
        Button {
            showEvents = true
        } label: {
            Text("События")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StudioTheme.text)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(StudioTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editorTitleInContent {
                Text("Расшифровка")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack(spacing: 12) {
                playButton
                if !dynamicTypeSize.isAccessibilitySize { Text("Аудио").accessibilityHidden(true) }
                Spacer(minLength: 4)
                Text(timeText(playbackPosition) + " / " + timeText(playbackDuration))
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(StudioTheme.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            TextEditor(text: $transcript)
                .focused($editorFocused)
                .disabled(isBusy)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Текст расшифровки")
                .accessibilityIdentifier("transcriptEditor")
                .overlay(alignment: .topLeading) {
                    if transcript.isEmpty {
                        Text("Введите текст записи")
                            .padding(12)
                            .foregroundStyle(StudioTheme.secondary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .padding(8)
                .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            if hasChanges {
                Text("Черновик сохранён")
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(StudioTheme.secondary)
            }
            if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(StudioTheme.coral) }
        }
    }

    private var playbackPosition: TimeInterval { isLoaded ? recordingService.playbackPosition : 0 }
    private var playbackDuration: TimeInterval { isLoaded ? recordingService.playbackDuration : recording.duration ?? 0 }
    private var isPlaying: Bool { isLoaded && recordingService.isAudioPlaying }

    private var playButton: some View {
        Button {
            do { try recordingService.togglePlayback(id: recording.id) }
            catch { errorMessage = error.localizedDescription }
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 19)).frame(width: 44, height: 44)
                .foregroundStyle(StudioTheme.background).background(StudioTheme.mint, in: Circle())
        }
        .accessibilityLabel(isPlaying ? "Пауза" : "Прослушать")
        .disabled(recordingService.isRecording || recordingService.isStarting)
    }

    private var player: some View {
        VStack(spacing: 12) {
            HStack {
                playButton
                Slider(value: Binding(
                    get: { isSeeking ? seekPosition : playbackPosition },
                    set: { seekPosition = $0 }
                ), in: 0...max(0.1, playbackDuration), onEditingChanged: { editing in
                    if editing { seekPosition = playbackPosition }
                    else { recordingService.seekPlayback(to: seekPosition) }
                    isSeeking = editing
                })
                .disabled(!isLoaded).accessibilityLabel("Позиция аудио")
            }
            HStack {
                Text(timeText(playbackPosition))
                Spacer()
                Text(timeText(playbackDuration))
            }.font(.caption.monospacedDigit()).foregroundStyle(StudioTheme.secondary)
        }.padding(16).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func closeEditor() {
        editorFocused = false
        editingTranscript = false
    }

    private func timeText(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "—" }
        let seconds = max(0, Int(time))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func persistDraft(previousText: String? = nil) {
        if hasChanges { drafts.save(recordingID: recording.id, text: transcript) }
        else { drafts.remove(recordingID: recording.id, matching: previousText ?? transcript) }
    }

    @MainActor
    private func transcribe() async {
        let ownedDraft = drafts.load(recordingID: recording.id)
        isTranscribing = true
        errorMessage = nil
        defer { isTranscribing = false }
        do {
            let result = try await recordingService.transcribe(recordingID: recording.id)
            savedText = result
            transcript = result
            if let ownedDraft { drafts.remove(recordingID: recording.id, matching: ownedDraft) }
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    @discardableResult
    private func saveTranscript() -> Bool {
        do {
            try recordingService.saveEditedTranscript(recordingID: recording.id, text: transcript)
            savedText = transcript
            drafts.remove(recordingID: recording.id)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
