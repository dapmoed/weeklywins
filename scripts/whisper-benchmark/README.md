# Whisper benchmark for WeeklyWins

This iPhone benchmark compares the bundled multilingual Whisper Base Q5_1 model against the existing Apple recognizer. Both consume the controlled one-minute and five-minute Russian fixtures. The benchmark creates a separate Xcode project for a hosted test using the WeeklyWins app and its existing development signing. The standard project has no dependency on Whisper.

The benchmark pins whisper.cpp v1.9.5 by commit and checks the model SHA-256 before bundling it into the test. It runs the native library on CPU with four threads and Apple Accelerate. Each fixture starts with a fresh model context. Reported processing time includes PCM decoding, model initialization, inference, and assembly of the transcript. Reports also record model loading and inference separately.

Generate the fixtures and build the test with XcodeGen, CMake, and Xcode available.

```sh
python3 scripts/generate-asr-fixtures.py --output /private/tmp/weeklywins-asr-fixtures
bash scripts/whisper-benchmark/build.sh /private/tmp/weeklywins-whisper /private/tmp/weeklywins-asr-fixtures
```

Use the connected iPhone's Xcode destination ID in `device_id`. The Apple acceptance tests expect the fixture files and manifest to have been copied into the app container at `Library/Application Support/ASRAcceptance` as described in the ASR validation plan.

```sh
TEST_RUNNER_RUN_DEVICE_ASR_ACCEPTANCE=1 \
python3 scripts/device-test-session.py run --device "$device_id" --command \
  xcodebuild -project /private/tmp/weeklywins-whisper/hosted/WeeklyWins.xcodeproj \
  -scheme WeeklyWins -destination "platform=iOS,id=$device_id" \
  -derivedDataPath /private/tmp/weeklywins-whisper/hosted-derived \
  -parallel-testing-enabled NO \
  -only-testing:WeeklyWinsTests/WhisperBenchmarkTests/testRussianCorpus \
  -only-testing:WeeklyWinsTests/ASRAcceptanceTests/testNativeRussianOneMinute \
  -only-testing:WeeklyWinsTests/ASRAcceptanceTests/testNativeRussianFiveMinutes \
  test-without-building
```

Read the four `*.whisper-report.json` and `*.native-report.json` files from `Library/Application Support/ASRAcceptance` using `devicectl device copy from`. Pass them to `scripts/evaluate-asr-reports.py` with the original fixture directory to verify the audio identity and calculate WER. After collecting reports, reinstall the standard signed WeeklyWins build in place to remove the benchmark test payload from the phone.
