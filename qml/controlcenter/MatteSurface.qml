import QtQuick
import IslandBackend

Item {
    id: root

    property real radius: StyleTokens.radiusModule
    property bool hovered: false
    property bool pressed: false

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.radius
        color: root.pressed ? "#10000000" : root.hovered ? "#1fffffff" : "#13ffffff"
        border.width: 1
        border.color: root.hovered ? "#2affffff" : StyleTokens.surfaceHighlight
        antialiasing: true

        Behavior on color {
            ColorAnimation { duration: StyleTokens.durationFast }
        }

        Behavior on border.color {
            ColorAnimation { duration: StyleTokens.durationFast }
        }

        // Specular glass highlight reflection
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, root.radius - 1)
            color: StyleTokens.transparent
            gradient: Gradient {
                GradientStop { position: 0; color: root.hovered ? "#12ffffff" : "#08ffffff" }
                GradientStop { position: 0.45; color: "#01ffffff" }
                GradientStop { position: 1; color: "#02000000" }
            }
            antialiasing: true
        }
    }
}
