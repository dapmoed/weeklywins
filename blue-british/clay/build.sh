#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=${LEMO_OPUSCAR_HOME:-"$HOME/lemo-opuscar"}
mkdir -p "$HERE/out"
cd "$LIB"
"$LIB/.venv/bin/python" "$HERE/../audio.py" "$HERE"
node core/render/video.mjs "$HERE" --fps 24 --workers 3 --out "$HERE/out/video.mp4"
sh core/render/mux.sh "$HERE/out/video.mp4" "$HERE/out/mix.wav" "$HERE/kuzya.mp4" 24 0
node core/render/still.mjs "$HERE" 2.2 6.1 14.5 24 28.5 32.8
cp "$HERE/stills/t_2.2.jpg" "$HERE/poster.jpg"
