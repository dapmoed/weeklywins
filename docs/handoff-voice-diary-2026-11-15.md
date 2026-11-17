# Handoff: WeeklyWins voice diary

Updated: 2026-11-16

## User goal

Build an iPhone 16 Pro app for Russian voice notes, recorded through the day in 1–5 minute chunks. The Action Button should start and stop recording on alternating presses, including while locked. The app stores recordings and timestamps, extracts mentioned tasks, supports `работа` / `дом` labels, and provides daily, weekly, and monthly reports. Processing is local by default; optional cloud text processing through a proxy requires a later quality decision and explicit opt-in. The recording screen displays app version/build.

## Workspace and signing

- Repository: `/Users/konstantin.brikalov/Projects/Обучение/AI/weeklywins`, branch `main`. Keep changes in this folder and preserve unrelated local edits.
- Design: `docs/superpowers/specs/2026-11-15-voice-daily-log-design.md`.
- Plan: `docs/superpowers/plans/2026-11-15-voice-daily-log.md`.
- `project.yml` is the XcodeGen source and now stores build `10`, `CODE_SIGN_STYLE: Automatic`, and the development team. `xcodegen generate` keeps signing settings.
- Xcode 26.6 requires `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for CLI commands.
- A signed `generic/platform=iOS` build 10 succeeded after regeneration. The phone was disconnected, so build 10 is not installed; the phone still has build 9.
- Simulator: iPhone 17 Pro, iOS 26.5, UDID `01FDA22D-80AB-4612-B93C-C63DFD9ABBAB`.
- iPhone: iPhone 16 Pro, iOS 27.2, UDID `540CA7E2-ACAE-5E2D-9D47-1E4AF7762E68`, currently disconnected.

## Task 1: Action Button feasibility

- `ToggleRecordingIntent` conforms to `AudioRecordingIntent`; the app publishes the `Запись` shortcut.
- A build-8 Console log on the physical iPhone showed `AVAudioSession.setActive(true)` failing in the background with `NSOSStatusErrorDomain` code `560557684` (`cannotInterruptOthers`) before recorder start. This led to the `AudioRecordingIntent` experiment; build 9 was installed but not physically retested.
- Simulator Settings exposes the Action Button and `Быстрая команда`; its picker lists `WeeklyWins → Запись`. Invoking the system shortcut produces `Не удается запустить быструю команду приложения`, and the simulated button did not start the app recording. Screenshot: `shots/action-button-simulator-shortcut-dispatch-failed.png`.
- Simulator does verify the in-process intent and recording behavior, but not the OS-level Action Button dispatch. The actual locked-screen acceptance remains open until a connected iPhone succeeds.

## Task 2: recording and persistence

- `Recording` stores UUID, start timestamp, duration, filename, capture state, processing state, and error.
- `RecordingStore` persists JSON atomically, imports recordings from build 8, writes active audio to a partial filename, finalizes by renaming after recorder stop, and preserves partial files as interrupted records after relaunch.
- `RecordingService` uses the same store from UI and intent, guards concurrent starts, makes stop idempotent, stops at the configured duration, handles audio interruption notifications, and surfaces interrupted/error state in the recordings list.
- Task 2 focused Simulator tests: 7 passed. Full Simulator suite on build 10: **13 passed, 2 skipped, 0 failed**. The two skips are OS-level Shortcut/Action Button dispatch tests.
- Sol reviewed Task 2: no definite critical flaw; specifically checked pending-manifest-before-capture, partial-file preservation on rename failure, and recovery if the manifest write fails after media rename.
- Physical locked/background recording validation is still pending because the phone is disconnected.

## Current simulator test boundary

- `RecordingServiceTests` covers intent conformance, direct in-process intent start/stop, and legacy library ordering.
- `RecordingTests` covers migration, interruption finalization, recovery without deleting audio, finalization conflicts, maximum duration, duplicate stop, and concurrent start requests.
- `ActionButtonUITests` covers the app's in-app recording flow and Action Button/shortcut discoverability. System dispatch tests skip on Simulator because the system returns the observed generic error.
- Test command:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -project WeeklyWins.xcodeproj -scheme WeeklyWins \
    -destination 'platform=iOS Simulator,id=01FDA22D-80AB-4612-B93C-C63DFD9ABBAB' \
    -derivedDataPath /private/tmp/weeklywins-derived \
    CODE_SIGNING_ALLOWED=NO test
  ```

