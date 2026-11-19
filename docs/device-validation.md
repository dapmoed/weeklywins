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

## Build 18 automatic-stop presentation

The full recorder now closes after a successful saved capture, including the native duration limit and an external stop. RecordingService publishes completedRecordingID after successful saved-state finalization and clears it before a new capture. The view observes this typed outcome. A finalization error keeps the recorder visible with its error message and preserved partial audio. The stop control delegates to the service. The root opens the recorder after a successful start, including the onboarding trial path.

A hosted UIKit/SwiftUI test reproduced the stuck recorder after an injected short duration before the change. A second regression verifies the finalization-conflict error and partial-file retention, including a previous successful capture followed by a new one. The reset assertion was observed failing when the reset was removed. Unit tests use a scripted transcriber to isolate recorder presentation. Focused evidence is in /private/tmp/weeklywins-recorder-dismiss-red-confirmed.log, /private/tmp/weeklywins-recorder-stale-completion-red.log and /private/tmp/weeklywins-recorder-dismiss-unit-final.log.

The real five-minute UI check ran with the production 300-second limit. It passed in 310.874 seconds and returned to the timeline automatically. Recording AD5F4E35-0FE5-4985-81D4-D83F684D0522 is saved, with duration 299.9 seconds in the manifest. Its AAC 16 kHz mono container has duration 300.032 seconds and decodes fully through ffmpeg. Native Simulator ASR reported its existing backend failure and retained the audio. This capture supplies duration, finalization, presentation and audio-retention evidence. Russian recognition quality and airplane-mode acceptance still require the device corpus.

The full run including this long check passed 79 tests, skipped 3 and failed 0, total 82, at /private/tmp/weeklywins-recorder-five-minute-full.log, xcresult Test-WeeklyWins-2026.11.17_17-48-06-+0500. After the final A05 visual corrections and the largest-text regression, the final ordinary suite passed 79 tests, skipped 4 and failed 0, total 83, at /private/tmp/weeklywins-recorder-build18-clean-final.log, xcresult Test-WeeklyWins-2026.11.17_18-12-48-+0500. The ordinary run skips the opt-in five-minute case, direct App Shortcut card, populated-install onboarding and the unavailable-ASR case on a runtime advertising legacy support.

Enable the long check explicitly when repeating wall-clock acceptance.

```sh
TEST_RUNNER_RUN_LONG_CAPTURE_TEST=1 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project WeeklyWins.xcodeproj -scheme WeeklyWins \
  -destination 'platform=iOS Simulator,id=31B6F161-6E54-4D66-8709-B7C790547F52' \
  -derivedDataPath /private/tmp/weeklywins-derived \
  CODE_SIGNING_ALLOWED=YES -parallel-testing-enabled NO \
  -only-testing:WeeklyWinsActionButtonUITests/ActionButtonUITests/testFiveMinuteAutomaticStopReturnsToTimeline test
```

The largest-text UI case supplies the UIKit accessibility XXXL category as a process argument, asserts its actual effect on text geometry and verifies reachable collapse/stop controls. The following tests launch with their ordinary arguments. Screenshots and visual-comparison notes are in docs/design/verification/README.md. Sol reviewed the implementation and both actual A05 screenshots and found no substantial issues.

Before the final ordinary run, generated recordings on WeeklyWins Shortcuts QA were backed up to /private/tmp/weeklywins-qa18-before-final-regression and its Documents directory was reset. This backup includes the measured five-minute file and manifest. The other Simulator data and the physical phone were preserved. WeeklyWins Shortcuts QA is the only booted Simulator. No physical build was installed in this stage.

## Build 22 with the long Russian event parser

The signed build was installed on the physical iPhone 16 Pro and CoreDevice reported bundle version 22. A baseline of recording identities was saved locally before installation. The physical offline locked-screen check requires the owner to speak, hold the Action Button twice and report any unlock prompt. The diagnostic journal and new saved recording can be compared against the baseline after reconnection.

On the iPhone 16 Pro Simulator, the full build 22 run passed 114 cases, skipped 8 and failed 0. The real Simulator Action Button test passed in 58.955 seconds. It exercised background start and stop, retained the new recording through relaunch and played that exact source. The separate in-app flow saved a manually entered transcript and opened the resulting card from Today. The full run is in /private/tmp/weeklywins-build22-full.log.

