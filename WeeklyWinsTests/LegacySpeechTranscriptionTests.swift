import AVFoundation
import XCTest
@testable import WeeklyWins

final class LegacySpeechTranscriptionTests: XCTestCase {
    @MainActor
    func testLongAudioUsesBoundedContextWindowsAndRetainsSource() async throws {
        let source = try makeAudio(seconds: 125)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let original = try Data(contentsOf: source)
        var files: [URL] = []
        var windows: [LegacySpeechTranscription.Window] = []
        let text = try await LegacySpeechTranscription.transcribe(audioFileURL: source) { url, window in
            files.append(url)
            windows.append(window)
            let chunk = try AVAudioFile(forReading: url)
            XCTAssertEqual(chunk.length, window.inputFrames.upperBound - window.inputFrames.lowerBound)
            XCTAssertLessThanOrEqual(Double(chunk.length) / chunk.processingFormat.sampleRate, 54)
            return self.transcript("часть\(window.coreFrames.lowerBound / 16_000)", window: window)
        }
        XCTAssertEqual(text, "часть0 часть50 часть100")
        XCTAssertEqual(windows.map(\.coreFrames), [0..<800_000, 800_000..<1_600_000, 1_600_000..<2_000_000])
        XCTAssertEqual(windows.map(\.inputFrames), [0..<832_000, 768_000..<1_632_000, 1_568_000..<2_000_000])
        XCTAssertTrue(files.allSatisfy { $0 != source && !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    @MainActor
    func testShortAudioUsesItsOriginalFile() async throws {
        let source = try makeAudio(seconds: 1)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let text = try await LegacySpeechTranscription.transcribe(audioFileURL: source) { url, _ in
            XCTAssertEqual(url, source)
            return .init(text: "Короткая запись.", words: [])
        }
        XCTAssertEqual(text, "Короткая запись.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testFailureDiscardsPartialTextAndRemovesTemporaryAudio() async throws {
        let source = try makeAudio(seconds: 125)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        var files: [URL] = []
        do {
            _ = try await LegacySpeechTranscription.transcribe(audioFileURL: source) { url, window in
                files.append(url)
                if window.coreFrames.lowerBound > 0 { throw TestError.failed }
                return self.transcript("Первый фрагмент.", window: window)
            }
            XCTFail("The failed second window must fail the complete transcription.")
        } catch { XCTAssertTrue(error is TestError) }
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testCancellationStopsBeforeTheNextWindowAndCleansUp() async throws {
        let source = try makeAudio(seconds: 125)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let started = expectation(description: "First window started")
        var files: [URL] = []
        let task = Task {
            try await LegacySpeechTranscription.transcribe(audioFileURL: source) { url, _ in
                files.append(url)
                started.fulfill()
                try await Task.sleep(for: .seconds(30))
                return .init(text: "Отменённый результат.", words: [])
            }
        }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled transcription must throw.")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testSilentWindowsPreserveOtherRecognizedSpeech() async throws {
        let source = try makeAudio(seconds: 125)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let text = try await LegacySpeechTranscription.transcribe(audioFileURL: source) { _, window in
            if window.coreFrames.lowerBound == 800_000 { throw TranscriptionError.noSpeechRecognized }
            return self.transcript("часть\(window.coreFrames.lowerBound / 16_000)", window: window)
        }
        XCTAssertEqual(text, "часть0 часть100")
    }

    func testTranscriptExcerptPreservesPunctuationAndOriginalOffsets() throws {
        let window = LegacySpeechTranscription.Window(
            inputFrames: 48..<102, coreFrames: 50..<100, totalFrames: 125, sampleRate: 1
        )
        let text = "  старое. Новое дело, завершено!  "
        let source = text as NSString
        let words = [
            LegacySpeechTranscription.Word(range: source.range(of: "старое"), timestamp: 1, duration: 0.2),
            .init(range: source.range(of: "Новое"), timestamp: 1.8, duration: 0.4),
            .init(range: source.range(of: "дело"), timestamp: 3, duration: 0.2),
            .init(range: source.range(of: "завершено"), timestamp: 52, duration: 0.2),
        ]
        let result = LegacySpeechTranscription.Transcript(text: text, words: words)
        XCTAssertEqual(try result.excerpt(from: 1, to: 3), "Новое дело,")
        XCTAssertEqual(window.progress(at: -1), 50.0 / 125)
        XCTAssertEqual(window.progress(at: 100), 100.0 / 125)
    }

    func testMalformedWordRangeFailsWithoutCrashing() {
        let result = LegacySpeechTranscription.Transcript(text: "Текст", words: [
            .init(range: NSRange(location: NSNotFound, length: 1), timestamp: 3, duration: 0.2)
        ])
        XCTAssertThrowsError(try result.excerpt(from: 0, to: 1))
    }

    func testOverlapAnchorKeepsOneBoundaryWordDespiteTimingDisagreement() throws {
        for oldTime in [49.5, 50.1] {
            let newTime = oldTime < 50 ? 1.9 : 1.7
            var merger = LegacyTranscriptMerger()
            let oldText = "начало стык"
            let newText = "стык конец"
            let old = LegacySpeechTranscription.Transcript(text: oldText, words: [
                .init(range: (oldText as NSString).range(of: "начало"), timestamp: 1, duration: 0.2),
                .init(range: (oldText as NSString).range(of: "стык"), timestamp: oldTime, duration: 0.4),
            ])
            let new = LegacySpeechTranscription.Transcript(text: newText, words: [
                .init(range: (newText as NSString).range(of: "стык"), timestamp: newTime, duration: 0.4),
                .init(range: (newText as NSString).range(of: "конец"), timestamp: 2.2, duration: 1.6),
            ])
            try merger.append(old, window: .init(inputFrames: 0..<52, coreFrames: 0..<50, totalFrames: 100, sampleRate: 1))
            try merger.append(new, window: .init(inputFrames: 48..<100, coreFrames: 50..<100, totalFrames: 100, sampleRate: 1))
            XCTAssertEqual(try merger.finish(), "начало стык конец")
        }
    }

    func testMatchingWordPairPreservesAnActualRepeatedWord() throws {
        var merger = LegacyTranscriptMerger()
        let old = LegacySpeechTranscription.Transcript(text: "начало да, да.", words: [
            .init(range: NSRange(location: 0, length: 6), timestamp: 1, duration: 0.2),
            .init(range: NSRange(location: 7, length: 2), timestamp: 49, duration: 0.2),
            .init(range: NSRange(location: 11, length: 2), timestamp: 49.4, duration: 0.2),
        ])
        let new = LegacySpeechTranscription.Transcript(text: "да, да. конец", words: [
            .init(range: NSRange(location: 0, length: 2), timestamp: 1.05, duration: 0.2),
            .init(range: NSRange(location: 4, length: 2), timestamp: 1.45, duration: 0.2),
            .init(range: NSRange(location: 8, length: 5), timestamp: 3, duration: 0.2),
        ])
        try merger.append(old, window: .init(inputFrames: 0..<52, coreFrames: 0..<50, totalFrames: 100, sampleRate: 1))
        try merger.append(new, window: .init(inputFrames: 48..<100, coreFrames: 50..<100, totalFrames: 100, sampleRate: 1))
        XCTAssertEqual(try merger.finish(), "начало да, да. конец")
    }

    func testLeftContextOnlyWindowKeepsThePreviouslyRecognizedTail() throws {
        for includeNextWindow in [false, true] {
            var merger = LegacyTranscriptMerger()
            let text = "начало важное"
            let previous = LegacySpeechTranscription.Transcript(text: text, words: [
                .init(range: (text as NSString).range(of: "начало"), timestamp: 1, duration: 0.2),
                .init(range: (text as NSString).range(of: "важное"), timestamp: 51, duration: 0.2),
            ])
            try merger.append(previous, window: .init(inputFrames: 0..<52, coreFrames: 0..<50, totalFrames: 125, sampleRate: 1))
            let contextOnly = LegacySpeechTranscription.Transcript(text: "ошибка", words: [
                .init(range: NSRange(location: 0, length: 6), timestamp: 0.5, duration: 0.2)
            ])
            try merger.append(contextOnly, window: .init(inputFrames: 48..<102, coreFrames: 50..<100, totalFrames: 125, sampleRate: 1))
            if includeNextWindow {
                let window = LegacySpeechTranscription.Window(inputFrames: 98..<125, coreFrames: 100..<125, totalFrames: 125, sampleRate: 1)
                try merger.append(transcript("конец", window: window), window: window)
            }
            XCTAssertEqual(try merger.finish(), includeNextWindow ? "начало важное конец" : "начало важное")
        }
    }

    @MainActor
    func testFiveMinuteAudioIncludesItsFinalWindow() async throws {
        let source = try makeAudio(seconds: 300)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        var count = 0
        let text = try await LegacySpeechTranscription.transcribe(audioFileURL: source) { _, window in
            count += 1
            let text = window.coreFrames.upperBound == 4_800_000 ? "последняя фраза" : "дело"
            return self.transcript(text, window: window)
        }
        XCTAssertEqual(count, 6)
        XCTAssertTrue(text.hasSuffix("последняя фраза"))
    }

    @MainActor
    func testFirstAndLastSilentWindowsPreserveTheMiddle() async throws {
        let source = try makeAudio(seconds: 125)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let text = try await LegacySpeechTranscription.transcribe(audioFileURL: source) { _, window in
            guard window.coreFrames.lowerBound == 800_000 else { throw TranscriptionError.noSpeechRecognized }
            return self.transcript("Сделал дело.", window: window)
        }
        XCTAssertEqual(text, "Сделал дело.")
    }

    @MainActor
    func testAllSilentWindowsReturnNoSpeechAndKeepTheSource() async throws {
        let source = try makeAudio(seconds: 125)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        do {
            _ = try await LegacySpeechTranscription.transcribe(audioFileURL: source) { _, _ in
                throw TranscriptionError.noSpeechRecognized
            }
            XCTFail("An entirely silent file must report no speech.")
        } catch { XCTAssertEqual(error as? TranscriptionError, .noSpeechRecognized) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testRecordedAACAudioIsDecodedIntoCompletePCMWindows() async throws {
        let source = try makeAudio(seconds: 60, aac: true)
        defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
        let original = try Data(contentsOf: source)
        let length = try AVAudioFile(forReading: source).length
        var lastFrame: Int64 = 0
        _ = try await LegacySpeechTranscription.transcribe(audioFileURL: source) { url, window in
            let decoded = try AVAudioFile(forReading: url)
            XCTAssertEqual(decoded.length, window.inputFrames.upperBound - window.inputFrames.lowerBound)
            XCTAssertEqual(window.coreFrames.lowerBound, lastFrame)
            lastFrame = window.coreFrames.upperBound
            return self.transcript("Дело.", window: window)
        }
        XCTAssertEqual(lastFrame, length)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    private func transcript(_ text: String, window: LegacySpeechTranscription.Window) -> LegacySpeechTranscription.Transcript {
        let timestamp = Double(window.coreFrames.lowerBound - window.inputFrames.lowerBound) / window.sampleRate + 0.1
        return .init(text: text, words: [.init(range: NSRange(location: 0, length: (text as NSString).length),
                                              timestamp: timestamp, duration: 0.1)])
    }

    private func makeAudio(seconds: Int, aac: Bool = false) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(aac ? "source.m4a" : "source.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData?[0].initialize(repeating: 0.01, count: Int(buffer.frameLength))
        let settings: [String: Any] = aac ? [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000
        ] : format.settings
        let file = try AVAudioFile(forWriting: url, settings: settings)
        for _ in 0..<seconds { try file.write(from: buffer) }
        return url
    }

    private enum TestError: Error { case failed }
}
