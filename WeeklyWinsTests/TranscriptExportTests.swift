import XCTest
@testable import WeeklyWins

final class TranscriptExportTests: XCTestCase {
    private func makeRecording(recordedAt: Date, transcript: String? = "Текст", deleted: Bool = false) -> Recording {
        var recording = Recording(id: UUID(), recordedAt: recordedAt, fileName: "fixture.m4a", state: .saved)
        recording.transcript = transcript
        if deleted { recording.deletedAt = .now }
        return recording
    }

    func testMakeIncludesActiveRecordingsOnlySortedAscending() {
        let old = makeRecording(recordedAt: Date(timeIntervalSince1970: 1_000))
        let mid = makeRecording(recordedAt: Date(timeIntervalSince1970: 2_000))
        let new = makeRecording(recordedAt: Date(timeIntervalSince1970: 3_000))
        let deleted = makeRecording(recordedAt: Date(timeIntervalSince1970: 4_000), deleted: true)

        let export = TranscriptExport.make(recordings: [new, deleted, old, mid])

        XCTAssertEqual(export.app, "weeklywins")
        XCTAssertEqual(export.recordings.map(\.id), [old.id, mid.id, new.id])
    }

    func testFileDataRoundTripsAndIncludesId() throws {
        let recording = makeRecording(recordedAt: Date(timeIntervalSince1970: 2_000), transcript: "Купил хлеб")
        let export = TranscriptExport.make(recordings: [recording], exportedAt: Date(timeIntervalSince1970: 5_000))

        let data = try export.fileData()
        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(raw.contains("\"id\""), raw)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TranscriptExport.self, from: data)
        XCTAssertEqual(decoded, export)
    }

    func testDecodesLegacyFormatWithoutId() throws {
        let json = """
        {
          "app": "weeklywins",
          "exportedAt": "2026-11-21T12:00:00+05:00",
          "recordings": [
            { "recordedAt": "2026-11-15T09:41:00+05:00", "duration": 720, "transcript": "Текст" }
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(TranscriptExport.self, from: Data(json.utf8))
        XCTAssertEqual(export.recordings.count, 1)
        XCTAssertNil(export.recordings[0].id)
        XCTAssertEqual(export.recordings[0].duration, 720)
        XCTAssertEqual(export.recordings[0].transcript, "Текст")
    }
}
