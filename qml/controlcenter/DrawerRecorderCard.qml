import QtQuick
import Quickshell
import IslandBackend

Item {
    id: root

    readonly property var userConfig: UserConfig
    readonly property var recorder: ScreenRecorder

    readonly property bool isRecording: recorder ? recorder.isRecording : false
    readonly property bool isPaused: recorder ? recorder.isPaused : false
    readonly property bool isReplayActive: recorder ? recorder.isReplayActive : false
    readonly property bool isMicOn: recorder ? recorder.micEnabled : false
    readonly property string timerText: recorder ? recorder.recordingTimeFormatted : "00:00"

    readonly property color cardAccent: StyleTokens.accent
    readonly property color cardRed: StyleTokens.danger
    readonly property color buttonBg: StyleTokens.cardFill
    readonly property color buttonBgHover: StyleTokens.cardFillHover
    readonly property color buttonBgPressed: StyleTokens.cardFillActive

    width: parent ? parent.width : 180
    height: 80

    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: StyleTokens.radiusModule
        color: StyleTokens.clearBlack
        clip: true

        MatteSurface {
            anchors.fill: parent
            radius: parent.radius
        }

        // Subtle glowing border when recording, harmonized with Matugen
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: StyleTokens.transparent
            border.width: 1
            border.color: root.isRecording ? StyleTokens.withAlpha(root.cardRed, 0.3) : StyleTokens.transparent
        }

        // Top Header Row
        Item {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.top: parent.top
            anchors.topMargin: 11
            height: 20

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.isRecording ? "Recording" : "Recorder"
                    color: StyleTokens.textPrimary
                    font.pixelSize: 12
                    font.family: userConfig.textFontFamily
                    font.weight: Font.DemiBold
                }
            }

            // Right status text (timer when recording, or 60 FPS when idle)
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.isRecording ? root.timerText : "60 FPS"
                color: root.isRecording ? root.cardRed : StyleTokens.textSecondary
                font.pixelSize: 10
                font.family: userConfig.textFontFamily
                font.weight: Font.DemiBold
            }
        }

        // Bottom Actions Row
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            height: 34
            spacing: 6

            // Main Record / Stop Button (fills remaining width)
            Rectangle {
                id: mainRecBtn
                width: parent.width - 34 - 34 - 12
                height: 34
                radius: 10
                scale: recMouse.pressed ? 0.95 : (recMouse.containsMouse ? 1.02 : 1.0)
                color: root.isRecording
                    ? StyleTokens.withAlpha(root.cardRed, 0.22)
                    : (recMouse.pressed ? root.buttonBgPressed : (recMouse.containsMouse ? root.buttonBgHover : root.buttonBg))
                border.color: root.isRecording
                    ? root.cardRed
                    : (recMouse.containsMouse ? StyleTokens.withAlpha(root.cardAccent, 0.35) : StyleTokens.withAlpha(StyleTokens.white, 0.08))
                border.width: 1

                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.isRecording ? 10 : 10
                        height: root.isRecording ? 10 : 10
                        radius: root.isRecording ? 2 : 5
                        color: root.cardRed
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isRecording ? "Stop" : "Record"
                        color: root.isRecording ? root.cardRed : StyleTokens.textPrimary
                        font.pixelSize: 11
                        font.family: userConfig.textFontFamily
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    id: recMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.recorder)
                            root.recorder.toggleRecording();
                    }
                }
            }

            // Mic Toggle Button
            Rectangle {
                width: 34
                height: 34
                radius: 10
                scale: micMouse.pressed ? 0.92 : (micMouse.containsMouse ? 1.06 : 1.0)
                color: root.isMicOn
                    ? StyleTokens.withAlpha(root.cardAccent, 0.22)
                    : (micMouse.pressed ? root.buttonBgPressed : (micMouse.containsMouse ? root.buttonBgHover : root.buttonBg))
                border.color: root.isMicOn
                    ? root.cardAccent
                    : (micMouse.containsMouse ? StyleTokens.withAlpha(root.cardAccent, 0.35) : StyleTokens.withAlpha(StyleTokens.white, 0.08))
                border.width: 1

                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: root.isMicOn ? "\uf130" : "\uf131"
                    color: root.isMicOn ? root.cardAccent : (micMouse.containsMouse ? StyleTokens.textPrimary : StyleTokens.textSecondary)
                    font.pixelSize: 12
                    font.family: userConfig.iconFontFamily
                }

                MouseArea {
                    id: micMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.recorder)
                            root.recorder.toggleMic();
                    }
                }
            }

            // Folder Button
            Rectangle {
                width: 34
                height: 34
                radius: 10
                scale: folderMouse.pressed ? 0.92 : (folderMouse.containsMouse ? 1.06 : 1.0)
                color: folderMouse.pressed ? root.buttonBgPressed : (folderMouse.containsMouse ? root.buttonBgHover : root.buttonBg)
                border.color: folderMouse.containsMouse
                    ? StyleTokens.withAlpha(root.cardAccent, 0.35)
                    : StyleTokens.withAlpha(StyleTokens.white, 0.08)
                border.width: 1

                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "\uf07b"
                    color: folderMouse.containsMouse ? root.cardAccent : StyleTokens.textSecondary
                    font.pixelSize: 12
                    font.family: userConfig.iconFontFamily
                }

                MouseArea {
                    id: folderMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.recorder)
                            root.recorder.openRecordingsFolder();
                    }
                }
            }
        }
    }
}
