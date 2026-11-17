import Foundation

enum RecordingState: String, Codable, Equatable {
    case recording
    case saved
    case interrupted
    case failed

    var displayName: String {
        switch self {
        case .recording: return "Записывается"
        case .saved: return "Сохранена"
        case .interrupted: return "Прервана"
        case .failed: return "Ошибка"
        }
    }
}

enum RecordingProcessingState: String, Codable, Equatable {
    case pending
    case processing
    case completed
    case failed
}

struct Recording: Identifiable, Codable, Equatable {
    let id: UUID
    let recordedAt: Date
    var duration: TimeInterval?
    var fileName: String
    var state: RecordingState
    var processingState: RecordingProcessingState
    var errorMessage: String?
    var transcript: String?
    var transcriptUpdatedAt: Date?
    var events: [DiaryEvent]?
    var eventsManuallyEdited: Bool?
    var deletedAt: Date?
    var deletedEventIDs: [UUID]?
    var automaticTranscriptionPending: Bool?

    init(
        id: UUID,
        recordedAt: Date,
        duration: TimeInterval? = nil,
        fileName: String,
        state: RecordingState,
        processingState: RecordingProcessingState = .pending,
        errorMessage: String? = nil,
        transcript: String? = nil,
        transcriptUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.duration = duration
        self.fileName = fileName
        self.state = state
        self.processingState = processingState
        self.errorMessage = errorMessage
        self.transcript = transcript
        self.transcriptUpdatedAt = transcriptUpdatedAt
    }
}
