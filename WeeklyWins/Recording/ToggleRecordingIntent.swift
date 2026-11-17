import AppIntents
import OSLog
import Foundation

struct ToggleRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Начать или остановить запись"
    static let description = IntentDescription("Переключает запись голосовой заметки.")
    static let supportedModes: IntentModes = [.background]
    private static let logger = Logger(subsystem: "com.weeklywins.app", category: "RecordingIntent")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await RecordingDiagnostics.write("intent entered")
        Self.logger.info("perform entered pid=\(ProcessInfo.processInfo.processIdentifier) mode=\(String(describing: systemContext.currentMode), privacy: .public)")
        do {
            try await RecordingService.shared.toggle()
            await RecordingDiagnostics.write("intent completed")
            Self.logger.info("toggle completed")
            let service = await RecordingService.shared
            let isRecording = await service.isRecording
            let isStarting = await service.isStarting
            let message = isRecording ? "Запись началась" : isStarting ? "Запись запускается" : "Запись остановлена"
            return .result(dialog: IntentDialog(stringLiteral: message))
        } catch {
            await RecordingDiagnostics.write("intent failed \(Self.errorSummary(error))")
            await RecordingService.shared.showError(error)
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


@MainActor
enum RecordingDiagnostics {
    static func write(_ message: String) {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent("recording-diagnostics.log")
        let line = "\(Date().ISO8601Format()) pid=\(ProcessInfo.processInfo.processIdentifier) \(message)\n"
        var data = (try? Data(contentsOf: url)) ?? Data()
        data.append(Data(line.utf8))
        if data.count > 64_000 { data = Data(data.suffix(32_000)) }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Logger(subsystem: "com.weeklywins.app", category: "Diagnostics").error("Diagnostic write failed: \(error.localizedDescription)")
        }
    }
}