The focused report suite passed all seven checks at /private/tmp/weeklywins-report22.log. Its new persistent-store integration covers day, week and month with different expected event ranges. After a category and duration edit, a second event's deletion and a store reload, the three totals changed to 30, 40 and 45 minutes respectively. The test verifies the query results after save and reload. A live view edit across all tabs and visual readability on the physical phone remain separate checks.

## Edit a Today item and delete it from a report

A focused build 22 Simulator UI test created a recording and saved two uniquely named tasks through the transcript editor. It opened the weekly report, went back to Today, edited one task through its detail screen and saved category Home with a one-minute duration. The changed card appeared in each of the day, week and month reports. The test deleted that card from the month report, returned to Today, found the neighboring task from the same recording and verified the deleted card was absent.

The focused run passed on the iPhone 16 Pro Simulator. Temporary test Documents were isolated and the original QA Documents were restored afterward. Log at /private/tmp/weeklywins-report-live-run4.log, result bundle Test-WeeklyWins-2026.11.18_10-46-35-+0500.xcresult. The scalar totals and separate date ranges are covered by the persistent report query tests above.

## Physical build 22 Action Button recording

After the user began the physical check on 18 November, the manifest contained one new saved recording with ID `FF14C484-FD14-41B6-BE19-6F6E70C9C974`. Its durable journal shows an intent entry at 06:13:37 UTC, audio session activation, recording and Live Activity start, and an intent return in the same second. PID 7184 handled both calls. The second entry at 06:14:33 UTC stopped the recorder. The saved duration was 56.124 s, with AAC mono audio at 16 kHz and a file duration of 56.256 s. FFmpeg decoded the entire file without errors. The transcript completed at 06:14:35 UTC with 49 words and one persisted event. The journal shows on-device legacy recognition of both audio windows. The user confirmed both holds were performed with the screen locked without unlocking between them, and that airplane mode with Wi-Fi off remained in effect until the text appeared. This satisfies the two-press locked-screen gate for a short, naturally spoken recording. The restart and maximum-duration result is documented below. Call and audio-route interruptions remain separate checks. The earlier five-minute offline fixture has its own verified network-path evidence. The audio and transcript of this natural recording remain local.


### Locked capture after force quit

On 18 November the owner confirmed that build 22 started and stopped recording from the locked iPhone after swiping WeeklyWins away in the app switcher. The durable journal shows a new app process (PID 7321) receiving the start intent at 07:02:04 UTC. It activated the audio session, started recording and began the Live Activity in the same logged second. The second intent at 07:02:17 UTC stopped recording in that process. On-device legacy recognition then processed the 12.22-second audio window and reported 20 words. The journal confirms the intent and audio path. The user's confirmation supplies the lock and force-quit conditions. Only the metadata journal was retrieved for this check.


### Five-minute locked capture after iPhone restart

On 18 November the owner confirmed that build 22 started recording from the locked iPhone after a reboot and one initial unlock, without opening WeeklyWins, and saved a 5:00 recording automatically. The journal shows one start intent at 07:12:51 UTC in PID 457. The recorder and Live Activity started at 07:12:52 UTC. The stop was logged at 07:17:54 UTC with no second intent entry. The manifest records 299.9 seconds of saved audio, completed transcription, 87 words and one event. The last two ASR windows reported no recognized speech. This run verifies capture and automatic finalization at the duration limit. The earlier airplane-mode recording and the controlled five-minute offline fixture supply the separate offline evidence.


## Build 23 Simulator regression

The app and Live Activity extension both report version 0.1.0, build 23. The generated project and XcodeGen source agree. The physical iPhone was not updated from build 22 for this check.

On the iPhone 16 Pro Simulator with iOS 26.5, the final ordinary run passed 116 cases, skipped 11 and failed 0. The system Action Button started and stopped capture, and the test opened and played the saved audio after relaunch. The full suite also verified recording, draft recovery, event editing and all three reports. The simulator's original Documents were restored after the run. Full log at /private/tmp/weeklywins-build23-release.log.

The populated report and clean-onboarding trials, plus the maximum-size calendar and settings trial, passed separately. The ordinary suite skips scenarios that require opt-in fixtures, a physical device or the wall-clock five-minute run. See [design verification](design/verification/README.md) for the actual Simulator screenshots. The owner's physical call-interruption test is deferred.

### Interruption and the next recording

On iPhone 16 Pro Simulator with iOS 26.5, the recording service received a synthetic audio-session interruption while capturing through the same toggle used by the Action Button intent. Reopening the store found one interrupted recording and AVAudioFile decoded its saved audio. A duplicate interruption added no recording. The next toggle started a new capture, which saved separately and left the interrupted audio intact. The physical call or route-change check requires an actual device interruption.

