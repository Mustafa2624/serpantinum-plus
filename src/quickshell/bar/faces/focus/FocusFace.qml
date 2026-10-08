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

    property real leftPadding: (isSolid && !distinctPills) ? 0 : (barWindow ? barWindow.s(6) : 6)
    property real rightPadding: (isSolid && !distinctPills) ? 0 : (barWindow ? barWindow.s(12) : 12)
    property real maxWidth: barWindow ? barWindow.s(300) : 300
    property real maxTextWidth: Math.max(0, maxWidth - (leftPadding + focusIconButton.width + innerLayout.spacing + rightPadding))
    property real targetWidth: (moduleActive && isFocused) ? Math.min(maxWidth, leftPadding + focusIconButton.width + innerLayout.spacing + titleTextMain.width + rightPadding) : 0

    implicitWidth: targetWidth
    implicitHeight: parent ? parent.height : 0

    Row {
        id: innerLayout
        anchors.left: parent.left
        anchors.leftMargin: root.leftPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: barWindow ? barWindow.s(root.isCompact ? 5 : 6) : (root.isCompact ? 5 : 6)

        property bool initAnimTrigger: !barWindow || barWindow.startupCascadeFinished

        opacity: initAnimTrigger ? 1.0 : 0.0
        transform: Translate {
            y: innerLayout.initAnimTrigger ? 0 : (barWindow ? barWindow.s(15) : 15)
            Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        IconButton {
            id: focusIconButton
            width: barWindow ? barWindow.s(root.isCompact ? 28 : 30) : (root.isCompact ? 28 : 30)
            height: barWindow ? barWindow.s(root.isCompact ? 28 : 30) : (root.isCompact ? 28 : 30)
            cornerRadius: barWindow ? barWindow.s(root.isCompact ? 9 : 10) : (root.isCompact ? 9 : 10)
            buttonIcon: "✦"
            iconFontSize: barWindow ? barWindow.s(root.isCompact ? 14 : 15) : (root.isCompact ? 14 : 15)
            accentColor: root.isCompact ? Qt.lighter(ThemeBackend.surface0, 1.18) : ThemeBackend.surface0
            textColor: isHoveredOrHighlighted ? ThemeBackend.text : (root.isCompact ? ThemeBackend.subtext0 : ThemeBackend.overlay2)
            anchors.verticalCenter: parent.verticalCenter
            onClicked: {
                if (Caching.serpantinumDir) {
                    Quickshell.execDetached(["bash", "-c", Caching.serpantinumDir + "/scripts/qs_manager.sh toggle applauncher"])
                }
            }
        }

        Item {
            id: titleClipRect
            width: Math.min(root.maxTextWidth, titleTextMain.width)
            height: titleTextMain.height
            anchors.verticalCenter: parent.verticalCenter
            clip: true

            Behavior on width {
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }

            Text {
                id: titleTextMain
                text: root.displayText
                font.family: ThemeBackend.fontFamily
                font.pixelSize: barWindow ? barWindow.s(root.isCompact ? 11 : 12) : (root.isCompact ? 11 : 12)
                font.weight: Font.DemiBold
                color: root.isCompact ? ThemeBackend.text : ThemeBackend.subtext1
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                width: Math.min(implicitWidth, root.maxTextWidth)

                property string targetText: root.displayText
                onTargetTextChanged: {
                    if (titleFadeAnim.running) titleFadeAnim.stop();
                    titleFadeAnim.start();
                }

                SequentialAnimation {
                    id: titleFadeAnim
                    NumberAnimation { target: titleTextMain; property: "opacity"; to: 0.0; duration: 100; easing.type: Easing.OutQuad }
                    ScriptAction { script: titleTextMain.text = titleTextMain.targetText; }
                    NumberAnimation { target: titleTextMain; property: "opacity"; to: 1.0; duration: 150; easing.type: Easing.InQuad }
                }
            }
        }
    }
}
