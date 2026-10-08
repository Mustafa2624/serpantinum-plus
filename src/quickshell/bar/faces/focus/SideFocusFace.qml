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
    readonly property bool moduleActive: module ? module.moduleActive : true
    readonly property bool isSolid: module ? module.isSolid : false
    readonly property bool distinctPills: module ? module.distinctPills : false

    readonly property string displayText: CurrentFocus.displayText
    readonly property bool isFocused: CurrentFocus.isFocused
    readonly property bool isFaceVisible: isFocused

    property real topPadding: (isSolid && !distinctPills) ? 0 : (barWindow ? barWindow.s(6) : 6)
    property real bottomPadding: (isSolid && !distinctPills) ? 0 : (barWindow ? barWindow.s(12) : 12)
    property real maxHeight: barWindow ? barWindow.s(300) : 300
    property real maxTextHeight: Math.max(0, maxHeight - (topPadding + focusIconButton.height + innerLayout.spacing + bottomPadding))
    property real targetHeight: (moduleActive && isFocused) ? Math.min(maxHeight, topPadding + focusIconButton.height + innerLayout.spacing + titleClipRect.height + bottomPadding) : 0

    implicitHeight: targetHeight
    implicitWidth: parent ? parent.width : 0

    Column {
        id: innerLayout
        anchors.top: parent.top
        anchors.topMargin: root.topPadding
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: (isSolid && !distinctPills) ? 0 : (barWindow ? barWindow.s(root.isCompact ? 5 : 6) : (root.isCompact ? 5 : 6))

        property bool initAnimTrigger: !barWindow || barWindow.startupCascadeFinished

        opacity: initAnimTrigger ? 1.0 : 0.0
        transform: Translate {
            x: innerLayout.initAnimTrigger ? 0 : (barWindow ? barWindow.s(15) : 15)
            Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        IconButton {
            id: focusIconButton
            width: barWindow ? barWindow.s(root.isCompact ? 28 : 30) : (root.isCompact ? 28 : 30)
            height: barWindow ? barWindow.s(root.isCompact ? 28 : 30) : (root.isCompact ? 28 : 30)
            cornerRadius: barWindow ? barWindow.s(root.isCompact ? 9 : 10) : (root.isCompact ? 9 : 10)
            buttonIcon: "✦"
            iconFontSize: barWindow ? barWindow.s(root.isCompact ? 14 : 15) : (root.isCompact ? 14 : 15)
            accentColor: root.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ((isSolid && !distinctPills) ? "transparent" : ThemeBackend.surface0)
            textColor: isHoveredOrHighlighted ? ThemeBackend.text : (root.isCompact ? ThemeBackend.subtext0 : ThemeBackend.overlay2)
            anchors.horizontalCenter: parent.horizontalCenter
            onClicked: {
                if (Caching.serpantinumDir) {
                    Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle applauncher"])
                }
            }
        }

        Item {
            id: titleClipRect
            width: focusIconButton.width
            height: Math.min(titleTextMain.implicitWidth, root.maxTextHeight)
            clip: true
            anchors.horizontalCenter: parent.horizontalCenter

            Item {
                id: rotator
                anchors.centerIn: parent
                width: titleClipRect.height
                height: titleClipRect.width
                rotation: 90

                Text {
                    id: titleTextMain
                    anchors.verticalCenter: parent.verticalCenter
                    width: rotator.width
                    text: root.displayText
                    color: ThemeBackend.text
                    font.pixelSize: barWindow ? barWindow.s(root.isCompact ? 11 : 12) : (root.isCompact ? 11 : 12)
                    elide: Text.ElideRight
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        z: -1
        onClicked: {
            if (Caching.serpantinumDir) {
                Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle applauncher"])
            }
        }
    }
}
