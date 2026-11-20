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
    private struct DeletionHistory: Codable, Equatable {
        // IDs for visible and deleted events in their shared order.
        var order: [UUID]
        var deleted: [DiaryEvent] = []
    }

    var baseline: [DiaryEvent]
    private(set) var events: [DiaryEvent]
    var mergeProposal: DiaryEvent?
    var mergingEventID: UUID?
    private var deletionHistory: DeletionHistory?

    init(baseline: [DiaryEvent], events: [DiaryEvent]) {
        self.baseline = baseline
        self.events = events
    }

    var hasDeletedEvents: Bool { deletionHistory?.deleted.isEmpty == false }

    mutating func addEvent(_ event: DiaryEvent) {
        events.append(event)
        deletionHistory?.order.append(event.id)
    }

    mutating func updateEvent(_ event: DiaryEvent) {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[index] = event
    }

    @discardableResult
    mutating func confirmMerge(_ merged: DiaryEvent, mergingEventID: UUID) -> Bool {
        guard let index = events.firstIndex(where: { $0.id == mergingEventID }),
              index > 0, events[index - 1].id == merged.id else { return false }
        events[index - 1] = merged
        events.remove(at: index)
        deletionHistory?.order.removeAll { $0 == mergingEventID }
        mergeProposal = nil
        self.mergingEventID = nil
        return true
    }

    mutating func deleteEvent(id: UUID) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        var history = deletionHistory ?? DeletionHistory(order: events.map(\.id))
        history.deleted.append(events.remove(at: index))
        deletionHistory = history
    }

    mutating func undoDeletion() -> UUID? {
        guard var history = deletionHistory, let event = history.deleted.popLast(),
              let position = history.order.firstIndex(of: event.id) else { return nil }
        let followingIDs = Set(history.order.suffix(from: position + 1))
        let index = events.firstIndex { followingIDs.contains($0.id) } ?? events.endIndex
        events.insert(event, at: index)
        deletionHistory = history.deleted.isEmpty ? nil : history
        return event.id
    }

    fileprivate func belongs(to recordingID: UUID) -> Bool {
        let deleted = deletionHistory?.deleted ?? []
        let allEvents = baseline + events + deleted + [mergeProposal].compactMap { $0 }
        guard allEvents.allSatisfy({ $0.recordingID == recordingID }) else { return false }
        guard let deletionHistory else { return true }
        let activeIDs = events.map(\.id)
        let deletedIDs = Set(deleted.map(\.id))
        let order = deletionHistory.order
        return order.count == activeIDs.count + deleted.count
            && Set(order) == Set(activeIDs).union(deletedIDs)
            && order.filter { !deletedIDs.contains($0) } == activeIDs
    }
}

struct EventReviewDraftStore {
    var defaults: UserDefaults = .standard

    func save(_ draft: EventReviewDraft, recordingID: UUID) throws {
        defaults.set(try JSONEncoder().encode(draft), forKey: key(recordingID))
    }

    func load(recordingID: UUID) -> EventReviewDraft? {
        guard let data = defaults.data(forKey: key(recordingID)),
              let draft = try? JSONDecoder().decode(EventReviewDraft.self, from: data),
              draft.belongs(to: recordingID) else { return nil }
        return draft
    }

    func remove(recordingID: UUID) { defaults.removeObject(forKey: key(recordingID)) }

    private func key(_ id: UUID) -> String { "event-review-draft-\(id.uuidString)" }
}
