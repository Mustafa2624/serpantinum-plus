#!/usr/bin/env bash

set -e

setterm -blank 0 -powerdown 0 2>/dev/null || true
printf '\033[9;0]' 2>/dev/null || true

RAW_SLUG="${REPO_SLUG:-Mustafa2624/serpantinum-plus}"
REPO_SLUG="$(printf '%s' "$RAW_SLUG" | tr -d '\r\n\t ' | sed 's/[^a-zA-Z0-9_\/-]//g')"
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum-installer"
export REPO_SLUG

if [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    INSTALL_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    PROJECT_ROOT="$(dirname "$INSTALL_DIR")"
else
    INSTALL_DIR=""
    PROJECT_ROOT=""
fi

if [[ -z "$PROJECT_ROOT" || ! -f "$PROJECT_ROOT/install/modules/deps.sh" || ! -d "$PROJECT_ROOT/src" ]]; then
    command -v curl &>/dev/null || { echo "curl is required to download the installer source." >&2; exit 1; }
    command -v tar &>/dev/null || { echo "tar is required to extract the installer source." >&2; exit 1; }
    mkdir -p "$CACHE_BASE"
    SOURCE_CACHE="$CACHE_BASE/source"
    SOURCE_STAGE="$(mktemp -d "$CACHE_BASE/.source.XXXXXX")"
    SOURCE_ARCHIVE="$CACHE_BASE/.source.$$.tar.gz"
    cleanup_source_download() {
        rm -rf -- "$SOURCE_STAGE"
        rm -f -- "$SOURCE_ARCHIVE"
    }
    trap cleanup_source_download EXIT
    SOURCE_URL="${SERPANTINUM_PLUS_TARBALL:-https://github.com/${REPO_SLUG}/archive/refs/heads/master.tar.gz}"
    curl -fsSL "$SOURCE_URL" -o "$SOURCE_ARCHIVE"
    tar -xzf "$SOURCE_ARCHIVE" --strip-components=1 -C "$SOURCE_STAGE"
    [[ -f "$SOURCE_STAGE/install/modules/deps.sh" && -d "$SOURCE_STAGE/src" ]] || {
        echo "The downloaded archive does not contain a Serpantinum source tree." >&2
        exit 1
    }
    rm -rf -- "$SOURCE_CACHE"
    mv -- "$SOURCE_STAGE" "$SOURCE_CACHE"
    rm -f -- "$SOURCE_ARCHIVE"
    trap - EXIT
    INSTALL_DIR="$SOURCE_CACHE/install"
    PROJECT_ROOT="$SOURCE_CACHE"
fi

export SERPANTINUM_DIR="$PROJECT_ROOT/src"
export I18N_DIR="$PROJECT_ROOT/src/assets/languages"

if [[ "${SERPANTINUM_INSTALLER_PREFLIGHT:-0}" == 1 ]]; then
    printf 'Preflight OK: repo=%s\nsource=%s\ninstaller=%s\n' "$REPO_SLUG" "$PROJECT_ROOT" "$INSTALL_DIR"
    exit 0
fi

MODULES_DIR="$INSTALL_DIR/modules"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/scripts/i18n.sh"
# shellcheck disable=SC1091
source "$MODULES_DIR/deps.sh"
# shellcheck disable=SC1091
source "$MODULES_DIR/state.sh"
# shellcheck disable=SC1091
source "$MODULES_DIR/migrate.sh"
# shellcheck disable=SC1091
source "$MODULES_DIR/deploy.sh"
# shellcheck disable=SC1091
source "$MODULES_DIR/version.sh"
# shellcheck disable=SC1091
source "$MODULES_DIR/config.sh"
# shellcheck disable=SC1091
source "$MODULES_DIR/service.sh"
# shellcheck disable=SC1091
source "$MODULES_DIR/ui.sh"

TELEMETRY_ID=$(get_telemetry_id)
ENABLE_TELEMETRY=$(get_telemetry_enabled)

check_supported_os
bootstrap_installer_deps

INSTALL_STATE=$(detect_install_state)
OLD_VERSION=$(get_installed_version)
TARGET_VERSION=$(get_target_version "$PROJECT_ROOT" "$REPO_SLUG")
TARGET_COMMIT=$(get_target_commit "$PROJECT_ROOT" "$REPO_SLUG")
OLD_COMMIT=$(get_installed_commit)

init_compositor_detection
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
