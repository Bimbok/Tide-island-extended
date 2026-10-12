pragma ComponentBehavior: Bound

import QtQuick
import IslandBackend

Item {
    id: root

    property bool micActive: false
    property bool cameraActive: false
    property bool screenRecordingActive: false
    property real contentOpacity: 1.0

    readonly property bool privacyActive: micActive || cameraActive || screenRecordingActive
    readonly property int activeDotCount: (cameraActive ? 1 : 0) + (micActive ? 1 : 0) + (screenRecordingActive ? 1 : 0)

    signal clicked

    implicitWidth: privacyActive ? backgroundPill.width : 0
    implicitHeight: 22
    width: implicitWidth
    height: implicitHeight
    opacity: privacyActive ? contentOpacity : 0
    visible: privacyActive || opacity > 0.01

    Behavior on opacity {
        NumberAnimation {
            duration: root.privacyActive ? 220 : 180
            easing.type: Easing.InOutQuad
        }
    }

    Behavior on implicitWidth {
        NumberAnimation {
            duration: 240
            easing.type: Easing.OutQuint
        }
    }

    Rectangle {
        id: backgroundPill
        height: 22
        width: dotsRow.implicitWidth + 14
        radius: 11
        color: pillMouseArea.containsMouse ? Qt.rgba(0.18, 0.18, 0.20, 0.75) : Qt.rgba(0.08, 0.08, 0.10, 0.55)
        border.width: 1
        border.color: pillMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10)
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        Behavior on border.color {
            ColorAnimation { duration: 150 }
        }

        Row {
            id: dotsRow
            anchors.centerIn: parent
            spacing: 5

            // Camera Indicator (Green)
            Item {
                id: cameraItem
                width: 7
                height: 7
                visible: root.cameraActive

                Rectangle {
                    id: cameraGlow
                    anchors.centerIn: parent
                    width: 7
                    height: 7
                    radius: 3.5
                    color: "#30d158"

                    SequentialAnimation on opacity {
                        running: root.cameraActive
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.5; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                    }
                }
            }

            // Microphone Indicator (Amber/Orange)
            Item {
                id: micItem
                width: 7
                height: 7
                visible: root.micActive

                Rectangle {
                    id: micGlow
                    anchors.centerIn: parent
                    width: 7
                    height: 7
                    radius: 3.5
                    color: "#ff9f0a"

                    SequentialAnimation on opacity {
                        running: root.micActive
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.45; duration: 800; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                    }
                }
            }

            // Screen Recording Indicator (Red)
            Item {
                id: screenItem
                width: 7
                height: 7
                visible: root.screenRecordingActive

                Rectangle {
                    id: screenGlow
                    anchors.centerIn: parent
                    width: 7
                    height: 7
                    radius: 3.5
                    color: "#ff453a"

                    SequentialAnimation on opacity {
                        running: root.screenRecordingActive
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: 750; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 750; easing.type: Easing.InOutSine }
                    }
                }
            }
        }

        MouseArea {
            id: pillMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }
}
