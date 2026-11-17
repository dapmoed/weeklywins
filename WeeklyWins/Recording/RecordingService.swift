import AVFoundation
import ActivityKit
import Combine
import Foundation
import OSLog

@MainActor
final class RecordingService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = RecordingService(
        recordingDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
        maxRecordingDuration: 300
    )

    @Published private(set) var playingRecordingID: UUID?
    @Published private(set) var recordingStartedAt: Date?
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var status = "Готово к записи"
    @Published private(set) var recordings: [Recording] = []

    private let store: RecordingStore
    private let maxRecordingDuration: TimeInterval
    private let transcriptionService: TranscriptionService
    private var player: AVAudioPlayer?
    private var playbackTask: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var activity: Activity<RecordingAttributes>?
    private var stopTask: Task<Void, Never>?
    private var activeRecordingID: UUID?
    private var interruptionObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.weeklywins.app", category: "RecordingService")

    init(
        recordingDirectory: URL,
        maxRecordingDuration: TimeInterval = 300,
        transcriber: any Transcriber = OnDeviceSpeechTranscriber()
    ) {
        store = RecordingStore(directory: recordingDirectory)
        self.maxRecordingDuration = maxRecordingDuration
        transcriptionService = TranscriptionService(store: store, transcriber: transcriber)
        super.init()
        refreshRecordings()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
            MainActor.assumeIsolated {
                self?.stop(
                    statusMessage: "Запись прервана и сохранена",
                    finalState: .interrupted,
                    errorMessage: "Аудиосессия была прервана системой."
                )
            }
        }
    }

    func refreshRecordings() {
        recordings = store.recordings
    }

    func transcribe(recordingID: UUID, locale: Locale = Locale(identifier: "ru-RU")) async throws -> String {
        do {
            let transcript = try await transcriptionService.transcribe(recordingID: recordingID, locale: locale)
            refreshRecordings()
            return transcript
        } catch {
            refreshRecordings()
            throw error
        }
    }

    func saveEditedTranscript(recordingID: UUID, text: String) throws {
        try transcriptionService.saveEditedTranscript(recordingID: recordingID, text: text)
        refreshRecordings()
    }

    func saveEvents(recordingID: UUID, events: [DiaryEvent]) throws {
        try store.saveEvents(recordingID: recordingID, events: events)
        refreshRecordings()
    }

    func playRecording(id: UUID) throws {
        guard !isRecording, !isStarting else { return }
        stopPlayback()
        guard let recording = store.recordings.first(where: { $0.id == id }) else {
            throw RecordingStoreError.recordingNotFound
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: store.fileURL(for: recording))
            guard newPlayer.play() else { throw RecordingError.playbackFailed }
            player = newPlayer
            playingRecordingID = id
            playbackTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    guard self?.player?.isPlaying == true else {
                        self?.stopPlayback()
                        return
                    }
                }
            }
        } catch {
            try? session.setActive(false)
            throw error
        }
    }

    func stopPlayback() {
        guard player != nil else { return }
        playbackTask?.cancel()
        playbackTask = nil
        player?.stop()
        player = nil
        playingRecordingID = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func audioLevel() -> Float {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        return min(1, max(0, pow(10, recorder.averagePower(forChannel: 0) / 40)))
    }

    func toggle() async throws {
        guard !isStarting else { return }
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
        guard !isRecording, !isStarting else { return }
        stopPlayback()
        isStarting = true
        status = "Запись запускается"
        defer { isStarting = false }

        RecordingDiagnostics.write("requesting microphone permission")
        logger.info("requesting microphone permission")
        let granted: Bool
        switch AVAudioApplication.shared.recordPermission {
        case .granted: granted = true
        case .denied: granted = false
        case .undetermined: granted = await AVAudioApplication.requestRecordPermission()
        @unknown default: granted = false
        }
        RecordingDiagnostics.write("microphone permission granted=\(granted)")
        logger.info("microphone permission granted=\(granted)")
        guard granted else {
            status = "Нет доступа к микрофону"
            throw RecordingError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            RecordingDiagnostics.write("audio session category configured")
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
        RecordingDiagnostics.write("audio session activated")
        logger.info("audio session activated")

        let recording: Recording
        do {
            recording = try store.beginRecording(startedAt: .now)
        } catch {
            try? session.setActive(false)
            throw error
        }
        let url = store.fileURL(for: recording)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.isMeteringEnabled = true
            newRecorder.delegate = self
            guard newRecorder.prepareToRecord(), newRecorder.record(forDuration: maxRecordingDuration) else {
                throw RecordingError.recorderStartFailed
            }
            RecordingDiagnostics.write("recorder started")
            logger.info("recorder started")
            recorder = newRecorder
            activeRecordingID = recording.id
            recordingStartedAt = recording.recordedAt
            isRecording = true
            status = "Запись идёт"
        } catch {
            _ = try? store.finalizeRecording(
                id: recording.id,
                duration: nil,
                state: .failed,
                errorMessage: error.localizedDescription
            )
            try? session.setActive(false)
            refreshRecordings()
            logger.error("audio recorder failed to start: \(Self.errorSummary(error), privacy: .public)")
            throw error
        }

        let attributes = RecordingAttributes()
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: .init(startedAt: .now), staleDate: .now.addingTimeInterval(300))
            )
            RecordingDiagnostics.write("recording Live Activity started")
            logger.info("recording Live Activity started")
        } catch {
            RecordingDiagnostics.write("Live Activity failed \(Self.errorSummary(error))")
            logger.error("Live Activity start failed: \(Self.errorSummary(error), privacy: .public)")
            stop()
            throw error
        }
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.maxRecordingDuration ?? 300))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stop(statusMessage: "Запись сохранена", finalState: .saved)
    }

    private func stop(
        statusMessage: String,
        finalState: RecordingState,
        errorMessage: String? = nil
    ) {
        guard isRecording, let activeRecordingID else { return }
        RecordingDiagnostics.write("stopping recorder")
        logger.info("stopping recorder")
        stopTask?.cancel()
        stopTask = nil
        let runningDuration = recorder?.currentTime
        let audioURL = recorder?.url
        recorder?.stop()
        let fileDuration = audioURL.flatMap { try? AVAudioPlayer(contentsOf: $0).duration }
        let duration = fileDuration ?? runningDuration
        recorder = nil
        isRecording = false
        recordingStartedAt = nil
        self.activeRecordingID = nil
        do {
            try store.finalizeRecording(
                id: activeRecordingID,
                duration: duration,
                state: finalState,
                errorMessage: errorMessage
            )
            status = statusMessage
            refreshRecordings()
        } catch {
            status = "Запись завершена, но не удалось сохранить состояние: \(error.localizedDescription)"
            logger.error("recording finalization failed: \(Self.errorSummary(error), privacy: .public)")
        }
        if let activity {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            self.activity = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.stop(
                statusMessage: flag ? "Запись сохранена" : "Запись прервана и сохранена",
                finalState: flag ? .saved : .interrupted
            )
        }
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
    case playbackFailed
}
