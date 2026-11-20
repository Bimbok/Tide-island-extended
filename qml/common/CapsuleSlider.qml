import QtQuick
import IslandBackend

Item {
    id: root

    property real value: 0.0
    property bool muted: false
    property bool enabled: true
    property real normalHeight: 8
    property real hoverHeight: 14
    property real step: 0.05
    property bool wheelEnabled: true

    property color accentColor: StyleTokens.accent
    property color mutedColor: StyleTokens.withAlpha(StyleTokens.accent, 0.45)
    property color trackColor: StyleTokens.withAlpha(StyleTokens.white, 0.10)
    property color trackHoverColor: StyleTokens.withAlpha(StyleTokens.white, 0.16)
    property color trackBorderColor: StyleTokens.withAlpha(StyleTokens.white, 0.06)
    property color trackHoverBorderColor: StyleTokens.withAlpha(StyleTokens.white, 0.20)

    readonly property bool isHovered: mouseArea.containsMouse || mouseArea.pressed
    readonly property bool isDragging: mouseArea.pressed
    readonly property real effectiveHeight: isHovered ? hoverHeight : normalHeight

    property real internalValue: value

    onValueChanged: {
        if (!mouseArea.pressed) {
            internalValue = value;
        }
    }

    signal moved(real value)
    signal committed(real value)

    implicitHeight: Math.max(normalHeight, hoverHeight, 22)
    implicitWidth: 120

    Rectangle {
        id: trackBg
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.effectiveHeight
        radius: height / 2
        color: root.isHovered ? root.trackHoverColor : root.trackColor
        border.width: 1
        border.color: root.isHovered ? root.trackHoverBorderColor : root.trackBorderColor
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: 150
            }
        }

        Rectangle {
            id: trackFill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            radius: parent.radius
            color: root.muted ? root.mutedColor : root.accentColor
            width: root.muted
                ? 0
                : (root.internalValue <= 0.001
                    ? 0
                    : Math.min(parent.width, parent.width * Math.max(0.0, Math.min(1.0, root.internalValue))))

            Behavior on width {
                enabled: !mouseArea.pressed
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: 140
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        preventStealing: true

        function updateFromMouse(mouseX) {
            const ratio = Math.max(0.0, Math.min(1.0, mouseX / width));
            root.internalValue = ratio;
            root.moved(ratio);
        }

        onPressed: mouse => updateFromMouse(mouse.x)
        onPositionChanged: mouse => {
            if (pressed) {
                updateFromMouse(mouse.x);
            }
        }
        onReleased: root.committed(root.internalValue)
        onCanceled: root.committed(root.internalValue)

        onWheel: wheel => {
            if (!root.wheelEnabled || !root.enabled) return;
            const delta = wheel.angleDelta.y > 0 ? root.step : -root.step;
            const nextVal = Math.max(0.0, Math.min(1.0, root.internalValue + delta));
            root.internalValue = nextVal;
            root.moved(nextVal);
            root.committed(nextVal);
        }
    }
}