## Next plan work

Continue Task 3 with Simulator-supported checks: probe `SpeechTranscriber`/Russian availability and build a replaceable offline transcription interface, while recording that Russian accuracy, throughput, and battery still need physical-device measurements. Then proceed through event extraction and reporting using fixtures and Simulator tests. Do not claim Task 1's locked-screen acceptance complete without a physical iPhone run.

## Latest physical progress, build 14

The iPhone is connected. Locked Action Button start/stop succeeded on build 14 and the user confirmed it works. Diagnostics show PID 8166 starting recorder and Live Activity at 22:44:33, then stopping from the second intent at 22:44:44. Manifest contains saved recording 14C0BDB3-EE95-4912-9248-C36DD224283F with duration 10.528125 seconds and no error. Audio playback, five-minute run, restart/force-quit/call cases still require acceptance.

Working changes include `.playAndRecord` with `.mixWithOthers`, conformance to both `AudioRecordingIntent` and `LiveActivityIntent`, and `some IntentResult & ProvidesDialog`. Prior build 13 activated audio and started recording, but Live Activity failed with authorization code 7 in background, then AppIntents asserted. Build 14 started Live Activity successfully. Durable metadata-only diagnostics live in Documents/recording-diagnostics.log.

Physical Speech probe succeeded after correcting an invalid test assumption that Russian must be offered by SpeechTranscriber. On iPhone 16 Pro iOS 27.2, SpeechTranscriber has no equivalent Russian locale, while SFSpeechRecognizer supportsOnDeviceRecognition=true for ru-RU. Existing provider falls back to SFSpeechRecognizer with requiresOnDeviceRecognition=true. User was asked to select a spoken recording and tap Расшифровать. Await this actual transcription result while continuing other plan work. Do not reinstall or start device tests while the user performs that manual check.

The user confirmed Russian transcription works on the iPhone. Next implement Tasks 4–5 through the normal transcript editing flow. Keep five-minute airplane-mode quality measurement and playback/extended Action Button acceptance open.

## Build 15 progress

Build 15 installed on the connected iPhone. Added persisted DiaryEvent values linked to recordings, local extraction after transcription or manual text save, editing of category/completion/time/duration, merge/delete/add, Today and day/week/month reports. Existing transcript records acquire event suggestions when their events field is missing. Existing manual event edits are retained on retranscription. Report durations sum completed events with known duration. Tests for event extraction and report queries pass. Latest full Simulator suite has 20 unit tests plus 2 UI tests passing, 2 system-dispatch UI tests skipped. Physical build succeeded.

Remaining work includes broader extraction fixtures and measured quality, report/edit UI acceptance on device, actual audio playback acceptance, five-minute airplane-mode transcription, extended Action Button restart/interruption tests, stronger persistence error handling and transcription cancellation review. Goal remains active. See docs/event-evaluation.md for current extractor limitations.

## Simulator implementation checkpoint, 2026-11-17

The user approved Voice Studio palette and layout A and requires exact adherence. Authoritative visual target is docs/design/layout-a-approved.png, with docs/design/approved-design.md and the A01–A18 screen specification. The user prefers Simulator verification and installations on iPhone only when technically needed. Commit and push each finished stage.

Implemented shared StudioTheme, StudioRootView with Today/Recordings/Reports navigation and persistent recording action, full-screen recorder with timer and actual microphone meter history, category-filtered timeline and calendar, and report charts. Added UILaunchScreen configuration to eliminate iOS compatibility letterboxing. Russian labels and explicit recording-time captions preserve time semantics. Current primary screen render was inspected with temporary synthetic Simulator-only data, then the original index was restored. Date localization and timeline chronological ordering were corrected afterward. Exact visual matching across all A01–A18 remains in progress, including settings/onboarding, event detail/source access, typography and spacing refinements, draft handling, and advanced report interactions. Do not claim design completion.

