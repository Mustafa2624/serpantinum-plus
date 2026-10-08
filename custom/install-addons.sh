#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: bash custom/install-addons.sh [--yes] [--dry-run] [--uninstall] [--no-restart]

Options:
  --yes          Skip the confirmation prompt.
  --dry-run      Check compatibility and summarize changes without writing.
  --uninstall   Restore the files saved by the last successful add-on install.
  --no-restart  Do not stop and start serpantinumd after changes.
  --help         Show this help.

If this script is fetched alone, it downloads this fork's source archive to a
private temporary directory and removes it on exit.
USAGE
}

for arg in "$@"; do
    if [[ "$arg" == --help ]]; then usage; exit 0; fi
done
original_args=("$@")

mode=install
yes=false
no_restart=false
while (($#)); do
    case "$1" in
        --yes) yes=true ;;
        --dry-run) [[ "$mode" == install ]] || { usage >&2; exit 2; }; mode=dry-run ;;
        --uninstall) [[ "$mode" == install ]] || { usage >&2; exit 2; }; mode=uninstall ;;
        --no-restart) no_restart=true ;;
        --help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

source_path="${BASH_SOURCE[0]}"
source_dir="$(cd -- "$(dirname -- "$source_path")" 2>/dev/null && pwd -P || true)"
if [[ ! -f "$source_dir/patches/addons.patch" || ! -d "$source_dir/overlay/src" ]]; then
    bootstrap_dir="$(mktemp -d "${TMPDIR:-/tmp}/serpantinum-plus-addons.XXXXXX")"
    trap 'rm -rf -- "$bootstrap_dir"' EXIT
    archive_url="${SERPANTINUM_PLUS_TARBALL:-https://github.com/Mustafa2624/serpantinum-plus/archive/refs/heads/master.tar.gz}"
    if ! curl -fsSL "$archive_url" -o "$bootstrap_dir/repo.tar.gz"; then
        printf 'Could not download Serpantinum Plus source archive: %s\n' "$archive_url" >&2
        exit 1
    fi
    mkdir "$bootstrap_dir/extracted"
    if ! tar -xzf "$bootstrap_dir/repo.tar.gz" --strip-components=1 -C "$bootstrap_dir/extracted"; then
        printf 'Could not extract the Serpantinum Plus source archive.\n' >&2
        exit 1
    fi
    if [[ ! -f "$bootstrap_dir/extracted/custom/patches/addons.patch" ]]; then
        printf 'Downloaded archive does not contain the add-on installer files.\n' >&2
        exit 1
    fi
    bash "$bootstrap_dir/extracted/custom/install-addons.sh" "${original_args[@]}"
    exit $?
fi

patch_file="$source_dir/patches/addons.patch"
overlay_dir="$source_dir/overlay"

if [[ -n "${SERPANTINUM_DIR:-}" ]]; then
    source_dir_target="$(realpath -m -- "$SERPANTINUM_DIR")"
    install_dir="$(dirname -- "$source_dir_target")"
else
    install_dir="${SERPANTINUM_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum}"
    install_dir="$(realpath -m -- "$install_dir")"
    source_dir_target="$install_dir/src"
fi
[[ -d "$source_dir_target" ]] || {
    printf 'Serpantinum source directory not found: %s\n' "$source_dir_target" >&2
    exit 1
}

state_root="$(realpath -m -- "${XDG_STATE_HOME:-$HOME/.local/state}/serpantinum-plus-addons")"
active_file="$state_root/active-backup"
upstream_commit="8c3ea64"

# SHA-256 fingerprints of the integration files at supported upstream commit 8c3ea64.
declare -A upstream_sha=(
    [src/quickshell/bar/BarModuleRegistry.qml]=0562b5fcaf81cc315125b71403fda2573c1bad466c9e56520005b97b6d0cd186
    [src/quickshell/bar/qmldir]=729048743ed9e62cb7a1d5e3af0dedc93fa4e2196779cb7e364922360f646de9
    [src/quickshell/quickactions/Floating.qml]=4a5cb2404510976396d1113ca01a7ee4cf13fbc70dc41d1ebce3f5fdba6bef3b
)
mapfile -t patch_paths < <(sed -n 's/^--- a\///p' "$patch_file")
mapfile -t overlay_paths < <(cd "$overlay_dir" && find src -type f -print | sort)

