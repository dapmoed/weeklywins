import UIKit
import XCTest
@testable import WeeklyWins

final class DeviceTestSessionTests: XCTestCase {
    @MainActor
    func testSessionKeepsTheScreenAwakeAndRestoresTheOriginalState() async throws {
        for original in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let marker = directory.appendingPathComponent("session.json")
            try Data(#"{"enabled":true}"#.utf8).write(to: marker)
            let previous = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = original
            defer { UIApplication.shared.isIdleTimerDisabled = previous }
            let task = Task { await DeviceTestSession.holdScreenAwake(marker: marker, pollInterval: .milliseconds(10)) }
            let awake = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let data = try? Data(contentsOf: marker.deletingPathExtension().appendingPathExtension("status.json")),
                      let status = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
                return UIApplication.shared.isIdleTimerDisabled && status["active"] as? Bool == true
            }, object: nil)
            await fulfillment(of: [awake], timeout: 2)
            try Data(#"{"enabled":false}"#.utf8).write(to: marker, options: .atomic)
            await task.value
            XCTAssertEqual(UIApplication.shared.isIdleTimerDisabled, original)
            let status = try JSONSerialization.jsonObject(with: Data(contentsOf: marker.deletingPathExtension().appendingPathExtension("status.json"))) as? [String: Any]
            XCTAssertEqual(status?["active"] as? Bool, false)
            XCTAssertEqual(status?["idleTimerDisabled"] as? Bool, original)
        }
    }

    @MainActor
    func testCancellationRestoresIdleTimer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("session.json")
        try Data(#"{"enabled":true}"#.utf8).write(to: marker)
        let previous = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = false
        defer { UIApplication.shared.isIdleTimerDisabled = previous }
        let task = Task { await DeviceTestSession.holdScreenAwake(marker: marker, pollInterval: .milliseconds(10)) }
        let awake = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in UIApplication.shared.isIdleTimerDisabled }, object: nil)
        await fulfillment(of: [awake], timeout: 2)
        task.cancel()
        await task.value
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    @MainActor
    func testIncompleteMarkerDoesNotEndAnActiveSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("session.json")
        try Data(#"{"enabled":true}"#.utf8).write(to: marker)
        let previous = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = false
        defer { UIApplication.shared.isIdleTimerDisabled = previous }
        let task = Task { await DeviceTestSession.holdScreenAwake(marker: marker, pollInterval: .milliseconds(10)) }
        let awake = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in UIApplication.shared.isIdleTimerDisabled }, object: nil)
        await fulfillment(of: [awake], timeout: 2)
        try Data(#"{"enabled":"#.utf8).write(to: marker)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        try Data(#"{"enabled":true}"#.utf8).write(to: marker)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        try Data(#"{"enabled":false}"#.utf8).write(to: marker, options: .atomic)
        await task.value
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }
}
