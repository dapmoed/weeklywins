import AVFoundation
import CryptoKit
import Foundation
import Network
import Speech
import UIKit
import XCTest
@testable import WeeklyWins

final class ASRAcceptanceTests: XCTestCase {
    @MainActor
    func testNativeRussianOneMinute() async throws {
        try await measureNativeTranscription(fileName: "ru-one-minute.m4a")
    }

    @MainActor
    func testNativeRussianFiveMinutes() async throws {
        try await measureNativeTranscription(fileName: "ru-five-minute.m4a")
    }

    @MainActor
    func testNativeRussianOfflineCorpus() async throws {
        try await measureNativeTranscription(fileName: "ru-one-minute.m4a", requireOffline: true)
        try await measureNativeTranscription(fileName: "ru-five-minute.m4a", requireOffline: true)
    }

    @MainActor
    func testNativeRussianNaturalCorpus() async throws {
        try requirePhysicalMeasurement("RUN_DEVICE_NATURAL_ASR")
        let directory = supportDirectory.appendingPathComponent("ASRNaturalCorpus", isDirectory: true)
        let fixtures = try loadFixtures(from: directory)
        XCTAssertFalse(fixtures.isEmpty)
        for fixture in fixtures {
            do {
                try await measureNativeTranscription(fixture, in: directory)
            } catch {
                XCTFail("\(fixture.file): \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func testNativeRussianIsolatedProblemWindow() async throws {
        #if targetEnvironment(simulator)
        let isPhysicalDevice = false
        #else
        let isPhysicalDevice = true
        #endif
        try XCTSkipUnless(isPhysicalDevice && ProcessInfo.processInfo.environment["RUN_DEVICE_ASR_ACCEPTANCE"] == "1")
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ASRAcceptance", isDirectory: true)
        let source = try AVAudioFile(forReading: directory.appendingPathComponent("ru-five-minute.m4a"))
        let rate = source.processingFormat.sampleRate
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var problem: LegacySpeechTranscription.Window?
        let url = temporary.appendingPathComponent("problem.wav")
        for second in stride(from: 0, through: 150, by: 50) {
            let start = Int64(Double(second) * rate)
            let end = start + Int64(50 * rate)
            let context = Int64(2 * rate)
            let window = LegacySpeechTranscription.Window(
                inputFrames: max(0, start - context)..<min(source.length, end + context),
                coreFrames: start..<end, totalFrames: source.length, sampleRate: rate
            )
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try LegacySpeechTranscription.write(window: window, from: source, to: url)
            problem = window
        }
        try Data(contentsOf: url).write(to: directory.appendingPathComponent("isolated-window.wav"), options: .atomic)
        let recognizer = try XCTUnwrap(SFSpeechRecognizer(locale: Locale(identifier: "ru-RU")))
        XCTAssertTrue(recognizer.supportsOnDeviceRecognition)
        XCTAssertEqual(SFSpeechRecognizer.authorizationStatus(), .authorized)
        let started = ProcessInfo.processInfo.systemUptime
        let result = try await OnDeviceSpeechTranscriber().recognizeLegacyWindow(
            url: url, window: try XCTUnwrap(problem), recognizer: recognizer, reportProgress: { _ in }
        )
        let report: [String: Any] = [
            "core_start": 150, "core_end": 200, "word_count": result.words.count,
            "first_timestamp": result.words.first?.timestamp ?? -1,
            "last_timestamp": result.words.last?.timestamp ?? -1,
            "transcript": result.text, "processing_seconds": ProcessInfo.processInfo.systemUptime - started,
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("isolated-window-report.json"), options: .atomic)
        XCTAssertGreaterThan(result.words.count, 40, "The isolated voiced window should contain its full speech.")
    }

    @MainActor
    private func measureNativeTranscription(fileName: String, requireOffline: Bool = false) async throws {
        try requirePhysicalMeasurement("RUN_DEVICE_ASR_ACCEPTANCE")
        let directory = supportDirectory.appendingPathComponent("ASRAcceptance", isDirectory: true)
        let fixture = try XCTUnwrap(loadFixtures(from: directory).first { $0.file == fileName })
        let text = try await measureNativeTranscription(fixture, in: directory, requireOffline: requireOffline)
        let reference = try String(contentsOf: directory.appendingPathComponent(fixture.referenceFile), encoding: .utf8)
        XCTAssertGreaterThanOrEqual(words(in: text).count, words(in: reference).count * 9 / 10, "The result may be incomplete.")
        if fileName == "ru-five-minute.m4a" {
            XCTAssertTrue(text.lowercased().contains("инструкц"), "The middle-of-recording task is missing.")
        }
        let ending = words(in: text).suffix(20).joined(separator: " ")
        XCTAssertNotNil(ending.range(of: #"\bпоследн\p{L}+\s+замет\p{L}+\b"#, options: .regularExpression),
                        "The ending marker is missing.")
    }

    private var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private func requirePhysicalMeasurement(_ flag: String) throws {
        #if targetEnvironment(simulator)
        let isPhysicalDevice = false
        #else
        let isPhysicalDevice = true
        #endif
        try XCTSkipUnless(
            isPhysicalDevice && ProcessInfo.processInfo.environment[flag] == "1",
            "Enable TEST_RUNNER_\(flag)=1 on the physical device with staged fixtures."
        )
    }

    private func loadFixtures(from directory: URL) throws -> [Fixture] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([Fixture].self, from: Data(contentsOf: directory.appendingPathComponent("fixtures.json")))
    }

    @MainActor @discardableResult
    private func measureNativeTranscription(_ fixture: Fixture, in directory: URL, requireOffline: Bool = false) async throws -> String {
        let audioURL = directory.appendingPathComponent(fixture.file)
        let audioData = try Data(contentsOf: audioURL)
        let hash = SHA256.hash(data: audioData).map { String(format: "%02x", $0) }.joined()
        guard hash == fixture.sha256 else { throw MeasurementError.fixtureMismatch }
        let reference = try String(contentsOf: directory.appendingPathComponent(fixture.referenceFile), encoding: .utf8)
        let referenceWords = words(in: reference)
        let file = try AVAudioFile(forReading: audioURL)

        let wasBatteryMonitoringEnabled = UIDevice.current.isBatteryMonitoringEnabled
        let wasIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            UIDevice.current.isBatteryMonitoringEnabled = wasBatteryMonitoringEnabled
            UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled
        }
        try await Task.sleep(for: .milliseconds(200))
        let locale = Locale(identifier: "ru-RU")
        var report: [String: Any] = [
            "provider": "OnDeviceSpeechTranscriber",
            "fixture": fixture.file,
            "sha256": hash,
            "reference_words": referenceWords.count,
            "audio_seconds": Double(file.length) / file.processingFormat.sampleRate,
            "audio_bytes": audioData.count,
            "device_model": UIDevice.current.model,
            "system_version": UIDevice.current.systemVersion,
            "app_build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "speech_authorization_before": SFSpeechRecognizer.authorizationStatus().rawValue,
            "offline_required": requireOffline,
        ]
        var started: TimeInterval?
        var transcript: String?
        var failure: NSError?
        do {
            if requireOffline {
                print("ASR_WAITING_FOR_OFFLINE \(fixture.file)")
                let waiting = ProcessInfo.processInfo.systemUptime
                let network = try await waitForOfflineNetwork()
                report["offline_wait_seconds"] = ProcessInfo.processInfo.systemUptime - waiting
                report["network_before"] = network.dictionary
            }
            let analyzerLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
            report["speech_analyzer_locale"] = analyzerLocale?.identifier ?? "unavailable"
            report["legacy_on_device_supported"] = SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition == true
            report["battery_before"] = UIDevice.current.batteryLevel
            report["charging_state_before"] = UIDevice.current.batteryState.rawValue
            report["thermal_state_before"] = ProcessInfo.processInfo.thermalState.rawValue
            report["started_at"] = Date().ISO8601Format()
            started = ProcessInfo.processInfo.systemUptime
            transcript = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await OnDeviceSpeechTranscriber().transcribe(audioFileURL: audioURL, locale: locale)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(180))
                    throw MeasurementError.timedOut
                }
                defer { group.cancelAll() }
                let result = try await group.next()
                return try XCTUnwrap(result)
            }
        } catch {
            failure = error as NSError
        }
        if let started { report["processing_seconds"] = ProcessInfo.processInfo.systemUptime - started }
        report["finished_at"] = Date().ISO8601Format()
        report["battery_after"] = UIDevice.current.batteryLevel
        report["charging_state_after"] = UIDevice.current.batteryState.rawValue
        report["thermal_state_after"] = ProcessInfo.processInfo.thermalState.rawValue
        if let transcript {
            report["transcript"] = transcript
            report["transcript_words"] = words(in: transcript).count
        }
        if let failure {
            report["error"] = ["domain": failure.domain, "code": failure.code, "message": failure.localizedDescription]
        }
        let resultURL = directory.appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent + ".native-report.json")
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: resultURL, options: .atomic)
        if let failure { throw failure }
        return try XCTUnwrap(transcript)
    }

    private func waitForOfflineNetwork() async throws -> NetworkSnapshot {
        let monitor = NWPathMonitor()
        let paths = AsyncStream<NetworkSnapshot> { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(NetworkSnapshot(
                    isOffline: path.status == .unsatisfied,
                    wifi: path.usesInterfaceType(.wifi),
                    cellular: path.usesInterfaceType(.cellular),
                    wired: path.usesInterfaceType(.wiredEthernet)
                ))
            }
            continuation.onTermination = { [weak monitor] _ in monitor?.cancel() }
            monitor.start(queue: DispatchQueue(label: "com.weeklywins.asr-offline-measurement"))
        }
        defer {
            monitor.cancel()
            monitor.pathUpdateHandler = nil
        }
        return try await withThrowingTaskGroup(of: NetworkSnapshot.self) { group in
            group.addTask {
                for await path in paths {
                    if path.isOffline { return path }
                }
                throw CancellationError()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(180))
                throw MeasurementError.offlineNotReached
            }
            defer { group.cancelAll() }
            let result = try await group.next()
            return try XCTUnwrap(result)
        }
    }

    private func words(in text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private struct Fixture: Decodable {
        let file: String
        let referenceFile: String
        let sha256: String
    }

    private struct NetworkSnapshot: Sendable {
        let isOffline: Bool
        let wifi: Bool
        let cellular: Bool
        let wired: Bool

        var dictionary: [String: Any] {
            ["is_offline": isOffline, "wifi": wifi, "cellular": cellular, "wired": wired]
        }
    }

    private enum MeasurementError: LocalizedError {
        case timedOut, offlineNotReached, fixtureMismatch
        var errorDescription: String? {
            switch self {
            case .timedOut: return "Native recognition did not finish within 180 seconds."
            case .offlineNotReached: return "The device did not reach an offline network state within 180 seconds."
            case .fixtureMismatch: return "The staged audio hash does not match its fixture manifest."
            }
        }
    }
}
