import XCTest

final class ActionButtonUITests: XCTestCase {
    @MainActor
    func testRecordingShortcutStartsRecording() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("App Shortcuts do not execute reliably in iOS 26/27 Simulator; verify dispatch on iPhone.")
        #else
        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        shortcuts.launch()

        let appShortcut = shortcuts.staticTexts["WeeklyWins"]
        XCTAssertTrue(appShortcut.waitForExistence(timeout: 10), shortcuts.debugDescription)
        appShortcut.tap()

        let recordingShortcut = shortcuts.buttons["Микрофон"]
        XCTAssertTrue(recordingShortcut.waitForExistence(timeout: 5), shortcuts.debugDescription)
        recordingShortcut.tap()

        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        XCTAssertTrue(app.staticTexts["Запись идёт"].waitForExistence(timeout: 10), app.debugDescription)
        #endif
    }

    @MainActor
    func testActionButtonStartsAndStopsRecording() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("App Shortcuts do not execute reliably in iOS 26/27 Simulator; verify dispatch on iPhone.")
        #else
        let device = XCUIDevice.shared
        try XCTSkipUnless(device.hasHardwareButton(.action), "Simulator has no Action Button")

        let app = XCUIApplication()
        app.launch()

        device.press(.action)
        XCTAssertTrue(app.staticTexts["Запись идёт"].waitForExistence(timeout: 5))

        device.press(.action)
        XCTAssertTrue(app.staticTexts["Запись сохранена"].waitForExistence(timeout: 5))
        #endif
    }
}
