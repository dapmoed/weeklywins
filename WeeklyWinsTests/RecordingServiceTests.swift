import XCTest
import AppIntents
import AVFoundation
import ActivityKit
@testable import WeeklyWins

final class RecordingServiceTests: XCTestCase {
    @MainActor
    func testBackgroundActivationStartsAfterLiveActivityRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existingActivities = Set(Activity<RecordingAttributes>.activities.map(\.id))
        let service = RecordingService(
            recordingDirectory: directory,
            isApplicationActive: { false },
            activateRecordingSession: { session in
                let newActivities = Activity<RecordingAttributes>.activities.filter { !existingActivities.contains($0.id) }
                XCTAssertEqual(newActivities.count, 1, "The Live Activity must already exist before the background audio session activates.")
                try session.setActive(true)
            }
        )
        defer { service.stop() }
        try await service.start()
        XCTAssertTrue(service.isRecording)
    }

    @MainActor
    func testRetryStartsOneRecordingAfterCannotStartPlaying() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var attempts = 0
        let service = RecordingService(recordingDirectory: directory, activateRecordingSession: { session in
            attempts += 1
            if attempts == 1 {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(AVAudioSession.ErrorCode.cannotStartPlaying.rawValue))
            }
            try session.setActive(true)
        })
        defer { service.stop() }

        try await service.start()
        XCTAssertTrue(service.isRecording)
        XCTAssertEqual(attempts, 2)
        service.stop()
        XCTAssertEqual(service.recordings.map(\.state), [.saved])
    }

    @MainActor
    func testActivationRetryStopsAfterSecondFailureWithoutCreatingRecording() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var attempts = 0
        let errorCode = Int(AVAudioSession.ErrorCode.cannotStartPlaying.rawValue)
        let service = RecordingService(recordingDirectory: directory, activateRecordingSession: { _ in
            attempts += 1
            throw NSError(domain: NSOSStatusErrorDomain, code: errorCode)
        })

        do {
            try await service.start()
            XCTFail("Expected audio-session activation to fail")
        } catch {
            XCTAssertEqual((error as NSError).code, errorCode)
        }
        XCTAssertEqual(attempts, 2)
        XCTAssertFalse(service.isRecording)
        XCTAssertTrue(service.recordings.isEmpty)
    }

    @MainActor
    func testRecorderRejectionRetriesWithFreshRecorderAndKeepsOneEntry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var attempts: [AVAudioRecorder] = []
        let service = RecordingService(recordingDirectory: directory, beginAudioCapture: { recorder, duration in
            attempts.append(recorder)
            return attempts.count > 1 && recorder.record(forDuration: duration)
        })
        defer { service.stop() }

        try await service.start()
        XCTAssertTrue(service.isRecording)
        XCTAssertEqual(attempts.count, 2)
        XCTAssertFalse(attempts.first === attempts.last)
        service.stop()
        XCTAssertEqual(service.recordings.map(\.state), [.saved])
    }

    @MainActor
    func testFailedRecorderDoesNotRetryAfterAudioSessionAlreadyRetried() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var activationAttempts = 0
        var captureAttempts = 0
        let service = RecordingService(
            recordingDirectory: directory,
            activateRecordingSession: { session in
                activationAttempts += 1
                if activationAttempts == 1 {
                    throw NSError(domain: NSOSStatusErrorDomain, code: Int(AVAudioSession.ErrorCode.cannotStartPlaying.rawValue))
                }
                try session.setActive(true)
            },
            beginAudioCapture: { _, _ in
                captureAttempts += 1
                return false
            }
        )
        defer { service.stop() }

        do {
            try await service.start()
            XCTFail("Expected the recorder to reject capture")
        } catch {
            XCTAssertEqual(error as? RecordingError, .recorderStartFailed)
        }
        XCTAssertEqual(activationAttempts, 2)
        XCTAssertEqual(captureAttempts, 1)
        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(service.recordings.map(\.state), [.failed])
    }

    func testActionButtonIntentConformsToAudioRecordingIntent() {
        let _: any AudioRecordingIntent = ToggleRecordingIntent()
        let _: any LiveActivityIntent = ToggleRecordingIntent()
    }

    @MainActor
    func testAudioInterruptionStopsAndSavesActiveRecording() async throws {
        let service = RecordingService.shared
        service.stop()
        let recordingCountBeforeStart = service.recordings.count

        try await service.start()
        defer { service.stop() }

        XCTAssertTrue(service.isRecording)
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )

        XCTAssertFalse(service.isRecording, "An audio interruption must stop the recorder and finalize its file.")
        XCTAssertEqual(service.recordings.count, recordingCountBeforeStart + 1)
    }

    func testRecordingLibraryListsSavedAudioNewestFirst() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_700_000_100)
        let olderURL = directory.appendingPathComponent("recording-old.m4a")
        let newerURL = directory.appendingPathComponent("recording-new.m4a")
        try Data([0]).write(to: olderURL)
        try Data([0]).write(to: newerURL)
        try Data([0]).write(to: directory.appendingPathComponent("not-a-recording.txt"))
        try FileManager.default.setAttributes([.modificationDate: olderDate], ofItemAtPath: olderURL.path)
        try FileManager.default.setAttributes([.modificationDate: newerDate], ofItemAtPath: newerURL.path)

        let recordings = RecordingLibrary.scan(directory: directory)

        XCTAssertEqual(recordings.map { $0.fileURL.lastPathComponent }, ["recording-new.m4a", "recording-old.m4a"])
        XCTAssertEqual(recordings.first?.recordedAt, newerDate)
    }

    @MainActor
    func testShortcutIntentStartsThenStopsRecording() async throws {
        let service = RecordingService.shared
        service.stop()

        _ = try await ToggleRecordingIntent().perform()
        XCTAssertTrue(service.isRecording)
        let options = AVAudioSession.sharedInstance().categoryOptions
        XCTAssertTrue(options.contains(.mixWithOthers))
        XCTAssertTrue(options.contains(.allowBluetoothA2DP), "Recording must keep Bluetooth music output available.")

        _ = try await ToggleRecordingIntent().perform()
        XCTAssertFalse(service.isRecording)
    }
}
