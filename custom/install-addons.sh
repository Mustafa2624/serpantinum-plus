#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: custom/install-addons.sh [--dry-run | --uninstall] [--install-dir DIR]

Install Serpantinum Plus add-ons over an existing Serpantinum source tree.
The installer applies the checked-in integration patch and copies the add-on
modules. It never replaces the complete src/ directory.

Options:
  --dry-run        Check patch applicability and report planned file copies.
  --uninstall      Restore files backed up by the last successful install.
  --install-dir    Serpantinum installation directory (default: ~/.local/share/serpantinum).
  -h, --help       Show this help.
USAGE
}

mode=install
install_dir="${SERPANTINUM_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum}"
while (($#)); do
    case "$1" in
        --dry-run) [[ "$mode" == install ]] || { usage >&2; exit 2; }; mode=dry-run ;;
        --uninstall) [[ "$mode" == install ]] || { usage >&2; exit 2; }; mode=uninstall ;;
        --install-dir)
            (($# >= 2)) || { usage >&2; exit 2; }
            install_dir="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"
install_dir="$(realpath -m -- "$install_dir")"
[[ -d "$install_dir/src" ]] || { printf 'Expected an existing Serpantinum source directory at %s/src\n' "$install_dir" >&2; exit 1; }

state_root="${XDG_STATE_HOME:-$HOME/.local/state}/serpantinum-plus-addons"
state_root="$(realpath -m -- "$state_root")"
active_file="$state_root/active-backup"
patch_file="$script_dir/patches/addons.patch"
overlay_dir="$script_dir/overlay"
backup_dir=""
transaction_active=false

rollback_on_error() {
    local status=$?
    if [[ "$transaction_active" == true && $status -ne 0 && -f "$backup_dir/manifest.tsv" ]]; then
        printf 'Operation failed; restoring the pre-add-on files.\n' >&2
        while IFS=$'\t' read -r had_original rel; do
            [[ -n "$rel" ]] || continue
            if [[ "$had_original" == present ]]; then
                mkdir -p -- "$install_dir/$(dirname -- "$rel")"
                cp -a -- "$backup_dir/files/$rel" "$install_dir/$rel"
            else
                rm -f -- "$install_dir/$rel"
            fi
        done < "$backup_dir/manifest.tsv"
        rm -f -- "$active_file"
        rm -rf -- "$backup_dir"
    fi
    exit "$status"
}
trap rollback_on_error EXIT

if [[ "$mode" == uninstall ]]; then
    [[ -f "$active_file" ]] || { printf 'No add-on installation is recorded at %s\n' "$install_dir" >&2; exit 1; }
    backup_dir="$(<"$active_file")"
    [[ -d "$backup_dir" && -f "$backup_dir/install-dir" && "$(<"$backup_dir/install-dir")" == "$install_dir" ]] || {
        printf 'The recorded backup does not belong to %s; refusing to restore.\n' "$install_dir" >&2; exit 1;
    }
    manifest="$backup_dir/manifest.tsv"
    [[ -f "$manifest" ]] || { printf 'Backup manifest missing: %s\n' "$manifest" >&2; exit 1; }
    while IFS=$'\t' read -r had_original rel; do
        [[ -n "$rel" ]] || continue
        case "$rel" in src/*) ;; *) printf 'Unsafe backup path in manifest: %s\n' "$rel" >&2; exit 1 ;; esac
        if [[ "$had_original" == present ]]; then
            [[ -e "$backup_dir/files/$rel" ]] || { printf 'Backup file missing: %s\n' "$backup_dir/files/$rel" >&2; exit 1; }
        fi
    done < "$manifest"
    while IFS=$'\t' read -r had_original rel; do
        [[ -n "$rel" ]] || continue
        if [[ "$had_original" == present ]]; then
            mkdir -p -- "$install_dir/$(dirname -- "$rel")"
            cp -a -- "$backup_dir/files/$rel" "$install_dir/$rel"
        else
            rm -f -- "$install_dir/$rel"
        fi
    done < "$manifest"
    rm -f -- "$active_file"
    printf 'Restored the pre-add-on files in %s. Backup retained at %s\n' "$install_dir" "$backup_dir"
    exit 0
fi

if [[ -f "$active_file" ]]; then
    printf 'An add-on installation is already recorded. Run --uninstall before reinstalling or updating it.\n' >&2
    exit 1
fi
[[ -f "$patch_file" && -d "$overlay_dir/src" ]] || { printf 'Add-on patch or overlay is missing from this checkout.\n' >&2; exit 1; }

mapfile -t patch_paths < <(sed -n 's/^--- a\///p' "$patch_file")
mapfile -t overlay_paths < <(cd "$overlay_dir" && find src -type f -print | sort)
((${#patch_paths[@]} > 0 && ${#overlay_paths[@]} > 0)) || { printf 'Patch and overlay must both contain files.\n' >&2; exit 1; }
for rel in "${patch_paths[@]}" "${overlay_paths[@]}"; do
    case "$rel" in src/*) ;; *) printf 'Unsafe add-on path: %s\n' "$rel" >&2; exit 1 ;; esac
done
for rel in "${overlay_paths[@]}"; do
    if [[ -e "$install_dir/$rel" || -L "$install_dir/$rel" ]]; then
        printf 'Overlay destination already exists; refusing to overwrite: %s\n' "$install_dir/$rel" >&2
        exit 1
    fi
done

patch --batch --forward --fuzz=0 -p1 -d "$install_dir" --dry-run -i "$patch_file" >/dev/null || {
    printf 'Integration patch does not match this Serpantinum source. No files were changed.\n' >&2
    exit 1
}

if [[ "$mode" == dry-run ]]; then
    printf 'Dry run OK for %s\n' "$install_dir"
    printf 'Would patch: %s\n' "${patch_paths[*]}"
    printf 'Would add %d overlay files.\n' "${#overlay_paths[@]}"
    for tool in yt-dlp mpv ffmpeg; do
        command -v "$tool" >/dev/null 2>&1 || printf 'Dependency not found on PATH: %s\n' "$tool"
    done
    exit 0
fi

mkdir -p -- "$state_root/backups"
backup_dir="$state_root/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
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
for rel in "${all_paths[@]}"; do
    if [[ -e "$install_dir/$rel" || -L "$install_dir/$rel" ]]; then
        mkdir -p -- "$backup_dir/files/$(dirname -- "$rel")"
        cp -a -- "$install_dir/$rel" "$backup_dir/files/$rel"
        printf 'present\t%s\n' "$rel" >> "$backup_dir/manifest.tsv"
    else
        printf 'absent\t%s\n' "$rel" >> "$backup_dir/manifest.tsv"
    fi
done

transaction_active=true
if ! patch --batch --forward --fuzz=0 -p1 -d "$install_dir" -i "$patch_file"; then
    printf 'Patch failed; no add-on changes were kept.\n' >&2
    exit 1
fi
cp -a -- "$overlay_dir/src/." "$install_dir/src/"
mkdir -p -- "$state_root"
printf '%s\n' "$backup_dir" > "$active_file"
transaction_active=false
printf 'Installed add-ons into %s\nBackup: %s\n' "$install_dir" "$backup_dir"
for tool in yt-dlp mpv ffmpeg; do
    command -v "$tool" >/dev/null 2>&1 || printf 'Dependency not found on PATH: %s\n' "$tool"
done
