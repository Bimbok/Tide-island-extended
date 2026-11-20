import QtQuick
import Quickshell
import IslandBackend
import "../common"

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

    focus: true

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            if (root.provider && root.provider.setConnectivityPanelOpen) {
                root.provider.setConnectivityPanelOpen("equalizer", false);
            }
            event.accepted = true;
        }
    }

    GlassSurface {
        anchors.fill: parent
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
        FlyoutHeader {
            id: headerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            title: "Equalizer"
            heroFontFamily: root.heroFontFamily
            textFontFamily: root.textFontFamily
            iconFontFamily: root.iconFontFamily

            ActionPill {
                text: SystemServices.equalizerEnabled ? SystemServices.equalizerPreset : "Bypassed"
                highlighted: SystemServices.equalizerEnabled
                clickable: false
                fontSize: 9
                textFontFamily: root.heroFontFamily
            }

            // Master Enable / Bypass Switch (Reusable Island Switch)
            SwitchToggle {
                id: masterToggle
                anchors.verticalCenter: parent.verticalCenter
                checked: SystemServices.equalizerEnabled
                activeColor: StyleTokens.success
                onToggled: function(val) {
                    SystemServices.setEqualizerEnabled(val);
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

                        ActionPill {
                            height: 26
                            text: modelData
                            active: SystemServices.equalizerEnabled && SystemServices.equalizerPreset === modelData
                            activeColor: StyleTokens.accent
                            activeBorderColor: StyleTokens.accent
                            activeTextColor: StyleTokens.black
                            textFontFamily: root.textFontFamily
                            fontSize: 10
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

                    ActionPill {
                        height: 24
                        text: modelData === "off" ? "Off" : (modelData === "balanced" ? "Bal" : "Night")
                        active: SystemServices.equalizerDynamics === modelData
                        fontSize: 9
                        textFontFamily: root.textFontFamily
                        onClicked: SystemServices.setEqualizerDynamics(modelData)
                    }
                }
            }

            // Right: Mono and Reset buttons
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                ActionPill {
                    height: 24
                    text: "Mono"
                    active: SystemServices.equalizerMono
                    fontSize: 9
                    textFontFamily: root.textFontFamily
                    onClicked: SystemServices.setEqualizerMono(!SystemServices.equalizerMono)
                }

                ActionPill {
                    height: 24
                    text: "Reset"
                    fontSize: 9
                    textFontFamily: root.textFontFamily
                    onClicked: SystemServices.resetEqualizer()
                }
            }
        }
    }
}
