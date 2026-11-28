import AVFoundation
import ActivityKit
import Combine
import Foundation
import OSLog
import UIKit

enum AudioRetentionPreferences {
    static let enabledKey = "weeklywins.audioRetention.enabled"
    static let daysKey = "weeklywins.audioRetention.days"
    static let defaultDays = 30
    static let dayRange = 1...365

    static func normalizedDays(_ days: Int) -> Int {
        dayRange.contains(days) ? days : defaultDays
    }

    static var current: AudioRetentionPolicy {
        let defaults = UserDefaults.standard
        return AudioRetentionPolicy(
            enabled: defaults.bool(forKey: enabledKey),
            days: normalizedDays(defaults.object(forKey: daysKey) as? Int ?? defaultDays)
        )
    }
}

struct AudioRetentionPolicy: Equatable {
    let enabled: Bool
    let days: Int
}

@MainActor
final class RecordingService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = RecordingService(
        recordingDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
        maxRecordingDuration: 300,
        initialAudioRetentionPolicy: AudioRetentionPreferences.current
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
    private let activateRecordingSession: @MainActor (AVAudioSession) throws -> Void
    private let beginAudioCapture: @MainActor (AVAudioRecorder, TimeInterval) -> Bool
    private var automaticTranscriptionTask: Task<Void, Never>?
    private var automaticResumeRequested = false
    private var isSynchronizingRecorder = false
    private var player: AVAudioPlayer?
    private var playbackTask: Task<Void, Never>?
    private var isPlaybackSessionActive = false
    private var recorder: AVAudioRecorder?
    private var activity: Activity<RecordingAttributes>?
    private var stopTask: Task<Void, Never>?
    private var activeRecordingID: UUID?
    private var interruptionObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.weeklywins.app", category: "RecordingService")

    var audioStorageItems: [AudioStorageItem] { store.audioStorageItems() }

    init(
        recordingDirectory: URL,
        maxRecordingDuration: TimeInterval = 300,
        transcriber: any Transcriber = OnDeviceSpeechTranscriber(),
        backgroundSessionFactory: @escaping @MainActor () -> any TranscriptionExecutionSession = { TranscriptionBackgroundSession() },
        isApplicationActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
        activateRecordingSession: @escaping @MainActor (AVAudioSession) throws -> Void = { try $0.setActive(true) },
        beginAudioCapture: @escaping @MainActor (AVAudioRecorder, TimeInterval) -> Bool = { $0.record(forDuration: $1) },
        initialAudioRetentionPolicy: AudioRetentionPolicy? = nil
    ) {
        store = RecordingStore(directory: recordingDirectory)
        self.maxRecordingDuration = maxRecordingDuration
        self.transcriber = transcriber
        self.backgroundSessionFactory = backgroundSessionFactory
        self.isApplicationActive = isApplicationActive
        self.activateRecordingSession = activateRecordingSession
        self.beginAudioCapture = beginAudioCapture
        transcriptionService = TranscriptionService(store: store, transcriber: transcriber)
        super.init()
        refreshRecordings()
        removeEmptyRecordings()
        if let initialAudioRetentionPolicy {
            _ = try? applyAudioRetention(enabled: initialAudioRetentionPolicy.enabled,
                                         days: initialAudioRetentionPolicy.days)
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
            MainActor.assumeIsolated {
                guard let self, self.isRecording else { return }
                RecordingDiagnostics.write("audio session interruption began")
                self.stop(
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

    /// Запись без полезного содержимого: нулевая длительность или расшифровка без единого слова.
    static func isEmptyRecording(_ recording: Recording) -> Bool {
        let hasNoWords = recording.transcript?.contains(where: { $0.isLetter || $0.isNumber }) != true
        return (recording.duration ?? 0) <= 0 || (recording.transcript != nil && hasNoWords)
    }

    /// Убирает пустые записи при запуске: из списков, из дел и из ошибок «Сегодня», вместе с аудио.
    func removeEmptyRecordings() {
        for recording in store.recordings where recording.deletedAt == nil && Self.isEmptyRecording(recording) {
            try? store.deleteRecording(id: recording.id)
        }
        refreshRecordings()
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

    func importTranscriptEntries(_ entries: [TranscriptExport.Entry]) throws -> ImportSummary {
        let summary = try store.importRecordings(entries)
        refreshRecordings()
        return summary
    }

    func synchronizeRecorder(using client: RecorderSyncClient) async throws -> Int {
        guard !isSynchronizingRecorder else { throw RecorderSyncError.busy }
        isSynchronizingRecorder = true
        defer {
            isSynchronizingRecorder = false
            refreshRecordings()
            resumeAutomaticTranscription()
        }

        try await client.synchronizeClock()
        let entries = try await client.pendingRecordings()
        var imported = 0
        for entry in entries {
            if !store.hasImportedAudio(id: entry.id) {
                let audio = try await client.audio(for: entry.id)
                try Task.checkCancellation()
                if try store.importAudio(id: entry.id, recordedAt: entry.recordedAt, wav: audio) {
                    imported += 1
                }
            }
            try await client.acknowledge(entry.id)
        }
        return imported
    }

    struct DeletedEvent {
        fileprivate let event: DiaryEvent
        fileprivate let draft: DiaryEvent?
        fileprivate let index: Int
    }

    func deleteEvent(_ event: DiaryEvent, editorDraft: DiaryEvent? = nil) throws -> DeletedEvent {
        guard let events = recordings.first(where: { $0.id == event.recordingID })?.events,
              let index = events.firstIndex(where: { $0.id == event.id }) else {
            throw RecordingStoreError.recordingNotFound
        }
        guard events[index] == event else { throw EventEditingError.conflictingChanges }
        let draft = editorDraft ?? EventDraftStore().load(for: event)
        var remaining = events
        remaining.remove(at: index)
        try saveEvents(recordingID: event.recordingID, events: remaining, expectedEvents: events)
        return DeletedEvent(event: event, draft: draft == event ? nil : draft, index: index)
    }

    func restoreEvent(_ deletion: DeletedEvent) throws {
        let event = deletion.event
        guard let recording = recordings.first(where: { $0.id == event.recordingID }) else {
            throw RecordingStoreError.recordingNotFound
        }
        let events = recording.events ?? []
        guard !events.contains(where: { $0.id == event.id }) else { throw EventEditingError.conflictingChanges }
        var restored = events
        restored.insert(event, at: min(deletion.index, restored.count))
        try saveEvents(recordingID: event.recordingID, events: restored, expectedEvents: events)
        if let draft = deletion.draft { try EventDraftStore().save(draft, baseline: event) }
    }

    func deleteRecording(id: UUID) throws {
        guard !transcribingRecordingIDs.contains(id) else { throw RecordingManagementError.busy }
        if playingRecordingID == id { stopPlayback() }
        defer { refreshRecordings() }
        try store.deleteRecording(id: id)
    }

    @discardableResult
    func applyAudioRetention(enabled: Bool, days: Int, now: Date = .now) throws -> [UUID] {
        guard enabled else { return [] }
        let retentionDays = AudioRetentionPreferences.normalizedDays(days)
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now) else {
            return []
        }
        defer { refreshRecordings() }
        if let playingRecordingID,
           let playing = store.recordings.first(where: { $0.id == playingRecordingID }),
           playing.recordedAt < cutoff {
            stopPlayback()
        }
        return try store.deleteAudio(olderThan: cutoff, at: now)
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

    func preparePlayback(id: UUID) throws {
        guard !isRecording, !isStarting, playingRecordingID != id else { return }
        guard let recording = store.recordings.first(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw RecordingStoreError.recordingNotFound
        }
        let url = store.fileURL(for: recording)
        guard FileManager.default.fileExists(atPath: url.path) else { throw RecordingStoreError.audioFileMissing }
        let newPlayer = try AVAudioPlayer(contentsOf: url)
        guard newPlayer.duration.isFinite, newPlayer.duration > 0 else { throw RecordingError.playbackFailed }

        stopPlayback()
        player = newPlayer
        playingRecordingID = id
        playbackDuration = newPlayer.duration
    }

    func playRecording(id: UUID) throws {
        guard !isRecording, !isStarting else { return }
        stopPlayback()
        try preparePlayback(id: id)
        try startPlayback()
    }

    func togglePlayback(id: UUID) throws {
        guard !isRecording, !isStarting else { return }
        try preparePlayback(id: id)
        if isAudioPlaying, let player {
            player.pause()
            playbackPosition = player.currentTime
            isAudioPlaying = false
            playbackTask?.cancel()
            playbackTask = nil
        } else {
            try startPlayback()
        }
    }

    private func startPlayback() throws {
        guard let player else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            isPlaybackSessionActive = true
            if playbackPosition >= playbackDuration { seekPlayback(to: 0) }
            guard player.play() else { throw RecordingError.playbackFailed }
        } catch {
            deactivatePlaybackSession()
            throw error
        }
        isAudioPlaying = true
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self, let player = self.player else { return }
                guard player.isPlaying else {
                    self.isAudioPlaying = false
                    self.seekPlayback(to: 0)
                    self.playbackTask = nil
                    self.deactivatePlaybackSession()
                    return
                }
                self.playbackPosition = player.currentTime
            }
        }
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
        deactivatePlaybackSession()
    }

    private func deactivatePlaybackSession() {
        guard isPlaybackSessionActive else { return }
        isPlaybackSessionActive = false
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
        defer {
            if !isRecording { endRecordingActivity() }
            isStarting = false
        }

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
        let startsFromBackground = !isApplicationActive()
        let categoryOptions: AVAudioSession.CategoryOptions = startsFromBackground
            ? [.mixWithOthers]
            : [.mixWithOthers, .allowBluetoothA2DP]
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: categoryOptions)
            RecordingDiagnostics.write("audio session category configured")
            logger.info("audio session category configured")
        } catch {
            logger.error("audio session category failed: \(Self.errorSummary(error), privacy: .public)")
            throw error
        }
        if startsFromBackground {
            try requestRecordingActivity(preparing: true)
        }
        var didRetryStartup = false
        do {
            do {
                try activateRecordingSession(session)
            } catch let error as NSError where
                error.domain == NSOSStatusErrorDomain &&
                error.code == Int(AVAudioSession.ErrorCode.cannotStartPlaying.rawValue) {
                didRetryStartup = true
                RecordingDiagnostics.write("audio session activation retry: \(Self.errorSummary(error))")
                try await Task.sleep(for: .milliseconds(600))
                try activateRecordingSession(session)
            }
        } catch {
            RecordingDiagnostics.write("audio session activation failed: \(Self.errorSummary(error))")
            logger.error("audio session activation failed: \(Self.errorSummary(error), privacy: .public)")
            throw error
        }
        RecordingDiagnostics.write("audio session activated")
        let route = session.currentRoute
        let inputs = route.inputs.map(\.portType.rawValue).joined(separator: ",")
        let outputs = route.outputs.map(\.portType.rawValue).joined(separator: ",")
        RecordingDiagnostics.write(
            "audio route input=\(inputs) output=\(outputs) sampleRate=\(session.sampleRate) " +
                "inputChannels=\(session.inputNumberOfChannels) otherAudio=\(session.isOtherAudioPlaying)"
        )
        logger.info("audio session activated")

        let recording: Recording
        do {
            try Task.checkCancellation()
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
            var startedRecorder = try prepareAndStartRecorder(url: url, settings: settings)
            if startedRecorder == nil && !didRetryStartup {
                RecordingDiagnostics.write("recorder start retry")
                try await Task.sleep(for: .milliseconds(600))
                startedRecorder = try prepareAndStartRecorder(url: url, settings: settings)
            }
            guard let newRecorder = startedRecorder else {
                throw RecordingError.recorderStartFailed
            }
            RecordingDiagnostics.write("recorder started")
            logger.info("recorder started")
            recorder = newRecorder
            activeRecordingID = recording.id
            recordingStartedAt = .now
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
            RecordingDiagnostics.write("audio recorder failed to start: \(Self.errorSummary(error))")
            logger.error("audio recorder failed to start: \(Self.errorSummary(error), privacy: .public)")
            throw error
        }

        if let activity {
            let content = recordingActivityContent(preparing: false)
            Task { await activity.update(content) }
        } else {
            do {
                try requestRecordingActivity(preparing: false)
            } catch {
                stop(statusMessage: "Запись сохранена", finalState: .saved)
                throw error
            }
        }
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.maxRecordingDuration ?? 300))
            guard !Task.isCancelled else { return }
            RecordingDiagnostics.write("recording duration timer reached")
            self?.stop(statusMessage: "Запись сохранена", finalState: .saved)
        }
    }

    private func recordingActivityContent(preparing: Bool) -> ActivityContent<RecordingAttributes.ContentState> {
        let start = recordingStartedAt ?? .now
        return .init(state: .init(startedAt: start, isPreparing: preparing), staleDate: start.addingTimeInterval(maxRecordingDuration))
    }

    private func requestRecordingActivity(preparing: Bool) throws {
        do {
            activity = try Activity.request(attributes: RecordingAttributes(), content: recordingActivityContent(preparing: preparing))
            RecordingDiagnostics.write("recording Live Activity started preparing=\(preparing)")
            logger.info("recording Live Activity started")
        } catch {
            RecordingDiagnostics.write("Live Activity failed \(Self.errorSummary(error))")
            logger.error("Live Activity start failed: \(Self.errorSummary(error), privacy: .public)")
            throw error
        }
    }

    private func endRecordingActivity() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func prepareAndStartRecorder(url: URL, settings: [String: Any]) throws -> AVAudioRecorder? {
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.delegate = self
        let prepared = recorder.prepareToRecord()
        RecordingDiagnostics.write("recorder prepared=\(prepared)")
        guard prepared else { throw RecordingError.recorderStartFailed }
        let started = beginAudioCapture(recorder, maxRecordingDuration)
        RecordingDiagnostics.write("recorder accepted start=\(started)")
        if started { return recorder }
        recorder.stop()
        return nil
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
        endRecordingActivity()
        try? AVAudioSession.sharedInstance().setActive(false)
        resumeAutomaticTranscription(userInitiatedRecordingID: userInitiatedRecordingID)
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            RecordingDiagnostics.write("audio recorder finished success=\(flag)")
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
