import XCTest
@testable import WeeklyWins

private actor QueueTranscriber: Transcriber {
    var calls: [String] = []
    var active = 0
    var maximumActive = 0
    let delay: Duration
    let fail: Bool
    nonisolated let canTranscribeWithoutAuthorizationPrompt: Bool

    init(delay: Duration = .zero, fail: Bool = false, requiresAuthorization: Bool = false) {
        self.delay = delay
        self.fail = fail
        canTranscribeWithoutAuthorizationPrompt = !requiresAuthorization
    }

    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String {
        calls.append(audioFileURL.lastPathComponent)
        active += 1
        maximumActive = max(active, maximumActive)
        defer { active -= 1 }
        try await Task.sleep(for: delay)
        if fail { throw TranscriptionError.noSpeechRecognized }
        return "Прошла встреча. Часовая встреча"
    }
}

private actor SlowCleanupTranscriber: Transcriber {
    let started: XCTestExpectation
    let cleanupStarted: XCTestExpectation
    var cleanup: CheckedContinuation<Void, Never>?
    var calls = 0

    init(started: XCTestExpectation, cleanupStarted: XCTestExpectation) {
        self.started = started
        self.cleanupStarted = cleanupStarted
    }

    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String {
        calls += 1
        if calls > 1 { return "Восстановленная заметка" }
        started.fulfill()
        do { try await Task.sleep(for: .seconds(30)) }
        catch {
            cleanupStarted.fulfill()
            await withCheckedContinuation { cleanup = $0 }
            throw CancellationError()
        }
        return "Заметка"
    }

    func finishCleanup() { cleanup?.resume(); cleanup = nil }
}

@MainActor
private final class TestExecutionSession: TranscriptionExecutionSession {
    var expiration: (() -> Void)?
    var didFinish = false
    var continuationRequests: [Bool] = []

    func begin(allowContinuedProcessing: Bool, onExpiration: @escaping @MainActor () -> Void) {
        continuationRequests.append(allowContinuedProcessing)
        expiration = onExpiration
    }
    func reportProgress(_ fraction: Double) {}
    func finish(success: Bool) { didFinish = true; expiration = nil }
}

