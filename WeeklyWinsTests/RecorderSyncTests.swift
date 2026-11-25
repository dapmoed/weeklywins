import AVFoundation
import Foundation
import XCTest
@testable import WeeklyWins

final class RecorderSyncTests: XCTestCase {
    @MainActor
    func testRecorderRetriesInterruptedTransfersAndKeepsOriginalDate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = RecorderEndpointFixture()
        let client = RecorderSyncClient(partialDirectory: directory.appendingPathComponent("parts"), exchange: fixture.respond)

        let store = RecordingStore(directory: directory)
        let phone = try store.beginRecording(startedAt: fixture.recordedAt.addingTimeInterval(300))
        try Data([1, 2, 3]).write(to: store.fileURL(for: phone))
        try store.finalizeRecording(id: phone.id, duration: 1)
        try store.updateTranscription(recordingID: phone.id, transcript: "Запись с телефона",
                                      processingState: .completed, errorMessage: nil)

        let service = RecordingService(recordingDirectory: directory, transcriber: RecorderFixtureTranscriber(),
                                       isApplicationActive: { false })
        do {
            _ = try await service.synchronizeRecorder(using: client)
            XCTFail("The initial download should fail.")
        } catch { XCTAssertEqual(fixture.requests, ["clock", "list", "download"]) }
        XCTAssertEqual(service.recordings.map(\.id), [phone.id])

        do {
            _ = try await service.synchronizeRecorder(using: client)
            XCTFail("The first acknowledgement should be interrupted.")
        } catch { XCTAssertTrue(fixture.requests.suffix(4).elementsEqual(["clock", "list", "download", "ack"])) }
        let imported = try XCTUnwrap(service.recordings.first { $0.id == fixture.id })
        XCTAssertEqual(imported.recordedAt, fixture.recordedAt)
        XCTAssertEqual(imported.duration, 0.1)
        XCTAssertEqual(imported.automaticTranscriptionPending, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: imported).path))

        // Re-create the service so the retry has to use the on-disk import ID.
        let reopened = RecordingService(recordingDirectory: directory, transcriber: RecorderFixtureTranscriber(),
                                        isApplicationActive: { false })
        let duplicates = try await reopened.synchronizeRecorder(using: client)
        XCTAssertEqual(duplicates, 0)
        XCTAssertTrue(fixture.requests.suffix(3).elementsEqual(["clock", "list", "ack"]))
        let empty = try await reopened.synchronizeRecorder(using: client)
        XCTAssertEqual(empty, 0)
        XCTAssertTrue(fixture.requests.suffix(2).elementsEqual(["clock", "list"]))
        XCTAssertEqual(reopened.recordings.filter { $0.id == fixture.id }.count, 1)

        _ = try await reopened.transcribe(recordingID: fixture.id, userInitiated: false)
        let reloaded = RecordingStore(directory: directory)
        for period in [ReportPeriod.day, .week, .month] {
            let events = ReportQuery.events(in: reloaded.recordings, period: period, date: fixture.recordedAt)
            XCTAssertEqual(events.map(\.event.text), ["Запись с телефона", "Запись с диктофона"], period.rawValue)
        }
    }
    @MainActor
    func testBluetoothDownloadResumesAtLastCompleteWindow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let wav = fixtureWAV(sampleBytes: 16_000)
        let firstWindow = RecorderSyncClient.windowSize
        var offsets: [Int] = []
        var fails = true
        let exchange: (RecorderBLECommand, Data) async throws -> Data = { command, payload in
            if command == .open { return uint32Bytes(UInt32(wav.count)) }
            XCTAssertEqual(command, .read)
            let offset = Int(payload.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) })
            offsets.append(offset)
            if offset == firstWindow && fails {
                fails = false
                throw RecorderSyncError.disconnected
            }
            return wav.subdata(in: offset..<min(offset + firstWindow, wav.count))
        }
        do {
            _ = try await RecorderSyncClient(partialDirectory: directory, exchange: exchange).audio(for: id)
            XCTFail("The second window should fail once.")
        } catch RecorderSyncError.disconnected {}
        let bytes = try await RecorderSyncClient(partialDirectory: directory, exchange: exchange).audio(for: id)
        XCTAssertEqual(bytes, wav)
        XCTAssertEqual(offsets, [0, firstWindow, firstWindow])
    }

    func testRecorderReplyChecksOffsetAndFinalFragment() throws {
        var response = RecorderBLEReply(tag: 42)
        XCTAssertNil(try response.consume(Data([42, 0, 0, 0, 10, 11])))
        XCTAssertThrowsError(try response.consume(Data([42, 0x80, 3, 0, 12])))
        XCTAssertEqual(try response.consume(Data([42, 0x80, 2, 0, 12])), Data([10, 11, 12]))
    }

}

private struct RecorderFixtureTranscriber: Transcriber {
    let canTranscribeWithoutAuthorizationPrompt = false

    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String {
        let audio = try AVAudioFile(forReading: audioFileURL)
        guard audio.length == 1_600 else { throw RecorderSyncError.invalidRecording }
        return "Запись с диктофона"
    }
}

@MainActor
private final class RecorderEndpointFixture {
    let id = UUID()
    let recordedAt = Date(timeIntervalSince1970: 1_795_550_400)
    private(set) var requests: [String] = []
    private var acknowledged = false

    func respond(to command: RecorderBLECommand, payload: Data) throws -> Data {
        switch command {
        case .clock:
            XCTAssertEqual(payload.count, 4)
            requests.append("clock")
            return Data()
        case .list:
            XCTAssertEqual(payload, Data([1]))
            requests.append("list")
            return acknowledged ? Data() : uuidBytes(id) + uint32Bytes(UInt32(recordedAt.timeIntervalSince1970))
        case .open:
            XCTAssertEqual(payload, uuidBytes(id))
            let fail = !requests.contains("download")
            requests.append("download")
            if fail { throw RecorderSyncError.disconnected }
            return uint32Bytes(3_244)
        case .read:
            XCTAssertEqual(payload, uint32Bytes(0))
            return fixtureWAV(sampleBytes: 3_200)
        case .acknowledge:
            XCTAssertEqual(payload, uuidBytes(id))
            let fail = !requests.contains("ack")
            requests.append("ack")
            if fail { throw RecorderSyncError.disconnected }
            acknowledged = true
            return Data()
        }
    }
}

private func uuidBytes(_ id: UUID) -> Data { withUnsafeBytes(of: id.uuid) { Data($0) } }

private func uint32Bytes(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}

private func fixtureWAV(sampleBytes: Int) -> Data {
    var wav = Data(base64Encoded: "UklGRqQMAABXQVZFZm10IBAAAAABAAEAgD4AAAB9AAACABAAZGF0YYAMAAA=")!
    wav.replaceSubrange(4..<8, with: uint32Bytes(UInt32(36 + sampleBytes)))
    wav.replaceSubrange(40..<44, with: uint32Bytes(UInt32(sampleBytes)))
    wav.append(Data(count: sampleBytes))
    return wav
}
