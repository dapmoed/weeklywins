import SwiftUI

@main
struct WeeklyWinsApp: App {
    var body: some Scene {
        WindowGroup {
            StudioRootView()
                #if DEBUG
                .onAppear { DeviceTestSession.startIfRequested() }
                #endif
        }
    }
}
