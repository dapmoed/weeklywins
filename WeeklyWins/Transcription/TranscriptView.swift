import SwiftUI

struct TranscriptView: View {
    let recording: Recording
    @ObservedObject var recordingService: RecordingService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var transcript: String
    @State private var savedText: String
    @State private var isTranscribing = false
    @State private var errorMessage: String?
    @State private var confirmClose = false
    @State private var confirmTranscription = false
    @State private var confirmEvents = false
    @State private var showEvents = false
    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0
    private let drafts = TranscriptDraftStore()

    init(recording: Recording, recordingService: RecordingService) {
        self.recording = recording
        self.recordingService = recordingService
        _savedText = State(initialValue: recording.transcript ?? "")
        _transcript = State(initialValue: TranscriptDraftStore().load(recordingID: recording.id) ?? recording.transcript ?? "")
    }

    private var isBusy: Bool { isTranscribing || recordingService.transcribingRecordingIDs.contains(recording.id) }
    private var hasChanges: Bool { transcript != savedText }
    private var isLoaded: Bool { recordingService.playingRecordingID == recording.id }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Записано \(recording.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline).foregroundStyle(StudioTheme.secondary)
                player
                TextEditor(text: $transcript)
                    .disabled(isBusy)
                    .scrollContentBackground(.hidden)
                    .accessibilityIdentifier("transcriptEditor")
                    .overlay(alignment: .topLeading) {
                        if transcript.isEmpty {
                            Text("Здесь появится расшифровка записи")
                                .padding(12).foregroundStyle(StudioTheme.secondary).allowsHitTesting(false)
                        }
                    }
                    .padding(8).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                if hasChanges { Text("Черновик сохранён").font(.caption).foregroundStyle(StudioTheme.secondary) }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(StudioTheme.coral) }
                HStack {
                    Button(isBusy ? "Расшифровывается…" : "Расшифровать") {
                        if hasChanges { confirmTranscription = true }
                        else { Task { await transcribe() } }
                    }
                    .buttonStyle(.borderedProminent).disabled(isBusy)
                    Spacer()
                    Button("События") {
                        if hasChanges { confirmEvents = true }
                        else { showEvents = true }
                    }.disabled(isBusy)
                }
                Button("Сохранить текст") { _ = saveTranscript() }
                    .disabled(isBusy || !hasChanges)
                    .frame(minHeight: 44)
            }
            .padding(20).background(StudioTheme.background).foregroundStyle(StudioTheme.text)
            .navigationTitle("Расшифровка").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showEvents) {
                EventReviewView(recording: currentRecording, service: recordingService)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        if hasChanges { confirmClose = true }
                        else { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(hasChanges)
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
                Button("Сохранить и закрыть") { if saveTranscript() { dismiss() } }
                Button("Отбросить изменения", role: .destructive) {
                    drafts.remove(recordingID: recording.id)
                    dismiss()
                }
            }
            .confirmationDialog("Открыть события", isPresented: $confirmEvents, titleVisibility: .visible) {
                Button("Сохранить текст и открыть") { if saveTranscript() { showEvents = true } }
                Button("Открыть сохранённые события") { showEvents = true }
            }
            .confirmationDialog("Заменить черновик новой расшифровкой?", isPresented: $confirmTranscription, titleVisibility: .visible) {
                Button("Расшифровать заново", role: .destructive) { Task { await transcribe() } }
            }
        }.tint(StudioTheme.mint).preferredColorScheme(.dark)
    }

    private var currentRecording: Recording {
        recordingService.recordings.first(where: { $0.id == recording.id }) ?? recording
    }

    private var player: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    do { try recordingService.togglePlayback(id: recording.id) }
                    catch { errorMessage = error.localizedDescription }
                } label: {
                    Image(systemName: isLoaded && recordingService.isAudioPlaying ? "pause.fill" : "play.fill")
                        .font(.title3).frame(width: 48, height: 48)
                        .foregroundStyle(StudioTheme.background).background(StudioTheme.mint, in: Circle())
                }
                .accessibilityLabel(isLoaded && recordingService.isAudioPlaying ? "Пауза" : "Прослушать")
                .disabled(recordingService.isRecording || recordingService.isStarting)
                Slider(value: Binding(
                    get: { isSeeking ? seekPosition : isLoaded ? recordingService.playbackPosition : 0 },
                    set: { seekPosition = $0 }
                ), in: 0...max(0.1, isLoaded ? recordingService.playbackDuration : recording.duration ?? 0.1), onEditingChanged: { editing in
                    if editing { seekPosition = recordingService.playbackPosition }
                    else { recordingService.seekPlayback(to: seekPosition) }
                    isSeeking = editing
                })
                .disabled(!isLoaded).accessibilityLabel("Позиция аудио")
            }
            HStack {
                Text(timeText(isLoaded ? recordingService.playbackPosition : 0))
                Spacer()
                Text(timeText(isLoaded ? recordingService.playbackDuration : recording.duration ?? 0))
            }.font(.caption.monospacedDigit()).foregroundStyle(StudioTheme.secondary)
        }.padding(16).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
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
