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
- [ ] Verify the locked path after an iPhone restart, automatic stop after five minutes, and capture recovery after a call or audio-route interruption.
- [ ] Record OS version, exact behavior, time from press to capture, produced file duration, and any unlock prompt in `docs/device-validation.md`.
- [x] Gate: locked start and stop both worked without unlocking and created a valid file. Build 22 produced one fully decodable 56-second recording and completed transcription in airplane mode, with the lock and radio states confirmed by the user.

### Task 2: Reliable recording and local persistence

**Deliverable:** App and button recordings survive interruptions and appear in a local list.

**Files:** `WeeklyWins/Recording/Recorder.swift`, `WeeklyWins/Recording/RecordingStore.swift`, `WeeklyWins/Recording/RecordingView.swift`, `WeeklyWins/Recording/Recording.swift`, `WeeklyWinsTests/RecordingTests.swift`.

- [x] Define one recording identity, start timestamp, duration, file URL, processing state, and error state in local storage.
- [x] Add tests for the 5-minute stop, double stop, interruption, and recovery after relaunch; run the focused test target and observe failures.
- [x] Implement capture and atomic finalization; make UI and intent call the same recording service; pass focused tests.
- [x] Verify short recordings on the physical device with WeeklyWins in the background and the screen locked. Build 22 saved and recognized audio in the ordinary run and after force quit. The restart, maximum-duration and interruption cases remain tracked in Task 1.

### Task 3: Offline Russian transcription selection and integration

**Deliverable:** A saved 5-minute Russian recording produces editable text without network access.

**Files:** `WeeklyWins/Transcription/Transcriber.swift`, `WeeklyWins/Transcription/TranscriptionService.swift`, `WeeklyWins/Transcription/TranscriptView.swift`, `WeeklyWinsTests/TranscriptionTests.swift`, `docs/asr-evaluation.md`.

- [ ] On device, check `SpeechTranscriber` availability and Russian locale; compare it with one bundled offline model using the same representative recordings in airplane mode.
- [ ] Record word errors, processing time, storage size, and battery impact; select the smallest acceptable solution in `docs/asr-evaluation.md`.
- [ ] Test success, unsupported language/model, retry, and failure without audio deletion; implement the chosen transcriber behind a replaceable interface.
- [ ] Verify the full five-minute path in airplane mode on the physical iPhone.

### Task 4: Event extraction and editing

**Deliverable:** Several mentioned tasks in one transcript become editable, traceable events.

**Files:** `WeeklyWins/Events/Event.swift`, `WeeklyWins/Events/EventExtractor.swift`, `WeeklyWins/Events/EventReviewView.swift`, `WeeklyWinsTests/EventExtractionTests.swift`, `docs/event-evaluation.md`.

- [ ] Build a small set of real Russian examples with large and small tasks, negation, recalled earlier tasks, and explicit or unknown duration; define expected splits.
- [ ] Compare local extraction approaches against these examples; choose one that meets a documented quality threshold. Do not add cloud processing silently.
- [ ] Test separate events, source linkage, unknown time/duration, category editing, merge, and deletion; implement extraction and editing; pass tests.
- [x] Confirm that new suggestions appear in Today immediately and can be corrected later. Build 22 Simulator cases save a transcript, open a new suggestion in Today, edit it and observe the updated card in all three report periods.

### Task 5: Today and period reports

**Deliverable:** Today, day, week, and month views show the same current events and known duration totals.

**Files:** `WeeklyWins/Timeline/TodayView.swift`, `WeeklyWins/Reports/ReportQuery.swift`, `WeeklyWins/Reports/ReportView.swift`, `WeeklyWinsTests/ReportTests.swift`.

- [x] Test ordering, local day boundaries, timezone changes, unknown duration exclusion, and report updates after edits/deletion. ReportTests verifies distinct period ranges and persisted edits.
- [x] Implement one query source for all periods and category grouping; pass tests. ReportView uses ReportQuery for Today and all selected periods.
- [ ] Check readable presentation of many short events and a few long events on the physical device.

### Task 6: Conditional cloud text fallback

**Deliverable:** Implement only if Task 4 documents insufficient local extraction quality and the user approves this optional capability.

**Files:** separate follow-on plan after selecting the API, hosting, proxy, authentication, privacy notice, and cost cap.

- [ ] Keep local MVP complete and usable without this task.
- [ ] If activated, design the server boundary so audio stays on-device, text transfer is opt-in per user setting, credentials stay server-side, and all external requests use the configured proxy.

## Delivery order

Task 1 is a hard device gate. Tasks 2–5 form the offline MVP. Task 6 is conditional and requires a separate implementation plan after local extraction has been measured.
