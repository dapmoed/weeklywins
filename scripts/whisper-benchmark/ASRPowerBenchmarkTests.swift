import CryptoKit
import UIKit
import XCTest
import os
@testable import WeeklyWins

final class ASRPowerBenchmarkTests: XCTestCase {
    private enum Workload: String {
        case idle, apple, whisper
    }

    private struct Fixture: Decodable {
        let file: String
        let sha256: String
    }

    @MainActor
    func testMatchedBatteryWorkloads() async throws {
        let environment = ProcessInfo.processInfo.environment
        #if targetEnvironment(simulator)
        throw XCTSkip("Power measurements require a physical device.")
        #else
        try XCTSkipUnless(environment["RUN_DEVICE_ASR_POWER_BENCHMARK"] == "1")
        let repeats = try XCTUnwrap(Int(environment["RUN_DEVICE_ASR_POWER_REPEATS"] ?? "2"))
        guard (1...40).contains(repeats) else { throw BenchmarkError.invalidBatch }
        let idleSeconds = 60
        // Non-uniform gaps reduce heating and avoid locking the workloads to one battery sensor sampling phase.
        let gaps = [5, 12, 7, 14, 9]

        let resources = Bundle(for: Self.self)
        let audio = try XCTUnwrap(resources.url(forResource: "ru-five-minute", withExtension: "m4a"))
        let model = try XCTUnwrap(resources.url(forResource: "ggml-base-q5_1", withExtension: "bin"))
        let manifest = try XCTUnwrap(resources.url(forResource: "asr-power-fixtures", withExtension: "json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: manifest))
        let expected = try XCTUnwrap(fixtures.first { $0.file == audio.lastPathComponent })
        let hash = SHA256.hash(data: try Data(contentsOf: audio)).map { String(format: "%02x", $0) }.joined()
        guard expected.sha256 == hash else { throw BenchmarkError.invalidFixture }

        let device = UIDevice.current
        let originalMonitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = originalMonitoring }
        try await Task.sleep(for: .seconds(1))
        let output = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ASRAcceptance/power-workloads.json")
        let directory = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let signposts = OSSignposter(subsystem: "com.weeklywins.app", category: "ASRPowerBenchmark")
        let clock = ContinuousClock()
        let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let screen = scene.screen
        let initialBrightness = Double(screen.brightness)
        var results: [[String: Any]] = []
        let runStartedAt = Date().formatted(dateFormat)

        // Equal numbers of the same transcriptions. Reverse the order in the second pair.
        let sequence: [Workload] = [.idle, .apple, .idle, .whisper, .idle, .whisper, .idle, .apple, .idle]
        for (index, workload) in sequence.enumerated() {
            try Task.checkCancellation()
            let before = batterySnapshot(screen)
            try requireComparableState(before, initialBrightness: initialBrightness, requireNominal: workload != .idle)
            let startedAt = Date().formatted(dateFormat)
            let started = clock.now
            let interval = signposts.beginInterval("ASR workload", "\(workload.rawValue, privacy: .public) \(index)")
            do {
                defer { signposts.endInterval("ASR workload", interval) }
                switch workload {
                case .idle:
                    try await Task.sleep(for: .seconds(idleSeconds))
                    let deadline = clock.now.advanced(by: .seconds(90))
                    while ProcessInfo.processInfo.thermalState != .nominal {
                        try requireComparableState(batterySnapshot(screen), initialBrightness: initialBrightness,
                                                   requireNominal: false)
                        guard clock.now < deadline else { throw BenchmarkError.cooldownTimedOut }
                        try await Task.sleep(for: .seconds(5))
                    }
                case .apple, .whisper:
                    for repetition in 0..<repeats {
                        try Task.checkCancellation()
                        try requireComparableState(batterySnapshot(screen), initialBrightness: initialBrightness)
                        let text: String
                        switch workload {
                        case .apple:
                            text = try await OnDeviceSpeechTranscriber().transcribe(
                                audioFileURL: audio, locale: Locale(identifier: "ru-RU")
                            )
                        case .whisper:
                            let report = WWMeasureWhisper(audio, model)
                            text = try XCTUnwrap(report["transcript"] as? String, String(describing: report["error"]))
                        case .idle:
                            preconditionFailure("Idle intervals do not transcribe.")
                        }
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            throw BenchmarkError.emptyTranscript
                        }
                        if repetition + 1 < repeats {
                            try await Task.sleep(for: .seconds(gaps[repetition % gaps.count]))
                        }
                    }
                }
            }
            let finishedAt = Date().formatted(dateFormat)
            let elapsed = started.duration(to: clock.now).components
            let after = batterySnapshot(screen)
            results.append([
                "workload": workload.rawValue,
                "started_at": startedAt,
                "finished_at": finishedAt,
                "elapsed_seconds": Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                "transcriptions": workload == .idle ? 0 : repeats,
                "before": before,
                "after": after,
            ])
            let report: [String: Any] = [
                "fixture": audio.lastPathComponent, "fixture_sha256": hash,
                "system_version": UIDevice.current.systemVersion, "expected_blocks": sequence.count,
                "run_started_at": runStartedAt, "minimum_idle_seconds": idleSeconds,
                "pause_pattern_seconds": gaps, "blocks": results,
            ]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output, options: .atomic)
            try requireComparableState(after, initialBrightness: initialBrightness)
        }
        #endif
    }

    @MainActor
    private func batterySnapshot(_ screen: UIScreen) -> [String: Double] {
        [
            "level": Double(UIDevice.current.batteryLevel),
            "charging_state": Double(UIDevice.current.batteryState.rawValue),
            "thermal_state": Double(ProcessInfo.processInfo.thermalState.rawValue),
            "brightness": Double(screen.brightness),
        ]
    }

    @MainActor
    private func requireComparableState(
        _ snapshot: [String: Double], initialBrightness: Double, requireNominal: Bool = true
    ) throws {
        let maxThermalState: ProcessInfo.ThermalState = requireNominal ? .nominal : .fair
        guard let level = snapshot["level"], level >= 0,
              let brightness = snapshot["brightness"], abs(brightness - initialBrightness) <= 0.01,
              snapshot["charging_state"] == Double(UIDevice.BatteryState.unplugged.rawValue),
              let thermalState = snapshot["thermal_state"], thermalState <= Double(maxThermalState.rawValue) else {
            let state = snapshot.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            throw BenchmarkError.unsuitableDeviceState("\(state), initial brightness=\(initialBrightness)")
        }
    }

    private enum BenchmarkError: LocalizedError {
        case invalidBatch, invalidFixture, emptyTranscript, cooldownTimedOut
        case unsuitableDeviceState(String)

        var errorDescription: String? {
            switch self {
            case .invalidBatch: "Power benchmark repeats must be between 1 and 40."
            case .invalidFixture: "The audio does not match the bundled fixture manifest."
            case .emptyTranscript: "The recognizer returned an empty transcript."
            case .cooldownTimedOut: "The iPhone did not return to nominal thermal state during the idle period."
            case .unsuitableDeviceState(let state):
                "Keep the iPhone unplugged, at fixed brightness, and at nominal thermal state. Observed \(state)."
            }
        }
    }
}
