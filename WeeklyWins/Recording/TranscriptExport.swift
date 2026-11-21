import Foundation

struct TranscriptExport: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var id: UUID?
        var recordedAt: Date
        var duration: TimeInterval?
        var transcript: String?
    }

    var app: String
    var exportedAt: Date
    var recordings: [Entry]

    var fileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let count = recordings.count
        let recordLabel = count == 1 ? "record" : "records"
        return "weeklywins-backup-\(count)-\(recordLabel)-\(formatter.string(from: exportedAt)).json"
    }

    static func make(recordings: [Recording], exportedAt: Date = .now) -> TranscriptExport {
        let entries = recordings
            .filter { $0.deletedAt == nil }
            .sorted { $0.recordedAt < $1.recordedAt }
            .map { recording in
                Entry(id: recording.id, recordedAt: recording.recordedAt,
                      duration: recording.duration, transcript: recording.transcript)
            }
        return TranscriptExport(app: "weeklywins", exportedAt: exportedAt, recordings: entries)
    }

    func fileData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
