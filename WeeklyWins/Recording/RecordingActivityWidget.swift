import ActivityKit
import SwiftUI
import WidgetKit

struct RecordingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            Label(context.state.isPreparing == true ? "Запускается…" : "Идёт запись", systemImage: "waveform")
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Label(context.state.isPreparing == true ? "Запускается…" : "Идёт запись", systemImage: "waveform")
                }
            } compactLeading: {
                Image(systemName: "waveform")
            } compactTrailing: {
                Text(context.state.isPreparing == true ? "…" : "REC")
            } minimal: {
                Image(systemName: "waveform")
            }
        }
    }
}

@main
struct WeeklyWinsWidgetBundle: WidgetBundle {
    var body: some Widget { RecordingActivityWidget() }
}
