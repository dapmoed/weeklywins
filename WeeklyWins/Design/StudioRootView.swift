import SwiftUI

struct StudioRootView: View {
    @ObservedObject private var service = RecordingService.shared
    @State private var recorderPresentation: RecorderPresentation?
    @State private var showsSavedAudio = false
    @State private var savedAudioToOpen: Recording?
    @State private var dayDeletions: [RecordingService.DeletedEvent] = []
    @State private var dayDeletionError: String?
    @State private var selectedTab = 0
    @FocusState private var isRecordingSearchFocused: Bool
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
                ReportView(isToday: true, onStartRecording: openRecorder, onDeleteEvent: deleteDayEvent)
                    .tag(0).toolbar(.hidden, for: .tabBar)
                RecordingView(searchFocused: $isRecordingSearchFocused).tag(1).toolbar(.hidden, for: .tabBar)
                ReportView(isToday: false).tag(2).toolbar(.hidden, for: .tabBar)
            }
            VStack(spacing: 0) {
                if selectedTab == 0 && !dayDeletions.isEmpty { dayDeletionUndo }
                if showsSavedAudio, let recording = service.recordings.first(where: { $0.id == service.completedRecordingID }) {
                    savedAudioConfirmation(for: recording)
                }
                if service.isRecording || (selectedTab != 0 && !isRecordingSearchFocused) { bottomBar }
                if !isRecordingSearchFocused {
                    Divider().overlay(StudioTheme.surface)
                    HStack {
                        tab("Сегодня", icon: "calendar", index: 0)
                        tab("Записи", icon: "waveform", index: 1)
                        tab("Отчёты", icon: "chart.bar.fill", index: 2)
                    }.padding(.top, 12).padding(.bottom, 5)
                }
            }.background(StudioTheme.background)
        }
        .background(StudioTheme.background.ignoresSafeArea())
        .tint(StudioTheme.mint)
        .preferredColorScheme(.dark)
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .fullScreenCover(item: $recorderPresentation) { presentation in
            StudioRecorderView(service: service, preparesOnAppear: presentation == .prepare)
        }
        .sheet(item: $savedAudioToOpen) { recording in
            TranscriptView(recording: recording, recordingService: service)
        }
        .alert("Не удалось изменить ленту", isPresented: Binding(
            get: { dayDeletionError != nil }, set: { if !$0 { dayDeletionError = nil } }
        )) {
            Button("Закрыть", role: .cancel) {}
        } message: {
            Text(dayDeletionError ?? "")
        }
        .task(id: service.completedRecordingID) {
            showsSavedAudio = service.completedRecordingID != nil && scenePhase == .active
            guard showsSavedAudio else { return }
            do { try await Task.sleep(for: .seconds(6)) }
            catch { return }
            showsSavedAudio = false
        }
    }

    private var dayDeletionUndo: some View {
        HStack(spacing: 4) {
            Button {
                guard let deletion = dayDeletions.last else { return }
                do {
                    try service.restoreEvent(deletion)
                    dayDeletions.removeLast()
                } catch {
                    dayDeletionError = error.localizedDescription
                }
            } label: {
                Label("Отменить удаление", systemImage: "arrow.uturn.backward")
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("day-undo-deletion")
            Button {
                dayDeletions.removeAll()
            } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Закрыть отмену удаления")
        }
        .buttonStyle(.plain)
        .foregroundStyle(StudioTheme.mint)
        .padding(.leading, 12)
        .padding(.vertical, 4)
        .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .background(StudioTheme.background)
    }

    private func deleteDayEvent(_ event: DiaryEvent) {
        do { dayDeletions.append(try service.deleteEvent(event)) }
        catch { dayDeletionError = error.localizedDescription }
    }

    private func savedAudioConfirmation(for recording: Recording) -> some View {
        Button {
            savedAudioToOpen = recording
            showsSavedAudio = false
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Label("Аудио сохранено", systemImage: "checkmark.circle")
                    Text("Открыть").fontWeight(.bold)
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Аудио сохранено", systemImage: "checkmark.circle")
                    Text("Открыть").fontWeight(.bold)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(StudioTheme.mint)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .accessibilityLabel("Аудио сохранено, открыть запись")
        .accessibilityIdentifier("open-saved-audio")
    }

    private func openRecorder() {
        recorderPresentation = service.isRecording ? .active : .prepare
    }

    private func tab(_ title: String, icon: String, index: Int) -> some View {
        Button { selectedTab = index } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 23))
                Text(title).font(.caption.weight(.medium))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }.frame(maxWidth: .infinity).frame(minHeight: 48)
                .foregroundStyle(selectedTab == index ? StudioTheme.mint : StudioTheme.secondary)
        }
        .accessibilityIdentifier("studio-tab-\(index)")
        .accessibilityAddTraits(selectedTab == index ? .isSelected : [])
    }

    private var bottomBar: some View {
        recordingBar.padding(.horizontal, 20).padding(.vertical, 12).background(StudioTheme.background)
    }

    @ViewBuilder
    private var recordingBar: some View {
        if service.isRecording {
            HStack(alignment: .bottom, spacing: 10) {
                Button(action: openRecorder) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle().fill(StudioTheme.coral).frame(width: 7, height: 7)
                                .accessibilityHidden(true)
                            Text("Идёт запись").font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            if let start = service.recordingStartedAt {
                                StudioElapsedTime(start: start)
                                    .font(.subheadline)
                                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            }
                        }
                        StudioWaveform(service: service).frame(height: 24)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                Button { service.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().strokeBorder(StudioTheme.coral, lineWidth: 2))
                }
                .accessibilityLabel("Остановить")
                .accessibilityIdentifier("compact-recording-stop")
            }
            .buttonStyle(.plain)
            .foregroundStyle(StudioTheme.coral)
            .padding(12)
            .background(StudioTheme.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).strokeBorder(StudioTheme.coral.opacity(0.25))
                    .allowsHitTesting(false)
            }
        } else {
            Button(action: openRecorder) {
                Label(service.isStarting ? "Запускается…" : "Записать", systemImage: "mic.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .foregroundStyle(StudioTheme.background)
                    .background(StudioTheme.mint, in: RoundedRectangle(cornerRadius: 26))
            }
            .buttonStyle(.plain)
            .disabled(service.isStarting)
        }
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
            StudioElapsedTime(start: service.recordingStartedAt)
                .font(.system(size: 72, weight: .light))
                .accessibilityIdentifier("recorder-timer")
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

private struct StudioElapsedTime: View {
    let start: Date?

    var body: some View {
        TimelineView(.periodic(from: start ?? .distantPast, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(start ?? context.date)))
            Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                .monospacedDigit()
        }
    }
}

private struct StudioWaveform: View {
    let service: RecordingService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .task(id: reduceMotion) {
            if reduceMotion {
                levels = Array(repeating: 0, count: levels.count)
                return
            }
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
