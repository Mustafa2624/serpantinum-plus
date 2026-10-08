#!/usr/bin/env bash
# usage: start-mpv.sh <socket_path>
# Starts a headless mpv, then bridges its IPC socket to stdin/stdout for the shell.
# When the shell goes away (stdin closes) the bridge exits and mpv is stopped too.
sock="${1:?socket path required}"
here="$(cd "$(dirname "$0")" && pwd)"

pkill -f -- "--input-ipc-server=$sock" 2>/dev/null
rm -f "$sock"

mpv \
  --no-config \
  --load-scripts=no \
  --idle=yes \
  --no-video \
  --audio-display=no \
  --force-window=no \
  --no-terminal \
  --keep-open=no \
  --audio-client-name=serpantinum-music \
  --log-file="${XDG_RUNTIME_DIR:-/tmp}/serpantinum-music.log" \
  --input-ipc-server="$sock" \
  </dev/null >/dev/null 2>&1 &
mpv_pid=$!
trap 'kill "$mpv_pid" 2>/dev/null' EXIT

python3 "$here/bridge.py" "$sock"
