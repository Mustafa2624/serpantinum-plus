#!/usr/bin/env bash
set -euo pipefail

step=0
if [[ "${SERPANTINUM_ADDONS_BOOTSTRAPPED:-0}" == 1 ]]; then step=3; fi
step_total=6
run_started_ms="${SERPANTINUM_ADDONS_STARTED_MS:-$(date +%s%3N)}"

elapsed_ms() { printf '%s' "$(( $(date +%s%3N) - $1 ))"; }

run_step() {
    local label="$1" failure_state="$2" heartbeat_text="$3"; shift 3
    local index=$((step + 1)) start heartbeat_pid status elapsed
    step=$((step + 1))
    printf '[%d/%d] %s\n' "$index" "$step_total" "$label"
    start="$(date +%s%3N)"
    (
        local ticks=0
        while sleep 5; do
            ticks=$((ticks + 1))
            if [[ "$label" == Downloading* ]] && [[ -t 1 ]] && ((ticks < 3)); then continue; fi
            printf '%s\n' "$heartbeat_text"
        done
    ) &
    heartbeat_pid=$!
    status=0
    "$@" || status=$?
    kill "$heartbeat_pid" 2>/dev/null || true
    wait "$heartbeat_pid" 2>/dev/null || true
    elapsed="$(elapsed_ms "$start")"
    if ((status == 0)); then
        printf 'done (%.1fs)\n' "$(awk "BEGIN {print $elapsed / 1000}")"
        return 0
    fi
    printf 'Step %d failed (exit %d): %s\n' "$index" "$status" "$failure_state" >&2
    return "$status"
}

download_archive() {
    local url="$1" output="$2"
    if [[ -t 1 ]]; then
        curl --fail --location --show-error --progress-bar --connect-timeout 10 --retry 3 --retry-delay 1 "$url" -o "$output"
    else
        curl --fail --location --show-error --silent --connect-timeout 10 --retry 3 --retry-delay 1 "$url" -o "$output"
    fi
}

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
if [[ -n "${SERPANTINUM_DIR:-}" ]]; then
    source_dir_target="$(realpath -m -- "$SERPANTINUM_DIR")"
    install_dir="$(dirname -- "$source_dir_target")"
else
    install_dir="${SERPANTINUM_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum}"
    install_dir="$(realpath -m -- "$install_dir")"
    source_dir_target="$install_dir/src"
fi
check_target() {
    [[ -d "$source_dir_target" ]] || {
        printf 'Serpantinum source directory not found: %s\n' "$source_dir_target" >&2
        return 1
    }
}
if [[ "${SERPANTINUM_ADDONS_BOOTSTRAPPED:-0}" != 1 ]]; then
    run_step 'Checking your Serpantinum install...' 'No files were changed.' 'Still checking...' check_target
fi

if [[ ! -f "$source_dir/patches/addons.patch" || ! -d "$source_dir/overlay/src" ]]; then
    if ! bootstrap_dir="$(mktemp -d "${TMPDIR:-/tmp}/serpantinum-plus-addons.XXXXXX")"; then
        printf 'Step 2 failed: could not create a temporary download directory. Nothing was changed.\n' >&2
        exit 1
    fi
    trap 'rm -rf -- "$bootstrap_dir"' EXIT
    archive_url="${SERPANTINUM_PLUS_TARBALL:-https://github.com/Mustafa2624/serpantinum-plus/archive/refs/heads/master.tar.gz}"
    printf 'Before downloading: I will fetch the Serpantinum Plus installer archive; nothing has been changed yet. Size is not published.\n'
    run_step 'Downloading Serpantinum Plus (size unknown)...' 'Nothing was changed.' 'Still downloading...' download_archive "$archive_url" "$bootstrap_dir/repo.tar.gz"
    # shellcheck disable=SC2329
    unpack_bootstrap() {
        mkdir -p "$bootstrap_dir/extracted" || return 1
        tar -xzf "$bootstrap_dir/repo.tar.gz" --strip-components=1 -C "$bootstrap_dir/extracted"
    }
    run_step 'Unpacking...' 'Nothing was changed.' 'Still unpacking...' unpack_bootstrap
    if [[ ! -f "$bootstrap_dir/extracted/custom/patches/addons.patch" ]]; then
        printf 'Step 3 failed: archive is missing add-on installer files. Nothing was changed.\n' >&2
        exit 1
    fi
    SERPANTINUM_ADDONS_STARTED_MS="$run_started_ms" SERPANTINUM_ADDONS_BOOTSTRAPPED=1 bash "$bootstrap_dir/extracted/custom/install-addons.sh" "${original_args[@]}"
    exit $?
