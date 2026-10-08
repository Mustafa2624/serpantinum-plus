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

    readonly property bool live: !module || module.moduleActive
    onLiveChanged: { if (live) MusicEngine.activate(); }
    Component.onCompleted: { if (live) MusicEngine.activate(); }

    property bool showLayout: false

    Timer {
        running: (!module || module.moduleActive) && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: root.showLayout = true
    }

    property real targetHeight: pill.height + (barWindow ? barWindow.s(root.isCompact ? 8 : 10) : 10)
    property bool isFaceVisible: showLayout && targetHeight > 0

    implicitHeight: targetHeight
    implicitWidth: parent ? parent.width : 0

    // click: play/pause, right-click: next track
    ClickButton {
        id: pill
        anchors.centerIn: parent
        width: barWindow ? barWindow.s(root.isCompact ? 28 : 30) : 30
        height: width
        cornerRadius: Math.max(0, ThemeBackend.borderRadius - (barWindow ? barWindow.s(2) : 2))
        horizontalPadding: 0
        buttonIcon: String.fromCodePoint(MusicEngine.playing ? 0xF03E4 : 0xF040A)
        iconFontSize: barWindow ? barWindow.s(14) : 14
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        accentColor: MusicEngine.playing ? ThemeBackend.mauve : ThemeBackend.surface1
        textColor: MusicEngine.playing ? ThemeBackend.base : ThemeBackend.subtext0

        onClicked: MusicEngine.togglePlay()
        onRightClicked: MusicEngine.next()
    }
}
