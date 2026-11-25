import QtQuick
import Quickshell
import IslandBackend

Rectangle {
    id: root

    property color cardAccent: StyleTokens.accent
    property real cardRadius: StyleTokens.radiusModule
    property color cardBackgroundColor: StyleTokens.clearBlack
    property color cardBorderColor: StyleTokens.transparent
    property real cardBorderWidth: 0
    property bool useMatteSurface: true
    property string textFontFamily: UserConfig ? UserConfig.textFontFamily : ""
    property string iconFontFamily: UserConfig ? UserConfig.iconFontFamily : ""
    property real modeSlotWidth: 44
    property bool showHeader: true
    property bool showConservationBadge: true
    property bool interactive: true
    property string titleText: "Battery"

    // Driver and control state
    readonly property var userConfig: UserConfig
    readonly property string powerDriver: {
        const d = (userConfig && userConfig.powerProfileDriver) ? String(userConfig.powerProfileDriver).trim() : "";
        return d.length > 0 ? d : "auto";
    }
    readonly property bool tlpControlsEnabled: {
        if (powerDriver === "disabled" || powerDriver === "none") return false;
        if (powerDriver === "powerprofilesctl") return true;
        if (powerDriver === "tlp") return userConfig && String(userConfig.tlpPermissionMode).trim() !== "skip";
        return true;
    }

    // State properties
    property bool batteryTlpChecked: false
    property bool batteryTlpAvailable: true
    property bool batteryModeBusy: false
    property bool batteryModeStateRunning: false
    property bool batteryModeSetterRunning: false
    property bool batteryModeSliderDragging: false
    property int batteryModeIndex: 1
    property int batteryModeAppliedIndex: 1
    property int batteryModePendingIndex: 1
    property real batteryModeDragOffset: 0
    property string batteryModeInfoMessage: ""
    property string batteryModeError: ""
    property string batteryModeLastCommandOutput: ""

    readonly property var batteryModeGlyphs: ["\uf06c", "\uf242", "\uf0e7"]
    readonly property var batteryModeNames: ["Power Saver", "Balanced", "Performance"]
    readonly property var batteryModeCmds: ["power-saver", "balanced", "performance"]

    readonly property string currentModeName: batteryModeNames[Math.max(0, Math.min(2, batteryModeIndex))]
    readonly property string currentModeCommand: batteryModeCmds[Math.max(0, Math.min(2, batteryModeIndex))]
    readonly property string batteryModeStatusText: {
        if (!tlpControlsEnabled) return "Disabled";
        if (!batteryTlpAvailable && batteryTlpChecked) return "Unavailable";
        if (batteryModeBusy) return "Applying " + batteryModeNames[Math.max(0, Math.min(2, batteryModePendingIndex))] + "...";
        return batteryModeNames[Math.max(0, Math.min(2, batteryModeIndex))];
    }

    signal modeSelected(int index, string command)

    radius: cardRadius
    color: cardBackgroundColor
    border.color: cardBorderColor
    border.width: cardBorderWidth
    clip: true

    function trimString(value) {
        if (value === undefined || value === null) return "";
        return String(value).trim();
    }

    function batteryModeLabel(index) {
        if (index <= 0) return "Power Saver";
        if (index >= 2) return "Performance";
        return "Balanced";
    }

    function batteryModeCommand(index) {
        if (index <= 0) return "power-saver";
        if (index >= 2) return "performance";
        return "balanced";
    }

    function batteryModeIndexForCommand(command) {
        const normalized = trimString(command).toLowerCase();
        if (normalized === "power-saver" || normalized === "bat") return 0;
        if (normalized === "performance" || normalized === "ac") return 2;
        return 1;
    }

    function setBatteryModeVisualIndex(index, animate) {
        const nextIndex = Math.max(0, Math.min(2, index));
        batteryModeIndex = nextIndex;
    }

    function refreshBatteryModeState() {
        if (batteryModeStateRunning || typeof SystemServices === "undefined" || !SystemServices)
            return;

        batteryModeStateRunning = true;
        SystemServices.requestPowerProfileState(powerDriver);
    }

    function applyBatteryModeState(available, profile, output, errorString) {
        batteryModeStateRunning = false;
        batteryTlpChecked = true;
        batteryTlpAvailable = !!available;

        if (!batteryTlpAvailable) {
            batteryModeBusy = false;
            batteryModeError = trimString(errorString).length > 0 ? errorString : "Power service not available.";
            setBatteryModeVisualIndex(batteryModeAppliedIndex, true);
            return;
        }

        if (batteryModeError === "TLP is not installed." || batteryModeError === "Power service not available.")
            batteryModeError = "";

        let resolvedProfile = trimString(profile);
        if (resolvedProfile.length === 0) {
            const profileMatch = String(output || "").match(/TLP profile\s*=\s*([a-z-]+)/i);
            if (profileMatch)
                resolvedProfile = profileMatch[1];
        }

        if (resolvedProfile.length > 0) {
            const nextIndex = batteryModeIndexForCommand(resolvedProfile);
            batteryModeAppliedIndex = nextIndex;
            if (!batteryModeBusy) {
                batteryModePendingIndex = nextIndex;
                setBatteryModeVisualIndex(nextIndex, true);
            }
        }
    }

    function rollbackBatteryMode(message) {
        batteryModeBusy = false;
        batteryModeError = message;
        batteryModeInfoMessage = "";
        batteryModeDragOffset = 0;
        setBatteryModeVisualIndex(batteryModeAppliedIndex, true);
    }

    function classifyBatteryModeFailure(exitCode) {
        const details = trimString(batteryModeLastCommandOutput).toLowerCase();

        if (details.indexOf("powerprofilesctl") >= 0)
            return "powerprofilesctl failed to set profile.";
        if (details.indexOf("sorry, try again") >= 0 || details.indexOf("incorrect password attempt") >= 0)
            return "The configured sudo password did not work.";
        if (details.indexOf("pkexec") >= 0 && details.indexOf("not installed") >= 0)
            return "Install pkexec or set tlpSudoPassword in userconfig.json.";
        if (details.indexOf("sudo is not installed") >= 0)
            return "sudo is not installed.";
        if (details.indexOf("sudo:") >= 0 && details.indexOf("password") >= 0) {
            if (userConfig && trimString(userConfig.tlpPermissionMode) === "ask")
                return "Install pkexec or set tlpSudoPassword in userconfig.json.";
            return "sudo needs a password; set tlpSudoPassword in userconfig.json.";
        }
        if (details.indexOf("sudo:") >= 0 && details.indexOf("no new privileges") >= 0)
            return "sudo is blocked by the current process security flags.";
        if (details.indexOf("sudo:") >= 0 && details.indexOf("a terminal is required") >= 0)
            return "sudo needs a real terminal, but the panel could not open one.";
        if (details.indexOf("missing root privilege") >= 0)
            return "Power service needs admin permission.";
        if (details.indexOf("command not found") >= 0 || details.indexOf("not found") >= 0) {
            if (details.indexOf("tlp") >= 0)
                return "TLP is not installed.";
            if (details.indexOf("powerprofilesctl") >= 0)
                return "powerprofilesctl is not installed.";
        }

        if (exitCode === 127)
            return "Power service command not found.";
        if (exitCode === 126)
            return "Authentication required to apply mode.";
        return "Could not apply power mode.";
    }

    function selectBatteryMode(index) {
        if (typeof SystemServices === "undefined" || !SystemServices) return;

        if (batteryModeBusy) {
            if (batteryModeSetterRunning)
                SystemServices.cancelPowerProfileApply();
            batteryModeBusy = false;
            batteryModeSetterRunning = false;
        }

        const nextIndex = Math.max(0, Math.min(2, index));

        if (!tlpControlsEnabled) {
            rollbackBatteryMode("Power mode switching is disabled in userconfig.json.");
            return;
        }

        if (!batteryTlpChecked) {
            refreshBatteryModeState();
            rollbackBatteryMode("Checking power service. Try again in a moment.");
            return;
        }

        if (!batteryTlpAvailable) {
            rollbackBatteryMode(batteryModeError.length > 0 ? batteryModeError : "Power service not available.");
            return;
        }

        if (nextIndex === batteryModeAppliedIndex) {
            batteryModeError = "";
            batteryModeInfoMessage = batteryModeLabel(nextIndex) + " active.";
            setBatteryModeVisualIndex(nextIndex, true);
            return;
        }

        batteryModePendingIndex = nextIndex;
        batteryModeBusy = true;
        batteryModeSetterRunning = true;
        batteryModeError = "";
        batteryModeInfoMessage = "Applying " + batteryModeLabel(nextIndex) + "...";
        setBatteryModeVisualIndex(nextIndex, true);
        batteryModeLastCommandOutput = "";
        const permissionMode = userConfig ? trimString(userConfig.tlpPermissionMode) : "";
        const sudoPassword = permissionMode === "password" && userConfig
            ? userConfig.tlpSudoPassword
            : "";
        SystemServices.setPowerProfileMode(powerDriver, batteryModeCommand(nextIndex), sudoPassword, permissionMode === "ask");
        root.modeSelected(nextIndex, batteryModeCommand(nextIndex));
    }

    function selectModeByCommand(cmd) {
        selectBatteryMode(batteryModeIndexForCommand(cmd));
    }

    function cycleNextMode() {
        selectBatteryMode((batteryModeAppliedIndex + 1) % 3);
    }

    function cyclePreviousMode() {
        selectBatteryMode((batteryModeAppliedIndex + 2) % 3);
    }

    function finishBatteryModeApply(success, exitCode, output, errorString) {
        batteryModeSetterRunning = false;
        batteryModeBusy = false;
        batteryModeLastCommandOutput = trimString(output);
        if (batteryModeLastCommandOutput.length === 0)
            batteryModeLastCommandOutput = trimString(errorString);

        if (!success) {
            rollbackBatteryMode(classifyBatteryModeFailure(exitCode));
            return;
        }

        batteryModeAppliedIndex = batteryModePendingIndex;
        batteryModeError = "";
        batteryModeInfoMessage = batteryModeLabel(batteryModeAppliedIndex) + " active.";
        setBatteryModeVisualIndex(batteryModeAppliedIndex, true);
        refreshBatteryModeState();
    }

    Connections {
        target: typeof SystemServices !== "undefined" ? SystemServices : null

        function onTlpStateReady(available, profile, output, errorString) {
            root.applyBatteryModeState(available, profile, output, errorString);
        }

        function onTlpSetFinished(success, exitCode, output, errorString) {
            root.finishBatteryModeApply(success, exitCode, output, errorString);
        }
    }

    Component.onCompleted: {
        if (root.visible && root.tlpControlsEnabled)
            root.refreshBatteryModeState();
    }

    onVisibleChanged: {
        if (root.visible && root.tlpControlsEnabled && !root.batteryTlpChecked)
            root.refreshBatteryModeState();
    }

    // Specular highlight gradient reflection
    Rectangle {
        anchors.fill: parent
        radius: root.cardRadius
        color: StyleTokens.transparent
        visible: root.useMatteSurface
        gradient: Gradient {
            GradientStop { position: 0; color: "#08ffffff" }
            GradientStop { position: 0.45; color: "#01ffffff" }
            GradientStop { position: 1; color: "#02000000" }
        }
        antialiasing: true
    }

    // Header Row: Title + Conservation Badge + Status Text
    Item {
        id: headerRow
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.top: parent.top
        anchors.topMargin: 11
        height: 18
        visible: root.showHeader

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                text: root.titleText
                color: StyleTokens.textPrimary
                font.pixelSize: 13
                font.family: root.textFontFamily
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                visible: root.showConservationBadge && typeof SystemServices !== "undefined" && SystemServices && SystemServices.batteryConservationMode
                width: capBadgeText.implicitWidth + 8
                height: 15
                radius: 7
                color: StyleTokens.moduleHover
                border.color: root.cardAccent
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    id: capBadgeText
                    anchors.centerIn: parent
                    text: "80%"
                    color: root.cardAccent
                    font.pixelSize: 9
                    font.family: root.textFontFamily
                    font.weight: Font.DemiBold
                }
            }
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - 90)
            text: root.batteryModeError.length > 0
                ? root.batteryModeError
                : (root.batteryModeInfoMessage.length > 0
                    ? root.batteryModeInfoMessage
                    : root.batteryModeStatusText)
            color: root.batteryModeError.length > 0 ? StyleTokens.error : StyleTokens.textMuted
            horizontalAlignment: Text.AlignRight
            font.pixelSize: 9
            font.family: root.textFontFamily
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
    }

    // Bottom Mode Carousel
    Item {
        id: batteryModeCarousel
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 24, root.modeSlotWidth * 4)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        height: 34
        clip: true

        Item {
            id: batteryModeItems
            width: root.modeSlotWidth * 3
            height: parent.height
            x: batteryModeCarousel.width / 2
                - root.modeSlotWidth / 2
                - root.batteryModeIndex * root.modeSlotWidth
                + root.batteryModeDragOffset

            Behavior on x {
                enabled: !root.batteryModeSliderDragging

                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }

            Repeater {
                model: 3

                delegate: Item {
                    x: index * root.modeSlotWidth
                    width: root.modeSlotWidth
                    height: batteryModeCarousel.height
                    opacity: index === root.batteryModeIndex ? 1 : 0.42

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: index === root.batteryModeIndex ? 32 : 28
                        height: index === root.batteryModeIndex ? 28 : 24
                        radius: 12
                        color: index === root.batteryModeIndex ? root.cardAccent : StyleTokens.track

                        Behavior on width {
                            NumberAnimation {
                                duration: 140
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on height {
                            NumberAnimation {
                                duration: 140
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 140
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.batteryModeGlyphs[index]
                            color: index === root.batteryModeIndex ? StyleTokens.textOnAccent : StyleTokens.textDim
                            font.pixelSize: index === root.batteryModeIndex ? 15 : 13
                            font.family: root.iconFontFamily
                        }
                    }
                }
            }
        }

        // Active indicator underline bar
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: 22
            height: 2
            radius: 1
            color: root.cardAccent
            opacity: 0.75
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.interactive
            hoverEnabled: root.interactive
            cursorShape: Qt.PointingHandCursor
            property real startX: 0
            property int startIndex: 1
            property bool moved: false

            function clampDrag(delta) {
                return Math.max(-root.modeSlotWidth, Math.min(root.modeSlotWidth, delta));
            }

            onPressed: function(mouse) {
                startX = mouse.x;
                startIndex = root.batteryModeIndex;
                moved = false;
                root.batteryModeInfoMessage = "";
                root.batteryModeError = "";
                root.batteryModeSliderDragging = true;
                root.batteryModeDragOffset = 0;
            }

            onPositionChanged: function(mouse) {
                if (!pressed)
                    return;

                const delta = mouse.x - startX;
                if (!moved && Math.abs(delta) < 4)
                    return;

                moved = true;
                root.batteryModeDragOffset = clampDrag(delta);
            }

            onReleased: function(mouse) {
                const delta = mouse.x - startX;
                let nextIndex = startIndex;

                if (moved && Math.abs(delta) >= 18) {
                    if (delta <= -18)
                        nextIndex = Math.min(2, startIndex + 1);
                    else if (delta >= 18)
                        nextIndex = Math.max(0, startIndex - 1);
                } else {
                    const offsetFromCenter = mouse.x - width / 2;
                    const slotDiff = Math.round(offsetFromCenter / root.modeSlotWidth);
                    nextIndex = Math.max(0, Math.min(2, startIndex + slotDiff));
                }

                root.batteryModeSliderDragging = false;
                root.batteryModeDragOffset = 0;
                root.selectBatteryMode(nextIndex);
            }

            onCanceled: {
                root.batteryModeSliderDragging = false;
                root.batteryModeDragOffset = 0;
                root.setBatteryModeVisualIndex(root.batteryModeAppliedIndex, true);
            }
        }
    }
}
