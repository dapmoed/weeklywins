import AVFoundation
import Foundation

enum LegacySpeechTranscription {
    struct Word: Sendable {
        let range: NSRange
        let timestamp: TimeInterval
        let duration: TimeInterval
    }

    struct Window: Sendable {
        let inputFrames: Range<Int64>
        let coreFrames: Range<Int64>
        let totalFrames: Int64
        let sampleRate: Double

        func progress(at timestamp: TimeInterval) -> Double {
            let absoluteFrame = Double(inputFrames.lowerBound) + timestamp * sampleRate
            let frame = min(Double(coreFrames.upperBound), max(Double(coreFrames.lowerBound), absoluteFrame))
            return frame / Double(totalFrames)
        }

    }

    static func transcribe(
        audioFileURL: URL,
        reportProgress: @escaping @Sendable (Double) -> Void = { _ in },
        recognize: @escaping @MainActor (URL, Window) async throws -> Transcript
    ) async throws -> String {
        try Task.checkCancellation()
        let source = try AVAudioFile(forReading: audioFileURL)
        let sampleRate = source.processingFormat.sampleRate
        guard source.length > 0 else { throw TranscriptionError.noSpeechRecognized }
        guard sampleRate.isFinite, sampleRate > 0 else { throw TranscriptionError.audioReadFailed }
        let coreLength = max(1, Int64(sampleRate * 50))
        if source.length <= coreLength {
            let window = Window(inputFrames: 0..<source.length, coreFrames: 0..<source.length,
                                totalFrames: source.length, sampleRate: sampleRate)
            let result = try await recognize(audioFileURL, window)
            try Task.checkCancellation()
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw TranscriptionError.noSpeechRecognized }
            return text
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("weeklywins-speech-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let contextLength = Int64(sampleRate * 2)
        var merger = LegacyTranscriptMerger()
        for coreStart in stride(from: Int64(0), to: source.length, by: Int(coreLength)) {
            try Task.checkCancellation()
            let coreEnd = min(source.length, coreStart + coreLength)
            let window = Window(
                inputFrames: max(0, coreStart - contextLength)..<min(source.length, coreEnd + contextLength),
                coreFrames: coreStart..<coreEnd, totalFrames: source.length, sampleRate: sampleRate
            )
            let url = directory.appendingPathComponent("segment-\(coreStart).wav")
            try write(window: window, from: source, to: url)
            do {
                let result = try await recognize(url, window)
                try Task.checkCancellation()
                try merger.append(result, window: window)
            } catch TranscriptionError.noSpeechRecognized {
                try Task.checkCancellation()
            }
            reportProgress(Double(coreEnd) / Double(source.length))
        }
        let text = try merger.finish()
        guard !text.isEmpty else { throw TranscriptionError.noSpeechRecognized }
        return text
    }

    static func write(window: Window, from source: AVAudioFile, to url: URL) throws {
        try autoreleasepool {
            let format = source.processingFormat
            let output = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            try FileManager.default.setAttributes([
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ], ofItemAtPath: url.path)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
                throw TranscriptionError.audioReadFailed
            }
            source.framePosition = window.inputFrames.lowerBound
            var remaining = window.inputFrames.upperBound - window.inputFrames.lowerBound
            while remaining > 0 {
                try Task.checkCancellation()
                try source.read(into: buffer, frameCount: AVAudioFrameCount(min(4096, remaining)))
                guard buffer.frameLength > 0 else { throw TranscriptionError.audioReadFailed }
                try output.write(from: buffer)
                remaining -= Int64(buffer.frameLength)
            }
        }
    }
}
