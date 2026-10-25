import QtQuick
import Quickshell
import IslandBackend

Item {
    id: root

    readonly property var userConfig: UserConfig
    readonly property var recorder: ScreenRecorder

    readonly property color cardAccent: StyleTokens.accent
    readonly property color cardAccentSoft: StyleTokens.accentSoft
    readonly property color cardRed: StyleTokens.danger
    readonly property color cardYellow: StyleTokens.warning
    readonly property color cardCyan: StyleTokens.accent

    readonly property color buttonBg: StyleTokens.cardFill
    readonly property color buttonBgHover: StyleTokens.cardFillHover
    readonly property color buttonBgPressed: StyleTokens.cardFillActive

    readonly property bool isRecording: recorder ? recorder.isRecording : false
    readonly property bool isPaused: recorder ? recorder.isPaused : false
    readonly property bool isReplayActive: recorder ? recorder.isReplayActive : false
    readonly property bool isMicOn: recorder ? recorder.micEnabled : false
    readonly property string timerText: recorder ? recorder.recordingTimeFormatted : "00:00"

    width: parent ? parent.width : 380
    height: isReplayActive ? 116 : (isRecording ? 98 : 74)

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

        // Subtle glowing border when active, harmonized with Matugen
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: StyleTokens.transparent
            border.width: 1
            border.color: root.isRecording
                ? StyleTokens.withAlpha(root.cardRed, 0.3)
                : (root.isReplayActive ? StyleTokens.withAlpha(root.cardAccent, 0.3) : StyleTokens.transparent)
        }

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // Top Row: Title, Status, and Main Actions
            Row {
                width: parent.width
                height: 46
                spacing: 12

                // Record / Stop Main Button
                Rectangle {
                    id: mainRecordButton
                    width: 44
                    height: 44
                    radius: 22
                    anchors.verticalCenter: parent.verticalCenter
                    scale: recordMouse.pressed ? 0.94 : (recordMouse.containsMouse ? 1.04 : 1.0)
                    color: root.isRecording
                        ? StyleTokens.withAlpha(root.cardRed, 0.22)
                        : (recordMouse.pressed
                            ? root.buttonBgPressed
                            : (recordMouse.containsMouse ? root.buttonBgHover : root.buttonBg))
                    border.color: root.isRecording
                        ? root.cardRed
                        : (recordMouse.containsMouse ? StyleTokens.withAlpha(root.cardAccent, 0.4) : StyleTokens.withAlpha(StyleTokens.white, 0.12))
                    border.width: 1

                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    // Icon: Stop square if recording, Red dot if idle
                    Rectangle {
                        anchors.centerIn: parent
                        width: root.isRecording ? 16 : 14
                        height: root.isRecording ? 16 : 14
                        radius: root.isRecording ? 3 : 7
                        color: root.isRecording ? root.cardRed : (recordMouse.containsMouse ? root.cardRed : StyleTokens.withAlpha(root.cardRed, 0.85))

                        Behavior on radius { NumberAnimation { duration: 160 } }
                        Behavior on width { NumberAnimation { duration: 160 } }
                    }

                    MouseArea {
                        id: recordMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.recorder)
                                root.recorder.toggleRecording();
                        }
                    }
                }

                // Info: Title & Dynamic Status
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - mainRecordButton.width - actionButtonsRow.width - 24
                    spacing: 3

                    Text {
                        text: "Screen Recorder"
                        color: StyleTokens.textPrimary
                        font.pixelSize: 13
                        font.family: userConfig.textFontFamily
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Row {
                        spacing: 6
                        anchors.left: parent.left

                        // Pulsing dot for live recording
                        Rectangle {
                            visible: root.isRecording
                            width: 6
                            height: 6
                            radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.isPaused ? root.cardYellow : root.cardRed

                            SequentialAnimation on opacity {
                                running: root.isRecording && !root.isPaused
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (root.isRecording) {
                                    return root.isPaused ? ("Paused • " + root.timerText) : ("Recording • " + root.timerText);
                                }
                                if (root.isReplayActive) {
                                    return "Replay Buffer Active (60s)";
                                }
                                return "60 FPS • GPU Accelerated";
                            }
                            color: root.isRecording
                                ? (root.isPaused ? root.cardYellow : root.cardRed)
                                : (root.isReplayActive ? root.cardCyan : StyleTokens.textMuted)
                            font.pixelSize: 11
                            font.family: userConfig.textFontFamily
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                    }
                }

                // Quick Action Pill Buttons
                Row {
                    id: actionButtonsRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // Pause / Resume Button (Visible only when recording)
                    Rectangle {
                        visible: root.isRecording
                        width: 34
                        height: 34
                        radius: 10
                        scale: pauseMouse.pressed ? 0.92 : (pauseMouse.containsMouse ? 1.06 : 1.0)
                        color: pauseMouse.pressed
                            ? root.buttonBgPressed
                            : (pauseMouse.containsMouse ? root.buttonBgHover : root.buttonBg)
                        border.color: root.isPaused ? root.cardYellow : (pauseMouse.containsMouse ? StyleTokens.withAlpha(root.cardAccent, 0.35) : StyleTokens.withAlpha(StyleTokens.white, 0.08))
                        border.width: 1

                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: root.isPaused ? "\uf04b" : "\uf04c"
                            color: root.isPaused ? root.cardYellow : (pauseMouse.containsMouse ? StyleTokens.textPrimary : StyleTokens.textSecondary)
                            font.pixelSize: 12
                            font.family: userConfig.iconFontFamily
                        }

                        MouseArea {
                            id: pauseMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.recorder)
                                    root.recorder.pauseRecording();
                            }
                        }
                    }

                    // Microphone Toggle Button
                    Rectangle {
                        width: 34
                        height: 34
                        radius: 10
                        scale: micMouse.pressed ? 0.92 : (micMouse.containsMouse ? 1.06 : 1.0)
                        color: root.isMicOn
                            ? StyleTokens.withAlpha(root.cardAccent, 0.22)
                            : (micMouse.pressed
                                ? root.buttonBgPressed
                                : (micMouse.containsMouse ? root.buttonBgHover : root.buttonBg))
                        border.color: root.isMicOn ? root.cardAccent : (micMouse.containsMouse ? StyleTokens.withAlpha(root.cardAccent, 0.35) : StyleTokens.withAlpha(StyleTokens.white, 0.08))
                        border.width: 1

                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf130"
                            color: root.isMicOn ? root.cardAccent : (micMouse.containsMouse ? StyleTokens.textPrimary : StyleTokens.textSecondary)
                            font.pixelSize: 13
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

                    // Replay Buffer Toggle Button
                    Rectangle {
                        width: 34
                        height: 34
                        radius: 10
                        scale: replayMouse.pressed ? 0.92 : (replayMouse.containsMouse ? 1.06 : 1.0)
                        color: root.isReplayActive
                            ? StyleTokens.withAlpha(root.cardAccent, 0.22)
                            : (replayMouse.pressed
                                ? root.buttonBgPressed
                                : (replayMouse.containsMouse ? root.buttonBgHover : root.buttonBg))
                        border.color: root.isReplayActive ? root.cardAccent : (replayMouse.containsMouse ? StyleTokens.withAlpha(root.cardAccent, 0.35) : StyleTokens.withAlpha(StyleTokens.white, 0.08))
                        border.width: 1

                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf0e7"
                            color: root.isReplayActive ? root.cardAccent : (replayMouse.containsMouse ? StyleTokens.textPrimary : StyleTokens.textSecondary)
                            font.pixelSize: 13
                            font.family: userConfig.iconFontFamily
                        }

                        MouseArea {
                            id: replayMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.recorder)
                                    root.recorder.toggleReplay();
                            }
                        }
                    }

                    // Open Recordings Folder Button
                    Rectangle {
                        width: 34
                        height: 34
                        radius: 10
                        scale: folderMouse.pressed ? 0.92 : (folderMouse.containsMouse ? 1.06 : 1.0)
                        color: folderMouse.pressed
                            ? root.buttonBgPressed
                            : (folderMouse.containsMouse ? root.buttonBgHover : root.buttonBg)
                        border.color: folderMouse.containsMouse ? StyleTokens.withAlpha(root.cardAccent, 0.35) : StyleTokens.withAlpha(StyleTokens.white, 0.08)
                        border.width: 1

                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf07b"
                            color: folderMouse.containsMouse ? root.cardAccent : StyleTokens.textSecondary
                            font.pixelSize: 13
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

            // Secondary Row: Save Replay Quick Actions (when replay buffer is active)
            Row {
                visible: root.isReplayActive
                width: parent.width
                height: 32
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Save Clip:"
                    color: StyleTokens.textSecondary
                    font.pixelSize: 11
                    font.family: userConfig.textFontFamily
                    font.weight: Font.Medium
                }

                // Save 60s
                Rectangle {
                    width: 74
                    height: 28
                    radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    scale: clip60Mouse.pressed ? 0.94 : (clip60Mouse.containsMouse ? 1.03 : 1.0)
                    color: clip60Mouse.pressed
                        ? root.buttonBgPressed
                        : (clip60Mouse.containsMouse ? root.buttonBgHover : root.buttonBg)
                    border.color: clip60Mouse.containsMouse ? root.cardAccent : StyleTokens.withAlpha(root.cardAccent, 0.4)
                    border.width: 1

                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Last 60s"
                        color: clip60Mouse.containsMouse ? root.cardAccent : StyleTokens.textPrimary
                        font.pixelSize: 11
                        font.family: userConfig.textFontFamily
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: clip60Mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.recorder)
                                root.recorder.saveReplay(60);
                        }
                    }
                }

                // Save 30s
                Rectangle {
                    width: 74
                    height: 28
                    radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    scale: clip30Mouse.pressed ? 0.94 : (clip30Mouse.containsMouse ? 1.03 : 1.0)
                    color: clip30Mouse.pressed
                        ? root.buttonBgPressed
                        : (clip30Mouse.containsMouse ? root.buttonBgHover : root.buttonBg)
                    border.color: clip30Mouse.containsMouse ? root.cardAccent : StyleTokens.withAlpha(root.cardAccent, 0.3)
                    border.width: 1

                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Last 30s"
                        color: clip30Mouse.containsMouse ? root.cardAccent : StyleTokens.textSecondary
                        font.pixelSize: 11
                        font.family: userConfig.textFontFamily
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: clip30Mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.recorder)
                                root.recorder.saveReplay(30);
                        }
                    }
                }

                // Save 10s
                Rectangle {
                    width: 74
                    height: 28
                    radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    scale: clip10Mouse.pressed ? 0.94 : (clip10Mouse.containsMouse ? 1.03 : 1.0)
                    color: clip10Mouse.pressed
                        ? root.buttonBgPressed
                        : (clip10Mouse.containsMouse ? root.buttonBgHover : root.buttonBg)
                    border.color: clip10Mouse.containsMouse ? root.cardAccent : StyleTokens.withAlpha(StyleTokens.white, 0.1)
                    border.width: 1

                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Last 10s"
                        color: clip10Mouse.containsMouse ? root.cardAccent : StyleTokens.textSecondary
                        font.pixelSize: 11
                        font.family: userConfig.textFontFamily
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: clip10Mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.recorder)
                                root.recorder.saveReplay(10);
                        }
                    }
                }
            }
        }
    }
}
