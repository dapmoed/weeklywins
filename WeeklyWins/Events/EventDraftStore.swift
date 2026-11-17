import Foundation

struct EventDraftStore {
    var defaults: UserDefaults = .standard

    func save(_ event: DiaryEvent) throws {
        let data = try JSONEncoder().encode(event)
        defaults.set(data, forKey: key(event.id))
    }

    func load(for event: DiaryEvent) -> DiaryEvent? {
        guard let data = defaults.data(forKey: key(event.id)),
              let draft = try? JSONDecoder().decode(DiaryEvent.self, from: data),
              draft.id == event.id, draft.recordingID == event.recordingID else { return nil }
        return draft
    }

    func remove(id: UUID) { defaults.removeObject(forKey: key(id)) }

    private func key(_ id: UUID) -> String { "event-draft-\(id.uuidString)" }
}
