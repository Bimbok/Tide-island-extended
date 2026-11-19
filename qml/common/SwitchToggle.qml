import QtQuick
import IslandBackend

Rectangle {
    id: control

    property bool checked: false
    property bool enabled: true
    property color activeColor: StyleTokens.success
    property color inactiveColor: StyleTokens.switchOff
    property color thumbColor: StyleTokens.white

    signal toggled(bool checked)

    width: 34
    height: 20
    radius: 10
    color: control.checked ? control.activeColor : control.inactiveColor

    Behavior on color {
        ColorAnimation {
            duration: StyleTokens.durationFast
        }
    }

    Rectangle {
        id: thumb
        width: 16
        height: 16
        radius: 8
        y: 2
        x: control.checked ? 16 : 2
        color: control.thumbColor

        Behavior on x {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: control.enabled
        cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            control.toggled(!control.checked);
        }
    }
}
