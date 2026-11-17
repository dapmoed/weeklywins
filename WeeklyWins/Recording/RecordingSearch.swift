import Foundation

enum RecordingSearch {
    static func matches(_ recording: Recording, query: String) -> Bool {
        let query = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return true }
        let locale = Locale(identifier: "ru_RU")
        let date = recording.recordedAt.formatted(.dateTime.day().month(.wide).year().locale(locale))
        let numericDate = recording.recordedAt.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(locale))
        let events = (recording.events ?? []).map { "\($0.text) \($0.category.title)" }.joined(separator: " ")
        let searchable = [recording.transcript ?? "", events, date, numericDate].joined(separator: " ")
        return normalized(searchable).contains(query)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
    }
}

enum RecordingManagementError: LocalizedError {
    case busy
    case audioDeletionPending
    var errorDescription: String? {
        switch self {
        case .busy: return "Сначала завершите запись или расшифровку."
        case .audioDeletionPending: return "Запись скрыта. Не удалось удалить аудиофайл, удаление повторится после запуска приложения."
        }
    }
}
