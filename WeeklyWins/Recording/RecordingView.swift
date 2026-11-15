import SwiftUI

struct RecordingView: View {
    @ObservedObject private var recorder = RecordingService.shared

    var body: some View {
        VStack(spacing: 18) {
            Group {
                Image(systemName: recorder.isRecording ? "waveform" : "mic")
                    .font(.system(size: 48))
                    .foregroundStyle(recorder.isRecording ? .red : .accentColor)
                Text(recorder.status).font(.title2)
                Button(recorder.isRecording ? "Остановить" : "Начать запись") {
                    Task {
                        do { try await recorder.toggle() }
                        catch { recorder.showError(error) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text(versionLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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
                                RecordingRow(recording: recording)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding()
        .onAppear { recorder.refreshRecordings() }
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Версия \(version) (сборка \(build))"
    }
}

private struct RecordingRow: View {
    let recording: RecordingSummary

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
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var durationText: String {
        guard let duration = recording.duration else { return "Длительность не определена" }
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
