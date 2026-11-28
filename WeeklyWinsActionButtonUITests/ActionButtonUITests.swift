import XCTest
import Speech
import UIKit

final class ActionButtonUITests: XCTestCase {
    @MainActor
    func testCustomReportRangeUsesTwoDatesInOneCalendar() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        app.buttons["studio-tab-2"].tap()

        let period = app.buttons["Выбрать период"]
        let calendar = app.navigationBars["Свой период"]
        let day = { (number: Int) in app.buttons["report-range-day-\(number)"] }
        func openCalendar() {
            period.tap()
            app.buttons["Свой период…"].tap()
            XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        }
        func attach(_ name: String) {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        openCalendar()
        day(1).tap()
        XCTAssertTrue(app.staticTexts["Выберите конец периода"].exists)
        attach("A16-report-range-start")
        app.buttons["Следующий месяц"].tap()
        day(2).tap()
        XCTAssertTrue(calendar.waitForNonExistence(timeout: 5))
        let range = period.value as? String
        XCTAssertTrue(range?.contains(" — ") == true)
        XCTAssertEqual(app.buttons["Категория"].value as? String, "Работа")
        let report = app.staticTexts["report-share-text"]
        if report.exists, let range { XCTAssertTrue(report.label.contains(range)) }

        openCalendar()
        day(3).tap()
        app.buttons["Отмена"].tap()
        XCTAssertTrue(calendar.waitForNonExistence(timeout: 5))
        XCTAssertEqual(period.value as? String, range)

        openCalendar()
        day(4).tap()
        day(4).tap()
        XCTAssertTrue(calendar.waitForNonExistence(timeout: 5))
        XCTAssertTrue((period.value as? String)?.hasPrefix("4 ") == true)
        XCTAssertFalse((period.value as? String)?.contains(" — ") == true)
    }

