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
    property string scriptPath: Qt.resolvedUrl("sysinfo.sh").toString().replace("file://", "")
    property string clickCmd: "kitty -e btop"
    property int pollMs: 2000
    property real statSpacing: 14
    // --------------------

    function px(v) { return barWindow ? barWindow.s(v) : v }
    function tone(c) { return isCompact ? Qt.lighter(c, 1.1) : c }

    property real cpu: 0
    property string ramGb: "0.0"
    property real temp: 0
    property bool hasData: false
    property bool showLayout: false

    property real horizontalPadding: px(isCompact ? 12 : 14)

    Process {
        id: pollProc
        command: ["bash", root.scriptPath]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = this.text.trim().split(/\s+/);
                if (p.length >= 4) {
                    root.cpu = parseFloat(p[0]);
                    root.ramGb = p[1];
                    root.temp = parseFloat(p[3]);
                    root.hasData = true;
                }
            }
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

    property real targetWidth: ((!module || module.moduleActive) && mainRow.implicitWidth > 0) ? (mainRow.implicitWidth + horizontalPadding * 2) : 0
    property bool isFaceVisible: showLayout && targetWidth > 0

    implicitWidth: targetWidth
    implicitHeight: parent ? parent.height : 0

    opacity: showLayout ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    transform: Translate {
        x: root.showLayout ? 0 : root.px(40)
        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutQuint } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                if (!pollProc.running) pollProc.running = true;
            } else {
                Quickshell.execDetached(["bash", "-c", root.clickCmd]);
            }
        }
    }

    component Stat: Row {
        property string value: "--"
        property string label: ""
        property color accent: ThemeBackend.text
        spacing: root.px(root.isCompact ? 3 : 4)

        Text {
            text: parent.value
            anchors.verticalCenter: parent.verticalCenter
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.px(root.isCompact ? 14 : 15)
            font.weight: Font.Black
            font.bold: true
            font.letterSpacing: -0.5
            color: root.tone(parent.accent)
        }
        Text {
            text: parent.label
            anchors.verticalCenter: parent.verticalCenter
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.px(root.isCompact ? 7 : 8)
            font.weight: Font.Black
            font.bold: true
            font.letterSpacing: 0.2
            color: ThemeBackend.subtext0
        }
    }

    Row {
        id: mainRow
        anchors.centerIn: parent
        spacing: root.px(root.isCompact ? Math.max(8, root.statSpacing - 4) : root.statSpacing)

        Stat {
            value: root.hasData ? Math.round(root.cpu) + "%" : "--"
            label: "CPU"
            accent: ThemeBackend.mauve
        }
        Stat {
            value: root.hasData ? root.ramGb + "G" : "--"
            label: "RAM"
            accent: ThemeBackend.teal
        }
        Stat {
            value: root.hasData ? Math.round(root.temp) + "°" : "--"
            label: "TEMP"
            accent: ThemeBackend.peach
        }
    }
}
