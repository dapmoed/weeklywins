import AVFoundation
import ActivityKit
import Combine
import Foundation
import OSLog

@MainActor
final class RecordingService: ObservableObject {
    static let shared = RecordingService()

    @Published private(set) var isRecording = false
    @Published private(set) var status = "Готово к записи"

    private var recorder: AVAudioRecorder?
    private var activity: Activity<RecordingAttributes>?
    private var stopTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.weeklywins.app", category: "RecordingService")

    private init() {}

    func toggle() async throws {
        if isRecording {
            stop()
        } else {
            try await start()
        }
    }

    func showError(_ error: Error) {
        status = "Ошибка записи: \(error.localizedDescription)"
    }

    func start() async throws {
        guard !isRecording else { return }
        logger.info("requesting microphone permission")
        let granted = await AVAudioApplication.requestRecordPermission()
        logger.info("microphone permission granted=\(granted)")
        guard granted else {
            status = "Нет доступа к микрофону"
            throw RecordingError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [])
            logger.info("audio session category configured")
        } catch {
            logger.error("audio session category failed: \(Self.errorSummary(error), privacy: .public)")
            throw error
        }
        do {
            try session.setActive(true)
        } catch {
            logger.error("audio session activation failed: \(Self.errorSummary(error), privacy: .public)")
            throw error
        }
        logger.info("audio session activated")

        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent("recording-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        guard newRecorder.prepareToRecord(), newRecorder.record(forDuration: 300) else {
            let error = RecordingError.recorderStartFailed
            logger.error("audio recorder failed to start: \(Self.errorSummary(error), privacy: .public)")
            throw error
        }
        logger.info("recorder started")
        recorder = newRecorder
        isRecording = true
        status = "Запись идёт"
        let attributes = RecordingAttributes()
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: .init(startedAt: .now), staleDate: .now.addingTimeInterval(300))
            )
            logger.info("recording Live Activity started")
        } catch {
            logger.error("Live Activity start failed: \(Self.errorSummary(error), privacy: .public)")
        }
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        guard isRecording else { return }
        logger.info("stopping recorder")
        stopTask?.cancel()
        stopTask = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        status = "Запись сохранена"
        if let activity {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            self.activity = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private static func errorSummary(_ error: Error) -> String {
        let error = error as NSError
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        return "domain=\(error.domain) code=\(error.code) underlying=\(underlying.map { "\($0.domain):\($0.code)" } ?? "none")"
    }
}

enum RecordingError: Error {
    case permissionDenied
    case recorderStartFailed
}
