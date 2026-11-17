import AVFoundation
import ActivityKit
import Combine
import Foundation
import OSLog
import UIKit

@MainActor
final class RecordingService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = RecordingService(
        recordingDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
        maxRecordingDuration: 300
    )

    @Published private(set) var transcribingRecordingIDs: Set<UUID> = []
    @Published private(set) var playingRecordingID: UUID?
    @Published private(set) var isAudioPlaying = false
    @Published private(set) var playbackPosition: TimeInterval = 0
    @Published private(set) var playbackDuration: TimeInterval = 0
    @Published private(set) var recordingStartedAt: Date?
    @Published private(set) var completedRecordingID: UUID?
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var status = "Готово к записи"
    @Published private(set) var recordings: [Recording] = []

    private let store: RecordingStore
    private let maxRecordingDuration: TimeInterval
    private let transcriptionService: TranscriptionService
    private let transcriber: any Transcriber
    private let backgroundSessionFactory: @MainActor () -> any TranscriptionExecutionSession
    private let isApplicationActive: @MainActor () -> Bool
    private var automaticTranscriptionTask: Task<Void, Never>?
    private var automaticResumeRequested = false
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
        transcriber: any Transcriber = OnDeviceSpeechTranscriber(),
        backgroundSessionFactory: @escaping @MainActor () -> any TranscriptionExecutionSession = { TranscriptionBackgroundSession() },
        isApplicationActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }
    ) {
        store = RecordingStore(directory: recordingDirectory)
        self.maxRecordingDuration = maxRecordingDuration
        self.transcriber = transcriber
        self.backgroundSessionFactory = backgroundSessionFactory
        self.isApplicationActive = isApplicationActive
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
        resumeAutomaticTranscription()
    }

    func refreshRecordings() {
        recordings = store.recordings.filter { $0.deletedAt == nil }
    }

    func transcribe(recordingID: UUID, locale: Locale = Locale(identifier: "ru-RU"), userInitiated: Bool = true) async throws -> String {
        guard transcribingRecordingIDs.isEmpty else { throw TranscriptionError.alreadyProcessing }
        try Task.checkCancellation()
        transcribingRecordingIDs.insert(recordingID)
        let background = backgroundSessionFactory()
        var success = false
        var shouldResumeQueue = true
        let operation = Task {
            try await transcriptionService.transcribe(
                recordingID: recordingID, locale: locale,
                onStarted: { [weak self] in self?.refreshRecordings() },
                reportProgress: { [weak background] fraction in
                    Task { @MainActor in background?.reportProgress(fraction) }
                }
            )
        }
        background.begin(allowContinuedProcessing: userInitiated) { operation.cancel() }
        defer {
            background.finish(success: success)
            transcribingRecordingIDs.remove(recordingID)
            if shouldResumeQueue { scheduleAutomaticTranscription() }
        }
        do {
            let transcript = try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: { operation.cancel() }
            success = true
            refreshRecordings()
            return transcript
        } catch {
            shouldResumeQueue = !(error is CancellationError || error as? TranscriptionError == .speechAuthorizationRequired)
            refreshRecordings()
            throw error
        }
    }

    func saveEditedTranscript(recordingID: UUID, text: String) throws {
        guard !transcribingRecordingIDs.contains(recordingID) else { throw TranscriptionError.alreadyProcessing }
        try transcriptionService.saveEditedTranscript(recordingID: recordingID, text: text)
        refreshRecordings()
    }

    func saveEvents(recordingID: UUID, events: [DiaryEvent], expectedEvents: [DiaryEvent]? = nil) throws {
        try store.saveEvents(recordingID: recordingID, events: events, expectedEvents: expectedEvents)
        refreshRecordings()
    }

    func deleteRecording(id: UUID) throws {
        guard !transcribingRecordingIDs.contains(id) else { throw RecordingManagementError.busy }
        if playingRecordingID == id { stopPlayback() }
        defer { refreshRecordings() }
        try store.deleteRecording(id: id)
    }

    func resumeAutomaticTranscription(userInitiatedRecordingID: UUID? = nil) {
        if automaticTranscriptionTask != nil {
            automaticResumeRequested = true
            return
        }
        scheduleAutomaticTranscription(userInitiatedRecordingID: userInitiatedRecordingID)
    }

    private func scheduleAutomaticTranscription(userInitiatedRecordingID: UUID? = nil) {
        guard automaticTranscriptionTask == nil, transcribingRecordingIDs.isEmpty,
              !isRecording, !isStarting, let next = nextAutomaticRecording,
              isApplicationActive() || transcriber.canTranscribeWithoutAuthorizationPrompt else { return }
        let eligibleRecordingID = isApplicationActive() && next.id == userInitiatedRecordingID ? next.id : nil
        automaticTranscriptionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.automaticTranscriptionTask = nil
                if self.automaticResumeRequested {
                    self.automaticResumeRequested = false
                    self.scheduleAutomaticTranscription()
                }
            }
            var attempted: Set<UUID> = []
            var continuationEligibility = eligibleRecordingID
            while !Task.isCancelled, !self.isRecording, !self.isStarting,
                  let recording = self.nextAutomaticRecording, attempted.insert(recording.id).inserted {
                let userInitiated = continuationEligibility == recording.id
                continuationEligibility = nil
                do { _ = try await self.transcribe(recordingID: recording.id, userInitiated: userInitiated) }
                catch {
                    if error is CancellationError || error as? TranscriptionError == .speechAuthorizationRequired { return }
                }
            }
        }
    }

    private var nextAutomaticRecording: Recording? {
        store.recordings.reversed().first {
            $0.deletedAt == nil && $0.automaticTranscriptionPending == true
                && $0.processingState == .pending && $0.transcript == nil
                && ($0.state == .saved || $0.state == .interrupted)
                && TranscriptDraftStore().load(recordingID: $0.id) == nil
        }
    }

    func playRecording(id: UUID) throws {
        guard !isRecording, !isStarting else { return }
        stopPlayback()
        guard let recording = store.recordings.first(where: { $0.id == id && $0.deletedAt == nil }) else {
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
            isAudioPlaying = true
            playbackPosition = 0
            playbackDuration = newPlayer.duration
            playbackTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    guard let self else { return }
                    guard self.isAudioPlaying else { continue }
                    self.playbackPosition = self.player?.currentTime ?? 0
                    guard self.player?.isPlaying == true else {
                        self.stopPlayback()
                        return
                    }
                }
            }
        } catch {
            try? session.setActive(false)
            throw error
        }
    }

    func togglePlayback(id: UUID) throws {
        guard !isRecording, !isStarting else { return }
        if playingRecordingID == id, let player {
            if isAudioPlaying {
                player.pause()
                playbackPosition = player.currentTime
                isAudioPlaying = false
            } else {
                guard player.play() else { throw RecordingError.playbackFailed }
                isAudioPlaying = true
            }
        } else { try playRecording(id: id) }
    }

    func seekPlayback(to time: TimeInterval) {
        guard time.isFinite, let player else { return }
        player.currentTime = min(max(0, time), player.duration)
        playbackPosition = player.currentTime
    }

    func stopPlayback() {
        guard player != nil else { return }
        playbackTask?.cancel()
        playbackTask = nil
        player?.stop()
        player = nil
        playingRecordingID = nil
        isAudioPlaying = false
        playbackPosition = 0
        playbackDuration = 0
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
        completedRecordingID = nil
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
            recording = try store.beginRecording(startedAt: .now, automaticTranscriptionPending: true)
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
            stop(statusMessage: "Запись сохранена", finalState: .saved)
            throw error
        }
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.maxRecordingDuration ?? 300))
            guard !Task.isCancelled else { return }
            self?.stop(statusMessage: "Запись сохранена", finalState: .saved)
        }
    }

    func stop() {
        stop(statusMessage: "Запись сохранена", finalState: .saved, userInitiated: true)
    }

    private func stop(
        statusMessage: String,
        finalState: RecordingState,
        errorMessage: String? = nil,
        userInitiated: Bool = false
    ) {
        guard isRecording, let activeRecordingID else { return }
        let userInitiatedRecordingID = userInitiated && isApplicationActive() ? activeRecordingID : nil
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
            if finalState == .saved { completedRecordingID = activeRecordingID }
        } catch {
            status = "Запись завершена, но не удалось сохранить состояние: \(error.localizedDescription)"
            logger.error("recording finalization failed: \(Self.errorSummary(error), privacy: .public)")
        }
        if let activity {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            self.activity = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false)
        resumeAutomaticTranscription(userInitiatedRecordingID: userInitiatedRecordingID)
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
