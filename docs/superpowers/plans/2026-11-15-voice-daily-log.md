# Voice Daily Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an offline-first Russian voice diary for iPhone 16 Pro with Action Button recording, editable events, and day/week/month reports.

**Architecture:** A native SwiftUI app owns recording, storage, transcription, event extraction, and reporting. App Intents exposes a single recording toggle to Shortcuts; cloud text processing is a later opt-in adapter only if local extraction fails its quality gate.

**Tech Stack:** Swift, SwiftUI, AVFoundation, App Intents, ActivityKit, on-device Speech or bundled ASR model, local persistence.

**Spec:** `docs/superpowers/specs/2026-11-15-voice-daily-log-design.md`

## Global Constraints

- Target device: iPhone 16 Pro; Russian speech; offline recording and transcription.
- Recording length: up to 5 minutes, with automatic stop at the limit.
- Action Button must start and stop recording while locked without unlocking.
- Preserve audio and recording timestamp even when later processing fails.
- Preserve unknown event time and duration as unknown; do not invent them.
- Cloud fallback, if needed, sends text only with explicit opt-in through a proxy-backed server.

## Review Focus

- First launch with microphone permission unset: grant permission before relying on locked-screen use (Task 1).
- Double press or simultaneous UI/button stop: create exactly one completed recording (Task 2).
- Phone call, audio route change, or app termination: retain a recoverable recording and accurate status (Task 2).
- Incorrect split, negation, or ambiguous time in Russian: preserve source text and allow correction (Task 4).
- Day boundary and time-zone change: group by the local date of the event, falling back to recording date (Task 5).

---

### Task 1: Locked-screen feasibility gate

**Deliverable:** A throwaway native device build that proves or disproves the required two-press flow before the rest of the app is built.

**Files:** `WeeklyWins/Recording/ToggleRecordingIntent.swift`, `WeeklyWins/Recording/RecordingActivity.swift`, `WeeklyWins/Recording/Recorder.swift`, `WeeklyWins/WeeklyWinsApp.swift`, `docs/device-validation.md`.