Reviewed and corrected recovery importing duplicate UUIDs after media rename, automatic recording finalization via AVAudioRecorderDelegate and finalized-file duration, event refresh after corrected transcript while retaining manual edits, ordinary negations and clock-time/duration confusion, and in-memory rollback for failed begin/transcript writes. Added playback with recording-start stopping playback. SpeechAnalyzer consumer cleanup now cancels on failure. Legacy speech task cancellation and broader ASR/extraction evaluations remain pending.

Full Simulator suite passed at /private/tmp/weeklywins-derived/Logs/Test/Test-WeeklyWins-2026.11.17_09-19-23-+0500.xcresult. Hardware acceptance retains confirmed build14 two-press locked start/stop and user-confirmed Russian transcription. Five-minute airplane-mode transcription, playback and longer interruption/restart cases still need physical acceptance. No new device install in this checkpoint.

## Event details and settings stage, 2026-11-17

Added EventDetailView with a live event lookup, source excerpt, original recording date, and navigation into audio/transcript. A dedicated editor changes one event against the latest recording snapshot, with shared store-level rejection of empty titles. Event deletion offers undo. EventDraftStore saves the editor draft on background transition and restores it when reopening; saving or explicit discard clears it.

Added SettingsView and ActionButtonGuideView in the approved dark palette. Entry buttons appear on Today, recordings and reports. Settings displays actual microphone/Speech authorization, Russian on-device engine availability, app version/build, system settings link, and Action Button assignment/testing instructions. Runtime capability is refreshed after returning from system Settings.

Static review identified empty-title save through the close dialog and missing persisted drafts. Both were fixed and regression tests added. Simulator UI tests exercised record→manual transcript→Today event→source transcript and settings→Action Button guide. Full Simulator suite passed at /private/tmp/weeklywins-source-settings-final.log. No physical-device installation in this stage.

Remaining approved UI work includes initial onboarding, all editor draft/close flows, search and recording deletion, playback scrubbing, detailed report day navigation, and exact spacing/screenshot comparison across A01–A18. Broader Russian extraction quality and hardware long-recording/airplane-mode acceptance remain open.

## Recording library stage, 2026-11-17

Added text/date search with Russian case/diacritic folding, grouping by local calendar day, explicit audio-duration labels, transcript snippets, processing states, and per-recording menus. Deleting requires confirmation that audio, transcript and linked events will be removed. Store persists a deletion marker and related draft IDs before deleting audio and drafts. Startup retries cleanup, so orphan audio cannot be reimported after interrupted deletion. Visible service collections, report queries, playback and transcription exclude deleted records. Recordings with active capture/processing cannot be deleted.

Review identified stale persisted .processing after termination and orphaned drafts when deletion is interrupted. Added startup recovery of abandoned processing to failed/retryable state and persisted deletion draft IDs for cleanup retry. Tests cover these cases, deletion/relaunch, busy capture, Russian text/date search. UI test records, saves a unique transcript, searches it and confirms deletion. Full Simulator suite passed at /private/tmp/weeklywins-management-final.log. No physical-device installation for this stage.

The deletion marker retains recording identity/file metadata plus draft UUIDs to avoid resurrection and support cleanup; audio, transcript, source events and error text are removed. The goal remains active with onboarding, transcript/multi-event draft flows, playback scrubber, report interactions, visual acceptance and long offline/hardware scenarios pending.

## Audio/transcript stage, 2026-11-17

Added pause/resume, live playback position/duration and bounded seeking to the original audio player. Capture start stops playback. Transcript screen uses approved studio surfaces, shows a player, persists even empty edited text as a per-recording draft, restores it on reopening, and requires save/discard/cancel when closing changed text. Events navigation with unsaved text offers explicit save-and-open or opening persisted events while retaining the draft. Replacement by a fresh ASR result requires confirmation when a draft exists.

