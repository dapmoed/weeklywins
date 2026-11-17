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

## Simulator OS dispatch revalidation, build 17

On 2026-11-17, a dedicated iPhone 16 Pro Simulator running iOS 26.5 (`31B6F161-6E54-4D66-8709-B7C790547F52`, named WeeklyWins Shortcuts QA) successfully ran the actual Action Button start/stop path. A saved single-action shortcut invokes WeeklyWins' existing ToggleRecordingIntent. Its action's `Показать при запуске` switch is disabled. Settings assigns this saved shortcut to the Action Button.

With that switch enabled, Shortcuts displays the returned `Запись началась` dialog and waits for Done. The command remains running. A subsequent shortcut-card tap can cancel the running command instead of invoking the recording toggle again. The screenshot at `shots/simulator-shortcuts-result-waits-for-done.png` captures the dialog and the running editor. XCTest's accessibility tree exposes both play and stop during this state, so existence of the play button alone is insufficient. The switch exposes a whole-row frame, and tapping its right-hand control is needed to toggle it reliably. The fixture asserts value `0` before proceeding.

The focused Action Button UI test uses Home before each of two Action Button presses, activating WeeklyWins between them to verify recording state. It then opens the saved audio and verifies playback reaches the Pause state. The run passed at `/private/tmp/weeklywins-action-background-no-dialog.log`. Manifest ID-set comparison before and after this isolated run found exactly one new recording, `CC6ABF8B-9C49-42C6-85CE-D0F88F1E7599`, state `saved`, duration 6.588 seconds. Both intent calls use PID 46191. The durable journal contains start, Live Activity creation, successful intent completion, the second intent entry, and one recorder stop. ffprobe identifies AAC, 16 kHz, mono, container duration 6.72 seconds. ffmpeg decoded the complete file with exit status 0.

A separate saved-shortcut editor regression passed at `/private/tmp/weeklywins-saved-editor-show-off.log`. It runs the action twice through Shortcuts' play control and verifies active and idle app states. Test setup creates the saved shortcut when needed and disables its result dialog. The direct automatic App Shortcut card remains a separate Simulator limitation from the build 17 probes. The system Action Button test now runs on Simulator.

These runs cover foreground observation and background capture through the actual Simulator OS route. Locked-device, restart, call/route interruption, long Russian ASR and airplane-mode acceptance remain governed by the physical-device checks above. No physical-device installation occurred during this stage.

The hardware regression also identifies recordings by UUID through a technical accessibility identifier on the existing recording title. It remembers the previous newest identity, requires a different identity after stop, relaunches WeeklyWins, reopens that exact saved identity and verifies playback. The missing-identifier test failed at `/private/tmp/weeklywins-action-identity-red.log` and passed after adding the identifier at `/private/tmp/weeklywins-action-identity-green.log`. This prevents playback of an older recording from satisfying the check. The isolated manifest comparison above supplies the exact one-new-file count for the measured run.

For local repetition, use the dedicated Russian-language Simulator and normal Simulator ad-hoc signing. The fixture can create its saved shortcut through Shortcuts. Native microphone permission must be granted to WeeklyWins before background use. The fixture explicitly configures the saved action's result switch and the Simulator's Action Button. Its setup is limited to Simulator. The physical Action Button test uses the phone's existing assignment.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project WeeklyWins.xcodeproj -scheme WeeklyWins \
  -destination 'platform=iOS Simulator,id=31B6F161-6E54-4D66-8709-B7C790547F52' \
  -derivedDataPath /private/tmp/weeklywins-derived \
  CODE_SIGNING_ALLOWED=YES -parallel-testing-enabled NO \
  -only-testing:WeeklyWinsActionButtonUITests/ActionButtonUITests/testActionButtonStartsAndStopsRecording test
```

The final full suite passed 76 tests, skipped 3 and failed 0, with 79 total tests in the xcresult summary at `/tmp/weeklywins-derived/Logs/Test/Test-WeeklyWins-2026.11.17_17-31-59-+0500.xcresult`. The log is `/private/tmp/weeklywins-simulator-shortcuts-identity-final.log`. Remaining skips cover the direct App Shortcut card, populated-installation onboarding and the unavailable-ASR case on a runtime advertising legacy recognition support. Sol reviewed the final diff and found no remaining substantial issues.