- [x] Create the minimal SwiftUI iOS project and configure microphone permission, background audio, App Shortcut, and Live Activity.
- [x] Implement one toggle intent that starts a file recording when idle and stops it when active. Keep its operation idempotent across repeated invocations.
- [x] On the physical iPhone, grant microphone permission, assign the shortcut to the Action Button, and start and stop a recording while locked. Build 22 passed both the ordinary run and a repeat after force quit.
- [x] Verify the locked path after an iPhone restart and automatic stop after five minutes. Build 22 stored 299.9 seconds after a single locked Action Button start.
- [x] Verify capture recovery after a call or audio-route interruption on iPhone. A real incoming call on build 25 interrupted and preserved 21.18 seconds of audio. The next locked Action Button capture saved 7.548 seconds. Both recordings decode and have completed transcripts. See [device validation](../../device-validation.md#physical-interruption-and-the-next-recording-on-build-25).
- [x] Verify short locked Action Button recordings when Bluetooth music was playing before the hold. Three physical build 30 runs followed system Pause, Wait 2 seconds and WeeklyWins, and saved decodable and transcribed audio. The experimental wait also delays the stop; this setup was verified away from the five-minute limit. See [device validation](../../device-validation.md#pause-followed-by-a-two-second-wait).
- [ ] Record OS version, exact behavior, time from press to capture, produced file duration, and any unlock prompt in `docs/device-validation.md`.
- [x] Gate: locked start and stop both worked without unlocking and created a valid file. Build 22 produced one fully decodable 56-second recording and completed transcription in airplane mode, with the lock and radio states confirmed by the user.

### Task 2: Reliable recording and local persistence

**Deliverable:** App and button recordings survive interruptions and appear in a local list.

**Files:** `WeeklyWins/Recording/Recorder.swift`, `WeeklyWins/Recording/RecordingStore.swift`, `WeeklyWins/Recording/RecordingView.swift`, `WeeklyWins/Recording/Recording.swift`, `WeeklyWinsTests/RecordingTests.swift`.

- [x] Define one recording identity, start timestamp, duration, file URL, processing state, and error state in local storage.
- [x] Add tests for the 5-minute stop, double stop, interruption, and recovery after relaunch; run the focused test target and observe failures.
- [x] Implement capture and atomic finalization; make UI and intent call the same recording service; pass focused tests.
- [x] Verify short recordings on the physical device with WeeklyWins in the background and the screen locked. Build 22 saved and recognized audio in the ordinary run and after force quit. Build 22 also saved a five-minute capture after an iPhone reboot. Physical interruption recovery remains tracked in Task 1.

### Task 3: Offline Russian transcription selection and integration

**Deliverable:** A saved 5-minute Russian recording produces editable text without network access.

**Files:** `WeeklyWins/Transcription/Transcriber.swift`, `WeeklyWins/Transcription/TranscriptionService.swift`, `WeeklyWins/Transcription/TranscriptView.swift`, `WeeklyWinsTests/TranscriptionTests.swift`, `docs/asr-evaluation.md`.

- [x] Check the Russian locale and compare Apple Speech and a bundled Whisper model using the same hash-verified recordings on iPhone 16 Pro. Apple uses the on-device legacy recognizer for Russian on this phone.
- [x] Measure word errors, elapsed time, and the candidate model footprint. Keep Apple as the default. Details and exclusions are in [ASR evaluation](../../asr-evaluation.md).
- [x] Verify editable text, retained audio after failure, and a successful retry through the replaceable transcriber interface. Runtime availability probes cover the installed Russian recognizers.
- [x] Verify saved one-minute and five-minute audio files complete processing with the device offline. A natural locked Action Button note with offline capture and processing was also confirmed at 56 seconds.
- [x] Verify one continuous five-minute spoken capture and transcription with the phone offline throughout. Build 22 saved a 299.9-second locked Action Button capture at the automatic limit and transcribed its final phrase before the owner restored connectivity. See [device validation](../../device-validation.md#five-minute-offline-capture-and-transcription-on-iphone).
- [ ] Compare battery impact and measure recognition quality on a larger natural Russian corpus.

### Task 4: Event extraction and editing

**Deliverable:** Several mentioned tasks in one transcript become editable, traceable events.

**Files:** `WeeklyWins/Events/Event.swift`, `WeeklyWins/Events/EventExtractor.swift`, `WeeklyWins/Events/EventReviewView.swift`, `WeeklyWinsTests/EventExtractionTests.swift`, `docs/event-evaluation.md`.

- [x] Record expected splits for three user-provided Russian examples with meeting, follow-up, and repair tasks. Controlled cases cover negation, references to earlier actions and unknown durations.
- [x] Compare punctuation-only splitting with contextual interpretation. Select the approach that matches all three examples, including event count, duration, completion status and linked source. See [event evaluation](../../event-evaluation.md).
- [x] Test separate events, source linkage, unknown time and duration, category editing, merge, and deletion. The controlled five-minute Apple transcript regression verifies 13 episodes.
- [x] Confirm that new suggestions appear in Today immediately and can be corrected later. Simulator cases save a transcript, open a new suggestion in Today, edit it and observe the updated card in all three report periods.
- [ ] Extend the natural-note corpus with negation and earlier-day recall, and record the expected events.

### Task 5: Today and period reports

**Deliverable:** Today, day, week, and month views show the same current events and known duration totals.

**Files:** `WeeklyWins/Timeline/TodayView.swift`, `WeeklyWins/Reports/ReportQuery.swift`, `WeeklyWins/Reports/ReportView.swift`, `WeeklyWinsTests/ReportTests.swift`.

- [x] Test ordering, local day boundaries, timezone changes, unknown duration exclusion, and report updates after edits/deletion. ReportTests verifies distinct period ranges and persisted edits.
- [x] Implement one query source for all periods and category grouping; pass tests. ReportView uses ReportQuery for Today and all selected periods.
- [x] Check readable presentation and day drilldown on iPhone 16 Pro Simulator with a populated week and maximum Dynamic Type. See [design verification](../../design/verification/README.md).
- [ ] Check readable presentation of many short events and a few long events on the physical device if needed after the Simulator verification.

### Task 6: Conditional cloud text fallback

**Deliverable:** Implement only if Task 4 documents insufficient local extraction quality and the user approves this optional capability.

**Files:** separate follow-on plan after selecting the API, hosting, proxy, authentication, privacy notice, and cost cap.

- [x] Keep the local MVP usable without a cloud service.
- [ ] If activated, design the server boundary so audio stays on-device, text transfer is opt-in per user setting, credentials stay server-side, and all external requests use the configured proxy.

## Delivery order

Task 1 is a hard device gate. Tasks 2–5 form the offline MVP. Task 6 is conditional and requires a separate implementation plan after local extraction has been measured.
