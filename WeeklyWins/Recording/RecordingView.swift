import SwiftUI

struct RecordingView: View {
    @ObservedObject private var recorder = RecordingService.shared
    @State private var selectedRecording: Recording?

    var body: some View {
        VStack(spacing: 18) {
            Text("Записи").font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading)
            Text(versionLabel).font(.caption).foregroundStyle(StudioTheme.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Записи").font(.headline)
                    Spacer()
                    Text("\(recorder.recordings.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if recorder.recordings.isEmpty {
                    ContentUnavailableView("Пока нет записей", systemImage: "waveform")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(recorder.recordings) { recording in
                                Button {
                                    selectedRecording = recording
                                } label: {
                                    RecordingRow(recording: recording)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("recording-row")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .background(StudioTheme.background)
        .foregroundStyle(StudioTheme.text)
        .onAppear { recorder.refreshRecordings() }
        .sheet(item: $selectedRecording) { recording in
            TranscriptView(recording: recording, recordingService: recorder)
        }
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Версия \(version) (сборка \(build))"
    }
}

private struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(recording.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.body)
                Text(durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if recording.state != .saved {
                    Text(recording.state.displayName)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let errorMessage = recording.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var durationText: String {
        guard let duration = recording.duration else { return "Длительность не определена" }
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
