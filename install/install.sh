#!/usr/bin/env bash

set -e

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    setterm -blank 0 -powerdown 0 2>/dev/null || true
    printf '\033[9;0]' 2>/dev/null || true
fi

step=0
step_total=5

begin_step() {
    local label="$1" heartbeat_text="$2"
    step=$((step + 1))
    printf '[%d/%d] %s\n' "$step" "$step_total" "$label"
    STEP_START_MS="$(date +%s%3N)"
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
    STEP_HEARTBEAT_PID=$!
}

end_step() {
    local elapsed
    kill "$STEP_HEARTBEAT_PID" 2>/dev/null || true
    wait "$STEP_HEARTBEAT_PID" 2>/dev/null || true
    elapsed=$(( $(date +%s%3N) - STEP_START_MS ))
    printf 'done (%d.%03ds)\n' "$((elapsed / 1000))" "$((elapsed % 1000))"
}

run_step() {
    local label="$1" failure_state="$2" heartbeat_text="$3"; shift 3
    local status=0
    begin_step "$label" "$heartbeat_text"
    "$@" || status=$?
    kill "$STEP_HEARTBEAT_PID" 2>/dev/null || true
    wait "$STEP_HEARTBEAT_PID" 2>/dev/null || true
    local elapsed=$(( $(date +%s%3N) - STEP_START_MS ))
    if ((status == 0)); then
        printf 'done (%d.%03ds)\n' "$((elapsed / 1000))" "$((elapsed % 1000))"
        return 0
    fi
    printf 'Step %d failed (exit %d): %s\n' "$step" "$status" "$failure_state" >&2
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

RAW_SLUG="${REPO_SLUG:-Mustafa2624/serpantinum-plus}"
REPO_SLUG="$(printf '%s' "$RAW_SLUG" | tr -d '\r\n\t ' | sed 's/[^a-zA-Z0-9_\/-]//g')"
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum-installer"
export REPO_SLUG

locate_source() {
    if [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
        INSTALL_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
        PROJECT_ROOT="$(dirname "$INSTALL_DIR")"
    else
        INSTALL_DIR=""
        PROJECT_ROOT=""
    fi
}
run_step 'Checking installer source...' 'The shell install has not started.' 'Still checking installer source...' locate_source

if [[ -z "$PROJECT_ROOT" || ! -f "$PROJECT_ROOT/install/modules/deps.sh" || ! -d "$PROJECT_ROOT/src" ]]; then
    command -v curl &>/dev/null || { echo "curl is required to download the installer source." >&2; exit 1; }
    command -v tar &>/dev/null || { echo "tar is required to extract the installer source." >&2; exit 1; }
    SOURCE_URL="${SERPANTINUM_PLUS_TARBALL:-https://github.com/${REPO_SLUG}/archive/refs/heads/master.tar.gz}"
    printf 'Before downloading: I will fetch the Serpantinum Plus source archive; nothing has been changed yet.\n'
    download_source() {
        mkdir -p "$CACHE_BASE" || return 1
        SOURCE_CACHE="$CACHE_BASE/source"
        SOURCE_STAGE="$(mktemp -d "$CACHE_BASE/.source.XXXXXX")" || return 1
        SOURCE_ARCHIVE="$CACHE_BASE/.source.$$.tar.gz"
        curl_status=0
        download_archive "$SOURCE_URL" "$SOURCE_ARCHIVE" || curl_status=$?
        if ((curl_status != 0)); then
            rm -rf -- "$SOURCE_STAGE"
            rm -f -- "$SOURCE_ARCHIVE"
            return "$curl_status"
        fi
    }
    run_step 'Downloading Serpantinum Plus...' 'No files were changed.' 'Downloading...' download_source
    unpack_source() {
        if ! tar -xzf "$SOURCE_ARCHIVE" --strip-components=1 -C "$SOURCE_STAGE"; then
            rm -rf -- "$SOURCE_STAGE" "$SOURCE_ARCHIVE"
            printf 'Could not unpack the downloaded archive.\n' >&2
            return 1
        fi
        [[ -f "$SOURCE_STAGE/install/modules/deps.sh" && -d "$SOURCE_STAGE/src" ]] || {
            rm -rf -- "$SOURCE_STAGE" "$SOURCE_ARCHIVE"
            echo 'The downloaded archive does not contain a Serpantinum source tree.' >&2
            return 1
        }
        rm -rf -- "$SOURCE_CACHE"
        mv -- "$SOURCE_STAGE" "$SOURCE_CACHE"
        rm -f -- "$SOURCE_ARCHIVE"
        INSTALL_DIR="$SOURCE_CACHE/install"
        PROJECT_ROOT="$SOURCE_CACHE"
    }
    run_step 'Unpacking...' 'No shell files were changed.' 'Still unpacking...' unpack_source
else
    run_step 'Using the local Serpantinum Plus checkout...' 'No shell files were changed.' 'Still checking...' true
    run_step 'Unpacking... not needed for a local checkout.' 'No shell files were changed.' 'Still checking...' true
fi

export SERPANTINUM_DIR="$PROJECT_ROOT/src"
export I18N_DIR="$PROJECT_ROOT/src/assets/languages"

if [[ "${SERPANTINUM_INSTALLER_PREFLIGHT:-0}" == 1 ]]; then
    printf 'Preflight OK: repo=%s\nsource=%s\ninstaller=%s\n' "$REPO_SLUG" "$PROJECT_ROOT" "$INSTALL_DIR"
    exit 0
fi

MODULES_DIR="$INSTALL_DIR/modules"
begin_step 'Loading installer modules...' 'Still loading installer modules...'

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/scripts/i18n.sh" || { printf 'Step 4 failed: could not load %s. No shell files were changed.\n' "$PROJECT_ROOT/src/scripts/i18n.sh" >&2; exit 1; }
# shellcheck disable=SC1091
source "$MODULES_DIR/deps.sh" || { printf 'Step 4 failed: could not load %s. No shell files were changed.\n' "$MODULES_DIR/deps.sh" >&2; exit 1; }
# shellcheck disable=SC1091
source "$MODULES_DIR/state.sh" || { printf 'Step 4 failed: could not load %s. No shell files were changed.\n' "$MODULES_DIR/state.sh" >&2; exit 1; }
# shellcheck disable=SC1091
source "$MODULES_DIR/migrate.sh" || { printf 'Step 4 failed: could not load %s. No shell files were changed.\n' "$MODULES_DIR/migrate.sh" >&2; exit 1; }
# shellcheck disable=SC1091
source "$MODULES_DIR/deploy.sh" || { printf 'Step 4 failed: could not load %s. No shell files were changed.\n' "$MODULES_DIR/deploy.sh" >&2; exit 1; }
# shellcheck disable=SC1091
source "$MODULES_DIR/version.sh" || { printf 'Step 4 failed: could not load %s. No shell files were changed.\n' "$MODULES_DIR/version.sh" >&2; exit 1; }
# shellcheck disable=SC1091
source "$MODULES_DIR/config.sh" || { printf 'Step 4 failed: could not load %s. No shell files were changed.\n' "$MODULES_DIR/config.sh" >&2; exit 1; }
# shellcheck disable=SC1091
source "$MODULES_DIR/service.sh" || { printf 'Step 4 failed: could not load %s. No shell files were changed.\n' "$MODULES_DIR/service.sh" >&2; exit 1; }
# shellcheck disable=SC1091
source "$MODULES_DIR/ui.sh" || { printf 'Step 4 failed: could not load %s. No shell files were changed.\n' "$MODULES_DIR/ui.sh" >&2; exit 1; }
end_step

pre_menu_checks() {
    TELEMETRY_ID=$(get_telemetry_id) || return $?
    ENABLE_TELEMETRY=$(get_telemetry_enabled) || return $?
    check_supported_os || return $?
    bootstrap_installer_deps || return $?
    INSTALL_STATE=$(detect_install_state) || return $?
    OLD_VERSION=$(get_installed_version) || return $?
    TARGET_VERSION=$(get_target_version "$PROJECT_ROOT" "$REPO_SLUG") || return $?
    TARGET_COMMIT=$(get_target_commit "$PROJECT_ROOT" "$REPO_SLUG") || return $?
    OLD_COMMIT=$(get_installed_commit) || return $?
    init_compositor_detection || return $?
}
run_step 'Checking requirements and preparing the menu...' 'The shell install has not started; dependency setup may have made partial package changes.' 'Still preparing requirements...' pre_menu_checks
run_installer_ui

TARGET_VERSION=$(get_target_version "$PROJECT_ROOT" "$REPO_SLUG")
TARGET_COMMIT=$(get_target_commit "$PROJECT_ROOT" "$REPO_SLUG")

if [ "$ENABLE_TELEMETRY" = true ] && [ -f "$MODULES_DIR/telemetry.sh" ]; then
    bash "$MODULES_DIR/telemetry.sh" --mode init --version "$TARGET_VERSION" --id "$TELEMETRY_ID" --enabled "$ENABLE_TELEMETRY"
fi

if [[ "$INSTALL_STATE" == "legacy" ]]; then
    migrate_legacy "${SELECTED_COMPOSITORS[@]}"
elif [[ "$INSTALL_STATE" == "fresh" || "$IS_REINSTALL" == true ]]; then
    backup_compositors "${SELECTED_COMPOSITORS[@]}"
fi

install_dependencies "$INSTALL_STATE" "$IS_REINSTALL" "${SELECTED_COMPOSITORS[@]}"

deploy_package "$PROJECT_ROOT" "$OLD_COMMIT" "$TARGET_COMMIT" "$IS_REINSTALL" "$INSTALL_STATE" "${SELECTED_COMPOSITORS[@]}"
setup_sddm "$PROJECT_ROOT" "$INSTALL_STATE" "$IS_REINSTALL"
install_wallpapers "$INSTALL_FULL_WALLPAPERS"

WALLPAPER_DIR=$(get_wallpaper_dir)
init_serpantinum_config "$PROJECT_ROOT" "$WALLPAPER_DIR" "$INSTALL_STATE" "$IS_REINSTALL"

setup_services
write_version_state "$TARGET_VERSION" "$TARGET_COMMIT" "$TELEMETRY_ID" "$ENABLE_TELEMETRY" "${SELECTED_COMPOSITORS[*]}"

if [[ "$INSTALL_STATE" == "legacy" || "$INSTALL_STATE" == "fresh" || "$IS_REINSTALL" == true ]]; then
    rm -f "$HOME/.local/state/serpantinum/first_launch.done" "$HOME/.local/state/quickshell/first_launch.done"
fi

if [ -f "$MODULES_DIR/telemetry.sh" ]; then
    bash "$MODULES_DIR/telemetry.sh" --mode "done" --version "$TARGET_VERSION" --old-version "$OLD_VERSION" --install-state "$INSTALL_STATE" --compositor "${SELECTED_COMPOSITORS[*]}" --id "$TELEMETRY_ID" --enabled "$ENABLE_TELEMETRY" --failed "${FAILED_PKGS[*]}"
fi

draw_completion_screen "$TARGET_VERSION" "$TARGET_COMMIT"

if command -v serpantinumd &>/dev/null; then
    serpantinumd start
elif [[ -x "$HOME/.local/bin/serpantinumd" ]]; then
    "$HOME/.local/bin/serpantinumd" start
else
    echo "Installation completed, but serpantinumd was not found; start the shell manually." >&2
fi
