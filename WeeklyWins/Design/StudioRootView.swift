import SwiftUI

struct StudioRootView: View {
    @ObservedObject private var service = RecordingService.shared
    @State private var showRecorder = false
    @State private var error: String?
    @State private var selectedTab = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding || !service.recordings.isEmpty || service.isRecording || service.isStarting {
                mainInterface.onAppear { hasCompletedOnboarding = true }
            } else {
                OnboardingView { startRecording in
                    hasCompletedOnboarding = true
                    if startRecording {
                        showRecorder = true
                        Task {
                            do { try await service.start() }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
        }
    }

    private var mainInterface: some View {
        ZStack {
            ReportView(isToday: true).opacity(selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(selectedTab == 0).accessibilityHidden(selectedTab != 0)
            RecordingView().opacity(selectedTab == 1 ? 1 : 0)
                .allowsHitTesting(selectedTab == 1).accessibilityHidden(selectedTab != 1)
            ReportView(isToday: false).opacity(selectedTab == 2 ? 1 : 0)
                .allowsHitTesting(selectedTab == 2).accessibilityHidden(selectedTab != 2)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
                showRecorder = true
                if !service.isRecording {
                    Task { do { try await service.start() } catch { self.error = error.localizedDescription } }
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
            Label(service.status, systemImage: "circle.fill")
                .font(.headline).foregroundStyle(StudioTheme.coral)
            if let start = service.recordingStartedAt {
                Text(start, style: .timer).font(.system(size: 72, weight: .light, design: .monospaced))
            } else {
                Text("00:00").font(.system(size: 72, weight: .light, design: .monospaced))
            }
            StudioWaveform(service: service).frame(height: 140)
            Spacer()
            Button {
                service.stop()
                dismiss()
            } label: {
                VStack(spacing: 14) {
                    Image(systemName: "stop.fill").font(.system(size: 32))
                        .frame(width: 94, height: 94)
                        .overlay(Circle().stroke(StudioTheme.coral, lineWidth: 3))
                    Text("Остановить").font(.title3.weight(.semibold))
                }.foregroundStyle(StudioTheme.coral)
            }.disabled(!service.isRecording)
            .accessibilityIdentifier("recorder-stop")
            Text("До 5 минут").font(.footnote).foregroundStyle(StudioTheme.secondary)
        }
        .padding(28).padding(.bottom, 35)
        .background(StudioTheme.background).foregroundStyle(StudioTheme.text)
    }
}

private struct StudioWaveform: View {
    @ObservedObject var service: RecordingService
    @State private var levels = Array(repeating: Float(0), count: 36)
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { context in
            GeometryReader { geometry in
                HStack(spacing: 4) {
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
