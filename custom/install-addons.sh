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
            if [[ "$label" == Downloading* ]]; then
                # curl owns the terminal while its progress bar is active. A
                # second writer corrupts its carriage-return updates.
                if [[ -t 1 ]] || ((ticks < 3)); then continue; fi
            fi
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
    local url="$1" output="$2" headers="${2}.headers.$$" errors="${2}.errors.$$"
    local curl_pid status=0 downloaded total percent filled empty bar frames=( '|' '/' '-' '\' ) frame=0
    if [[ -t 1 ]]; then
        curl --fail --location --show-error --silent --connect-timeout 10 --retry 3 --retry-delay 1 \
            --dump-header "$headers" --stderr "$errors" "$url" -o "$output" &
        curl_pid=$!
        while kill -0 "$curl_pid" 2>/dev/null; do
            downloaded="$(stat -c '%s' "$output" 2>/dev/null || printf 0)"
            total="$(awk 'tolower($1) == "content-length:" { n = $2 } END { print n + 0 }' "$headers" 2>/dev/null || printf 0)"
            if ((total > 0)); then
                percent=$((downloaded * 100 / total))
                ((percent > 100)) && percent=100
                filled=$((percent * 28 / 100))
                printf -v bar '%*s' "$filled" ''; bar=${bar// /#}
                empty=$((28 - filled))
                printf -v empty '%*s' "$empty" ''; empty=${empty// /-}
                printf '\rDownloading [%s%s] %3d%% (%s/%s MB)' "$bar" "$empty" "$percent" \
                    "$(awk -v n="$downloaded" 'BEGIN { printf "%.1f", n / 1048576 }')" \
                    "$(awk -v n="$total" 'BEGIN { printf "%.1f", n / 1048576 }')"
            else
                printf '\rDownloading %s (%s MB received)' "${frames[$((frame % ${#frames[@]}))]}" \
                    "$(awk -v n="$downloaded" 'BEGIN { printf "%.1f", n / 1048576 }')"
                frame=$((frame + 1))
            fi
            sleep 0.25
        done
        wait "$curl_pid" || status=$?
        printf '\n'
    else
        curl --fail --location --show-error --silent --connect-timeout 10 --retry 3 --retry-delay 1 \
            --stderr "$errors" "$url" -o "$output" || status=$?
    fi
    if ((status != 0)) && [[ -s "$errors" ]]; then cat "$errors" >&2; fi
    rm -f -- "$headers" "$errors"
    return "$status"
}

usage() {
    cat <<'USAGE'
Usage: bash custom/install-addons.sh [--yes] [--dry-run] [--no-restart]

Options:
  --yes          Skip the confirmation prompt.
  --dry-run      Check compatibility and summarize changes without writing.
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

keybind_file=""
for candidate in \
    "$HOME/.config/hypr/config/keybinds.lua" \
    "$HOME/.config/hypr/config/keybind.lua" \
    "$HOME/.config/hypr/keybinds.lua" \
    "$HOME/.config/hypr/keybind.lua"; do
    if [[ -f "$candidate" ]]; then keybind_file="$candidate"; break; fi
done
check_target() {
    [[ -d "$source_dir_target" ]] || {
        printf 'Serpantinum source directory not found: %s\n' "$source_dir_target" >&2
        return 1
    }
}
if [[ "${SERPANTINUM_ADDONS_BOOTSTRAPPED:-0}" != 1 ]]; then
    run_step 'Checking your Serpantinum install...' 'No files were changed.' 'Checking...' check_target
fi

if [[ ! -f "$source_dir/patches/addons.patch" || ! -f "$source_dir/patches/quickactions-compat.patch" || ! -f "$source_dir/patches/workspace-fixes.patch" || ! -f "$source_dir/patches/music-lifecycle.patch" || ! -d "$source_dir/overlay/src" ]]; then
    if ! bootstrap_dir="$(mktemp -d "${TMPDIR:-/tmp}/serpantinum-plus-addons.XXXXXX")"; then
        printf 'Step 2 failed: could not create a temporary download directory. Nothing was changed.\n' >&2
        exit 1
    fi
    trap 'rm -rf -- "$bootstrap_dir"' EXIT
    archive_url="${SERPANTINUM_PLUS_TARBALL:-https://github.com/Mustafa2624/serpantinum-plus/archive/refs/heads/master.tar.gz}"
    printf 'Before downloading: I will fetch the Serpantinum Plus installer archive; nothing has been changed yet.\n'
    run_step 'Downloading Serpantinum Plus...' 'Nothing was changed.' 'Downloading...' download_archive "$archive_url" "$bootstrap_dir/repo.tar.gz"
    # shellcheck disable=SC2329
    unpack_bootstrap() {
        mkdir -p "$bootstrap_dir/extracted" || return 1
        tar -xzf "$bootstrap_dir/repo.tar.gz" --strip-components=1 -C "$bootstrap_dir/extracted"
    }
    run_step 'Unpacking...' 'Nothing was changed.' 'Unpacking...' unpack_bootstrap
    if [[ ! -f "$bootstrap_dir/extracted/custom/patches/addons.patch" || ! -f "$bootstrap_dir/extracted/custom/patches/music-lifecycle.patch" ]]; then
        printf 'Step 3 failed: archive is missing add-on installer files. Nothing was changed.\n' >&2
        exit 1
    fi
    SERPANTINUM_ADDONS_STARTED_MS="$run_started_ms" SERPANTINUM_ADDONS_BOOTSTRAPPED=1 bash "$bootstrap_dir/extracted/custom/install-addons.sh" "${original_args[@]}"
    exit $?
fi

if [[ "${SERPANTINUM_ADDONS_BOOTSTRAPPED:-0}" != 1 ]]; then
    run_step 'Using the local Serpantinum Plus checkout...' 'Nothing was changed.' 'Checking...' true
    run_step 'Unpacking... not needed for a local checkout.' 'Nothing was changed.' 'Checking...' true
fi

patch_file="$source_dir/patches/addons.patch"
compat_patch_file="$source_dir/patches/quickactions-compat.patch"
workspace_patch_file="$source_dir/patches/workspace-fixes.patch"
music_lifecycle_patch_file="$source_dir/patches/music-lifecycle.patch"
overlay_dir="$source_dir/overlay"
patch_action=apply
compat_patch_action=apply
workspace_patch_action=apply
music_lifecycle_patch_action=apply
legacy_music_registered=false

state_root="$(realpath -m -- "${XDG_STATE_HOME:-$HOME/.local/state}/serpantinum-plus-addons")"
active_file="$state_root/active-backup"
mapfile -t patch_paths < <({ sed -n 's/^--- a\///p' "$patch_file"; sed -n 's/^--- a\///p' "$compat_patch_file"; sed -n 's/^--- a\///p' "$workspace_patch_file"; sed -n 's/^--- a\///p' "$music_lifecycle_patch_file"; } | sort -u)
mapfile -t compat_patch_paths < <(sed -n 's/^--- a\///p' "$compat_patch_file" | sort -u)
mapfile -t workspace_patch_paths < <(sed -n 's/^--- a\///p' "$workspace_patch_file" | sort -u)
mapfile -t music_lifecycle_patch_paths < <(sed -n 's/^--- a\///p' "$music_lifecycle_patch_file" | sort -u)
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

is_complete() {
    local file
    if grep -Fq 'faces/music/MusicFace.qml' "$source_dir_target/quickshell/bar/BarModuleRegistry.qml"; then return 1; fi
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
    grep -Fq '"sysinfo": {' "$source_dir_target/quickshell/bar/BarModuleRegistry.qml" || return 1
    grep -Fq 'target: "quickactions"' "$source_dir_target/quickshell/quickactions/Floating.qml" || return 1
    grep -Fq 'function shortcutToggle()' "$source_dir_target/quickshell/quickactions/Floating.qml" || return 1
    grep -Fq 'function moveOpenedLayout(step)' "$source_dir_target/quickshell/quickactions/Floating.qml" || return 1
    grep -Fq 'property bool shouldLoad' "$source_dir_target/quickshell/quickactions/Floating.qml" || return 1
    grep -Fq 'isMusicModule' "$source_dir_target/quickshell/quickactions/Floating.qml" || return 1
    [[ -n "$keybind_file" ]] && grep -Fq 'SERPANTINUM-PLUS QUICKACTIONS BINDS' "$keybind_file" || return 1
}

keybind_block() {
    local qs_path="$source_dir_target/quickshell/Shell.qml"
    python3 - "$qs_path" <<'PY'
import json, shlex, sys
target = shlex.quote(sys.argv[1])
commands = {
    "toggle": f"qs -p {target} ipc call quickactions toggle",
    "previousSection": f"qs -p {target} ipc call quickactions previousSection",
    "nextSection": f"qs -p {target} ipc call quickactions nextSection",
    "collapse": f"qs -p {target} ipc call quickactions collapse",
    "expand": f"qs -p {target} ipc call quickactions expand",
    "moveForward": f"qs -p {target} ipc call quickactions moveForward",
    "moveBackward": f"qs -p {target} ipc call quickactions moveBackward",
}
binds = [
    ('mainMod .. " + SHIFT + LESS"', 'toggle'),
    ('"ALT + home"', 'previousSection'),
    ('"ALT + end"', 'nextSection'),
    ('"ALT + Prior"', 'collapse'),
    ('"ALT + Next"', 'expand'),
    ('"ALT + CTRL + page_up"', 'moveForward'),
    ('"ALT + CTRL + page_down"', 'moveBackward'),
]
print("\n-- SERPANTINUM-PLUS QUICKACTIONS BINDS (managed by add-on installer)")
for chord, action in binds:
    print(f"hl.bind({chord}, hl.dsp.exec_cmd({json.dumps(commands[action])}))")
print("-- END SERPANTINUM-PLUS QUICKACTIONS BINDS")
PY
}

show_group() {
    local name="$1"; shift
    local pattern rel
    printf '%s\n' "$name"
    for rel in "${patch_paths[@]}"; do
        for pattern in "$@"; do
            # shellcheck disable=SC2053
            if [[ "$rel" == $pattern ]]; then
                local file_patch_action="$patch_action"
                if [[ "$compat_patch_action" == apply ]] && printf '%s\n' "${compat_patch_paths[@]}" | grep -Fxq -- "$rel"; then
                    file_patch_action=apply
                fi
                if [[ "$workspace_patch_action" == apply ]] && printf '%s\n' "${workspace_patch_paths[@]}" | grep -Fxq -- "$rel"; then
                    file_patch_action=apply
                fi
                if [[ "$music_lifecycle_patch_action" == apply ]] && printf '%s\n' "${music_lifecycle_patch_paths[@]}" | grep -Fxq -- "$rel"; then
                    file_patch_action=apply
                fi
                if [[ "$file_patch_action" == present ]]; then
                    printf '  KEEP %s (integration patch already present)\n' "$rel"
                else
                    printf '  OVERWRITE %s (backup: %s/files/%s)\n' "$rel" "$backup_dir" "$rel"
                fi
                break
            fi
        done
    done
    for rel in "${overlay_paths[@]}"; do
        for pattern in "$@"; do
            # shellcheck disable=SC2053
            if [[ "$rel" == $pattern ]]; then
                if [[ -f "$install_dir/$rel" ]] && cmp -s "$install_dir/$rel" "$overlay_dir/$rel"; then
                    printf '  REUSE %s (already matches the add-on)\n' "$rel"
                elif [[ -e "$install_dir/$rel" || -L "$install_dir/$rel" ]]; then
                    printf '  OVERWRITE %s (backup: %s/files/%s)\n' "$rel" "$backup_dir" "$rel"
                else
                    printf '  ADD %s\n' "$rel"
                fi
                break
            fi
        done
    done
}

show_file_plan() {
    printf 'Files to change (existing files are backed up before overwrite):\n'
    show_group 'Downloader:' 'src/quickshell/bar/BarModuleRegistry.qml' 'src/quickshell/bar/faces/ytdl/*'
    show_group 'Music player (Quickactions):' 'src/quickshell/quickactions/Floating.qml' 'src/quickshell/quickactions/actions/Music.qml' 'src/quickshell/quickactions/actions/music/*'
    show_group 'Expose:' 'src/quickshell/bar/BarModuleRegistry.qml' 'src/quickshell/bar/qmldir' 'src/quickshell/bar/ExposeState.qml' 'src/quickshell/bar/faces/expose/*'
    show_group 'Workspace overview button:' 'src/quickshell/bar/faces/workspaces/NumbersFace.qml'
    show_group 'System info:' 'src/quickshell/bar/BarModuleRegistry.qml' 'src/quickshell/bar/faces/sysinfo/*'
    show_group 'Quickactions shortcuts:' 'src/quickshell/quickactions/Floating.qml' 'src/quickshell/singletons/widgetcontrols/FloatingController.qml'
    if [[ "$music_lifecycle_patch_action" == apply ]]; then
        printf 'Quickactions music lifecycle: unload the music player when the sidebar closes; keep it alive while the sidebar remains open.\n'
    else
        printf 'Quickactions music lifecycle fix is already present.\n'
    fi
    show_group 'Drop shelf:' 'src/quickshell/quickactions/Floating.qml' 'src/quickshell/quickactions/actions/DropShelf.qml'
    show_group 'Snake:' 'src/quickshell/quickactions/Floating.qml' 'src/quickshell/quickactions/actions/Game.qml' 'src/quickshell/quickactions/actions/Model.js'
    if [[ "$legacy_music_registered" == true ]]; then
        printf 'Bar Music cleanup: REMOVE legacy registry entry (backup: %s/files/src/quickshell/bar/BarModuleRegistry.qml)\n' "$backup_dir"
    fi
    if [[ -n "$keybind_file" ]]; then
        if grep -Fq 'SERPANTINUM-PLUS QUICKACTIONS BINDS' "$keybind_file"; then
            printf 'Quickactions keybinds: KEEP %s (already installed)\n' "$keybind_file"
        else
            printf 'Quickactions keybinds: APPEND 7 binds to %s (backup: %s)\n' "$keybind_file" "$keybind_backup"
        fi
    fi
}

check_changes() {
    if [[ -z "$keybind_file" ]]; then
        printf 'Could not find a Hyprland config keybinds.lua/keybind.lua file under ~/.config/hypr. No files were changed.\n' >&2
        return 1
    fi
    if is_complete; then
        printf 'Serpantinum Plus additions are already present; nothing to do.\n'
        return 2
    fi
    if [[ -f "$active_file" ]]; then
        previous_backup="$(<"$active_file")"
        [[ -f "$previous_backup/manifest.tsv" && "$(<"$previous_backup/install-dir")" == "$install_dir" ]] || {
            printf 'Existing add-on backup state is invalid; refusing to replace it.\n' >&2
            return 1
        }
    fi
    local patch_output reverse_output
    local registry="$source_dir_target/quickshell/bar/BarModuleRegistry.qml"
    if grep -Fq 'faces/music/MusicFace.qml' "$registry"; then legacy_music_registered=true; fi
    if [[ "$legacy_music_registered" == true ]] &&
       grep -Fq 'faces/expose/ExposeFace.qml' "$registry" &&
       grep -Fq 'faces/ytdl/YtdlFace.qml' "$registry" &&
       grep -Fq 'singleton ExposeState' "$source_dir_target/quickshell/bar/qmldir"; then
        patch_action=present
        printf 'Existing add-on registry detected; it will be kept while removing the old bar music entry.\n'
    elif patch_output="$(patch --batch --forward --fuzz=0 -p1 -d "$install_dir" --dry-run -i "$patch_file" 2>&1)"; then
        patch_action=apply
    elif reverse_output="$(patch --batch --reverse --fuzz=0 -p1 -d "$install_dir" --dry-run -i "$patch_file" 2>&1)"; then
        patch_action=present
        printf 'Integration patch is already applied; it will be kept.\n'
    else
        local conflicts
        conflicts="$(printf '%s\n' "$patch_output" | awk '
            /^checking file / { file = $3 }
            /Hunk .*FAILED/ || /FAILED to open/ { if (file != "") print file }
        ' | sort -u)"
        printf 'The integration patch cannot apply cleanly.\n' >&2
        if [[ -n "$conflicts" ]]; then
            printf 'Conflicting file(s):\n%s\n' "$conflicts" >&2
        else
            printf '%s\n' "$patch_output" >&2
        fi
        printf 'No files were changed. Review those files or update the add-on patch for this Serpantinum version.\n' >&2
        return 1
    fi
    if patch_output="$(patch --batch --forward --fuzz=0 -p1 -d "$install_dir" --dry-run -i "$music_lifecycle_patch_file" 2>&1)"; then
        music_lifecycle_patch_action=apply
    elif reverse_output="$(patch --batch --reverse --fuzz=0 -p1 -d "$install_dir" --dry-run -i "$music_lifecycle_patch_file" 2>&1)"; then
        music_lifecycle_patch_action=present
        printf 'Quickactions music lifecycle fix is already applied; it will be kept.\n'
    else
        printf 'The Quickactions music lifecycle patch cannot apply cleanly. No files were changed.\n' >&2
        printf 'Conflicting file(s):\n' >&2
        printf '%s\n' "$patch_output" | awk '/^checking file / { print "  " $3 }' >&2
        printf '%s\n' "$patch_output" >&2
        return 1
    fi
    if patch_output="$(patch --batch --forward --fuzz=0 -p1 -d "$install_dir" --dry-run -i "$compat_patch_file" 2>&1)"; then
        compat_patch_action=apply
    elif reverse_output="$(patch --batch --reverse --fuzz=0 -p1 -d "$install_dir" --dry-run -i "$compat_patch_file" 2>&1)"; then
        compat_patch_action=present
        printf 'Quickactions and sysinfo compatibility patch is already applied; it will be kept.\n'
    else
        printf 'The quickactions compatibility patch cannot apply cleanly. No files were changed.\n' >&2
        printf 'Conflicting file(s):\n' >&2
        printf '%s\n' "$patch_output" | awk '/^checking file / { print "  " $3 }' >&2
        printf '%s\n' "$patch_output" >&2
        return 1
    fi
    if patch_output="$(patch --batch --forward --fuzz=0 -p1 -d "$install_dir" --dry-run -i "$workspace_patch_file" 2>&1)"; then
        workspace_patch_action=apply
    elif reverse_output="$(patch --batch --reverse --fuzz=0 -p1 -d "$install_dir" --dry-run -i "$workspace_patch_file" 2>&1)"; then
        workspace_patch_action=present
        printf 'Workspace, sysinfo, and Quickactions fixes are already applied; they will be kept.\n'
    else
        local stage_dir stage_ok=true
        stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/serpantinum-plus-patch-check.XXXXXX")" || return 1
        for rel in "${patch_paths[@]}"; do
            if [[ ! -f "$install_dir/$rel" ]] || ! mkdir -p "$stage_dir/$(dirname -- "$rel")" || ! cp -a "$install_dir/$rel" "$stage_dir/$rel"; then
                stage_ok=false
                break
            fi
        done
        if [[ "$stage_ok" == true && "$patch_action" == apply ]]; then
            patch --batch --forward --fuzz=0 -p1 -d "$stage_dir" -i "$patch_file" >/dev/null 2>&1 || stage_ok=false
        fi
        if [[ "$stage_ok" == true && "$compat_patch_action" == apply ]]; then
            patch --batch --forward --fuzz=0 -p1 -d "$stage_dir" -i "$compat_patch_file" >/dev/null 2>&1 || stage_ok=false
        fi
        if [[ "$stage_ok" == true && "$music_lifecycle_patch_action" == apply ]]; then
            patch --batch --forward --fuzz=0 -p1 -d "$stage_dir" -i "$music_lifecycle_patch_file" >/dev/null 2>&1 || stage_ok=false
        fi
        if [[ "$stage_ok" == true ]] && patch_output="$(patch --batch --forward --fuzz=0 -p1 -d "$stage_dir" --dry-run -i "$workspace_patch_file" 2>&1)"; then
            workspace_patch_action=apply
        else
            stage_ok=false
        fi
        rm -rf -- "$stage_dir"
        if [[ "$stage_ok" != true ]]; then
            printf 'The workspace, sysinfo, or Quickactions patch cannot apply to this Serpantinum source. No files were changed.\n' >&2
            printf '%s\n' "${patch_output:-Could not verify patch sequence in a temporary source copy.}" >&2
            return 1
        fi
    fi
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
    run_step 'Checking what will change...' 'No files were changed.' 'Checking...' true
    printf 'Serpantinum Plus additions are already present; nothing to do.\n'
    report_dependencies
    exit 0
fi
run_step 'Checking what will change...' 'No files were changed.' 'Checking...' check_changes
backup_dir="$state_root/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
keybind_backup="$backup_dir/user-config/${keybind_file#"$HOME"/}"
printf 'If you continue, the backup will be saved to: %s\n' "$backup_dir"
show_file_plan
report_dependencies
if [[ "$mode" == dry-run ]]; then printf 'Dry run complete. Nothing was changed.\n'; exit 0; fi
if [[ "$yes" != true ]]; then
    read -r -p 'Continue? [y/N] ' answer </dev/tty || answer=""
    [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]] || { printf 'Cancelled.\n'; exit 0; }
fi

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
    if ! mkdir -p -- "$(dirname -- "$keybind_backup")" || ! cp -a -- "$keybind_file" "$keybind_backup"; then
        rm -rf -- "$backup_dir"
        printf 'Could not back up %s; no install files were changed.\n' "$keybind_file" >&2
        return 1
    fi
    local all_paths=() rel had dest
    local -A seen=()
    local touched_paths=("${overlay_paths[@]}")
    if [[ "$patch_action" == apply || "$compat_patch_action" == apply || "$workspace_patch_action" == apply || "$music_lifecycle_patch_action" == apply ]]; then
        touched_paths=("${patch_paths[@]}" "${overlay_paths[@]}")
    fi
    if [[ "$legacy_music_registered" == true ]]; then touched_paths+=(src/quickshell/bar/BarModuleRegistry.qml); fi
    for rel in "${touched_paths[@]}"; do
        [[ -n "${seen[$rel]:-}" ]] && continue
        seen[$rel]=1
        all_paths+=("$rel")
    done
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
            if [[ -f "$dest" ]] && [[ -f "$overlay_dir/$rel" ]] && cmp -s "$dest" "$overlay_dir/$rel"; then
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
    if [[ "$patch_action" == apply ]]; then
        if ! patch --batch --forward --fuzz=0 -p1 -d "$install_dir" -i "$patch_file"; then
            rollback_changes || return 1
            printf 'Patch failed; restored all touched files from the operation backup.\n' >&2
            return 1
        fi
    else
        printf 'Integration patch already present; skipped applying it.\n'
    fi
    if [[ "$music_lifecycle_patch_action" == apply ]]; then
        if ! patch --batch --forward --fuzz=0 -p1 -d "$install_dir" -i "$music_lifecycle_patch_file"; then
            rollback_changes || return 1
            printf 'Quickactions music lifecycle patch failed; restored all touched files from the operation backup.\n' >&2
            return 1
        fi
    else
        printf 'Quickactions music lifecycle fix already present; skipped applying it.\n'
    fi
    if [[ "$legacy_music_registered" == true ]]; then
        if ! python3 - "$source_dir_target/quickshell/bar/BarModuleRegistry.qml" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
s = p.read_text()
pattern = re.compile(r'(?m)^\s*"music":\s*\{\n\s*name: "music",\n\s*icon: "",\n\s*defaultVariant: "default",\n\s*horizontalFace: "faces/music/MusicFace.qml",\n\s*verticalFace: "faces/music/SideMusicFace.qml"\n\s*\},\n')
updated, count = pattern.subn('', s, count=1)
if count != 1:
    raise SystemExit("recognized old bar music registration was not found exactly")
p.write_text(updated)
PY
        then
            rollback_changes || return 1
            printf 'Could not remove the old bar music entry; restored the backup.\n' >&2
            return 1
        fi
        printf 'Removed the legacy Music entry from the bar registry.\n'
    fi
    if [[ "$compat_patch_action" == apply ]]; then
        if ! patch --batch --forward --fuzz=0 -p1 -d "$install_dir" -i "$compat_patch_file"; then
            rollback_changes || return 1
            printf 'Compatibility patch failed; restored all touched files from the operation backup.\n' >&2
            return 1
        fi
    else
        printf 'Quickactions and sysinfo compatibility patch already present; skipped applying it.\n'
    fi
    if [[ "$workspace_patch_action" == apply ]]; then
        if ! patch --batch --forward --fuzz=0 -p1 -d "$install_dir" -i "$workspace_patch_file"; then
            rollback_changes || return 1
            printf 'Workspace, sysinfo, or Quickactions patch failed; restored all touched files from the operation backup.\n' >&2
            return 1
        fi
    else
        printf 'Workspace, sysinfo, and Quickactions fixes already present; skipped applying them.\n'
    fi
    if ! cp -a -- "$overlay_dir/src/." "$source_dir_target/"; then
        rollback_changes || return 1
        printf 'Overlay copy failed; restored all touched files from the operation backup.\n' >&2
        return 1
    fi
    if ! grep -Fq 'SERPANTINUM-PLUS QUICKACTIONS BINDS' "$keybind_file"; then
        if ! keybind_block >> "$keybind_file"; then
            cp -a -- "$keybind_backup" "$keybind_file"
            rollback_changes || return 1
            printf 'Could not update %s; restored its backup and all add-on files.\n' "$keybind_file" >&2
            return 1
        fi
        printf 'Added 7 Quickactions binds to %s (backup: %s).\n' "$keybind_file" "$keybind_backup"
    fi
    local active_tmp="$active_file.tmp.$$"
    if ! printf '%s\n' "$backup_dir" > "$active_tmp" || ! mv -- "$active_tmp" "$active_file"; then
        rm -f -- "$active_tmp"
        if ! grep -Fq 'SERPANTINUM-PLUS QUICKACTIONS BINDS' "$keybind_backup" 2>/dev/null; then
            cp -a -- "$keybind_backup" "$keybind_file"
        fi
        rollback_changes || return 1
        printf 'Could not record backup state; restored all touched files.\n' >&2
        return 1
    fi
    printf 'Installed Serpantinum Plus additions; updated %d overlay files.\n' "${#overlay_paths[@]}"
    report_dependencies
}

run_step "Applying changes (backup: $backup_dir)..." 'Backup restored; see error above.' 'Applying...' perform_install
run_step 'Restarting the shell...' 'Changes are installed; restart the shell manually.' 'Restarting...' restart_shell
printf 'Complete. Added/updated the listed files. Backup: %s\nTotal time: %.1fs\n' "$backup_dir" "$(awk "BEGIN {print $(elapsed_ms "$run_started_ms") / 1000}")"
