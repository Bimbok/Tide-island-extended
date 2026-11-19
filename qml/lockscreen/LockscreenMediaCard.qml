import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Widgets
import IslandBackend
import "../island"

Rectangle {
    id: root

    property var activePlayer: null
    property bool hasMedia: false
    property string trackTitle: ""
    property string trackArtist: ""
    property string trackArtUrl: ""
    property bool isMediaPlaying: false
    property real trackProgress: 0
    property string timePlayed: "0:00"
    property string timeTotal: "0:00"
    property bool locked: true
    property string textFont: ""
    property string nerdFont: ""

    signal seekRequested(real ratio)

    height: root.hasMedia ? 164 : 0
    visible: root.hasMedia
    radius: 20
    color: "#30000000"
    border.width: 1
    border.color: StyleTokens.surfaceHighlight
    clip: true
    antialiasing: true

    Behavior on height {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // Row 1: Album Art + Track Info + Live Audio Waveform Visualizer
        RowLayout {
            width: parent.width
            spacing: 12

            // Album Art with rounded squircle and subtle border
            ClippingRectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: 14
                color: StyleTokens.cardFillHover

                Text {
                    anchors.centerIn: parent
                    text: "󰝚" // Cute music note
                    font.family: root.nerdFont
                    font.pixelSize: 22
                    color: StyleTokens.textMuted
                    visible: artImage.status !== Image.Ready
                }

                Image {
                    id: artImage
                    anchors.fill: parent
                    source: root.trackArtUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(96, 96)
                }
            }

            // Track Title & Artist
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: root.trackTitle
                    font.family: root.textFont
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: StyleTokens.textPrimaryBright
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.trackArtist
                    font.family: root.textFont
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: StyleTokens.textSecondary
                    elide: Text.ElideRight
                }
            }

            // Live Animated Audio Visualizer Bars
            LiveAudioVisualizer {
                Layout.alignment: Qt.AlignVCenter
                barWidth: 3.5
                barSpacing: 3
                barRadius: 1.75
                minHeight: 4
                maxHeight: 22
                isPlaying: root.isMediaPlaying
                active: root.locked && root.hasMedia
                activeColor: StyleTokens.accent
                pausedColor: StyleTokens.withAlpha(StyleTokens.accent, 0.40)
            }
        }

        // Row 2: Seekable Progress Bar & Timestamps (Mac / Control Center style)
        RowLayout {
            width: parent.width
            spacing: 8

            Text {
                text: root.timePlayed
                font.family: root.textFont
                font.pixelSize: 10
                font.weight: Font.Medium
                color: trackContainer.isHovered ? StyleTokens.textPrimaryBright : StyleTokens.textMuted
                Layout.alignment: Qt.AlignVCenter
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Item {
                id: trackContainer
                Layout.fillWidth: true
                height: 22

                readonly property bool isHovered: progressMouse.containsMouse || progressMouse.pressed
                readonly property real currentTrackHeight: isHovered ? 14 : 8

                // Mac / Control Center style rounded capsule track
                Rectangle {
                    id: trackBg
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: trackContainer.currentTrackHeight
                    radius: height / 2
                    color: trackContainer.isHovered
                        ? Qt.rgba(255, 255, 255, 0.16)
                        : Qt.rgba(255, 255, 255, 0.10)
                    border.width: 1
                    border.color: trackContainer.isHovered
                        ? Qt.rgba(255, 255, 255, 0.20)
                        : Qt.rgba(255, 255, 255, 0.06)
                    clip: true

                    Behavior on height {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    // Active filled progress capsule
                    Rectangle {
                        id: trackFill
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        radius: parent.radius
                        color: StyleTokens.accent
                        width: root.trackProgress <= 0.001
                            ? 0
                            : Math.min(parent.width, parent.width * Math.max(0, Math.min(1.0, root.trackProgress)))

                        Behavior on width {
                            enabled: !progressMouse.pressed
                            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                        }
                    }
                }

                MouseArea {
                    id: progressMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => root.seekRequested(mouse.x / width)
                    onClicked: mouse => root.seekRequested(mouse.x / width)
                    onPositionChanged: mouse => {
                        if (pressed) root.seekRequested(mouse.x / width)
                    }
                }
            }

            Text {
                text: root.timeTotal
                font.family: root.textFont
                font.pixelSize: 10
                font.weight: Font.Medium
                color: trackContainer.isHovered ? StyleTokens.textPrimaryBright : StyleTokens.textMuted
                Layout.alignment: Qt.AlignVCenter
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        // Row 3: Perfectly Spaced Hero Playback Controls
        Item {
            width: parent.width
            height: 44

            Row {
                anchors.centerIn: parent
                spacing: 28

                // Previous Button
                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    color: prevMouse.containsMouse
                        ? StyleTokens.withAlpha(StyleTokens.white, 0.15)
                        : "#13ffffff"
                    border.width: 1
                    border.color: prevMouse.containsMouse ? StyleTokens.accent : StyleTokens.surfaceHighlight
                    scale: prevMouse.pressed ? 0.88 : (prevMouse.containsMouse ? 1.10 : 1.0)
                    anchors.verticalCenter: parent.verticalCenter
                    antialiasing: true

                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒮"
                        font.family: root.nerdFont
                        font.pixelSize: 16
                        color: prevMouse.containsMouse ? StyleTokens.accent : StyleTokens.textPrimaryBright
                    }
                    MouseArea {
                        id: prevMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.activePlayer && root.activePlayer.canGoPrevious) root.activePlayer.previous()
                    }
                }

                // Play / Pause Hero Pill
                Rectangle {
                    width: 44
                    height: 44
                    radius: 22
                    color: StyleTokens.accent
                    scale: playMouse.pressed ? 0.88 : (playMouse.containsMouse ? 1.10 : 1.0)
                    anchors.verticalCenter: parent.verticalCenter

                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                    // Ambient glow on play button
                    RectangularGlow {
                        anchors.fill: parent
                        glowRadius: 14
                        spread: 0.08
                        color: StyleTokens.withAlpha(StyleTokens.accent, 0.40)
                        cornerRadius: 22
                        opacity: root.isMediaPlaying ? 1.0 : 0.4
                    }

                    // Pause state: two crisp rounded vertical bars
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        visible: root.isMediaPlaying

                        Rectangle {
                            width: 3.5
                            height: 14
                            radius: 1.75
                            color: StyleTokens.textOnAccent
                        }
                        Rectangle {
                            width: 3.5
                            height: 14
                            radius: 1.75
                            color: StyleTokens.textOnAccent
                        }
                    }

                    // Play state: right-pointing triangle
                    Canvas {
                        id: playCanvas
                        width: 14
                        height: 14
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 1
                        visible: !root.isMediaPlaying

                        property color fillColor: StyleTokens.textOnAccent
                        onFillColorChanged: requestPaint()
                        onVisibleChanged: if (visible) requestPaint()

                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            ctx.fillStyle = fillColor;
                            ctx.beginPath();
                            ctx.moveTo(1.5, 0.5);
                            ctx.lineTo(13.5, 7.0);
                            ctx.lineTo(1.5, 13.5);
                            ctx.closePath();
                            ctx.fill();
                        }
                    }

                    MouseArea {
                        id: playMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.activePlayer && root.activePlayer.canControl) root.activePlayer.togglePlaying()
                    }
                }

                // Next Button
                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    color: nextMouse.containsMouse
                        ? StyleTokens.withAlpha(StyleTokens.white, 0.15)
                        : "#13ffffff"
                    border.width: 1
                    border.color: nextMouse.containsMouse ? StyleTokens.accent : StyleTokens.surfaceHighlight
                    scale: nextMouse.pressed ? 0.88 : (nextMouse.containsMouse ? 1.10 : 1.0)
                    anchors.verticalCenter: parent.verticalCenter
                    antialiasing: true

                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒭"
                        font.family: root.nerdFont
                        font.pixelSize: 16
                        color: nextMouse.containsMouse ? StyleTokens.accent : StyleTokens.textPrimaryBright
                    }
                    MouseArea {
                        id: nextMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.activePlayer && root.activePlayer.canGoNext) root.activePlayer.next()
                    }
                }
            }
        }
    }
}
