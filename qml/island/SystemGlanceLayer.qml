pragma ComponentBehavior: Bound

import QtQuick
import IslandBackend

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

    MouseArea {
        anchors.fill: parent
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
            width: parent.width
            height: 40

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                // Avatar / Monogram
                Rectangle {
                    width: 38
                    height: 38
                    radius: 19
                    color: StyleTokens.cardFillActive
                    border.width: 1
                    border.color: StyleTokens.inputBorder
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.fill: parent
                        visible: SystemGlance.avatarPath !== "" && status === Image.Ready
                        source: SystemGlance.avatarPath
                        fillMode: Image.PreserveAspectCrop
                        mipmap: true
                        asynchronous: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: SystemGlance.avatarPath === ""
                        text: (SystemGlance.userName && SystemGlance.userName.length > 0)
                            ? SystemGlance.userName.charAt(0).toUpperCase()
                            : "U"
                        color: StyleTokens.accent
                        font.family: root.heroFontFamily
                        font.pixelSize: 16
                        font.weight: Font.Bold
                    }
                }

                // User details
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Row {
                        spacing: 4

                        Text {
                            text: SystemGlance.userName
                            color: StyleTokens.textPrimaryBright
                            font.family: root.heroFontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Text {
                            text: "@" + SystemGlance.hostName
                            color: StyleTokens.textSecondary
                            font.family: root.textFontFamily
                            font.pixelSize: 11
                            anchors.baseline: parent.children[0].baseline
                        }
                    }

                    Row {
                        spacing: 6

                        Text {
                            text: "\uf017 " + SystemGlance.uptimeText
                            color: StyleTokens.textMuted
                            font.family: root.iconFontFamily
                            font.pixelSize: 10
                        }

                        Text {
                            text: "•"
                            color: StyleTokens.textMuted
                            font.pixelSize: 8
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: SystemGlance.osName
                            color: StyleTokens.textMuted
                            font.family: root.textFontFamily
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Right side: Battery badge & Close button
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // Battery badge
                Rectangle {
                    height: 24
                    width: batteryRow.implicitWidth + 14
                    radius: 12
                    color: StyleTokens.cardFill
                    border.width: 1
                    border.color: StyleTokens.inputBorder
                    anchors.verticalCenter: parent.verticalCenter

                    Row {
                        id: batteryRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isCharging ? "\uf0e7" : "\uf240"
                            font.family: root.iconFontFamily
                            font.pixelSize: 10
                            color: root.isCharging ? StyleTokens.success : (root.batteryCapacity <= 20 ? StyleTokens.danger : StyleTokens.textPrimaryBright)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.batteryCapacity + "%"
                            font.family: root.textFontFamily
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: StyleTokens.textPrimaryBright
                        }
                    }
                }

                // Close button
                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: closeArea.containsMouse ? StyleTokens.cardFillActive : StyleTokens.cardFill
                    border.width: 1
                    border.color: closeArea.containsMouse ? StyleTokens.accent : StyleTokens.inputBorder
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "\uf00d"
                        font.family: root.iconFontFamily
                        font.pixelSize: 10
                        color: closeArea.containsMouse ? StyleTokens.textPrimaryBright : StyleTokens.textSecondary
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }
        }

        // ==========================================
        // 2. 2x2 Metric Cards Grid
        // ==========================================
        Grid {
            width: parent.width
            columns: 2
            spacing: 8

            // --------------------
            // Card 1: CPU Card
            // --------------------
            Rectangle {
                width: Math.floor((mainCol.width - 8) / 2)
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
                                SystemGlance.cpuTemperature >= 80 ? StyleTokens.danger
                                : (SystemGlance.cpuTemperature >= 65 ? StyleTokens.warning : StyleTokens.success),
                                0.18
                            )

                            Text {
                                id: cpuTempText
                                anchors.centerIn: parent
                                text: SystemGlance.cpuTemperature + "°C"
                                font.family: root.textFontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: SystemGlance.cpuTemperature >= 80 ? StyleTokens.danger
                                    : (SystemGlance.cpuTemperature >= 65 ? StyleTokens.warning : StyleTokens.success)
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: Math.round(SystemGlance.cpuUsage) + "%"
                            font.family: root.heroFontFamily
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: StyleTokens.textPrimaryBright
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: SystemGlance.cpuModel
                            font.family: root.textFontFamily
                            font.pixelSize: 10
                            color: StyleTokens.textSecondary
                            elide: Text.ElideRight
                            width: parent.width - 50
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
                            width: Math.max(4, parent.width * Math.min(1.0, SystemGlance.cpuUsage / 100.0))
                            color: SystemGlance.cpuUsage >= 85 ? StyleTokens.danger
                                : (SystemGlance.cpuUsage >= 60 ? StyleTokens.warning : StyleTokens.accent)

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
                width: Math.floor((mainCol.width - 8) / 2)
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
                                text: Math.round(SystemGlance.memoryUsagePercent) + "%"
                                font.family: root.textFontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: "#af52de"
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: SystemGlance.memoryText
                            font.family: root.heroFontFamily
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: StyleTokens.textPrimaryBright
                            elide: Text.ElideRight
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
                            width: Math.max(4, parent.width * Math.min(1.0, SystemGlance.memoryUsagePercent / 100.0))
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
                width: Math.floor((mainCol.width - 8) / 2)
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
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                text: "\uf1eb"
                                font.family: root.iconFontFamily
                                font.pixelSize: 11
                                color: "#0a84ff"
                            }

                            Text {
                                text: SystemGlance.networkInterface
                                font.family: root.heroFontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: StyleTokens.textPrimaryBright
                            }
                        }

                        Rectangle {
                            visible: SystemGlance.vpnActive
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
                                text: SystemGlance.downloadSpeedText.replace("↓ ", "")
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
                                text: SystemGlance.uploadSpeedText.replace("↑ ", "")
                                font.family: root.heroFontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: StyleTokens.textPrimaryBright
                            }
                        }
                    }

                    Text {
                        text: "IP: " + SystemGlance.ipAddress
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
                width: Math.floor((mainCol.width - 8) / 2)
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
                                text: SystemGlance.gpuAvailable ? "\uf108" : "\uf0a0"
                                font.family: root.iconFontFamily
                                font.pixelSize: 11
                                color: StyleTokens.warning
                            }

                            Text {
                                text: SystemGlance.gpuAvailable ? SystemGlance.gpuName : "Storage"
                                font.family: root.heroFontFamily
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: StyleTokens.textPrimaryBright
                                elide: Text.ElideRight
                                width: Math.min(100, parent.width - 60)
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
                                text: (SystemGlance.gpuAvailable && SystemGlance.gpuTemperature > 0)
                                    ? (SystemGlance.gpuTemperature + "°C")
                                    : (Math.round(SystemGlance.diskUsagePercent) + "%")
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
                            text: SystemGlance.diskText
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
                            width: Math.max(4, parent.width * Math.min(1.0, SystemGlance.diskUsagePercent / 100.0))
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
        // 3. Bottom Quick Actions Bar (ChillPill-Shell inspired)
        // ==========================================
        Rectangle {
            width: parent.width
            height: 38
            radius: 19
            color: StyleTokens.clearBlack
            border.width: 1
            border.color: StyleTokens.inputBorder

            Row {
                anchors.centerIn: parent
                spacing: 14

                // Lock button
                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    color: lockBtnArea.containsMouse ? StyleTokens.cardFillHover : StyleTokens.transparent
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "\uf023"
                        font.family: root.iconFontFamily
                        font.pixelSize: 12
                        color: lockBtnArea.containsMouse ? StyleTokens.accent : StyleTokens.textPrimaryBright
                    }

                    MouseArea {
                        id: lockBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SystemGlance.lockScreen()
                    }
                }

                // Sleep / Suspend button
                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    color: sleepBtnArea.containsMouse ? StyleTokens.cardFillHover : StyleTokens.transparent
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "\uf186"
                        font.family: root.iconFontFamily
                        font.pixelSize: 12
                        color: sleepBtnArea.containsMouse ? StyleTokens.accent : StyleTokens.textPrimaryBright
                    }

                    MouseArea {
                        id: sleepBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SystemGlance.suspendSystem()
                    }
                }

                // Divider
                Rectangle {
                    width: 1
                    height: 16
                    color: StyleTokens.inputBorder
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Calendar button
                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    color: calBtnArea.containsMouse ? StyleTokens.cardFillHover : StyleTokens.transparent
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "\uf073"
                        font.family: root.iconFontFamily
                        font.pixelSize: 12
                        color: calBtnArea.containsMouse ? StyleTokens.accent : StyleTokens.textPrimaryBright
                    }

                    MouseArea {
                        id: calBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openCalendarRequested()
                    }
                }

                // Weather button
                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    color: weatherBtnArea.containsMouse ? StyleTokens.cardFillHover : StyleTokens.transparent
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "\uf0c2"
                        font.family: root.iconFontFamily
                        font.pixelSize: 12
                        color: weatherBtnArea.containsMouse ? StyleTokens.accent : StyleTokens.textPrimaryBright
                    }

                    MouseArea {
                        id: weatherBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openWeatherRequested()
                    }
                }

                // Divider
                Rectangle {
                    width: 1
                    height: 16
                    color: StyleTokens.inputBorder
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Restart / Reboot button
                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    color: rebootBtnArea.containsMouse ? StyleTokens.cardFillHover : StyleTokens.transparent
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "\uf021"
                        font.family: root.iconFontFamily
                        font.pixelSize: 12
                        color: rebootBtnArea.containsMouse ? StyleTokens.warning : StyleTokens.textPrimaryBright
                    }

                    MouseArea {
                        id: rebootBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SystemGlance.rebootSystem()
                    }
                }

                // Power off / Shutdown button
                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    color: shutdownBtnArea.containsMouse ? StyleTokens.cardFillHover : StyleTokens.transparent
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "\uf011"
                        font.family: root.iconFontFamily
                        font.pixelSize: 12
                        color: shutdownBtnArea.containsMouse ? StyleTokens.danger : StyleTokens.textPrimaryBright
                    }

                    MouseArea {
                        id: shutdownBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SystemGlance.powerOffSystem()
                    }
                }
            }
        }
    }
}
