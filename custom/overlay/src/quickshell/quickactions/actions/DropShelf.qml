import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../"
import "Model.js" as Model

Item {
    id: root

    property int requestedLayoutTemplate: 1
    property bool isActiveTab: typeof isCurrentTarget !== "undefined" ? isCurrentTarget : true
    property string safeActiveEdge: typeof activeEdge !== "undefined" ? activeEdge : "left"

    function s(v) {
        return typeof scaleFunc === "function" ? scaleFunc(v) : v;
    }

    property real baseW: s(360)
    property real baseL: s(420)
    property real preferredWidth: (root.safeActiveEdge === "bottom" || root.safeActiveEdge === "top") ? baseL : baseW
    property real preferredExtraLength: (root.safeActiveEdge === "bottom" || root.safeActiveEdge === "top") ? baseW : baseL

    property real counterRotation: {
        if (root.safeActiveEdge === "right") return 180;
        if (root.safeActiveEdge === "bottom") return 90;
        if (root.safeActiveEdge === "top") return -90;
        return 0;
    }

    property var entries: []
    property string statusText: "Drop files here"
    property var pendingCandidates: []
    property int candidateAttempts: 0
    readonly property int maxCandidateAttempts: 4
    property var lastRemovedEntry: null
    property string activeDragUri: ""
    property bool selfDrop: false

    readonly property string stateDir: {
        const configured = Quickshell.env("XDG_STATE_HOME");
        return configured && configured.length > 0
            ? configured + "/serpantinum/dropshelf"
            : (Quickshell.env("HOME") || "~") + "/.local/state/serpantinum/dropshelf";
    }
    readonly property string statePath: root.stateDir + "/shelf.json"
    readonly property string dataDir: {
        const configured = Quickshell.env("XDG_DATA_HOME");
        return configured && configured.length > 0
            ? configured + "/serpantinum/dropshelf"
            : (Quickshell.env("HOME") || "~") + "/.local/share/serpantinum/dropshelf";
    }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function mutedColor() { return alpha(ThemeBackend.text, 0.62); }
    function subtleColor() { return alpha(ThemeBackend.text, 0.08); }
    function hairlineColor() { return alpha(ThemeBackend.text, 0.18); }
    function bgColor() { return ThemeBackend.surface0 || alpha(ThemeBackend.text, 0.06); }
    function accentColor() { return ThemeBackend.mauve; }
    function radius() { return Math.max(0, s(ThemeBackend.borderRadius || 8)); }

    function updateStatus() {
        statusText = entries.length === 0
            ? "Drop files or images here"
            : entries.length + (entries.length === 1 ? " item" : " items");
    }

    function loadState(text) {
        entries = Model.parseState(text);
        updateStatus();
    }

    function persist() {
        writer.command = [
            "bash", "-c",
            "umask 077; mkdir -p -- \"$1\" && printf '%s' \"$2\" > \"$3\"",
            "serpantinum-dropshelf", root.stateDir, Model.serialize(entries), root.statePath
        ];
        writer.running = true;
    }

    function removeAt(index) {
        entries = Model.removeAt(entries, index);
        lastRemovedEntry = null;
        updateStatus();
        persist();
    }

    function removeAfterDrag(uri) {
        const matches = entries.filter(function(item) { return item.uri === uri; });
        if (matches.length === 0) return;
        lastRemovedEntry = matches[0];
        entries = Model.removeUri(entries, uri);
        statusText = "Dragged out — Undo to restore";
        persist();
    }

    function undoRemove() {
        if (!lastRemovedEntry) return;
        entries = Model.addUrls(entries, [lastRemovedEntry.uri]);
        lastRemovedEntry = null;
        updateStatus();
        persist();
    }

    function clearShelf() {
        entries = [];
        lastRemovedEntry = null;
        statusText = "Shelf cleared";
        persist();
    }

    function imageMimeFormat(formats) {
        const preferred = ["image/gif", "image/webp", "image/png", "image/jpeg", "image/avif", "image/bmp"];
        for (let i = 0; i < preferred.length; i++)
            if (formats.indexOf(preferred[i]) !== -1) return preferred[i];
        return "";
    }

    function firstMimeText(drop, formats) {
        for (let i = 0; i < formats.length; i++) {
            if ((drop.formats || []).indexOf(formats[i]) === -1) continue;
            const value = String(drop.getDataAsString(formats[i]) || "").trim();
            if (value !== "") return value;
        }
        return "";
    }

    function anyTextMime(drop) {
        const formats = drop.formats || [];
        for (let i = 0; i < formats.length; i++) {
            const format = String(formats[i]);
            if (!/^text\//i.test(format) && format.toLowerCase().indexOf("url") === -1) continue;
            const value = String(drop.getDataAsString(format) || "").trim();
            if (value.indexOf("http://") !== -1 || value.indexOf("https://") !== -1)
                return value;
        }
        return "";
    }

    function addDrop(drop) {
        const urls = Model.localUrls(drop.urls || []);
        if (urls.length > 0) {
            if (activeDragUri !== "" && urls.indexOf(activeDragUri) !== -1)
                selfDrop = true;
            const next = Model.addUrls(entries, urls);
            const added = next.length - entries.length;
            entries = next;
            statusText = added > 0 ? "Added " + added + (added === 1 ? " item" : " items") : "Already on the shelf";
            persist();
            return;
        }

        if (downloader.running || imageWriter.running) {
            statusText = "Please wait for the current image";
            return;
        }

        const nativeUrl = firstMimeText(drop, [
            "application/x-moz-file-promise-url",
            "application/x-moz-url",
            "text/x-moz-url",
            "DownloadURL"
        ]) || anyTextMime(drop);

        const directLinks = Model.webUrls(
            drop.urls || [],
            drop.hasText ? drop.text : "",
            nativeUrl
        );

        pendingCandidates = Model.remoteImageCandidates(
            drop.urls || [],
            drop.hasText ? drop.text : "",
            drop.hasHtml ? drop.html : "",
            nativeUrl
        );
        candidateAttempts = 0;

        const imageFormat = imageMimeFormat(drop.formats || []);
        if (imageFormat !== "") {
            importBase64Image(imageFormat, Model.base64FromArrayBuffer(drop.getDataAsArrayBuffer(imageFormat)));
            return;
        }

        const imageCandidates = pendingCandidates.filter(function(candidate) {
            return Model.looksLikeImageSource(candidate);
        });

        if (imageCandidates.length > 0) {
            pendingCandidates = imageCandidates;
            tryNextCandidate();
            return;
        }

        if (directLinks.length > 0) {
            const next = Model.addUrls(entries, directLinks);
            const added = next.length - entries.length;
            entries = next;
            statusText = added > 0
                ? "Added " + added + (added === 1 ? " link" : " links")
                : "Already on the shelf";
            persist();
            return;
        }

        statusText = "Drop a local file, image, or link";
    }

    function tryNextCandidate() {
        if (candidateAttempts >= maxCandidateAttempts || pendingCandidates.length === 0) {
            pendingCandidates = [];
            statusText = "Could not save that image";
            return;
        }
        const next = String(pendingCandidates.shift());
        candidateAttempts++;
        const data = Model.parseDataUri(next);
        if (data !== null) {
            importBase64Image(data.mime, data.base64);
            return;
        }
        startDownload(next);
    }

    function importFinished() {
        pendingCandidates = [];
        candidateAttempts = 0;
    }

    function importBase64Image(mime, base64) {
        const suffix = String(mime).split("/").pop().replace(/[^a-zA-Z0-9]/g, "") || "img";
        statusText = "Saving image…";
        imageWriter.command = [
            "bash", "-c",
            "set -e; umask 077; mkdir -p -- \"$1\"; out=$(mktemp --tmpdir=\"$1\" dropshelf-XXXXXX.\"$2\"); trap 'rm -f -- \"$out\"' EXIT; base64 -d > \"$out\"; file -Lb --mime-type \"$out\" | grep -q '^image/'; trap - EXIT; printf '%s' \"$out\"",
            "serpantinum-dropshelf", root.dataDir, suffix
        ];
        imageWriter.stdinEnabled = true;
        imageWriter.running = true;
        imageWriter.write(base64);
        imageWriter.stdinEnabled = false;
    }

    function startDownload(url) {
        statusText = candidateAttempts > 1 ? "Saving image… (trying another source)" : "Saving image…";
        downloader.command = [
            "bash", "-c",
            "set -e; umask 077; mkdir -p -- \"$1\"; out=$(mktemp --tmpdir=\"$1\" dropshelf-XXXXXX); trap 'rm -f -- \"$out\"' EXIT; curl -fL --max-time 30 --max-filesize 52428800 --proto '=http,https' -A 'Mozilla/5.0' -e \"$3\" -o \"$out\" -- \"$2\"; mime=$(file -Lb --mime-type \"$out\"); case \"$mime\" in image/*) ;; *) exit 65 ;; esac; ext=$(printf '%s' \"${mime#image/}\" | tr -cd 'a-zA-Z0-9'); final=\"${out}.${ext:-img}\"; mv -- \"$out\" \"$final\"; trap - EXIT; printf '%s' \"$final\"",
            "serpantinum-dropshelf", root.dataDir, url, Model.refererFor(url)
        ];
        downloader.running = true;
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.loadState(text())
        onLoadFailed: root.loadState("")
    }

    Process {
        id: writer
        running: false
        onExited: function(exitCode) {
            if (exitCode === 0) stateFile.reload();
            else root.statusText = "Could not save shelf";
        }
    }

    Process {
        id: downloader
        running: false
        stdout: StdioCollector { id: downloadOutput; waitForEnd: true }
        onExited: function(exitCode) {
            const path = String(downloadOutput.text || "").trim();
            if (exitCode !== 0 || path === "") {
                root.tryNextCandidate();
                return;
            }
            root.importFinished();
            const uri = "file://" + encodeURI(path);
            root.entries = Model.addUrls(root.entries, [uri]);
            root.statusText = "Image added";
            root.persist();
        }
    }

    Process {
        id: imageWriter
        running: false
        stdout: StdioCollector { id: imageWriterOutput; waitForEnd: true }
        onExited: function(exitCode) {
            const path = String(imageWriterOutput.text || "").trim();
            if (exitCode !== 0 || path === "") {
                root.tryNextCandidate();
                return;
            }
            root.importFinished();
            const uri = "file://" + encodeURI(path);
            root.entries = Model.addUrls(root.entries, [uri]);
            root.statusText = "Image added";
            root.persist();
        }
    }

    Item {
        id: rotatedRoot
        anchors.fill: parent
        rotation: root.counterRotation
        transformOrigin: Item.Center

        Rectangle {
            anchors.fill: parent
            radius: root.radius()
            color: alpha(ThemeBackend.surface0, 0.98)
            border.width: Math.max(1, root.s(1))
            border.color: hairlineColor()
            clip: true

            DropArea {
                id: dropArea
                anchors.fill: parent
                anchors.margins: root.s(2)

                onDropped: function(drop) {
                    drop.acceptProposedAction();
                    root.addDrop(drop);
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: root.s(5)
                    radius: Math.max(0, root.radius() - root.s(2))
                    color: dropArea.containsDrag ? alpha(accentColor(), 0.10) : "transparent"
                    border.width: dropArea.containsDrag ? root.s(2) : 0
                    border.color: accentColor()
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(14)
                    spacing: root.s(10)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(10)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: root.s(1)

                            Text {
                                Layout.fillWidth: true
                                text: "Drop Shelf"
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(18)
                                font.weight: Font.Black
                                font.bold: true
                                color: ThemeBackend.text
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.statusText
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(9)
                                font.weight: Font.Black
                                font.bold: true
                                color: mutedColor()
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            spacing: root.s(6)

                            Rectangle {
                                visible: root.lastRemovedEntry !== null
                                width: undoText.implicitWidth + root.s(18)
                                height: root.s(28)
                                radius: Math.max(0, root.radius() - root.s(2))
                                color: alpha(ThemeBackend.text, 0.07)
                                border.width: root.s(1)
                                border.color: hairlineColor()

                                Text {
                                    id: undoText
                                    anchors.centerIn: parent
                                    text: "Undo"
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.s(9)
                                    font.weight: Font.Black
                                    color: ThemeBackend.text
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.undoRemove()
                                }
                            }

                            Rectangle {
                                visible: root.entries.length > 0
                                width: clearText.implicitWidth + root.s(18)
                                height: root.s(28)
                                radius: Math.max(0, root.radius() - root.s(2))
                                color: alpha(ThemeBackend.text, 0.07)
                                border.width: root.s(1)
                                border.color: hairlineColor()

                                Text {
                                    id: clearText
                                    anchors.centerIn: parent
                                    text: "Clear"
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.s(9)
                                    font.weight: Font.Black
                                    color: ThemeBackend.text
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.clearShelf()
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: root.s(1)
                        color: hairlineColor()
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, root.s(280))
                            spacing: root.s(8)
                            visible: root.entries.length === 0

                            Text {
                                width: parent.width
                                text: dropArea.containsDrag ? "󰉋" : "󰉋"
                                horizontalAlignment: Text.AlignHCenter
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(38)
                                color: dropArea.containsDrag ? accentColor() : mutedColor()
                            }
                            Text {
                                width: parent.width
                                text: dropArea.containsDrag ? "Release to add" : "Drop files, images, or links here"
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(13)
                                font.weight: Font.Black
                                font.bold: true
                                color: ThemeBackend.text
                            }
                            Text {
                                width: parent.width
                                text: "Files stay where they are. Images are saved privately. Links are stored and can be opened or dragged out."
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(9)
                                color: mutedColor()
                            }
                        }

                        GridView {
                            id: shelfGrid
                            anchors.fill: parent
                            visible: root.entries.length > 0
                            clip: true
                            model: root.entries
                            cellWidth: width / Math.max(1, Math.floor(width / root.s(112)))
                            cellHeight: root.s(128)
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Item {
                                id: tile
                                required property var modelData
                                required property int index

                                width: shelfGrid.cellWidth
                                height: shelfGrid.cellHeight

                                readonly property string uri: String(modelData.uri || "")
                                readonly property string name: String(modelData.name || "File")
                                readonly property bool linkItem: String(modelData.kind || "") === "link" || Model.isWebUrl(uri)
                                readonly property bool imageFile: !linkItem && Model.isImage(name)
                                property var grabResult: null

                                Rectangle {
                                    id: tileSurface
                                    anchors.fill: parent
                                    anchors.margins: root.s(5)
                                    radius: Math.max(0, root.radius() - root.s(1))
                                    color: tileMouse.containsMouse || tile.Drag.active ? subtleColor() : "transparent"
                                    border.width: root.s(1)
                                    border.color: tile.Drag.active ? accentColor() : hairlineColor()

                                    Image {
                                        id: thumbnail
                                        anchors.top: parent.top
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.topMargin: root.s(9)
                                        width: root.s(70)
                                        height: root.s(70)
                                        source: tile.imageFile ? tile.uri : ""
                                        visible: tile.imageFile && status === Image.Ready
                                        asynchronous: true
                                        cache: true
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize: Qt.size(width * 2, height * 2)
                                    }

                                    Text {
                                        anchors.centerIn: thumbnail
                                        visible: !thumbnail.visible
                                        text: tile.linkItem ? "󰌷" : "󰈔"
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: root.s(34)
                                        color: mutedColor()
                                    }

                                    Rectangle {
                                        visible: tile.linkItem
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.margins: root.s(8)
                                        width: linkBadge.implicitWidth + root.s(10)
                                        height: root.s(20)
                                        radius: root.s(10)
                                        color: alpha(accentColor(), 0.14)
                                        border.width: root.s(1)
                                        border.color: alpha(accentColor(), 0.35)
                                        z: 2

                                        Text {
                                            id: linkBadge
                                            anchors.centerIn: parent
                                            text: "LINK"
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: root.s(7)
                                            font.weight: Font.Black
                                            color: accentColor()
                                        }
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: root.s(8)
                                        text: tile.name
                                        textFormat: Text.PlainText
                                        horizontalAlignment: Text.AlignHCenter
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: root.s(8)
                                        font.weight: Font.Black
                                        color: ThemeBackend.text
                                        elide: Text.ElideMiddle
                                    }

                                    Rectangle {
                                        id: removeButton
                                        width: root.s(22)
                                        height: width
                                        radius: width / 2
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: root.s(5)
                                        visible: tileMouse.containsMouse && !tile.Drag.active
                                        z: 2
                                        color: alpha(ThemeBackend.surface0, 0.92)
                                        border.width: root.s(1)
                                        border.color: hairlineColor()

                                        Text {
                                            anchors.centerIn: parent
                                            text: "×"
                                            font.pixelSize: root.s(14)
                                            font.weight: Font.Black
                                            color: ThemeBackend.text
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            z: 3
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.removeAt(tile.index)
                                        }
                                    }
                                }

                                Drag.active: tileMouse.drag.active
                                Drag.mimeData: ({ "text/uri-list": tile.uri + "\r\n" })
                                Drag.supportedActions: Qt.CopyAction
                                Drag.proposedAction: Qt.CopyAction
                                Drag.dragType: Drag.Automatic
                                Drag.imageSource: tile.imageFile ? tile.uri : ""
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: height / 2

                                Drag.onDragStarted: {
                                    root.activeDragUri = tile.uri;
                                    root.selfDrop = false;
                                }

                                Drag.onDragFinished: function(dropAction) {
                                    tile.x = 0;
                                    tile.y = 0;
                                    const droppedOnShelf = root.selfDrop && root.activeDragUri === tile.uri;
                                    root.activeDragUri = "";
                                    root.selfDrop = false;
                                    if (!droppedOnShelf)
                                        root.removeAfterDrag(tile.uri);
                                }

                                MouseArea {
                                    id: tileMouse
                                    anchors.fill: parent
                                    z: 1
                                    hoverEnabled: true
                                    cursorShape: tile.linkItem ? Qt.PointingHandCursor : Qt.OpenHandCursor
                                    drag.target: tile
                                    preventStealing: true

                                    onPressed: {
                                        if (!tile.imageFile) {
                                            tileSurface.grabToImage(function(result) {
                                                tile.grabResult = result;
                                                tile.Drag.imageSource = result.url;
                                            });
                                        }
                                    }

                                    onDoubleClicked: {
                                        if (tile.linkItem)
                                            Quickshell.execDetached(["xdg-open", tile.uri]);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