Review found old ASR completion deleting newer drafts and implicit save during Events navigation. Fixed with shared service-level ASR ownership, disabled editing in reopened views while the job runs, conditional draft cleanup by owned text version, and explicit Events navigation choices. Deletion cleanup now removes transcript drafts both immediately and during startup retry. Playback polling exits when service disappears.

Simulator unit tests verify pause/seek/start behavior, persisted empty/nonempty drafts and old-job/new-draft ownership. UI test terminates/relaunches with a draft, verifies restoration, discards it through close confirmation, and verifies it is absent afterward. Full Simulator suite passed at /private/tmp/weeklywins-audio-draft-final.log. No physical install for this stage. Remaining work includes onboarding, multi-event review draft handling, report interactions, further UI fidelity and device long/offline acceptance.

## First-launch stage, 2026-11-17

Added approved A01 onboarding with Voice Studio palette, voice-to-two-events example, microphone permission/status and Settings recovery, Action Button guide link, optional trial capture and skip-to-diary actions. StudioRootView persists completion in UserDefaults. Existing visible recordings and an ongoing capture/start bypass onboarding so first-foreground use after an Action Button recording preserves the recorder.

Read-only review found no important issues. A dedicated clean iPhone16Pro iOS26.5 Simulator was created, app installed and microphone granted using simctl, then the onboarding UI test passed: welcome→microphone step→trial recording→stop→app terminate/relaunch→no repeated onboarding. The clean QA simulator was then shut down and deleted. First-request/denied system prompt branches still require a dedicated permission-state check.

Main Simulator regression suite passed at /private/tmp/weeklywins-onboarding-regression.log. Its fresh-install-only test skips on the populated simulator; it passed separately at /private/tmp/weeklywins-onboarding-fresh.log. Two OS Action Button/Shortcut dispatch tests remain skipped as previously documented. No physical device install in this stage.

## Report navigation stage, 2026-11-17

Added Russian period titles, week/month range navigation from calendar boundaries, Monday–Sunday reporting weeks, calendar-derived day lists, chart tap to day drill-down and return to original week/month. Timeline supports explicit historical day selection and a Today return action. Today-following mode refreshes on foreground/day boundaries. Week definition follows the approved Monday-first chart.

Review found historical civil dates shifting across a time-zone change. Fixed by preserving selected era/year/month/day components (and the parent drill-down period) across zones while Today-following uses the current instant. The date picker explicitly controls following mode, avoiding implicit changes during rebasing. Unit tests cover month-end navigation, February day count, Monday/Sunday week endpoints, Russian titles, event regrouping by timezone and retaining a selected civil date. UI test creates a real in-app recording and manual transcript, switches report weeks, taps a chart into a day and returns to the original week. Full Simulator suite passed at /private/tmp/weeklywins-report-navigation-final.log. No real-device installation for this stage.

## Event review stage, 2026-11-17

A10 now shows compact expandable event cards and bottom Add/Done actions in the approved Voice Studio palette. The complete review draft, including deleted and newly added events and an edited pending merge proposal, persists with its original baseline. Closing a changed list prompts save/discard. Source deletion clears review drafts immediately and during startup cleanup. List saves validate their original baseline to prevent overwriting newer event edits. Individual drafts now track their original event baseline, while existing draft data remains readable. Committed changes clear obsolete individual drafts.

Merging adjacent events opens a text/metadata preview with explicit confirmation and cancellation. The combined source text is retained. Time and duration are reset for explicit review. Differing categories default to unclassified, and a not-completed source carries that status into the proposal. Event deletion offers undo. A Simulator UI regression exposed a crash from array-index bindings after merging an expanded row. ID-based bindings fix the crash and ignore writes to removed rows.

Independent static review found baseline lifetime and stale individual-draft issues, both corrected. The full Simulator suite passed with 48 passed, 3 skipped, 0 failed at /private/tmp/weeklywins-event-review-release.log. Skips remain the two OS Shortcut/Action Button dispatch cases and clean-install onboarding on the populated Simulator. The new UI scenario verifies draft restoration after termination, save-on-close, merge cancellation and confirmation, the persisted merged list, and restart during an edited merge preview. No physical-device installation in this stage.