report_dependencies() {
    local missing=()
    for tool in yt-dlp mpv ffmpeg; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if ((${#missing[@]})); then
        printf 'Missing dependencies: %s\nInstall them with: sudo pacman -S --needed %s\n' \
            "${missing[*]}" "${missing[*]}"
    else
        printf 'Dependencies found: yt-dlp, mpv, ffmpeg\n'
    fi
}

restart_shell() {
    [[ "$no_restart" == true ]] && return 0
    local daemon=""
    if command -v serpantinumd >/dev/null 2>&1; then
        daemon="serpantinumd"
    elif [[ -x "$HOME/.local/bin/serpantinumd" ]]; then
        daemon="$HOME/.local/bin/serpantinumd"
    else
        printf 'Add-ons changed, but serpantinumd is not on PATH; restart the shell manually.\n'
        return 0
    fi
    "$daemon" stop >/dev/null 2>&1 || true
    "$daemon" start
}

if [[ "$mode" == uninstall ]]; then
    if [[ ! -f "$active_file" ]]; then
        printf 'No managed add-on installation is recorded; nothing to uninstall.\n'
        exit 0
    fi
    backup_dir="$(<"$active_file")"
    [[ -d "$backup_dir" && -f "$backup_dir/install-dir" && "$(<"$backup_dir/install-dir")" == "$install_dir" ]] || {
        printf 'The recorded backup does not belong to %s; refusing to restore.\n' "$install_dir" >&2
        exit 1
    }
    manifest="$backup_dir/manifest.tsv"
    [[ -f "$manifest" ]] || { printf 'Backup manifest missing: %s\n' "$manifest" >&2; exit 1; }
    while IFS=$'\t' read -r had_original rel; do
        [[ "$rel" == src/* ]] || { printf 'Unsafe backup path: %s\n' "$rel" >&2; exit 1; }
        if [[ "$had_original" == present && ! -e "$backup_dir/files/$rel" ]]; then
            printf 'Backup file missing: %s\n' "$backup_dir/files/$rel" >&2
            exit 1
        fi
    done < "$manifest"
    if [[ "$yes" != true ]]; then
        read -r -p 'Uninstall Serpantinum Plus add-ons and restore the backup? [y/N] ' answer </dev/tty || answer=""
        [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]] || { printf 'Cancelled.\n'; exit 0; }
    fi
    while IFS=$'\t' read -r had_original rel; do
        if [[ "$had_original" == present ]]; then
            mkdir -p -- "$install_dir/$(dirname -- "$rel")"
            cp -a -- "$backup_dir/files/$rel" "$install_dir/$rel"
        else
            rm -f -- "$install_dir/$rel"
        fi
    done < "$manifest"
    rm -f -- "$active_file"
    printf 'Add-ons removed; restored files from %s.\n' "$backup_dir"
    restart_shell
    exit 0
fi

is_complete() {
    local file
    grep -Fq 'faces/music/MusicFace.qml' "$source_dir_target/quickshell/bar/BarModuleRegistry.qml" || return 1
    grep -Fq 'faces/expose/ExposeFace.qml' "$source_dir_target/quickshell/bar/BarModuleRegistry.qml" || return 1
    grep -Fq 'faces/ytdl/YtdlFace.qml' "$source_dir_target/quickshell/bar/BarModuleRegistry.qml" || return 1
    grep -Fq 'singleton ExposeState' "$source_dir_target/quickshell/bar/qmldir" || return 1
    for rel in "${overlay_paths[@]}"; do
        file="$source_dir_target/${rel#src/}"
        [[ -f "$file" ]] && cmp -s "$overlay_dir/$rel" "$file" || return 1
    done
    grep -Fq 'actions/Game.qml' "$source_dir_target/quickshell/quickactions/Floating.qml" || return 1
    grep -Fq 'actions/DropShelf.qml' "$source_dir_target/quickshell/quickactions/Floating.qml" || return 1
    grep -Fq 'actions/Music.qml' "$source_dir_target/quickshell/quickactions/Floating.qml" || return 1
}

if is_complete; then
    printf 'Serpantinum Plus additions are already present; nothing to do.\n'
    report_dependencies
    exit 0
fi

base_matches=true
for rel in "${!upstream_sha[@]}"; do
    [[ -f "$source_dir_target/${rel#src/}" ]] || { base_matches=false; break; }
    actual="$(sha256sum "$source_dir_target/${rel#src/}" | cut -d' ' -f1)"
    if [[ "$actual" != "${upstream_sha[$rel]}" ]]; then base_matches=false; break; fi
done
if [[ "$base_matches" != true ]]; then
    printf 'This install does not match supported upstream commit %s and the add-on patch is not already complete. No files were changed.\n' "$upstream_commit" >&2
    exit 1
fi

if [[ -f "$active_file" ]]; then
    previous_backup="$(<"$active_file")"
    [[ -f "$previous_backup/manifest.tsv" && "$(<"$previous_backup/install-dir")" == "$install_dir" ]] || {
        printf 'Existing add-on backup state is invalid; refusing to replace it.\n' >&2
        exit 1
    }
fi

patch --batch --forward --fuzz=0 -p1 -d "$install_dir" --dry-run -i "$patch_file" >/dev/null || {
    printf 'Integration patch cannot apply to the supported source. No files were changed.\n' >&2
    exit 1
}
for rel in "${overlay_paths[@]}"; do
    dest="$source_dir_target/${rel#src/}"
    if [[ -e "$dest" && ! -f "$dest" ]]; then
        printf 'Unexpected overlay destination; refusing to overwrite: %s\n' "$dest" >&2
        exit 1
    fi
done

printf 'Dry-run summary for %s (upstream %s):\n' "$install_dir" "$upstream_commit"
printf '  Patch 3 integration files; add %d module files.\n' "${#overlay_paths[@]}"
report_dependencies
if [[ "$mode" == dry-run ]]; then exit 0; fi
if [[ "$yes" != true ]]; then
    read -r -p 'Continue? [y/N] ' answer </dev/tty || answer=""
    [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]] || { printf 'Cancelled.\n'; exit 0; }
fi

mkdir -p -- "$state_root/backups"
backup_dir="$state_root/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
rollback_dir="$(mktemp -d "${TMPDIR:-/tmp}/serpantinum-plus-rollback.XXXXXX")"
cleanup_rollback() { rm -rf -- "$rollback_dir"; }
trap cleanup_rollback EXIT
mkdir -m 700 -- "$backup_dir" "$backup_dir/files"
printf '%s\n' "$install_dir" > "$backup_dir/install-dir"
: > "$backup_dir/manifest.tsv"
all_paths=()
declare -A seen=()
for rel in "${patch_paths[@]}" "${overlay_paths[@]}"; do
    [[ -n "${seen[$rel]:-}" ]] && continue
    seen[$rel]=1
    all_paths+=("$rel")
done

declare -A previous_absent=()
if [[ -f "$active_file" ]]; then
    while IFS=$'\t' read -r had_original rel; do
        [[ "$had_original" == absent ]] && previous_absent["$rel"]=1 || true
    done < "$previous_backup/manifest.tsv"
fi
for rel in "${all_paths[@]}"; do
    dest="$install_dir/$rel"
    if [[ -e "$dest" || -L "$dest" ]]; then
        mkdir -p -- "$rollback_dir/files/$(dirname -- "$rel")"
        cp -a -- "$dest" "$rollback_dir/files/$rel"
        printf 'present\t%s\n' "$rel" >> "$rollback_dir/manifest.tsv"
        if [[ -n "${previous_absent[$rel]:-}" ]]; then
            printf 'absent\t%s\n' "$rel" >> "$backup_dir/manifest.tsv"
        elif [[ -f "$dest" ]] && [[ -f "$overlay_dir/$rel" ]] && cmp -s "$dest" "$overlay_dir/$rel"; then
            printf 'absent\t%s\n' "$rel" >> "$backup_dir/manifest.tsv"
        else
            mkdir -p -- "$backup_dir/files/$(dirname -- "$rel")"
            cp -a -- "$dest" "$backup_dir/files/$rel"
            printf 'present\t%s\n' "$rel" >> "$backup_dir/manifest.tsv"
        fi
    else
        printf 'absent\t%s\n' "$rel" >> "$backup_dir/manifest.tsv"
        printf 'absent\t%s\n' "$rel" >> "$rollback_dir/manifest.tsv"
    fi
done

rollback_changes() {
    local had rel
    while IFS=$'\t' read -r had rel; do
        [[ -n "$rel" ]] || continue
        if [[ "$had" == present ]]; then
            mkdir -p -- "$install_dir/$(dirname -- "$rel")"
            cp -a -- "$rollback_dir/files/$rel" "$install_dir/$rel"
        else
            rm -f -- "$install_dir/$rel"
        fi
    done < "$rollback_dir/manifest.tsv"
    rm -rf -- "$backup_dir"
}
if ! patch --batch --forward --fuzz=0 -p1 -d "$install_dir" -i "$patch_file"; then
    rollback_changes
    printf 'Patch failed; restored all touched files from the operation backup.\n' >&2
    exit 1
fi
if ! cp -a -- "$overlay_dir/src/." "$source_dir_target/"; then
    rollback_changes
    printf 'Overlay copy failed; restored all touched files from the operation backup.\n' >&2
    exit 1
fi
printf '%s\n' "$backup_dir" > "$active_file"
printf 'Installed Serpantinum Plus additions: 3 integration patches and %d files.\n' "${#overlay_paths[@]}"
printf 'Backup: %s\n' "$backup_dir"
report_dependencies
restart_shell
