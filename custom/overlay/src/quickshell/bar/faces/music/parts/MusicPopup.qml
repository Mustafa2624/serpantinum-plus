import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../../../"
import "."

PopupWindow {
    id: popup

    property var barWindow: null
    property Item anchorItem: null
    property real anchorX: 0
    property real anchorY: 0
    property double lastCleared: 0

    function px(v) { return barWindow ? barWindow.s(v) : v }

    // Material Design Icons (Nerd Font) code points
    readonly property string icoPlay: String.fromCodePoint(0xF040A)
    readonly property string icoPause: String.fromCodePoint(0xF03E4)
    readonly property string icoNext: String.fromCodePoint(0xF04AD)
    readonly property string icoPrev: String.fromCodePoint(0xF04AE)
    readonly property string icoShuffle: String.fromCodePoint(0xF049F)
    readonly property string icoRepeat: String.fromCodePoint(0xF0456)
    readonly property string icoRepeatOff: String.fromCodePoint(0xF0457)
    readonly property string icoRepeatOnce: String.fromCodePoint(0xF0458)
    readonly property string icoNote: String.fromCodePoint(0xF075A)
    readonly property string icoRefresh: String.fromCodePoint(0xF0450)

    anchor.window: barWindow
    anchor.rect.x: anchorX
    anchor.rect.y: anchorY
    anchor.rect.width: 1
    anchor.rect.height: 1

    implicitWidth: px(380)
    implicitHeight: px(470)
    color: "transparent"
    visible: false

    function toggle() {
        if (visible) { visible = false; return; }
        // the focus grab just closed us because of this same click
        if (Date.now() - lastCleared < 250) return;
        if (!anchorItem || !barWindow) return;

        let p = anchorItem.mapToItem(null, 0, 0);
        let margin = px(8);
        let x = p.x + anchorItem.width / 2 - implicitWidth / 2;
        x = Math.max(margin, Math.min(x, barWindow.width - implicitWidth - margin));
        anchorX = x;
        anchorY = p.y + anchorItem.height + px(8);
        MusicEngine.activate();
        visible = true;
    }

    onVisibleChanged: {
        if (!visible) return;
        enter.restart();
        if (MusicEngine.currentIndex >= 0)
            Qt.callLater(() => list.positionViewAtIndex(MusicEngine.currentIndex, ListView.Center));
    }

    HyprlandFocusGrab {
        windows: [popup]
        active: popup.visible
        onCleared: {
            popup.visible = false;
            popup.lastCleared = Date.now();
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: ThemeBackend.borderRadius + popup.px(4)
        color: ThemeBackend.base
        border.width: 1
        border.color: ThemeBackend.surface1

        transform: Translate { id: shift }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
            NumberAnimation { target: shift; property: "y"; from: -popup.px(10); to: 0; duration: 320; easing.type: Easing.OutQuint }
        }

        // faint circle in the corner, same feel as the wifi / volume popups
        Rectangle {
            width: popup.px(240)
            height: width
            radius: width / 2
            anchors.top: parent.top
            anchors.right: parent.right
            color: ThemeBackend.surface0
            opacity: 0.35
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: popup.px(16)
            spacing: popup.px(12)

            // ---- now playing ----
            RowLayout {
                Layout.fillWidth: true
                spacing: popup.px(14)

                Rectangle {
                    id: tile
                    Layout.preferredWidth: popup.px(84)
                    Layout.preferredHeight: popup.px(84)
                    radius: popup.px(14)
                    color: ThemeBackend.surface0
                    border.width: 1
                    border.color: ThemeBackend.surface1

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: parent.height * MusicEngine.progress
                        radius: parent.radius
                        color: ThemeBackend.mauve
                        opacity: 0.5
                        Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: popup.icoNote
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: popup.px(32)
                        color: ThemeBackend.text
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: popup.px(2)

                    Text {
                        text: "Now playing"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: popup.px(9)
                        font.weight: Font.Black
                        font.bold: true
                        font.letterSpacing: 0.2
                        color: ThemeBackend.subtext0
                    }
                    Text {
                        Layout.fillWidth: true
                        text: MusicEngine.hasTrack ? MusicEngine.title : "Nothing playing"
                        elide: Text.ElideRight
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: popup.px(16)
                        font.weight: Font.Black
                        font.bold: true
                        font.letterSpacing: -0.5
                        color: ThemeBackend.text
                    }
                    Text {
                        Layout.fillWidth: true
                        text: {
                            if (MusicEngine.hasTrack) {
                                if (MusicEngine.artist !== "") return MusicEngine.artist;
                                let i = MusicEngine.currentIndex;
                                return i >= 0 ? MusicEngine.library[i].sub : "";
                            }
                            if (MusicEngine.status !== "") return MusicEngine.status;
                            return MusicEngine.libraryCount + (MusicEngine.libraryCount === 1 ? " track" : " tracks");
                        }
                        elide: Text.ElideRight
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: popup.px(11)
                        color: (!MusicEngine.hasTrack && MusicEngine.status !== "") ? ThemeBackend.peach : ThemeBackend.subtext0
                    }
                }
            }

            // ---- seekbar ----
            RowLayout {
                Layout.fillWidth: true
                spacing: popup.px(8)

                Text {
                    Layout.preferredWidth: popup.px(38)
                    text: MusicEngine.fmt(seekBar.dragging ? seekBar.dragValue * MusicEngine.duration : MusicEngine.position)
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: popup.px(10)
                    font.weight: Font.Black
                    font.bold: true
                    color: ThemeBackend.subtext0
                }

                Item {
                    id: seekBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: popup.px(18)

                    property bool dragging: false
                    property real dragValue: 0
                    readonly property real shown: dragging ? dragValue : MusicEngine.progress

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: popup.px(5)
                        radius: height / 2
                        color: ThemeBackend.surface1

                        Rectangle {
                            width: parent.width * seekBar.shown
                            height: parent.height
                            radius: parent.radius
                            color: ThemeBackend.mauve
                        }
                    }

                    Rectangle {
                        width: popup.px(12)
                        height: width
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(parent.width - width, parent.width * seekBar.shown - width / 2))
                        color: ThemeBackend.text
                        opacity: (seekMa.containsMouse || seekBar.dragging) && MusicEngine.hasTrack ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    MouseArea {
                        id: seekMa
                        anchors.fill: parent
                        enabled: MusicEngine.hasTrack
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        function val(mx) { return Math.max(0, Math.min(1, mx / width)) }
                        onPressed: mouse => {
                            seekBar.dragging = true;
                            seekBar.dragValue = val(mouse.x);
                        }
                        onPositionChanged: mouse => {
                            if (pressed) seekBar.dragValue = val(mouse.x);
                        }
                        onReleased: {
                            MusicEngine.seek(seekBar.dragValue * MusicEngine.duration);
                            seekBar.dragging = false;
                        }
                        onCanceled: seekBar.dragging = false
                    }
                }

                Text {
                    Layout.preferredWidth: popup.px(38)
                    horizontalAlignment: Text.AlignRight
                    text: MusicEngine.fmt(MusicEngine.duration)
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: popup.px(10)
                    font.weight: Font.Black
                    font.bold: true
                    color: ThemeBackend.subtext0
                }
            }

            // ---- transport ----
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: popup.px(14)

                IconBtn {
                    glyph: popup.icoShuffle
                    iconSize: popup.px(17)
                    tint: MusicEngine.shuffle ? ThemeBackend.mauve : ThemeBackend.subtext0
                    onClicked: MusicEngine.toggleShuffle()
                }
                IconBtn {
                    glyph: popup.icoPrev
                    iconSize: popup.px(22)
                    onClicked: MusicEngine.prev()
                }
                Rectangle {
                    Layout.preferredWidth: popup.px(48)
                    Layout.preferredHeight: popup.px(48)
                    radius: width / 2
                    color: ThemeBackend.mauve
                    scale: playMa.pressed ? 0.94 : (playMa.containsMouse ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    Text {
                        anchors.centerIn: parent
                        text: MusicEngine.playing ? popup.icoPause : popup.icoPlay
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: popup.px(22)
                        color: ThemeBackend.base
                    }
                    MouseArea {
                        id: playMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MusicEngine.togglePlay()
                    }
                }
                IconBtn {
                    glyph: popup.icoNext
                    iconSize: popup.px(22)
                    onClicked: MusicEngine.next()
                }
                IconBtn {
                    glyph: MusicEngine.repeatMode === 2 ? popup.icoRepeatOnce : popup.icoRepeat
                    iconSize: popup.px(17)
                    tint: MusicEngine.repeatMode > 0 ? ThemeBackend.mauve : ThemeBackend.subtext0
                    onClicked: MusicEngine.cycleRepeat()
                }
            }

            // ---- library ----
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Library"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: popup.px(9)
                    font.weight: Font.Black
                    font.bold: true
                    font.letterSpacing: 0.2
                    color: ThemeBackend.subtext0
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: MusicEngine.libraryCount + (MusicEngine.libraryCount === 1 ? " track" : " tracks")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: popup.px(9)
                    color: ThemeBackend.subtext0
                }
                IconBtn {
                    glyph: popup.icoRefresh
                    iconSize: popup.px(13)
                    box: popup.px(22)
                    tint: ThemeBackend.subtext0
                    onClicked: MusicEngine.rescan()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: popup.px(12)
                color: ThemeBackend.surface0
                border.width: 1
                border.color: ThemeBackend.surface1

                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.margins: popup.px(4)
                    clip: true
                    spacing: popup.px(2)
                    boundsBehavior: Flickable.StopAtBounds
                    model: MusicEngine.library

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool current: modelData.path === MusicEngine.currentPath

                        width: ListView.view.width
                        height: popup.px(34)
                        radius: popup.px(8)
                        color: current
                            ? Qt.rgba(ThemeBackend.mauve.r, ThemeBackend.mauve.g, ThemeBackend.mauve.b, 0.2)
                            : (rowMa.containsMouse ? ThemeBackend.surface1 : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: popup.px(10)
                            anchors.rightMargin: popup.px(10)
                            spacing: popup.px(10)

                            Text {
                                Layout.preferredWidth: popup.px(18)
                                horizontalAlignment: Text.AlignHCenter
                                text: row.current ? popup.icoNote : String(row.index + 1)
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: row.current ? popup.px(13) : popup.px(9)
                                color: row.current ? ThemeBackend.mauve : ThemeBackend.subtext0
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                elide: Text.ElideRight
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: popup.px(11)
                                font.weight: row.current ? Font.Black : Font.Bold
                                font.bold: true
                                color: row.current ? ThemeBackend.mauve : ThemeBackend.text
                            }
                            Text {
                                Layout.maximumWidth: popup.px(90)
                                text: row.modelData.sub
                                elide: Text.ElideRight
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: popup.px(9)
                                color: ThemeBackend.subtext0
                            }
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MusicEngine.playPath(row.modelData.path)
                        }
                    }
                }

                // thin scroll indicator
                Rectangle {
                    visible: list.visibleArea.heightRatio < 1
                    anchors.right: parent.right
                    anchors.rightMargin: popup.px(2)
                    width: popup.px(3)
                    radius: width / 2
                    color: ThemeBackend.surface2
                    y: list.y + list.visibleArea.yPosition * list.height
                    height: Math.max(popup.px(18), list.visibleArea.heightRatio * list.height)
                }

                Text {
                    visible: MusicEngine.scanned && MusicEngine.libraryCount === 0
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "No music found in\n" + MusicEngine.musicDir
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: popup.px(11)
                    color: ThemeBackend.subtext0
                }
            }
        }
    }
}
