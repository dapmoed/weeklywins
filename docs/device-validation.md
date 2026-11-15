# Action Button validation

Updated: 2026-11-15

## Devices and builds

- Physical iPhone 16 Pro (iPhone17,1), iOS 27.2 (24B119), Developer Mode enabled.
- iOS Simulator iPhone 17 Pro, iOS 26.5, UDID `01FDA22D-80AB-4612-B93C-C63DFD9ABBAB`.
- Xcode 26.6; CLI requires `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Latest app version/build: `0.1.0 (build 8)`.

## Current implementation

- Start/stop recording through a regular background `AppIntent` and an `AppShortcutsProvider` shortcut titled `Запись`.
- Microphone permission is requested before activating `AVAudioSession`.
- The recording screen displays version/build; capture writes AAC to the app container, has a 5-minute cap, and updates a Live Activity.
- App Intent and session activation emit OSLog messages. Build 8 logs the execution mode/PID, permission result, category activation, recorder start, Live Activity start, and NSError domain/code/underlying code.
- XcodeGen source is `project.yml`; regenerate with `xcodegen generate`.
- The shared `WeeklyWins` scheme now explicitly runs and profiles `WeeklyWins.app`; the RecordingActivityExtension remains embedded, not launched directly.

## Evidence

- In-app recording in Simulator starts an AAC input queue and an ActivityKit Live Activity.
- The physical app Documents container contained 11 `recording-*.m4a` files (filenames/metadata only; audio contents were not read), so prior attempts did create files even though the app UI had no recording history.
- Build 8 adds a `Записи` list with local recording date/time and duration; Simulator screenshot verified existing test recordings are visible. The phone currently has build 7, so install build 8 to see this UI there.
- The direct in-process test invokes the intent twice and verifies recording starts then stops: 1 test passed.
- The Shortcuts app displays the `WeeklyWins → Запись` tile. Tapping it in the iOS 26.5 Simulator shows `Не удается запустить быструю команду приложения`; `RecordingIntent.perform()` does not log `perform entered`.
- XCUITest confirmed the Simulator Action Button setting currently reads `Без действия`; the Action Button was not assigned in that simulator test.
- Repeated XCUITest swipes reached only `Без действия`, `Элементы управления`, and `Бесшумный режим`; the simulator settings did not expose `Команда` in that run.
- An XCUITest pressing `XCUIDevice.shared.press(.action)` does not launch the intent while the button is unassigned.
- The physical iPhone previously showed `Session activation failed` on the first and second press. The user now reports Action Button recording works only while WeeklyWins is active and the screen is unlocked; background/locked execution still fails. Build 7 is installed; build 8 has not yet been installed.
- The latest Xcode screenshot showed the selected run action trying to launch `RecordingActivityExtension.appex` directly (`Failed to show Widget`). The scheme now launches the containing `WeeklyWins.app`; Simulator launch shows the recording screen and version `0.1.0 (сборка 8)`.
- Simulator app metadata contains `ToggleRecordingIntent`, `autoShortcuts`, and provider name `WeeklyWinsShortcuts`. Xcode's training processor sometimes logs `No AppShortcuts found - Skipping`; runtime linkd update calls also failed in Simulator. These diagnostics have not established a project-side provider bug.
- A recent Apple Developer Forums report says Shortcuts and App Intents fail in iOS 26/27 simulators (FB23342158). This is a developer report, not an Apple-confirmed release-note issue. It supports treating the Simulator failure as a likely platform limitation, not a proven app defect.

## Test result

`xcodebuild test` on iOS 26.5 Simulator passes the direct recording test; two App Shortcut / Action Button UI tests are explicitly skipped on iOS 26/27 Simulator because system shortcut dispatch is unreliable there. Build 8 tests: 1 passed, 2 skipped, 0 failures. The skipped tests are intended to run on a physical iPhone.

## Sol consultation

Sol assessed the simulator evidence as consistent with a failure before `perform()`. The direct recording test establishes that the local capture path works; it does not establish App Shortcut registration or locked-screen execution. The Action Button assignment in Simulator was not set (Settings showed `Без действия`).

## Next step / blocker

No more product changes are justified until the physical-device path is diagnosed. Xcode CLI device signing still reports `No Account for Team 9U44QT57YP` and missing profiles, despite a screenshot showing the Personal Team selected in Xcode's signing UI. Build 7 is installed; build 8 with additional diagnostics must be installed through Xcode GUI. Run the `WeeklyWins` scheme (not the extension), then use Xcode's debug console to compare recording from the app UI with Action Button presses while unlocked and locked. Look for `perform entered`, `audio session activated`, and `recorder started`. Task 1 remains incomplete until two locked-screen presses create one playable recording without unlocking.
