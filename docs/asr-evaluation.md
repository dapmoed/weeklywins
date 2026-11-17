# Offline Russian transcription evaluation

Updated: 2026-11-16

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

No final ASR provider or bundled model has been selected. The current Simulator cannot run either Russian on-device engine, and the iPhone 16 Pro is disconnected. When the device is available, compare installed `SpeechTranscriber` assets against one bundled offline model using the same Russian recordings in airplane mode. Record word error rate, processing time, model size, and battery impact before selecting the provider. If no offline engine is supported, keep transcription unavailable with an explicit error rather than sending audio or text to a network service.

## Physical iPhone probe, build 14

On the connected iPhone 16 Pro running iOS 27.2, the runtime probe on 2026-11-16 returned no equivalent Russian locale for SpeechTranscriber. SFSpeechRecognizer(ru-RU) exists and reports supportsOnDeviceRecognition=true. The provider selects this fallback with requiresOnDeviceRecognition=true. Actual Russian accuracy and five-minute offline processing still need measurement.

The user confirmed that transcription of a spoken recording works on the physical iPhone with build 14. The five-minute airplane-mode comparison, measured word errors, storage, and battery evaluation remain open.
