import SwiftUI
import AVFoundation
import Speech
import UniformTypeIdentifiers

struct SettingsButton: View {
    @State private var isPresented = false
    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "gearshape").font(.title3)
                .foregroundStyle(StudioTheme.secondary).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
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
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var showImportMessage = false

    var body: some View {
        NavigationStack {
            List {
                Section("Доступы") {
                    LabeledContent("Микрофон", value: microphone)
                    LabeledContent("Распознавание речи", value: speech)
                    Button("Открыть настройки iPhone") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }.listRowBackground(StudioTheme.surface)
                Section("Офлайн-распознавание") {
                    LabeledContent("На устройстве", value: offline)
                    Text("Аудиозаписи обрабатываются на устройстве. Доступность модели зависит от языка и версии iOS.")
                        .font(.footnote).foregroundStyle(StudioTheme.secondary)
                }.listRowBackground(StudioTheme.surface)
                Section {
                    NavigationLink("Настроить кнопку действия") { ActionButtonGuideView() }
                }.listRowBackground(StudioTheme.surface)
                Section("Отчёты") {
                    NavigationLink("Инструкция для внешней модели") { ReportPromptEditorView() }
                        .accessibilityIdentifier("settings-report-prompt")
                    Text("Помогает собрать рабочие записи по дням и задачам для недельного отчёта.")
                        .font(.footnote)
                        .foregroundStyle(StudioTheme.secondary)
                }.listRowBackground(StudioTheme.surface)
                Section("Данные") {
                    NavigationLink("Диктофон ESP32") { RecorderSyncView() }
                        .accessibilityIdentifier("settings-esp32-recorder")
                    NavigationLink("Хранилище аудиозаписей") { AudioStorageView() }
                        .accessibilityIdentifier("settings-audio-storage")
                    Button("Выгрузить расшифровки (JSON)") { exportTranscripts() }
                        .accessibilityIdentifier("settings-export-transcripts")
                    Button("Импортировать расшифровки (JSON)") { showImporter = true }
                        .accessibilityIdentifier("settings-import-transcripts")
                }.listRowBackground(StudioTheme.surface)
                Section("Версия и сборка") {
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
                    LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    LabeledContent("Сборка", value: build)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Сборка")
                        .accessibilityValue(build)
                        .accessibilityIdentifier("settings-build")
                }.listRowBackground(StudioTheme.surface)
            }
            .scrollContentBackground(.hidden).background(StudioTheme.background)
            .navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .task { await refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                importFile(result)
            }
            .alert("Импорт расшифровок", isPresented: $showImportMessage, presenting: importMessage) { _ in
                Button("Готово", role: .cancel) {}
            } message: { message in Text(message) }
        }.tint(StudioTheme.mint).preferredColorScheme(.dark)
    }

    private func exportTranscripts() {
        do {
            let export = TranscriptExport.make(recordings: RecordingService.shared.recordings)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(export.fileName)
            try export.fileData().write(to: url, options: .atomic)
            SharePresenter.present(url: url)
        } catch {
            importMessage = "Не удалось подготовить файл: \(error.localizedDescription)"
            showImportMessage = true
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let export = try decoder.decode(TranscriptExport.self, from: data)
            let summary = try RecordingService.shared.importTranscriptEntries(export.recordings)
            importMessage = "Импортировано записей: \(summary.imported). Пропущено дублей: \(summary.skippedDuplicates)."
        } catch {
            importMessage = "Не удалось прочитать файл."
        }
        showImportMessage = true
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
            case .supported: offline = "Требуется модель"
            case .downloading: offline = "Загружается"
            case .unsupported: offline = legacyAvailability
            @unknown default: offline = "Не определено"
            }
        } else { offline = legacyAvailability }
    }

    private var legacyAvailability: String {
        SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))?.supportsOnDeviceRecognition == true ? "Готова" : "Недоступна"
    }
}

struct AudioStorageView: View {
    @ObservedObject private var service = RecordingService.shared
    @AppStorage(AudioRetentionPreferences.enabledKey) private var autoDeleteEnabled = false
    @AppStorage(AudioRetentionPreferences.daysKey) private var retentionDays = AudioRetentionPreferences.defaultDays
    @State private var errorMessage: String?

    private var items: [AudioStorageItem] { service.audioStorageItems }
    private var totalBytes: Int64 { items.reduce(Int64.zero) { $0 + $1.byteCount } }

