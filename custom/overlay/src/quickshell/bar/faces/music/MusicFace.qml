import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../reusables"
import "../../../"
import "parts"

Item {
    id: root

    property var module: null
    property var widget: module

    readonly property bool isCompact: module ? module.isCompact : false
    readonly property var barWindow: module ? module.barWindow : null

    // ---- edit these ----
    property real titleMaxWidth: 150
    // --------------------

    function px(v) { return barWindow ? barWindow.s(v) : v }
    function tone(c) { return isCompact ? Qt.lighter(c, 1.1) : c }

    readonly property bool live: !module || module.moduleActive
    onLiveChanged: { if (live) MusicEngine.activate(); }
    Component.onCompleted: { if (live) MusicEngine.activate(); }

    readonly property string icoPlay: String.fromCodePoint(0xF040A)
    readonly property string icoPause: String.fromCodePoint(0xF03E4)
    readonly property string icoNext: String.fromCodePoint(0xF04AD)
    readonly property string icoPrev: String.fromCodePoint(0xF04AE)

    property bool showLayout: false
    property real horizontalPadding: px(isCompact ? 12 : 14)

    Timer {
        running: (!module || module.moduleActive) && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: root.showLayout = true
    }

    property real targetWidth: (live && mainRow.implicitWidth > 0) ? (mainRow.implicitWidth + horizontalPadding * 2) : 0
    property bool isFaceVisible: showLayout && targetWidth > 0

    implicitWidth: targetWidth
    implicitHeight: parent ? parent.height : 0

    opacity: showLayout ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    transform: Translate {
        x: root.showLayout ? 0 : root.px(40)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    MusicPopup {
        id: popup
        barWindow: root.barWindow
        anchorItem: root
    }

    Row {
        id: mainRow
        anchors.centerIn: parent
        spacing: root.px(root.isCompact ? 5 : 7)

        IconBtn {
            anchors.verticalCenter: parent.verticalCenter
            glyph: root.icoPrev
            iconSize: root.px(root.isCompact ? 15 : 16)
            box: root.px(24)
            tint: MusicEngine.hasTrack ? root.tone(ThemeBackend.text) : root.tone(ThemeBackend.subtext0)
            onClicked: MusicEngine.prev()
        }

        // play / pause: filled pill like the wifi / volume pills
        Rectangle {
            id: playPill
            anchors.verticalCenter: parent.verticalCenter
            width: root.px(root.isCompact ? 28 : 30)
            height: width
            radius: Math.max(0, ThemeBackend.borderRadius - root.px(2))
            color: MusicEngine.playing ? root.tone(ThemeBackend.mauve) : ThemeBackend.surface1
            scale: playMa.pressed ? 0.92 : (playMa.containsMouse ? 1.06 : 1.0)
            Behavior on color { ColorAnimation { duration: 200 } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Text {
                anchors.centerIn: parent
                text: MusicEngine.playing ? root.icoPause : root.icoPlay
                font.family: ThemeBackend.fontFamily
                font.pixelSize: root.px(root.isCompact ? 15 : 16)
                color: MusicEngine.playing ? ThemeBackend.base : ThemeBackend.text
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
            anchors.verticalCenter: parent.verticalCenter
            glyph: root.icoNext
            iconSize: root.px(root.isCompact ? 15 : 16)
            box: root.px(24)
            tint: MusicEngine.hasTrack ? root.tone(ThemeBackend.text) : root.tone(ThemeBackend.subtext0)
            onClicked: MusicEngine.next()
        }

        // title + thin progress line. click: open library, right: play/pause, middle: next
        Item {
            id: titleBlock
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Math.min(titleText.implicitWidth, root.px(root.titleMaxWidth))
            implicitHeight: titleText.implicitHeight + root.px(5)

            Text {
                id: titleText
                width: parent.width
                text: MusicEngine.hasTrack ? MusicEngine.title : "Music"
                elide: Text.ElideRight
                font.family: ThemeBackend.fontFamily
                font.pixelSize: root.px(root.isCompact ? 12 : 13)
                font.weight: Font.Black
                font.bold: true
                font.letterSpacing: -0.3
                color: MusicEngine.hasTrack ? root.tone(ThemeBackend.text) : root.tone(ThemeBackend.subtext0)
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: root.px(2)
                radius: height / 2
                color: ThemeBackend.surface1
                visible: MusicEngine.hasTrack

                Rectangle {
                    width: parent.width * MusicEngine.progress
                    height: parent.height
                    radius: parent.radius
                    color: root.tone(ThemeBackend.teal)
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) MusicEngine.togglePlay();
                    else if (mouse.button === Qt.MiddleButton) MusicEngine.next();
                    else popup.toggle();
                }
            }
        }
    }
}
