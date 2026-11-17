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