### Timing available for the physical Action Button checks

The build 22 checks used the iPhone 16 Pro on iOS 27.2.1. The ordinary and force-quit runs logged intent entry and capture start in the same UTC second. After reboot, intent entry was logged at 07:12:51 UTC and capture at 07:12:52 UTC. The journal has whole-second resolution and starts at intent entry. The time of the physical hold was not recorded, so these timestamps do not measure hold-to-capture latency.

### Five-minute automatic stop on build 23

The opt-in `testFiveMinuteAutomaticStopReturnsToTimeline` passed in 308.135 seconds on iPhone 16 Pro Simulator with iOS 26.5. The UI returned from the recorder automatically and showed 5:00 in the recording list. The isolated manifest contained one saved entry, `CCF76BC4-0FE9-410D-B885-734ED90A1D8C`, with duration 299.9 seconds. FFprobe measured 300.032 seconds of 16 kHz mono AAC and FFmpeg decoded the file to completion. Simulator transcription reported “Failed to initialize recognizer”, and the saved audio remained available. The original Simulator data was restored. Log at /private/tmp/weeklywins-build23-five-minute.log. The continuous physical offline test remains tracked separately in the plan.

### Build 23 device package

Source revision `58679e9` built successfully in Debug for `generic/platform=iOS`. The application and embedded Live Activity extension are arm64 and both report version 0.1.0, build 23. The app declares background audio and Live Activity support. The bundle passed `codesign --verify --deep --strict`, and the development provisioning profiles for both targets included the connected iPhone 16 Pro and were valid through 22 November 2026.

The local package is at `/private/tmp/weeklywins-device23.4GqvCI/DerivedData/Build/Products/Debug-iphoneos/WeeklyWins.app`. A read-only app listing confirmed the phone was still running the installed build 22. This stage checked the package and provisioning. Physical behavior of build 23 remains unverified.

### Simulator regression after the event extraction changes

At revision `85ae026`, the unit suite passed 106 tests with 4 device-only skips and no failures. The system Action Button UI test passed separately in 60.462 seconds on iPhone 16 Pro Simulator. It verified two background button presses, a new recording identity, persistence across relaunch and playback of that recording. This run exercised the Simulator system shortcut, while physical locked-screen results remain documented under build 22. Log at /private/tmp/weeklywins-final-parser-action-button.log.

### Five-minute offline capture and transcription on iPhone

On 18 November, the owner confirmed a successful manual run on build 22, starting with one Action Button hold on the locked iPhone 16 Pro, airplane mode on and Wi-Fi off. The owner checked the 5:00 recording and the final phrase in its transcript before restoring connectivity. The radio conditions are from the owner's confirmation.

The device journal logged intent entry and capture start at 09:43:54 UTC and automatic stop at 09:48:56 UTC, with no intervening intent. The stored recording `7D8DC9DC-BC99-4AD6-8B37-F522CA2399C1` has 299.9 seconds of audio and completed transcription. The recognizer logged six on-device legacy windows through 09:49:04 UTC. The persisted text contains 596 word tokens and the expected final phrase near the end. Only metadata and diagnostic evidence are recorded here. Recognition accuracy was not scored for this run.

### Locked recording while music plays

The owner reported that build 22 failed to start a recording from the locked Action Button while music was playing. Two matching entries reached the intent with microphone permission granted and an active audio session, then returned `WeeklyWins.RecordingError` code 1 before recording and Live Activity startup. An intervening attempt started, saved and transcribed a 29-second recording. Build 22 used one error for both recorder preparation and start, so those failures could not be distinguished from its journal.

Build 24 logs the active input/output port types, sample rate, input channel count, presence of other audio and the results of preparation and start separately. The iPhone 16 Pro Simulator passed all 11 recording unit tests and the system Action Button test with this build.

The owner repeated the locked test on build 24 with Bluetooth music playback and reported that music paused and the recording started. At 11:42:27 UTC, the activated session saw other audio playing and reported built-in microphone input, receiver output, one input channel and 48 kHz. Both preparation and start succeeded. The second Action Button hold stopped the recorder. The resulting 8.828-second recording was saved and transcribed. Build 24 remains installed. This is one successful repeat after the earlier build 22 failures. Their underlying cause remains undetermined.

A subsequent build 24 failure logged `otherAudio=true` and the same built-in microphone/receiver route. The recorder returned `prepared=true` followed by `accepted start=false`. The next capture in the same process and on the same route started with `otherAudio=false` and saved 19 seconds. The failing path is therefore the recorder start after successful audio session activation and preparation.

