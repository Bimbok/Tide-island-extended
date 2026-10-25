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
    property int bubbleSize: 36
    readonly property real defaultHorizontalOffset: {
        if (iconText === "\uf03d") return -2.5;
        if (iconText === "\uf131") return -3.5;
        if (iconText === "\uf130") return -0.5;
        return 0;
    }
    property real iconHorizontalOffset: defaultHorizontalOffset
    property real iconVerticalOffset: 0
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

    // Main glass circular body matching fileShelfBubble aesthetic
    Rectangle {
        id: bubbleBody
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(StyleTokens.panel.r, StyleTokens.panel.g, StyleTokens.panel.b, 0.86)
        border.width: 1
        border.color: mouseArea.containsMouse ? StyleTokens.withAlpha(StyleTokens.white, 0.28) : StyleTokens.surfaceBorder
        antialiasing: true

        Behavior on border.color {
            ColorAnimation { duration: 150 }
        }

        Text {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.iconHorizontalOffset
            anchors.verticalCenterOffset: root.iconVerticalOffset
            text: root.iconText
            color: StyleTokens.textPrimary
            font.family: root.iconFontFamily
            font.pixelSize: root.iconFontSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        // Corner indicator dot badge matching fileShelfBubble badge structure
        Rectangle {
            id: badgeDot
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -1
            anchors.bottomMargin: -1
            width: 11
            height: 11
            radius: width / 2
            color: root.accentColor
            border.width: 2
            border.color: StyleTokens.black
            antialiasing: true

            SequentialAnimation on opacity {
                running: root.active && root.mounted
                loops: Animation.Infinite
                NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
            }
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
