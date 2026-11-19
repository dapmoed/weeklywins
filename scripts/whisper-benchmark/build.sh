#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 WORK_DIRECTORY FIXTURE_DIRECTORY" >&2
    exit 2
fi
mkdir -p "$1"
work=$(cd "$1" && pwd)
fixtures=$(cd "$2" && pwd)
script_dir=$(cd "$(dirname "$0")" && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
source_dir="$work/whisper.cpp"
revision=d1be6fde11ac6e0407606b4e42fe72d34add8037
model=ggml-base-q5_1.bin
model_sha=422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898
if [[ ! -d "$source_dir/.git" ]]; then
    git clone --depth 1 --branch v1.9.5 https://github.com/ggml-org/whisper.cpp.git "$source_dir"
fi
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$revision" ]]
[[ -z "$(git -C "$source_dir" status --porcelain --untracked-files=all)" ]]
if [[ ! -f "$work/$model" ]]; then
    curl --fail --location --retry 2 --output "$work/$model.download" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$model"
    mv "$work/$model.download" "$work/$model"
fi
printf '%s  %s\n' "$model_sha" "$work/$model" | shasum -a 256 -c -

cmake -S "$source_dir" -B "$work/ios" \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF \
    -DGGML_METAL=OFF -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF
cmake --build "$work/ios" --target whisper -j 8

repo=$(cd "$script_dir/../.." && pwd)
mkdir -p "$work/hosted"
cd "$work/hosted"
for path in WeeklyWins WeeklyWinsTests WeeklyWinsActionButtonUITests; do
    mkdir -p "$path"
    rsync -a --delete "$repo/$path/" "$path/"
done
mkdir -p WhisperResources
cp "$script_dir/WhisperBenchmarkTests.mm" "$script_dir/WhisperBenchmarkBridge.h" .
cp "$script_dir/ASRPowerBenchmarkTests.swift" .
cp "$work/$model" "$fixtures/ru-one-minute.m4a" "$fixtures/ru-five-minute.m4a" WhisperResources/
cp "$fixtures/fixtures.json" WhisperResources/asr-power-fixtures.json
cp "$source_dir/LICENSE" WhisperResources/whisper.cpp-LICENSE.txt
printf '{"revision":"%s","sha256":"%s","bytes":%s}\n' \
    "$revision" "$model_sha" "$(stat -f %z "$work/$model")" > WhisperResources/whisper-build.json
cp "$repo/project.yml" project.yml
cat > benchmark.yml <<YAML
include:
  - project.yml
targets:
  WeeklyWinsTests:
    sources:
      - path: WhisperBenchmarkTests.mm
      - path: ASRPowerBenchmarkTests.swift
      - path: WhisperResources
        buildPhase: resources
    settings:
      base:
        CLANG_ENABLE_OBJC_ARC: YES
        SWIFT_OBJC_BRIDGING_HEADER: WhisperBenchmarkBridge.h
        GCC_OPTIMIZATION_LEVEL: 3
        HEADER_SEARCH_PATHS:
          - "$source_dir/include"
          - "$source_dir/ggml/include"
        OTHER_LDFLAGS:
          - "$work/ios/src/libwhisper.a"
          - "$work/ios/ggml/src/libggml.a"
          - "$work/ios/ggml/src/libggml-cpu.a"
          - "$work/ios/ggml/src/libggml-base.a"
          - "$work/ios/ggml/src/ggml-blas/libggml-blas.a"
    dependencies:
      - sdk: Accelerate.framework
      - sdk: AVFoundation.framework
YAML
xcodegen generate --spec benchmark.yml
xcodebuild -project WeeklyWins.xcodeproj -scheme WeeklyWins -destination 'generic/platform=iOS' \
    -derivedDataPath "$work/hosted-derived" -allowProvisioningUpdates build-for-testing