    var body: some View {
        List {
            Section("Использование") {
                LabeledContent("Занято аудиозаписями", value: formattedSize(totalBytes))
                LabeledContent("Аудиофайлов", value: "\(items.count)")
            }
            .listRowBackground(StudioTheme.surface)

            Section("Автоматическое удаление") {
                Toggle("Удалять старое аудио", isOn: $autoDeleteEnabled)
                    .accessibilityIdentifier("audio-retention-toggle")
                if autoDeleteEnabled {
                    Stepper(value: $retentionDays, in: AudioRetentionPreferences.dayRange) {
                        LabeledContent("Срок хранения", value: retentionPeriodTitle)
                    }
                    .accessibilityIdentifier("audio-retention-days")
                }
                Text("Удаляются только аудиофайлы. Расшифровки и дела сохраняются.")
                    .font(.footnote)
                    .foregroundStyle(StudioTheme.secondary)
            }
            .listRowBackground(StudioTheme.surface)

        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(StudioTheme.background)
        .foregroundStyle(StudioTheme.text)
        .tint(StudioTheme.mint)
        .navigationTitle("Хранилище аудио")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !AudioRetentionPreferences.dayRange.contains(retentionDays) {
                retentionDays = AudioRetentionPreferences.defaultDays
            }
            service.refreshRecordings()
            applyRetention()
        }
        .onChange(of: autoDeleteEnabled) { _, _ in applyRetention() }
        .onChange(of: retentionDays) { _, _ in
            if autoDeleteEnabled { applyRetention() }
        }
        .alert("Не удалось удалить аудио", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Закрыть", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var retentionPeriodTitle: String {
        let lastTwoDigits = retentionDays % 100
        let lastDigit = retentionDays % 10
        let unit: String
        if (11...14).contains(lastTwoDigits) { unit = "дней" }
        else if lastDigit == 1 { unit = "день" }
        else if (2...4).contains(lastDigit) { unit = "дня" }
        else { unit = "дней" }
        return "\(retentionDays) \(unit)"
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func applyRetention() {
        do { _ = try service.applyAudioRetention(enabled: autoDeleteEnabled, days: retentionDays) }
        catch { errorMessage = error.localizedDescription }
    }

}

struct ReportPromptEditorView: View {
    @AppStorage(ReportPromptPreferences.key) private var instruction = ReportPromptPreferences.defaultPrompt
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Промпт добавляется перед исходным отчётом в тексте для отправки.")
                .font(.subheadline)
                .foregroundStyle(StudioTheme.secondary)
            TextEditor(text: $instruction)
                .focused($editorFocused)
                .font(.body)
                .foregroundStyle(StudioTheme.text)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: StudioTheme.cornerRadius))
                .clipShape(RoundedRectangle(cornerRadius: StudioTheme.cornerRadius))
                .accessibilityIdentifier("report-model-prompt-editor")
        }
        .padding(20)
        .background(StudioTheme.background)
        .navigationTitle("Промпт отчёта")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("По умолчанию") { instruction = ReportPromptPreferences.defaultPrompt }
                    .accessibilityIdentifier("report-prompt-reset")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { editorFocused = false }
            }
        }
    }
}

struct ActionButtonGuideView: View {
    var offersTrial = true
    @ObservedObject private var service = RecordingService.shared
    @State private var showTrial = false

    var body: some View {
        List {
            Section("Первоначальная настройка") {
                if offersTrial {
                    Button(service.isRecording ? "Открыть запись" : "Сделать пробную запись") { showTrial = true }
                        .disabled(service.isStarting)
                }
                Text("Откройте «Настройки» iPhone → «Кнопка действия».")
                Text("Выберите «Быстрая команда» → «Выбрать команду» → WeeklyWins → «Запись».")
            }.listRowBackground(StudioTheme.surface)
            Section("Проверка") {
                Text("Сверните WeeklyWins и заблокируйте экран. Удержите кнопку действия до начала записи.")
                Text("На экране блокировки появятся индикатор и таймер. Повторное удержание остановит и сохранит запись.")
                Text("Откройте «Записи» и прослушайте результат. Через пять минут запись завершается автоматически.")
            }.listRowBackground(StudioTheme.surface)
        }
        .scrollContentBackground(.hidden).background(StudioTheme.background)
        .fullScreenCover(isPresented: $showTrial) {
            StudioRecorderView(service: service, preparesOnAppear: !service.isRecording)
        }
        .navigationTitle("Кнопка действия").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct RecorderSyncView: View {
    @ObservedObject private var recorder = RecorderBluetooth.shared

    var body: some View {
        List {
            Section {
                Label(
                    recorder.isConnected ? "Диктофон подключён" : "Диктофон не подключён",
                    systemImage: recorder.isConnected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(recorder.isConnected ? StudioTheme.mint : StudioTheme.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("esp32-device-connection-state")

                if recorder.pairedID == nil {
                    Text("Удерживайте кнопку диктофона 5 секунд до синего индикатора. Затем нажмите «Подключить диктофон» и подтвердите запрос на iPhone. Serial-порт и PIN не нужны.")
                        .font(.subheadline)
                        .foregroundStyle(StudioTheme.secondary)
                    Button("Подключить диктофон") { recorder.pair() }
                        .accessibilityIdentifier("pair-esp32-recorder")
                } else {
                    Text("WeeklyWins сам импортирует новые записи, когда диктофон рядом.")
                        .font(.subheadline)
                        .foregroundStyle(StudioTheme.secondary)
                }
                Text(recorder.status)
                    .accessibilityIdentifier("esp32-recorder-status")
                if recorder.pairedID != nil {
                    Button("Забыть диктофон", role: .destructive) { recorder.forget() }
                }
            }.listRowBackground(StudioTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(StudioTheme.background)
        .navigationTitle("Диктофон ESP32")
        .navigationBarTitleDisplayMode(.inline)
    }
}
