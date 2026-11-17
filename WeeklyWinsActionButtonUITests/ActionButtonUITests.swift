import XCTest
import Speech
import UIKit

final class ActionButtonUITests: XCTestCase {
    @MainActor
    func testRecorderControlsRemainReachableAtLargestTextSize() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()
        addTeardownBlock { @MainActor in
            app.activate()
            let stop = app.buttons["recorder-stop"]
            if stop.exists && stop.isHittable { stop.tap() }
        }
        app.buttons["Записать"].tap()
        let stop = app.buttons["recorder-stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), app.debugDescription)
        let status = app.staticTexts["recorder-status"]
        XCTAssertGreaterThan(status.frame.height, 30, "The app must use the requested accessibility text size.")
        XCTAssertTrue(app.buttons["Свернуть"].isHittable)
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "A05-largest-text-initial"
        initial.lifetime = .keepAlways
        add(initial)
        for _ in 0..<4 {
            if stop.isHittable && app.frame.contains(stop.frame) { break }
            let scroll = app.scrollViews.firstMatch
            XCTAssertTrue(scroll.exists, app.debugDescription)
            scroll.swipeUp()
        }
        XCTAssertTrue(stop.isHittable)
        XCTAssertTrue(app.frame.contains(stop.frame))
        let controls = XCTAttachment(screenshot: app.screenshot())
        controls.name = "A05-largest-text-stop"
        controls.lifetime = .keepAlways
        add(controls)
        stop.tap()
        XCTAssertTrue(app.buttons["Записать"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFiveMinuteAutomaticStopReturnsToTimeline() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_LONG_CAPTURE_TEST"] == "1",
                          "Enable TEST_RUNNER_RUN_LONG_CAPTURE_TEST=1 for the five-minute wall-clock check.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        addTeardownBlock { @MainActor in
            app.activate()
            let stop = app.buttons["recorder-stop"]
            if stop.exists && stop.isHittable { stop.tap() }
        }
        app.buttons["Записать"].tap()
        XCTAssertTrue(app.buttons["recorder-stop"].waitForExistence(timeout: 10))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "A05-five-minute-recording"
        capture.lifetime = .keepAlways
        add(capture)
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: app.buttons["Записать"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 320), .completed, app.debugDescription)
        XCTAssertFalse(app.buttons["recorder-stop"].exists)
        let finished = XCTAttachment(screenshot: app.screenshot())
        finished.name = "A06-after-five-minute-stop"
        finished.lifetime = .keepAlways
        add(finished)
        app.buttons["studio-tab-1"].tap()
        let row = app.buttons.matching(identifier: "recording-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row.label.contains("Аудио · 5:00"), row.label)
    }

    @MainActor
    func testSavedTranscriptionFailureCanOpenAudioSource() throws {
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        let failure = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ошибка расшифровки")).firstMatch
        try XCTSkipUnless(failure.waitForExistence(timeout: 3), "This case requires a saved failed-recording fixture.")
        failure.tap()
        XCTAssertTrue(app.textViews["transcriptEditor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Прослушать"].exists)
    }

    @MainActor
    func testAutomaticTranscriptionFailureShowsSourceAndRetry() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This case exercises unavailable Russian ASR on Simulator.")
        #else
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ru-RU")) {
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            let status = await AssetInventory.status(forModules: [transcriber])
            try XCTSkipUnless(status == .unsupported, "This case requires unavailable on-device Russian ASR.")
        }
        try XCTSkipIf(SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))?.supportsOnDeviceRecognition == true,
                      "This case requires unavailable on-device Russian ASR.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        if app.staticTexts["Вспомнить свой день"].exists {
            app.buttons["Начать"].tap()
            app.buttons["Сделать пробную запись"].tap()
        } else { app.buttons["Записать"].tap() }
        XCTAssertTrue(app.staticTexts["Идёт запись"].waitForExistence(timeout: 5))
        app.buttons["recorder-stop"].tap()
        let failure = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ошибка расшифровки")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 10), app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "A06-automatic-transcription-error"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Повторить расшифровку"].firstMatch.tap()
        XCTAssertTrue(failure.waitForExistence(timeout: 10))
        failure.tap()
        XCTAssertTrue(app.textViews["transcriptEditor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Прослушать"].exists)
        #endif
    }

    @MainActor
    func testEventReviewDraftRestoresAndMergeRequiresConfirmation() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        app.buttons["Записать"].tap()
        XCTAssertTrue(app.staticTexts["Идёт запись"].waitForExistence(timeout: 5))
        app.buttons["recorder-stop"].tap()
        app.buttons["studio-tab-1"].tap()
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        let transcript = app.textViews["transcriptEditor"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        transcript.tap()
        transcript.typeText("Подготовил отчёт. Купил хлеб.")
        app.buttons["Сохранить текст"].tap()
        app.buttons["События"].tap()
        app.buttons["Подготовил отчёт, Без категории"].tap()
        let title = app.textFields["review-event-text"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        title.tap()
        title.typeText("Уточнил ")
        let editedTitle = try XCTUnwrap(title.value as? String)
        app.terminate()
        app.launch()
        app.buttons["studio-tab-1"].tap()
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        app.buttons["События"].tap()
        XCTAssertTrue(app.staticTexts[editedTitle].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Назад"].tap()
        XCTAssertTrue(app.buttons["Сохранить и закрыть"].waitForExistence(timeout: 5))
        app.buttons["Сохранить и закрыть"].tap()
        app.buttons["События"].tap()
        let compact = XCTAttachment(screenshot: app.screenshot())
        compact.name = "A10-event-review"
        compact.lifetime = .keepAlways
        add(compact)
        app.buttons["Купил хлеб, Без категории"].tap()
        let merge = app.buttons["Объединить с предыдущим"]
        if !merge.isHittable { app.swipeUp() }
        merge.tap()
        XCTAssertTrue(app.navigationBars["Объединить дела"].waitForExistence(timeout: 5))
        let proposalText = try XCTUnwrap(app.textFields.matching(identifier: "review-event-text")
            .allElementsBoundByIndex.first(where: { $0.isHittable }))
        proposalText.tap()
        proposalText.typeText("Проверил ")
        let mergeText = try XCTUnwrap(proposalText.value as? String)
        app.terminate()
        app.launch()
        app.buttons["studio-tab-1"].tap()
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        app.buttons["События"].tap()
        XCTAssertTrue(app.navigationBars["Объединить дела"].waitForExistence(timeout: 5))
        let restoredProposal = try XCTUnwrap(app.textFields.matching(identifier: "review-event-text")
            .allElementsBoundByIndex.first(where: { $0.isHittable }))
        XCTAssertEqual(restoredProposal.value as? String, mergeText)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "A10-merge-confirmation"
        preview.lifetime = .keepAlways
        add(preview)
        app.buttons["Отмена"].tap()
        XCTAssertTrue(app.staticTexts["Купил хлеб"].exists)
        app.buttons["Купил хлеб, Без категории"].tap()
        if !merge.isHittable { app.swipeUp() }
        merge.tap()
        app.buttons["Объединить"].tap()
        app.buttons["Готово"].tap()
        app.buttons["События"].tap()
        XCTAssertTrue(app.staticTexts[editedTitle + ". Купил хлеб"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Купил хлеб, Без категории"].exists)
    }

    @MainActor
    func testReportChartOpensDayAndReturnsToWeek() throws {
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        app.buttons["Записать"].tap()
        XCTAssertTrue(app.staticTexts["Идёт запись"].waitForExistence(timeout: 5))
        app.buttons["recorder-stop"].tap()
        app.buttons["studio-tab-1"].tap()
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        let editor = app.textViews["transcriptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Работал два часа.")
        app.buttons["Сохранить текст"].tap()
        app.buttons["Готово"].tap()
        app.buttons["studio-tab-2"].tap()
        app.buttons["Неделя"].tap()
        let period = app.buttons["Выбрать период"]
        let original = period.value as? String
        app.buttons["Следующий период"].tap()
        XCTAssertNotEqual(period.value as? String, original)
        app.buttons["Предыдущий период"].tap()
        XCTAssertEqual(period.value as? String, original)
        app.buttons["studio-tab-0"].tap()
        app.buttons["studio-tab-2"].tap()
        XCTAssertEqual(period.value as? String, original)
        let chart = app.otherElements["report-chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5), app.debugDescription)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap()
        let back = app.buttons["Вернуться к отчёту за неделю"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        back.tap()
        XCTAssertEqual(period.value as? String, original)
    }

    @MainActor
    func testFreshInstallOnboardingStartsTrialRecordingAndDoesNotRepeat() throws {
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        try XCTSkipUnless(app.staticTexts["Вспомнить свой день"].waitForExistence(timeout: 3), "Run this case on a clean Simulator installation.")
        app.buttons["Начать"].tap()
        XCTAssertTrue(app.staticTexts["Начните с голоса"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Сделать пробную запись"].waitForExistence(timeout: 5), "Microphone must be granted by the clean Simulator setup.")
        app.buttons["Сделать пробную запись"].tap()
        XCTAssertTrue(app.staticTexts["Идёт запись"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["Идёт запись"].waitForExistence(timeout: 5))
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
        addTeardownBlock { @MainActor in
            app.activate()
            let stop = app.buttons["recorder-stop"]
            if stop.exists && stop.isHittable { stop.tap() }
        }

        let startRecording = app.buttons["Записать"]
        XCTAssertTrue(startRecording.waitForExistence(timeout: 10), app.debugDescription)
        startRecording.tap()
        XCTAssertTrue(app.staticTexts["Идёт запись"].waitForExistence(timeout: 10), app.debugDescription)

        let status = app.staticTexts["recorder-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(status.label, "Идёт запись")
        let timer = app.staticTexts["recorder-timer"]
        XCTAssertNotNil(timer.label.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "A05-recording-controls"
        capture.lifetime = .keepAlways
        add(capture)
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
        let eventTitle = "Проверил отчёт \(UUID().uuidString.prefix(6))"
        editor.typeText(eventTitle + ".")
        app.buttons["Сохранить текст"].tap()
        app.buttons["Готово"].tap()
        app.buttons["studio-tab-0"].tap()
        let event = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", eventTitle)).firstMatch
        for _ in 0..<32 {
            if event.isHittable, event.frame.maxY < startRecording.frame.minY - 12 { break }
            app.scrollViews.firstMatch.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(event.isHittable, app.debugDescription)
        XCTAssertLessThan(event.frame.maxY, startRecording.frame.minY - 12)
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
        let back = shortcutsApp.buttons["Назад"].firstMatch
        if back.exists && back.isHittable { back.tap() }
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
    func testSavedShortcutStartsAndStopsRecording() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Saved-shortcut fixture setup runs on a dedicated Russian-language Simulator.")
        #else
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        addTeardownBlock { @MainActor in
            app.activate()
            let stop = app.buttons["Остановить"].firstMatch
            if stop.exists && stop.isHittable { stop.tap() }
        }
        let shortcuts = prepareSavedRecordingShortcut()
        let play = shortcuts.buttons["воспроизвести"]
        let readyToPlay = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: play
        )
        XCTAssertEqual(XCTWaiter.wait(for: [readyToPlay], timeout: 10), .completed, shortcuts.debugDescription)
        play.tap()
        app.activate()
        XCTAssertTrue(app.staticTexts["Идёт запись"].waitForExistence(timeout: 10), app.debugDescription)
        shortcuts.activate()
        let readyToStop = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: play
        )
        XCTAssertEqual(XCTWaiter.wait(for: [readyToStop], timeout: 10), .completed, shortcuts.debugDescription)
        play.tap()
        app.activate()
        XCTAssertTrue(app.buttons["Записать"].waitForExistence(timeout: 10), app.debugDescription)
        #endif
    }

    @MainActor
    func testRecordingShortcutStartsRecording() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("iOS 26.5 Simulator does not deliver the direct App Shortcut card invocation on build 17; testSavedShortcutStartsAndStopsRecording covers the saved single-action shortcut.")
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
        XCTAssertTrue(app.staticTexts["Идёт запись"].waitForExistence(timeout: 10), app.debugDescription)
        #endif
    }

    @MainActor
    func testActionButtonStartsAndStopsRecording() throws {
        continueAfterFailure = false
        let device = XCUIDevice.shared
        try XCTSkipUnless(device.hasHardwareButton(.action), "Device has no Action Button")
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        addTeardownBlock { @MainActor in
            app.activate()
            let stop = app.buttons["Остановить"].firstMatch
            if stop.exists && stop.isHittable { stop.tap() }
        }
        let recordingTitles = app.staticTexts.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "recording-title-"
        ))
        var previousRecordingID: String?
        if app.buttons["studio-tab-1"].exists {
            app.buttons["studio-tab-1"].tap()
            if app.buttons.matching(identifier: "recording-row").firstMatch.exists {
                XCTAssertTrue(recordingTitles.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
                previousRecordingID = recordingTitles.firstMatch.identifier
            }
        }
        #if targetEnvironment(simulator)
        let shortcuts = prepareSavedRecordingShortcut()
        shortcuts.buttons["Назад"].firstMatch.tap()
        let saved = shortcuts.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Начать или остановить запись"
        )).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), shortcuts.debugDescription)
        let shortcutName = saved.label
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let row = settings.staticTexts["Кнопка действия"]
        let back = settings.buttons["Настройки"].firstMatch
        if !row.exists && back.exists { back.tap() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), settings.debugDescription)
        row.tap()
        // The system's 3D carousel transition is not tracked by XCTest idling.
        Thread.sleep(forTimeInterval: 2)
        for _ in 0..<3 {
            if settings.staticTexts["Быстрая команда"].exists { break }
            settings.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.4)).press(
                forDuration: 0.1,
                thenDragTo: settings.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4)),
                withVelocity: .slow, thenHoldForDuration: 0.7
            )
        }
        XCTAssertTrue(settings.staticTexts["Быстрая команда"].exists, settings.debugDescription)
        let choose = settings.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "Выбрать команду…", shortcutName
        )).firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 5), settings.debugDescription)
        choose.tap()
        let selection = settings.staticTexts[shortcutName].firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 5), settings.debugDescription)
        selection.tap()
        #endif
        device.press(.home)
        device.press(.action)
        app.activate()
        XCTAssertTrue(app.staticTexts["Идёт запись"].waitForExistence(timeout: 10), app.debugDescription)
        device.press(.home)
        device.press(.action)
        app.activate()
        XCTAssertTrue(app.buttons["Записать"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["studio-tab-1"].tap()
        XCTAssertTrue(recordingTitles.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        let savedRecordingID = recordingTitles.firstMatch.identifier
        XCTAssertNotEqual(savedRecordingID, previousRecordingID)
        app.terminate()
        app.launch()
        app.buttons["studio-tab-1"].tap()
        let persistedRecording = app.staticTexts[savedRecordingID]
        XCTAssertTrue(persistedRecording.waitForExistence(timeout: 5), app.debugDescription)
        persistedRecording.tap()
        let play = app.buttons["Прослушать"]
        XCTAssertTrue(play.waitForExistence(timeout: 5), app.debugDescription)
        play.tap()
        XCTAssertTrue(app.buttons["Пауза"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Пауза"].tap()
    }

    @MainActor
    private func prepareSavedRecordingShortcut() -> XCUIApplication {
        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        shortcuts.launch()
        let back = shortcuts.buttons["Назад"].firstMatch
        if back.exists && back.isHittable { back.tap() }
        let saved = shortcuts.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Начать или остановить запись"
        )).firstMatch
        if !saved.exists {
            shortcuts.buttons["Создать быструю команду"].tap()
            let search = shortcuts.searchFields["Поиск действий"]
            XCTAssertTrue(search.waitForExistence(timeout: 5), shortcuts.debugDescription)
            search.tap()
            search.typeText("WeeklyWins")
            let action = shortcuts.staticTexts["Начать или остановить запись"].firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 30), shortcuts.debugDescription)
            action.tap()
            XCTAssertTrue(shortcuts.buttons["воспроизвести"].waitForExistence(timeout: 5))
        } else {
            let edit = saved.buttons["Еще"].firstMatch
            XCTAssertTrue(edit.waitForExistence(timeout: 10), shortcuts.debugDescription)
            edit.tap()
        }
        let showWhenRun = shortcuts.switches["Показать при запуске"]
        XCTAssertTrue(showWhenRun.waitForExistence(timeout: 5), shortcuts.debugDescription)
        if showWhenRun.value as? String == "1" {
            showWhenRun.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertEqual(showWhenRun.value as? String, "0", shortcuts.debugDescription)
        return shortcuts
    }
}
