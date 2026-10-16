#!/usr/bin/env bash
set -euo pipefail

step=0
step_total=5
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

usage() {
    cat <<'USAGE'
Usage: bash custom/install-addons.sh [--yes] [--dry-run] [--no-restart]

Options:
  --yes          Skip confirmation prompt.
  --dry-run      Check compatibility and summarize changes without writing.
  --no-restart   Do not restart serpantinumd after changes.
  --help         Show this help.
USAGE
}

mode=install
yes=false
no_restart=false
while (($#)); do
    case "$1" in
        --yes) yes=true ;;
        --dry-run) mode=dry-run ;;
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

version_metadata_missing=false
version_metadata_target=""
version_metadata_rel=""
version_state_file="${QS_STATE_DIR:-$HOME/.local/state/serpantinum}/version"
package_version=""
if [[ -r "$version_state_file" ]]; then
    package_version="$(python3 - "$version_state_file" <<'PY'
import re, sys
try:
    for line in open(sys.argv[1], encoding="utf-8"):
        match = re.match(r'^SERPANTINUM_VERSION=["\']?([^"\'\s]+)', line)
        if match:
            print(match.group(1))
            break
except OSError:
    pass
PY
)"
fi
if [[ ! -r "$source_dir_target/version.txt" ]]; then
    version_metadata_missing=true
    version_metadata_target="$(realpath -m -- "$source_dir_target/version.txt")"
    case "$version_metadata_target" in
        "$install_dir"/*) version_metadata_rel="${version_metadata_target#"$install_dir"/}" ;;
        *) version_metadata_target="" ;;
    esac
fi

check_target() {
    [[ -d "$source_dir_target" ]] || {
        printf 'Serpantinum source directory not found: %s\n' "$source_dir_target" >&2
        return 1
    }
    [[ -f "$source_dir_target/quickshell/bar/BarModuleRegistry.qml" ]] || {
        printf 'BarModuleRegistry.qml not found at %s\n' "$source_dir_target/quickshell/bar" >&2
        return 1
    }
    [[ -f "$source_dir_target/quickshell/quickactions/Floating.qml" ]] || {
        printf 'Floating.qml not found at %s\n' "$source_dir_target/quickshell/quickactions" >&2
        return 1
    }
}

overlay_dir="$source_dir/overlay"
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
        printf 'serpantinumd is not on PATH; restart shell manually.\n'
        return 0
    fi
    "$daemon" stop >/dev/null 2>&1 || true
    "$daemon" start
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

patch_bar_registry() {
    local reg="$source_dir_target/quickshell/bar/BarModuleRegistry.qml"
    python3 - "$reg" << 'PY'
import sys, re
reg = sys.argv[1]
s = open(reg).read()

# Register Expose if not present
if '"expose": {' not in s:
    anchor = "property var types: ({"
    if anchor in s:
        expose_entry = '''
        "expose": {
            name: "expose",
            icon: "",
            defaultVariant: "default",
            face: "faces/expose/ExposeFace.qml"
        },'''
        s = s.replace(anchor, anchor + expose_entry, 1)

# Register YTDL if not present
if '"ytdl": {' not in s:
    anchor = "property var types: ({"
    if anchor in s:
        ytdl_entry = '''
        "ytdl": {
            name: "ytdl",
            icon: "",
            defaultVariant: "default",
            face: "faces/ytdl/YtdlFace.qml"
        },'''
        s = s.replace(anchor, anchor + ytdl_entry, 1)

# Register sysinfo if not present
if '"sysinfo": {' not in s:
    anchor = "property var types: ({"
    if anchor in s:
        sysinfo_entry = '''
        "sysinfo": {
            name: "System Info",
            icon: "\uf2db",
            defaultVariant: "default",
            face: "faces/sysinfo/SysInfoFace.qml"
        },'''
        s = s.replace(anchor, anchor + sysinfo_entry, 1)

# Remove legacy bar music if bar music exists
if 'faces/music/MusicFace.qml' in s:
    s = re.sub(r'(?m)^\s*"music":\s*\{\n\s*name: "music",\n\s*icon: "",\n\s*defaultVariant: "default",\n\s*horizontalFace: "faces/music/MusicFace.qml",\n\s*verticalFace: "faces/music/SideMusicFace.qml"\n\s*\},\n', '', s)
    s = re.sub(r'(?m)^\s*"music":\s*\{\n\s*name: "music",\n\s*icon: "",\n\s*defaultVariant: "default",\n\s*face: "faces/music/MusicFace.qml"\n\s*\},\n', '', s)

open(reg, "w").write(s)
PY
}

patch_qmldir() {
    local qmldir="$source_dir_target/quickshell/bar/qmldir"
    if [[ -f "$qmldir" ]] && ! grep -q 'ExposeState' "$qmldir"; then
        printf '\nsingleton ExposeState 1.0 ExposeState.qml\n' >> "$qmldir"
    fi
}

patch_floating() {
    local fl="$source_dir_target/quickshell/quickactions/Floating.qml"
    python3 - "$fl" << 'PY'
import sys, re
fl = sys.argv[1]
s = open(fl).read()
orig = s

# 1. tabModules append
mods = ["actions/Game.qml", "actions/DropShelf.qml", "actions/Music.qml"]
for mod in mods:
    if f'"{mod}"' not in s:
        m = re.search(r'(property var tabModules: \[)(.*?)(\n[ \t]*\])', s, re.S)
        if m:
            body = m.group(2).rstrip()
            ind = re.search(r'\n([ \t]+)"', m.group(2))
            indent = ind.group(1) if ind else "                "
            body = body + ',\n' + indent + f'"{mod}"'
            s = s[:m.start()] + m.group(1) + body + m.group(3) + s[m.end():]

# 2. getTabInfo icons & names
if 'mod.indexOf("Game")' not in s:
    anchor_info = 'else if (mod.indexOf("Notes") !== -1) {\n                    return { name: I18n.t("quickactions.tabs.notes"), icon: "󰈙" };\n                }'
    custom_tabs = '''else if (mod.indexOf("Notes") !== -1) {
                    return { name: I18n.t("quickactions.tabs.notes"), icon: "󰈙" };
                } else if (mod.indexOf("Game") !== -1 || mod.indexOf("Snake") !== -1) {
                    return { name: "Snake", icon: "󰊴" };
                } else if (mod.indexOf("DropShelf") !== -1) {
                    return { name: "Drop Shelf", icon: "󰉓" };
                } else if (mod.indexOf("Music") !== -1) {
                    return { name: "Music", icon: "󰎈" };
                }'''
    if anchor_info in s:
        s = s.replace(anchor_info, custom_tabs, 1)

# 3. Dynamic tab fallback
if 'let base = mod.replace(' not in s:
    fallback_anchor = 'return { name: I18n.t("quickactions.tabs.tab"), icon: "󰍜" };'
    fallback_code = '''let base = mod.replace(/^.*\\//, "").replace(/\\.qml$/, "");
                if (base) return { name: base, icon: "󰍜" };
                return { name: I18n.t("quickactions.tabs.tab"), icon: "󰍜" };'''
    if fallback_anchor in s:
        s = s.replace(fallback_anchor, fallback_code, 1)

# 4. IPC handler & layout navigation
if 'target: "quickactions"' not in s:
    anchor_widget = 'PanelWindow {\n            id: floatingWidget\n'
    ipc_code = '''PanelWindow {
            id: floatingWidget

            function closeQuickActions() {
                floatingWidget.isPinned = false;
                floatingWidget.isExpanded = false;
                floatingWidget.isSidebarVisible = false;
                floatingWidget.isPeekVisible = false;
                floatingWidget.useGraceTimer = false;
                hideTimer.stop();
                peekHideTimer.stop();
            }

            IpcHandler {
                target: "quickactions"
                function toggle() { floatingWidget.shortcutToggle(); }
                function show() {
                    let edge = floatingWidget.barPosition === "left" ? "right"
                        : floatingWidget.barPosition === "right" ? "left" : floatingWidget.activeEdge;
                    floatingWidget.isPinned = false;
                    floatingWidget.isExpanded = false;
                    floatingWidget.showSidebar(edge, floatingWidget.height / 2, false);
                    floatingWidget.isPinned = true;
                    floatingWidget.isExpanded = false;
                    hideTimer.stop();
                    peekHideTimer.stop();
                }
                function hide() { floatingWidget.closeQuickActions(); }
                function nextSection() {
                    if (!floatingWidget.isSidebarVisible) return;
                    let step = floatingWidget.activeEdge === "right" ? -1 : 1;
                    floatingWidget.activeIndex = Math.max(0, Math.min(floatingWidget.tabCount - 1, floatingWidget.activeIndex + step));
                }
                function previousSection() {
                    if (!floatingWidget.isSidebarVisible) return;
                    let step = floatingWidget.activeEdge === "right" ? 1 : -1;
                    floatingWidget.activeIndex = Math.max(0, Math.min(floatingWidget.tabCount - 1, floatingWidget.activeIndex + step));
                }
                function moveForward() { floatingWidget.moveOpenedLayout(1); }
                function moveBackward() { floatingWidget.moveOpenedLayout(-1); }
                function expand() {
                    if (!floatingWidget.isSidebarVisible) return;
                    floatingWidget.isExpanded = true;
                    hideTimer.stop();
                }
                function collapse() {
                    if (!floatingWidget.isSidebarVisible) return;
                    floatingWidget.isExpanded = false;
                    hideTimer.stop();
                }
            }

            function shortcutToggle() {
                if (floatingWidget.isSidebarVisible || floatingWidget.isPinned) {
                    floatingWidget.closeQuickActions();
                    return;
                }
                let edge = floatingWidget.barPosition === "left" ? "right"
                    : floatingWidget.barPosition === "right" ? "left" : floatingWidget.activeEdge;
                floatingWidget.isPinned = false;
                floatingWidget.showSidebar(edge, floatingWidget.height / 2, false);
                floatingWidget.isPinned = true;
                floatingWidget.isExpanded = false;
                floatingWidget.isPeekVisible = false;
                floatingWidget.useGraceTimer = false;
                hideTimer.stop();
                peekHideTimer.stop();
            }

            function moveOpenedLayout(step) {
                if (!floatingWidget.isSidebarVisible) return;
                let xSpan = Math.max(1, floatingWidget.rightBound - floatingWidget.leftBound);
                let ySpan = Math.max(1, floatingWidget.bottomBound - floatingWidget.topBound);
                let t = 0;
                if (floatingWidget.activeEdge === "top") {
                    t = (floatingWidget.currentPos - floatingWidget.leftBound) / xSpan;
                } else if (floatingWidget.activeEdge === "right") {
                    t = 1 + (floatingWidget.currentPos - floatingWidget.topBound) / ySpan;
                } else if (floatingWidget.activeEdge === "bottom") {
                    t = 2 + (floatingWidget.rightBound - floatingWidget.currentPos) / xSpan;
                } else if (floatingWidget.activeEdge === "left") {
                    t = 3 + (floatingWidget.bottomBound - floatingWidget.currentPos) / ySpan;
                }
                t = (t % 4 + 4) % 4;
                t += step * 0.25;
                t = (t % 4 + 4) % 4;
                let nextEdge = "";
                let nextPos = 0;
                if (t < 1) {
                    nextEdge = "top"; nextPos = floatingWidget.leftBound + t * xSpan;
                } else if (t < 2) {
                    nextEdge = "right"; nextPos = floatingWidget.topBound + (t - 1) * ySpan;
                } else if (t < 3) {
                    nextEdge = "bottom"; nextPos = floatingWidget.rightBound - (t - 2) * xSpan;
                } else {
                    nextEdge = "left"; nextPos = floatingWidget.bottomBound - (t - 3) * ySpan;
                }
                edgeTransitionTimer.stop();
                teleportTimer.stop();
                floatingWidget.pendingEdge = "";
                floatingWidget.pendingPos = 0;
                floatingWidget.pendingMode = "";
                floatingWidget.disableAnim = false;
                floatingWidget.currentPos = nextPos;
                floatingWidget.activeEdge = nextEdge;
                floatingWidget.isPeekVisible = false;
                floatingWidget.isSidebarVisible = true;
                if (floatingWidget.isPinned) hideTimer.stop();
                else floatingWidget.kickTimer();
            }
'''
    if anchor_widget in s:
        s = s.replace(anchor_widget, ipc_code, 1)

# 5. Music lifecycle
if 'isMusicModule' not in s:
    loader_anchor = 'visible: index === floatingWidget.activeIndex && floatingWidget.expandProgress > 0.01\n                                source: modelData'
    music_lifecycle = '''property bool isMusicModule: String(modelData).endsWith("/Music.qml")
                                property bool shouldLoad: isMusicModule ? floatingWidget.isSidebarVisible : (index === floatingWidget.activeIndex && floatingWidget.isSidebarVisible && floatingWidget.isExpanded && floatingWidget.expandProgress > 0.01)
                                visible: index === floatingWidget.activeIndex && floatingWidget.isExpanded && floatingWidget.expandProgress > 0.01
                                active: shouldLoad
                                source: modelData'''
    if loader_anchor in s:
        s = s.replace(loader_anchor, music_lifecycle, 1)

if s != orig:
    open(fl, "w").write(s)
PY
}

perform_install() {
    # 1. Copy overlays
    cp -a -- "$overlay_dir/src/." "$source_dir_target/"

    # 2. Dynamic QML/Registry patches
    patch_bar_registry
    patch_qmldir
    patch_floating

    # 3. Version file restoration
    if [[ "$version_metadata_missing" == true && -n "$package_version" && -n "$version_metadata_target" ]]; then
        printf '%s\n' "$package_version" > "$version_metadata_target"
    fi

    # 4. Keybinds
    if [[ -n "$keybind_file" ]] && ! grep -Fq 'SERPANTINUM-PLUS QUICKACTIONS BINDS' "$keybind_file"; then
        keybind_block >> "$keybind_file"
    fi
}

run_step 'Checking Serpantinum install...' 'Source check failed.' 'Checking...' check_target

if [[ "$mode" == dry-run ]]; then
    printf 'Dry-run: install directory is %s\n' "$install_dir"
    printf 'Overlays to sync: %d files\n' "${#overlay_paths[@]}"
    report_dependencies
    exit 0
fi

if [[ "$yes" != true ]]; then
    read -r -p 'Continue with installation? [y/N] ' answer </dev/tty || answer=""
    [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]] || { printf 'Cancelled.\n'; exit 0; }
fi

run_step 'Applying add-on files and dynamic configuration...' 'Installation failed.' 'Installing...' perform_install
run_step 'Restarting shell...' 'Failed to restart shell.' 'Restarting...' restart_shell

printf 'Installation complete. Elapsed time: %.1fs\n' "$(awk "BEGIN {print $(elapsed_ms "$run_started_ms") / 1000}")"
