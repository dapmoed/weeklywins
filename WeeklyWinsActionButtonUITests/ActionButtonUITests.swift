import XCTest

final class ActionButtonUITests: XCTestCase {
    @MainActor
    func testFreshInstallOnboardingStartsTrialRecordingAndDoesNotRepeat() throws {
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        try XCTSkipUnless(app.staticTexts["Вспомнить свой день"].waitForExistence(timeout: 3), "Run this case on a clean Simulator installation.")
        app.buttons["Начать"].tap()
        XCTAssertTrue(app.staticTexts["Начните с голоса"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Сделать пробную запись"].waitForExistence(timeout: 5), "Microphone must be granted by the clean Simulator setup.")
        app.buttons["Сделать пробную запись"].tap()
        XCTAssertTrue(app.staticTexts["Запись идёт"].waitForExistence(timeout: 5))
        app.buttons["recorder-stop"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Записать"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Вспомнить свой день"].exists)
    }

    @MainActor
    func testTranscriptDraftSurvivesAppRelaunchAndCanBeDiscarded() throws {
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        app.buttons["Записать"].tap()
        XCTAssertTrue(app.staticTexts["Запись идёт"].waitForExistence(timeout: 5))
        app.buttons["recorder-stop"].tap()
        app.buttons["studio-tab-1"].tap()
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        let editor = app.textViews["transcriptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        let marker = "Черновик после перезапуска"
        editor.typeText(marker)
        XCTAssertTrue(app.staticTexts["Черновик сохранён"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.buttons["studio-tab-1"].tap()
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, marker)
        app.buttons["Готово"].tap()
        app.buttons["Отбросить изменения"].tap()
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertNotEqual(editor.value as? String, marker)
    }

    @MainActor
    func testRecordingSearchAndConfirmedDeletion() throws {
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        let marker = "Проверка удаления \(UUID().uuidString)"
        app.buttons["Записать"].tap()
        XCTAssertTrue(app.buttons["recorder-stop"].waitForExistence(timeout: 5))
        app.buttons["recorder-stop"].tap()
        app.buttons["studio-tab-1"].tap()
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        let editor = app.textViews["transcriptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(marker)
        app.buttons["Сохранить текст"].tap()
        app.buttons["Готово"].tap()
        let search = app.textFields["recording-search"]
        search.tap()
        search.typeText(marker)
        XCTAssertEqual(app.buttons.matching(identifier: "recording-row").count, 1)
        app.buttons["Действия записи"].firstMatch.tap()
        app.buttons["Удалить запись"].tap()
        app.buttons["Удалить запись"].tap()
        XCTAssertTrue(app.staticTexts["Ничего не найдено"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "recording-row").count, 0)
    }

    @MainActor
    func testSimulatorCanVerifyRecordingFlowInApp() throws {
        #if targetEnvironment(simulator)
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()

        let startRecording = app.buttons["Записать"]
        XCTAssertTrue(startRecording.waitForExistence(timeout: 10), app.debugDescription)
        startRecording.tap()
        XCTAssertTrue(app.staticTexts["Запись идёт"].waitForExistence(timeout: 10), app.debugDescription)

        app.buttons["recorder-stop"].tap()
        app.buttons["studio-tab-1"].tap()

        let recordingRow = app.buttons.matching(identifier: "recording-row").firstMatch
        XCTAssertTrue(recordingRow.waitForExistence(timeout: 5), app.debugDescription)
        recordingRow.tap()
        XCTAssertTrue(app.textViews["transcriptEditor"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Расшифровать"].exists)
        XCTAssertTrue(app.buttons["Сохранить текст"].exists)
        let editor = app.textViews["transcriptEditor"]
        editor.tap()
        editor.typeText("Проверил отчёт.")
        app.buttons["Сохранить текст"].tap()
        app.buttons["Готово"].tap()
        app.buttons["studio-tab-0"].tap()
        let event = app.staticTexts["Проверил отчёт"].firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5), app.debugDescription)
        event.tap()
        XCTAssertTrue(app.buttons["edit-event"].waitForExistence(timeout: 5))
        app.buttons["Открыть аудиозапись и текст"].tap()
        XCTAssertTrue(app.textViews["transcriptEditor"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("This recorder-flow check is for Simulator; Action Button end-to-end is covered by the device test.")
        #endif
    }

    @MainActor
    func testSettingsShowsVersionAndActionButtonGuide() throws {
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        let settings = app.buttons["settings-button"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.staticTexts["Сборка"].waitForExistence(timeout: 5))
        app.buttons["Настроить кнопку действия"].tap()
        XCTAssertTrue(app.staticTexts["Первоначальная настройка"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSimulatorShowsActionButtonAndWeeklyWinsShortcut() throws {
        #if targetEnvironment(simulator)
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()

        let actionButtonRow = settings.staticTexts["Кнопка действия"]
        XCTAssertTrue(actionButtonRow.waitForExistence(timeout: 10), settings.debugDescription)
        XCTAssertTrue(XCUIDevice.shared.hasHardwareButton(.action))
        let shortcutsApp = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        shortcutsApp.launch()
        let shortcutPicker = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        let weeklyWins = shortcutPicker.staticTexts["WeeklyWins"]
        XCTAssertTrue(weeklyWins.waitForExistence(timeout: 10), shortcutPicker.debugDescription)
        weeklyWins.tap()
        XCTAssertTrue(shortcutPicker.staticTexts["Запись"].waitForExistence(timeout: 5), shortcutPicker.debugDescription)
        XCTAssertTrue(XCUIDevice.shared.hasHardwareButton(.action))
        #else
        throw XCTSkip("This setup probe is only for Simulator.")
        #endif
    }

    @MainActor
    func testRecordingShortcutStartsRecording() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("iOS 26.5 Simulator shows ‘Не удается запустить быструю команду приложения’ when this App Shortcut is invoked; direct intent behavior is tested in WeeklyWinsTests.")
        #else
        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        shortcuts.launch()

        let appShortcut = shortcuts.staticTexts["WeeklyWins"]
        XCTAssertTrue(appShortcut.waitForExistence(timeout: 10), shortcuts.debugDescription)
        appShortcut.tap()

        let recordingShortcut = shortcuts.staticTexts["Запись"]
        XCTAssertTrue(recordingShortcut.waitForExistence(timeout: 5), shortcuts.debugDescription)
        recordingShortcut.tap()

        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.activate()
        XCTAssertTrue(app.staticTexts["Запись идёт"].waitForExistence(timeout: 10), app.debugDescription)
        #endif
    }

    @MainActor
    func testActionButtonStartsAndStopsRecording() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("iOS 26.5 Simulator Action Button dispatch shows ‘Не удается запустить быструю команду приложения’; direct intent behavior is tested in WeeklyWinsTests.")
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
