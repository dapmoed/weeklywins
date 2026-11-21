import XCTest

final class SettingsExchangeUITests: XCTestCase {
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
