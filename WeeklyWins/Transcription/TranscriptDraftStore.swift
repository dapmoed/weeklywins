import Foundation

struct TranscriptDraftStore {
    var defaults: UserDefaults = .standard

    func save(recordingID: UUID, text: String) { defaults.set(text, forKey: key(recordingID)) }
    func load(recordingID: UUID) -> String? { defaults.string(forKey: key(recordingID)) }
    func remove(recordingID: UUID) { defaults.removeObject(forKey: key(recordingID)) }
    func remove(recordingID: UUID, matching text: String) {
        if load(recordingID: recordingID) == text { remove(recordingID: recordingID) }
    }
    private func key(_ id: UUID) -> String { "transcript-draft-\(id.uuidString)" }
}
