// YT Downloader bar module for Serpantinum.
// Behavior modeled on dlpwaters/omarchy-yt-downloader (MIT). Independent
// implementation: UI, theme and process handling written for Serpantinum.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../../reusables"
import "../../../"

Item {
    id: root

    property var module: null
    property var widget: module

    readonly property bool isCompact: module ? module.isCompact : false
    readonly property var barWindow: module ? module.barWindow : null

    function px(v) { return barWindow ? barWindow.s(v) : v }

    // ---------- state ----------
    readonly property string home: Quickshell.env("HOME")
    readonly property string baseDir: home + "/Downloads/YT"
    readonly property string fullPath: home + "/.local/bin:" + (Quickshell.env("PATH") || "/usr/local/bin:/usr/bin:/bin")
    readonly property var commonLangs: [
        { code: "en", label: "English" }, { code: "ur", label: "Urdu" },
        { code: "hi", label: "Hindi" }, { code: "ar", label: "Arabic" },
        { code: "es", label: "Spanish" }, { code: "fr", label: "French" },
        { code: "de", label: "German" }, { code: "pt", label: "Portuguese" },
        { code: "ru", label: "Russian" }, { code: "it", label: "Italian" },
        { code: "tr", label: "Turkish" }, { code: "id", label: "Indonesian" },
        { code: "zh-Hans", label: "Chinese (Simplified)" }, { code: "ja", label: "Japanese" },
        { code: "ko", label: "Korean" }, { code: "fa", label: "Persian" },
        { code: "bn", label: "Bengali" }, { code: "nl", label: "Dutch" },
        { code: "pl", label: "Polish" }
    ]

    property bool open: false
    property real popupX: 0
    property real popupY: 0
    property double closedAt: 0
    property bool showLayout: false

    property string url: ""
    property var queue: []
    property int queueIndex: -1
    property int mode: 0          // 0 video, 1 audio, 2 transcript
    property bool playlist: false
    property var langs: commonLangs
    property string lang: "en"
    property bool langsOpen: false

    property string ytdlpPath: ""
    property string ffmpegPath: ""
    readonly property bool depsOk: ytdlpPath !== "" && ffmpegPath !== ""
    readonly property string missingTools: (ytdlpPath === "" ? "yt-dlp " : "") + (ffmpegPath === "" ? "ffmpeg" : "")

    property bool busy: false
    property int flash: 0        // 0 none, 1 done, 2 error
    property bool stopping: false
    property bool finding: false
    property bool findingFormats: false
    property var formats: []
    property string selectedFormat: ""
    property string qualityPreset: "best"
    property bool formatsOpen: false
    property bool pasteAuto: false
    property bool retried: false
    property bool saw403: false
    property real percent: 0
    property string speed: ""
    property string eta: ""
    property int itemIndex: 0
    property int itemCount: 0
    property string currentFile: ""
    property string lastError: ""
    property string statusText: ""
    property bool statusError: false
    property var history: []
    readonly property string historyPath: home + "/.local/state/serpantinum/ytdl/history.json"

    readonly property string selectedFormatLabel: {
        for (var i = 0; i < formats.length; i++) {
            if (formats[i].selector === selectedFormat) return formats[i].label
        }
        return "Best available"
    }

    readonly property string langLabel: {
        for (var i = 0; i < langs.length; i++) if (langs[i].code === lang) return langs[i].label
        return lang
    }

    // ---------- logic ----------
    function setStatus(t, isErr) { statusText = t; statusError = !!isErr }

    function addHistory(status) {
        var item = { url: url, file: currentFile, mode: ["Video", "Audio", "Transcript"][mode], status: status, time: new Date().toISOString() }
        history = [item].concat(history).slice(0, 20)
        Quickshell.execDetached(["bash", "-c", "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$1/history.json\"", "x", home + "/.local/state/serpantinum/ytdl", JSON.stringify(history)])
    }

    function outDir() { return baseDir + "/" + ["Video", "Audio", "Transcript"][mode] }

    function buildCommand(useFallback) {
        var tmpl = playlist
            ? outDir() + "/%(playlist_title)s/%(playlist_index)03d - %(title)s [%(id)s].%(ext)s"
            : outDir() + "/%(title)s [%(id)s].%(ext)s"
        var a = [ytdlpPath, "--newline", "--no-colors", "-o", tmpl]
        a.push(playlist ? "--yes-playlist" : "--no-playlist")
        if (mode === 0) {
            var preset = qualityPreset === "1080" ? "bv*[height<=1080]+bestaudio/best" : qualityPreset === "720" ? "bv*[height<=720]+bestaudio/best" : qualityPreset === "small" ? "bv*[height<=480][vcodec!=none]+ba[acodec!=none]/best[height<=480]" : "bv*[vcodec^=avc1]+ba[acodec^=mp4a]/b[vcodec^=avc1][ext=mp4]/bv*+ba/b"
            a.push("-f", selectedFormat !== "" ? selectedFormat : preset,
                   "--merge-output-format", "mp4")
        } else if (mode === 1) {
            a.push("-x", "--audio-format", "mp3", "--audio-quality", "0")
        } else {
            a.push("--skip-download", "--write-subs", "--write-auto-subs",
                   "--sub-langs", lang, "--convert-subs", "srt")
        }
        if (useFallback) a.push("--extractor-args", "youtube:player_client=web_embedded")
        a.push("--", url.trim())
        return a
    }

    function isUrl(t) { return /^https?:\/\//i.test(t) }

    function recheckDeps() { depsProc.running = false; depsProc.running = true }

    function enqueue() {
        var u = url.trim()
        if (!isUrl(u)) { setStatus("Paste a full http(s) link", true); return }
        queue = queue.concat([{ url: u, mode: mode, playlist: playlist }])
        setStatus(queue.length + " item(s) queued", false)
        url = ""
    }

    function start() {
        var u = url.trim()
        if (busy || u === "") return
        if (!isUrl(u)) { setStatus("Paste a full http(s) link", true); return }
        if (!depsOk) { setStatus("Missing: " + missingTools, true); return }
        retried = false; saw403 = false; lastError = ""
        percent = 0; speed = ""; eta = ""; itemIndex = 0; itemCount = 0; currentFile = ""
        busy = true
        flash = 0
        setStatus("Starting...", false)
        run(false)
    }

    function run(fallback) {
        dl.command = buildCommand(fallback)
        dl.running = true
    }

    function stop() {
        if (!dl.running) return
        stopping = true
        dl.running = false
    }

    function baseName(p) { return p.split("/").pop() }

    function updateStatus() {
        var s = ""
        if (itemCount > 0) s += "Item " + itemIndex + "/" + itemCount + "  "
        s += Math.round(percent) + "%"
        if (speed !== "") s += "  " + speed
        if (eta !== "") s += "  ETA " + eta
        setStatus(s, false)
    }

    function handleLine(line) {
        var m = line.match(/\[download\]\s+([\d.]+)%(?:.*?at\s+(\S+))?(?:.*?ETA\s+(\S+))?/)
        if (m) {
            percent = parseFloat(m[1]); speed = m[2] || ""; eta = m[3] || ""
            updateStatus(); return
        }
        m = line.match(/Downloading item (\d+) of (\d+)/)
        if (m) { itemIndex = parseInt(m[1]); itemCount = parseInt(m[2]); percent = 0; updateStatus(); return }
        m = line.match(/Destination:\s+(.+)$/) || line.match(/Merging formats into "(.+)"/)
            || line.match(/Writing video subtitles to:\s+(.+)$/)
        if (m) { currentFile = baseName(m[1]); return }
        if (/^\[(ExtractAudio|Merger|VideoConvertor|SubtitlesConvertor|FFmpegSubtitlesConvertor)\]/.test(line)) {
            setStatus("Converting...", false)
        }
    }

    function handleErr(line) {
        if (/HTTP Error 403/.test(line)) saw403 = true
        if (/^ERROR:/.test(line)) lastError = line.replace(/^ERROR:\s*/, "")
    }

    function startQueue() {
        if (busy || queue.length === 0) return
        var item = queue[0]
        queue = queue.slice(1)
        url = item.url
        mode = item.mode
        playlist = item.playlist
        start()
    }

    function finished(code) {
        if (stopping) {
            stopping = false; busy = false
            setStatus("Stopped (partial file kept, run again to resume)", false)
            return
        }
        if (code === 0) {
            busy = false; percent = 100
            flash = 1; flashTimer.restart()
            setStatus("Done" + (currentFile !== "" ? ": " + currentFile : ""), false)
            addHistory("done")
            if (queue.length > 0) Qt.callLater(startQueue)
            Quickshell.execDetached(["notify-send", "YT Downloader", "Finished: " + (currentFile !== "" ? currentFile : url)])
            return
        }
        if (!retried && saw403) {
            retried = true
            setStatus("HTTP 403, retrying with embedded client...", false)
            run(true)
            return
        }
        busy = false
        flash = 2
        addHistory("failed")
        setStatus(lastError !== "" ? lastError : "Failed (exit " + code + ")", true)
    }

    function paste(auto) {
        pasteAuto = !!auto
        pasteProc.running = false
        pasteProc.running = true
    }

    function findFormats() {
        var u = url.trim()
        if (findingFormats) return
        if (!isUrl(u)) { setStatus("Paste a link first", true); return }
        if (!depsOk) { setStatus("Missing: " + missingTools, true); return }
        findingFormats = true
        setStatus("Looking up formats...", false)
        formatProc.command = [ytdlpPath, "--skip-download", "--no-playlist", "--no-warnings", "--dump-single-json", "--", u]
        formatProc.running = true
    }

    function formatSize(bytes) {
        if (!bytes) return "size ?"
        if (bytes > 1073741824) return (bytes / 1073741824).toFixed(1) + " GB"
        return (bytes / 1048576).toFixed(0) + " MB"
    }

    function parseFormats(txt) {
        findingFormats = false
        try {
            var j = JSON.parse(txt)
            var out = []
            var fs = j.formats || []
            for (var i = 0; i < fs.length; i++) {
                var f = fs[i]
                if (!f.format_id || !f.vcodec || f.vcodec === "none" || !f.height) continue
                if (f.ext !== "mp4" && f.ext !== "webm" && f.ext !== "mkv") continue
                var selector = String(f.format_id)
                if (!f.acodec || f.acodec === "none") selector += "+bestaudio/best"
                out.push({
                    id: String(f.format_id),
                    selector: selector,
                    height: Number(f.height),
                    label: (f.height || "?") + "p " + (f.fps ? Math.round(f.fps) + "fps " : "") + f.ext.toUpperCase() + " " + formatSize(f.filesize || f.filesize_approx)
                })
            }
            out.sort(function(a, b) { return parseInt(b.label) - parseInt(a.label) })
            var seen = {}
            formats = out.filter(function(f) { if (seen[f.label]) return false; seen[f.label] = true; return true }).slice(0, 8)
            selectedFormat = formats.length ? formats[0].id : ""
            setStatus(formats.length ? formats.length + " formats found" : "No video formats found", !formats.length)
        } catch (e) {
            setStatus("Could not read formats", true)
        }
    }

    function findLanguages() {
        var u = url.trim()
        if (finding) return
        if (!isUrl(u)) { setStatus("Paste a link first", true); return }
        if (!depsOk) { setStatus("Missing: " + missingTools, true); return }
        finding = true
        setStatus("Looking up transcript tracks...", false)
        langProc.command = [ytdlpPath, "--skip-download", "--no-playlist", "--no-warnings",
                            "--dump-single-json", "--", u]
        langProc.running = true
    }

    function parseLangs(txt) {
        finding = false
        try {
            var j = JSON.parse(txt)
            var out = [], seen = {}
            var subs = j.subtitles || {}
            for (var k in subs) {
                if (k === "live_chat") continue
                out.push({ code: k, label: k + " (manual)" }); seen[k] = true
            }
            var auto = j.automatic_captions || {}
            for (var a in auto) {
                if (!seen[a]) out.push({ code: a, label: a + " (auto)" })
            }
            if (out.length === 0) { setStatus("No transcripts found for this video", true); return }
            langs = out
            lang = out[0].code
            setStatus(out.length + " transcript tracks found", false)
        } catch (e) {
            setStatus("Could not read the transcript list", true)
        }
    }

    function openFolder() {
        Quickshell.execDetached(["bash", "-c", 'mkdir -p "$1" && xdg-open "$1"', "x", baseDir])
    }

    function placePopup() {
        if (!barWindow) return
        var p = root.mapToItem(null, 0, 0)
        var w = px(650)
        var x = Math.round(p.x + root.width / 2 - w / 2)
        popupX = Math.max(px(8), Math.min(x, barWindow.width - w - px(8)))
        popupY = barWindow.height + px(4)
    }

    function togglePopup() {
        if (open) { open = false; return }
        recheckDeps()
        placePopup()
        open = true
        if (url.trim() === "") paste(true)
    }

    onOpenChanged: { if (open) focusTimer.restart() }

    Component.onCompleted: {
        recheckDeps()
        historyFile.reload()
    }

    // ---------- processes ----------
    Process {
        id: dl
        environment: ({ "PYTHONUNBUFFERED": "1", "PATH": root.fullPath })
        stdout: SplitParser { onRead: data => root.handleLine(data) }
        stderr: SplitParser { onRead: data => root.handleErr(data) }
        onExited: exitCode => root.finished(exitCode)
    }

    Process {
        id: historyDirProc
        command: ["mkdir", "-p", home + "/.local/state/serpantinum"]
        running: true
    }

    FileView {
        id: historyFile
        path: root.historyPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try { root.history = JSON.parse(text()) || [] } catch (e) { root.history = [] }
        }
        onLoadFailed: root.history = []
        onFileChanged: reload()
    }

    Process {
        id: formatProc
        environment: ({ "PATH": root.fullPath })
        stdout: StdioCollector { onStreamFinished: root.parseFormats(this.text) }
        onExited: root.findingFormats = false
    }

    Process {
        id: langProc
        environment: ({ "PATH": root.fullPath })
        stdout: StdioCollector { onStreamFinished: root.parseLangs(this.text) }
        onExited: root.finding = false
    }

    Process {
        id: pasteProc
        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim().split("\n")[0]
                if (t === "") return
                if (root.pasteAuto && !root.isUrl(t)) return
                root.url = t
            }
        }
    }

    Process {
        id: depsProc
        command: ["bash", "-c", 'export PATH="$HOME/.local/bin:$PATH"; for t in yt-dlp ffmpeg; do p=$(command -v "$t") || p=""; echo "$t=$p"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                var y = "", f = ""
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf("yt-dlp=") === 0) y = lines[i].substring(7)
                    if (lines[i].indexOf("ffmpeg=") === 0) f = lines[i].substring(7)
                }
                root.ytdlpPath = y
                root.ffmpegPath = f
            }
        }
    }

    Timer {
        id: flashTimer
        interval: 4000
        onTriggered: { if (root.flash === 1) root.flash = 0 }
    }

    Timer {
        id: focusTimer
        interval: 120
        onTriggered: urlInput.forceActiveFocus()
    }

    Timer {
        running: (!module || module.moduleActive) && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: root.showLayout = true
    }

    FontLoader {
        id: clockFontLoader
        source: (typeof Caching !== "undefined" && Caching.serpantinumDir && Caching.serpantinumDir !== "")
            ? ("file://" + Caching.serpantinumDir + "/assets/fonts/GoogleSansFlex.ttf")
            : Qt.resolvedUrl("../../../../assets/fonts/GoogleSansFlex.ttf")
    }

    readonly property string clockFont: clockFontLoader.status === FontLoader.Ready && clockFontLoader.name !== ""
        ? clockFontLoader.name
        : ThemeBackend.fontFamily

    // ---------- bar pill ----------
    readonly property var activeTarget: widget || module
    property string orientation: (activeTarget && activeTarget.orientation !== undefined) ? activeTarget.orientation : "horizontal"
    readonly property bool isVertical: orientation === "vertical"

    property real targetLength: ((!module || module.moduleActive) && sysLayout.implicitWidth > 0) ? (sysLayout.implicitWidth + px(isCompact ? 8 : 10)) : 0
    property bool isFaceVisible: showLayout && targetLength > 0

    implicitWidth: isVertical ? (parent ? parent.width : 0) : targetLength
    implicitHeight: isVertical ? targetLength : (parent ? parent.height : 0)

    transform: Translate {
        x: root.showLayout ? 0 : root.px(60)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    AxisFlow {
        id: sysLayout
        anchors.centerIn: parent
        vertical: root.isVertical
        property int pillHeight: root.px(root.isCompact ? 28 : 30)

        Rectangle {
            id: pill
            property bool initAnimTrigger: false
            readonly property bool hovered: pillMouse.containsMouse
            readonly property bool lit: root.busy || root.open || root.flash !== 0
            readonly property color accent: root.flash === 2 ? ThemeBackend.peach : (root.flash === 1 ? ThemeBackend.teal : ThemeBackend.mauve)
            readonly property color idleColor: root.isCompact ? Qt.lighter(ThemeBackend.surface1, 1.12) : ThemeBackend.surface1

            height: sysLayout.pillHeight
            width: Math.max(root.px(root.isCompact ? 36 : 40), pillRow.implicitWidth + root.px(root.isCompact ? 20 : 24))
            radius: Math.max(0, ThemeBackend.borderRadius - root.px(2))
            color: lit ? accent : (hovered ? Qt.lighter(idleColor, 1.25) : idleColor)
            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on width { NumberAnimation { duration: 480; easing.type: Easing.OutQuint } }

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: root.px(5)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.flash === 2 ? "\uDB80\uDC26" : (root.flash === 1 ? "\uDB80\uDD2C" : "\uDB80\uDDDA")
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: root.px(root.isCompact ? 16 : 17)
                    color: pill.lit ? ThemeBackend.base : ThemeBackend.mauve
                    transform: Translate { id: bob; y: 0 }
                }
                Text {
                    visible: root.busy
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(root.percent) + "%"
                    font.family: root.clockFont
                    font.pixelSize: root.px(root.isCompact ? 11 : 12)
                    font.weight: Font.Bold
                    font.variableAxes: ({ "wght": 400, "ROND": 100, "wdth": 100 })
                    color: ThemeBackend.base
                }
            }

            SequentialAnimation {
                running: root.busy
                loops: Animation.Infinite
                onRunningChanged: { if (!running) bob.y = 0 }
                NumberAnimation { target: bob; property: "y"; to: root.px(2); duration: 420; easing.type: Easing.InOutSine }
                NumberAnimation { target: bob; property: "y"; to: -root.px(2); duration: 420; easing.type: Easing.InOutSine }
            }

            Timer { running: (!module || module.moduleActive) && root.showLayout && !pill.initAnimTrigger; interval: 200; onTriggered: pill.initAnimTrigger = true }
            opacity: initAnimTrigger ? 1.0 : 0.0
            transform: Translate { y: pill.initAnimTrigger ? 0 : root.px(15); Behavior on y { NumberAnimation { duration: 620; easing.type: Easing.OutQuint } } }
            Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

            MouseArea {
                id: pillMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        if (root.busy) root.stop()
                        return
                    }
                    if (Date.now() - root.closedAt < 400) return
                    root.togglePopup()
                }
            }
        }
    }

    // ---------- popup ----------
    component Btn: Rectangle {
        id: b
        property string label: ""
        property bool primary: false
        property bool selected: false
        property bool active: true
        signal clicked()

        radius: root.px(8)
        height: root.px(30)
        color: (selected || primary) ? ThemeBackend.mauve : (btnMouse.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0)
        opacity: active ? 1.0 : 0.5

        Text {
            anchors.centerIn: parent
            text: b.label
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.px(12)
            font.weight: Font.Black
            font.bold: true
            color: (b.selected || b.primary) ? ThemeBackend.base : ThemeBackend.text
        }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (b.active) b.clicked() }
        }
    }

    HyprlandFocusGrab {
        windows: [popup]
        active: root.open
        onCleared: { root.open = false; root.closedAt = Date.now() }
    }

    PopupWindow {
        id: popup
        anchor.window: root.barWindow
        anchor.rect.x: root.popupX
        anchor.rect.y: root.popupY
        visible: root.open && root.barWindow !== null
        color: "transparent"
        implicitWidth: root.px(650)
        implicitHeight: Math.max(root.px(150), col.implicitHeight + root.px(28))

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: ThemeBackend.borderRadius
            color: ThemeBackend.base
            border.width: 1
            border.color: ThemeBackend.surface1

            Shortcut { sequence: "Escape"; enabled: root.open; onActivated: root.open = false }

            Column {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.px(14)
                spacing: root.px(10)

                Text {
                    text: "YT Downloader"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.px(15)
                    font.weight: Font.Black
                    font.bold: true
                    color: ThemeBackend.mauve
                }

                Rectangle {
                    width: col.width
                    height: root.px(34)
                    radius: root.px(8)
                    color: ThemeBackend.surface0
                    border.width: urlInput.activeFocus ? 1 : 0
                    border.color: ThemeBackend.mauve

                    TextInput {
                        id: urlInput
                        anchors.left: parent.left
                        anchors.right: pasteBtn.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: root.px(10)
                        anchors.rightMargin: root.px(6)
                        clip: true
                        selectByMouse: true
                        text: root.url
                        onTextChanged: root.url = text
                        onAccepted: root.start()
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.px(12)
                        color: ThemeBackend.text

                        Text {
                            visible: urlInput.text === ""
                            text: "Paste a video or playlist link"
                            font: urlInput.font
                            color: ThemeBackend.subtext0
                        }
                    }

                    Btn {
                        id: pasteBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: root.px(3)
                        width: root.px(56)
                        height: root.px(28)
                        label: "Paste"
                        onClicked: root.paste(false)
                    }
                }

                Row {
                    width: col.width
                    spacing: root.px(6)
                    Btn { width: (col.width - root.px(12)) / 3; label: "Video"; selected: root.mode === 0; onClicked: root.mode = 0 }
                    Btn { width: (col.width - root.px(12)) / 3; label: "Audio"; selected: root.mode === 1; onClicked: root.mode = 1 }
                    Btn { width: (col.width - root.px(12)) / 3; label: "Transcript"; selected: root.mode === 2; onClicked: root.mode = 2 }
                }

                Row {
                    visible: root.mode === 0
                    width: col.width
                    spacing: root.px(6)
                    Btn { width: (parent.width - root.px(18)) / 4; label: "Best"; selected: root.qualityPreset === "best" && root.selectedFormat === ""; onClicked: { root.qualityPreset = "best"; root.selectedFormat = "" } }
                    Btn { width: (parent.width - root.px(18)) / 4; label: "1080p"; selected: root.qualityPreset === "1080" && root.selectedFormat === ""; onClicked: { root.qualityPreset = "1080"; root.selectedFormat = "" } }
                    Btn { width: (parent.width - root.px(18)) / 4; label: "720p"; selected: root.qualityPreset === "720" && root.selectedFormat === ""; onClicked: { root.qualityPreset = "720"; root.selectedFormat = "" } }
                    Btn { width: (parent.width - root.px(18)) / 4; label: "Small"; selected: root.qualityPreset === "small" && root.selectedFormat === ""; onClicked: { root.qualityPreset = "small"; root.selectedFormat = "" } }
                }

                Row {
                    visible: root.mode === 0
                    width: col.width
                    spacing: root.px(6)
                    Btn {
                        width: parent.width - formatBtn.width - root.px(6)
                        label: root.formats.length ? (root.formatsOpen ? "Hide formats" : "Format: " + root.selectedFormatLabel) : "Format: Best"
                        selected: root.formatsOpen
                        onClicked: {
                            if (!root.formats.length) root.findFormats()
                            else root.formatsOpen = !root.formatsOpen
                        }
                    }
                    Btn {
                        id: formatBtn
                        width: root.px(120)
                        label: root.findingFormats ? "Finding..." : "Formats"
                        active: !root.findingFormats
                        onClicked: root.findFormats()
                    }
                }

                Rectangle {
                    visible: root.mode === 0 && root.formatsOpen && root.formats.length > 0
                    width: col.width
                    height: Math.min(root.px(160), root.formats.length * root.px(28))
                    radius: root.px(8)
                    color: ThemeBackend.surface0
                    clip: true

                    ListView {
                        anchors.fill: parent
                        model: root.formats
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width
                            height: root.px(28)
                            color: modelData.id === root.selectedFormat ? ThemeBackend.surface1 : "transparent"
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: root.px(10)
                                text: modelData.label
                                font.family: root.clockFont
                                font.pixelSize: root.px(11)
                                font.weight: Font.Normal
                                color: modelData.id === root.selectedFormat ? ThemeBackend.mauve : ThemeBackend.text
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.selectedFormat = modelData.id
                                    root.formatsOpen = false
                                }
                            }
                        }
                    }
                }

                Column {
                    visible: root.mode === 2
                    width: col.width
                    spacing: root.px(6)

                    Row {
                        width: parent.width
                        spacing: root.px(6)
                        Btn {
                            width: parent.width - findBtn.width - root.px(6)
                            label: root.langLabel + (root.langsOpen ? "  ▴" : "  ▾")
                            onClicked: root.langsOpen = !root.langsOpen
                        }
                        Btn {
                            id: findBtn
                            width: root.px(120)
                            label: root.finding ? "Finding..." : "Find languages"
                            active: !root.finding
                            onClicked: root.findLanguages()
                        }
                    }

                    Rectangle {
                        visible: root.langsOpen
                        width: parent.width
                        height: Math.min(root.px(150), root.langs.length * root.px(26))
                        radius: root.px(8)
                        color: ThemeBackend.surface0
                        clip: true

                        ListView {
                            anchors.fill: parent
                            model: root.langs
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: Rectangle {
                                required property var modelData
                                width: ListView.view.width
                                height: root.px(26)
                                color: rowMouse.containsMouse ? ThemeBackend.surface1 : "transparent"
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: root.px(10)
                                    text: modelData.label
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.px(12)
                                    font.bold: modelData.code === root.lang
                                    color: modelData.code === root.lang ? ThemeBackend.mauve : ThemeBackend.text
                                }
                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.lang = modelData.code; root.langsOpen = false }
                                }
                            }
                        }
                    }
                }

                Column {
                    width: col.width
                    spacing: root.px(4)
                    Text {
                        text: "Recent downloads"
                        font.family: root.clockFont
                        font.pixelSize: root.px(12)
                        font.weight: Font.Bold
                        color: ThemeBackend.subtext0
                    }
                    Repeater {
                        model: root.history.slice(0, 3)
                        delegate: Text {
                            required property var modelData
                            width: col.width
                            text: modelData.status.toUpperCase() + " · " + modelData.mode + " · " + (modelData.file || modelData.url)
                            elide: Text.ElideMiddle
                            font.family: root.clockFont
                            font.pixelSize: root.px(10)
                            color: modelData.status === "done" ? ThemeBackend.text : ThemeBackend.peach
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.url = modelData.url
                                    root.mode = modelData.mode === "Audio" ? 1 : modelData.mode === "Transcript" ? 2 : 0
                                }
                            }
                        }
                    }
                }

                Row {
                    spacing: root.px(8)

                    Rectangle {
                        width: root.px(18)
                        height: root.px(18)
                        radius: root.px(5)
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.playlist ? ThemeBackend.mauve : ThemeBackend.surface0
                        Text {
                            anchors.centerIn: parent
                            visible: root.playlist
                            text: "✓"
                            font.pixelSize: root.px(12)
                            font.bold: true
                            color: ThemeBackend.base
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.playlist = !root.playlist
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Playlist mode (keeps order, adds a folder)"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.px(11)
                        color: ThemeBackend.subtext0
                    }
                }

                Row {
                    width: col.width
                    spacing: root.px(6)
                    Btn {
                        width: (col.width - openBtn.width - queueBtn.width - root.px(12)) / 2
                        primary: true
                        label: root.busy ? "Stop" : "Download"
                        onClicked: root.busy ? root.stop() : root.start()
                    }
                    Btn {
                        id: queueBtn
                        width: root.px(86)
                        label: "Queue"
                        onClicked: root.enqueue()
                    }
                    Btn {
                        id: openBtn
                        width: root.px(110)
                        label: "Open folder"
                        onClicked: root.openFolder()
                    }
                }

                Row {
                    visible: root.queue.length > 0
                    width: col.width
                    spacing: root.px(6)
                    Text {
                        width: parent.width - queueStartBtn.width
                        text: root.queue.length + " queued"
                        font.family: root.clockFont
                        font.pixelSize: root.px(11)
                        color: ThemeBackend.subtext0
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Btn {
                        id: queueStartBtn
                        width: root.px(110)
                        label: "Start queue"
                        onClicked: root.startQueue()
                    }
                }

                Rectangle {
                    visible: root.busy
                    width: col.width
                    height: root.px(5)
                    radius: height / 2
                    color: ThemeBackend.surface1
                    Rectangle {
                        width: parent.width * Math.max(0.02, Math.min(1, root.percent / 100))
                        height: parent.height
                        radius: height / 2
                        color: ThemeBackend.mauve
                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                }

                Text {
                    visible: root.statusText !== "" || !root.depsOk
                    width: col.width
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: root.depsOk ? root.statusText : ("Missing: " + root.missingTools + " (install it, then reopen this panel)")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.px(11)
                    color: (root.statusError || !root.depsOk) ? ThemeBackend.peach : ThemeBackend.subtext0
                }
            }
        }
    }
}
