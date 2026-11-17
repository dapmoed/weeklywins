# Action Button and Simulator validation

Updated 2026-11-17

## Devices and builds

- iPhone 16 Pro, iOS 27.2.1, UDID `540CA7E2-ACAE-5E2D-9D47-1E4AF7762E68`. A read-only devicectl check on 2026-11-17 confirmed it is connected/paired and has WeeklyWins `0.1.0 (15)` installed.
- iPhone 17 Pro Simulator, iOS 26.5, UDID `01FDA22D-80AB-4612-B93C-C63DFD9ABBAB`. Simulator tests build `0.1.0 (17)`.
- Xcode 26.6; prefix Xcode CLI calls with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Build 10 also succeeds for `generic/platform=iOS` with automatic signing. It is available at `/private/tmp/weeklywins-device-derived/Build/Products/Debug-iphoneos/WeeklyWins.app`, but is not installed on the disconnected phone.

## Current recording implementation

- `ToggleRecordingIntent` conforms to `AudioRecordingIntent` and `LiveActivityIntent`; `WeeklyWinsShortcuts` publishes `Запись`.
- `Recording` stores a UUID, local recording timestamp, optional duration, audio filename, capture state, processing state, and error.
- `RecordingStore` writes a JSON manifest atomically. Active captures use `.partial.m4a`; stop closes the recorder, renames the media file, and saves the final state. On relaunch it migrates legacy recordings and recovers unfinished records without deleting their partial audio.
- UI and intent call the same `RecordingService`. It serializes concurrent starts, makes stop idempotent, enforces the configured maximum duration, and finalizes interruption state.
- XcodeGen source `project.yml` stores build number, `CODE_SIGN_STYLE: Automatic`, and team ID. Regenerating the project preserves signing.

## Simulator verification

- Full `xcodebuild test` on iPhone 17 Pro Simulator: **13 passed, 2 skipped, 0 failed**.
- Seven `RecordingTests` pass: legacy import, partial-file recovery, finalization conflict preservation, automatic stop (short test duration), repeated stop, concurrent starts, and interruption finalization.
- These recording tests exercise app-owned persistence and service behavior in Simulator; they do not simulate five minutes of wall-clock time or a physical call interruption.
- Other passing tests cover `AudioRecordingIntent` conformance, direct in-process intent start/stop, recording-library ordering, the in-app recording UI, and Action Button/shortcut discoverability.
- XCTest confirms the Simulator has an Action Button and can navigate Settings → `Кнопка действия` → `Быстрая команда`; the picker lists `WeeklyWins → Запись`.
- The system picker reports `Не удается запустить быструю команду приложения`, and a simulated Action Button press did not change recording state. The two system-dispatch UI tests are skipped with this exact limitation as the reason. This does not invalidate the passing direct intent/service tests.
- Screenshot: `shots/action-button-simulator-shortcut-dispatch-failed.png`.

## Physical-device evidence

- On build 8, a locked/background Action Button call reached `RecordingService` but `AVAudioSession.setActive(true)` failed with `NSOSStatusErrorDomain` code `560557684` (`cannotInterruptOthers`) before the recorder started. Screenshot: `shots/action-button-background-audio-session-failed.png`.
- Build 9 with `AudioRecordingIntent` was installed on the iPhone but not tested before it disconnected. Build 10 has since been signed successfully and is ready to install when the phone reconnects.
- Apple's definition of `cannotInterruptOthers`: [AVAudioSession error code](https://developer.apple.com/documentation/coreaudiotypes/avaudiosession/errorcode/cannotinterruptothers). For `AudioRecordingIntent`, Apple requires a Live Activity for the duration of capture: [AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent).

## Remaining acceptance

Continue Tasks 3–5 with Simulator coverage while the iPhone is unavailable. Task 1's locked-screen Action Button acceptance and Task 2's physical background/recovery check remain open: on build 10, verify one playable recording from two locked presses and confirm interrupted captures are retained; collect Console markers for `perform entered`, session activation, recorder start, stop, and recovery.

## Physical diagnostic follow-up, 2026-11-16

The iPhone reconnected and builds 10–13 were installed through `devicectl`. The user confirmed that new files from build 10 were created with the in-app button. Locked Action Button attempts on build 11 reached `perform()`, had microphone permission, and failed session activation with OSStatus 560557684.

Build 12 changed the audio category to `.playAndRecord` with `.mixWithOthers`. Its durable diagnostic journal confirmed audio session activation and recorder start on locked Action Button invocation. Each invocation then terminated with an AppIntents assertion (`EXC_BREAKPOINT`, `_assertionFailure`, first framework frames in AppIntents). The second invocation had a different PID. Crash report examined locally at `/private/tmp/weeklywins-crash12.ips`.

Build 13 declares `some IntentResult & ProvidesDialog` for `perform()`, matching its returned dialog. It also journals Live Activity failures. Signed build and installation succeeded. A repeated physical two-press check is pending from the user. The locked recording acceptance is still open.

## Successful physical two-press run on build 14

The user reported success while the phone was locked. Durable diagnostic markers confirm the same process PID 8166 handled start at 22:44:33 local time, started the recorder and Live Activity, returned from the intent, and handled stop at 22:44:44. The persisted recording `14C0BDB3-EE95-4912-9248-C36DD224283F` has state `saved`, duration 10.528125 seconds, and no error. Audio playback and the longer acceptance scenarios remain to be checked.

The working action conforms to both `AudioRecordingIntent` and `LiveActivityIntent`. Audio category is `.playAndRecord` with `.mixWithOthers`, and the result declares `ProvidesDialog`. Build 13 diagnostics showed Live Activity authorization code 7 from background followed by an AppIntents assertion. Adding `LiveActivityIntent` allowed the Live Activity to start and the process to retain the active recording across both invocations. Unit tests passed on build 14.

## Current acceptance summary, 2026-11-17

The short locked two-press recording flow is confirmed by the build 14 evidence above. Source build 16 adds the selected dimensional Echo C icon and later UI/data improvements. The connected physical phone still has build 15, verified through devicectl device info apps filtered to com.weeklywins.app. No physical installation occurred during icon or duration work.

The latest full Simulator regression passed 52 tests, skipped 3 and failed 0 at /private/tmp/weeklywins-duration-final.log. Two skipped cases concern OS Shortcut/Action Button dispatch, and one requires fresh-install onboarding. Long physical recordings, offline ASR accuracy, playback listening, restart/force-quit and call/route interruption acceptance remain open.

## Build 17 automatic-queue verification

Full regression on a dedicated iPhone16Pro Simulator, iOS26.5, passed 74 tests with 4 skipped and 0 failures. The skipped cases cover OS Action Button/Shortcut dispatch, fresh-install onboarding on a populated installation, and the unavailable-ASR UI scenario when the runtime advertises legacy on-device support. A separate saved-error UI case verifies that the error row opens the audio/transcript source. The queue, expiration and resumption success paths use deterministic test providers.

Native Simulator recognition currently advertises legacy local support and reports SpeechFramework backend failures in actual attempts. This supplies error-handling evidence. Physical Russian accuracy and long/background acceptance remain open. The OS shortcut-dispatch skips originated during earlier builds, so recheck them against the current AudioRecordingIntent plus LiveActivityIntent implementation before treating that limitation as current.
