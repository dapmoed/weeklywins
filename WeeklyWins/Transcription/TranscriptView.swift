import SwiftUI

struct TranscriptView: View {
    let recording: Recording
    @ObservedObject var recordingService: RecordingService

    @Environment(\.dismiss) private var dismiss
    @State private var transcript: String
    @State private var isTranscribing = false
    @State private var errorMessage: String?

    init(recording: Recording, recordingService: RecordingService) {
        self.recording = recording
        self.recordingService = recordingService
        _transcript = State(initialValue: recording.transcript ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(recording.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(recordingService.playingRecordingID == recording.id ? "Остановить аудио" : "Прослушать") {
                    do {
                        if recordingService.playingRecordingID == recording.id {
                            recordingService.stopPlayback()
                        } else {
                            try recordingService.playRecording(id: recording.id)
                        }
                    } catch { errorMessage = error.localizedDescription }
                }
                .disabled(recordingService.isRecording || recordingService.isStarting)

                TextEditor(text: $transcript)
                    .disabled(isTranscribing)
                    .accessibilityIdentifier("transcriptEditor")
                    .overlay {
                        if transcript.isEmpty {
                            Text("Здесь появится расшифровка записи")
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(isTranscribing ? "Расшифровывается…" : "Расшифровать") {
                    Task { await transcribe() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTranscribing)

                NavigationLink("События") {
                    EventReviewView(
                        recording: recordingService.recordings.first(where: { $0.id == recording.id }) ?? recording,
                        service: recordingService
                    )
                }

                Button("Сохранить текст") {
                    saveTranscript()
                }
                .disabled(isTranscribing || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .onDisappear { recordingService.stopPlayback() }
            .navigationTitle("Расшифровка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func transcribe() async {
        isTranscribing = true
        errorMessage = nil
        defer { isTranscribing = false }

        do {
            transcript = try await recordingService.transcribe(recordingID: recording.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveTranscript() {
        do {
            try recordingService.saveEditedTranscript(recordingID: recording.id, text: transcript)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
