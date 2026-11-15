import AppIntents
import OSLog

struct ToggleRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Начать или остановить запись"
    static let description = IntentDescription("Переключает запись голосовой заметки.")
    static let supportedModes: IntentModes = [.background]
    private static let logger = Logger(subsystem: "com.weeklywins.app", category: "RecordingIntent")

    func perform() async throws -> some IntentResult {
        Self.logger.info("perform entered pid=\(ProcessInfo.processInfo.processIdentifier) mode=\(String(describing: systemContext.currentMode), privacy: .public)")
        do {
            try await RecordingService.shared.toggle()
            Self.logger.info("toggle completed")
            let isRecording = await RecordingService.shared.isRecording
            let message = isRecording ? "Запись началась" : "Запись остановлена"
            return .result(dialog: IntentDialog(stringLiteral: message))
        } catch {
            Self.logger.error("toggle failed: \(Self.errorSummary(error), privacy: .public)")
            return .result(dialog: Self.failureDialog(for: error))
        }
    }

    private static func errorSummary(_ error: Error) -> String {
        let error = error as NSError
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        return "domain=\(error.domain) code=\(error.code) underlying=\(underlying.map { "\($0.domain):\($0.code)" } ?? "none")"
    }

    private static func failureDialog(for error: Error) -> IntentDialog {
        let error = error as NSError
        return IntentDialog(stringLiteral: "Запись не запущена: \(error.domain), код \(error.code).")
    }
}

struct WeeklyWinsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleRecordingIntent(),
            phrases: ["Переключить запись в \(.applicationName)"],
            shortTitle: "Запись",
            systemImageName: "mic"
        )
    }
}
