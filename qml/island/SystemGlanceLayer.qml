pragma ComponentBehavior: Bound

import QtQuick
import IslandBackend
import Quickshell.Widgets

FocusScope {
    id: root

    property bool showCondition: false
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property string heroFontFamily: ""
    property int batteryCapacity: 100
    property bool isCharging: false

    signal closeRequested()
    signal openCalendarRequested()
    signal openWeatherRequested()

    readonly property real contentHeight: mainCol.implicitHeight + 28

    focus: root.showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    anchors.margins: 14
    opacity: showCondition ? 1 : 0
    visible: opacity > 0.01

    Behavior on opacity {
        NumberAnimation {
            duration: root.showCondition ? StyleTokens.durationStandard : StyleTokens.durationFast
            easing.type: Easing.InOutQuad
        }
    }

    onShowConditionChanged: {
        if (showCondition) {
            forceActiveFocus();
            SystemGlance.checkUpdatesAsync();
        }
    }

    Keys.onEscapePressed: function(event) {
        root.closeRequested();
        event.accepted = true;
    }

    // Activate the on-demand system glance sampler ONLY when this layer is visible
    Binding {
        target: SystemGlance
        property: "active"
        value: root.showCondition
    }

    Column {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 10

        // ==========================================
        // 1. Top Identity / Profile Header
        // ==========================================
        Item {
            id: headerItem
            width: parent.width
            height: 40
            z: 100

            Item {
                id: userProfileContainer
                anchors.left: parent.left
                anchors.right: updatesBadge.visible ? updatesBadge.left : batteryBadge.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 38
                clip: true

                // Avatar / Monogram (True circular clipping via ClippingRectangle)
                ClippingRectangle {
                    id: avatarContainer
                    width: 38
                    height: 38
                    radius: 19
                    color: StyleTokens.cardFillActive
                    border.width: 1
                    border.color: avatarHover.containsMouse ? StyleTokens.accent : StyleTokens.inputBorder
                    antialiasing: true
                    contentUnderBorder: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        id: avatarImg
                        anchors.fill: parent
                        visible: (SystemGlance.avatarPath || "") !== "" && status === Image.Ready
                        source: {
                            const p = SystemGlance.avatarPath || "";
                            if (!p) return "";
                            if (p.startsWith("/") && !p.startsWith("file://"))
                                return "file://" + p;
                            return p;
                        }
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        mipmap: true
                        asynchronous: false
                        sourceSize: Qt.size(96, 96)
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: (SystemGlance.avatarPath || "") === "" || avatarImg.status !== Image.Ready
                        text: (SystemGlance.userName && SystemGlance.userName.length > 0)
                            ? SystemGlance.userName.charAt(0).toUpperCase()
                            : "U"
                        color: StyleTokens.accent
                        font.family: root.heroFontFamily
                        font.pixelSize: 16
                        font.weight: Font.Bold
                    }

                    // Hover hint overlay
                    Rectangle {
                        anchors.fill: parent
                        radius: 19
                        color: Qt.rgba(0, 0, 0, 0.4)
                        opacity: avatarHover.containsMouse ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf030" // Camera icon
                            font.family: root.iconFontFamily
                            font.pixelSize: 13
                            color: "#ffffff"
                        }
                    }

                    MouseArea {
                        id: avatarHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SystemGlance.openAvatarDirectory()
                    }

                    DropArea {
                        anchors.fill: parent
                        onDropped: (drop) => {
                            let path = "";
                            if (drop.hasUrls && drop.urls.length > 0) {
                                path = drop.urls[0].toString();
                            } else if (drop.hasText) {
                                path = drop.text.trim();
                            }
                            if (path !== "") {
                                if (path.startsWith("file://")) {
                                    path = path.substring(7);
                                }
                                SystemGlance.setAvatarPath(path);
                            }
                        }
                    }
                }

                // User details
                Column {
                    anchors.left: avatarContainer.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Row {
                        width: parent.width
                        spacing: 4

                        Text {
                            id: userNameText
                            text: SystemGlance.userName || "User"
                            color: StyleTokens.textPrimaryBright
                            font.family: root.heroFontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }

                        Text {
                            text: "@" + (SystemGlance.hostName || "linux")
                            color: StyleTokens.textSecondary
                            font.family: root.textFontFamily
                            font.pixelSize: 11
                            anchors.baseline: userNameText.baseline
                            width: Math.max(0, parent.width - userNameText.implicitWidth - 4)
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 6

                        Text {
                            id: uptimeText
                            text: "\uf017 " + (SystemGlance.uptimeText || "0m")
                            color: StyleTokens.textMuted
                            font.family: root.iconFontFamily
                            font.pixelSize: 10
                        }

                        Text {
                            id: uptimeDot
                            text: "•"
                            color: StyleTokens.textMuted
                            font.pixelSize: 8
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: SystemGlance.osName || "Linux"
                            color: StyleTokens.textMuted
                            font.family: root.textFontFamily
                            font.pixelSize: 10
                            width: Math.max(0, parent.width - uptimeText.implicitWidth - uptimeDot.implicitWidth - 12)
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Updates Badge (Interactive)
            Rectangle {
                id: updatesBadge
                visible: (SystemGlance.pendingUpdatesCount || 0) > 0
                anchors.right: batteryBadge.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 26
                width: updatesContentRow.implicitWidth + 16
                radius: 13
                color: updatesHover.containsMouse ? StyleTokens.cardFillHover : StyleTokens.cardFill
                border.width: 1
                border.color: updatesHover.containsMouse ? StyleTokens.accent : StyleTokens.inputBorder

                Behavior on border.color { ColorAnimation { duration: 150 } }
                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    id: updatesContentRow
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf1b2" // package cube
                        font.family: root.iconFontFamily
                        font.pixelSize: 10
                        color: StyleTokens.accent
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: SystemGlance.pendingUpdatesCount + (SystemGlance.pendingUpdatesCount === 1 ? " update" : " updates")
                        font.family: root.heroFontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: StyleTokens.accent
                    }
                }

                MouseArea {
                    id: updatesHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            SystemGlance.checkUpdatesAsync(true);
                        } else {
                            SystemGlance.launchUpdateTerminal();
                        }
                    }
                }
            }

            // Right side: Rich Battery Badge
            Rectangle {
                id: batteryBadge
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 26
                width: batteryContentRow.implicitWidth + 16
                radius: 13
                color: batteryHover.containsMouse ? StyleTokens.cardFillHover : StyleTokens.cardFill
                border.width: 1
                border.color: batteryHover.containsMouse ? StyleTokens.accent : StyleTokens.inputBorder

                Behavior on border.color { ColorAnimation { duration: 150 } }
                Behavior on color { ColorAnimation { duration: 150 } }

                readonly property int effectiveCap: SystemGlance.hasBattery ? SystemGlance.batteryCapacity : root.batteryCapacity
                readonly property bool effectiveCharging: root.isCharging || (SystemGlance.batteryStatus === "Charging")
                readonly property bool isConservation: SystemGlance.batteryConservationActive || (SystemServices.batteryConservationMode ?? false)
                readonly property int effectiveHealth: SystemGlance.batteryHealthPercent > 0 ? SystemGlance.batteryHealthPercent : (SystemServices.batteryHealthPercent || 100)

                Row {
                    id: batteryContentRow
                    anchors.centerIn: parent
                    spacing: 5

                    // Battery Icon
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (batteryBadge.effectiveCharging) return "\uf0e7"; // Bolt
                            const c = batteryBadge.effectiveCap;
                            if (c >= 85) return "\uf240"; // Full
                            if (c >= 60) return "\uf241"; // 3/4
                            if (c >= 35) return "\uf242"; // 1/2
                            if (c >= 15) return "\uf243"; // 1/4
                            return "\uf244"; // Empty
                        }
                        font.family: root.iconFontFamily
                        font.pixelSize: 11
                        color: {
                            if (batteryBadge.effectiveCharging) return StyleTokens.success;
                            if (batteryBadge.effectiveCap <= 20) return StyleTokens.danger;
                            if (batteryBadge.effectiveCap <= 40) return StyleTokens.warning;
                            return StyleTokens.accent;
                        }
                    }

                    // Main Capacity %
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: batteryBadge.effectiveCap + "%"
                        font.family: root.textFontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: StyleTokens.textPrimaryBright
                    }

                    // Separator
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "•"
                        font.family: root.textFontFamily
                        font.pixelSize: 8
                        color: StyleTokens.textMuted
                    }

                    // Secondary info: Rate (e.g. +14.2W / -8.5W / 80% Cap / Plugged In)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (batteryBadge.isConservation && !batteryBadge.effectiveCharging)
                                return "Capped";
                            if (SystemGlance.batteryRateText && SystemGlance.batteryRateText !== "" && SystemGlance.batteryRateText !== "0.0 W")
                                return SystemGlance.batteryRateText;
                            if (batteryBadge.effectiveCharging)
                                return "Charging";
                            return "Plugged In";
                        }
                        font.family: root.textFontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: batteryBadge.isConservation ? StyleTokens.accent : StyleTokens.textSecondary
                    }

                    // Separator
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "•"
                        font.family: root.textFontFamily
                        font.pixelSize: 8
                        color: StyleTokens.textMuted
                    }

                    // Battery Health
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: batteryBadge.effectiveHealth + "% Health"
                        font.family: root.textFontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: StyleTokens.textSecondary
                    }
                }

                MouseArea {
                    id: batteryHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }

                // Tooltip on Hover showing Full Battery Analytics
                Rectangle {
                    id: batteryTooltip
                    anchors.top: parent.bottom
                    anchors.topMargin: 6
                    anchors.right: parent.right
                    width: tooltipCol.implicitWidth + 20
                    height: tooltipCol.implicitHeight + 14
                    radius: 8
                    color: Qt.rgba(0.08, 0.08, 0.1, 0.95)
                    border.width: 1
                    border.color: StyleTokens.inputBorder
                    opacity: batteryHover.containsMouse ? 1 : 0
                    visible: opacity > 0
                    z: 9999

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    Column {
                        id: tooltipCol
                        anchors.centerIn: parent
                        spacing: 3

                        Text {
                            text: "Battery Telemetry"
                            font.family: root.textFontFamily
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: StyleTokens.accent
                        }

                        Text {
                            text: "Status: " + (SystemGlance.batteryStatus || (batteryBadge.effectiveCharging ? "Charging" : "Discharging"))
                            font.family: root.textFontFamily
                            font.pixelSize: 9
                            color: StyleTokens.textPrimaryBright
                        }

                        Text {
                            text: "Health: " + batteryBadge.effectiveHealth + "% (" + (SystemGlance.batteryCycleCount > 0 ? (SystemGlance.batteryCycleCount + " cycles") : "Good") + ")"
                            font.family: root.textFontFamily
                            font.pixelSize: 9
                            color: StyleTokens.textPrimaryBright
                        }

                        Text {
                            visible: SystemGlance.batteryPowerWatts > 0.05
                            text: "Power Rate: " + SystemGlance.batteryPowerWatts.toFixed(1) + " W"
                            font.family: root.textFontFamily
                            font.pixelSize: 9
                            color: StyleTokens.textMuted
                        }

                        Text {
                            visible: batteryBadge.isConservation
                            text: "Conservation Mode: Active (80% Cap)"
                            font.family: root.textFontFamily
                            font.pixelSize: 9
                            color: StyleTokens.accent
                        }
                    }
                }
            }
        }

        // ==========================================
        // 2. 2x2 Metric Cards Grid
        // ==========================================
        Grid {
            id: metricGrid
            width: parent.width
            columns: 2
            spacing: 8

            // --------------------
            // Card 1: CPU Card
            // --------------------
            Rectangle {
                width: Math.floor((metricGrid.width - metricGrid.spacing) / 2)
                height: 76
                radius: 14
                color: StyleTokens.cardFill
                border.width: 1
                border.color: StyleTokens.inputBorder

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 18

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                text: "\uf2db"
                                font.family: root.iconFontFamily
                                font.pixelSize: 11
                                color: StyleTokens.accent
                            }

                            Text {
                                text: "CPU"
                                font.family: root.heroFontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: StyleTokens.textPrimaryBright
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 18
                            width: cpuTempText.implicitWidth + 10
                            radius: 9
                            color: StyleTokens.withAlpha(
                                (SystemGlance.cpuTemperature || 0) >= 80 ? StyleTokens.danger
                                : ((SystemGlance.cpuTemperature || 0) >= 65 ? StyleTokens.warning : StyleTokens.success),
                                0.18
                            )

                            Text {
                                id: cpuTempText
                                anchors.centerIn: parent
                                text: (SystemGlance.cpuTemperature || 0) + "°C"
                                font.family: root.textFontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: (SystemGlance.cpuTemperature || 0) >= 80 ? StyleTokens.danger
                                    : ((SystemGlance.cpuTemperature || 0) >= 65 ? StyleTokens.warning : StyleTokens.success)
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: Math.round(SystemGlance.cpuUsage || 0) + "%"
                            font.family: root.heroFontFamily
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: StyleTokens.textPrimaryBright
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: SystemGlance.cpuModel || "Processor"
                            font.family: root.textFontFamily
                            font.pixelSize: 10
                            color: StyleTokens.textSecondary
                            elide: Text.ElideRight
                            width: parent.width - 55
                        }
                    }

                    // Progress Bar
                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: StyleTokens.cardFillHover

                        Rectangle {
                            height: parent.height
                            radius: 2
                            width: Math.max(4, parent.width * Math.min(1.0, (SystemGlance.cpuUsage || 0) / 100.0))
                            color: (SystemGlance.cpuUsage || 0) >= 85 ? StyleTokens.danger
                                : ((SystemGlance.cpuUsage || 0) >= 60 ? StyleTokens.warning : StyleTokens.accent)

                            Behavior on width {
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }
            }

            // --------------------
            // Card 2: Memory (RAM) Card
            // --------------------
            Rectangle {
                width: Math.floor((metricGrid.width - metricGrid.spacing) / 2)
                height: 76
                radius: 14
                color: StyleTokens.cardFill
                border.width: 1
                border.color: StyleTokens.inputBorder

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 18

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                text: "\uf538"
                                font.family: root.iconFontFamily
                                font.pixelSize: 11
                                color: "#af52de"
                            }

                            Text {
                                text: "Memory"
                                font.family: root.heroFontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: StyleTokens.textPrimaryBright
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 18
                            width: memPercentText.implicitWidth + 10
                            radius: 9
                            color: StyleTokens.withAlpha("#af52de", 0.18)

                            Text {
                                id: memPercentText
                                anchors.centerIn: parent
                                text: Math.round(SystemGlance.memoryUsagePercent || 0) + "%"
                                font.family: root.textFontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: "#af52de"
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 18

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: SystemGlance.memoryText || "0 / 0 GB"
                            font.family: root.heroFontFamily
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: StyleTokens.textPrimaryBright
                        }

                        Text {
                            visible: !!SystemGlance.hasSwap
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Swap " + Math.round(SystemGlance.swapUsagePercent || 0) + "%"
                            font.family: root.textFontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: StyleTokens.textSecondary
                        }
                    }

                    // Progress Bar
                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: StyleTokens.cardFillHover

                        Rectangle {
                            height: parent.height
                            radius: 2
                            width: Math.max(4, parent.width * Math.min(1.0, (SystemGlance.memoryUsagePercent || 0) / 100.0))
                            color: "#af52de"

                            Behavior on width {
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }
            }

            // --------------------
            // Card 3: Network Throughput Card
            // --------------------
            Rectangle {
                width: Math.floor((metricGrid.width - metricGrid.spacing) / 2)
                height: 76
                radius: 14
                color: StyleTokens.cardFill
                border.width: 1
                border.color: StyleTokens.inputBorder

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 5

                    Item {
                        width: parent.width
                        height: 18

                        Row {
                            anchors.left: parent.left
                            anchors.right: vpnBadge.visible ? vpnBadge.left : parent.right
                            anchors.rightMargin: vpnBadge.visible ? 6 : 0
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                text: "\uf1eb"
                                font.family: root.iconFontFamily
                                font.pixelSize: 11
                                color: "#0a84ff"
                            }

                            Text {
                                text: SystemGlance.networkInterface || "Offline"
                                font.family: root.heroFontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: StyleTokens.textPrimaryBright
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, parent.width - 20)
                            }
                        }

                        Rectangle {
                            id: vpnBadge
                            visible: !!SystemGlance.vpnActive
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 18
                            width: vpnText.implicitWidth + 10
                            radius: 9
                            color: StyleTokens.withAlpha(StyleTokens.success, 0.18)

                            Text {
                                id: vpnText
                                anchors.centerIn: parent
                                text: "VPN"
                                font.family: root.textFontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: StyleTokens.success
                            }
                        }
                    }

                    // Speeds row
                    Row {
                        width: parent.width
                        spacing: 12

                        Row {
                            spacing: 3
                            Text {
                                text: "↓"
                                font.family: root.textFontFamily
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: StyleTokens.success
                            }
                            Text {
                                text: SystemGlance.downloadSpeedText ? SystemGlance.downloadSpeedText.replace("↓ ", "") : "0 B/s"
                                font.family: root.heroFontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: StyleTokens.textPrimaryBright
                            }
                        }

                        Row {
                            spacing: 3
                            Text {
                                text: "↑"
                                font.family: root.textFontFamily
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: "#0a84ff"
                            }
                            Text {
                                text: SystemGlance.uploadSpeedText ? SystemGlance.uploadSpeedText.replace("↑ ", "") : "0 B/s"
                                font.family: root.heroFontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: StyleTokens.textPrimaryBright
                            }
                        }
                    }

                    Text {
                        text: "IP: " + (SystemGlance.ipAddress || "127.0.0.1")
                        font.family: root.textFontFamily
                        font.pixelSize: 10
                        color: StyleTokens.textSecondary
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }

            // --------------------
            // Card 4: GPU / Disk Card
            // --------------------
            Rectangle {
                width: Math.floor((metricGrid.width - metricGrid.spacing) / 2)
                height: 76
                radius: 14
                color: StyleTokens.cardFill
                border.width: 1
                border.color: StyleTokens.inputBorder

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 18

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                text: "\uf0a0"
                                font.family: root.iconFontFamily
                                font.pixelSize: 11
                                color: StyleTokens.warning
                            }

                            Text {
                                text: "Storage"
                                font.family: root.heroFontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: StyleTokens.textPrimaryBright
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 18
                            width: diskPercentText.implicitWidth + 10
                            radius: 9
                            color: StyleTokens.withAlpha(StyleTokens.warning, 0.18)

                            Text {
                                id: diskPercentText
                                anchors.centerIn: parent
                                text: Math.round(SystemGlance.diskUsagePercent || 0) + "%"
                                font.family: root.textFontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: StyleTokens.warning
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: SystemGlance.diskText || "0 / 0 GB"
                            font.family: root.heroFontFamily
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: StyleTokens.textPrimaryBright
                        }
                    }

                    // Progress Bar
                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: StyleTokens.cardFillHover

                        Rectangle {
                            height: parent.height
                            radius: 2
                            width: Math.max(4, parent.width * Math.min(1.0, (SystemGlance.diskUsagePercent || 0) / 100.0))
                            color: StyleTokens.warning

                            Behavior on width {
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }
            }
        }

        // ==========================================
        // 3. Bottom Kernel & System Telemetry Pill
        // ==========================================
        Rectangle {
            id: kernelPill
            width: parent.width
            height: 44
            radius: 14
            color: StyleTokens.clearBlack
            border.width: 1
            border.color: kernelHover.containsMouse ? StyleTokens.accent : StyleTokens.inputBorder

            Behavior on border.color { ColorAnimation { duration: 150 } }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                // Left Section: Linux Kernel & Architecture
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    width: Math.floor((parent.width - 25) * 0.52)

                    // Linux Tux Icon
                    Rectangle {
                        width: 28
                        height: 28
                        radius: 8
                        color: StyleTokens.cardFillActive
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "\uf17c" // Tux Linux penguin
                            font.family: root.iconFontFamily
                            font.pixelSize: 14
                            color: StyleTokens.accent
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        width: parent.width - 36

                        Text {
                            width: parent.width
                            text: "Linux " + (SystemGlance.kernelRelease || SystemGlance.kernelVersion || "Kernel")
                            font.family: root.textFontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: StyleTokens.textPrimaryBright
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: (SystemGlance.kernelArch || "x86_64") + " • " + (SystemGlance.cpuGovernor || "powersave") + ((SystemGlance.pendingUpdatesCount || 0) > 0 ? (" • " + SystemGlance.pendingUpdatesCount + " pkgs") : "")
                            font.family: root.textFontFamily
                            font.pixelSize: 10
                            color: StyleTokens.textMuted
                            elide: Text.ElideRight
                        }
                    }
                }

                // Vertical Divider
                Rectangle {
                    width: 1
                    height: 22
                    color: StyleTokens.inputBorder
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Right Section: Load Averages & Scheduling Entities (Tasks)
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    width: Math.floor((parent.width - 25) * 0.48)

                    // Tachometer / Load Icon
                    Rectangle {
                        width: 28
                        height: 28
                        radius: 8
                        color: StyleTokens.cardFillActive
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "\uf0e4" // Tachometer / Gauge
                            font.family: root.iconFontFamily
                            font.pixelSize: 13
                            color: StyleTokens.textPrimaryBright
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        width: parent.width - 36

                        Text {
                            width: parent.width
                            text: "Load: " + (SystemGlance.loadAvgText || "0.00, 0.00, 0.00")
                            font.family: root.textFontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: StyleTokens.textPrimaryBright
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: SystemGlance.tasksText || "Active tasks"
                            font.family: root.textFontFamily
                            font.pixelSize: 10
                            color: StyleTokens.textMuted
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            MouseArea {
                id: kernelHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }
        }
    }
}
