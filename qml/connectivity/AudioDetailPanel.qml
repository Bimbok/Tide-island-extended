import QtQuick
import Quickshell
import IslandBackend

Item {
    id: root

    property var provider: null
    property string panelKind: "audio_output"
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property string heroFontFamily: textFontFamily
    property real presentationProgress: 1

    property string activeTab: panelKind === "audio_input" ? "inputs" : "outputs"

    function getDeviceGlyph(iconType) {
        if (iconType === "headphones") return "\uf025";
        if (iconType === "bluetooth") return "\udb80\udcaf";
        if (iconType === "hdmi") return "\udb80\ude41";
        if (iconType === "headset") return "\udb80\udccd";
        if (iconType === "mic") return "\uf130";
        return "\udb81\udcc3"; // speaker default
    }

    onPanelKindChanged: {
        if (panelKind === "audio_input") {
            activeTab = "inputs";
        } else if (panelKind === "audio_output") {
            if (activeTab === "inputs")
                activeTab = "outputs";
        }
    }

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

        // Header
        Item {
            id: headerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 24

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Audio"
                color: StyleTokens.textPrimary
                font.pixelSize: 15
                font.family: root.heroFontFamily
                font.weight: Font.Bold
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 22
                radius: 11
                color: StyleTokens.cardFill
                visible: SystemServices.appStreams.length > 0
                width: appCountText.implicitWidth + 14

                Text {
                    id: appCountText
                    anchors.centerIn: parent
                    text: SystemServices.appStreams.length + (SystemServices.appStreams.length === 1 ? " app" : " apps")
                    color: StyleTokens.textSecondary
                    font.pixelSize: 10
                    font.family: root.textFontFamily
                    font.weight: Font.Medium
                }
            }
        }

        // Segmented Tabs: Outputs | Inputs | Mixer
        Rectangle {
            id: segmentedTabs
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerRow.bottom
            anchors.topMargin: 12
            height: 36
            radius: 18
            color: StyleTokens.input
            border.width: 1
            border.color: StyleTokens.inputBorder
            clip: true

            Row {
                anchors.fill: parent

                // Tab: Outputs
                Rectangle {
                    width: parent.width / 3
                    height: parent.height
                    radius: 18
                    color: root.activeTab === "outputs" ? StyleTokens.accent : (outMouse.containsMouse ? StyleTokens.moduleHover : StyleTokens.transparent)

                    Behavior on color { ColorAnimation { duration: 140 } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\udb81\udcc3"
                            font.pixelSize: 12
                            font.family: root.iconFontFamily
                            color: root.activeTab === "outputs" ? StyleTokens.textOnAccent : StyleTokens.textSecondary
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Output"
                            font.pixelSize: 11
                            font.family: root.textFontFamily
                            font.weight: root.activeTab === "outputs" ? Font.DemiBold : Font.Normal
                            color: root.activeTab === "outputs" ? StyleTokens.textOnAccent : StyleTokens.textSecondary
                        }
                    }

                    MouseArea {
                        id: outMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = "outputs"
                    }
                }

                // Tab: Inputs
                Rectangle {
                    width: parent.width / 3
                    height: parent.height
                    radius: 18
                    color: root.activeTab === "inputs" ? StyleTokens.accent : (inMouse.containsMouse ? StyleTokens.moduleHover : StyleTokens.transparent)

                    Behavior on color { ColorAnimation { duration: 140 } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uf130"
                            font.pixelSize: 12
                            font.family: root.iconFontFamily
                            color: root.activeTab === "inputs" ? StyleTokens.textOnAccent : StyleTokens.textSecondary
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Input"
                            font.pixelSize: 11
                            font.family: root.textFontFamily
                            font.weight: root.activeTab === "inputs" ? Font.DemiBold : Font.Normal
                            color: root.activeTab === "inputs" ? StyleTokens.textOnAccent : StyleTokens.textSecondary
                        }
                    }

                    MouseArea {
                        id: inMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = "inputs"
                    }
                }

                // Tab: Mixer (Apps)
                Rectangle {
                    width: parent.width / 3
                    height: parent.height
                    radius: 18
                    color: root.activeTab === "apps" ? StyleTokens.accent : (appMouse.containsMouse ? StyleTokens.moduleHover : StyleTokens.transparent)

                    Behavior on color { ColorAnimation { duration: 140 } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uf1de"
                            font.pixelSize: 12
                            font.family: root.iconFontFamily
                            color: root.activeTab === "apps" ? StyleTokens.textOnAccent : StyleTokens.textSecondary
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Mixer"
                            font.pixelSize: 11
                            font.family: root.textFontFamily
                            font.weight: root.activeTab === "apps" ? Font.DemiBold : Font.Normal
                            color: root.activeTab === "apps" ? StyleTokens.textOnAccent : StyleTokens.textSecondary
                        }
                    }

                    MouseArea {
                        id: appMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = "apps"
                    }
                }
            }
        }

        // View 1: Outputs List
        ListView {
            id: outputsList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: segmentedTabs.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            visible: root.activeTab === "outputs"
            clip: true
            spacing: 8
            model: SystemServices.audioOutputs

            delegate: Rectangle {
                id: outputDelegate
                required property var modelData
                width: outputsList.width
                height: 56
                radius: 16
                color: modelData.active
                    ? StyleTokens.withAlpha(StyleTokens.accent, 0.15)
                    : (outputMouse.containsMouse ? StyleTokens.moduleHover : StyleTokens.cardFill)
                border.width: 1
                border.color: modelData.active ? StyleTokens.accent : StyleTokens.inputBorder

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                Item {
                    anchors.fill: parent
                    anchors.margins: 10

                    // Icon bubble
                    Rectangle {
                        id: outIconBubble
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 34
                        radius: 17
                        color: modelData.active ? StyleTokens.accent : StyleTokens.module

                        Text {
                            anchors.centerIn: parent
                            text: root.getDeviceGlyph(modelData.iconType)
                            color: modelData.active ? StyleTokens.textOnAccent : StyleTokens.textPrimary
                            font.pixelSize: 15
                            font.family: root.iconFontFamily
                        }
                    }

                    // Device Name and Subtitle
                    Column {
                        anchors.left: outIconBubble.right
                        anchors.leftMargin: 10
                        anchors.right: outCheckIcon.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: modelData.name || "Output Device"
                            color: modelData.active ? StyleTokens.textPrimary : StyleTokens.textSecondary
                            font.pixelSize: 12
                            font.family: root.textFontFamily
                            font.weight: modelData.active ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: modelData.description || ""
                            color: StyleTokens.textMuted
                            font.pixelSize: 10
                            font.family: root.textFontFamily
                            elide: Text.ElideRight
                            visible: text.length > 0
                        }
                    }

                    // Active checkmark badge
                    Rectangle {
                        id: outCheckIcon
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 22
                        radius: 11
                        color: modelData.active ? StyleTokens.accent : StyleTokens.transparent
                        border.width: modelData.active ? 0 : 1
                        border.color: StyleTokens.textSubtle

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00c"
                            color: StyleTokens.textOnAccent
                            font.pixelSize: 10
                            font.family: root.iconFontFamily
                            visible: modelData.active
                        }
                    }
                }

                MouseArea {
                    id: outputMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: SystemServices.setAudioOutput(modelData.sinkName, modelData.portName)
                }
            }
        }

        // View 2: Inputs List
        ListView {
            id: inputsList
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: segmentedTabs.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            visible: root.activeTab === "inputs"
            clip: true
            spacing: 8
            model: SystemServices.audioInputs

            delegate: Rectangle {
                id: inputDelegate
                required property var modelData
                width: inputsList.width
                height: 56
                radius: 16
                color: modelData.active
                    ? StyleTokens.withAlpha(StyleTokens.accent, 0.15)
                    : (inputMouse.containsMouse ? StyleTokens.moduleHover : StyleTokens.cardFill)
                border.width: 1
                border.color: modelData.active ? StyleTokens.accent : StyleTokens.inputBorder

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                Item {
                    anchors.fill: parent
                    anchors.margins: 10

                    // Icon bubble
                    Rectangle {
                        id: inIconBubble
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 34
                        radius: 17
                        color: modelData.active ? StyleTokens.accent : StyleTokens.module

                        Text {
                            anchors.centerIn: parent
                            text: root.getDeviceGlyph(modelData.iconType)
                            color: modelData.active ? StyleTokens.textOnAccent : StyleTokens.textPrimary
                            font.pixelSize: 15
                            font.family: root.iconFontFamily
                        }
                    }

                    // Device Name and Subtitle
                    Column {
                        anchors.left: inIconBubble.right
                        anchors.leftMargin: 10
                        anchors.right: inCheckIcon.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: modelData.name || "Microphone"
                            color: modelData.active ? StyleTokens.textPrimary : StyleTokens.textSecondary
                            font.pixelSize: 12
                            font.family: root.textFontFamily
                            font.weight: modelData.active ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: modelData.description || ""
                            color: StyleTokens.textMuted
                            font.pixelSize: 10
                            font.family: root.textFontFamily
                            elide: Text.ElideRight
                            visible: text.length > 0
                        }
                    }

                    // Active checkmark badge
                    Rectangle {
                        id: inCheckIcon
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 22
                        radius: 11
                        color: modelData.active ? StyleTokens.accent : StyleTokens.transparent
                        border.width: modelData.active ? 0 : 1
                        border.color: StyleTokens.textSubtle

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00c"
                            color: StyleTokens.textOnAccent
                            font.pixelSize: 10
                            font.family: root.iconFontFamily
                            visible: modelData.active
                        }
                    }
                }

                MouseArea {
                    id: inputMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: SystemServices.setAudioInput(modelData.sourceName, modelData.portName)
                }
            }
        }

        // View 3: Per-App Volume Mixer
        Item {
            id: appsView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: segmentedTabs.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            visible: root.activeTab === "apps"

            // Empty state
            Item {
                anchors.centerIn: parent
                width: parent.width - 32
                height: 120
                visible: SystemServices.appStreams.length === 0

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "\uf1de"
                        color: StyleTokens.textSubtle
                        font.pixelSize: 28
                        font.family: root.iconFontFamily
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No Active Audio Streams"
                        color: StyleTokens.textPrimary
                        font.pixelSize: 13
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Play media in Firefox, Spotify, or games"
                        color: StyleTokens.textMuted
                        font.pixelSize: 11
                        font.family: root.textFontFamily
                    }
                }
            }

            // Stream list
            ListView {
                id: streamsList
                anchors.fill: parent
                clip: true
                spacing: 8
                model: SystemServices.appStreams
                visible: SystemServices.appStreams.length > 0

                delegate: Rectangle {
                    id: streamDelegate
                    required property var modelData
                    width: streamsList.width
                    height: 72
                    radius: 16
                    color: StyleTokens.cardFill
                    border.width: 1
                    border.color: StyleTokens.inputBorder

                    property real displayedVolume: (modelData && modelData.volume !== undefined) ? modelData.volume : 0.0
                    property real pendingVolume: displayedVolume
                    readonly property bool isDragging: sliderMouse.pressed

                    onModelDataChanged: {
                        if (!isDragging && modelData && modelData.volume !== undefined) {
                            displayedVolume = modelData.volume;
                            pendingVolume = modelData.volume;
                        }
                    }

                    Timer {
                        id: streamVolumeApplyTimer
                        interval: 35
                        repeat: false
                        onTriggered: {
                            if (modelData && modelData.index !== undefined) {
                                SystemServices.setAppStreamVolume(modelData.index, streamDelegate.pendingVolume);
                            }
                        }
                    }

                    function updateVolumeFromMouse(val) {
                        const clamped = Math.max(0.0, Math.min(1.0, val));
                        displayedVolume = clamped;
                        pendingVolume = clamped;
                        streamVolumeApplyTimer.restart();
                    }

                    function commitVolume() {
                        streamVolumeApplyTimer.stop();
                        if (modelData && modelData.index !== undefined) {
                            SystemServices.setAppStreamVolume(modelData.index, streamDelegate.pendingVolume);
                        }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: 10

                        // App icon or music note glyph
                        Rectangle {
                            id: appIconBox
                            anchors.left: parent.left
                            anchors.top: parent.top
                            width: 24
                            height: 24
                            radius: 6
                            color: StyleTokens.module
                            clip: true

                            Image {
                                id: appImg
                                anchors.fill: parent
                                anchors.margins: 2
                                sourceSize: Qt.size(48, 48)
                                source: Quickshell.iconPath(modelData.iconName, true) || ""
                                fillMode: Image.PreserveAspectFit
                                visible: source.toString() !== "" && status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "\uf001"
                                color: StyleTokens.textSecondary
                                font.pixelSize: 12
                                font.family: root.iconFontFamily
                                visible: !appImg.visible
                            }
                        }

                        // App Name
                        Text {
                            anchors.left: appIconBox.right
                            anchors.leftMargin: 8
                            anchors.right: percentLabel.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: appIconBox.verticalCenter
                            text: modelData.name || "Application"
                            color: StyleTokens.textPrimary
                            font.pixelSize: 12
                            font.family: root.textFontFamily
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        // Percentage text
                        Text {
                            id: percentLabel
                            anchors.right: muteButton.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: appIconBox.verticalCenter
                            text: Math.round(streamDelegate.displayedVolume * 100) + "%"
                            color: modelData.muted ? StyleTokens.textMuted : StyleTokens.textSecondary
                            font.pixelSize: 11
                            font.family: root.textFontFamily
                            font.weight: Font.Medium
                        }

                        // Mute button
                        Rectangle {
                            id: muteButton
                            anchors.right: parent.right
                            anchors.verticalCenter: appIconBox.verticalCenter
                            width: 24
                            height: 24
                            radius: 12
                            color: modelData.muted
                                ? StyleTokens.withAlpha(StyleTokens.error, 0.2)
                                : (muteMouse.containsMouse ? StyleTokens.moduleHover : StyleTokens.transparent)

                            Text {
                                anchors.centerIn: parent
                                text: modelData.muted ? "\ueb24" : "\ueb75"
                                color: modelData.muted ? StyleTokens.error : (muteMouse.containsMouse ? StyleTokens.textPrimary : StyleTokens.textSecondary)
                                font.pixelSize: 13
                                font.family: root.iconFontFamily
                            }

                            MouseArea {
                                id: muteMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: SystemServices.toggleAppStreamMute(modelData.index)
                            }
                        }

                        // Volume Slider Track
                        Rectangle {
                            id: appSliderTrack
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 20
                            radius: 10
                            color: StyleTokens.track
                            border.width: 1
                            border.color: StyleTokens.inputBorder
                            clip: true

                            Rectangle {
                                id: appSliderFill
                                width: streamDelegate.displayedVolume <= 0.001
                                    ? 0
                                    : Math.min(appSliderTrack.width, appSliderTrack.width * streamDelegate.displayedVolume)
                                height: parent.height
                                radius: parent.radius
                                color: modelData.muted
                                    ? StyleTokens.withAlpha(StyleTokens.accent, 0.45)
                                    : StyleTokens.accent

                                Behavior on color { ColorAnimation { duration: 140 } }
                            }

                            MouseArea {
                                id: sliderMouse
                                anchors.fill: parent
                                anchors.topMargin: -8
                                anchors.bottomMargin: -8
                                preventStealing: true
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                function updateFromMouse(mouseX) {
                                    const nextVal = Math.max(0.0, Math.min(1.0, mouseX / appSliderTrack.width));
                                    streamDelegate.updateVolumeFromMouse(nextVal);
                                }

                                onPressed: function(mouse) {
                                    updateFromMouse(mouse.x);
                                }
                                onPositionChanged: function(mouse) {
                                    if (pressed) {
                                        updateFromMouse(mouse.x);
                                    }
                                }
                                onReleased: streamDelegate.commitVolume()
                                onCanceled: streamDelegate.commitVolume()

                                onWheel: function(wheel) {
                                    const delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                                    const nextVal = Math.max(0.0, Math.min(1.0, streamDelegate.displayedVolume + delta));
                                    streamDelegate.displayedVolume = nextVal;
                                    streamDelegate.pendingVolume = nextVal;
                                    streamDelegate.commitVolume();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
