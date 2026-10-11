import QtQuick
import "../../../../"

// Bare glyph button. All sizes are passed in already scaled (px).
Item {
    id: btn

    property string glyph: ""
    property real iconSize: 16
    property real box: iconSize * 1.9
    property color tint: ThemeBackend.text
    property bool dim: false

    signal clicked()
    signal rightClicked()

    implicitWidth: box
    implicitHeight: box
    width: box
    height: box

    Text {
        anchors.centerIn: parent
        text: btn.glyph
        font.family: ThemeBackend.fontFamily
        font.pixelSize: btn.iconSize
        color: btn.tint
        opacity: btn.dim ? 0.45 : 1.0
        scale: ma.pressed ? 0.9 : (ma.containsMouse ? 1.12 : 1.0)
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) btn.rightClicked();
            else btn.clicked();
        }
    }
}
