import SwiftUI

struct StudioRootView: View {
    @ObservedObject private var service = RecordingService.shared
    @State private var recorderPresentation: RecorderPresentation?
    @State private var selectedTab = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    private enum RecorderPresentation: String, Identifiable {
        case prepare, active
        var id: Self { self }
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding || !service.recordings.isEmpty || service.isRecording || service.isStarting {
                mainInterface.onAppear { hasCompletedOnboarding = true }
            } else {
                OnboardingView { startRecording in
                    hasCompletedOnboarding = true
                    if startRecording { openRecorder() }
                }
            }
        }
        .task { service.resumeAutomaticTranscription() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { service.refreshRecordings(); service.resumeAutomaticTranscription() }
        }
    }

    private var mainInterface: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                ReportView(isToday: true).tag(0).toolbar(.hidden, for: .tabBar)
                RecordingView().tag(1).toolbar(.hidden, for: .tabBar)
                ReportView(isToday: false).tag(2).toolbar(.hidden, for: .tabBar)
            }
            VStack(spacing: 0) {
                bottomBar
                Divider().overlay(StudioTheme.surface)
                HStack {
                    tab("Сегодня", icon: "calendar", index: 0)
                    tab("Записи", icon: "waveform", index: 1)
                    tab("Отчёты", icon: "chart.bar.fill", index: 2)
                }.padding(.top, 12).padding(.bottom, 5)
            }.background(StudioTheme.background)
        }
        .background(StudioTheme.background.ignoresSafeArea())
        .tint(StudioTheme.mint)
        .preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .fullScreenCover(item: $recorderPresentation) { presentation in
            StudioRecorderView(service: service, preparesOnAppear: presentation == .prepare)
        }
    }

    private func openRecorder() {
        recorderPresentation = service.isRecording ? .active : .prepare
    }

    private func tab(_ title: String, icon: String, index: Int) -> some View {
        Button { selectedTab = index } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 23))
                Text(title).font(.caption.weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }.frame(maxWidth: .infinity).frame(minHeight: 48)
                .foregroundStyle(selectedTab == index ? StudioTheme.mint : StudioTheme.secondary)
        }
        .accessibilityIdentifier("studio-tab-\(index)")
        .accessibilityAddTraits(selectedTab == index ? .isSelected : [])
    }

    private var bottomBar: some View {
        recordingBar.padding(.horizontal, 20).padding(.vertical, 12).background(StudioTheme.background)
    }

    private var recordingBar: some View {
        HStack(spacing: 14) {
            Button(action: openRecorder) {
                HStack {
                    Image(systemName: service.isRecording ? "waveform" : "mic.fill").font(.title2)
                    Text(service.isRecording ? "Идёт запись" : service.isStarting ? "Запускается…" : "Записать")
                        .font(.title3.weight(.semibold))
                    if service.isRecording, let start = service.recordingStartedAt {
                        Spacer()
                        Text(start, style: .timer).monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity).frame(minHeight: 60)
            }
            .disabled(service.isStarting)
            if service.isRecording {
                Button { service.stop() } label: {
                    Image(systemName: "stop.fill").font(.title2).frame(width: 50, height: 54)
                }.accessibilityLabel("Остановить")
            }
        }
        .foregroundStyle(service.isRecording ? StudioTheme.coral : StudioTheme.background)
        .padding(.horizontal, 16)
        .background(service.isRecording ? StudioTheme.surface : StudioTheme.mint, in: RoundedRectangle(cornerRadius: 26))
        .buttonStyle(.plain)
    }
}

struct StudioRecorderView: View {
    @ObservedObject var service: RecordingService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isPreparing: Bool
    @State private var startupError: Error?
    private let preparesOnAppear: Bool

    init(service: RecordingService, preparesOnAppear: Bool = false) {
        self.service = service
        self.preparesOnAppear = preparesOnAppear
        _isPreparing = State(initialValue: preparesOnAppear)
    }

