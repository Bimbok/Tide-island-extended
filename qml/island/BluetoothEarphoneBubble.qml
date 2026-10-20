pragma ComponentBehavior: Bound

import QtQuick
import IslandBackend

Item {
    id: root

    property var device: null
    property bool active: !!device && device.connected
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property int bubbleSize: 36
    property real shownX: 0
    property real hiddenX: 0
    property real centerY: 0
    property real autoHideProgress: 1.0
    property bool autoHideEnabled: false

    Behavior on shownX {
        NumberAnimation {
            duration: 320
            easing.type: Easing.OutQuint
        }
    }

    property bool mounted: active
    property real reveal: active ? 1 : 0

    readonly property bool batteryAvailable: !!(device && device.batteryAvailable)
    readonly property real batteryRawValue: batteryAvailable ? Math.max(0, Number(device.battery) || 0) : -1
    readonly property int batteryPercent: batteryAvailable
        ? Math.max(0, Math.min(100, Math.round(batteryRawValue <= 1 ? batteryRawValue * 100 : batteryRawValue)))
        : -1

    readonly property real batteryProgress: batteryPercent >= 0 ? (batteryPercent / 100.0) : 1.0
    property real animatedProgress: batteryProgress

    Behavior on animatedProgress {
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    onAnimatedProgressChanged: ringCanvas.requestPaint()
    onBatteryPercentChanged: ringCanvas.requestPaint()
    onBatteryColorChanged: ringCanvas.requestPaint()

    readonly property color batteryColor: {
        if (!batteryAvailable || batteryPercent < 0)
            return StyleTokens.accent;
        if (batteryPercent >= 60)
            return StyleTokens.batteryHigh;
        if (batteryPercent >= 30)
            return StyleTokens.batteryMedium;
        if (batteryPercent >= 15)
            return StyleTokens.batteryLow;
        return StyleTokens.batteryCritical;
    }

    signal entered
    signal exited

    width: bubbleSize
    height: bubbleSize
    x: hiddenX + (shownX - hiddenX) * reveal
    y: centerY + (1 - reveal) * 8
    z: 6
    visible: mounted
    opacity: reveal * autoHideProgress
    scale: (0.55 + reveal * 0.45) * (0.96 + autoHideProgress * 0.04) * (mouseArea.containsMouse ? 1.08 : 1.0)
    transformOrigin: Item.Center

    Behavior on scale {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutQuad
        }
    }

    onActiveChanged: {
        showAnimation.stop();
        hideAnimation.stop();
        if (active) {
            mounted = true;
            showAnimation.restart();
            ringCanvas.requestPaint();
        } else {
            hideAnimation.restart();
        }
    }

    NumberAnimation {
        id: showAnimation
        target: root
        property: "reveal"
        from: root.reveal
        to: 1
        duration: 360
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: hideAnimation
        target: root
        property: "reveal"
        from: root.reveal
        to: 0
        duration: 280
        easing.type: Easing.InCubic
        onStopped: {
            if (!root.active && root.reveal <= 0.001)
                root.mounted = false;
        }
    }

    Connections {
        target: StyleTokens
        ignoreUnknownSignals: true

        function onColorsChanged() {
            ringCanvas.requestPaint();
        }
    }

    Connections {
        target: root.device
        ignoreUnknownSignals: true

        function onBatteryChanged() {
            ringCanvas.requestPaint();
        }
        function onBatteryAvailableChanged() {
            ringCanvas.requestPaint();
        }
        function onConnectedChanged() {
            ringCanvas.requestPaint();
        }
    }

    // Inner dark circular capsule matching fileShelfBubble aesthetic
    Rectangle {
        id: bubbleBody
        anchors.fill: parent
        anchors.margins: 2.5
        radius: width / 2
        color: StyleTokens.black
        antialiasing: true

        // 1. Headphone icon (optically and mathematically centered)
        Text {
            id: earphoneIcon
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -2.5
            anchors.verticalCenterOffset: 0.5
            text: "\uf025" // FontAwesome Headphones
            color: mouseArea.containsMouse ? root.batteryColor : StyleTokens.textPrimary
            font.family: root.iconFontFamily
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            opacity: (mouseArea.containsMouse && root.batteryPercent >= 0) ? 0 : 1

            Behavior on opacity {
                NumberAnimation { duration: 140 }
            }
            Behavior on color {
                ColorAnimation { duration: 140 }
            }
        }

        // 2. Exact Battery percentage number (revealed smoothly on hover)
        Text {
            id: batteryText
            anchors.centerIn: parent
            visible: root.batteryPercent >= 0
            text: root.batteryPercent + "%"
            color: root.batteryColor
            font.family: root.textFontFamily
            font.pixelSize: root.batteryPercent === 100 ? 9 : 10
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            opacity: mouseArea.containsMouse ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 140 }
            }
        }
    }

    // Outer Circular Progress Ring Canvas
    Canvas {
        id: ringCanvas
        anchors.fill: parent

        Component.onCompleted: requestPaint()
        onVisibleChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const cx = width / 2;
            const cy = height / 2;
            const lineWidth = 2.5;
            const radius = cx - lineWidth / 2 - 0.5;

            // Faint track background ring harmonized with matugen theme
            ctx.beginPath();
            ctx.arc(cx, cy, radius, 0, Math.PI * 2, false);
            ctx.strokeStyle = StyleTokens.withAlpha(root.batteryColor, 0.20);
            ctx.lineWidth = lineWidth;
            ctx.stroke();

            // Colored circular battery progress ring
            const progress = Math.max(0, Math.min(1, root.animatedProgress));
            if (progress > 0.005) {
                const startAngle = -Math.PI / 2; // 12 o'clock top
                const endAngle = startAngle + (Math.PI * 2 * progress); // clockwise sweep

                ctx.beginPath();
                ctx.arc(cx, cy, radius, startAngle, endAngle, false);
                ctx.strokeStyle = root.batteryColor;
                ctx.lineWidth = lineWidth;
                ctx.lineCap = "round";
                ctx.stroke();
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.mounted && root.autoHideProgress > 0.5
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor

        onEntered: root.entered()
        onExited: root.exited()
    }
}
