import Speech
import XCTest
@testable import WeeklyWins

private enum FixtureTranscriberError: Error {
    case unsupportedLanguage
}

private actor ScriptedTranscriptionResponses {
    private var responses: [Result<String, FixtureTranscriberError>]

    init(_ responses: [Result<String, FixtureTranscriberError>]) {
        self.responses = responses
    }

    func next() throws -> String {
        guard !responses.isEmpty else { throw FixtureTranscriberError.unsupportedLanguage }
        return try responses.removeFirst().get()
    }
}

private struct ScriptedTranscriber: Transcriber {
    let responses: ScriptedTranscriptionResponses

    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String {
        try await responses.next()
    }
}

final class TranscriptionTests: XCTestCase {
    func testOldTranscriptionCompletionCannotRemoveNewerDraft() throws {
        let suite = "draft-ownership-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let store = TranscriptDraftStore(defaults: defaults)
        store.save(recordingID: id, text: "Первый черновик")
        let original = try XCTUnwrap(store.load(recordingID: id))
        store.save(recordingID: id, text: "Новая правка")
        store.remove(recordingID: id, matching: original)
        XCTAssertEqual(store.load(recordingID: id), "Новая правка")
        store.remove(recordingID: id, matching: "Новая правка")
        XCTAssertNil(store.load(recordingID: id))
    }

    func testTranscriptDraftRestoresEmptyAndNonemptyEditsAndCanBeCleared() throws {
        let suite = "transcript-draft-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let store = TranscriptDraftStore(defaults: defaults)
        store.save(recordingID: id, text: "Исправленный текст")
        XCTAssertEqual(TranscriptDraftStore(defaults: defaults).load(recordingID: id), "Исправленный текст")
        store.save(recordingID: id, text: "")
        XCTAssertEqual(store.load(recordingID: id), "")
        store.remove(recordingID: id)
        XCTAssertNil(store.load(recordingID: id))
    }

    @available(iOS 26.0, *)
    func testSpeechTranscriberSupportsRussianAndReportsAssetStatus() async throws {
        let requestedLocale = Locale(identifier: "ru-RU")
        let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale)
        print("SPEECH_TRANSCRIBER_RU_SUPPORTED=\(supportedLocale != nil)")
        guard let supportedLocale else { return }
        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .transcription)
        let status = await AssetInventory.status(forModules: [transcriber])
        print("SPEECH_TRANSCRIBER_RU_LOCALE=\(supportedLocale.identifier)")
        print("SPEECH_TRANSCRIBER_RU_ASSET_STATUS=\(status)")
    }

    func testSystemSpeechRecognizerOnDeviceRussianAvailability() {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
        print("SYSTEM_SPEECH_RU_RECOGNIZER_AVAILABLE=\(recognizer != nil)")
        print("SYSTEM_SPEECH_RU_ON_DEVICE=\(recognizer?.supportsOnDeviceRecognition ?? false)")
    }

    @MainActor
    func testTranscriptionPersistsEditableTextWithoutDeletingAudio() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = RecordingStore(directory: directory)
        let recording = try makeSavedRecording(in: store)
        let transcriber = ScriptedTranscriber(responses: ScriptedTranscriptionResponses([.success("Проверил работу приложения.")]))
        let service = TranscriptionService(store: store, transcriber: transcriber)

        let transcript = try await service.transcribe(recordingID: recording.id, locale: Locale(identifier: "ru-RU"))
        let extractedEvents = try XCTUnwrap(store.recordings.first?.events)
        XCTAssertFalse(extractedEvents.isEmpty)
        try service.saveEditedTranscript(recordingID: recording.id, text: "Исправленный текст о работе приложения.")

        let reloadedStore = RecordingStore(directory: directory)
        let reloadedRecording = try XCTUnwrap(reloadedStore.recordings.first)
        XCTAssertEqual(transcript, "Проверил работу приложения.")
        XCTAssertEqual(reloadedRecording.transcript, "Исправленный текст о работе приложения.")
        XCTAssertEqual(reloadedRecording.events, extractedEvents)
        XCTAssertEqual(reloadedRecording.processingState, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reloadedStore.fileURL(for: reloadedRecording).path))
    }

    @MainActor
    func testTranscriptionFailureKeepsAudioAndRetryCanSucceed() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = RecordingStore(directory: directory)
        let recording = try makeSavedRecording(in: store)
        let transcriber = ScriptedTranscriber(responses: ScriptedTranscriptionResponses([
            .failure(.unsupportedLanguage),
            .success("Встретился с коллегой.")
        ]))
        let service = TranscriptionService(store: store, transcriber: transcriber)

        do {
            _ = try await service.transcribe(recordingID: recording.id, locale: Locale(identifier: "ru-RU"))
            XCTFail("The scripted unsupported-language result should fail.")
        } catch {}

        let failedRecord = try XCTUnwrap(store.recordings.first)
        XCTAssertEqual(failedRecord.processingState, .failed)
        XCTAssertNotNil(failedRecord.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: failedRecord).path))

        let retryText = try await service.transcribe(recordingID: recording.id, locale: Locale(identifier: "ru-RU"))
        XCTAssertEqual(retryText, "Встретился с коллегой.")
        XCTAssertEqual(store.recordings.first?.processingState, .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: recording).path))
    }

    @MainActor
    private func makeSavedRecording(in store: RecordingStore) throws -> Recording {
        let pending = try store.beginRecording()
        try Data([1, 2, 3, 4, 5]).write(to: store.fileURL(for: pending))
        return try store.finalizeRecording(id: pending.id, duration: 3)
    }
}
