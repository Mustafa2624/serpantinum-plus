import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../reusables"
import "../../../"

Item {
    id: root

    property var module: null
    property var widget: module

    readonly property bool isCompact: module ? module.isCompact : false
    readonly property var barWindow: module ? module.barWindow : null

    property string clickCmd: "kitty -e btop"
    property color pillColor: ThemeBackend.blue !== undefined ? ThemeBackend.blue : ThemeBackend.mauve
    property bool showLayout: false
    property alias customPill: pill

    Timer {
        running: (!module || module.moduleActive) && barWindow && barWindow.isStartupReady && barWindow.isDataReady
        interval: 100
        onTriggered: root.showLayout = true
    }

    property real targetHeight: pill.height + (barWindow ? barWindow.s(root.isCompact ? 8 : 10) : 10)
    property bool isFaceVisible: showLayout && targetHeight > 0

    implicitHeight: targetHeight
    implicitWidth: parent ? parent.width : 0

    ClickButton {
        id: pill
        anchors.centerIn: parent
        width: barWindow ? barWindow.s(root.isCompact ? 28 : 30) : 30
        height: width
        cornerRadius: Math.max(0, ThemeBackend.borderRadius - (barWindow ? barWindow.s(2) : 2))
        horizontalPadding: 0
        buttonIcon: "󰍛"
        iconFontSize: barWindow ? barWindow.s(14) : 14
        accentColor: root.isCompact ? Qt.lighter(root.pillColor, 1.08) : root.pillColor
        textColor: ThemeBackend.base

        onClicked: Quickshell.execDetached(["bash", "-c", root.clickCmd])
    }
}
