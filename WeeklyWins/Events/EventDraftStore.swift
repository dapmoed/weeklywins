import Foundation

struct EventDraftStore {
    var defaults: UserDefaults = .standard

    private struct Snapshot: Codable {
        let event: DiaryEvent
        let baseline: DiaryEvent?
    }

    func save(_ event: DiaryEvent, baseline: DiaryEvent? = nil) throws {
        let data = try JSONEncoder().encode(Snapshot(event: event, baseline: baseline))
        defaults.set(data, forKey: key(event.id))
    }

    func load(for event: DiaryEvent) -> DiaryEvent? {
        guard let data = defaults.data(forKey: key(event.id)) else { return nil }
        if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            guard snapshot.baseline == nil || snapshot.baseline == event,
                  snapshot.event.id == event.id, snapshot.event.recordingID == event.recordingID else { return nil }
            return snapshot.event
        }
        // Read drafts saved before baseline tracking was introduced.
        guard let draft = try? JSONDecoder().decode(DiaryEvent.self, from: data),
              draft.id == event.id, draft.recordingID == event.recordingID else { return nil }
        return draft
    }

    func remove(id: UUID) { defaults.removeObject(forKey: key(id)) }

    private func key(_ id: UUID) -> String { "event-draft-\(id.uuidString)" }
}

struct EventReviewDraft: Codable, Equatable {
    var baseline: [DiaryEvent]
    var events: [DiaryEvent]
    var mergeProposal: DiaryEvent?
    var mergingEventID: UUID?
}

struct EventReviewDraftStore {
    var defaults: UserDefaults = .standard

    func save(_ draft: EventReviewDraft, recordingID: UUID) throws {
        defaults.set(try JSONEncoder().encode(draft), forKey: key(recordingID))
    }

    func load(recordingID: UUID) -> EventReviewDraft? {
        guard let data = defaults.data(forKey: key(recordingID)),
              let draft = try? JSONDecoder().decode(EventReviewDraft.self, from: data) else { return nil }
        let allEvents = draft.baseline + draft.events + [draft.mergeProposal].compactMap { $0 }
        guard allEvents.allSatisfy({ $0.recordingID == recordingID }) else { return nil }
        return draft
    }

    func remove(recordingID: UUID) { defaults.removeObject(forKey: key(recordingID)) }

    private func key(_ id: UUID) -> String { "event-review-draft-\(id.uuidString)" }
}
