#!/usr/bin/env bash
# usage: scan.sh <music_dir> <m3u_out>
# Prints one absolute path per line (sorted) and writes the same list to the m3u file.
dir="${1:-$HOME/Music}"
out="${2:-/tmp/serpantinum-music.m3u}"

if [ ! -d "$dir" ]; then
  : > "$out"
  exit 0
fi

find -L "$dir" -type f \( \
    -iname '*.mp3' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.opus' \
    -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.wav' -o -iname '*.wma' \
  \) 2>/dev/null | LC_ALL=C.UTF-8 sort -f | tee "$out"
