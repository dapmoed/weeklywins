import AVFoundation
import Foundation

@MainActor
final class RecordingStore {
    let directory: URL
    private(set) var recordings: [Recording] = []

    private let fileManager: FileManager
    private let manifestURL: URL
    private var initializationError: Error?

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        manifestURL = directory.appendingPathComponent("recordings.json")

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: manifestURL.path) {
                let data = try Data(contentsOf: manifestURL)
                recordings = try JSONDecoder().decode([Recording].self, from: data)
            }
            purgeDeletedAudio()
            try recoverIncompleteRecordings()
            try importLegacyAudioFiles()
            var importedEvents = false
            for index in recordings.indices where recordings[index].events == nil && recordings[index].deletedAt == nil {
                if let transcript = recordings[index].transcript {
                    recordings[index].events = EventExtractor.extract(transcript, recordingID: recordings[index].id)
                    recordings[index].eventsManuallyEdited = false
                    importedEvents = true
                }
            }
            if importedEvents { try persist() }
        } catch {
            initializationError = error
        }
        sortRecordings()
    }

    func beginRecording(startedAt: Date = .now, automaticTranscriptionPending: Bool = false) throws -> Recording {
        try validateReady()
        let id = UUID()
        var recording = Recording(
            id: id,
            recordedAt: startedAt,
            fileName: Self.partialFileName(for: id),
            state: .recording
        )
        recording.automaticTranscriptionPending = automaticTranscriptionPending
        let previous = recordings
        recordings.append(recording)
        sortRecordings()
        do { try persist() }
        catch { recordings = previous; throw error }
        return recording
    }

    func fileURL(for recording: Recording) -> URL {
        directory.appendingPathComponent(recording.fileName)
    }

    func updateTranscription(
        recordingID: UUID,
        transcript: String?,
        processingState: RecordingProcessingState,
        errorMessage: String?
    ) throws {
        try validateReady()
        guard let index = recordings.firstIndex(where: { $0.id == recordingID && $0.deletedAt == nil }) else {
            throw RecordingStoreError.recordingNotFound
        }

        let previous = recordings[index]
        if recordings[index].events == nil || recordings[index].eventsManuallyEdited == false,
           let transcript, processingState == .completed {
            recordings[index].events = EventExtractor.extract(transcript, recordingID: recordingID)
            recordings[index].eventsManuallyEdited = false
        }
        recordings[index].transcript = transcript
        recordings[index].transcriptUpdatedAt = transcript == nil ? nil : .now
        recordings[index].processingState = processingState
        if processingState == .completed || processingState == .failed {
            recordings[index].automaticTranscriptionPending = false
        }
        recordings[index].errorMessage = errorMessage
        do { try persist() }
        catch { recordings[index] = previous; throw error }
    }

    func saveEvents(recordingID: UUID, events: [DiaryEvent], expectedEvents: [DiaryEvent]? = nil) throws {
        try validateReady()
        guard events.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw EventEditingError.emptyTitle
        }
        guard let index = recordings.firstIndex(where: { $0.id == recordingID && $0.deletedAt == nil }),
              events.allSatisfy({ $0.recordingID == recordingID }) else {
            throw RecordingStoreError.recordingNotFound
        }
        if let expectedEvents, (recordings[index].events ?? []) != expectedEvents {
            throw EventEditingError.conflictingChanges
        }
        let previous = recordings[index]
        recordings[index].events = events
        recordings[index].eventsManuallyEdited = true
        do { try persist() }
        catch {
            recordings[index] = previous
            throw error
        }
        for event in previous.events ?? [] where events.first(where: { $0.id == event.id }) != event {
            EventDraftStore().remove(id: event.id)
        }
    }

    @discardableResult
    func finalizeRecording(
        id: UUID,
        duration: TimeInterval?,
        state: RecordingState = .saved,
        errorMessage: String? = nil
    ) throws -> Recording {
        try validateReady()
        guard let index = recordings.firstIndex(where: { $0.id == id }) else {
            throw RecordingStoreError.recordingNotFound
        }

        var recording = recordings[index]
        let currentURL = fileURL(for: recording)
        let finalFileName = Self.finalFileName(for: id)
        let finalURL = directory.appendingPathComponent(finalFileName)

        if currentURL != finalURL, fileManager.fileExists(atPath: currentURL.path) {
            if fileManager.fileExists(atPath: finalURL.path) {
                throw RecordingStoreError.destinationAlreadyExists
            }
            try fileManager.moveItem(at: currentURL, to: finalURL)
            recording.fileName = finalFileName
        } else if !fileManager.fileExists(atPath: finalURL.path), state != .failed {
            throw RecordingStoreError.audioFileMissing
        }

        recording.duration = duration
        recording.state = state
        if state == .failed { recording.automaticTranscriptionPending = false }
        recording.errorMessage = errorMessage
        recordings[index] = recording
        sortRecordings()
        try persist()
        return recording
    }

    func deleteRecording(id: UUID) throws {
        try validateReady()
        guard let index = recordings.firstIndex(where: { $0.id == id }) else {
            throw RecordingStoreError.recordingNotFound
        }
        guard recordings[index].state != .recording, recordings[index].processingState != .processing else {
            throw RecordingManagementError.busy
        }
        let previous = recordings[index]
        let eventIDs = Array(Set((previous.events ?? []).map(\.id) + (previous.deletedEventIDs ?? [])))
        recordings[index].deletedAt = .now
        recordings[index].deletedEventIDs = eventIDs
        recordings[index].transcript = nil
        recordings[index].transcriptUpdatedAt = nil
        recordings[index].events = []
        recordings[index].errorMessage = nil
        do { try persist() }
        catch { recordings[index] = previous; throw error }
        for eventID in eventIDs { EventDraftStore().remove(id: eventID) }
        TranscriptDraftStore().remove(recordingID: id)
        EventReviewDraftStore().remove(recordingID: id)
        let url = fileURL(for: previous)
        if fileManager.fileExists(atPath: url.path) {
            do { try fileManager.removeItem(at: url) }
            catch { throw RecordingManagementError.audioDeletionPending }
        }
    }

    private func purgeDeletedAudio() {
        for recording in recordings where recording.deletedAt != nil {
            TranscriptDraftStore().remove(recordingID: recording.id)
            EventReviewDraftStore().remove(recordingID: recording.id)
            for id in recording.deletedEventIDs ?? [] { EventDraftStore().remove(id: id) }
            let url = fileURL(for: recording)
            if fileManager.fileExists(atPath: url.path) { try? fileManager.removeItem(at: url) }
        }
    }

    private func validateReady() throws {
        if let initializationError {
            throw RecordingStoreError.storageUnavailable(initializationError.localizedDescription)
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(recordings)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func importLegacyAudioFiles() throws {
        let knownFileNames = Set(recordings.map(\.fileName))
        let legacy = RecordingLibrary.scan(directory: directory)
            .filter { !$0.fileURL.lastPathComponent.contains(".partial.") }

        for summary in legacy where !knownFileNames.contains(summary.fileURL.lastPathComponent) {
            let name = summary.fileURL.deletingPathExtension().lastPathComponent
            let id = UUID(uuidString: String(name.dropFirst("recording-".count))) ?? UUID()
            recordings.append(Recording(
                id: id,
                recordedAt: summary.recordedAt,
                duration: summary.duration,
                fileName: summary.fileURL.lastPathComponent,
                state: .saved
            ))
        }

        if !legacy.isEmpty {
            try persist()
        }
    }

    private func recoverIncompleteRecordings() throws {
        var didChange = false
        for index in recordings.indices where recordings[index].state == .recording && recordings[index].deletedAt == nil {
            let recording = recordings[index]
            let partialURL = fileURL(for: recording)
            let finalURL = directory.appendingPathComponent(Self.finalFileName(for: recording.id))

            if fileManager.fileExists(atPath: finalURL.path) {
                recordings[index].fileName = finalURL.lastPathComponent
                recordings[index].duration = (try? AVAudioPlayer(contentsOf: finalURL).duration)
                recordings[index].state = .saved
                recordings[index].errorMessage = nil
            } else if fileManager.fileExists(atPath: partialURL.path) {
                recordings[index].state = .interrupted
                recordings[index].errorMessage = "Запись была прервана; исходный аудиофайл сохранён."
            } else {
                recordings[index].state = .failed
                recordings[index].automaticTranscriptionPending = false
                recordings[index].errorMessage = "Файл записи не найден после перезапуска."
            }
            didChange = true
        }

        for index in recordings.indices where recordings[index].processingState == .processing && recordings[index].deletedAt == nil {
            let automatic = recordings[index].automaticTranscriptionPending == true
            recordings[index].processingState = automatic ? .pending : .failed
            recordings[index].errorMessage = automatic
                ? "Расшифровка будет продолжена."
                : "Расшифровка прервана. Можно повторить обработку."
            didChange = true
        }
        if didChange {
            try persist()
        }
    }

    private func sortRecordings() {
        recordings.sort { $0.recordedAt > $1.recordedAt }
    }

    private static func partialFileName(for id: UUID) -> String {
        "recording-\(id.uuidString).partial.m4a"
    }

    private static func finalFileName(for id: UUID) -> String {
        "recording-\(id.uuidString).m4a"
    }
}

enum RecordingStoreError: LocalizedError {
    case storageUnavailable(String)
    case recordingNotFound
    case destinationAlreadyExists
    case audioFileMissing

    var errorDescription: String? {
        switch self {
        case .storageUnavailable(let details): return "Хранилище записей недоступно: \(details)"
        case .recordingNotFound: return "Запись не найдена в локальном индексе."
        case .destinationAlreadyExists: return "Файл записи с таким именем уже существует."
        case .audioFileMissing: return "Аудиофайл записи не найден."
        }
    }
}