Build 25 allows A2DP output while preserving the mixable play-and-record session. This lets iOS keep Bluetooth music output available without requesting a Bluetooth headset microphone. The simulator regression proves the Action Button configures both mixing and A2DP options. The signed arm64 build 25 was installed on the physical iPhone for the Bluetooth repeat. A route change and successful repeated capture on the device remain to be verified.

#### Build 25 repeat and the system Pause experiment

On iOS 27.2.1, the owner's repeat with Bluetooth headphones reached the intent at 16:01:01 UTC. The session activated with `MicrophoneBuiltIn` / `BluetoothA2DPOutput`, 48 kHz, one input channel, and `otherAudio=true`. Preparation succeeded and `record(forDuration:)` returned false again. A2DP selection alone did not resolve the failure. A subsequent two-second capture with `otherAudio=false` saved successfully. Its log does not establish how playback stopped.

The next experiment keeps build 25 and uses the system Shortcuts action «Воспроизведение/Пауза» in «Приостановить» mode on iPhone, before WeeklyWins «Начать или остановить запись». An editable shortcut can be created with the plus button in Shortcuts. Search for `WeeklyWins` inside the new shortcut's action picker to find the recording action. Turn off «Показать при запуске» for that action, save the shortcut, and select it in the Action Button settings.

On the iPhone 16 Pro Simulator with iOS 26.5, a copy of the shortcut used this order and two editor runs started and stopped WeeklyWins, saving a 17.916-second recording. No music was playing on that simulator. The physical locked run with Bluetooth media playing before the shortcut is still required to test whether system Pause restores capture.

The tested two-action shortcut is also available as a signed `WeeklyWins-Pause.shortcut` file at `/private/tmp/weeklywins-shortcut.LVUkeJ/WeeklyWins-Pause.shortcut`. Apple Shortcuts accepted the file on iOS 26.5 Simulator. The imported editor showed «Приостановить на iPhone» first, «Начать или остановить запись» second and «Показать при запуске» disabled. Import and the locked Bluetooth test on iOS 27.2.1 still require the owner's phone.

The owner created and assigned the two-action shortcut on the physical iPhone running iOS 27.2.1. They confirmed that the shortcut paused Bluetooth music and that a second Action Button hold saved the recording. On build 25 at 16:27:16 UTC, the journal showed an A2DP output, the built-in microphone and `otherAudio=false` at recorder start. A second intent at 16:27:23 UTC stopped it. Recording `927397DF-C159-4AF5-BFE9-3F0FFB6F2A8A` contains 6.524 seconds of audio, decoded through EOF, with completed transcription. This confirms one successful physical run of the Pause workaround. An earlier attempt at 16:25:48 UTC failed to activate the audio session with `NSOSStatusErrorDomain` code 561015905 (`!pla`). The exact shortcut setup at that earlier attempt was not established.

#### Retry after intermittent start rejection

Additional owner tests on build 25 showed intermittent failure and early completion with the screen locked. The journal contained separate activation refusals with `!pla` and recorder-start refusals with `otherAudio=false`, including with A2DP and with receiver output. It also contained one 6.78-second recording that stopped without a second intent. The previous journal does not identify which system callback ended that capture.

Build 26 makes at most one retry after 600 ms for the documented activation error or a false start from a prepared recorder. A recorder retry creates a new recorder for the same recording file and entry. The build logs session interruption, recorder completion and timer expiry separately. It was installed on the physical iPhone for a repeat. The simulator passed the recording suite and the system Action Button test. Physical repeatability and the source of early completion remain to be verified.

On the physical iPhone, build 26 saved three short Bluetooth runs after the system Pause action. The two explicitly confirmed locked runs saved 4.732 and 3.708 seconds, decoded fully, and completed transcription. Both started on the first attempt. Later in the same series, two launches with A2DP output and `otherAudio=false` returned false at both recorder-start attempts, and a third returned `!pla` at both activation attempts. This rules out treating the bounded retry as a reliable fix.

#### Request Live Activity before background audio

