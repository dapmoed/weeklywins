#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=${LEMO_OPUSCAR_HOME:-"$HOME/lemo-opuscar"}
case "${1:-}" in
  phone) size=1080x1920; query=format=phone; name=kuzya-phone; poster=poster-phone.jpg ;;
  "") size=1920x1080; query=format=landscape; name=kuzya; poster=poster.jpg ;;
  *) printf 'Usage: %s [phone]\n' "$0" >&2; exit 2 ;;
esac
mkdir -p "$HERE/out"
cd "$LIB"
"$LIB/.venv/bin/python" "$HERE/../audio.py" "$HERE"
node core/render/video.mjs "$HERE" --size "$size" --q "$query" --fps 24 --workers 3 --out "$HERE/out/$name.mp4"
sh core/render/mux.sh "$HERE/out/$name.mp4" "$HERE/out/mix.wav" "$HERE/$name.mp4" 24 0
node core/render/still.mjs "$HERE" 2.2 15 21.8 25.4 27.2 29.3 32.4 --size "$size" --q "$query" --prefix "${name}_"
cp "$HERE/stills/${name}_2.2.jpg" "$HERE/$poster"
