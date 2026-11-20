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

## Matched battery workloads

Build the hosted test with `build.sh`. Connect the unlocked iPhone over Wi-Fi and leave the charger disconnected. Use this test with an Instruments system power trace or the on-device Performance Trace. Keep the display brightness and other device settings fixed during the run.

```sh
TEST_RUNNER_RUN_DEVICE_ASR_POWER_BENCHMARK=1 \
TEST_RUNNER_RUN_DEVICE_ASR_POWER_REPEATS=2 \
python3 scripts/device-test-session.py run --device "$device_id" --command \
  xcodebuild -xctestrun "$xctestrun" -destination "platform=iOS,id=$device_id" \
    -parallel-testing-enabled NO -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 1800 -maximum-test-execution-time-allowance 1800 \
    -only-testing:WeeklyWinsTests/ASRPowerBenchmarkTests/testMatchedBatteryWorkloads \
    test-without-building
```

The test runs Apple Speech, Whisper, Whisper and Apple Speech with idle periods of at least 60 seconds between workloads and at the endpoints. It waits up to 90 extra seconds in each idle period for the phone to return to nominal thermal state. Each workload transcribes the same verified five-minute fixture the same number of times using fresh recognizers. The engines use the same pause pattern between transcriptions to limit heating. The test checks for unplugged operation, nominal thermal state during workloads and stable brightness. It writes completed blocks incrementally to `Library/Application Support/ASRAcceptance/power-workloads.json`. Match the timestamps or `ASRPowerBenchmark` signposts to the power trace and account for unequal processing time when integrating energy. The battery percentage is a coarse cross-check. After the run, restore the standard signed build in place.

If wireless Instruments recording stalls, set up Performance Trace in the iPhone's Developer settings. Enable Power Profiler, add the Performance Trace control to Control Center and start it before the test command. Stop it after the final idle block. Export the trace to the Mac and open it in Instruments. [Apple's steps for recording and exporting on the iPhone](https://developer.apple.com/documentation/Xcode/measuring-your-app-s-power-use-with-power-profiler).

In the system power track, read the average battery percentage per hour for each complete workload and its neighboring idle intervals at matched brightness and thermal state. Multiply the workload rate minus the idle rate by the workload duration in hours, then divide by the number of transcriptions. Report both samples per recognizer, together with the idle rates. A small or noisy difference may call for more repeats.

Alternatively, on an already trusted Wi-Fi connection, use the battery diagnostic sampler with Python 3.12 and uv. Start it before the workload command, leave it running until the final idle block has finished, then stop it. The sampler makes read-only queries and prints only power-source fields and timestamps.

```sh
uv run --script scripts/whisper-benchmark/sample-battery-current.py "$device_id" 1000 > battery-current.ndjson
python3 scripts/whisper-benchmark/evaluate-battery-current.py --cumulative power-workloads.json battery-current.ndjson
```

The cumulative method brackets each workload with counter readings in the neighboring idle periods. It subtracts the estimated idle energy over the entire bracket, then divides by the number of transcriptions. It requires the full matched sequence, fresh readings before and after each workload, valid counter progression and two readings within each idle block. For older captures with only current and voltage, omit `--cumulative` to use the previous approximate method. Report the device refresh cadence and the variation between blocks. One-second polling only observes the device's updates as they arrive.
