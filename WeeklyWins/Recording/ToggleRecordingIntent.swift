import AppIntents
import OSLog

struct ToggleRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Начать или остановить запись"
    static let description = IntentDescription("Переключает запись голосовой заметки.")
    static let supportedModes: IntentModes = [.background]
    private static let logger = Logger(subsystem: "com.weeklywins.app", category: "RecordingIntent")

    func perform() async throws -> some IntentResult {
        Self.logger.info("perform entered")
        do {
            try await RecordingService.shared.toggle()
            Self.logger.info("toggle completed")
        } catch {
            Self.logger.error("toggle failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        return .result()
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
