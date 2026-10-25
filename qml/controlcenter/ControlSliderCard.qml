import QtQuick
import IslandBackend

Rectangle {
    id: root

    signal interactionStarted()
    signal valueMoved(real value)
    signal commitRequested()
    signal cancelRequested()
    signal iconClicked()
    signal flyoutClicked()

    property bool showFlyoutChevron: false
    property bool flyoutOpen: false

    property string title: ""
    property string iconText: ""
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property real value: 0
    property real knobSize: 24
    property color accentColor: StyleTokens.accent
    property color moduleColor: StyleTokens.module
    property color moduleHover: StyleTokens.moduleHover
    property color trackColor: StyleTokens.track
    property color textPrimary: StyleTokens.textPrimary
    property color textSecondary: StyleTokens.textSecondary
    readonly property bool pressed: sliderArea.pressed

    function clamp01(nextValue) {
        return Math.max(0, Math.min(1, nextValue));
    }

    radius: StyleTokens.radiusModule
    color: StyleTokens.clearBlack
    clip: true

    MatteSurface {
        anchors.fill: parent
        radius: root.radius
        hovered: sliderArea.containsMouse
        pressed: sliderArea.pressed
    }

    Item {
        anchors.fill: parent
        anchors.margins: 12

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            text: root.title
            color: root.textPrimary
            font.pixelSize: 13
            font.family: root.textFontFamily
            font.weight: Font.DemiBold
        }

        Row {
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 8

            Item {
                width: 22
                height: 20
                visible: root.iconText !== ""
                scale: iconMouse.pressed ? 0.88 : (iconMouse.containsMouse ? 1.08 : 1.0)

                Behavior on scale {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.iconText
                    color: iconMouse.containsMouse ? root.accentColor : root.textSecondary
                    font.pixelSize: 13
                    font.family: root.iconFontFamily

                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                    id: iconMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.iconClicked()
                }
            }

            Item {
                width: 18
                height: 20
                visible: root.showFlyoutChevron
                scale: chevronMouse.pressed ? 0.88 : (chevronMouse.containsMouse ? 1.12 : 1.0)

                Behavior on scale {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "›"
                    color: root.flyoutOpen
                        ? root.accentColor
                        : (chevronMouse.containsMouse ? root.textPrimary : StyleTokens.textSubtle)
                    font.pixelSize: 16
                    font.family: root.textFontFamily
                    font.weight: Font.DemiBold

                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                    id: chevronMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.flyoutClicked()
                }
            }
        }

        Rectangle {
            id: sliderTrack
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 24
            radius: 12
            color: "#30000000"
            border.width: 1
            border.color: StyleTokens.surfaceHighlight
            clip: true

            Rectangle {
                width: root.value <= 0.001
                    ? 0
                    : Math.min(sliderTrack.width, sliderTrack.width * root.value)
                height: parent.height
                radius: parent.radius
                color: root.accentColor
            }

            MouseArea {
                id: sliderArea
                anchors.fill: parent
                hoverEnabled: true

                function update(mouseX) {
                    root.valueMoved(root.clamp01(mouseX / width));
                }

                onPressed: function(mouse) {
                    root.interactionStarted();
                    update(mouse.x);
                }
                onPositionChanged: function(mouse) {
                    if (pressed)
                        update(mouse.x);
                }
                onReleased: root.commitRequested()
                onCanceled: root.cancelRequested()
            }
        }
    }
}
