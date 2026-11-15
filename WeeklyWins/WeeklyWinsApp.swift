import SwiftUI

@main
struct WeeklyWinsApp: App {
    init() {
        WeeklyWinsShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RecordingView()
        }
    }
}
