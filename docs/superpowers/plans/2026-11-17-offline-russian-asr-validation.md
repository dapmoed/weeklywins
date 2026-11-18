# Offline Russian ASR validation plan

> Execute this part of Task 3 inline with the executing-plans skill. Keep the original voice-diary goal active until the complete product acceptance is verified.

## Goal

Measure complete Russian transcription of one-minute and five-minute audio on iPhone 16 Pro, compare the existing native engine with one bundled-model candidate, and select a provider from the measured results.

## Architecture

The current OnDeviceSpeechTranscriber remains the production entry point during measurement. Gated device-hosted XCTest cases read fixtures from Application Support/ASRAcceptance and write structured results there. Local macOS speech synthesis creates controlled reference audio. Evaluation fixtures and reports stay separate from user recordings.

## Tech stack

Swift, AVFoundation, Speech, XCTest, local macOS say, ffmpeg, ffprobe and Python standard library. Select the bundled comparison implementation after the native measurements establish its necessary integration scope.

## Specification

The governing product requirements are in docs/superpowers/specs/2026-11-15-voice-daily-log-design.md and Task 3 of docs/superpowers/plans/2026-11-15-voice-daily-log.md.

## Global constraints

- Russian speech and all audio recognition stay local.
- Check supportsOnDeviceRecognition before requiring on-device legacy recognition.
- Preserve user audio, transcripts, events, drafts and timestamps during installation and measurement.
- Use the same fixture bytes for all providers.
- Synthetic speech supplies a controlled baseline. Keep natural user-speech accuracy identified separately.
- Real-device work serves native engine availability, performance and offline acceptance. Continue general product testing on Simulator.
- Commit and push each completed measurement or implementation stage after relevant verification and Sol review.

Apple documents an audio-duration limit in the legacy recognizer guidance. Measure the complete file and its ending before treating the five-minute path as accepted. The current production adapter's guarded on-device requirement is documented by Apple. [SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer), [requiresOnDeviceRecognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)

## Review focus

- A recognizer may return a final result after processing only part of a long file. Compare the complete reference and ending.
- Recognition can fail or cancel after producing partial text. Preserve the audio and report the terminal outcome.
- Wi-Fi authorization and service names can have alternate orthography. Keep strict word errors and domain-term observations distinguishable in the report.
- Simulator capability flags can advertise support while the native backend fails. Device engine selection must follow measured device behavior.
- Background expiration, denied permission, charging and thermal conditions affect the interpretation of results. Record their observed state.

## Task 1 — Controlled fixtures

Files are scripts/asr-fixtures/ru-one-minute.txt, scripts/asr-fixtures/ru-five-minute.txt and scripts/generate-asr-fixtures.py.

- [x] Generate both files with the installed local Russian Milena voice.
- [x] Calibrate speech to fit the duration, retain every spoken reference word, and pad the remaining interval to 60 or 300 seconds.
- [x] Produce mono 16 kHz AAC, copy the references and record voice, speech duration, container duration, word count and SHA-256 in fixture metadata.
- [x] Run ffprobe and complete decoding on both generated files.

## Task 2 — Native device measurements

Create WeeklyWinsTests/ASRAcceptanceTests.swift and regenerate the project through XcodeGen. Use gated tests enabled by TEST_RUNNER_RUN_DEVICE_ASR_ACCEPTANCE=1 and explicit test selection.

- [x] Read the fixture folder from Application Support/ASRAcceptance. Ordinary test runs skip this device-only measurement.
- [x] Call OnDeviceSpeechTranscriber.transcribe(audioFileURL:locale:) with ru-RU and record a report on success or failure.
- [x] Record processing time, audio duration, selected native availability, reference/transcript word counts, complete transcript, terminal error, battery/charging and thermal state.
- [ ] Stage fixtures on the phone and run the one-minute and five-minute cases. Inspect the ending and compute word error rate against the controlled reference.
- [ ] Verify wired transport before airplane-mode acceptance and restore connectivity to its prior state after the measurement.
- [ ] Preserve measured reports locally and summarize evidence in docs/asr-evaluation.md. Seek Sol review and commit/push the completed stage.

## Task 3 — Duration or lifecycle fixes when established by evidence

- [x] If measurement finds incomplete long recognition, create the reproducing test and implement a bounded local processing strategy through the existing Transcriber interface.
- [x] Cover cancellation, output ordering, boundaries and preservation of audio and user edits.
- [ ] Repeat the same native device corpus after the fix, including the five-minute offline case.

## Task 4 — Bundled candidate comparison and selection

- [ ] Choose one maintained multilingual offline model implementation from primary documentation and record its version, license and artifact hash.
- [ ] Compare the same fixture bytes on the device, recording quality, processing time, storage footprint and the available energy observations with their resolution and charging state.
- [ ] Use natural user speech for an additional accuracy check with an explicit reference.
- [ ] Document the selected provider and any remaining measurement limits. Update the original Task 3 checkboxes only for requirements with matching evidence.

## Measurement status

The native measurements are documented in docs/asr-evaluation.md and raw reports under docs/asr/2026-11-17-native-baseline. The user confirmed manual offline recognition. The five-minute fixture exposes incomplete long-file output and Task 3 is the next implementation step. The bundled comparison remains open. Radio automation was removed after a runner trust failure, and the successful offline workflow uses one running native test host with user-controlled radio settings.

## Build 20 implementation status

Bounded contextual windows and native timed-partial accumulation now preserve the complete controlled300s narrative. Final device result474/478words, WER10.67%,8.258s. Details and raw reports are in docs/asr-evaluation.md. Final Simulator suite102PASS8SKIP0FAIL,total110. Both final device acceptance cases passed. The actual full-build20 airplane-mode repeat, bundled comparison, natural corpus and energy observations remain open.
