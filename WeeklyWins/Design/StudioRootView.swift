import SwiftUI

struct StudioRootView: View {
    @ObservedObject private var service = RecordingService.shared
    @State private var showRecorder = false
    @State private var error: String?
    @State private var selectedTab = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if hasCompletedOnboarding || !service.recordings.isEmpty || service.isRecording || service.isStarting {
                mainInterface.onAppear { hasCompletedOnboarding = true }
            } else {
                OnboardingView { startRecording in
                    hasCompletedOnboarding = true
                    if startRecording {
                        Task {
                            do {
                                try await service.start()
                                showRecorder = service.isRecording
                            }
                            catch { self.error = error.localizedDescription }
                        }
                    }
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
        .fullScreenCover(isPresented: $showRecorder) { StudioRecorderView(service: service) }
        .alert("Запись не запущена", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Готово") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func tab(_ title: String, icon: String, index: Int) -> some View {
        Button { selectedTab = index } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 23))
                Text(title).font(.caption.weight(.medium))
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
            Button {
                if service.isRecording {
                    showRecorder = true
                } else {
                    Task {
                        do {
                            try await service.start()
                            showRecorder = service.isRecording
                        } catch { self.error = error.localizedDescription }
                    }
                }
            } label: {
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

    var body: some View {
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
            TimelineView(.periodic(from: .now, by: 1)) { context in
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
        .background(StudioTheme.background).foregroundStyle(StudioTheme.text)
        .onAppear { dismissAfterSuccessfulSave() }
        .onChange(of: service.completedRecordingID) { _, _ in dismissAfterSuccessfulSave() }
    }

    private func dismissAfterSuccessfulSave() {
        guard service.completedRecordingID != nil, !service.isRecording, !service.isStarting else { return }
        dismiss()
    }
}

private struct StudioWaveform: View {
    @ObservedObject var service: RecordingService
    @State private var levels = Array(repeating: Float(0), count: 48)
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { context in
            GeometryReader { geometry in
                HStack(spacing: 3) {
                    ForEach(levels.indices, id: \.self) { index in
                        Capsule().fill(StudioTheme.coral)
                            .frame(height: max(4, CGFloat(levels[index]) * geometry.size.height))
                    }
                }.frame(maxHeight: .infinity)
            }
            .onChange(of: context.date) { _, _ in
                levels.removeFirst()
                levels.append(service.audioLevel())
            }
        }
        .accessibilityLabel("Уровень микрофона")
        .accessibilityHidden(true)
    }
}
