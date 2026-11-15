import AVFoundation
import Foundation

struct RecordingSummary: Identifiable, Equatable {
    let fileURL: URL
    let recordedAt: Date
    let duration: TimeInterval?

    var id: String { fileURL.lastPathComponent }
}

enum RecordingLibrary {
    static func scan(directory: URL) -> [RecordingSummary] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.lastPathComponent.hasPrefix("recording-") && $0.pathExtension == "m4a" }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
                let player = try? AVAudioPlayer(contentsOf: url)
                return RecordingSummary(
                    fileURL: url,
                    recordedAt: values?.contentModificationDate ?? values?.creationDate ?? .distantPast,
                    duration: player?.duration
                )
            }
            .sorted { $0.recordedAt > $1.recordedAt }
    }
}
