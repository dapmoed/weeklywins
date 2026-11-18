# Offline Russian transcription evaluation

Updated 2026-11-17

## Simulator probe

Environment: iPhone 17 Pro Simulator, iOS 26.5, Xcode 26.6.

- `SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ru-RU"))` resolves to `ru_RU`.
- `AssetInventory.status(forModules: [SpeechTranscriber])` returns `.unsupported` in this Simulator.
- `SFSpeechRecognizer(locale: ru-RU)` exists but reports `supportsOnDeviceRecognition == false`.
- No Russian audio was transcribed in this environment; word error rate, processing time, model storage, and battery impact are **not measured**.

## Current implementation

- `Transcriber` is replaceable and accepts an audio file URL and locale.
- `OnDeviceSpeechTranscriber` uses `SpeechTranscriber` with on-device assets when supported. If that engine is unavailable, it only falls back to `SFSpeechRecognizer` when `supportsOnDeviceRecognition` is true and sets `requiresOnDeviceRecognition = true`. It never falls back to network recognition.
- `TranscriptionService` persists transcript text and processing state, supports retry, and retains the audio file on errors. `TranscriptView` lets the user edit and save the text.
- Simulator tests use a scripted fake transcriber to verify success, editing persistence, error state, retry, and audio retention. They do not measure ASR quality.

## Selection status and next measurement

No final ASR provider or bundled model has been selected. The initial Simulator probe reported unavailable on-device Russian engines. Later runtime probes advertise legacy on-device support, while native recognition in this Simulator reports backend failures. Physical short-note transcription is confirmed below. When the device is available, compare installed `SpeechTranscriber` assets against one bundled offline model using the same Russian recordings in airplane mode. Record word error rate, processing time, model size, and battery impact before selecting the provider. If no offline engine is supported, keep transcription unavailable with an explicit error rather than sending audio or text to a network service.

## Physical iPhone probe, build 14

On the connected iPhone 16 Pro running iOS 27.2, the runtime probe on 2026-11-16 returned no equivalent Russian locale for SpeechTranscriber. SFSpeechRecognizer(ru-RU) exists and reports supportsOnDeviceRecognition=true. The provider selects this fallback with requiresOnDeviceRecognition=true. Actual Russian accuracy and five-minute offline processing still need measurement.

The user confirmed that transcription of a spoken recording works on the physical iPhone with build 14. The five-minute airplane-mode comparison, measured word errors, storage, and battery evaluation remain open.

## Cancellation prerequisite, 2026-11-17

Legacy on-device recognition now uses a one-shot MainActor SpeechRecognitionSession. It retains the recognition task through a cancellation closure, completes its checked continuation once and cancels recognition before releasing the waiting caller. Late and duplicate callbacks are ignored after completion. The session is retained through its async lifetime.

Three deterministic tests exercise cancellation before engine start, cancellation during recognition with a late result, and duplicate completion callbacks. The full unit-test target passed 57 tests with 0 failures at /private/tmp/weeklywins-speech-cancel-final.log. These tests verify callback ownership/cancellation using an injected recognizer starter. Physical native-engine cancellation and long-recording quality require device verification.

Automatic processing is the next implementation slice. The design uses persisted intent before recording finalization, a serial worker and cancellable execution sessions. Foreground user-initiated processing will request BGContinuedProcessingTask execution, while a locked/background stop can use a bounded UIKit background task after speech permission has been granted. Pending work will resume after foreground/relaunch, preserving current text and user drafts.

Apple documents foreground user initiation, progress reporting and expiration for [continued processing](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados). UIKit's [background execution extension](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time) grants limited execution time and requires balancing every task identifier.

## Automatic processing in build 17

New captures persist automaticTranscriptionPending before audio recording starts. After finalization, RecordingService drains ready jobs serially, oldest first. Launch and foreground activation resume pending work. Interrupted automatic processing returns to pending during recovery. Completed text, manual text and unsaved transcript drafts retain their ownership. A draft postpones automatic processing until it is discarded or saved.

Each recognition attempt owns its operation and execution session. A short UIKit background task protects execution. A continued-processing request is eligible only for an immediate foreground user stop or an explicit manual transcribe action. Recovery, queued backlog, timer and interruption paths use the short lease. Background expiration cancels recognition and preserves genuine automatic work as pending. Foreground requests arriving during cancellation cleanup are latched until the old attempt releases ownership. Native progress uses actual analyzer ranges or recognized-word timestamps. Task completion follows the transcript/events commit.

SpeechAnalyzer now explicitly cancels its results consumer and analyzer through a cancellation handler. Legacy SFSpeech uses the previously verified one-shot session. General failures retain audio and present explicit retry through the app.

Nine queue regressions cover stop-triggered ASR dispatch, ordering/concurrency, persisted recovery, expiration, draft protection, terminal failure, resumption during delayed cancellation cleanup and continuation eligibility with older queued work. The full iPhone16Pro Simulator suite passed 74 tests, skipped 4 and failed 0 at /private/tmp/weeklywins-auto-final-ephemeral.log. Successful recognition in queue tests uses a scripted provider. Native background scheduling, native cancellation, five-minute Russian accuracy and airplane-mode acceptance require physical-device verification.

