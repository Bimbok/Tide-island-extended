pragma ComponentBehavior: Bound

import QtQuick
import IslandBackend

FocusScope {
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

    focus: root.showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    anchors.margins: 16
    opacity: showCondition ? 1 : 0
    visible: opacity > 0.01

    Behavior on opacity {
        NumberAnimation {
            duration: root.showCondition ? StyleTokens.durationStandard : StyleTokens.durationFast
            easing.type: Easing.InOutQuad
        }
    }

    Keys.onEscapePressed: function(event) {
        root.closeRequested();
        event.accepted = true;
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
                    color: StyleTokens.withAlpha(StyleTokens.success, 0.18)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "\uf132"
                        font.family: root.iconFontFamily
                        font.pixelSize: 12
                        color: StyleTokens.success
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Privacy & Media Activity"
                    color: StyleTokens.textPrimaryBright
                    font.family: root.heroFontFamily
                    font.pixelSize: 14
                    font.weight: Font.Bold
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
                    color: StyleTokens.cardFill
                    border.width: 1
                    border.color: StyleTokens.inputBorder

                    readonly property string appType: String(modelData.type || "mic")
                    readonly property color typeColor: appType === "camera"
                        ? StyleTokens.success
                        : (appType === "screen" ? StyleTokens.danger : (root.isMicMuted ? StyleTokens.danger : StyleTokens.warning))
                    readonly property string typeIcon: appType === "camera"
                        ? "\uf03d"
                        : (appType === "screen" ? "\uf108" : (root.isMicMuted ? "\uf131" : "\uf130"))

                    Item {
                        anchors.fill: parent
                        anchors.margins: 10

                        Row {
                            anchors.left: parent.left
                            anchors.right: actionBtn.visible ? actionBtn.left : parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Rectangle {
                                width: 32
                                height: 32
                                radius: 16
                                color: StyleTokens.withAlpha(typeColor, 0.18)
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
                                width: parent.width - 42
                                spacing: 2

                                Text {
                                    text: String(modelData.name || "Unknown Application")
                                    color: StyleTokens.textPrimaryBright
                                    font.family: root.textFontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    width: parent.width
                                }

                                Text {
                                    text: (appType === "camera"
                                        ? "Camera Active"
                                        : (appType === "screen" ? "Screen Sharing" : "Microphone Active"))
                                        + (modelData.pid > 0 ? " • PID " + modelData.pid : "")
                                    color: StyleTokens.textSecondary
                                    font.family: root.textFontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    width: parent.width
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
                                ? (appType === "screen" ? StyleTokens.danger : (root.isMicMuted ? StyleTokens.success : StyleTokens.warning))
                                : StyleTokens.cardFillHover
                            border.width: 1
                            border.color: actionMouseArea.containsMouse ? StyleTokens.transparent : StyleTokens.inputBorder

                            Text {
                                id: actionBtnText
                                anchors.centerIn: parent
                                text: appType === "screen"
                                    ? "Stop"
                                    : (root.isMicMuted ? "Unmute" : "Mute")
                                color: actionMouseArea.containsMouse ? StyleTokens.white : (root.isMicMuted ? StyleTokens.danger : StyleTokens.textPrimaryBright)
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
                color: StyleTokens.cardFill
                border.width: 1
                border.color: StyleTokens.inputBorder

                Text {
                    anchors.centerIn: parent
                    text: "No active microphone or camera capture."
                    color: StyleTokens.textMuted
                    font.family: root.textFontFamily
                    font.pixelSize: 12
                }
            }
        }
    }
}