Build 27 requests the Live Activity with a preparing state before activating the audio session in the background. It updates the state after the recorder accepts capture and ends the activity on startup failure. Foreground order, the mixable A2DP options, recorder format, duration limit and retry budget are retained. This tests the ordering separately from recorder or route changes. [Apple's AudioRecordingIntent contract](https://developer.apple.com/documentation/AppIntents/AudioRecordingIntent).

The ordering assertion failed on build 26 and passed with build 27. On iPhone 16 Pro Simulator, all 20 focused unit tests and the system Action Button UI test passed. The signed arm64 build was installed on the real iPhone for the same locked Bluetooth test with the existing Pause shortcut. The transient preparing label has not been captured on the Lock Screen. Physical startup and failure cleanup still need an observed result.

The owner's locked build 27 attempt reached the intent at 16:45:48 UTC. The journal shows the preparing Live Activity started, then both audio-session activation attempts returned `NSOSStatusErrorDomain` code 561015905 (`!pla`). Capture did not reach recorder preparation. The ordering change did not eliminate the activation failure. The next comparison uses the same build and shortcut with Bluetooth switched off, to separate the route from the locked startup context.

#### Background audio route comparison

With Bluetooth switched off in Settings, the owner repeated the same command from the Lock Screen on build 27. The journal shows a built-in microphone and receiver route, a start at 16:47:35 UTC, a second intent to stop at 16:47:41 UTC and successful transcription. Recording `29B65286-6A67-4791-ABC1-14CD239DBEDE` was persisted with a duration of 5.5 seconds. This control suggests a route-dependent issue. It does not establish that removing a session option is equivalent to switching off Bluetooth in Settings.

Build 28 omits `allowBluetoothA2DP` for background recording only, preserves mixing and the start order from build 27, and leaves foreground options intact. The simulator background-options regression failed with build 27 and passed with this change. All 20 focused unit tests and the system Action Button UI test passed. The signed arm64 build was installed on the iPhone. The acceptance comparison keeps Bluetooth enabled on the phone, with the same connected headphones, playback and Pause shortcut. The journal will show the actual route selected for capture.

Build 28 selected the receiver and built-in microphone after the music paused. The physical series still included false recorder starts, an activation failure and a separate 8.188-second successful recording. With iPhone Console streaming over USB, a further locked repeat failed at 16:57:07–08 UTC. Console tied the failure to WeeklyWins' input audio queue. iOS logged that the mixable `PlayAndRecord/Default` session lacked an assertion to start mixable playback, and `AudioSessionSetClientPlayState` returned 2003329396 (`what`). The audio session had activated and the input queue and converter had been created. The issue occurred when starting that queue.

#### Input-only background capture

Build 29 requests the public input-only `.record` category in the background. Foreground capture still uses mixable `.playAndRecord` with A2DP. The existing short startup retry, early Live Activity, recorder format and 300-second limit are retained. The locked physical comparison uses the same Pause shortcut. It must verify that iOS authorizes the nonmixable input session and that both Action Button presses work.

The category regression failed on build 28 and passed on build 29. The simulator run passed 20 focused unit tests and the system Action Button start/stop/playback test. The signed arm64 build 29 was installed on the connected iPhone for the physical comparison.

The owner's build 29 repeat reached the intent at 17:05:31 UTC with permission granted. It started the preparing Live Activity and configured `.record`, but iOS rejected activation with 560557684 (`cannotInterruptOthers`). The recorder was never reached. The foreground path and five-minute behavior had not been changed, but the physical result rejects this background category as a fix for the Bluetooth scenario.

Build 30 restores the mixable audio configuration from build 28 and has been installed on the iPhone. The two device traces show different policy failures with the two configurations. The Bluetooth failure remains unresolved. The previously confirmed Bluetooth-off capture remains documented above.

The signed build 30 bundle's generated App Intents metadata lists `ToggleRecordingIntent` as discoverable with background support, `openAppWhenRun=false`, and both system protocols `AudioRecording` and `SessionStarting`. The action was exported as intended. The metadata does not prove that iOS grants the live audio assertion for a particular shortcut execution. The next physical comparison is the direct WeeklyWins action after manually pausing music, with Bluetooth headphones still connected.

### Physical interruption and the next recording on build 25

During the owner's manual interruption test, the device journal logged a successful Action Button start at 15:39:45 UTC and a stop at 15:40:06 UTC without a second intent. Recording `BF804577-66BB-4414-849A-B4DE5E7EA509` is persisted as interrupted with 21.18 seconds of audio and completed transcription.

The next intent at 15:41:22 UTC started a separate recording. An intent at 15:41:30 UTC stopped it, saving `136CF00F-3F1E-4221-AA0E-D99F4FA14D69` with 7.548 seconds and completed transcription. FFmpeg decoded both saved files through EOF without errors. The owner confirmed that an incoming phone call interrupted the first capture and that the next capture started via the Action Button with the screen locked.
