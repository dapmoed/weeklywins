import AVFoundation
import XCTest
@testable import WeeklyWins

final class RecorderSyncTests: XCTestCase {
    @MainActor
    func testRecorderRetriesInterruptedTransfersAndKeepsOriginalDate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = RecorderEndpointFixture()
        RecorderURLProtocol.fixture = fixture
        defer { RecorderURLProtocol.fixture = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecorderURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = RecorderSyncClient(session: session)

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
}

private struct RecorderFixtureTranscriber: Transcriber {
    let canTranscribeWithoutAuthorizationPrompt = false

    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String {
        let audio = try AVAudioFile(forReading: audioFileURL)
        guard audio.length == 1_600 else { throw RecorderSyncError.invalidRecording }
        return "Запись с диктофона"
    }
}

private final class RecorderEndpointFixture: @unchecked Sendable {
    let id = UUID()
    let recordedAt = Date(timeIntervalSince1970: 1_795_550_400)
    private let lock = NSLock()
    private var history: [String] = []
    private var acknowledged = false

    var requests: [String] { lock.withLock { history } }

    func respond(to request: URLRequest) -> (Int, Data) {
        lock.withLock {
            guard let url = request.url, request.value(forHTTPHeaderField: "X-WeeklyWins-Recorder") == "1" else {
                return (403, Data())
            }
            switch (request.httpMethod, url.path) {
            case ("POST", "/clock"):
                guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value,
                      let seconds = Double(value), abs(seconds - Date.now.timeIntervalSince1970) < 60 else { return (400, Data()) }
                history.append("clock")
                return (204, Data())
            case ("GET", "/recordings"):
                history.append("list")
                let json = acknowledged ? "[]" : #"[{"id":"\#(id.uuidString.lowercased())","recordedAt":\#(Int(recordedAt.timeIntervalSince1970))}]"#
                return (200, Data(json.utf8))
            case ("GET", "/recording"):
                guard url.query == "id=\(id.uuidString)" else { return (404, Data()) }
                let failFirstDownload = !history.contains("download")
                history.append("download")
                if failFirstDownload { return (503, Data()) }
                var wav = Data(base64Encoded: "UklGRqQMAABXQVZFZm10IBAAAAABAAEAgD4AAAB9AAACABAAZGF0YYAMAAA=")!
                wav.append(Data(count: 3_200))
                return (200, wav)
            case ("DELETE", "/recording"):
                guard url.query == "id=\(id.uuidString)" else { return (404, Data()) }
                let failFirstAck = !history.contains("ack")
                history.append("ack")
                if failFirstAck { return (503, Data()) }
                acknowledged = true
                return (204, Data())
            default:
                return (404, Data())
            }
        }
    }
}

private final class RecorderURLProtocol: URLProtocol, @unchecked Sendable {
    static var fixture: RecorderEndpointFixture?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let fixture = Self.fixture, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = fixture.respond(to: request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