## Controlled native measurements on iPhone 16 Pro, build 18

Measured on iOS 27.2.1 with guarded requiresOnDeviceRecognition. SpeechTranscriber has no equivalent Russian locale on this phone. The adapter selects the legacy recognizer, whose on-device capability is true. Fixtures use the installed local Milena voice, generated from the references in scripts/asr-fixtures. Both AAC files are mono 16 kHz, decode completely and retain all reference speech within their 60s and 300s containers. Their SHA-256 values, raw synthetic transcripts and metrics are in [the baseline reports](asr/2026-11-17-native-baseline/fixtures.json).

| Input and condition | Reference words | Recognized words | Processing | Word error rate |
| --- | --- | --- | --- | --- |
| One minute, initial connectivity | 89 | 87 | 1.475 s | 15.73% |
| One minute, offline | 89 | 87 | 1.510 s | 15.73% |
| Five minutes, offline | 478 | 90 | 6.267 s | 83.05% |

The offline cases observe an actual NWPathMonitor update with unsatisfied status and no Wi-Fi, cellular or wired interface in use. They run in one already-launched test host. The minute result includes the complete ending. The five-minute result contains the tail of the narrative and loses earlier material, despite the native API returning a final result without an error. The result demonstrates a completeness defect in the current long-file adapter. Its acceptance assertion fails because 90 words fall below the expected complete output. The final marker has a grammatical recognition difference, so the marker check permits inflections and the word-coverage assertion remains the decisive failure.

Word errors use Levenshtein distance after lowercasing, punctuation tokenization and ё/е normalization. Number formatting, SNS/СНС spelling and Wi-Fi variants contribute to the minute score. These are controlled synthetic-speech measurements. The user separately confirmed that their manual offline transcription works. The duration of that manual sample was not supplied.

The phone was charging. Battery readings remained at 70% across the minute request, which supplies coarse observed state. A discharge-based energy comparison remains open. The bundled model comparison and natural-speech accuracy corpus remain open.

A UI-runner attempt to change radio settings lost its remote connection, and offline relaunch of that runner failed developer-certificate trust validation. The user restored the original airplane-off/Wi-Fi-on state. The failed helper was removed. The successful native measurement launches online, waits for a genuine offline path update, and processes both files in the same host. The user controls airplane mode manually. General product testing continues on Simulator.

Run the fixture generator and evaluator locally.

```sh
python3 scripts/generate-asr-fixtures.py --output /private/tmp/weeklywins-asr-fixtures-18
python3 scripts/evaluate-asr-reports.py --fixtures /private/tmp/weeklywins-asr-fixtures-18 REPORT.json
```

Device-hosted cases are explicitly gated by TEST_RUNNER_RUN_DEVICE_ASR_ACCEPTANCE=1. The combined offline case is ASRAcceptanceTests/testNativeRussianOfflineCorpus. Ordinary Simulator runs skip the three physical measurement cases. The final unit run passed 68 cases, skipped 3 and failed 0 at /private/tmp/weeklywins-asr-measurement-unit-final.log. Sol consultation was attempted during the radio-runner issue, and the service returned HTTP403. This measurement stage received author self-review.

## Complete native long-file processing, build 20

The legacy adapter now processes 50-second core ranges with two seconds of context on both sides, keeping each request at most 54 seconds. PCM windows are copied using a bounded buffer into protected temporary WAV files. Short captures up to 50 seconds retain their original file path. Context is reconciled through unique word-pair anchors, followed by unambiguous single-word anchors and a temporal fallback. The last pending text is retained through silent or left-context-only results. Original audio is read-only, and all temporary windows are removed on success, failure or cancellation.

A second native issue was established after the first windowing implementation. The voiced 148–202s WAV decoded correctly and reproduced the failure with a fresh recognizer. Its callback trace grew to a timed 86-word partial result, reset to an untimed new phrase and ended with a final two-word result at 53s. Keeping only the final result lost the completed preceding utterance. The new MainActor accumulator keeps established timed speech, applies corrections to overlapping snapshots and appends subsequent utterances. It retains original UTF-16 offsets while joining text and uses half-open time intervals. Untimed partials are deferred until timing is established. Empty or identical untimed finals preserve known speech, while conflicting untimed finals fail explicitly.

A single owned AsyncStream consumer processes native callbacks in delivery order. Existing one-shot completion and native task cancellation are reused through SpeechRecognitionResultSession with the previous String-based SpeechRecognitionSession type alias. Only Apple's documented no-recognized-speech error is skipped when the request has no established timed speech. Other failures propagate without committing a partial transcript. [Speech task errors](https://developer.apple.com/documentation/speech/sfspeechrecognitiontask/error)