Remaining acceptance includes A01–A18 visual comparison on iPhone 16 Pro, large Dynamic Type and keyboard states, system permission states, Russian extraction quality and long offline physical-device recording. The current review screenshots use the iPhone 17 Pro Simulator. Broader goal remains active.

Visual inspection covers compact A10 cards and the merge preview after relaunch. Screenshots are saved locally at shots/A10-event-review.png and shots/A10-merge-confirmation.png. Compared against the A10 specification and the shared palette, native typography and rounded card treatment of the approved direction. Corrected mint-button text contrast, shared surface colors and the truncated merge title by placing confirmation at the bottom. Large Dynamic Type, keyboard screenshots and complete A01–A18 fidelity remain pending.

## App icon integration, 2026-11-17

User selected Echo C and requested volume. Added its opaque 1024px artwork to the app's AppIcon asset catalog, configured the target in project.yml, regenerated Xcode project and increased build number to 16. Settings and the full in-app recording/source flow UI tests passed at /private/tmp/weeklywins-icon-integration.log. Built Info.plist reports build 16 and AppIcon; Assets.car is present. Static review found no important issues.

Updated the existing Simulator app installation and visually verified its actual home-screen icon at docs/design/icons/weeklywins-build-16-home-screen.png. Removed the five temporary icon-preview applications from Simulator. Physical iPhone installation remains build 15 from the earlier transcription stage. Current source build 16 has not been installed on physical hardware.

## Explicit-duration extraction stage, 2026-11-17

Preserved decimal dots in transcript fragments and expanded exact duration parsing to decimal values, compound hours/minutes and spelled Russian quantities. The complete quantity phrase is matched before temporal-context validation. Clock times and relative references keep duration unknown. Range/approximation and unmatched larger-number context prevent false exact values. Added four regression groups covering 28 constructed phrases, observed failures before fixes and passed the full Simulator suite with 52 passed, 3 skipped, 0 failed. Log is /private/tmp/weeklywins-duration-final.log. Independent review's partial-quantity finding was fixed and rechecked.

User examples were requested asynchronously for the real-note extraction quality corpus. That evaluation and comparison of local extraction approaches remain open. Current iPhone read-only status confirms connection, iOS 27.2.1 and installed build 15. No new physical install. Build 16 remains the current source/Simulator build. Next work includes actual Russian quality evaluation, remaining UI fidelity and physical long/offline acceptance.

## User-note corpus stage, 2026-11-17

User supplied three real notes, preserved verbatim in EventExtractionTests and documented in docs/event-evaluation.md. The meeting note needs two events, completed meeting with a one-hour duration and pending infosec follow-up. The service repair and password change notes each need one completed event with unknown time/duration. Interpreted the typo “Поменя” as completed password change while preserving its original spelling in text/sourceText.

Baseline independent-fragment extraction passed 2/3 notes. Added contextual linking for standalone singular adjectival duration descriptions, source retention and explicit conflict tracking. Static review found incidental follow-up mentions, repeated-conflict loss and plural total inference. Regressions were observed failing and all three issues corrected. Store/relaunch/report integration verifies four events, three completed and one known hour. Full Simulator suite passed 61 tests, skipped 3, failed 0 at /private/tmp/weeklywins-user-corpus-final.log.

Visual comparison was started before the examples arrived. A dedicated iPhone16Pro iOS26.5 Simulator named WeeklyWins Design QA was created and first-booted. UDID A24693A8-FC21-43D6-9F57-1FFCAC2349ED is saved at /private/tmp/weeklywins-design-qa-id. It is currently shut down and has no WeeklyWins app/fixtures installed. Resume it for the pending Today/recorder/report comparison against docs/design/layout-a-approved.png. Broader real-note quality, long/offline physical acceptance and A01–A18 fidelity remain open.

