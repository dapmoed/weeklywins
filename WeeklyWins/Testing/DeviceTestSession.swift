#if DEBUG
import Foundation
import UIKit

enum DeviceTestSession {
    @MainActor private static var keeper: Task<Void, Never>?

    static var markerURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WeeklyWinsDeviceTestSession.json")
    }

    @MainActor
    static func startIfRequested() {
        guard keeper == nil else { return }
        keeper = Task { @MainActor in
            await holdScreenAwake()
            keeper = nil
        }
    }

    @MainActor
    static func holdScreenAwake(
        marker: URL = markerURL,
        pollInterval: Duration = .milliseconds(500)
    ) async {
        let previous = UIApplication.shared.isIdleTimerDisabled
        guard isEnabled(marker) == true else {
            writeStatus(active: false, marker: marker)
            return
        }
        UIApplication.shared.isIdleTimerDisabled = true
        writeStatus(active: true, marker: marker)
        defer {
            UIApplication.shared.isIdleTimerDisabled = previous
            writeStatus(active: false, marker: marker)
        }
        while !Task.isCancelled && isEnabled(marker) != false {
            UIApplication.shared.isIdleTimerDisabled = true
            do { try await Task.sleep(for: pollInterval) }
            catch { return }
        }
    }

    private static func isEnabled(_ marker: URL) -> Bool? {
        guard let data = try? Data(contentsOf: marker),
              let value = try? JSONDecoder().decode(Marker.self, from: data) else { return nil }
        return value.enabled
    }

    @MainActor
    private static func writeStatus(active: Bool, marker: URL) {
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let status = Status(active: active, idleTimerDisabled: UIApplication.shared.isIdleTimerDisabled,
                            processID: ProcessInfo.processInfo.processIdentifier)
        let url = marker.deletingPathExtension().appendingPathExtension("status.json")
        guard let data = try? JSONEncoder().encode(status) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private struct Marker: Decodable { let enabled: Bool }
    private struct Status: Encodable {
        let active: Bool
        let idleTimerDisabled: Bool
        let processID: Int32
    }
}
#endif
