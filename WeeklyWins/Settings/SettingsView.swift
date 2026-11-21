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
    @State private var showShareSheet = false
    @State private var shareURL: URL?
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
                Section("Данные") {
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
            .sheet(isPresented: $showShareSheet) {
                if let shareURL { ShareSheet(url: shareURL) }
            }
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
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("weeklywins-transcripts.json")
            try export.fileData().write(to: url, options: .atomic)
            shareURL = url
            showShareSheet = true
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
