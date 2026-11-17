import SwiftUI
import AVFoundation
import Speech

struct SettingsButton: View {
    @State private var isPresented = false
    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "gearshape").font(.title3)
                .foregroundStyle(StudioTheme.secondary).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Настройки")
        .accessibilityIdentifier("settings-button")
        .sheet(isPresented: $isPresented) { SettingsView() }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var microphone = "Проверяется"
    @State private var speech = "Проверяется"
    @State private var offline = "Проверяется"

    var body: some View {
        NavigationStack {
            List {
                Section("Доступы") {
                    LabeledContent("Микрофон", value: microphone)
                    LabeledContent("Распознавание речи", value: speech)
                    Button("Открыть настройки iPhone") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Section("Русская расшифровка") {
                    LabeledContent("На устройстве", value: offline)
                    Text("Аудиозаписи обрабатываются на устройстве. Доступность модели зависит от языка и версии iOS.")
                        .font(.footnote).foregroundStyle(StudioTheme.secondary)
                }
                Section {
                    NavigationLink("Настроить кнопку действия") { ActionButtonGuideView() }
                }
                Section("Приложение") {
                    LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    LabeledContent("Сборка", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
                }
            }
            .scrollContentBackground(.hidden).background(StudioTheme.background)
            .navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .task { await refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
        }.tint(StudioTheme.mint).preferredColorScheme(.dark)
    }

    @MainActor
    private func refresh() async {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: microphone = "Разрешён"
        case .denied: microphone = "Отклонён"
        default: microphone = "Не запрошен"
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speech = "Разрешено"
        case .denied, .restricted: speech = "Недоступно"
        default: speech = "Не запрошено"
        }
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ru-RU")) {
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            switch await AssetInventory.status(forModules: [transcriber]) {
            case .installed: offline = "Готова"
            case .supported, .downloading: offline = "Требуется модель"
            case .unsupported: offline = legacyAvailability
            @unknown default: offline = "Не определено"
            }
        } else { offline = legacyAvailability }
    }

    private var legacyAvailability: String {
        SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))?.supportsOnDeviceRecognition == true ? "Готова" : "Недоступна"
    }
}

struct ActionButtonGuideView: View {
    var body: some View {
        List {
            Section("Первоначальная настройка") {
                Text("Разрешите доступ к микрофону и сделайте пробную запись в приложении.")
                Text("Откройте «Настройки» iPhone → «Кнопка действия».")
                Text("Выберите «Быстрая команда» → «Выбрать команду» → WeeklyWins → «Запись».")
            }
            Section("Проверка") {
                Text("Сверните WeeklyWins и заблокируйте экран. Удержите кнопку действия до начала записи.")
                Text("На экране блокировки появятся индикатор и таймер. Повторное удержание остановит и сохранит запись.")
                Text("Откройте «Записи» и прослушайте результат. Через пять минут запись завершается автоматически.")
            }
        }
        .scrollContentBackground(.hidden).background(StudioTheme.background)
        .navigationTitle("Кнопка действия").navigationBarTitleDisplayMode(.inline)
    }
}