    @MainActor
    func testReportRangeCalendarAtLargestTextSize() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launchArguments = [
            "-hasCompletedOnboarding", "YES",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()
        app.buttons["studio-tab-2"].tap()

        let period = app.buttons["Выбрать период"]
        period.tap()
        app.buttons["Свой период…"].tap()
        let calendar = app.navigationBars["Свой период"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        let firstDay = app.buttons["report-range-day-1"]
        let secondDay = app.buttons["report-range-day-2"]
        XCTAssertTrue(firstDay.isHittable)
        XCTAssertGreaterThanOrEqual(firstDay.frame.height, 43.99)
        secondDay.tap()
        XCTAssertTrue(app.staticTexts["Выберите конец периода"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "A16-report-range-largest-text"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        firstDay.tap()
        XCTAssertTrue(calendar.waitForNonExistence(timeout: 5))
        XCTAssertTrue((period.value as? String)?.hasPrefix("1 ") == true)
        XCTAssertTrue((period.value as? String)?.contains(" — 2 ") == true)
    }

    @MainActor
    func testReportPeriodMenuSwipesByWeekAndMonth() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        app.buttons["studio-tab-2"].tap()

        let period = app.buttons["Выбрать период"]
        let category = app.buttons["Категория"]
        let report = app.staticTexts["report-share-text"]
        XCTAssertTrue(period.waitForExistence(timeout: 5))
        for mode in ["Неделя (текущая)", "Месяц"] {
            period.tap()
            app.buttons[mode].tap()

            let initial = period.value as? String
            let initialReport = report.exists ? report.label : nil
            let initialCategory = category.value as? String
            XCTAssertNotNil(initial)
            period.swipeRight()
            let previous = period.value as? String
            XCTAssertNotEqual(previous, initial, mode)
            if let initialReport {
                XCTAssertTrue(!report.exists || report.label != initialReport)
            }
            period.swipeUp()
            XCTAssertEqual(period.value as? String, previous)
            period.swipeLeft()
            XCTAssertEqual(period.value as? String, initial)
            if let initialReport { XCTAssertEqual(report.label, initialReport) }

            period.swipeLeft()
            XCTAssertNotEqual(period.value as? String, initial)
            period.swipeRight()
            XCTAssertEqual(period.value as? String, initial)
            XCTAssertEqual(category.value as? String, initialCategory)
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "A15-report-period-swipe"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testRecordingPeriodSwipesInBothDirections() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        app.buttons["studio-tab-1"].tap()

        for mode in ["Неделя", "Месяц"] {
            app.buttons["recording-period-mode"].tap()
            app.buttons[mode].tap()
            let range = app.staticTexts["recording-period-range"]
            XCTAssertTrue(range.waitForExistence(timeout: 5))
            let initial = range.label
            range.swipeRight()
            let previous = range.label
            XCTAssertNotEqual(previous, initial, mode)
            range.swipeUp()
            XCTAssertEqual(range.label, previous)
            range.swipeLeft()
            XCTAssertEqual(range.label, initial)
            range.swipeLeft()
            XCTAssertNotEqual(range.label, initial)
            range.swipeRight()
            XCTAssertEqual(range.label, initial)
            XCTAssertEqual(app.buttons["recording-period-mode"].label, mode)
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "A07-recording-period"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testCaptureFinalOverviewScreens() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()

        func attach(_ name: String) {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        XCTAssertTrue(app.buttons["Категория"].waitForExistence(timeout: 5))
        attach("A02-final-today")
        let previousDay = app.buttons["Предыдущий день"]
        XCTAssertTrue(previousDay.isHittable, app.debugDescription)
        XCTAssertLessThan(previousDay.frame.midX, 100, app.debugDescription)
        previousDay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let expectedPreviousDate = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
            .formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU")))
        XCTAssertTrue(app.staticTexts[expectedPreviousDate].waitForExistence(timeout: 5), app.debugDescription)
        let settingsDone = app.buttons["Готово"]
        if settingsDone.isHittable { settingsDone.tap() }
        XCTAssertFalse(app.buttons["return-to-today"].exists, app.debugDescription)
        attach("A03-final-previous-day")
        app.buttons["studio-tab-2"].tap()
        XCTAssertTrue(app.staticTexts["Отчёты"].waitForExistence(timeout: 5))
        attach("A14-final-reports-work-filter")
    }

    @MainActor
    func testTodayDateOpensDatePickerInsteadOfSettings() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()

        let dayPicker = app.buttons["Выбрать день"]
        XCTAssertTrue(dayPicker.waitForExistence(timeout: 5), app.debugDescription)
        dayPicker.tap()

        XCTAssertTrue(app.staticTexts["Выбор даты"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Настройки"].exists, app.debugDescription)
    }

    @MainActor
    func testTodayArrowChangesDateInsteadOfOpeningSettings() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()

        let dayPicker = app.buttons["Выбрать день"]
        let previousDay = app.buttons["Предыдущий день"]
        XCTAssertTrue(dayPicker.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(previousDay.isHittable, app.debugDescription)
        previousDay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let expectedDate = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        XCTAssertEqual(dayPicker.value as? String, formatter.string(from: expectedDate), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Настройки"].exists, app.debugDescription)
    }

    @MainActor
    func testReportsDoNotRepeatSelectedCategoryBelowFilter() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        app.buttons["studio-tab-2"].tap()

        let category = app.buttons["Категория"]
        XCTAssertTrue(category.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(category.value as? String, "Работа", app.debugDescription)
        XCTAssertFalse(app.buttons["reset-category-filter"].exists, app.debugDescription)
        XCTAssertFalse(app.otherElements["selected-category-summary"].exists, app.debugDescription)
    }

    @MainActor
    func testHobbyCategoryIsAvailableInTodayFilter() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()

        let category = app.buttons["Категория"]
        XCTAssertTrue(category.waitForExistence(timeout: 5), app.debugDescription)
        category.tap()
        XCTAssertTrue(app.buttons["Хобби"].waitForExistence(timeout: 5), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "A02-hobby-filter-option"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testTodaySwipeUsesSameDeleteButton() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()

        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Позвонил маме")).firstMatch
        guard card.waitForExistence(timeout: 5) else {
            throw XCTSkip("The Today feed has no event card in this simulator.")
        }
        card.swipeLeft()

        let delete = app.buttons["day-swipe-delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(delete.isHittable, app.debugDescription)
        XCTAssertTrue(card.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "A02-today-delete-revealed"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testRecordingSwipeRevealsDeleteWithoutDeleting() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        app.buttons["studio-tab-1"].tap()

        let row = app.buttons.matching(identifier: "recording-row").firstMatch
        guard row.waitForExistence(timeout: 5) else {
            throw XCTSkip("The recording list is empty in this simulator.")
        }
        row.swipeLeft()

        let delete = app.buttons["recording-swipe-delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(delete.isHittable, app.debugDescription)
        XCTAssertTrue(row.exists)
        XCTAssertFalse(app.buttons["recording-details-back"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "A07-recording-delete-revealed"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testRedesignAuditLongRecordingAndSearch() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_REDESIGN_AUDIT_FIXTURE"] == "1",
                          "Run with the AUDIT8, AUDIT60 and AUDIT300 recording fixture.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        app.buttons["studio-tab-1"].tap()
        let search = app.textFields["recording-search"]
        let row = app.buttons.matching(identifier: "recording-row").firstMatch
        let play = app.buttons["Прослушать"]
        let position = app.sliders["recording-playback-position"]
        for marker in ["AUDIT8", "AUDIT60", "AUDIT300"] {
            search.tap()
            search.typeText(marker)
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            XCTAssertFalse(app.buttons["studio-tab-1"].exists)
            XCTAssertLessThan(row.label.count, 220)
            XCTAssertTrue(row.label.contains(marker))
            row.tap()
            XCTAssertTrue(play.waitForExistence(timeout: 5))
            XCTAssertTrue(position.isEnabled)
            if marker != "AUDIT8" {
                let startPosition = position.value as? String
                position.adjust(toNormalizedSliderPosition: 0.72)
                XCTAssertNotEqual(position.value as? String, startPosition)
                XCTAssertTrue(play.isHittable)
            }
            play.tap()
            XCTAssertTrue(app.buttons["Пауза"].waitForExistence(timeout: 5))
            app.buttons["Пауза"].tap()
            if marker == "AUDIT300" {
                XCTAssertTrue(app.buttons["Изменить текст"].isHittable)
                XCTAssertTrue(app.buttons["События"].isHittable)
                let full = app.buttons["show-full-transcript"]
                XCTAssertTrue(full.isHittable)
                let details = XCTAttachment(screenshot: app.screenshot())
                details.name = "A08-reaudit-long-recording"
                details.lifetime = .keepAlways
                add(details)
                full.tap()
                let fullText = app.staticTexts["full-transcript"]
                XCTAssertTrue(fullText.waitForExistence(timeout: 5))
                XCTAssertGreaterThan(fullText.label.count, 1_000)
                app.buttons["Готово"].tap()
                app.buttons["Изменить текст"].tap()
                let editor = app.textViews["transcriptEditor"]
                XCTAssertTrue(editor.waitForExistence(timeout: 5))
                editor.tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
                app.buttons["transcript-keyboard-done"].tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
                app.buttons["Отмена"].tap()
                app.buttons["События"].tap()
                let list = app.collectionViews.firstMatch
                let first = list.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "AUDIT300 Сегодня")).firstMatch
                let second = list.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "посмотрел список")).firstMatch
                let undo = app.buttons["review-undo-deletion"]
                for event in [first, second] {
                    for _ in 0..<4 where !event.isHittable { list.swipeDown(velocity: .slow) }
                    event.tap()
                    let delete = list.buttons["Удалить событие"].firstMatch
                    for _ in 0..<4 where !delete.isHittable { list.swipeUp(velocity: .slow) }
                    delete.tap()
                    XCTAssertTrue(undo.isHittable)
                }
                let undoScreenshot = XCTAttachment(screenshot: app.screenshot())
                undoScreenshot.name = "A10-reaudit-undo"
                undoScreenshot.lifetime = .keepAlways
                add(undoScreenshot)
                undo.tap()
                XCTAssertTrue(second.waitForExistence(timeout: 5))
                XCTAssertTrue(undo.isHittable)
                undo.tap()
                XCTAssertTrue(first.waitForExistence(timeout: 5))
                XCTAssertFalse(undo.exists)
                app.buttons["Назад"].tap()
            }
            app.buttons["recording-details-back"].tap()
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            app.buttons["Очистить поиск"].tap()
        }
    }

    @MainActor
    func testRedesignAuditReportsAtLargestTextSize() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_REDESIGN_AUDIT_FIXTURE"] == "1",
                          "Run with the week of populated reports.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()
        app.buttons["studio-tab-2"].tap()
        let period = app.buttons["Выбрать период"]
        XCTAssertTrue(period.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(period.frame.height, 43.99)
        let shareText = app.staticTexts["report-share-text"]
        XCTAssertTrue(shareText.waitForExistence(timeout: 5))
        let share = app.buttons["report-share-button"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        let summary = XCTAttachment(screenshot: app.screenshot())
        summary.name = "A13-reaudit-largest-text"
        summary.lifetime = .keepAlways
        add(summary)

        for (title, name) in [("Неделя (текущая)", "A14"), ("Месяц", "A15"), ("Свой период…", "A16")] {
            period.tap()
            app.buttons[title].tap()
            if title == "Свой период…" {
                let calendar = app.navigationBars["Свой период"]
                XCTAssertTrue(calendar.waitForExistence(timeout: 5))
                app.buttons["report-range-day-1"].tap()
                let lastDay = Calendar.current.component(.day, from: .now)
                let end = app.buttons["report-range-day-\(lastDay)"]
                for _ in 0..<4 where !end.isHittable { app.scrollViews.firstMatch.swipeUp() }
                end.tap()
                XCTAssertTrue(calendar.waitForNonExistence(timeout: 5))
            }
            XCTAssertTrue(shareText.waitForExistence(timeout: 5))
            XCTAssertTrue(share.isHittable)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(name)-reaudit-largest-text"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testRedesignAuditMissingAudioStillAllowsManualEditing() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_REDESIGN_AUDIT_FIXTURE"] == "1",
                          "Run with the failed recording fixture without an audio file.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        app.buttons["studio-tab-1"].tap()
        let failed = app.buttons.matching(identifier: "recording-row").matching(
            NSPredicate(format: "label CONTAINS %@", "длительность не определена")
        ).firstMatch
        let list = app.scrollViews.firstMatch
        for _ in 0..<6 where !failed.isHittable { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(failed.isHittable)
        failed.tap()
        XCTAssertTrue(app.staticTexts["recording-audio-unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Прослушать"].exists)
        XCTAssertFalse(app.sliders["recording-playback-position"].exists)
        app.buttons["Изменить текст"].tap()
        XCTAssertTrue(app.textViews["transcriptEditor"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDayAuditKeepsFailuresGroupedAndCategoryFilterReachable() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_DAY_TIMELINE_FIXTURE"] == "1",
                          "Run on the day timeline fixture with three failed transcriptions.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()

        let summary = app.buttons["day-transcription-failures"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "3 записи требуют внимания")
        let retry = app.buttons.matching(identifier: "Повторить расшифровку")
        XCTAssertEqual(retry.count, 0)
        XCTAssertTrue(app.staticTexts["Подготовил отчёт"].isHittable)
        let unclassified = app.buttons["Без категории"]
        XCTAssertTrue(unclassified.isHittable)
        let collapsed = XCTAttachment(screenshot: app.screenshot())
        collapsed.name = "A02-reaudit-collapsed-failures"
        collapsed.lifetime = .keepAlways
        add(collapsed)

        summary.tap()
        XCTAssertTrue(retry.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(retry.count, 3)
        XCTAssertTrue(retry.firstMatch.isHittable)
        summary.tap()
        XCTAssertTrue(retry.firstMatch.waitForNonExistence(timeout: 5))

        unclassified.tap()
        XCTAssertFalse(app.staticTexts["Подготовил отчёт"].exists)
        let calendar = Calendar.current
        let now = Date.now
        let offset = calendar.component(.day, from: now) == 1 ? 1 : -1
        let otherDay = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: now))
        app.buttons["Выбрать день"].tap()
        XCTAssertTrue(app.navigationBars["Выбор даты"].waitForExistence(timeout: 5))
        let emptyDay = app.datePickers["Дата"].buttons.containing(
            .staticText, identifier: String(calendar.component(.day, from: otherDay))
        ).firstMatch
        emptyDay.tap()
        app.buttons["Готово"].tap()
        XCTAssertTrue(app.staticTexts["Нет дел в этой категории"].waitForExistence(timeout: 5))
        app.buttons["reset-category-filter"].tap()
        XCTAssertTrue(app.staticTexts["В этот день нет событий"].waitForExistence(timeout: 5))
        app.buttons[offset < 0 ? "Следующий день" : "Предыдущий день"].tap()
        app.buttons["Открыть аудио: Подготовил отчёт"].tap()
        XCTAssertTrue(app.buttons["Прослушать"].waitForExistence(timeout: 5))
        app.buttons["recording-details-back"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()
        let categoryMenu = app.buttons["Категория"]
        XCTAssertTrue(categoryMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(categoryMenu.isHittable)
        XCTAssertTrue(summary.isHittable)
        XCTAssertEqual(retry.count, 0)
        let largestText = XCTAttachment(screenshot: app.screenshot())
        largestText.name = "A02-reaudit-largest-text"
        largestText.lifetime = .keepAlways
        add(largestText)
        categoryMenu.tap()
        XCTAssertTrue(unclassified.waitForExistence(timeout: 5))
        unclassified.tap()
        XCTAssertFalse(app.staticTexts["Подготовил отчёт"].exists)
    }

    @MainActor
    func testDaySwipeRevealsDeleteAndCanRestoreTheCard() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_DAY_TIMELINE_FIXTURE"] == "1",
                          "Run on the day timeline fixture with known cards.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()

        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Подготовил отчёт,")).firstMatch
        let action = app.buttons["day-swipe-delete"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.swipeLeft()
        XCTAssertTrue(action.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(action.isHittable, app.debugDescription)
        XCTAssertTrue(card.exists)
        XCTAssertFalse(app.navigationBars["Событие"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "A02-day-swipe-open"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        card.swipeRight()
        XCTAssertTrue(action.waitForNonExistence(timeout: 4))
        card.swipeLeft()
        action.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))

        app.buttons["studio-tab-1"].tap()
        let search = app.textFields["recording-search"]
        search.tap()
        search.typeText("Подготовил отчёт\n")
        app.buttons["recording-row"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Прослушать"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["recording-playback-position"].isEnabled)
        app.buttons["recording-details-back"].tap()
        app.buttons["studio-tab-0"].tap()
        XCTAssertFalse(card.exists)

        let secondCard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Купил продукты,")).firstMatch
        secondCard.swipeLeft()
        action.tap()
        XCTAssertTrue(secondCard.waitForNonExistence(timeout: 5))
        let undo = app.buttons["day-undo-deletion"]
        XCTAssertTrue(undo.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(undo.isHittable, app.debugDescription)
        undo.tap()
        XCTAssertTrue(secondCard.waitForExistence(timeout: 5))
        XCTAssertFalse(card.exists)
        XCTAssertTrue(undo.isHittable)
        undo.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertFalse(undo.exists)

        app.terminate()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let timeline = app.scrollViews["day-timeline"]
        let record = app.buttons["day-floating-record"]
        for _ in 0..<3 where card.frame.maxY > record.frame.minY {
            timeline.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(card.isHittable, app.debugDescription)
        card.swipeLeft()
        XCTAssertTrue(action.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(action.isHittable, app.debugDescription)
        let largeText = XCTAttachment(screenshot: app.screenshot())
        largeText.name = "A02-day-swipe-largest-text"
        largeText.lifetime = .keepAlways
        add(largeText)
        action.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    @MainActor
    func testDayTimelineKeepsFloatingRecordButtonAndLastCardReachable() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_DAY_TIMELINE_FIXTURE"] == "1",
                          "Run on a disposable Simulator seeded with the long day timeline fixture.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()

        let record = app.buttons["day-floating-record"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertEqual(record.label, "Записать")
        XCTAssertEqual(record.frame.width, 48, accuracy: 1)
        XCTAssertEqual(record.frame.height, 48, accuracy: 1)
        XCTAssertLessThan(record.frame.midX, app.frame.midX)
        let sideInset = record.frame.minX - app.frame.minX
        let tabContentPadding: CGFloat = 12
        let bottomInset = app.buttons["studio-tab-0"].frame.minY - tabContentPadding - record.frame.maxY
        XCTAssertEqual(sideInset, 20, accuracy: 1)
        XCTAssertEqual(bottomInset, sideInset, accuracy: 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "A02-day-regular-text-and-record-insets"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let date = app.buttons["Выбрать день"]
        XCTAssertGreaterThanOrEqual(date.frame.height, 44)
        date.tap()
        XCTAssertTrue(app.navigationBars["Выбор даты"].waitForExistence(timeout: 5))
        app.buttons["Готово"].tap()

        let timeline = app.scrollViews["day-timeline"]
        let lastCard = timeline.staticTexts["Последнее дело из тестовой ленты"]
        let position = record.frame
        for _ in 0..<14 {
            if lastCard.isHittable, lastCard.frame.maxY < record.frame.minY { break }
            timeline.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(lastCard.isHittable)
        XCTAssertLessThan(lastCard.frame.maxY, record.frame.minY)
        XCTAssertEqual(record.frame, position)
        XCTAssertTrue(record.isHittable)
    }

    @MainActor
    func testDayTimelineKeepsTopControlsFixedWhileScrolling() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_DAY_TIMELINE_FIXTURE"] == "1",
                          "Run on a disposable Simulator seeded with the long day timeline fixture.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()

        let date = app.buttons["Выбрать день"]
        let category = app.buttons["Категория"]
        let settings = app.buttons["settings-button"]
        let timeline = app.collectionViews["day-timeline"]
        let firstCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Подготовил отчёт")
        ).firstMatch
        let lastCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Последнее дело из тестовой ленты")
        ).firstMatch
        guard firstCard.waitForExistence(timeout: 5) else {
            throw XCTSkip("The long day timeline fixture is not installed in this Simulator.")
        }
        XCTAssertTrue(date.isHittable)
        XCTAssertTrue(category.isHittable)
        XCTAssertTrue(settings.isHittable)
        let dateFrame = date.frame
        let categoryFrame = category.frame
        let settingsFrame = settings.frame

        for _ in 0..<14 {
            if lastCard.isHittable { break }
            timeline.swipeUp(velocity: .fast)
        }

        XCTAssertTrue(lastCard.isHittable, app.debugDescription)
        XCTAssertFalse(firstCard.isHittable, app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "A02-top-controls-fixed-after-scroll"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(date.isHittable, app.debugDescription)
        XCTAssertTrue(category.isHittable, app.debugDescription)
        XCTAssertTrue(settings.isHittable, app.debugDescription)
        XCTAssertEqual(date.frame, dateFrame)
        XCTAssertEqual(category.frame, categoryFrame)
        XCTAssertEqual(settings.frame, settingsFrame)
    }

    @MainActor
    func testEmptyTodayKeepsFloatingRecordButtonVisible() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()

        guard app.staticTexts["Нет событий"].waitForExistence(timeout: 5) else {
            throw XCTSkip("The current simulator day is not empty.")
        }
        XCTAssertTrue(app.buttons["day-floating-record"].isHittable, app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "A02-empty-day-fixed-controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testSettingsOpenAudioStorageManagement() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()

        let settingsButton = app.buttons["settings-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), app.debugDescription)
        settingsButton.tap()
        let storageLink = app.buttons["settings-audio-storage"]
        XCTAssertTrue(storageLink.waitForExistence(timeout: 5), app.debugDescription)
        storageLink.tap()

        XCTAssertTrue(app.staticTexts["Хранилище аудио"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.switches["audio-retention-toggle"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Занято аудиозаписями"].exists, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Аудиозаписи"].exists, app.debugDescription)
    }

    @MainActor
    func testSettingsOpenExternalReportPromptEditor() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()

        let settingsButton = app.buttons["settings-button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), app.debugDescription)
        settingsButton.tap()
        let promptLink = app.buttons["settings-report-prompt"]
        XCTAssertTrue(promptLink.waitForExistence(timeout: 5), app.debugDescription)
        promptLink.tap()

        let editor = app.textViews["report-model-prompt-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue((editor.value as? String)?.contains("рабочего отчёта за неделю") == true)
        XCTAssertTrue(app.buttons["report-prompt-reset"].exists)
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "report-prompt-editor-keyboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Готово"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    @MainActor
    func testDeniedMicrophoneShowsRecordingPreparationAndRetry() throws {
        #if targetEnvironment(simulator)
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_DENIED_MIC_UI_TEST"] == "1",
                          "Enable TEST_RUNNER_RUN_DENIED_MIC_UI_TEST=1 after revoking microphone access.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        app.buttons["Записать"].tap()
        if ProcessInfo.processInfo.environment["RUN_MIC_UI_PROMPT"] == "1" {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let prompt = springboard.alerts.firstMatch
            XCTAssertTrue(prompt.waitForExistence(timeout: 5), springboard.debugDescription)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "A04-microphone-preparation"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let deny = prompt.buttons.matching(NSPredicate(format: "label IN %@", [
                "Не разрешать", "Не разрешить", "Don’t Allow", "Don't Allow"
            ])).firstMatch
            XCTAssertTrue(deny.exists, prompt.debugDescription)
            deny.tap()
        }
        let retry = app.buttons["Повторить"]
        let failure = app.staticTexts["Нет доступа к микрофону"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Запись"].exists)
        XCTAssertTrue(app.buttons["Открыть настройки"].isHittable)
        XCTAssertFalse(app.buttons["recorder-stop"].exists)
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "A04-microphone-denied"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Закрыть"].tap()
        XCTAssertTrue(app.buttons["Записать"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("This permission fixture uses Simulator.")
        #endif
    }

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
        #if targetEnvironment(simulator)
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_RECORDING_FAILURE_FIXTURE"] == "1",
                          "Run with the failed-recording Simulator fixture.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        let failure = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ошибка расшифровки")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 5), app.debugDescription)
        failure.tap()
        XCTAssertTrue(app.buttons["transcript-preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Прослушать"].exists)
        app.buttons["Настройки распознавания"].tap()
        XCTAssertTrue(app.navigationBars["Настройки"].waitForExistence(timeout: 5))
        app.buttons["Готово"].tap()
        app.buttons["recording-details-actions"].tap()
        app.buttons["Удалить запись"].tap()
        XCTAssertTrue(app.staticTexts["Удалить запись?"].waitForExistence(timeout: 5))
        app.buttons["Удалить запись"].tap()
        XCTAssertTrue(failure.waitForNonExistence(timeout: 5))
        #else
        throw XCTSkip("This case operates on a disposable Simulator fixture.")
        #endif
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
        XCTAssertTrue(app.buttons["transcript-preview"].waitForExistence(timeout: 5))
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
        openRecordingsAfterSaving(app)
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        app.buttons["Изменить текст"].tap()
        let transcript = app.textViews["transcriptEditor"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        transcript.tap()
        transcript.typeText("Подготовил отчёт. Купил хлеб.")
        app.buttons["save-transcript"].tap()
        app.buttons["События"].tap()
        XCTAssertTrue(app.buttons["Подготовил отчёт, Без категории"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recording-details-back"].exists)
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
        let firstSource = app.staticTexts["merge-source-0"]
        let secondSource = app.staticTexts["merge-source-1"]
        XCTAssertTrue(firstSource.label.contains("Подготовил отчёт"))
        XCTAssertTrue(secondSource.label.contains("Купил хлеб"))
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
        XCTAssertTrue(firstSource.exists)
        XCTAssertTrue(secondSource.exists)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "A17-merge-confirmation"
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
    func testReportPeriodsUpdateShareTextAcrossTabs() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        app.buttons["Записать"].tap()
        XCTAssertTrue(app.staticTexts["Идёт запись"].waitForExistence(timeout: 5))
        app.buttons["recorder-stop"].tap()
        openRecordingsAfterSaving(app)
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        app.buttons["Изменить текст"].tap()
        let editor = app.textViews["transcriptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Работал два часа. Купил хлеб.")
        app.buttons["save-transcript"].tap()
        app.buttons["recording-details-back"].tap()
        app.buttons["studio-tab-2"].tap()
        func attach(_ name: String) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
        }
        func shareLabel() -> String {
            app.staticTexts["report-share-text"].label
        }
        let menuButton = app.buttons["Выбрать период"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))

        // Неделя (по умолчанию): текст сгруппирован по дням.
        let weekText = shareLabel()
        XCTAssertTrue(weekText.contains("Неделя"), weekText)
        XCTAssertTrue(weekText.contains("Работал два часа (2 ч 0 мин)"), weekText)
        XCTAssertTrue(weekText.contains("Купил хлеб"), weekText)
        XCTAssertTrue(app.buttons["report-share-button"].isHittable)
        attach("A14-report-week")

        // День: выбор из меню открывает календарь, после «Готово» отчёт за день.
        menuButton.tap()
        app.buttons["День"].tap()
        XCTAssertTrue(app.buttons["Готово"].waitForExistence(timeout: 5))
        app.buttons["Готово"].tap()
        let dayText = shareLabel()
        XCTAssertTrue(dayText.contains("Дела за"), dayText)
        XCTAssertTrue(dayText.contains("Купил хлеб"), dayText)
        attach("A13-report-day")

        // Месяц: группировка по неделям, заголовок — текущий месяц.
        menuButton.tap()
        app.buttons["Месяц"].tap()
        let monthText = shareLabel()
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "ru_RU")
        monthFormatter.dateFormat = "LLLL yyyy"
        let monthTitle = monthFormatter.string(from: .now).capitalized
        XCTAssertTrue(monthText.contains(monthTitle), monthText)
        XCTAssertTrue(monthText.contains("Работал два часа"), monthText)
        attach("A15-report-month")

        // Свой период: две даты в одном календаре.
        menuButton.tap()
        app.buttons["Свой период…"].tap()
        let rangeCalendar = app.navigationBars["Свой период"]
        XCTAssertTrue(rangeCalendar.waitForExistence(timeout: 5))
        app.buttons["report-range-day-1"].tap()
        let todayNumber = Calendar.current.component(.day, from: .now)
        app.buttons["report-range-day-\(todayNumber)"].tap()
        XCTAssertTrue(rangeCalendar.waitForNonExistence(timeout: 5))
        let customText = shareLabel()
        XCTAssertTrue(customText.contains("Дела за"), customText)
        XCTAssertTrue(customText.contains("Работал два часа"), customText)
        attach("A16-report-custom")

        // Состояние периода сохраняется при переключении вкладок.
        let selected = menuButton.value as? String
        app.buttons["studio-tab-0"].tap()
        app.buttons["studio-tab-2"].tap()
        XCTAssertEqual(menuButton.value as? String, selected)

        // Компактная запись поверх отчёта: начинаем с «Сегодня», сворачиваем и возвращаемся к отчёту.
        app.buttons["studio-tab-0"].tap()
        app.buttons["Записать"].tap()
        let collapse = app.buttons["Свернуть"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 5))
        collapse.tap()
        app.buttons["studio-tab-2"].tap()
        let compactStop = app.buttons["compact-recording-stop"]
        XCTAssertTrue(compactStop.waitForExistence(timeout: 5))
        XCTAssertTrue(compactStop.isHittable)
        compactStop.tap()
        XCTAssertEqual(menuButton.value as? String, selected)
    }

    @MainActor
    func testEventAndTranscriptEditIndependently() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        defer { app.terminate() }

        let originalTitle = "Проверил правку существующего события"
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", originalTitle)).firstMatch
        guard card.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the inline editing recording fixture.")
        }
        card.tap()

        func attach(_ name: String) {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        let title = app.buttons["edit-event"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "event-time").count, 1)
        let openSource = app.buttons["Открыть аудиозапись и текст"]
        XCTAssertTrue(openSource.isHittable)
        XCTAssertFalse(app.buttons["edit-event-transcript"].exists)
        attach("A11-event-detail")

        title.tap()
        let field = app.descendants(matching: .any).matching(identifier: "event-editor-title").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if !app.keyboards.firstMatch.exists { field.tap() }
        field.typeText(" правка")
        let save = app.buttons["save-event"]
        XCTAssertTrue(save.isHittable)
        if app.keyboards.firstMatch.exists {
            XCTAssertLessThanOrEqual(save.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        }
        attach("A12-inline-editor")
        app.buttons["Отмена"].tap()
        app.buttons["Отбросить изменения"].tap()
        XCTAssertEqual(title.label, originalTitle)

        title.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if !app.keyboards.firstMatch.exists { field.tap() }
        field.typeText(" сохранено")
        save.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("сохранено"))

        openSource.tap()
        let sourceTranscript = app.staticTexts["source-transcript"]
        XCTAssertTrue(sourceTranscript.waitForExistence(timeout: 5))
        XCTAssertEqual(sourceTranscript.label, "Исходная расшифровка для проверки")
        let play = app.buttons["Прослушать"]
        XCTAssertTrue(play.isHittable)
        XCTAssertTrue(play.isEnabled)
        XCTAssertFalse(app.buttons["Изменить текст"].exists)
        XCTAssertFalse(app.textViews["transcriptEditor"].exists)
        attach("A08-recording-source")
        app.buttons["recording-details-back"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("сохранено"))
        title.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if !app.keyboards.firstMatch.exists { field.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText(" проверка")
        XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(save.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        attach("A12-inline-editor-largest-text")
        app.buttons["Отмена"].tap()
        app.buttons["Отбросить изменения"].tap()
    }

    @MainActor
    func testEventDetailChangesCategoryWithoutEditor() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        addTeardownBlock { @MainActor in
            app.activate()
            let stop = app.buttons["recorder-stop"].firstMatch
            if stop.exists && stop.isHittable { stop.tap() }
        }
        app.buttons["Записать"].tap()
        XCTAssertTrue(app.buttons["recorder-stop"].waitForExistence(timeout: 10))
        app.buttons["recorder-stop"].tap()
        openRecordingsAfterSaving(app)
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        app.buttons["Изменить текст"].tap()
        let editor = app.textViews["transcriptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Обсудил планы на выходные. Купил хлеб.")
        app.buttons["save-transcript"].tap()
        app.buttons["recording-details-back"].tap()

        app.buttons["studio-tab-0"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Обсудил планы")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), app.debugDescription)
        card.tap()
        XCTAssertTrue(app.navigationBars["Событие"].waitForExistence(timeout: 5))
        let category = app.buttons["event-category"]
        XCTAssertTrue(category.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(category.label.contains("Без категории"), category.label)
        usleep(600_000)
        XCTAssertTrue(category.isHittable, app.debugDescription)
        category.tap()
        let work = app.sheets.buttons["Работа"]
        XCTAssertTrue(work.waitForExistence(timeout: 5), app.debugDescription)
        work.tap()
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertTrue(category.label.contains("Работа"), category.label)
        let changed = XCTAttachment(screenshot: app.screenshot())
        changed.name = "A17-event-category-quick-change"
        changed.lifetime = .keepAlways
        add(changed)
        #else
        throw XCTSkip("This detail regression runs on Simulator.")
        #endif
    }

    @MainActor
    func testTodayEditAndReportDeletionUpdateAlreadyOpenedTabs() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        addTeardownBlock { @MainActor in
            app.activate()
            let stop = app.buttons["recorder-stop"].firstMatch
            if stop.exists && stop.isHittable { stop.tap() }
        }
        app.buttons["Записать"].tap()
        XCTAssertTrue(app.buttons["recorder-stop"].waitForExistence(timeout: 10))
        app.buttons["recorder-stop"].tap()
        openRecordingsAfterSaving(app)
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        app.buttons["Изменить текст"].tap()
        let editor = app.textViews["transcriptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let marker = UUID().uuidString.prefix(6)
        let title = "Подготовил отчёт \(marker)"
        let neighbor = "Купил хлеб \(marker)"
        editor.tap()
        editor.typeText(title + ". " + neighbor + ".")
        app.buttons["save-transcript"].tap()
        app.buttons["recording-details-back"].tap()

        app.buttons["studio-tab-2"].tap()
        let reportMenu = app.buttons["Выбрать период"]
        XCTAssertTrue(reportMenu.waitForExistence(timeout: 5))
        reportMenu.tap()
        app.buttons["Неделя (текущая)"].tap()
        app.buttons["studio-tab-0"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        let neighboringCard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", neighbor)).firstMatch
        func revealCard(_ element: XCUIElement) {
            let record = app.buttons["Записать"]
            for _ in 0..<20 {
                if element.exists && element.isHittable && element.frame.maxY < record.frame.minY { return }
                app.scrollViews.firstMatch.swipeUp(velocity: .fast)
            }
            XCTFail("Could not reveal the saved event in the current view.")
        }

        func dismissEvent() {
            let header = app.navigationBars["Событие"]
            header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            )
            XCTAssertTrue(header.waitForNonExistence(timeout: 5))
        }

        revealCard(card)
        card.tap()
        let edit = app.buttons["edit-event"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        let eventTime = app.descendants(matching: .any)["event-time"].firstMatch
        XCTAssertEqual(eventTime.value as? String, "Не указано", app.debugDescription)
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "A11-event-detail"
        detail.lifetime = .keepAlways
        add(detail)
        if !edit.isHittable { app.swipeUp() }
        edit.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Категория,")).firstMatch.tap()
        app.buttons["Дом"].firstMatch.tap()
        let duration = app.switches["Указать длительность"]
        duration.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let minutes = app.textFields["event-duration-minutes"]
        XCTAssertTrue(minutes.waitForExistence(timeout: 5), app.debugDescription)
        minutes.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        minutes.typeText(XCUIKeyboardKey.delete.rawValue + "2")
        XCTAssertEqual(minutes.value as? String, "2")
        let save = app.buttons["save-event"]
        XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(save.frame.maxY, keyboard.frame.minY)
        let editorKeyboard = XCTAttachment(screenshot: app.screenshot())
        editorKeyboard.name = "A12-event-editor-keyboard"
        editorKeyboard.lifetime = .keepAlways
        add(editorKeyboard)
        save.tap()
        XCTAssertTrue(app.staticTexts["Длительность"].waitForExistence(timeout: 5))
        dismissEvent()
        app.buttons["studio-tab-2"].tap()
        app.buttons["Дом"].firstMatch.tap()
        func shareLabel() -> String { app.staticTexts["report-share-text"].label }
        for item in ["День", "Неделя (текущая)", "Месяц"] {
            reportMenu.tap()
            app.buttons[item].tap()
            if item == "День" {
                XCTAssertTrue(app.buttons["Готово"].waitForExistence(timeout: 5))
                app.buttons["Готово"].tap()
            }
            let text = shareLabel()
            XCTAssertTrue(text.contains("\(title) (2 мин)"), text)
        }

        app.buttons["studio-tab-0"].tap()
        revealCard(card)
        card.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        if !edit.isHittable { app.swipeUp() }
        edit.tap()
        let eventTitle = app.descendants(matching: .any)["event-editor-title"].firstMatch
        XCTAssertTrue(eventTitle.waitForExistence(timeout: 5), app.debugDescription)
        eventTitle.tap()
        eventTitle.typeText(" Черновик")
        let draft = try XCTUnwrap(eventTitle.value as? String)
        app.buttons["event-editor-actions"].tap()
        app.buttons["event-editor-delete"].tap()
        XCTAssertTrue(app.staticTexts["Удалить событие?"].waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "confirm-event-deletion").firstMatch.tap()
        let undo = app.buttons["Отменить удаление"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        if !edit.isHittable { app.swipeUp() }
        edit.tap()
        XCTAssertTrue(eventTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(eventTitle.value as? String, draft)
        app.buttons["Отмена"].tap()
        app.buttons["Отбросить изменения"].tap()
        let delete = app.buttons["Удалить событие"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        if !delete.isHittable { app.swipeUp() }
        delete.tap()
        XCTAssertTrue(app.staticTexts["Событие удалено"].waitForExistence(timeout: 5))
        dismissEvent()
        app.buttons["studio-tab-0"].tap()
        revealCard(neighboringCard)
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))

        app.terminate()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()
        revealCard(neighboringCard)
        neighboringCard.tap()
        for _ in 0..<6 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable, app.debugDescription)
        edit.tap()
        XCTAssertTrue(eventTitle.waitForExistence(timeout: 5))
        eventTitle.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isHittable)
        XCTAssertLessThanOrEqual(save.frame.maxY, keyboard.frame.minY)
        let largest = XCTAttachment(screenshot: app.screenshot())
        largest.name = "A12-event-editor-largest-text"
        largest.lifetime = .keepAlways
        add(largest)
        #else
        throw XCTSkip("This editing and report regression runs on Simulator.")
        #endif
    }

    @MainActor
    func testRecordingFromAnotherDayKeepsSelectionAndUsesCurrentDate() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        addTeardownBlock { @MainActor in
            app.activate()
            let stop = app.buttons["recorder-stop"].firstMatch
            if stop.exists && stop.isHittable { stop.tap() }
        }
        let datePicker = app.buttons["Выбрать день"]
        XCTAssertTrue(datePicker.waitForExistence(timeout: 5))
        let todayLabel = datePicker.value as? String
        let calendar = Calendar.current
        let now = Date.now
        let offset = calendar.component(.day, from: now) == 1 ? 1 : -1
        let selectedDay = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: now))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        let selectedLabel = formatter.string(from: selectedDay)
        datePicker.tap()
        XCTAssertTrue(app.navigationBars["Выбор даты"].waitForExistence(timeout: 5))
        let calendarScreenshot = XCTAttachment(screenshot: app.screenshot())
        calendarScreenshot.name = "A16-calendar"
        calendarScreenshot.lifetime = .keepAlways
        add(calendarScreenshot)
        let calendarDay = app.datePickers["Дата"].buttons.containing(
            .staticText, identifier: String(calendar.component(.day, from: selectedDay))
        ).firstMatch
        XCTAssertTrue(calendarDay.waitForExistence(timeout: 5), app.debugDescription)
        calendarDay.tap()
        app.buttons["Готово"].tap()
        XCTAssertEqual(datePicker.value as? String, selectedLabel)

        let outward = app.buttons[offset < 0 ? "Предыдущий день" : "Следующий день"]
        let inward = app.buttons[offset < 0 ? "Следующий день" : "Предыдущий день"]
        outward.tap()
        let adjacent = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: selectedDay))
        XCTAssertEqual(datePicker.value as? String, formatter.string(from: adjacent))
        inward.tap()
        XCTAssertEqual(datePicker.value as? String, selectedLabel)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "A03-other-day"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["Записать"].tap()
        let stop = app.buttons["recorder-stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        stop.tap()
        XCTAssertTrue(datePicker.waitForExistence(timeout: 5))
        XCTAssertEqual(datePicker.value as? String, selectedLabel)
        let savedAudio = app.buttons["open-saved-audio"]
        XCTAssertTrue(savedAudio.waitForExistence(timeout: 5))
        savedAudio.tap()
        XCTAssertTrue(app.buttons["transcript-preview"].waitForExistence(timeout: 5))
        app.buttons["Изменить текст"].tap()
        let editor = app.textViews["transcriptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let title = "Подготовил отчёт \(UUID().uuidString.prefix(6))"
        editor.tap()
        editor.typeText(title + ".")
        app.buttons["save-transcript"].tap()
        app.buttons["recording-details-back"].tap()
        XCTAssertEqual(datePicker.value as? String, selectedLabel)
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertFalse(card.exists)
        inward.tap()
        XCTAssertEqual(datePicker.value as? String, todayLabel)
        for _ in 0..<32 {
            if card.exists { break }
            app.scrollViews.firstMatch.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        #else
        throw XCTSkip("This timeline date regression runs on Simulator.")
        #endif
    }

    @MainActor
    func testFreshInstallOnboardingStartsTrialRecordingAndDoesNotRepeat() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        try XCTSkipUnless(app.staticTexts["Вспомнить свой день"].waitForExistence(timeout: 3), "Run this case on a clean Simulator installation.")
        let introduction = XCTAttachment(screenshot: app.screenshot())
        introduction.name = "A01-onboarding"
        introduction.lifetime = .keepAlways
        add(introduction)
        app.buttons["Начать"].tap()
        XCTAssertTrue(app.staticTexts["Начните с голоса"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Сделать пробную запись"].waitForExistence(timeout: 5), "Microphone must be granted by the clean Simulator setup.")
        let ready = XCTAttachment(screenshot: app.screenshot())
        ready.name = "A01-onboarding-microphone"
        ready.lifetime = .keepAlways
        add(ready)
        app.buttons["Сделать пробную запись"].tap()
        XCTAssertTrue(app.staticTexts["Идёт запись"].waitForExistence(timeout: 5))
        app.buttons["recorder-stop"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Записать"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Вспомнить свой день"].exists)
    }

    @MainActor
    func testOnboardingOffersMicrophoneThenSkipAfterDenial() throws {
        #if targetEnvironment(simulator)
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_ONBOARDING_PERMISSION_FIXTURE"] == "1",
                          "Run on a clean Simulator with microphone permission undetermined.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        app.buttons["Начать"].tap()
        let microphone = app.buttons["Проверить микрофон"]
        let skip = app.buttons["Продолжить без записи"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        XCTAssertTrue(microphone.isHittable)
        XCTAssertGreaterThanOrEqual(microphone.frame.height, 55)
        XCTAssertGreaterThan(skip.frame.minY, microphone.frame.minY)
        microphone.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let prompt = springboard.alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.buttons.matching(NSPredicate(format: "label IN %@", [
            "Не разрешать", "Не разрешить", "Don’t Allow", "Don't Allow"
        ])).firstMatch.tap()
        let settings = app.buttons["Открыть настройки iPhone"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.isHittable)
        XCTAssertTrue(skip.isHittable)
        skip.tap()
        XCTAssertTrue(app.buttons["day-floating-record"].waitForExistence(timeout: 5))
        #endif
    }

    @MainActor
    func testTranscriptDraftSurvivesAppRelaunchAndCanBeDiscarded() throws {
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        app.buttons["Записать"].tap()
        XCTAssertTrue(app.staticTexts["Идёт запись"].waitForExistence(timeout: 5))
        app.buttons["recorder-stop"].tap()
        openRecordingsAfterSaving(app)
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        app.buttons["Изменить текст"].tap()
        let editor = app.textViews["transcriptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        let marker = "Черновик после перезапуска"
        editor.typeText(marker)
        XCTAssertTrue(app.staticTexts["Черновик сохранён"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()
        app.buttons["studio-tab-1"].tap()
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, marker)
        XCTAssertTrue(app.staticTexts["Расшифровка"].isHittable)
        XCTAssertTrue(app.buttons["save-transcript"].isHittable)
        editor.tap()
        XCTAssertTrue(app.buttons["transcript-keyboard-done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["save-transcript"].isHittable)
        let largest = XCTAttachment(screenshot: app.screenshot())
        largest.name = "A09-transcript-editor-largest-text"
        largest.lifetime = .keepAlways
        add(largest)
        app.buttons["Отмена"].tap()
        app.buttons["Отбросить изменения"].tap()
        let preview = app.buttons["transcript-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertNotEqual(preview.label, marker)
        app.buttons["recording-details-back"].tap()
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertFalse(editor.exists)
    }

    @MainActor
    func testRecordingSearchAndConfirmedDeletion() throws {
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        let marker = "Проверка удаления \(UUID().uuidString)"
        app.buttons["Записать"].tap()
        XCTAssertTrue(app.buttons["recorder-stop"].waitForExistence(timeout: 5))
        app.buttons["recorder-stop"].tap()
        openRecordingsAfterSaving(app)
        app.buttons.matching(identifier: "recording-row").firstMatch.tap()
        app.buttons["Изменить текст"].tap()
        let editor = app.textViews["transcriptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(marker)
        app.buttons["save-transcript"].tap()
        app.buttons["recording-details-back"].tap()
        let search = app.textFields["recording-search"]
        search.tap()
        search.typeText(marker)
        XCTAssertEqual(app.buttons.matching(identifier: "recording-row").count, 1)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.buttons["studio-tab-1"].exists)
        XCTAssertFalse(app.buttons["Записать"].exists)
        let searchResults = XCTAttachment(screenshot: app.screenshot())
        searchResults.name = "A07-recording-search-keyboard"
        searchResults.lifetime = .keepAlways
        add(searchResults)
        search.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["studio-tab-1"].isHittable)
        XCTAssertTrue(app.buttons["Записать"].isHittable)
        XCTAssertEqual(app.buttons.matching(identifier: "recording-row").count, 1)
        app.buttons["Действия записи"].firstMatch.tap()
        app.buttons["Удалить запись"].tap()
        app.buttons["Удалить запись"].tap()
        XCTAssertTrue(app.staticTexts["Ничего не найдено"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "recording-row").count, 0)
    }

    @MainActor
    func testRecordingListGroupsDaysAndKeepsMenuReachableAtLargestTextSize() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_RECORDINGS_LAYOUT_FIXTURE"] == "1",
                          "Run with the two-day Simulator recording fixture.")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        app.launch()
        app.buttons["studio-tab-1"].tap()
        let rows = app.buttons.matching(identifier: "recording-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let calendar = Calendar.current
        let today = Date.now
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let format = Date.FormatStyle.dateTime.day().month(.wide).year().locale(Locale(identifier: "ru_RU"))
        let todayHeading = app.staticTexts[today.formatted(format)]
        let yesterdayHeading = app.staticTexts[yesterday.formatted(format)]
        XCTAssertTrue(todayHeading.exists)
        XCTAssertTrue(yesterdayHeading.exists)
        XCTAssertLessThan(todayHeading.frame.minY, yesterdayHeading.frame.minY)
        let normal = XCTAttachment(screenshot: app.screenshot())
        normal.name = "A07-recording-days"
        normal.lifetime = .keepAlways
        add(normal)

        app.terminate()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()
        app.buttons["studio-tab-1"].tap()
        XCTAssertTrue(todayHeading.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(todayHeading.frame.height, 30)
        let menu = app.buttons["Действия записи"].firstMatch
        XCTAssertTrue(menu.isHittable)
        XCTAssertGreaterThanOrEqual(menu.frame.width, 44)
        XCTAssertLessThan(menu.frame.maxY, app.buttons["Записать"].frame.minY)
        let largest = XCTAttachment(screenshot: app.screenshot())
        largest.name = "A07-recording-largest-text"
        largest.lifetime = .keepAlways
        add(largest)
    }

    @MainActor
    func testSimulatorCanVerifyRecordingFlowInApp() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
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
        let savedAudio = app.buttons["open-saved-audio"]
        XCTAssertTrue(savedAudio.waitForExistence(timeout: 5), app.debugDescription)
        let confirmation = XCTAttachment(screenshot: app.screenshot())
        confirmation.name = "A06-audio-saved"
        confirmation.lifetime = .keepAlways
        add(confirmation)
        savedAudio.tap()
        XCTAssertTrue(app.buttons["transcript-preview"].waitForExistence(timeout: 5))
        app.buttons["recording-details-back"].tap()
        app.buttons["studio-tab-1"].tap()

        let recordingRow = app.buttons.matching(identifier: "recording-row").firstMatch
        XCTAssertTrue(recordingRow.waitForExistence(timeout: 5), app.debugDescription)
        let recordButton = app.buttons["day-floating-record"]
        XCTAssertTrue(recordButton.isHittable)
        XCTAssertLessThan(recordButton.frame.midX, app.windows.firstMatch.frame.midX)
        let recordingsList = XCTAttachment(screenshot: app.screenshot())
        recordingsList.name = "A07-recordings-floating-record"
        recordingsList.lifetime = .keepAlways
        add(recordingsList)
        recordingRow.tap()
        XCTAssertTrue(app.buttons["transcript-preview"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Расшифровать"].exists)
        let editor = app.textViews["transcriptEditor"]
        XCTAssertFalse(editor.exists)
        app.buttons["Изменить текст"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse(app.sliders["Позиция аудио"].exists)
        editor.tap()
        let eventTitle = "Проверил отчёт \(UUID().uuidString.prefix(6))"
        editor.typeText(eventTitle + ".")
        let keyboardDone = app.buttons["transcript-keyboard-done"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5), app.debugDescription)
        let editorScreenshot = XCTAttachment(screenshot: app.screenshot())
        editorScreenshot.name = "A09-transcript-editor-keyboard"
        editorScreenshot.lifetime = .keepAlways
        add(editorScreenshot)
        keyboardDone.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["save-transcript"].tap()
        XCTAssertTrue(app.buttons["transcript-preview"].waitForExistence(timeout: 5))
        let detailsScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailsScreenshot.name = "A08-recording-details"
        detailsScreenshot.lifetime = .keepAlways
        add(detailsScreenshot)
        app.buttons["recording-details-back"].tap()
        app.buttons["studio-tab-0"].tap()
        let event = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", eventTitle)).firstMatch
        for _ in 0..<32 {
            if event.isHittable, event.frame.maxY < startRecording.frame.minY - 12 { break }
            app.scrollViews.firstMatch.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(event.isHittable, app.debugDescription)
        XCTAssertLessThan(event.frame.maxY, startRecording.frame.minY - 12)
        let audio = app.buttons["Открыть аудио: " + eventTitle]
        XCTAssertTrue(audio.isHittable)
        // Allow for floating-point error in the accessibility frame.
        XCTAssertGreaterThanOrEqual(audio.frame.width, 44 - 0.01)
        XCTAssertGreaterThanOrEqual(audio.frame.height, 44 - 0.01)
        audio.tap()
        let sourceText = app.buttons["transcript-preview"]
        XCTAssertTrue(sourceText.waitForExistence(timeout: 5))
        XCTAssertTrue(sourceText.label.contains(eventTitle))
        app.buttons["recording-details-back"].tap()
        XCTAssertTrue(sourceText.waitForNonExistence(timeout: 5))
        event.tap()
        XCTAssertTrue(app.buttons["edit-event"].waitForExistence(timeout: 5))
        app.buttons["Открыть аудиозапись и текст"].tap()
        XCTAssertTrue(app.staticTexts["source-transcript"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("This recorder-flow check is for Simulator; Action Button end-to-end is covered by the device test.")
        #endif
    }

    @MainActor
    func testSettingsShowsVersionAndActionButtonGuide() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.weeklywins.app")
        let largestText = ProcessInfo.processInfo.environment["RUN_SETTINGS_LAYOUT_FIXTURE"] == "1"
        if largestText {
            app.launchArguments = [
                "-UIPreferredContentSizeCategoryName",
                UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
            ]
        }
        app.launch()
        let settings = app.buttons["settings-button"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let build = app.descendants(matching: .any)["settings-build"].firstMatch
        if !largestText {
            XCTAssertTrue(app.staticTexts["Офлайн-распознавание"].exists)
        }
        for _ in 0..<12 where !build.isHittable { list.swipeUp() }
        XCTAssertTrue(build.isHittable, app.debugDescription)
        XCTAssertNotNil((build.value as? String).flatMap(Int.init))
        let settingsScreenshot = XCTAttachment(screenshot: app.screenshot())
        settingsScreenshot.name = largestText ? "A18-settings-largest-text" : "A18-settings"
        settingsScreenshot.lifetime = .keepAlways
        add(settingsScreenshot)
        let guide = app.buttons["Настроить кнопку действия"]
        for _ in 0..<12 where !guide.isHittable { list.swipeDown() }
        XCTAssertTrue(guide.isHittable, app.debugDescription)
        guide.tap()
        XCTAssertTrue(app.staticTexts["Первоначальная настройка"].waitForExistence(timeout: 5))
        let guideScreenshot = XCTAttachment(screenshot: app.screenshot())
        guideScreenshot.name = "A18-action-button-guide"
        guideScreenshot.lifetime = .keepAlways
        add(guideScreenshot)
        #if targetEnvironment(simulator)
        app.buttons["Сделать пробную запись"].tap()
        let stop = app.buttons["recorder-stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        stop.tap()
        XCTAssertTrue(app.navigationBars["Кнопка действия"].waitForExistence(timeout: 5))
        if largestText {
            app.terminate()
            app.launch()
            app.buttons["Выбрать день"].tap()
            XCTAssertTrue(app.navigationBars["Выбор даты"].waitForExistence(timeout: 5))
            let done = app.buttons["Готово"]
            XCTAssertTrue(done.isHittable)
            let calendar = app.datePickers["Дата"]
            XCTAssertTrue(calendar.waitForExistence(timeout: 5))
            let calendarScreenshot = XCTAttachment(screenshot: app.screenshot())
            calendarScreenshot.name = "A16-calendar-largest-text"
            calendarScreenshot.lifetime = .keepAlways
            add(calendarScreenshot)
            done.tap()
        }
        #endif
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
    private func openRecordingsAfterSaving(_ app: XCUIApplication) {
        let tab = app.buttons["studio-tab-1"]
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: tab
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed, app.debugDescription)
        tab.tap()
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