| Controlled 300s fixture | Recognized words | Processing | Word error rate |
| --- | --- | --- | --- |
| Build 18 single final result | 90 of 478 | 6.267 s | 83.05% |
| Initial windowing, final-only window result | 396 of 478 | 8.249 s | 25.73% |
| Build 20 complete accumulation | 474 of 478 | 8.258 s | 10.67% |

The middle instruction task and the ending are present. The largest changed reference span is three words. The isolated problem window returns 88 timed segments instead of two. [Final results](asr/2026-11-18-native-windowed/scores.json) and the [pre-fix callback reset](asr/2026-11-18-native-windowed/callback-reset-before-fix.json) preserve the measured evidence. Results use the same controlled fixture bytes as the baseline. Device iPhone16Pro, iOS27.2.1. This final device repetition kept network settings under user control and did not record a network path snapshot. An explicit full build20 airplane-mode repetition remains open, alongside the bundled-model and natural-speech comparisons and energy measurement.

The final Simulator suite passed 102 cases, skipped 8 and failed 0, total 110, at /private/tmp/weeklywins-speech-build20-final-verified.log. Skips cover four physical ASR measurement cases, the opt-in real five-minute capture case, direct App Shortcut dispatch, populated-install onboarding and unavailable-ASR capability preconditions. The final physical run passed both the complete-file and isolated-window cases at /private/tmp/weeklywins-device-asr20/native-final-validation.log.

Sol's review findings about original UTF-16 offsets, cross-window timing disagreements, context-only results and abutting correction intervals were addressed with regressions. RED-to-GREEN evidence is in /private/tmp/weeklywins-speech-merger-overlap-red.log, /private/tmp/weeklywins-speech-context-only-red.log, /private/tmp/weeklywins-speech-final-reset-red.log and /private/tmp/weeklywins-speech-half-open-red.log, followed by the final full suite. No phone radio settings were changed in this implementation stage.

## On-device Apple and Whisper comparison, build 21

A single iPhone 16 Pro on iOS 27.2.1 processed the same hash-verified 60- and 300-second fixtures using Apple Speech and a bundled multilingual Whisper Base Q5_1 model. The Whisper library is whisper.cpp v1.9.5, revision `d1be6fde11ac6e0407606b4e42fe72d34add8037`, distributed under the MIT license. The model occupies 59,707,625 bytes and has SHA-256 `422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898`. Runtime settings were four CPU threads with Accelerate and greedy Russian transcription. The [upstream implementation](https://github.com/ggml-org/whisper.cpp/tree/v1.9.5) and [model distribution](https://huggingface.co/ggerganov/whisper.cpp/blob/main/ggml-base-q5_1.bin) identify the artifacts.

| Controlled fixture | Apple time | Apple WER | Whisper time | Whisper WER |
| --- | ---: | ---: | ---: | ---: |
| 60 seconds, 89 reference words | 1.520 s | 14 errors, 15.73% | 1.853 s | 16 errors, 17.98% |
| 300 seconds, 478 reference words | 8.101 s | 51 errors, 10.67% | 7.642 s | 48 errors, 10.04% |

Processing time covers the path from opening audio through complete transcript assembly. Whisper model load took 0.059 s and 0.031 s respectively and is included in the totals. Each run initialized its own context. Both transcripts included the concluding phrase for both fixtures. The phone was connected by USB, at 100% charge, with nominal thermal state for all runs. These battery observations do not resolve per-engine energy consumption. Network state was not recorded in this comparison. The Whisper test performed all inference from bundled resources with local APIs. The explicit airplane-mode repetition of the updated Apple path remains open.

Apple Speech remains the default for build 21 based on the measured minute latency, the small differences on this controlled corpus, and the 59.7 MB footprint of the candidate model. The decision will be reassessed using natural Russian speech if the measured quality falls short. The Apple model allocation is managed by iOS and was not measured. Source and resources for Whisper are confined to the benchmark test project. The two Apple tests and the Whisper corpus test all passed in the same device run. The test session confirmed that idle-timer suppression was removed when the run finished. [Reports and scores](asr/2026-11-18-whisper-comparison/scores.json), [reproduction](../scripts/whisper-benchmark/README.md).

## Recovered offline reports, build 21

Both reports were saved on the iPhone 16 Pro running iOS 27.2.1 on 18 November, after the developer connection broke during the switch to airplane mode. CoreDevice reported a local-network connection when the device reappeared. The host-side XCTest run ended with a connection error. The recovered app reports record an unsatisfied network path, no active Wi-Fi, cellular or wired network interface, and successful recognition of both SHA-256-verified fixtures. The test session ended after reconnection, with `active=false` and `idleTimerDisabled=false` confirmed by the app.

| Fixture | Processing | Recognized words | WER | Ending |
| --- | ---: | ---: | ---: | --- |
| 60 seconds | 1.650 s | 87 of 89 | 15.73% | Present |
| 300 seconds | 7.909 s | 474 of 478 | 10.67% | Present |

This verifies native offline processing of saved Russian audio through the current adapter at both durations. Capture through the locked Action Button, background completion and natural speech remain separate acceptance checks. [Recovered reports and scores](asr/2026-11-18-native-offline/scores.json).
