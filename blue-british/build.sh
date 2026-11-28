#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=/Users/konstantin.brikalov/lemo-opuscar
export LIB
mkdir -p "$HERE/out" "$HERE/stills"
cd "$LIB"
"$LIB/.venv/bin/python" "$HERE/audio.py"
node core/render/readcheck.mjs "$HERE"
node core/render/video.mjs "$HERE" --fps 24 --workers 2 --out "$HERE/out/video.mp4"
sh core/render/mux.sh "$HERE/out/video.mp4" "$HERE/out/mix.wav" "$HERE/blue-british.mp4" 24 2
node core/render/still.mjs "$HERE" 1.5 6 15 24 32 --prefix frame_ --out "$HERE/stills"
cp "$HERE/stills/frame_1.5.jpg" "$HERE/poster.jpg"
