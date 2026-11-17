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
    private func measureNativeTranscription(fileName: String, requireOffline: Bool = false) async throws {
        #if targetEnvironment(simulator)
        let isPhysicalDevice = false
        #else
        let isPhysicalDevice = true
        #endif
        try XCTSkipUnless(
            isPhysicalDevice && ProcessInfo.processInfo.environment["RUN_DEVICE_ASR_ACCEPTANCE"] == "1",
            "Enable TEST_RUNNER_RUN_DEVICE_ASR_ACCEPTANCE=1 on the physical device with staged fixtures."
        )

        let directory = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
            .appendingPathComponent("ASRAcceptance", isDirectory: true)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let fixtures = try decoder.decode([Fixture].self, from: Data(contentsOf: directory.appendingPathComponent("fixtures.json")))
        let fixture = try XCTUnwrap(fixtures.first { $0.file == fileName })
        let audioURL = directory.appendingPathComponent(fixture.file)
        let audioData = try Data(contentsOf: audioURL)
        let hash = SHA256.hash(data: audioData).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hash, fixture.sha256)
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
        let text = try XCTUnwrap(transcript)
        XCTAssertGreaterThanOrEqual(words(in: text).count, referenceWords.count * 4 / 5, "The result may be incomplete.")
        let ending = words(in: text).suffix(20).joined(separator: " ")
        XCTAssertNotNil(ending.range(of: #"\bпоследн\p{L}+\s+замет\p{L}+\b"#, options: .regularExpression),
                        "The ending marker is missing.")
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
        case timedOut, offlineNotReached
        var errorDescription: String? {
            switch self {
            case .timedOut: return "Native recognition did not finish within 180 seconds."
            case .offlineNotReached: return "The device did not reach an offline network state within 180 seconds."
            }
        }
    }
}
