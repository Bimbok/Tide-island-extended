import QtQuick
import Quickshell
import IslandBackend

Item {
    id: root

    property var provider: null
    property string panelKind: "equalizer"
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property string heroFontFamily: textFontFamily
    property real presentationProgress: 1

    readonly property var presetList: ["Flat", "Bass", "Treble", "Vocal", "Pop", "Rock", "Jazz", "Classic"]
    readonly property var bandFrequencies: ["32", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    Rectangle {
        anchors.fill: parent
        radius: 28
        color: StyleTokens.module
        opacity: 0.9
    }

    Item {
        id: contentRoot
        anchors.fill: parent
        anchors.margins: 16
        opacity: 0.45 + root.presentationProgress * 0.55

        Behavior on opacity {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        // Header Row
        Item {
            id: headerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 26

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // Equalizer Icon
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\udb80\udf79"
                    color: SystemServices.equalizerEnabled ? StyleTokens.accent : StyleTokens.textMuted
                    font.pixelSize: 15
                    font.family: root.iconFontFamily
                }

                // Title
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Equalizer"
                    color: StyleTokens.textPrimary
                    font.pixelSize: 15
                    font.family: root.heroFontFamily
                    font.weight: Font.Bold
                }

                // Preset / Status Badge
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 20
                    width: statusBadgeText.implicitWidth + 12
                    radius: 10
                    color: SystemServices.equalizerEnabled
                        ? StyleTokens.withAlpha(StyleTokens.accent, 0.20)
                        : StyleTokens.withAlpha(StyleTokens.textMuted, 0.15)
                    border.width: 1
                    border.color: SystemServices.equalizerEnabled
                        ? StyleTokens.accent
                        : StyleTokens.withAlpha(StyleTokens.textMuted, 0.40)

                    Text {
                        id: statusBadgeText
                        anchors.centerIn: parent
                        text: SystemServices.equalizerEnabled
                            ? SystemServices.equalizerPreset
                            : "Bypassed"
                        color: SystemServices.equalizerEnabled
                            ? StyleTokens.accent
                            : StyleTokens.textMuted
                        font.pixelSize: 9
                        font.family: root.heroFontFamily
                        font.weight: Font.Bold
                    }
                }
            }

            // Master Enable / Bypass Switch
            Item {
                id: masterToggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 24

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: SystemServices.equalizerEnabled
                        ? StyleTokens.accent
                        : StyleTokens.cardFill
                    border.width: 1
                    border.color: SystemServices.equalizerEnabled
                        ? StyleTokens.accent
                        : StyleTokens.inputBorder

                    Behavior on color {
                        ColorAnimation { duration: 160 }
                    }

                    Rectangle {
                        id: switchThumb
                        width: 18
                        height: 18
                        radius: 9
                        anchors.verticalCenter: parent.verticalCenter
                        x: SystemServices.equalizerEnabled ? 23 : 3
                        color: SystemServices.equalizerEnabled ? StyleTokens.black : StyleTokens.textSecondary

                        Behavior on x {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on color {
                            ColorAnimation { duration: 160 }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        SystemServices.setEqualizerEnabled(!SystemServices.equalizerEnabled);
                    }
                }
            }
        }

        // Preset Pills
        Item {
            id: presetsContainer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerRow.bottom
            anchors.topMargin: 10
            height: 28

            Flickable {
                anchors.fill: parent
                contentWidth: presetRow.implicitWidth
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                clip: true

                Row {
                    id: presetRow
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: root.presetList

                        Rectangle {
                            id: presetChip
                            readonly property bool isSelected: SystemServices.equalizerEnabled && SystemServices.equalizerPreset === modelData
                            height: 26
                            width: presetLabel.implicitWidth + 16
                            radius: 13
                            color: isSelected
                                ? StyleTokens.accent
                                : (chipMouse.containsMouse
                                    ? StyleTokens.cardFillHover
                                    : StyleTokens.cardFill)
                            border.width: 1
                            border.color: isSelected
                                ? StyleTokens.accent
                                : StyleTokens.inputBorder

                            Behavior on color {
                                ColorAnimation { duration: 120 }
                            }

                            Text {
                                id: presetLabel
                                anchors.centerIn: parent
                                text: modelData
                                font.pixelSize: 10
                                font.family: root.textFontFamily
                                font.weight: presetChip.isSelected ? Font.Bold : Font.Normal
                                color: presetChip.isSelected
                                    ? StyleTokens.black
                                    : (chipMouse.containsMouse
                                        ? StyleTokens.textPrimary
                                        : StyleTokens.textSecondary)
                            }

                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!SystemServices.equalizerEnabled) {
                                        SystemServices.setEqualizerEnabled(true);
                                    }
                                    SystemServices.applyEqualizerPreset(modelData);
                                }
                            }
                        }
                    }
                }
            }
        }

        // 10-Band Sliders Container
        Rectangle {
            id: slidersBox
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: presetsContainer.bottom
            anchors.topMargin: 10
            height: 220
            radius: 16
            color: StyleTokens.cardFill
            border.width: 1
            border.color: StyleTokens.inputBorder
            opacity: SystemServices.equalizerEnabled ? 1.0 : 0.55

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            // Zero dB Center Reference Line
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                y: 110 // Center of slider track area
                height: 1
                color: StyleTokens.withAlpha(StyleTokens.track, 0.50)
            }

            // 10 Frequency Band Columns
            Row {
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                anchors.topMargin: 8
                anchors.bottomMargin: 8

                Repeater {
                    model: 10

                    Item {
                        id: bandColumn
                        width: parent.width / 10
                        height: parent.height

                        readonly property int bandIndex: index
                        readonly property real currentGain: (SystemServices.equalizerBands && SystemServices.equalizerBands.length > index)
                            ? Number(SystemServices.equalizerBands[index])
                            : 0.0

                        // Gain dB text at top
                        Text {
                            id: gainText
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: (bandColumn.currentGain > 0 ? "+" : "") + Math.round(bandColumn.currentGain)
                            font.pixelSize: 9
                            font.family: root.textFontFamily
                            font.weight: Math.abs(bandColumn.currentGain) > 0.5 ? Font.Bold : Font.Normal
                            color: Math.abs(bandColumn.currentGain) > 0.5
                                ? (SystemServices.equalizerEnabled ? StyleTokens.accent : StyleTokens.textPrimary)
                                : StyleTokens.textMuted
                        }

                        // Vertical Slider Track Area
                        Item {
                            id: trackArea
                            anchors.top: gainText.bottom
                            anchors.topMargin: 6
                            anchors.bottom: freqText.top
                            anchors.bottomMargin: 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width

                            readonly property real trackHeight: height - 12
                            readonly property real trackCenterY: height / 2
                            readonly property real maxDb: 12.0 // UI slider scale -12 to +12 dB

                            // Track Background Pill
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 6
                                width: 4
                                height: trackArea.trackHeight
                                radius: 2
                                color: StyleTokens.track
                            }

                            // Active Fill Bar from 0 dB Center
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 4
                                radius: 2
                                color: SystemServices.equalizerEnabled ? StyleTokens.accent : StyleTokens.textSecondary

                                y: bandColumn.currentGain >= 0
                                    ? (trackArea.trackCenterY - Math.min(trackArea.trackHeight / 2, (bandColumn.currentGain / trackArea.maxDb) * (trackArea.trackHeight / 2)))
                                    : trackArea.trackCenterY
                                height: Math.abs((bandColumn.currentGain / trackArea.maxDb) * (trackArea.trackHeight / 2))
                            }

                            // Draggable Knob
                            Rectangle {
                                id: sliderKnob
                                width: 12
                                height: 12
                                radius: 6
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: trackArea.trackCenterY - (bandColumn.currentGain / trackArea.maxDb) * (trackArea.trackHeight / 2) - 6
                                color: columnMouse.containsMouse || columnMouse.drag.active
                                    ? StyleTokens.white
                                    : (SystemServices.equalizerEnabled ? StyleTokens.accent : StyleTokens.textSecondary)
                                border.width: 1.5
                                border.color: SystemServices.equalizerEnabled ? StyleTokens.accent : StyleTokens.cardFill

                                Behavior on color {
                                    ColorAnimation { duration: 100 }
                                }
                            }

                            // Interactive Area for Dragging & Wheel
                            MouseArea {
                                id: columnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.SizeVerCursor

                                function updateFromY(mouseY) {
                                    var clampedY = Math.max(6, Math.min(trackArea.trackHeight + 6, mouseY));
                                    var normalized = (trackArea.trackCenterY - clampedY) / (trackArea.trackHeight / 2);
                                    var newGain = Math.max(-12.0, Math.min(12.0, normalized * trackArea.maxDb));
                                    newGain = Math.round(newGain * 2) / 2; // snap to 0.5 dB
                                    if (bandColumn.currentGain !== newGain) {
                                        if (!SystemServices.equalizerEnabled) {
                                            SystemServices.setEqualizerEnabled(true);
                                        }
                                        SystemServices.setEqualizerBand(bandColumn.bandIndex, newGain);
                                    }
                                }

                                onPressed: (mouse) => updateFromY(mouse.y)
                                onPositionChanged: (mouse) => {
                                    if (pressed) updateFromY(mouse.y);
                                }

                                onDoubleClicked: {
                                    // Reset this band to 0 dB
                                    SystemServices.setEqualizerBand(bandColumn.bandIndex, 0.0);
                                }

                                onWheel: (wheel) => {
                                    var step = wheel.angleDelta.y > 0 ? 1.0 : -1.0;
                                    var targetGain = Math.max(-12.0, Math.min(12.0, bandColumn.currentGain + step));
                                    if (!SystemServices.equalizerEnabled) {
                                        SystemServices.setEqualizerEnabled(true);
                                    }
                                    SystemServices.setEqualizerBand(bandColumn.bandIndex, targetGain);
                                }
                            }
                        }

                        // Frequency Label at bottom
                        Text {
                            id: freqText
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.bandFrequencies[index]
                            font.pixelSize: 9
                            font.family: root.textFontFamily
                            color: StyleTokens.textSecondary
                        }
                    }
                }
            }
        }

        // Bottom Controls: Dynamics Pills + Mono Toggle + Reset Button
        Item {
            id: bottomControlsRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: slidersBox.bottom
            anchors.topMargin: 10
            height: 30

            // Left: Dynamics Selector
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Dyn:"
                    font.pixelSize: 10
                    font.family: root.textFontFamily
                    font.weight: Font.Medium
                    color: StyleTokens.textSecondary
                }

                Repeater {
                    model: ["off", "balanced", "night"]

                    Rectangle {
                        id: dynChip
                        readonly property bool isSelected: SystemServices.equalizerDynamics === modelData
                        height: 24
                        width: dynLabel.implicitWidth + 12
                        radius: 12
                        color: isSelected
                            ? StyleTokens.withAlpha(StyleTokens.accent, 0.25)
                            : (dynMouse.containsMouse ? StyleTokens.cardFillHover : StyleTokens.cardFill)
                        border.width: 1
                        border.color: isSelected ? StyleTokens.accent : StyleTokens.inputBorder

                        Text {
                            id: dynLabel
                            anchors.centerIn: parent
                            text: modelData === "off" ? "Off" : (modelData === "balanced" ? "Bal" : "Night")
                            font.pixelSize: 9
                            font.family: root.textFontFamily
                            font.weight: dynChip.isSelected ? Font.Bold : Font.Normal
                            color: dynChip.isSelected ? StyleTokens.accent : StyleTokens.textSecondary
                        }

                        MouseArea {
                            id: dynMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SystemServices.setEqualizerDynamics(modelData)
                        }
                    }
                }
            }

            // Right: Mono and Reset buttons
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // Mono Pill Toggle
                Rectangle {
                    id: monoButton
                    height: 24
                    width: monoText.implicitWidth + 14
                    radius: 12
                    color: SystemServices.equalizerMono
                        ? StyleTokens.withAlpha(StyleTokens.accent, 0.25)
                        : (monoMouse.containsMouse ? StyleTokens.cardFillHover : StyleTokens.cardFill)
                    border.width: 1
                    border.color: SystemServices.equalizerMono ? StyleTokens.accent : StyleTokens.inputBorder

                    Text {
                        id: monoText
                        anchors.centerIn: parent
                        text: "Mono"
                        font.pixelSize: 9
                        font.family: root.textFontFamily
                        font.weight: SystemServices.equalizerMono ? Font.Bold : Font.Normal
                        color: SystemServices.equalizerMono ? StyleTokens.accent : StyleTokens.textSecondary
                    }

                    MouseArea {
                        id: monoMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SystemServices.setEqualizerMono(!SystemServices.equalizerMono)
                    }
                }

                // Reset Button
                Rectangle {
                    id: resetButton
                    height: 24
                    width: resetText.implicitWidth + 14
                    radius: 12
                    color: resetMouse.containsMouse ? StyleTokens.cardFillHover : StyleTokens.cardFill
                    border.width: 1
                    border.color: StyleTokens.inputBorder

                    Text {
                        id: resetText
                        anchors.centerIn: parent
                        text: "Reset"
                        font.pixelSize: 9
                        font.family: root.textFontFamily
                        font.weight: Font.Medium
                        color: resetMouse.containsMouse ? StyleTokens.textPrimary : StyleTokens.textSecondary
                    }

                    MouseArea {
                        id: resetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SystemServices.resetEqualizer()
                    }
                }
            }
        }
    }
}
