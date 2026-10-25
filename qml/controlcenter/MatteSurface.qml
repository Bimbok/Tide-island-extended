import QtQuick
import IslandBackend

Item {
    id: root

    property real radius: 20
    property bool hovered: false
    property bool pressed: false

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.pressed ? "#10000000" : root.hovered ? "#1fffffff" : "#13ffffff"
        border.width: 1
        border.color: root.hovered ? "#2affffff" : StyleTokens.surfaceHighlight

        Behavior on color {
            ColorAnimation { duration: StyleTokens.durationFast }
        }
    }
}