    var body: some View {
        Group {
            if !service.isRecording && (isPreparing || startupError != nil) {
                preparation
            } else {
                recorder
            }
        }
        .background(StudioTheme.background.ignoresSafeArea())
        .foregroundStyle(StudioTheme.text)
        .task {
            if preparesOnAppear { await prepareRecording() }
            else { dismissAfterSuccessfulSave() }
        }
        .onChange(of: service.completedRecordingID) { _, _ in dismissAfterSuccessfulSave() }
    }

    private var preparation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Запись").font(.largeTitle.bold())
                if let startupError {
                    let denied = (startupError as? RecordingError) == .permissionDenied
                    Label(denied ? "Нет доступа к микрофону" : "Не удалось начать запись",
                          systemImage: "exclamationmark.circle")
                        .font(.headline).foregroundStyle(StudioTheme.coral)
                    if denied {
                        Button("Открыть настройки") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }.frame(minHeight: 44)
                    }
                    Button {
                        Task { await prepareRecording() }
                    } label: {
                        Text("Повторить").font(.headline)
                            .foregroundStyle(StudioTheme.background)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(StudioTheme.mint, in: Capsule())
                    }.buttonStyle(.plain)
                    Button("Закрыть") { dismiss() }.frame(minHeight: 44)
                } else {
                    ProgressView("Подготавливаем микрофон…")
                        .foregroundStyle(StudioTheme.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .tint(StudioTheme.mint)
    }

    private var recorder: some View {
        VStack(spacing: 24) {
            HStack {
                Button { dismiss() } label: { Label("Свернуть", systemImage: "chevron.down") }
                Spacer()
            }.frame(minHeight: 44)
            Spacer()
            HStack(spacing: 10) {
                Circle().fill(StudioTheme.coral).frame(width: 12, height: 12)
                Text(service.isRecording ? "Идёт запись" : service.status)
                    .font(.headline)
                    .foregroundStyle(service.isRecording ? StudioTheme.text : StudioTheme.coral)
                    .accessibilityIdentifier("recorder-status")
            }
            TimelineView(.periodic(from: service.recordingStartedAt ?? .distantPast, by: 1)) { context in
                let elapsed = max(0, Int(context.date.timeIntervalSince(service.recordingStartedAt ?? context.date)))
                Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                    .font(.system(size: 72, weight: .light)).monospacedDigit()
                    .accessibilityIdentifier("recorder-timer")
            }
            StudioWaveform(service: service).frame(height: 140)
            Spacer()
            Button {
                service.stop()
            } label: {
                VStack(spacing: 14) {
                    Image(systemName: "stop.fill").font(.system(size: 32))
                        .foregroundStyle(StudioTheme.coral)
                        .frame(width: 100, height: 100)
                        .overlay(Circle().stroke(StudioTheme.coral, lineWidth: 3))
                    Text("Остановить").font(.title3.weight(.semibold)).foregroundStyle(StudioTheme.text)
                }
            }.disabled(!service.isRecording)
            .accessibilityIdentifier("recorder-stop")
            Text("До 5 минут").font(.footnote).foregroundStyle(StudioTheme.secondary)
        }
        .padding(28).padding(.bottom, 35)
    }

    private func prepareRecording() async {
        isPreparing = true
        startupError = nil
        defer {
            isPreparing = false
            dismissAfterSuccessfulSave()
        }
        do {
            // An Action Button intent can be waiting for microphone permission.
            while service.isStarting { try await Task.sleep(for: .milliseconds(50)) }
            try Task.checkCancellation()
            if !service.isRecording { try await service.start() }
        } catch is CancellationError {
            return
        } catch {
            startupError = error
        }
    }

    private func dismissAfterSuccessfulSave() {
        guard !isPreparing, startupError == nil, service.completedRecordingID != nil,
              !service.isRecording, !service.isStarting else { return }
        dismiss()
    }
}

private struct StudioWaveform: View {
    let service: RecordingService
    @State private var levels = Array(repeating: Float(0), count: 48)
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule().fill(StudioTheme.coral)
                        .frame(height: max(4, CGFloat(levels[index]) * geometry.size.height))
                }
            }.frame(maxHeight: .infinity)
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(80)) }
                catch { return }
                levels.removeFirst()
                levels.append(service.audioLevel())
            }
        }
        .accessibilityLabel("Уровень микрофона")
        .accessibilityHidden(true)
    }
}
