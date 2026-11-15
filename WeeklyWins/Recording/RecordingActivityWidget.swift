import ActivityKit
import SwiftUI
import WidgetKit

struct RecordingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            Label("Идёт запись", systemImage: "waveform")
                .padding()
        } dynamicIsland: { _ in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { Label("Идёт запись", systemImage: "waveform") }
            } compactLeading: {
                Image(systemName: "waveform")
            } compactTrailing: {
                Text("REC")
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
