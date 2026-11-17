import Foundation

enum EventCategory: String, Codable, CaseIterable, Identifiable {
    case unclassified, work, home
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unclassified: return "Без категории"
        case .work: return "Работа"
        case .home: return "Дом"
        }
    }
}

enum EventCompletion: String, Codable, CaseIterable, Identifiable {
    case completed, notCompleted
    var id: String { rawValue }
    var title: String { self == .completed ? "Сделано" : "Не сделано" }
}

struct DiaryEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    let recordingID: UUID
    var sourceText: String
    var text: String
    var category: EventCategory = .unclassified
    var completion: EventCompletion = .completed
    var occurredAt: Date?
    var duration: TimeInterval?
}


enum EventEditingError: LocalizedError {
    case emptyTitle
    case conflictingChanges

    var errorDescription: String? {
        switch self {
        case .emptyTitle: return "Укажите название дела."
        case .conflictingChanges: return "Список событий изменился. Черновик сохранён. Закройте редактор и откройте актуальный список, отбросив черновик."
        }
    }
}