A current-source inspection also confirmed RecordingService.stop finalizes audio and ends Live Activity, while transcription currently requires the explicit transcribe action. Approved A06 describes processing after stop. Automatic processing/durable scheduling needs a separate implementation pass, including permission handling and background termination behavior. Keep this gap in the remaining scope.

## Cancellable recognition dependency, 2026-11-17

Implemented and reviewed SpeechRecognitionSession, a MainActor one-shot continuation bridge used by native legacy SFSpeech recognition. It cancels the underlying recognition task and resolves the waiter once. Tests cover early cancellation, cancellation with late response and duplicate completion. Full unit target passed 57 tests, 0 failures at /private/tmp/weeklywins-speech-cancel-final.log. No physical install.

Automatic ASR after capture remains the active next slice. Architecture consultation established these constraints. Serial worker owns jobs. Persist optional automaticTranscriptionPending on beginRecording before the audio rename window. Existing manual/completed/edited transcripts retain their ownership. On processing cancellation/termination, genuine automatic work stays pending. Background coordinator grants time and forwards cancellation, and its handlers do not independently launch recognition. Foreground user actions can submit BGContinuedProcessingTask with real progress. Locked stop uses bounded UIKit time when authorized, or waits for foreground authorization. Every attempt needs isolated callbacks. Skip existing unsaved transcript drafts and resume after discard. Root activation/initial launch must resume pending work. UI should publish processing state before awaiting the engine.

Implementation sketch for next slice uses optional durable automaticTranscriptionPending on Recording, serial queue in RecordingService, TranscriptionExecutionSession protocol for deterministic expiration tests, native execution session with balanced UIKit lease and foreground BGContinuedProcessingTask, and a progress-capable Transcriber overload with a compatibility default. Queue tests should cover capture stop, rehydrated pending/processing jobs, cancellation/expiration, no duplicate workers, edited/draft protection, failure without audio deletion, and oldest-first serial ordering. Native Speech result ranges/legacy word timestamps can report actual processed-audio progress. Real five-minute Russian/offline acceptance and bundled-model comparison remain open.

## Automatic-transcription queue, build 17, 2026-11-17

Implemented durable automaticTranscriptionPending before capture starts, oldest-first serial processing, root launch/foreground resumption, draft protection, visible Today processing/error rows with source/retry, and processing state publication before engine await. New flag is optional for existing data. Successful/failed jobs clear it, while cancellation or authorization deferral preserves genuine automatic pending work. Interrupted automatic processing resumes after store recovery. Legacy/manual jobs retain existing recovery behavior.

TranscriptionBackgroundSession supplies balanced UIKit time and foreground user-initiated BGContinuedProcessingTask protection with actual native result progress. New Info keys and processing mode are in project.yml. Foreground user-action context is scoped to the immediate worker invocation and its first attempted job. Recovery, backlog, timer and interruption work get bounded execution. Every recognition attempt owns its cancellation and callback state. SpeechAnalyzer cancellation explicitly stops results consumption and the analyzer.

Review findings about analyzer cancellation, dropped foreground resumption during cleanup and deferred continuation provenance were fixed with regressions. Nine queue tests cover these and stop/expiry/draft/failure/serialization behavior. Full iPhone16Pro iOS26.5 Simulator suite passed 74 tests, 4 skipped, 0 failed at /private/tmp/weeklywins-auto-final-ephemeral.log. Successful ASR in queue tests is scripted. Native long/background recognition and five-minute airplane-mode acceptance remain open. Native Simulator capability probes now report legacy local support but actual attempts encounter backend failures.

UI testing exposed a real scroll clipping bug. Root ZStack plus outer safeAreaInset allowed last cards below the custom bottom controls. Replaced it with constrained VStack and native TabView preserving per-tab state, hiding the system tab bar on each child. UI tests verify full-card reachability, source opening and report state across tabs. Final actual A06 screenshot and its fixture details are in docs/design/verification/.

