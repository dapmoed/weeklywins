import AVFoundation
import Foundation
import Speech

protocol Transcriber: Sendable {
    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String
}

struct OnDeviceSpeechTranscriber: Transcriber {
    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw TranscriptionError.audioFileMissing
        }

        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return try await transcribeWithLegacyOnDeviceRecognizer(audioFileURL: audioFileURL, locale: locale)
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .transcription)
        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        guard assetStatus != .unsupported else {
            return try await transcribeWithLegacyOnDeviceRecognizer(audioFileURL: audioFileURL, locale: locale)
        }

        if assetStatus != .installed {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                throw TranscriptionError.onDeviceModelUnavailable(supportedLocale.identifier)
            }
            try await request.downloadAndInstall()
        }

        try await ensureSpeechAuthorization()
        return try await transcribeWithSpeechAnalyzer(audioFileURL: audioFileURL, transcriber: transcriber)
    }

    private func transcribeWithSpeechAnalyzer(
        audioFileURL: URL,
        transcriber: SpeechTranscriber
    ) async throws -> String {
        let audioFile = try AVAudioFile(forReading: audioFileURL)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: audioFile.processingFormat)

        let resultsTask = Task {
            var chunks: [String] = []
            for try await result in transcriber.results {
                chunks.append(String(result.text.characters))
            }
            return chunks.joined()
        }

        do {
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = try await resultsTask.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw TranscriptionError.noSpeechRecognized }
            return text
        } catch {
            resultsTask.cancel()
            await analyzer.cancelAndFinishNow()
            _ = try? await resultsTask.value
            throw error
        }
    }

    @MainActor
    private func transcribeWithLegacyOnDeviceRecognizer(audioFileURL: URL, locale: Locale) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.unsupportedLocale(locale.identifier)
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceModelUnavailable(locale.identifier)
        }
        try await ensureSpeechAuthorization()

        let request = SFSpeechURLRecognitionRequest(url: audioFileURL)
        request.requiresOnDeviceRecognition = true
        return try await SpeechRecognitionSession().run { finish in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    finish(.failure(error))
                } else if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty { finish(.failure(TranscriptionError.noSpeechRecognized)) }
                    else { finish(.success(text)) }
                }
            }
            return { task.cancel() }
        }
    }

    private func ensureSpeechAuthorization() async throws {
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard authorization == .authorized else {
            throw TranscriptionError.speechAuthorizationDenied
        }
    }
}

enum TranscriptionError: LocalizedError, Equatable {
    case audioFileMissing
    case speechAuthorizationDenied
    case unsupportedLocale(String)
    case onDeviceModelUnavailable(String)
    case noSpeechRecognized
    case recordingNotFound
    case recordingStillActive
    case alreadyProcessing

    var errorDescription: String? {
        switch self {
        case .audioFileMissing: return "Аудиофайл записи не найден."
        case .speechAuthorizationDenied: return "Нет разрешения на распознавание речи."
        case .unsupportedLocale(let locale): return "Русский язык не поддерживается: \(locale)."
        case .onDeviceModelUnavailable(let locale): return "Офлайн-модель речи недоступна для языка \(locale)."
        case .noSpeechRecognized: return "В записи не удалось распознать речь."
        case .recordingNotFound: return "Запись не найдена."
        case .recordingStillActive: return "Сначала остановите запись, затем запускайте расшифровку."
        case .alreadyProcessing: return "Расшифровка этой записи уже выполняется."
        }
    }
}
