pragma ComponentBehavior: Bound

import QtQuick
import IslandBackend

Item {
    id: root

    property bool active: false
    property color accentColor: "#30d158"
    property string iconText: ""
    property string iconFontFamily: ""
    property real iconFontSize: 13
    property int bubbleSize: 34
    property real shownX: 0
    Behavior on shownX {
        NumberAnimation {
            duration: 320
            easing.type: Easing.OutQuint
        }
    }
    property real hiddenX: 0
    property real centerY: 0
    property real autoHideProgress: 1.0
    property bool autoHideEnabled: false

    property bool mounted: active
    property real reveal: active ? 1 : 0

    signal clicked
    signal entered
    signal exited

    width: bubbleSize
    height: bubbleSize
    x: hiddenX + (shownX - hiddenX) * reveal
    y: centerY + (1 - reveal) * 10
    z: 6
    visible: mounted
    opacity: reveal * autoHideProgress
    scale: (0.55 + reveal * 0.45) * (0.96 + autoHideProgress * 0.04) * (mouseArea.containsMouse ? 1.06 : 1.0)
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

    // Outer subtle pulsating glow ring
    Rectangle {
        id: pulseGlow
        anchors.fill: parent
        anchors.margins: -2
        radius: width / 2
        color: "transparent"
        border.width: 1.5
        border.color: root.accentColor
        opacity: 0.35
        visible: root.active && root.mounted

        SequentialAnimation on opacity {
            running: root.active && root.mounted
            loops: Animation.Infinite
            NumberAnimation { to: 0.12; duration: 1100; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.65; duration: 1100; easing.type: Easing.InOutSine }
        }
    }

    // Main dark circular body with colored accent ring matching timer bubble aesthetic
    Rectangle {
        id: bubbleBody
        anchors.fill: parent
        anchors.margins: 1
        radius: width / 2
        color: StyleTokens.black
        border.width: 2.5
        border.color: root.accentColor
        antialiasing: true

        Text {
            anchors.centerIn: parent
            text: root.iconText
            color: "white"
            font.family: root.iconFontFamily
            font.pixelSize: root.iconFontSize
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.mounted && root.autoHideProgress > 0.5
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.entered()
        onExited: root.exited()
        onClicked: root.clicked()
    }
}