fi

if [[ "${SERPANTINUM_ADDONS_BOOTSTRAPPED:-0}" != 1 ]]; then
    run_step 'Using the local Serpantinum Plus checkout...' 'Nothing was changed.' 'Still checking...' true
    run_step 'Unpacking... not needed for a local checkout.' 'Nothing was changed.' 'Still checking...' true
fi

patch_file="$source_dir/patches/addons.patch"
overlay_dir="$source_dir/overlay"

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
        run_step 'Checking what will be restored...' 'Nothing was changed.' 'Still checking...' true
        printf 'No managed add-on installation is recorded; nothing to uninstall.\n'
        exit 0
    fi
    backup_dir="$(<"$active_file")"
    manifest="$backup_dir/manifest.tsv"
    # shellcheck disable=SC2329
    validate_uninstall() {
        [[ -d "$backup_dir" && -f "$backup_dir/install-dir" && "$(<"$backup_dir/install-dir")" == "$install_dir" ]] || {
            printf 'The recorded backup does not belong to %s, or its metadata is missing.\n' "$install_dir" >&2
            return 1
        }
        [[ -f "$manifest" ]] || { printf 'Backup manifest missing: %s\n' "$manifest" >&2; return 1; }
        local had rel
        while IFS=$'\t' read -r had rel; do
            [[ "$rel" == src/* ]] || { printf 'Unsafe backup path: %s\n' "$rel" >&2; return 1; }
            if [[ "$had" == present && ! -e "$backup_dir/files/$rel" ]]; then
                printf 'Backup file missing: %s\n' "$backup_dir/files/$rel" >&2
                return 1
            fi
        done < "$manifest"
    }
    run_step 'Checking what will be restored...' 'No files were changed.' 'Still checking the backup...' validate_uninstall
    printf 'Files to restore:\n'
    while IFS=$'\t' read -r had_original rel; do printf '  %s %s\n' "$([[ "$had_original" == present ]] && printf 'RESTORE' || printf 'REMOVE ')" "$rel"; done < "$manifest"
    if [[ "$yes" != true ]]; then
        read -r -p 'Uninstall Serpantinum Plus add-ons and restore the backup? [y/N] ' answer </dev/tty || answer=""
        [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]] || { printf 'Cancelled.\n'; exit 0; }
    fi
    # shellcheck disable=SC2329
    restore_backup() {
        local had_original rel
        while IFS=$'\t' read -r had_original rel; do
            if [[ "$had_original" == present ]]; then
                mkdir -p -- "$install_dir/$(dirname -- "$rel")" || return 1
                cp -a -- "$backup_dir/files/$rel" "$install_dir/$rel" || return 1
            else
                rm -f -- "$install_dir/$rel" || return 1
            fi
        done < "$manifest"
        rm -f -- "$active_file"
    }
    run_step 'Restoring the backup...' 'Restore stopped early; the backup is still at the path above.' 'Still restoring...' restore_backup
    printf 'Add-ons removed; restored files from %s.\n' "$backup_dir"
    run_step 'Restarting the shell...' 'Files are restored; restart the shell manually.' 'Still restarting...' restart_shell
    printf 'Uninstall complete. Backup retained at %s. Total time: %.1fs\n' "$backup_dir" "$(awk "BEGIN {print $(elapsed_ms "$run_started_ms") / 1000}")"
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

show_group() {
    local name="$1"; shift
    local pattern rel
    printf '%s\n' "$name"
    for rel in "${patch_paths[@]}"; do
        for pattern in "$@"; do
            # shellcheck disable=SC2053
            if [[ "$rel" == $pattern ]]; then printf '  PATCH %s\n' "$rel"; break; fi
        done
    done
    for rel in "${overlay_paths[@]}"; do
        for pattern in "$@"; do
            # shellcheck disable=SC2053
            if [[ "$rel" == $pattern ]]; then printf '  ADD   %s\n' "$rel"; break; fi
        done
    done
}

show_file_plan() {
    printf 'Files to change:\n'
    show_group 'Downloader:' 'src/quickshell/bar/BarModuleRegistry.qml' 'src/quickshell/bar/faces/ytdl/*'
    show_group 'Music player:' 'src/quickshell/bar/BarModuleRegistry.qml' 'src/quickshell/quickactions/Floating.qml' 'src/quickshell/bar/faces/music/*' 'src/quickshell/quickactions/actions/Music.qml' 'src/quickshell/quickactions/actions/music/*'
    show_group 'Expose:' 'src/quickshell/bar/BarModuleRegistry.qml' 'src/quickshell/bar/qmldir' 'src/quickshell/bar/ExposeState.qml' 'src/quickshell/bar/faces/expose/*'
    show_group 'Drop shelf:' 'src/quickshell/quickactions/Floating.qml' 'src/quickshell/quickactions/actions/DropShelf.qml'
    show_group 'Snake:' 'src/quickshell/quickactions/Floating.qml' 'src/quickshell/quickactions/actions/Game.qml' 'src/quickshell/quickactions/actions/Model.js'
}

check_changes() {
    if is_complete; then
        printf 'Serpantinum Plus additions are already present; nothing to do.\n'
        return 2
    fi
    local base_matches=true rel actual
    for rel in "${!upstream_sha[@]}"; do
        [[ -f "$source_dir_target/${rel#src/}" ]] || { base_matches=false; break; }
        actual="$(sha256sum "$source_dir_target/${rel#src/}" | cut -d' ' -f1)"
        if [[ "$actual" != "${upstream_sha[$rel]}" ]]; then base_matches=false; break; fi
    done
    if [[ "$base_matches" != true ]]; then
        printf 'This install does not match supported upstream commit %s; no files were changed.\n' "$upstream_commit" >&2
        return 1
    fi
    if [[ -f "$active_file" ]]; then
        previous_backup="$(<"$active_file")"
        [[ -f "$previous_backup/manifest.tsv" && "$(<"$previous_backup/install-dir")" == "$install_dir" ]] || {
            printf 'Existing add-on backup state is invalid; refusing to replace it.\n' >&2
            return 1
        }
    fi
    patch --batch --forward --fuzz=0 -p1 -d "$install_dir" --dry-run -i "$patch_file" >/dev/null || {
        printf 'Integration patch cannot apply; no files were changed.\n' >&2
        return 1
    }
    for rel in "${overlay_paths[@]}"; do
        local dest="$source_dir_target/${rel#src/}"
        if [[ -e "$dest" && ! -f "$dest" ]]; then
            printf 'Unexpected overlay destination; refusing to overwrite: %s\n' "$dest" >&2
            return 1
        fi
    done
    return 0
}

if is_complete; then
    run_step 'Checking what will change...' 'No files were changed.' 'Still checking...' true
    printf 'Serpantinum Plus additions are already present; nothing to do.\n'
    show_file_plan
    printf 'Dry run complete. Nothing was changed.\n'
    report_dependencies
    exit 0
fi
run_step 'Checking what will change...' 'No files were changed.' 'Still checking...' check_changes
show_file_plan
report_dependencies
if [[ "$mode" == dry-run ]]; then printf 'Dry run complete. Nothing was changed.\n'; exit 0; fi
if [[ "$yes" != true ]]; then
    read -r -p 'Continue? [y/N] ' answer </dev/tty || answer=""
    [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]] || { printf 'Cancelled.\n'; exit 0; }
fi

backup_dir="$state_root/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
perform_install() {
    mkdir -p -- "$state_root/backups" || { printf 'Could not create backup directory; no install files were changed.\n' >&2; return 1; }
    rollback_dir="$(mktemp -d "${TMPDIR:-/tmp}/serpantinum-plus-rollback.XXXXXX")" || { printf 'Could not create rollback storage; no install files were changed.\n' >&2; return 1; }
    trap 'rm -rf -- "$rollback_dir"' EXIT
    if ! mkdir -m 700 -- "$backup_dir" "$backup_dir/files" ||
        ! printf '%s\n' "$install_dir" > "$backup_dir/install-dir" ||
        ! : > "$backup_dir/manifest.tsv"; then
        rm -rf -- "$backup_dir"
        printf 'Could not prepare the backup; no install files were changed.\n' >&2
        return 1
    fi
    local all_paths=() rel had dest
    local -A seen=() previous_absent=()
    for rel in "${patch_paths[@]}" "${overlay_paths[@]}"; do
        [[ -n "${seen[$rel]:-}" ]] && continue
        seen[$rel]=1
        all_paths+=("$rel")
    done
    if [[ -f "$active_file" ]]; then
        while IFS=$'\t' read -r had rel; do
            [[ "$had" == absent ]] && previous_absent["$rel"]=1 || true
        done < "$previous_backup/manifest.tsv"
    fi
    for rel in "${all_paths[@]}"; do
        dest="$install_dir/$rel"
        if [[ -e "$dest" || -L "$dest" ]]; then
            if ! mkdir -p -- "$rollback_dir/files/$(dirname -- "$rel")" ||
                ! cp -a -- "$dest" "$rollback_dir/files/$rel" ||
                ! printf 'present\t%s\n' "$rel" >> "$rollback_dir/manifest.tsv"; then
                rm -rf -- "$backup_dir"
                printf 'Could not prepare rollback data; no install files were changed.\n' >&2
                return 1
            fi
            if [[ -n "${previous_absent[$rel]:-}" ]]; then
                printf 'absent\t%s\n' "$rel" >> "$backup_dir/manifest.tsv" || { rm -rf -- "$backup_dir"; printf 'Could not write backup manifest; no install files were changed.\n' >&2; return 1; }
            elif [[ -f "$dest" ]] && [[ -f "$overlay_dir/$rel" ]] && cmp -s "$dest" "$overlay_dir/$rel"; then
                printf 'absent\t%s\n' "$rel" >> "$backup_dir/manifest.tsv" || { rm -rf -- "$backup_dir"; printf 'Could not write backup manifest; no install files were changed.\n' >&2; return 1; }
            else
                if ! mkdir -p -- "$backup_dir/files/$(dirname -- "$rel")" ||
                    ! cp -a -- "$dest" "$backup_dir/files/$rel" ||
                    ! printf 'present\t%s\n' "$rel" >> "$backup_dir/manifest.tsv"; then
                    rm -rf -- "$backup_dir"
                    printf 'Could not create backup files; no install files were changed.\n' >&2
                    return 1
                fi
            fi
        else
            if ! printf 'absent\t%s\n' "$rel" >> "$backup_dir/manifest.tsv" ||
                ! printf 'absent\t%s\n' "$rel" >> "$rollback_dir/manifest.tsv"; then
                rm -rf -- "$backup_dir"
                printf 'Could not write backup manifest; no install files were changed.\n' >&2
                return 1
            fi
        fi
    done
    rollback_changes() {
        local had rel failed=false
        while IFS=$'\t' read -r had rel; do
            [[ -n "$rel" ]] || continue
            if [[ "$had" == present ]]; then
                mkdir -p -- "$install_dir/$(dirname -- "$rel")" &&
                    cp -a -- "$rollback_dir/files/$rel" "$install_dir/$rel" || failed=true
            else
                rm -f -- "$install_dir/$rel" || failed=true
            fi
        done < "$rollback_dir/manifest.tsv"
        if [[ "$failed" == true ]]; then
            printf 'Rollback was incomplete; recovery backup retained at %s.\n' "$backup_dir" >&2
            return 1
        fi
        rm -rf -- "$backup_dir"
    }
    if ! patch --batch --forward --fuzz=0 -p1 -d "$install_dir" -i "$patch_file"; then
        rollback_changes || return 1
        printf 'Patch failed; restored all touched files from the operation backup.\n' >&2
        return 1
    fi
    if ! cp -a -- "$overlay_dir/src/." "$source_dir_target/"; then
        rollback_changes || return 1
        printf 'Overlay copy failed; restored all touched files from the operation backup.\n' >&2
        return 1
    fi
    local active_tmp="$active_file.tmp.$$"
    if ! printf '%s\n' "$backup_dir" > "$active_tmp" || ! mv -- "$active_tmp" "$active_file"; then
        rm -f -- "$active_tmp"
        rollback_changes || return 1
        printf 'Could not record backup state; restored all touched files.\n' >&2
        return 1
    fi
    printf 'Installed Serpantinum Plus additions: 3 integration patches and %d files.\n' "${#overlay_paths[@]}"
    report_dependencies
}

run_step "Applying changes (backup: $backup_dir)..." 'Backup restored; see error above.' 'Still applying...' perform_install
run_step 'Restarting the shell...' 'Changes are installed; restart the shell manually.' 'Still restarting...' restart_shell
printf 'Complete. Added/updated the listed files. Backup: %s\nUndo with: bash custom/install-addons.sh --uninstall\nTotal time: %.1fs\n' "$backup_dir" "$(awk "BEGIN {print $(elapsed_ms "$run_started_ms") / 1000}")"
