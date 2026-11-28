import SwiftUI
import UIKit

@main
struct WeeklyWinsApp: App {
    @UIApplicationDelegateAdaptor(RecorderBluetoothAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            StudioRootView()
                #if DEBUG
                .onAppear { DeviceTestSession.startIfRequested() }
                #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { RecorderBluetooth.shared.activate() }
        }
    }
}

@MainActor
final class RecorderBluetoothAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        RecorderBluetooth.shared.activate()
        return true
    }
}
