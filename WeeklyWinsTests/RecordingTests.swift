import AVFoundation
import XCTest
@testable import WeeklyWins

final class RecordingTests: XCTestCase {
    @MainActor
    func testSavedRecordingCanBePlayedAndRecordingStopsPlayback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = RecordingService(recordingDirectory: directory, maxRecordingDuration: 10)
        try await service.start()
        try await Task.sleep(for: .milliseconds(350))
        service.stop()
        let recording = try XCTUnwrap(service.recordings.first)
        try service.playRecording(id: recording.id)
        XCTAssertEqual(service.playingRecordingID, recording.id)
        try service.togglePlayback(id: recording.id)
        XCTAssertFalse(service.isAudioPlaying)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(service.playingRecordingID, recording.id)
        service.seekPlayback(to: 999)
        XCTAssertLessThanOrEqual(service.playbackPosition, service.playbackDuration)
        service.seekPlayback(to: -10)
        XCTAssertEqual(service.playbackPosition, 0)
        try service.togglePlayback(id: recording.id)
        XCTAssertTrue(service.isAudioPlaying)
        try await service.start()
        defer { service.stop() }
        XCTAssertNil(service.playingRecordingID)
        XCTAssertTrue(service.isRecording)
    }

    @MainActor
    func testRecoveryAfterRenameBeforeManifestCommitKeepsOneIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordingStore(directory: directory)
        let pending = try store.beginRecording()
        let partial = store.fileURL(for: pending)
        try Data([1, 2, 3]).write(to: partial)
        let final = directory.appendingPathComponent("recording-\(pending.id.uuidString).m4a")
        try FileManager.default.moveItem(at: partial, to: final)
        let restored = RecordingStore(directory: directory)
        XCTAssertEqual(restored.recordings.count, 1)
        XCTAssertEqual(restored.recordings.first?.id, pending.id)
        XCTAssertEqual(restored.recordings.first?.fileName, final.lastPathComponent)
    }

    @MainActor
    func testStoreImportsLegacyRecordingsAndPreservesTheirTimestamp() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recordedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let legacyURL = directory.appendingPathComponent("recording-\(UUID().uuidString).m4a")
        try Data([0, 1, 2, 3]).write(to: legacyURL)
        try FileManager.default.setAttributes([.modificationDate: recordedAt], ofItemAtPath: legacyURL.path)

        let store = RecordingStore(directory: directory)
        let recordings = store.recordings

        XCTAssertEqual(recordings.count, 1)
        XCTAssertEqual(recordings.first?.recordedAt, recordedAt)
        XCTAssertEqual(recordings.first?.state, .saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @MainActor
    func testStoreRecoversInterruptedRecordingWithoutDeletingAudio() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeBeforeRelaunch = RecordingStore(directory: directory)
        let pending = try storeBeforeRelaunch.beginRecording(startedAt: Date(timeIntervalSince1970: 1_700_000_100))
        let partialURL = storeBeforeRelaunch.fileURL(for: pending)
        let partialAudio = Data([0, 1, 2, 3, 4, 5])
        try partialAudio.write(to: partialURL)

        let storeAfterRelaunch = RecordingStore(directory: directory)
        let recoveredRecordings = storeAfterRelaunch.recordings
        let recovered = try XCTUnwrap(recoveredRecordings.first)
        let recoveredURL = storeAfterRelaunch.fileURL(for: recovered)
        let recoveredAudio = try Data(contentsOf: recoveredURL)

        XCTAssertEqual(recovered.id, pending.id)
        XCTAssertEqual(recovered.state, .interrupted)
        XCTAssertEqual(recoveredAudio, partialAudio)
    }

    @MainActor
    func testFinalizationConflictKeepsPartialFileAndManifestReference() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = RecordingStore(directory: directory)
        let pending = try store.beginRecording()
        let partialURL = store.fileURL(for: pending)
        let partialAudio = Data([1, 2, 3, 4])
        try partialAudio.write(to: partialURL)
        try Data([9, 9, 9]).write(to: directory.appendingPathComponent("recording-\(pending.id.uuidString).m4a"))

        var finalizationError: Error?
        do {
            try store.finalizeRecording(id: pending.id, duration: 0.1)
        } catch {
            finalizationError = error
        }

        XCTAssertNotNil(finalizationError)
        XCTAssertEqual(store.recordings.first?.fileName, pending.fileName)
        XCTAssertEqual(try Data(contentsOf: partialURL), partialAudio)
    }

    @MainActor
    func testMaximumDurationAutomaticallyFinalizesRecording() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let service = RecordingService(recordingDirectory: directory, maxRecordingDuration: 0.15)
        try await service.start()
        defer { service.stop() }
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertFalse(service.isRecording)
        XCTAssertGreaterThan(service.recordings.first?.duration ?? 0, 0)
        XCTAssertEqual(service.recordings.count, 1)
        XCTAssertEqual(service.recordings.first?.state, .saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(try XCTUnwrap(service.recordings.first?.fileName)).path))
    }

    @MainActor
    func testStoppingTwiceFinalizesOneRecording() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let service = RecordingService(recordingDirectory: directory, maxRecordingDuration: 10)
        try await service.start()
        defer { service.stop() }
        try await Task.sleep(for: .milliseconds(100))
        service.stop()
        service.stop()

        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(service.recordings.count, 1)
        XCTAssertEqual(service.recordings.first?.state, .saved)
    }

    @MainActor
    func testConcurrentStartRequestsCreateOneActiveRecording() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let service = RecordingService(recordingDirectory: directory, maxRecordingDuration: 10)
        async let firstStart: Void = service.start()
        async let secondStart: Void = service.start()
        _ = try await (firstStart, secondStart)
        defer { service.stop() }

        XCTAssertTrue(service.isRecording)
        service.stop()
        XCTAssertEqual(service.recordings.count, 1)
        XCTAssertEqual(service.recordings.first?.state, .saved)
    }

    @MainActor
    func testAudioInterruptionFinalizesRecordingAsInterrupted() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let service = RecordingService(recordingDirectory: directory, maxRecordingDuration: 10)
        try await service.start()
        defer { service.stop() }
        let interruption = Notification(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        NotificationCenter.default.post(interruption)

        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(service.recordings.count, 1)
        XCTAssertEqual(service.recordings.first?.state, .interrupted)
        XCTAssertEqual(service.status, "Запись прервана и сохранена")
    }
}
