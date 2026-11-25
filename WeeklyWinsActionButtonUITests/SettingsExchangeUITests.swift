import XCTest

final class SettingsExchangeUITests: XCTestCase {
    @MainActor
    func testRecorderSyncIsReachableInSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()

        app.buttons["settings-button"].tap()
        let recorder = app.buttons["settings-esp32-recorder"]
        for _ in 0..<3 where !recorder.isHittable { app.swipeUp() }
        XCTAssertTrue(recorder.isHittable)
        recorder.tap()
        XCTAssertTrue(app.navigationBars["Диктофон ESP32"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pair-esp32-recorder"].isHittable)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "A18-recorder-sync"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testExportOpensShareSheetWithVisibleActions() throws {
        let app = XCUIApplication()
        app.launch()
        continueAfterFailure = false

        app.buttons["settings-button"].tap()
        app.buttons["settings-export-transcripts"].tap()

        let firstActivity = app.collectionViews.cells.firstMatch
        XCTAssertTrue(firstActivity.waitForExistence(timeout: 5),
                      "Лист поделиться открылся без доступных действий")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "export-share-sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
