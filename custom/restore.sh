#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
install_dir="${SERPANTINUM_INSTALL_DIR:-$data_home/serpantinum}"

if [[ ! -d "$repo_root/src" ]]; then
    printf 'Fork source directory not found: %s/src\n' "$repo_root" >&2
    exit 1
fi
if [[ ! -d "$install_dir/src" ]]; then
    printf 'Serpantinum install source directory not found: %s/src\n' "$install_dir" >&2
    printf 'Set SERPANTINUM_INSTALL_DIR to the installation directory and retry.\n' >&2
    exit 1
fi

cp -a -- "$repo_root/src/." "$install_dir/src/"
printf 'Restored fork source files to %s/src\n' "$install_dir"
