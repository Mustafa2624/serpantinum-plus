#!/usr/bin/env bash
set -euo pipefail

address="${1:-}"
[[ "$address" =~ ^0x[0-9a-fA-F]+$ ]] || exit 2

# Let the full-screen layer unmap before requesting Hyprland focus.
sleep 0.12
hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:$address' }))" >/dev/null