Dedicated QA Simulator A24693A8-FC21-43D6-9F57-1FFCAC2349ED has build 17. After final regression it was reseeded with the four visual fixtures for the saved A06 screenshot. Its earlier visual fixture included a future 15:20 record, which interfered with tests assuming newest recording is newly captured. Its generated data was backed up to /private/tmp/weeklywins-design-fixture-backup-17, then cleared before the successful clean run. Validated generated test recordings were backed up to /private/tmp/weeklywins-auto-validated-recordings-17 before reseeding. Clear the generated visual recordings before a fresh full UI run that assumes the newest capture is the first library row. Primary iPhone17Pro Simulator data was preserved. No physical-device installation in this stage.

Remaining work includes exact A01–A18 visual fidelity, auto-stop screen transition at the five-minute limit, speech/microphone permission states, real five-minute/offline provider comparison, and physical interruption/restart acceptance. Revalidate the two OS Simulator action/shortcut dispatch paths against current role conformance, since their skip evidence originated before the successful physical build 14 fix.

The final cold-authorization regression also verifies that a locked stop with no speech authorization waits for foreground and carries no continued-processing eligibility into that later session. The active-state dependency is injectable for deterministic tests and defaults to UIKit. Observed the deferred-eligibility failure before adding the active-at-stop guard. All queue tests now model their relevant foreground/background state explicitly.

Final rapid-restart regression observed stale unclaimed stop eligibility surviving a new capture. Removed the per-record eligibility Set. stop passes a scoped recording ID into immediate scheduling, and the worker consumes it only for its first attempt. An unstarted worker drops its context when it exits. All nine queue regressions pass, and the final full suite reports 74 passed, 4 skipped, 0 failed at /private/tmp/weeklywins-auto-final-ephemeral.log.

## Simulator Action Button automation, 2026-11-17

A new dedicated iPhone16Pro iOS26.5 Simulator, WeeklyWins Shortcuts QA (`31B6F161-6E54-4D66-8709-B7C790547F52`), proves actual background Action Button dispatch. Saved single-action Shortcuts with `Показать при запуске` enabled wait on the returned dialog's Done button. The command stays running, so another shortcut-card tap can cancel its execution. A screenshot of the blocked result is saved locally at shots/simulator-shortcuts-result-waits-for-done.png. The switch exposes a whole-row frame; tap its right-hand knob and assert value 0.

UI tests now prepare a saved command with this switch off. The saved-editor test runs twice through the play control, waiting for enabled and hittable state. The Action Button test assigns the saved command through Settings, backgrounds with Home before each of two actual XCUIDevice Action presses, observes active/idle states, reopens the new UUID after app relaunch and plays that exact recording. The Simulator hardware skip is removed. The direct App Shortcut card remains a separate skipped case based on current build 17 negative probes.

Focused background hardware verification passed at /private/tmp/weeklywins-action-background-no-dialog.log. Isolated manifest comparison found exactly one new saved recording CC6ABF8B-9C49-42C6-85CE-D0F88F1E7599, duration 6.588s, both intent calls PID46191. ffprobe reports AAC16k mono, container duration6.72s; ffmpeg decoded it fully. Reviewer flagged the possibility of playing an older row. Added a technical UUID accessibility identifier to the title, recorded the baseline newest identity, required a new identity, relaunched and selected that exact identity before playback. The identity test failed before the identifier and passed after it at /private/tmp/weeklywins-action-identity-{red,green}.log. No layout change was needed for this verification.

An initial full suite passed 76 tests, skipped3, failed0 at /private/tmp/weeklywins-simulator-shortcuts-final.log. The final suite including the stronger identity assertion passed 76 tests, skipped 3 and failed 0 at /private/tmp/weeklywins-simulator-shortcuts-identity-final.log. The xcresult summary confirms 79 total tests. Sol completed a static review of the final diff with no remaining substantial findings.

At the user's request, extra booted Simulators were shut down. Primary iPhone17Pro and WeeklyWins Design QA preserve their data. WeeklyWins Shortcuts QA is the only booted device. No physical installation occurred. Continue with the five-minute recorder-screen transition and the remaining approved A01–A18, extraction-quality and physical long/offline/interruption acceptance work. The thread goal remains active.
