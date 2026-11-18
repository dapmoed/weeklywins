import SwiftUI
import AVFoundation

struct OnboardingView: View {
    let onFinish: (Bool) -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsMicrophone = false
    @State private var microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
    @State private var requestingPermission = false
    @State private var permissionDenied = AVAudioApplication.shared.recordPermission == .denied

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "waveform").font(.system(size: 42)).foregroundStyle(StudioTheme.mint)
                        .padding(.top, 24)
                    Text(showsMicrophone ? "Начните с голоса" : "Вспомнить свой день")
                        .font(.largeTitle.bold())
                    if showsMicrophone {
                        Text("Запись длится до пяти минут. Начните её в приложении или настроенной кнопкой действия.")
                            .foregroundStyle(StudioTheme.secondary)
                        Label(microphoneGranted ? "Микрофон разрешён" : permissionDenied ? "Доступ к микрофону отклонён" : "Разрешите доступ к микрофону", systemImage: microphoneGranted ? "checkmark.circle" : "mic")
                            .foregroundStyle(microphoneGranted ? StudioTheme.mint : StudioTheme.text)
                        if permissionDenied {
                            Button("Открыть настройки iPhone") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }.buttonStyle(.bordered)
                        } else if !microphoneGranted {
                            Button(requestingPermission ? "Запрашивается доступ…" : "Проверить микрофон") {
                                Task { await requestMicrophone() }
                            }.buttonStyle(.borderedProminent).disabled(requestingPermission)
                        }
                        if microphoneGranted {
                            NavigationLink("Настроить кнопку действия") { ActionButtonGuideView(offersTrial: false) }
                                .frame(minHeight: 44)
                        }
                        Text("После остановки аудио сохраняется. Расшифровка превращает рассказ в события, которые можно исправить и распределить по работе и дому.")
                            .foregroundStyle(StudioTheme.secondary)
                    } else {
                        Text("Расскажите, чем занимались. Сохраните и крупные дела, и небольшие повседневные события.")
                            .foregroundStyle(StudioTheme.secondary)
                        VStack(alignment: .leading, spacing: 20) {
                            Label("«Подготовил отчёт и купил продукты»", systemImage: "mic")
                            Divider()
                            Label("Подготовил отчёт", systemImage: "briefcase")
                                .foregroundStyle(StudioTheme.mint)
                            Label("Купил продукты", systemImage: "house")
                                .foregroundStyle(StudioTheme.sand)
                        }.padding(20).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                        Text("Ваши дела появятся в ленте дня и отчётах. Время и длительность можно уточнить позже.")
                            .foregroundStyle(StudioTheme.secondary)
                    }
                }.padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button(showsMicrophone ? microphoneGranted ? "Сделать пробную запись" : "Продолжить без записи" : "Начать") {
                        if !showsMicrophone { showsMicrophone = true }
                        else { onFinish(microphoneGranted) }
                    }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(StudioTheme.background).background(StudioTheme.mint, in: Capsule())
                    .disabled(requestingPermission)
                    if showsMicrophone && microphoneGranted {
                        Button("Перейти в дневник") { onFinish(false) }.frame(minHeight: 44)
                    }
                }.padding(24).background(StudioTheme.background)
            }
            .background(StudioTheme.background).foregroundStyle(StudioTheme.text)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshPermission() }
            }
        }
        .preferredColorScheme(.dark).tint(StudioTheme.mint)
        .environment(\.locale, Locale(identifier: "ru_RU"))
    }

    @MainActor
    private func requestMicrophone() async {
        requestingPermission = true
        defer { requestingPermission = false }
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }
        refreshPermission()
    }

    private func refreshPermission() {
        microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
        permissionDenied = AVAudioApplication.shared.recordPermission == .denied
    }
}
