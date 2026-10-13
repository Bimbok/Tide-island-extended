pragma ComponentBehavior: Bound

import QtQuick
import IslandBackend

Item {
    id: root

    property bool showCondition: false
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property string heroFontFamily: ""
    property bool isMicMuted: false

    readonly property var activeApps: SystemServices.activePrivacyApps || []
    readonly property int appCount: activeApps.length
    readonly property real contentHeight: mainCol.implicitHeight + 32

    signal closeRequested

    anchors.fill: parent
    anchors.margins: 16
    opacity: showCondition ? 1 : 0
    visible: opacity > 0.01

    Behavior on opacity {
        NumberAnimation {
            duration: root.showCondition ? 240 : 120
            easing.type: Easing.InOutQuad
        }
    }

    Column {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 12

        // Header
        Item {
            width: parent.width
            height: 28

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: Qt.rgba(0.20, 0.82, 0.35, 0.18)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "\uf132"
                        font.family: root.iconFontFamily
                        font.pixelSize: 12
                        color: "#30d158"
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Privacy & Media Activity"
                    color: "white"
                    font.family: root.heroFontFamily
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }
            }

            Rectangle {
                id: closeBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                radius: 12
                color: closeMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)

                Text {
                    anchors.centerIn: parent
                    text: "\uf00d"
                    font.family: root.iconFontFamily
                    font.pixelSize: 10
                    color: closeMouseArea.containsMouse ? "white" : "#a1a1a6"
                }

                MouseArea {
                    id: closeMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }
            }
        }

        // Active Devices / Streams List
        Column {
            width: parent.width
            spacing: 8

            Repeater {
                model: root.activeApps

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    width: parent.width
                    height: 52
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    readonly property string appType: String(modelData.type || "mic")
                    readonly property color typeColor: appType === "camera"
                        ? "#30d158"
                        : (appType === "screen" ? "#ff453a" : "#ff9f0a")
                    readonly property string typeIcon: appType === "camera"
                        ? "\uf03d"
                        : (appType === "screen" ? "\uf108" : (root.isMicMuted ? "\uf131" : "\uf130"))

                    Item {
                        anchors.fill: parent
                        anchors.margins: 10

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Rectangle {
                                width: 32
                                height: 32
                                radius: 16
                                color: Qt.rgba(typeColor.r, typeColor.g, typeColor.b, 0.20)
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: typeIcon
                                    font.family: root.iconFontFamily
                                    font.pixelSize: 14
                                    color: typeColor
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    text: String(modelData.name || "Unknown Application")
                                    color: "white"
                                    font.family: root.textFontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    width: 220
                                }

                                Text {
                                    text: (appType === "camera"
                                        ? "Camera Active"
                                        : (appType === "screen" ? "Screen Sharing" : "Microphone Active"))
                                        + (modelData.pid > 0 ? " • PID " + modelData.pid : "")
                                    color: "#98989d"
                                    font.family: root.textFontFamily
                                    font.pixelSize: 11
                                }
                            }
                        }

                        // Action button
                        Rectangle {
                            id: actionBtn
                            visible: appType === "mic" || (appType === "screen" && ScreenRecorder.isRecording)
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 28
                            width: actionBtnText.implicitWidth + 20
                            radius: 14
                            color: actionMouseArea.containsMouse
                                ? (appType === "screen" ? "#ff3b30" : (root.isMicMuted ? "#30d158" : "#ff9f0a"))
                                : Qt.rgba(1, 1, 1, 0.12)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.16)

                            Text {
                                id: actionBtnText
                                anchors.centerIn: parent
                                text: appType === "screen"
                                    ? "Stop"
                                    : (root.isMicMuted ? "Unmute" : "Mute")
                                color: actionMouseArea.containsMouse ? "white" : (root.isMicMuted ? "#ff453a" : "white")
                                font.family: root.textFontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: actionMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (appType === "mic") {
                                        SystemServices.toggleMicMute();
                                    } else if (appType === "screen" && ScreenRecorder.isRecording) {
                                        ScreenRecorder.toggleRecording();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Fallback when list is empty
            Rectangle {
                visible: root.appCount === 0
                width: parent.width
                height: 48
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.04)

                Text {
                    anchors.centerIn: parent
                    text: "No active microphone or camera capture."
                    color: "#8e8e93"
                    font.family: root.textFontFamily
                    font.pixelSize: 12
                }
            }
        }

        // Global Microphone Quick Toggle
        Rectangle {
            width: parent.width
            height: 40
            radius: 10
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.06)

            Item {
                anchors.fill: parent
                anchors.margins: 8

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isMicMuted ? "\uf131" : "\uf130"
                        font.family: root.iconFontFamily
                        font.pixelSize: 12
                        color: root.isMicMuted ? "#ff453a" : "#30d158"
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Hardware Mic State: " + (root.isMicMuted ? "Muted" : "Active")
                        color: "#a1a1a6"
                        font.family: root.textFontFamily
                        font.pixelSize: 11
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 24
                    width: masterMuteText.implicitWidth + 14
                    radius: 6
                    color: masterMuteMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)

                    Text {
                        id: masterMuteText
                        anchors.centerIn: parent
                        text: root.isMicMuted ? "Enable" : "Mute"
                        color: "white"
                        font.family: root.textFontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: masterMuteMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SystemServices.toggleMicMute()
                    }
                }
            }
        }
    }
}
