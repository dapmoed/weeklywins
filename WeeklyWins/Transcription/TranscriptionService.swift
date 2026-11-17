import Foundation

@MainActor
final class TranscriptionService {
    private let store: RecordingStore
    private let transcriber: any Transcriber
    private var processingIDs: Set<UUID> = []

    init(store: RecordingStore, transcriber: any Transcriber) {
        self.store = store
        self.transcriber = transcriber
    }

    func transcribe(
        recordingID: UUID,
        locale: Locale = Locale(identifier: "ru-RU"),
        onStarted: () -> Void = {},
        reportProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> String {
        try Task.checkCancellation()
        guard let recording = store.recordings.first(where: { $0.id == recordingID && $0.deletedAt == nil }) else {
            throw TranscriptionError.recordingNotFound
        }
        guard recording.state != .recording else { throw TranscriptionError.recordingStillActive }
        guard !processingIDs.contains(recordingID) else { throw TranscriptionError.alreadyProcessing }

        let audioURL = store.fileURL(for: recording)

        processingIDs.insert(recordingID)
        defer { processingIDs.remove(recordingID) }
        try store.updateTranscription(
            recordingID: recordingID,
            transcript: recording.transcript,
            processingState: .processing,
            errorMessage: nil
        )
        onStarted()

        do {
            guard FileManager.default.fileExists(atPath: audioURL.path) else { throw TranscriptionError.audioFileMissing }
            let transcript = try await transcriber.transcribe(audioFileURL: audioURL, locale: locale, reportProgress: reportProgress)
            try Task.checkCancellation()
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranscriptionError.noSpeechRecognized
            }
            try store.updateTranscription(
                recordingID: recordingID,
                transcript: transcript,
                processingState: .completed,
                errorMessage: nil
            )
            return transcript
        } catch {
            let shouldResume = recording.automaticTranscriptionPending == true
                && (error is CancellationError || error as? TranscriptionError == .speechAuthorizationRequired)
            try? store.updateTranscription(
                recordingID: recordingID,
                transcript: recording.transcript,
                processingState: shouldResume ? .pending : .failed,
                errorMessage: shouldResume ? "Расшифровка приостановлена; продолжится при открытии приложения." : error.localizedDescription
            )
            throw error
        }
    }

    func saveEditedTranscript(recordingID: UUID, text: String) throws {
        guard !processingIDs.contains(recordingID) else { throw TranscriptionError.alreadyProcessing }
        try store.updateTranscription(
            recordingID: recordingID,
            transcript: text,
            processingState: .completed,
            errorMessage: nil
        )
    }
}
