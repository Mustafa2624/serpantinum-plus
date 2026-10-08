import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../../reusables"
import "../../../"
import "../../"
import "ScreenLayout.js" as ScreenLayout

Item {
    id: root

    property var module: null
    property var widget: module
    readonly property bool isCompact: module ? module.isCompact : false
    readonly property var barWindow: module ? module.barWindow : null
    readonly property bool moduleActive: module ? module.moduleActive : true
    property bool open: false

    // Only built while the overview is open; empty (and free) otherwise.
    property var windows: open ? collectWindows() : []

    readonly property real labelH: px(30)   // title row + spacing under each thumbnail
    readonly property string scriptPath: Qt.resolvedUrl("activate-window.sh").toString().replace("file://", "")

    function px(v) { return barWindow ? barWindow.s(v) : v }

    function wsOf(win) {
        return win && win.workspace ? win.workspace.id : 0;
    }

    function collectWindows() {
        let result = [];
        if (Hyprland.workspaces && Hyprland.workspaces.values) {
            for (const ws of Hyprland.workspaces.values) {
                if (!ws.toplevels || !ws.toplevels.values) continue;
                for (const win of ws.toplevels.values) result.push(win);
            }
        }
        // Group by workspace (special workspaces have negative ids and go last).
        const key = w => { const id = wsOf(w); return id > 0 ? id : 1000000 - id; };
        result.sort((a, b) => key(a) - key(b));
        return result;
    }

    function activate(win) {
        let address = win && win.lastIpcObject ? win.lastIpcObject.address : (win ? win.address : "");
        address = address ? String(address) : "";
        if (!/^0x[0-9a-fA-F]+$/.test(address)) return;
        open = false; // LazyLoader tears the overlay down right away
        // The script waits ~120ms for the layer to unmap, then focuses.
        Quickshell.execDetached(["bash", scriptPath, address]);
    }

    onOpenChanged: {
        if (ExposeState.open !== open) ExposeState.open = open;
        if (open && Hyprland.refreshToplevels) Hyprland.refreshToplevels();
    }

    Connections {
        target: ExposeState
        function onOpenChanged() {
            if (root.open !== ExposeState.open) root.open = ExposeState.open;
        }
    }

    implicitWidth: px(38)
    implicitHeight: parent ? parent.height : px(30)
    property real targetWidth: implicitWidth
    property bool isFaceVisible: moduleActive

    // ───────────────────────── bar button ─────────────────────────
    Item {
        id: exposeButton
        visible: root.moduleActive
        anchors.centerIn: parent
        width: root.px(30)
        height: root.px(30)

        readonly property bool hovered: btnMouse.containsMouse
        // 0 = resting, 0.5 = hover, 1 = open. Drives the gap between glyph tiles.
        property real spread: root.open ? 1 : (hovered ? 0.5 : 0)
        Behavior on spread { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        scale: btnMouse.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

        readonly property color tileColor: root.open ? ThemeBackend.base
                                         : hovered ? ThemeBackend.text
                                         : ThemeBackend.subtext1

        Rectangle {
            anchors.fill: parent
            radius: root.px(9)
            color: root.open ? ThemeBackend.mauve
                 : exposeButton.hovered ? (ThemeBackend.surface1 || ThemeBackend.surface0)
                 : ThemeBackend.surface0
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        Item {
            id: glyph
            anchors.centerIn: parent
            width: exposeButton.width * 0.5
            height: width

            readonly property real gap: exposeButton.width * (0.05 + 0.05 * exposeButton.spread)
            readonly property real tw: (width - gap) / 2
            readonly property real th: (height - gap) / 2
            readonly property real r: exposeButton.width * 0.07

            Rectangle {
                x: 0; y: 0
                width: glyph.tw; height: glyph.height
                radius: glyph.r; color: exposeButton.tileColor
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Rectangle {
                x: glyph.tw + glyph.gap; y: 0
                width: glyph.tw; height: glyph.th
                radius: glyph.r; color: exposeButton.tileColor
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Rectangle {
                x: glyph.tw + glyph.gap; y: glyph.th + glyph.gap
                width: glyph.tw; height: glyph.th
                radius: glyph.r; color: exposeButton.tileColor
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open = !root.open
        }
    }

    // ───────────────────────── overview (created on demand) ─────────────────────────
    LazyLoader {
        active: root.open && root.moduleActive && root.barWindow !== null

        PanelWindow {
            id: overview
            screen: root.barWindow ? root.barWindow.screen : null
            visible: true
            focusable: true
            color: "transparent"
            WlrLayershell.namespace: "serpantinum-expose-overview"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Index of the highlighted card (mouse hover or keyboard), -1 = none.
            property int current: -1

            property var gridLayout: ScreenLayout.fit(
                root.windows,
                width - root.px(68),
                height - root.px(120),
                root.px(18),
                root.labelH
            )

            function move(delta) {
                const n = root.windows.length;
                if (n === 0) return;
                if (current < 0) current = delta > 0 ? 0 : n - 1;
                else current = Math.max(0, Math.min(n - 1, current + delta));
            }

            Shortcut {
                sequence: "Escape"
                context: Qt.WindowShortcut
                onActivated: root.open = false
            }

            Rectangle {
                id: scrim
                anchors.fill: parent
                color: "#a6000000"
                focus: true
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

                Keys.onPressed: (e) => {
                    const cols = overview.gridLayout.columns;
                    if (e.key === Qt.Key_Escape) root.open = false;
                    else if (e.key === Qt.Key_Left) overview.move(-1);
                    else if (e.key === Qt.Key_Right) overview.move(1);
                    else if (e.key === Qt.Key_Up) overview.move(-cols);
                    else if (e.key === Qt.Key_Down) overview.move(cols);
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        if (overview.current >= 0) root.activate(root.windows[overview.current]);
                    } else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                        const w = root.windows[e.key - Qt.Key_1];
                        if (w) root.activate(w);
                    } else return;
                    e.accepted = true;
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.open = false
                }

                ColumnLayout {
                    id: content
                    anchors.fill: parent
                    anchors.margins: root.px(34)
                    spacing: root.px(12)
                    scale: 0.97
                    Component.onCompleted: scale = 1
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "WINDOW OVERVIEW"
                            color: ThemeBackend.text
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.px(16)
                            font.weight: Font.Black
                            font.bold: true
                            Layout.fillWidth: true
                        }
                        Text {
                            text: root.windows.length + (root.windows.length === 1 ? " window" : " windows") + " · all workspaces"
                            color: ThemeBackend.subtext0
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.px(11)
                        }
                        Text {
                            text: "×"
                            color: closeMouse.containsMouse ? ThemeBackend.mauve : ThemeBackend.text
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.px(26)
                            horizontalAlignment: Text.AlignHCenter
                            Layout.preferredWidth: root.px(36)
                            Layout.leftMargin: root.px(12)
                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.open = false
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        GridLayout {
                            anchors.centerIn: parent
                            columns: overview.gridLayout.columns
                            rowSpacing: root.px(18)
                            columnSpacing: root.px(18)

                            Repeater {
                                model: root.windows
                                delegate: Item {
                                    id: card
                                    required property var modelData
                                    required property int index

                                    readonly property var win: modelData
                                    readonly property real aspect: ScreenLayout.aspectOf(win)
                                    readonly property bool highlighted: overview.current === index
                                    // Largest thumbnail that fits the card without distortion.
                                    readonly property real thumbW: Math.max(1, Math.min(width, Math.max(1, height - root.labelH) * aspect))
                                    readonly property real thumbH: thumbW / aspect
                                    readonly property int wsId: root.wsOf(win)

                                    Layout.preferredWidth: overview.gridLayout.cardWidth
                                    Layout.preferredHeight: overview.gridLayout.cardHeight

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: root.px(8)

                                        Item {
                                            id: thumb
                                            width: card.thumbW
                                            height: card.thumbH
                                            scale: card.highlighted ? 1.03 : 1
                                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: root.px(6)
                                                color: ThemeBackend.surface0
                                            }
                                            ScreencopyView {
                                                anchors.fill: parent
                                                captureSource: card.win.wayland
                                                // One snapshot when the overview opens; only the
                                                // highlighted card streams live.
                                                live: card.highlighted
                                                visible: hasContent
                                                Component.onCompleted: captureFrame()
                                            }
                                            // Dim everything except the highlighted card.
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: root.px(6)
                                                color: "black"
                                                opacity: overview.current >= 0 && !card.highlighted ? 0.35 : 0
                                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                            }
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: root.px(6)
                                                color: "transparent"
                                                border.width: root.px(2)
                                                border.color: card.highlighted ? ThemeBackend.mauve : "transparent"
                                                Behavior on border.color { ColorAnimation { duration: 120 } }
                                            }
                                        }

                                        RowLayout {
                                            width: card.thumbW
                                            spacing: root.px(8)

                                            Rectangle {
                                                Layout.preferredWidth: root.px(20)
                                                Layout.preferredHeight: root.px(20)
                                                radius: root.px(6)
                                                color: card.highlighted ? ThemeBackend.mauve : ThemeBackend.surface0
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: card.wsId > 0 ? card.wsId : "S"
                                                    color: card.highlighted ? ThemeBackend.base : ThemeBackend.mauve
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: root.px(11)
                                                    font.bold: true
                                                }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: card.win.title || (card.win.lastIpcObject ? card.win.lastIpcObject.class : "")
                                                elide: Text.ElideRight
                                                color: card.highlighted ? ThemeBackend.text : ThemeBackend.subtext0
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: root.px(12)
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: overview.current = card.index
                                        onExited: if (overview.current === card.index) overview.current = -1
                                        onClicked: root.activate(card.win)
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: root.windows.length === 0
                        Layout.alignment: Qt.AlignHCenter
                        text: "No windows open"
                        color: ThemeBackend.subtext0
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.px(12)
                    }
                }
            }
        }
    }
}