final class AutomaticTranscriptionTests: XCTestCase {
    @MainActor
    func testStoppingRecordingAutomaticallyTranscribesItOnce() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcriber = QueueTranscriber()
        let session = TestExecutionSession()
        let service = RecordingService(recordingDirectory: directory, transcriber: transcriber,
            backgroundSessionFactory: { session }, isApplicationActive: { true })
        try await service.start()
        try await Task.sleep(for: .milliseconds(120))
        service.stop()
        service.stop()
        try await waitUntil { service.recordings.first?.processingState == .completed }
        XCTAssertEqual(service.recordings.count, 1)
        XCTAssertEqual(service.recordings.first?.events?.first?.duration, 3600)
        XCTAssertEqual(service.recordings.first?.automaticTranscriptionPending, false)
        let calls = await transcriber.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(session.continuationRequests, [true])
    }

    @MainActor
    func testLockedStopWaitsForAuthorizationWithoutDeferringContinuationEligibility() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var active = false
        let session = TestExecutionSession()
        let transcriber = QueueTranscriber(requiresAuthorization: true)
        let service = RecordingService(recordingDirectory: directory, transcriber: transcriber,
            backgroundSessionFactory: { session }, isApplicationActive: { active })
        try await service.start()
        try await Task.sleep(for: .milliseconds(120))
        service.stop()
        let backgroundCalls = await transcriber.calls
        XCTAssertTrue(backgroundCalls.isEmpty)
        XCTAssertEqual(service.recordings.first?.processingState, .pending)
        active = true
        service.resumeAutomaticTranscription()
        try await waitUntil { service.recordings.first?.processingState == .completed }
        XCTAssertEqual(session.continuationRequests, [false])
    }

    @MainActor
    func testFreshStopDoesNotDeferContinuationEligibilityBehindOlderJobs() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let older = try makePendingRecording(store: store, date: Date(timeIntervalSince1970: 100))
        let drafts = TranscriptDraftStore()
        defer { drafts.remove(recordingID: older.id) }
        drafts.save(recordingID: older.id, text: "Черновик")
        let session = TestExecutionSession()
        let service = RecordingService(recordingDirectory: directory, transcriber: QueueTranscriber(),
            backgroundSessionFactory: { session }, isApplicationActive: { true })
        try await service.start()
        try await Task.sleep(for: .milliseconds(120))
        drafts.remove(recordingID: older.id)
        service.resumeAutomaticTranscription()
        service.stop()
        try await waitUntil { service.recordings.allSatisfy { $0.processingState == .completed } }
        XCTAssertEqual(session.continuationRequests, [false, false])
    }

    @MainActor
    func testImmediateRestartDropsUnclaimedStopContinuationEligibility() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = TestExecutionSession()
        let service = RecordingService(recordingDirectory: directory, transcriber: QueueTranscriber(),
            backgroundSessionFactory: { session }, isApplicationActive: { true })
        try await service.start()
        try await Task.sleep(for: .milliseconds(120))
        service.stop()
        try await service.start()
        try await Task.sleep(for: .milliseconds(120))
        service.stop()
        try await waitUntil { service.recordings.count == 2 && service.recordings.allSatisfy { $0.processingState == .completed } }
        XCTAssertEqual(session.continuationRequests, [false, false])
    }

    @MainActor
    func testRelaunchResumesAutomaticJobsOldestFirstAndSerially() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let first = try makePendingRecording(store: store, date: Date(timeIntervalSince1970: 100))
        let second = try makePendingRecording(store: store, date: Date(timeIntervalSince1970: 200))
        try store.updateTranscription(recordingID: first.id, transcript: nil, processingState: .processing, errorMessage: nil)
        let transcriber = QueueTranscriber(delay: .milliseconds(30))
        let service = RecordingService(recordingDirectory: directory, transcriber: transcriber,
            backgroundSessionFactory: { TestExecutionSession() }, isApplicationActive: { true })
        service.resumeAutomaticTranscription()
        service.resumeAutomaticTranscription()
        try await waitUntil { service.recordings.allSatisfy { $0.processingState == .completed } }
        let calls = await transcriber.calls
        let maximumActive = await transcriber.maximumActive
        XCTAssertEqual(calls, [first.fileName, second.fileName])
        XCTAssertEqual(maximumActive, 1)
    }

    @MainActor
    func testExpirationKeepsPendingAudioForRelaunch() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let recording = try makePendingRecording(store: store)
        let session = TestExecutionSession()
        let service = RecordingService(recordingDirectory: directory,
            transcriber: QueueTranscriber(delay: .seconds(30)), backgroundSessionFactory: { session }, isApplicationActive: { true })
        try await waitUntil { service.transcribingRecordingIDs.contains(recording.id) }
        session.expiration?()
        try await waitUntil { service.transcribingRecordingIDs.isEmpty }
        XCTAssertEqual(service.recordings.first?.processingState, .pending)
        XCTAssertEqual(service.recordings.first?.automaticTranscriptionPending, true)
        XCTAssertTrue(session.didFinish)
        XCTAssertEqual(session.continuationRequests, [false])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: recording).path))
        let restored = RecordingService(recordingDirectory: directory, transcriber: QueueTranscriber(),
            backgroundSessionFactory: { TestExecutionSession() }, isApplicationActive: { true })
        try await waitUntil { restored.recordings.first?.processingState == .completed }
    }

    @MainActor
    func testFailedAutomaticJobRetainsAudioAndDoesNotRetryForever() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let recording = try makePendingRecording(store: store)
        let transcriber = QueueTranscriber(fail: true)
        let service = RecordingService(recordingDirectory: directory, transcriber: transcriber,
            backgroundSessionFactory: { TestExecutionSession() }, isApplicationActive: { true })
        try await waitUntil { service.recordings.first?.processingState == .failed }
        service.resumeAutomaticTranscription()
        let calls = await transcriber.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(service.recordings.first?.automaticTranscriptionPending, false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: recording).path))
    }

    @MainActor
    func testDraftBlocksAutomationUntilDiscarded() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let recording = try makePendingRecording(store: store)
        let drafts = TranscriptDraftStore()
        defer { drafts.remove(recordingID: recording.id) }
        drafts.save(recordingID: recording.id, text: "Мой черновик")
        let transcriber = QueueTranscriber()
        let service = RecordingService(recordingDirectory: directory, transcriber: transcriber,
            backgroundSessionFactory: { TestExecutionSession() }, isApplicationActive: { true })
        let calls = await transcriber.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(drafts.load(recordingID: recording.id), "Мой черновик")
        drafts.remove(recordingID: recording.id)
        service.resumeAutomaticTranscription()
        try await waitUntil { service.recordings.first?.processingState == .completed }
    }

    @MainActor
    func testForegroundResumeDuringCancellationCleanupIsServiced() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        _ = try makePendingRecording(store: store)
        let started = expectation(description: "Recognition started")
        let cleanupStarted = expectation(description: "Cancellation cleanup started")
        let transcriber = SlowCleanupTranscriber(started: started, cleanupStarted: cleanupStarted)
        let session = TestExecutionSession()
        let service = RecordingService(recordingDirectory: directory, transcriber: transcriber,
            backgroundSessionFactory: { session }, isApplicationActive: { true })
        await fulfillment(of: [started], timeout: 2)
        session.expiration?()
        await fulfillment(of: [cleanupStarted], timeout: 2)
        service.resumeAutomaticTranscription()
        await transcriber.finishCleanup()
        try await waitUntil { service.recordings.first?.processingState == .completed }
        let calls = await transcriber.calls
        XCTAssertEqual(calls, 2)
    }

    @MainActor
    private func makePendingRecording(store: RecordingStore, date: Date = .now) throws -> Recording {
        let recording = try store.beginRecording(startedAt: date, automaticTranscriptionPending: true)
        try Data([1, 2, 3]).write(to: store.fileURL(for: recording))
        return try store.finalizeRecording(id: recording.id, duration: 1)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw XCTestError(.timeoutWhileWaiting) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
