import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../../reusables"
import "../../../"

Item {
    id: root

    property var module: null
    property var widget: module

    readonly property bool isCompact: module ? module.isCompact : false
    readonly property var barWindow: module ? module.barWindow : null

    // ---- edit these ----
    property string pollCmd: "free -h | awk '/Mem:/{print $3}'"
    property string clickCmd: "kitty -e btop"
    property string iconGlyph: "󰍛"
    property int pollMs: 5000
    // fill color: tries peach, then blue, then mauve
    property color pillColor: ThemeBackend.peach !== undefined ? ThemeBackend.peach
                            : (ThemeBackend.blue !== undefined ? ThemeBackend.blue : ThemeBackend.mauve)
    // --------------------

    property string outText: ""
    property bool isActive: outText !== ""
    property bool showLayout: false
    property alias customPill: pill

    Process {
        id: pollProc
        command: ["bash", "-c", root.pollCmd]
        stdout: StdioCollector {
            onStreamFinished: root.outText = this.text.trim()
        }
    }

    Timer {
        interval: root.pollMs
        repeat: true
        triggeredOnStart: true
        running: !module || module.moduleActive
        onTriggered: { if (!pollProc.running) pollProc.running = true }
    }

    Timer {
        running: (!module || module.moduleActive) && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: root.showLayout = true
    }

    property real targetWidth: ((!module || module.moduleActive) && sysLayout.implicitWidth > 0) ? (sysLayout.implicitWidth + (barWindow ? barWindow.s(isCompact ? 8 : 10) : (isCompact ? 8 : 10))) : 0
    property bool isFaceVisible: showLayout && targetWidth > 0

    implicitWidth: targetWidth
    implicitHeight: parent ? parent.height : 0

    transform: Translate {
        x: root.showLayout ? 0 : (barWindow ? barWindow.s(60) : 60)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    Row {
        id: sysLayout
        anchors.centerIn: parent
        property int pillHeight: barWindow ? barWindow.s(root.isCompact ? 28 : 30) : (root.isCompact ? 28 : 30)

        ClickButton {
            id: pill
            property bool initAnimTrigger: false

            height: sysLayout.pillHeight
            maxWidth: barWindow ? barWindow.s(root.isCompact ? 140 : 150) : 150
            cornerRadius: Math.max(0, ThemeBackend.borderRadius - (barWindow ? barWindow.s(2) : 2))
            horizontalPadding: barWindow ? barWindow.s(root.isCompact ? 10 : 12) : (root.isCompact ? 10 : 12)
            buttonIcon: root.iconGlyph
            iconFontSize: barWindow ? barWindow.s(root.isCompact ? 14 : 15) : (root.isCompact ? 14 : 15)
            buttonText: root.outText
            textFontSize: barWindow ? barWindow.s(root.isCompact ? 11 : 12) : (root.isCompact ? 11 : 12)
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            accentColor: root.isActive ? (root.isCompact ? Qt.lighter(root.pillColor, 1.08) : root.pillColor) : (root.isCompact ? Qt.lighter(ThemeBackend.surface1, 1.12) : ThemeBackend.surface1)
            textColor: root.isActive ? ThemeBackend.base : (root.isCompact ? ThemeBackend.text : ThemeBackend.subtext0)

            property real targetWidth: implicitWidth
            width: targetWidth
            Behavior on width { NumberAnimation { duration: 480; easing.type: Easing.OutQuint } }

            Timer { running: (!module || module.moduleActive) && root.showLayout && !pill.initAnimTrigger; interval: 300; onTriggered: pill.initAnimTrigger = true }
            opacity: initAnimTrigger ? 1.0 : 0.0
            transform: Translate { y: pill.initAnimTrigger ? 0 : (barWindow ? barWindow.s(15) : 15); Behavior on y { NumberAnimation { duration: 620; easing.type: Easing.OutQuint } } }
            Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

            onClicked: Quickshell.execDetached(["bash", "-c", root.clickCmd])
            onRightClicked: { if (!pollProc.running) pollProc.running = true }
        }
    }
}
