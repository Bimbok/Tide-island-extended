import QtQuick
import Quickshell
import IslandBackend
import "../common"

Item {
    id: root

    property var provider: null
    property string panelKind: "audio_output"
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property string heroFontFamily: textFontFamily
    property real presentationProgress: 1

    property string activeTab: panelKind === "audio_input" ? "inputs" : "outputs"

    focus: true

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            if (root.provider && root.provider.setConnectivityPanelOpen) {
                root.provider.setConnectivityPanelOpen(root.panelKind, false);
            }
            event.accepted = true;
        }
    }

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

        // Header
        FlyoutHeader {
            id: headerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            title: "Audio"
            heroFontFamily: root.heroFontFamily
            textFontFamily: root.textFontFamily
            iconFontFamily: root.iconFontFamily

            ActionPill {
                visible: SystemServices.isMultiOutputActive
                text: "Multi-Audio (" + SystemServices.activeOutputCount + ")"
                highlighted: true
                clickable: false
                fontSize: 9
                textFontFamily: root.heroFontFamily
            }

            ActionPill {
                id: eqJumpButton
                text: "EQ"
                icon: "\udb80\udf79"
                iconFontFamily: root.iconFontFamily
                textFontFamily: root.heroFontFamily
                active: SystemServices.equalizerEnabled
                onClicked: {
                    if (root.provider && root.provider.setConnectivityPanelOpen) {
                        root.provider.setConnectivityPanelOpen("equalizer", true);
                    }
                }
            }

            ActionPill {
                visible: SystemServices.appStreams.length > 0
                text: SystemServices.appStreams.length + (SystemServices.appStreams.length === 1 ? " app" : " apps")
                clickable: false
                textFontFamily: root.textFontFamily
            }
        }

        // Segmented Tabs: Outputs | Inputs | Mixer
        SegmentedTabBar {
            id: segmentedTabs
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerRow.bottom
            anchors.topMargin: 12
            iconFontFamily: root.iconFontFamily
            textFontFamily: root.textFontFamily
            currentId: root.activeTab
            model: [
                {
                    id: "outputs",
                    label: "Output",
                    icon: "\udb81\udcc3",
                    badge: SystemServices.isMultiOutputActive ? "(" + SystemServices.activeOutputCount + ")" : ""
                },
                {
                    id: "inputs",
                    label: "Input",
                    icon: "\uf130",
                    badge: ""
                },
                {
                    id: "apps",
                    label: "Mixer",
                    icon: "\uf1de",
                    badge: ""
                }
            ]
            onTabSelected: (tabId) => root.activeTab = tabId
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

            delegate: PanelItemCard {
                id: outputDelegate
                required property var modelData
                width: outputsList.width
                height: modelData.active ? 98 : 56
                active: modelData.active
                title: modelData.name || "Output Device"
                subtitle: modelData.description || ""
                iconText: root.getDeviceGlyph(modelData.iconType)
                iconFontFamily: root.iconFontFamily
                textFontFamily: root.textFontFamily

                onClicked: {
                    if (SystemServices.isMultiOutputActive) {
                        SystemServices.toggleAudioOutput(modelData.sinkName, modelData.portName);
                    } else {
                        SystemServices.setAudioOutput(modelData.sinkName, modelData.portName);
                    }
                }

                rightAccessory: [
                    Rectangle {
                        id: outCheckIcon
                        width: 24
                        height: 24
                        radius: 12
                        color: modelData.active ? StyleTokens.accent : StyleTokens.transparent
                        border.width: modelData.active ? 0 : 1
                        border.color: checkMouse.containsMouse ? StyleTokens.accent : StyleTokens.textSubtle
                        scale: checkMouse.containsMouse ? 1.15 : 1.0

                        Behavior on scale { NumberAnimation { duration: 120 } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf00c"
                            color: StyleTokens.textOnAccent
                            font.pixelSize: 10
                            font.family: root.iconFontFamily
                            visible: modelData.active
                        }

                        MouseArea {
                            id: checkMouse
                            anchors.fill: parent
                            anchors.margins: -10
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            preventStealing: true
                            onClicked: (mouse) => {
                                SystemServices.toggleAudioOutput(modelData.sinkName, modelData.portName);
                                mouse.accepted = true;
                            }
                        }
                    }
                ]

                // Bottom Row: Expandable Individual Volume Slider
                Item {
                    id: volumeControlRow
                    anchors.fill: parent
                    visible: opacity > 0.01
                    opacity: modelData.active ? 1.0 : 0.0

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    // Mute / Speaker toggle button
                    Rectangle {
                        id: devMuteBtn
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        radius: 12
                        color: devMuteMouse.containsMouse ? StyleTokens.moduleHover : StyleTokens.transparent

                        Text {
                            anchors.centerIn: parent
                            text: modelData.muted ? "\uf6a9" : ((modelData.volume || 1.0) > 0.6 ? "\uf028" : ((modelData.volume || 1.0) > 0.2 ? "\uf027" : "\uf026"))
                            font.pixelSize: 11
                            font.family: root.iconFontFamily
                            color: modelData.muted ? StyleTokens.danger : StyleTokens.accent
                        }

                        MouseArea {
                            id: devMuteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            preventStealing: true
                            onClicked: (mouse) => {
                                SystemServices.toggleDeviceMute(modelData.sinkName, modelData.portName);
                                mouse.accepted = true;
                            }
                        }
                    }

                    // Interactive Slider Capsule
                    CapsuleSlider {
                        id: devSlider
                        anchors.left: devMuteBtn.right
                        anchors.leftMargin: 8
                        anchors.right: devVolLabel.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        height: 24
                        normalHeight: 7
                        hoverHeight: 13
                        value: modelData.volume !== undefined ? modelData.volume : 1.0
                        muted: modelData.muted || false
                        onMoved: (val) => {
                            SystemServices.setDeviceVolume(modelData.sinkName, val, modelData.portName);
                        }
                        onCommitted: (val) => {
                            SystemServices.setDeviceVolume(modelData.sinkName, val, modelData.portName);
                        }
                    }

                    // Percentage Label
                    Text {
                        id: devVolLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.muted ? "Muted" : Math.round((devSlider.isDragging ? devSlider.internalValue : (modelData.volume !== undefined ? modelData.volume : 1.0)) * 100) + "%"
                        color: modelData.muted ? StyleTokens.danger : (devSlider.isHovered ? StyleTokens.textPrimary : StyleTokens.textSecondary)
                        font.pixelSize: 10
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignRight
                        width: 38
                    }
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

            delegate: PanelItemCard {
                id: inputDelegate
                required property var modelData
                width: inputsList.width
                height: 56
                active: modelData.active
                title: modelData.name || "Microphone"
                subtitle: modelData.description || ""
                iconText: root.getDeviceGlyph(modelData.iconType)
                iconFontFamily: root.iconFontFamily
                textFontFamily: root.textFontFamily

                onClicked: SystemServices.setAudioInput(modelData.sourceName, modelData.portName)

                rightAccessory: [
                    Rectangle {
                        id: inCheckIcon
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
                ]
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
                    readonly property bool isDragging: appSlider.isDragging

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
                        CapsuleSlider {
                            id: appSlider
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 24
                            normalHeight: 8
                            hoverHeight: 14
                            value: streamDelegate.displayedVolume
                            muted: modelData.muted || false
                            onMoved: (val) => streamDelegate.updateVolumeFromMouse(val)
                            onCommitted: (val) => streamDelegate.commitVolume()
                        }
                    }
                }
            }
        }
    }
}
