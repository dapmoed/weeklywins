import SwiftUI

struct RecordingView: View {
    @ObservedObject private var recorder = RecordingService.shared

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: recorder.isRecording ? "waveform" : "mic")
                .font(.system(size: 54))
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
        .padding()
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Версия \(version) (сборка \(build))"
    }
}
