import BackgroundTasks
import Foundation
import UIKit

@MainActor
protocol TranscriptionExecutionSession: AnyObject {
    func begin(allowContinuedProcessing: Bool, onExpiration: @escaping @MainActor () -> Void)
    func reportProgress(_ fraction: Double)
    func finish(success: Bool)
}

@MainActor
final class TranscriptionBackgroundSession: TranscriptionExecutionSession {
    private let identifier = "com.weeklywins.app.transcription.\(UUID().uuidString)"
    private var shortTask: UIBackgroundTaskIdentifier = .invalid
    private var continuedTask: BGContinuedProcessingTask?
    private var expiration: (() -> Void)?
    private var isFinished = false
    private var isRegistered = false
    private var completedUnits: Int64 = 0

    func begin(allowContinuedProcessing: Bool, onExpiration: @escaping @MainActor () -> Void) {
        expiration = onExpiration
        shortTask = UIApplication.shared.beginBackgroundTask(withName: "Расшифровка записи") { [weak self] in
            guard let self, self.shortTask != .invalid else { return }
            self.expire()
        }
        guard UIApplication.shared.applicationState == .active else {
            if shortTask == .invalid { expire() }
            return
        }
        guard allowContinuedProcessing else { return }
        isRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, !self.isFinished, let continued = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.continuedTask = continued
                continued.progress.totalUnitCount = 1000
                continued.progress.completedUnitCount = self.completedUnits
                continued.expirationHandler = { [weak self] in
                    Task { @MainActor in self?.expire() }
                }
                self.endShortTask()
            }
        }
        guard isRegistered else { return }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "Расшифровка записи",
            subtitle: "Русская речь на устройстве"
        )
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request) }
        catch { RecordingDiagnostics.write("transcription continued-processing request unavailable") }
    }

    func reportProgress(_ fraction: Double) {
        guard !isFinished, fraction.isFinite else { return }
        // Reserve the last units for committing the transcript and extracted events.
        completedUnits = max(completedUnits, Int64(min(1, max(0, fraction)) * 950))
        continuedTask?.progress.completedUnitCount = completedUnits
    }

    func finish(success: Bool) {
        guard !isFinished else { return }
        isFinished = true
        expiration = nil
        if success { continuedTask?.progress.completedUnitCount = 1000 }
        continuedTask?.setTaskCompleted(success: success)
        continuedTask = nil
        if isRegistered { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
        endShortTask()
    }

    private func expire() {
        guard !isFinished else { return }
        let cancel = expiration
        finish(success: false)
        cancel?()
    }

    private func endShortTask() {
        guard shortTask != .invalid else { return }
        let identifier = shortTask
        shortTask = .invalid
        UIApplication.shared.endBackgroundTask(identifier)
    }
}
