import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../"
import "music"

Item {
    id: root

    // Serpantinum QuickAction module contract.
    property int requestedLayoutTemplate: 1
    property bool isActiveTab: typeof isCurrentTarget !== "undefined" ? isCurrentTarget : true
    property string safeActiveEdge: typeof activeEdge !== "undefined" ? activeEdge : "left"

    function s(v) { return typeof scaleFunc === "function" ? scaleFunc(v) : v }

    property real baseW: s(400)
    property real baseL: s(470)
    property real preferredWidth: (safeActiveEdge === "bottom" || safeActiveEdge === "top") ? baseL + s(50) : baseW
    property real preferredExtraLength: (safeActiveEdge === "bottom" || safeActiveEdge === "top") ? baseW : baseL

    property real counterRotation: {
        if (safeActiveEdge === "right") return 180
        if (safeActiveEdge === "bottom") return 90
        if (safeActiveEdge === "top") return -90
        return 0
    }

    readonly property string icoPlay: String.fromCodePoint(0xF040A)
    readonly property string icoPause: String.fromCodePoint(0xF03E4)
    readonly property string icoNext: String.fromCodePoint(0xF04AD)
    readonly property string icoPrev: String.fromCodePoint(0xF04AE)
    readonly property string icoShuffle: String.fromCodePoint(0xF049F)
    readonly property string icoRepeat: String.fromCodePoint(0xF0456)
    readonly property string icoRepeatOnce: String.fromCodePoint(0xF0458)
    readonly property string icoNote: String.fromCodePoint(0xF075A)
    readonly property string icoRefresh: String.fromCodePoint(0xF0450)

    // Local engine instance: QuickAction Loader destroys it when this tab unloads.
    MusicEngine {
        id: musicEngine
    }

    Component.onCompleted: musicEngine.activate()

    implicitWidth: root.preferredWidth
    implicitHeight: root.preferredExtraLength

    Item {
        id: orientedRoot
        anchors.centerIn: parent
        width: (root.counterRotation % 180 !== 0) ? parent.height : parent.width
        height: (root.counterRotation % 180 !== 0) ? parent.width : parent.height
        rotation: root.counterRotation
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: root.s(12)
            color: ThemeBackend.surface0
            border.width: 1
            border.color: ThemeBackend.surface1
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.s(14)
                spacing: root.s(10)

                // ---- now playing ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.s(12)

                    Rectangle {
                        Layout.preferredWidth: root.s(64)
                        Layout.preferredHeight: root.s(64)
                        radius: root.s(12)
                        color: ThemeBackend.base
                        border.width: 1
                        border.color: ThemeBackend.surface1

                        Text {
                            anchors.centerIn: parent
                            text: root.icoNote
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(27)
                            color: ThemeBackend.text
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: parent.height * musicEngine.progress
                            radius: parent.radius
                            color: ThemeBackend.mauve
                            opacity: 0.45
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: root.s(2)

                        Text {
                            text: "NOW PLAYING"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(9)
                            font.weight: Font.Black
                            font.bold: true
                            font.letterSpacing: 0.4
                            color: ThemeBackend.subtext0
                        }

                        Text {
                            Layout.fillWidth: true
                            text: musicEngine.hasTrack ? musicEngine.title : "Nothing playing"
                            elide: Text.ElideRight
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(16)
                            font.weight: Font.Black
                            font.bold: true
                            font.letterSpacing: -0.5
                            color: ThemeBackend.text
                        }

                        Text {
                            Layout.fillWidth: true
                            text: {
                                if (musicEngine.hasTrack) {
                                    if (musicEngine.artist !== "") return musicEngine.artist
                                    let i = musicEngine.currentIndex
                                    return i >= 0 ? musicEngine.library[i].sub : ""
                                }
                                if (musicEngine.status !== "") return musicEngine.status
                                return musicEngine.libraryCount + (musicEngine.libraryCount === 1 ? " track" : " tracks")
                            }
                            elide: Text.ElideRight
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(10)
                            color: (!musicEngine.hasTrack && musicEngine.status !== "") ? ThemeBackend.peach : ThemeBackend.subtext0
                        }
                    }
                }

                // ---- seekbar ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.s(7)

                    Text {
                        Layout.preferredWidth: root.s(38)
                        text: musicEngine.fmt(seekBar.dragging ? seekBar.dragValue * musicEngine.duration : musicEngine.position)
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(9)
                        font.weight: Font.Black
                        color: ThemeBackend.subtext0
                    }

                    Item {
                        id: seekBar
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.s(18)

                        property bool dragging: false
                        property real dragValue: 0
                        readonly property real shown: dragging ? dragValue : musicEngine.progress

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: root.s(5)
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
                            width: root.s(11)
                            height: width
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, Math.min(parent.width - width, parent.width * seekBar.shown - width / 2))
                            color: ThemeBackend.text
                            opacity: (seekMa.containsMouse || seekBar.dragging) && musicEngine.hasTrack ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 100 } }
                        }

                        MouseArea {
                            id: seekMa
                            anchors.fill: parent
                            enabled: musicEngine.hasTrack
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            function val(mx) { return Math.max(0, Math.min(1, mx / width)) }

                            onPressed: mouse => {
                                seekBar.dragging = true
                                seekBar.dragValue = val(mouse.x)
                            }
                            onPositionChanged: mouse => {
                                if (pressed) seekBar.dragValue = val(mouse.x)
                            }
                            onReleased: {
                                musicEngine.seek(seekBar.dragValue * musicEngine.duration)
                                seekBar.dragging = false
                            }
                            onCanceled: seekBar.dragging = false
                        }
                    }

                    Text {
                        Layout.preferredWidth: root.s(38)
                        horizontalAlignment: Text.AlignRight
                        text: musicEngine.fmt(musicEngine.duration)
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(9)
                        font.weight: Font.Black
                        color: ThemeBackend.subtext0
                    }
                }

                // ---- transport ----
                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: root.s(9)

                    IconBtn {
                        glyph: root.icoShuffle
                        iconSize: root.s(17)
                        box: root.s(32)
                        tint: musicEngine.shuffle ? ThemeBackend.mauve : ThemeBackend.subtext0
                        onClicked: musicEngine.toggleShuffle()
                    }

                    IconBtn {
                        glyph: root.icoPrev
                        iconSize: root.s(21)
                        box: root.s(36)
                        tint: ThemeBackend.text
                        onClicked: musicEngine.prev()
                    }

                    Rectangle {
                        Layout.preferredWidth: root.s(48)
                        Layout.preferredHeight: root.s(48)
                        radius: width / 2
                        color: ThemeBackend.mauve
                        scale: playMa.pressed ? 0.94 : (playMa.containsMouse ? 1.05 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: musicEngine.playing ? root.icoPause : root.icoPlay
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(21)
                            color: ThemeBackend.base
                        }

                        MouseArea {
                            id: playMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: musicEngine.togglePlay()
                        }
                    }

                    IconBtn {
                        glyph: root.icoNext
                        iconSize: root.s(21)
                        box: root.s(36)
                        tint: ThemeBackend.text
                        onClicked: musicEngine.next()
                    }

                    IconBtn {
                        glyph: musicEngine.repeatMode === 2 ? root.icoRepeatOnce : root.icoRepeat
                        iconSize: root.s(17)
                        box: root.s(32)
                        tint: musicEngine.repeatMode > 0 ? ThemeBackend.mauve : ThemeBackend.subtext0
                        onClicked: musicEngine.cycleRepeat()
                    }
                }

                // ---- library header ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.s(5)

                    Text {
                        text: "LIBRARY"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(9)
                        font.weight: Font.Black
                        font.bold: true
                        font.letterSpacing: 0.35
                        color: ThemeBackend.subtext0
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: musicEngine.libraryCount + (musicEngine.libraryCount === 1 ? " track" : " tracks")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(9)
                        color: ThemeBackend.subtext0
                    }

                    IconBtn {
                        glyph: root.icoRefresh
                        iconSize: root.s(13)
                        box: root.s(23)
                        tint: ThemeBackend.subtext0
                        onClicked: musicEngine.rescan()
                    }
                }

                // ---- library list ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: root.s(10)
                    color: ThemeBackend.base
                    border.width: 1
                    border.color: ThemeBackend.surface1
                    clip: true

                    ListView {
                        id: list
                        anchors.fill: parent
                        anchors.margins: root.s(4)
                        clip: true
                        spacing: root.s(2)
                        boundsBehavior: Flickable.StopAtBounds
                        model: musicEngine.library

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool current: modelData.path === musicEngine.currentPath

                            width: ListView.view.width
                            height: root.s(34)
                            radius: root.s(8)
                            color: current
                                ? Qt.rgba(ThemeBackend.mauve.r, ThemeBackend.mauve.g, ThemeBackend.mauve.b, 0.18)
                                : (rowMa.containsMouse ? ThemeBackend.surface1 : "transparent")

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: root.s(9)
                                anchors.rightMargin: root.s(8)
                                spacing: root.s(8)

                                Text {
                                    Layout.preferredWidth: root.s(18)
                                    horizontalAlignment: Text.AlignHCenter
                                    text: row.current ? root.icoNote : String(row.index + 1)
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: row.current ? root.s(12) : root.s(9)
                                    color: row.current ? ThemeBackend.mauve : ThemeBackend.subtext0
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.s(10.5)
                                    font.weight: row.current ? Font.Black : Font.Bold
                                    font.bold: true
                                    color: row.current ? ThemeBackend.mauve : ThemeBackend.text
                                }

                                Text {
                                    Layout.maximumWidth: root.s(90)
                                    text: row.modelData.sub
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.s(8.5)
                                    color: ThemeBackend.subtext0
                                }
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: musicEngine.playPath(row.modelData.path)
                            }
                        }
                    }

                    Rectangle {
                        visible: list.visibleArea.heightRatio < 1
                        anchors.right: parent.right
                        anchors.rightMargin: root.s(2)
                        width: root.s(3)
                        radius: width / 2
                        color: ThemeBackend.surface2
                        y: list.y + list.visibleArea.yPosition * list.height
                        height: Math.max(root.s(18), list.visibleArea.heightRatio * list.height)
                    }

                    Text {
                        visible: musicEngine.scanned && musicEngine.libraryCount === 0
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: musicEngine.status !== "" ? musicEngine.status : "No music found in\n" + musicEngine.musicDir
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(10)
                        color: musicEngine.status !== "" ? ThemeBackend.peach : ThemeBackend.subtext0
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
