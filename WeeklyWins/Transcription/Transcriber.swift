import AVFoundation
import Foundation
import Speech
import UIKit

protocol Transcriber: Sendable {
    var canTranscribeWithoutAuthorizationPrompt: Bool { get }
    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String
    func transcribe(audioFileURL: URL, locale: Locale, reportProgress: @escaping @Sendable (Double) -> Void) async throws -> String
}

extension Transcriber {
    var canTranscribeWithoutAuthorizationPrompt: Bool { true }

    func transcribe(audioFileURL: URL, locale: Locale, reportProgress: @escaping @Sendable (Double) -> Void) async throws -> String {
        let text = try await transcribe(audioFileURL: audioFileURL, locale: locale)
        reportProgress(1)
        return text
    }
}

struct OnDeviceSpeechTranscriber: Transcriber {
    var canTranscribeWithoutAuthorizationPrompt: Bool {
        SFSpeechRecognizer.authorizationStatus() != .notDetermined
    }

    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String {
        try await transcribe(audioFileURL: audioFileURL, locale: locale, reportProgress: { _ in })
    }

    func transcribe(audioFileURL: URL, locale: Locale, reportProgress: @escaping @Sendable (Double) -> Void) async throws -> String {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw TranscriptionError.audioFileMissing
        }

        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return try await transcribeWithLegacyOnDeviceRecognizer(audioFileURL: audioFileURL, locale: locale, reportProgress: reportProgress)
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .transcription)
        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        guard assetStatus != .unsupported else {
            return try await transcribeWithLegacyOnDeviceRecognizer(audioFileURL: audioFileURL, locale: locale, reportProgress: reportProgress)
        }

        if assetStatus != .installed {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                throw TranscriptionError.onDeviceModelUnavailable(supportedLocale.identifier)
            }
            try await request.downloadAndInstall()
        }

        try await ensureSpeechAuthorization()
        return try await transcribeWithSpeechAnalyzer(audioFileURL: audioFileURL, transcriber: transcriber, reportProgress: reportProgress)
    }

    private func transcribeWithSpeechAnalyzer(
        audioFileURL: URL,
        transcriber: SpeechTranscriber,
        reportProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        let audioFile = try AVAudioFile(forReading: audioFileURL)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        let resultsTask = Task {
            var chunks: [String] = []
            for try await result in transcriber.results {
                chunks.append(String(result.text.characters))
                let processed = CMTimeRangeGetEnd(result.range).seconds
                if duration > 0, processed.isFinite { reportProgress(min(1, max(0, processed / duration))) }
            }
            return chunks.joined()
        }

        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                try await analyzer.prepareToAnalyze(in: audioFile.processingFormat)
                try Task.checkCancellation()
                try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                let text = try await resultsTask.value.trimmingCharacters(in: .whitespacesAndNewlines)
                try Task.checkCancellation()
                guard !text.isEmpty else { throw TranscriptionError.noSpeechRecognized }
                return text
            } catch {
                resultsTask.cancel()
                await analyzer.cancelAndFinishNow()
                _ = try? await resultsTask.value
                throw error
            }
        } onCancel: {
            resultsTask.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    @MainActor
    private func transcribeWithLegacyOnDeviceRecognizer(
        audioFileURL: URL,
        locale: Locale,
        reportProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.unsupportedLocale(locale.identifier)
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.onDeviceModelUnavailable(locale.identifier)
        }
        try await ensureSpeechAuthorization()

        return try await LegacySpeechTranscription.transcribe(audioFileURL: audioFileURL, reportProgress: reportProgress) { url, window in
            let start = Double(window.coreFrames.lowerBound) / window.sampleRate
            let end = Double(window.coreFrames.upperBound) / window.sampleRate
            do {
                let result = try await recognizeLegacyWindow(url: url, window: window, recognizer: recognizer, reportProgress: reportProgress)
                RecordingDiagnostics.write("legacy ASR core=\(start)-\(end) words=\(result.words.count) timing=\(result.words.first?.timestamp ?? -1)-\(result.words.last?.timestamp ?? -1)")
                return result
            } catch {
                let failure = error as NSError
                RecordingDiagnostics.write("legacy ASR core=\(start)-\(end) failed domain=\(failure.domain) code=\(failure.code)")
                throw error
            }
        }
    }

    @MainActor
    func recognizeLegacyWindow(
        url: URL,
        window: LegacySpeechTranscription.Window,
        recognizer: SFSpeechRecognizer,
        reportProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> LegacySpeechTranscription.Transcript {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        let accumulator = LegacySpeechResultAccumulator()
        return try await SpeechRecognitionResultSession<LegacySpeechTranscription.Transcript>().run { finish in
            let (updates, continuation) = AsyncStream<LegacyRecognitionEvent>.makeStream()
            let consumer = Task { @MainActor in
                defer { continuation.finish() }
                var progress = Double(window.coreFrames.lowerBound) / Double(window.totalFrames)
                for await event in updates {
                    if let error = event.error {
                        let nativeError = error as NSError
                        // Apple's 1110 code identifies a window without recognized speech.
                        let noSpeech = nativeError.domain == "kAFAssistantErrorDomain" && nativeError.code == 1110
                        finish(.failure(noSpeech && !accumulator.hasTimedSpeech ? TranscriptionError.noSpeechRecognized : error))
                        return
                    }
                    guard let snapshot = event.snapshot else { continue }
                    if let last = snapshot.words.last, last.timestamp > 0 || last.duration > 0 {
                        progress = max(progress, window.progress(at: last.timestamp + last.duration))
                        reportProgress(progress)
                    }
                    do {
                        if let complete = try accumulator.update(snapshot, isFinal: event.isFinal) {
                            if complete.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                finish(.failure(TranscriptionError.noSpeechRecognized))
                            } else {
                                finish(.success(complete))
                            }
                            return
                        }
                    } catch {
                        finish(.failure(error))
                        return
                    }
                }
            }
            let task = recognizer.recognitionTask(with: request) { result, error in
                let snapshot = result.map { result in
                    LegacySpeechTranscription.Transcript(
                        text: result.bestTranscription.formattedString,
                        words: result.bestTranscription.segments.map {
                            .init(range: $0.substringRange, timestamp: $0.timestamp, duration: $0.duration)
                        }
                    )
                }
                continuation.yield(LegacyRecognitionEvent(snapshot: snapshot, isFinal: result?.isFinal == true, error: error))
            }
            return {
                task.cancel()
                continuation.finish()
                consumer.cancel()
            }
        }
    }

    private struct LegacyRecognitionEvent: Sendable {
        let snapshot: LegacySpeechTranscription.Transcript?
        let isFinal: Bool
        let error: Error?
    }

    @MainActor
    private func ensureSpeechAuthorization() async throws {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return }
        guard current == .notDetermined else { throw TranscriptionError.speechAuthorizationDenied }
        guard UIApplication.shared.applicationState == .active else { throw TranscriptionError.speechAuthorizationRequired }
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
    case speechAuthorizationRequired
    case unsupportedLocale(String)
    case onDeviceModelUnavailable(String)
    case noSpeechRecognized
    case recordingNotFound
    case recordingStillActive
    case alreadyProcessing
    case audioReadFailed
    case invalidRecognitionResult

    var errorDescription: String? {
        switch self {
        case .audioFileMissing: return "Аудиофайл записи не найден."
        case .speechAuthorizationDenied: return "Нет разрешения на распознавание речи."
        case .speechAuthorizationRequired: return "Откройте приложение, чтобы разрешить распознавание речи."
        case .unsupportedLocale(let locale): return "Русский язык не поддерживается: \(locale)."
        case .onDeviceModelUnavailable(let locale): return "Офлайн-модель речи недоступна для языка \(locale)."
        case .noSpeechRecognized: return "В записи не удалось распознать речь."
        case .recordingNotFound: return "Запись не найдена."
        case .recordingStillActive: return "Сначала остановите запись, затем запускайте расшифровку."
        case .alreadyProcessing: return "Расшифровка уже выполняется. Дождитесь её завершения."
        case .audioReadFailed: return "Не удалось прочитать аудиозапись."
        case .invalidRecognitionResult: return "Не удалось обработать результат распознавания речи. Повторите расшифровку."
        }
    }
}
