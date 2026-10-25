import QtQuick
import IslandBackend
import "../common"

Item {
    id: root

    property var provider: null
    property string panelKind: "wifi"
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property string heroFontFamily: textFontFamily
    property real presentationProgress: 1

    readonly property bool isWifi: panelKind === "wifi"
    readonly property bool isBluetooth: panelKind === "bluetooth"
    readonly property bool isPower: panelKind === "power"
    readonly property var bluetoothDevices: provider ? provider.bluetoothDeviceValues || [] : []
    readonly property var bluetoothConnectedDevices: bluetoothDevicesForSection("connected")
    readonly property var bluetoothPairedDevices: bluetoothDevicesForSection("paired")
    readonly property var bluetoothAvailableDevices: bluetoothDevicesForSection("available")
    readonly property int bluetoothDeviceCount: bluetoothConnectedDevices.length
        + bluetoothPairedDevices.length
        + bluetoothAvailableDevices.length
    readonly property bool bluetoothScanning: provider && provider.bluetoothAdapter
        ? provider.bluetoothAdapter.discovering
        : !!(provider && provider.bluetoothListRunning)

    function safeString(value) {
        return value === undefined || value === null ? "" : String(value);
    }

    function wifiEntryVisible(connected) {
        if (!root.provider) return false;
        return !(connected && root.provider.wifiEnabled && safeString(root.provider.wifiCurrentSsid).length > 0);
    }

    function bluetoothDeviceVisible(device, section) {
        return root.provider && root.provider.bluetoothDeviceMatchesSection
            ? root.provider.bluetoothDeviceMatchesSection(device, section)
            : false;
    }

    function bluetoothDevicesForSection(section) {
        const devices = root.bluetoothDevices || [];
        const filtered = [];

        for (let index = 0; index < devices.length; index++) {
            const device = devices[index];
            if (root.bluetoothDeviceVisible(device, section))
                filtered.push(device);
        }

        filtered.sort(function(left, right) {
            const leftNamed = root.provider && root.provider.bluetoothDeviceHasFriendlyName
                ? root.provider.bluetoothDeviceHasFriendlyName(left)
                : false;
            const rightNamed = root.provider && root.provider.bluetoothDeviceHasFriendlyName
                ? root.provider.bluetoothDeviceHasFriendlyName(right)
                : false;
            if (leftNamed !== rightNamed)
                return leftNamed ? -1 : 1;

            const leftName = root.provider && root.provider.bluetoothDeviceName
                ? root.provider.bluetoothDeviceName(left)
                : "";
            const rightName = root.provider && root.provider.bluetoothDeviceName
                ? root.provider.bluetoothDeviceName(right)
                : "";
            return leftName.localeCompare(rightName);
        });

        return filtered;
    }

    function focusPromptField() {
        if (wifiPasswordPrompt.visible) {
            wifiPasswordField.forceActiveFocus();
            return;
        }

        if (bluetoothPairingPrompt.visible && bluetoothSecretField.visible)
            bluetoothSecretField.forceActiveFocus();
    }

    Timer {
        id: promptFocusTimer
        interval: 0
        repeat: false
        onTriggered: root.focusPromptField()
    }

    Keys.onEscapePressed: function(event) {
        if (root.isWifi && root.provider && root.provider.wifiPendingPasswordSsid.length > 0) {
            root.provider.clearWifiPrompt();
            event.accepted = true;
            return;
        }
        if (root.isBluetooth && root.provider && root.provider.bluetoothPairingActive) {
            root.provider.cancelBluetoothPairing();
            event.accepted = true;
            return;
        }
        root.closeRequested();
        event.accepted = true;
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            if (root.isWifi && root.provider && root.provider.wifiPendingPasswordSsid.length > 0) {
                root.provider.clearWifiPrompt();
                event.accepted = true;
                return;
            }
            if (root.isBluetooth && root.provider && root.provider.bluetoothPairingActive) {
                root.provider.cancelBluetoothPairing();
                event.accepted = true;
                return;
            }
            root.closeRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.isBluetooth && root.provider && root.provider.bluetoothPairingActive && root.provider.bluetoothPairingRequiresConfirmation) {
                root.provider.confirmBluetoothPairing();
                event.accepted = true;
            }
        }
    }

    Connections {
        target: root.provider
        ignoreUnknownSignals: true

        function onWifiPendingPasswordSsidChanged() {
            promptFocusTimer.restart();
        }

        function onBluetoothPairingActiveChanged() {
            promptFocusTimer.restart();
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

        Item {
            id: headerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 24

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.isWifi ? "Wi-Fi" : root.isBluetooth ? "Bluetooth" : "Battery"
                color: StyleTokens.textPrimary
                font.pixelSize: 15
                font.family: root.heroFontFamily
                font.weight: Font.Bold
            }

            Rectangle {
                id: bluetoothScanButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 58
                height: 24
                radius: 12
                visible: root.isBluetooth && root.provider
                    && root.provider.bluetoothAvailable
                    && root.provider.bluetoothEnabled
                color: bluetoothScanMouse.containsMouse
                    ? StyleTokens.moduleHover
                    : StyleTokens.secondaryButton

                Text {
                    anchors.centerIn: parent
                    text: root.bluetoothScanning ? "Stop" : "Scan"
                    color: root.bluetoothScanning ? StyleTokens.accentSoft : StyleTokens.textPrimary
                    font.pixelSize: 10
                    font.family: root.textFontFamily
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: bluetoothScanMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.provider)
                            root.provider.toggleBluetoothScan();
                    }
                }
            }
        }

        Column {
            id: topSection
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerRow.bottom
            anchors.topMargin: root.isPower ? 10 : 14
            spacing: 10

            Rectangle {
                width: parent.width
                height: visible ? 64 : 0
                radius: 16
                color: StyleTokens.transparent
                visible: root.isWifi && root.provider && root.provider.wifiEnabled && root.provider.wifiCurrentSsid.length > 0

                MouseArea {
                    anchors.fill: parent
                    enabled: root.provider
                        && root.provider.wifiSupported
                        && root.provider.wifiAvailable
                        && !root.provider.wifiBusy
                    onClicked: {
                        if (root.provider)
                            root.provider.disconnectWifi();
                    }
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: 14

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.provider ? root.provider.wifiGlyph : ""
                        color: StyleTokens.accent
                        font.pixelSize: 16
                        font.family: root.iconFontFamily
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 28
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.rightMargin: 24
                        text: root.provider ? root.provider.wifiCurrentSsid : ""
                        color: StyleTokens.textPrimary
                        font.pixelSize: 12
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 28
                        anchors.bottom: parent.bottom
                        text: "Connected"
                        color: StyleTokens.textSoft
                        font.pixelSize: 11
                        font.family: root.textFontFamily
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✓"
                        color: StyleTokens.success
                        font.pixelSize: 18
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                    }
                }
            }

            Text {
                width: parent.width
                visible: root.provider && root.provider.wifiAvailabilityMessage.length > 0 && root.isWifi
                text: root.provider ? root.provider.wifiAvailabilityMessage : ""
                color: StyleTokens.textMuted
                font.pixelSize: 11
                font.family: root.textFontFamily
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                visible: root.provider && root.provider.wifiInfoMessage.length > 0 && root.isWifi
                text: root.provider ? root.provider.wifiInfoMessage : ""
                color: StyleTokens.accentSoft
                font.pixelSize: 11
                font.family: root.textFontFamily
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                visible: root.provider && root.provider.wifiError.length > 0 && root.isWifi
                text: root.provider ? root.provider.wifiError : ""
                color: StyleTokens.error
                font.pixelSize: 11
                font.family: root.textFontFamily
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                visible: root.provider && root.provider.bluetoothAvailabilityMessage.length > 0 && root.isBluetooth
                text: root.provider ? root.provider.bluetoothAvailabilityMessage : ""
                color: StyleTokens.textMuted
                font.pixelSize: 11
                font.family: root.textFontFamily
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                visible: root.provider && root.provider.bluetoothInfoMessage.length > 0 && root.isBluetooth
                text: root.provider ? root.provider.bluetoothInfoMessage : ""
                color: StyleTokens.accentSoft
                font.pixelSize: 11
                font.family: root.textFontFamily
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                visible: root.provider && root.provider.bluetoothError.length > 0 && root.isBluetooth
                text: root.provider ? root.provider.bluetoothError : ""
                color: StyleTokens.error
                font.pixelSize: 11
                font.family: root.textFontFamily
                wrapMode: Text.Wrap
            }

            Rectangle {
                id: bluetoothPairingPrompt
                width: parent.width
                height: visible
                    ? ((root.provider && root.provider.bluetoothPairingRequiresInput)
                        ? 122
                        : ((root.provider && root.provider.bluetoothPairingRequiresConfirmation) ? 110 : 82))
                    : 0
                radius: 16
                color: StyleTokens.prompt
                visible: root.isBluetooth && root.provider && root.provider.bluetoothPairingActive
                clip: true

                onVisibleChanged: {
                    if (visible)
                        promptFocusTimer.restart();
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: 12

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 10

                        Text {
                            width: parent.width
                            text: root.provider ? root.provider.bluetoothPairingTitle : ""
                            color: StyleTokens.textPrimary
                            font.pixelSize: 12
                            font.family: root.textFontFamily
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.provider ? root.provider.bluetoothPairingMessage : ""
                            color: "#d2d4da"
                            font.pixelSize: 11
                            font.family: root.textFontFamily
                            wrapMode: Text.Wrap
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        spacing: 8
                        visible: root.provider
                            && (root.provider.bluetoothPairingRequiresInput
                                || root.provider.bluetoothPairingRequiresConfirmation)

                        Rectangle {
                            id: bluetoothSecretFieldFrame
                            width: visible
                                ? Math.max(0, parent.width - bluetoothPrimaryButton.width - bluetoothCancelButton.width - 16)
                                : 0
                            height: 34
                            radius: 12
                            color: StyleTokens.input
                            border.color: StyleTokens.inputBorder
                            border.width: 1
                            visible: root.provider && root.provider.bluetoothPairingRequiresInput

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.provider && root.provider.bluetoothPairingNumericInput
                                    ? "Passkey"
                                    : "PIN"
                                color: StyleTokens.textTertiary
                                font.pixelSize: 11
                                font.family: root.textFontFamily
                                visible: bluetoothSecretField.text.length === 0 && !bluetoothSecretField.activeFocus
                            }

                            TextInput {
                                id: bluetoothSecretField
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                height: Math.min(parent.height - 8, implicitHeight + 2)
                                color: StyleTokens.textPrimary
                                font.pixelSize: 11
                                font.family: root.textFontFamily
                                verticalAlignment: TextInput.AlignVCenter
                                topPadding: 0
                                bottomPadding: 0
                                leftPadding: 0
                                rightPadding: 0
                                clip: true
                                selectByMouse: true
                                cursorVisible: activeFocus
                                inputMethodHints: root.provider && root.provider.bluetoothPairingNumericInput
                                    ? Qt.ImhDigitsOnly
                                    : Qt.ImhNoPredictiveText
                                maximumLength: root.provider && root.provider.bluetoothPairingNumericInput ? 6 : 16
                                text: root.provider ? root.provider.bluetoothPendingSecretValue : ""
                                onTextChanged: {
                                    if (root.provider)
                                        root.provider.bluetoothPendingSecretValue = text;
                                }
                                Keys.onReturnPressed: {
                                    if (root.provider)
                                        root.provider.submitBluetoothPairingSecret();
                                }
                                Keys.onEnterPressed: {
                                    if (root.provider)
                                        root.provider.submitBluetoothPairingSecret();
                                }
                                Keys.onEscapePressed: {
                                    if (root.provider)
                                        root.provider.cancelBluetoothPairing();
                                }
                            }
                        }

                        Rectangle {
                            id: bluetoothPrimaryButton
                            width: root.provider && root.provider.bluetoothPairingRequiresInput ? 50 : 76
                            height: 34
                            radius: 12
                            color: StyleTokens.accent

                            Text {
                                anchors.centerIn: parent
                                text: root.provider && root.provider.bluetoothPairingRequiresConfirmation
                                    ? "Confirm"
                                    : "Pair"
                                color: StyleTokens.white
                                font.pixelSize: 11
                                font.family: root.textFontFamily
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (!root.provider)
                                        return;

                                    if (root.provider.bluetoothPairingRequiresConfirmation)
                                        root.provider.confirmBluetoothPairing();
                                    else
                                        root.provider.submitBluetoothPairingSecret();
                                }
                            }
                        }

                        Rectangle {
                            id: bluetoothCancelButton
                            width: 58
                            height: 34
                            radius: 12
                            color: StyleTokens.secondaryButton

                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: StyleTokens.textPrimary
                                font.pixelSize: 11
                                font.family: root.textFontFamily
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (root.provider)
                                        root.provider.cancelBluetoothPairing();
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: wifiPasswordPrompt
                width: parent.width
                height: visible ? 92 : 0
                radius: 16
                color: StyleTokens.prompt
                visible: root.isWifi && root.provider && root.provider.wifiPendingPasswordSsid.length > 0
                clip: true

                onVisibleChanged: {
                    if (visible)
                        promptFocusTimer.restart();
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: 12

                    Text {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.right: parent.right
                        text: "Enter password for " + (root.provider ? root.provider.wifiPendingPasswordSsid : "")
                        color: StyleTokens.textPrimary
                        font.pixelSize: 12
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: joinButton.left
                        anchors.rightMargin: 8
                        anchors.bottom: parent.bottom
                        height: 34
                        radius: 12
                        color: StyleTokens.input
                        border.color: StyleTokens.inputBorder
                        border.width: 1

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Password"
                            color: StyleTokens.textTertiary
                            font.pixelSize: 11
                            font.family: root.textFontFamily
                            visible: root.provider && root.provider.wifiPendingPasswordValue.length === 0 && !wifiPasswordField.activeFocus
                        }

                        TextInput {
                            id: wifiPasswordField
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            height: Math.min(parent.height - 8, implicitHeight + 2)
                            color: StyleTokens.textPrimary
                            font.pixelSize: 11
                            font.family: root.textFontFamily
                            echoMode: TextInput.Password
                            verticalAlignment: TextInput.AlignVCenter
                            topPadding: 0
                            bottomPadding: 0
                            leftPadding: 0
                            rightPadding: 0
                            clip: true
                            selectByMouse: true
                            cursorVisible: activeFocus
                            text: root.provider ? root.provider.wifiPendingPasswordValue : ""
                            onTextChanged: {
                                if (root.provider)
                                    root.provider.wifiPendingPasswordValue = text;
                            }
                            Keys.onReturnPressed: {
                                if (root.provider)
                                    root.provider.submitWifiPassword();
                            }
                            Keys.onEnterPressed: {
                                if (root.provider)
                                    root.provider.submitWifiPassword();
                            }
                            Keys.onEscapePressed: {
                                if (root.provider)
                                    root.provider.clearWifiPrompt();
                            }
                        }
                    }

                    Rectangle {
                        id: joinButton
                        anchors.right: cancelButton.left
                        anchors.rightMargin: 8
                        anchors.bottom: parent.bottom
                        width: 50
                        height: 34
                        radius: 12
                        color: StyleTokens.accent

                        Text {
                            anchors.centerIn: parent
                            text: "Join"
                            color: StyleTokens.white
                            font.pixelSize: 11
                            font.family: root.textFontFamily
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (root.provider)
                                    root.provider.submitWifiPassword();
                            }
                        }
                    }

                    Rectangle {
                        id: cancelButton
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: 50
                        height: 34
                        radius: 12
                        color: StyleTokens.secondaryButton

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: StyleTokens.textPrimary
                            font.pixelSize: 11
                            font.family: root.textFontFamily
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (root.provider)
                                    root.provider.clearWifiPrompt();
                            }
                        }
                    }
                }
            }
        }

        Flickable {
            id: contentFlick
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: topSection.bottom
            anchors.bottom: parent.bottom
            clip: true
            contentWidth: width
            contentHeight: contentColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: contentColumn
                width: contentFlick.width
                spacing: 8

                // 1. Live Battery Status & Metrics Card
                Rectangle {
                    visible: root.isPower
                    width: parent.width
                    height: 58
                    radius: 16
                    color: StyleTokens.secondaryButton

                    Item {
                        id: batteryInfoContainer
                        anchors.fill: parent
                        anchors.margins: 10

                        readonly property int effectiveCap: (root.provider && root.provider.batteryCapacity > 0)
                            ? root.provider.batteryCapacity
                            : ((typeof SysBackend !== "undefined" && SysBackend.batteryCapacity > 0)
                                ? SysBackend.batteryCapacity
                                : ((typeof SystemGlance !== "undefined" && SystemGlance.batteryCapacity > 0) ? SystemGlance.batteryCapacity : 0))
                        readonly property bool effectiveCharging: (root.provider && root.provider.isCharging)
                            || (typeof SysBackend !== "undefined" && (SysBackend.batteryStatus === "Charging" || SysBackend.batteryStatus === "Full"))
                            || (typeof SystemGlance !== "undefined" && (SystemGlance.batteryStatus === "Charging" || SystemGlance.batteryStatus === "Full"))

                        Rectangle {
                            id: batteryIconCircle
                            width: 38
                            height: 38
                            radius: 19
                            color: StyleTokens.moduleHover
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: batteryInfoContainer.effectiveCharging ? (root.provider ? root.provider.chargingIconGlyph || "\uf0e7" : "\uf0e7") : "\uf240"
                                color: batteryInfoContainer.effectiveCharging
                                    ? StyleTokens.accent
                                    : (batteryInfoContainer.effectiveCap <= 20 ? StyleTokens.warning : StyleTokens.textPrimary)
                                font.pixelSize: 15
                                font.family: root.iconFontFamily
                            }
                        }

                        Column {
                            anchors.left: batteryIconCircle.right
                            anchors.leftMargin: 10
                            anchors.right: batteryStatusBadge.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Row {
                                spacing: 6

                                Text {
                                    text: batteryInfoContainer.effectiveCap + "%"
                                    color: StyleTokens.textPrimary
                                    font.pixelSize: 15
                                    font.family: root.heroFontFamily
                                    font.weight: Font.Bold
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: {
                                        if (batteryInfoContainer.effectiveCharging) return "Charging";
                                        if (SystemServices.batteryChargeState === "Not charging") return "Plugged In";
                                        if (SystemServices.batteryChargeState === "Full") return "Full";
                                        return "Discharging";
                                    }
                                    color: StyleTokens.textMuted
                                    font.pixelSize: 11
                                    font.family: root.textFontFamily
                                }
                            }

                            Text {
                                width: parent.width
                                text: {
                                    if (SystemServices.batteryConservationMode)
                                        return "Conservation limit active (80% ceiling)";
                                    if (SystemServices.batteryCycleCount > 0)
                                        return SystemServices.batteryCycleCount + " cycles • " + SystemServices.batteryHealthPercent + "% health";
                                    return "Full capacity mode";
                                }
                                color: StyleTokens.textDim
                                font.pixelSize: 10
                                font.family: root.textFontFamily
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            id: batteryStatusBadge
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: badgeText.implicitWidth + 14
                            height: 22
                            radius: 11
                            color: SystemServices.batteryConservationMode ? StyleTokens.moduleHover : StyleTokens.transparent
                            border.color: SystemServices.batteryConservationMode ? StyleTokens.accent : StyleTokens.track
                            border.width: 1

                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: SystemServices.batteryConservationMode ? "80% Cap" : "100% Full"
                                color: SystemServices.batteryConservationMode ? StyleTokens.accent : StyleTokens.textMuted
                                font.pixelSize: 10
                                font.family: root.textFontFamily
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                // 2. Battery Health & Charge Limit Card
                Rectangle {
                    visible: root.isPower && SystemServices.batteryThresholdSupported
                    width: parent.width
                    implicitHeight: thresholdContentCol.implicitHeight + 20
                    radius: 16
                    color: StyleTokens.secondaryButton

                    Column {
                        id: thresholdContentCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 8

                        Item {
                            width: parent.width
                            height: 18

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Text {
                                    text: "\uf132"
                                    color: StyleTokens.accent
                                    font.pixelSize: 12
                                    font.family: root.iconFontFamily
                                }

                                Text {
                                    text: "Charge Limit"
                                    color: StyleTokens.textPrimary
                                    font.pixelSize: 12
                                    font.family: root.textFontFamily
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: SystemServices.batteryThresholdBusy
                                    ? "Applying..."
                                    : (SystemServices.batteryThresholdType === "conservation"
                                        ? (SystemServices.batteryConservationMode ? "Conservation (80%)" : "Full Charge (100%)")
                                        : (SystemServices.batteryThresholdValue + "% Limit"))
                                color: SystemServices.batteryThresholdBusy ? StyleTokens.warning : StyleTokens.textMuted
                                font.pixelSize: 10
                                font.family: root.textFontFamily
                            }
                        }

                        // Presets Row for Lenovo IdeaPad (Conservation Mode)
                        Row {
                            visible: SystemServices.batteryThresholdType === "conservation"
                            width: parent.width
                            spacing: 8

                            readonly property real pillWidth: (width - spacing) / 2

                            Rectangle {
                                width: parent.pillWidth
                                height: 32
                                radius: 10
                                color: SystemServices.batteryConservationMode ? StyleTokens.accent : StyleTokens.moduleHover
                                opacity: SystemServices.batteryThresholdBusy ? 0.6 : 1.0

                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "80% Conservation"
                                    color: SystemServices.batteryConservationMode ? StyleTokens.textOnAccent : StyleTokens.textPrimary
                                    font.pixelSize: 11
                                    font.family: root.textFontFamily
                                    font.weight: SystemServices.batteryConservationMode ? Font.DemiBold : Font.Normal
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !SystemServices.batteryThresholdBusy
                                    onClicked: SystemServices.setBatteryConservationMode(true)
                                }
                            }

                            Rectangle {
                                width: parent.pillWidth
                                height: 32
                                radius: 10
                                color: !SystemServices.batteryConservationMode ? StyleTokens.accent : StyleTokens.moduleHover
                                opacity: SystemServices.batteryThresholdBusy ? 0.6 : 1.0

                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "100% Full Charge"
                                    color: !SystemServices.batteryConservationMode ? StyleTokens.textOnAccent : StyleTokens.textPrimary
                                    font.pixelSize: 11
                                    font.family: root.textFontFamily
                                    font.weight: !SystemServices.batteryConservationMode ? Font.DemiBold : Font.Normal
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !SystemServices.batteryThresholdBusy
                                    onClicked: SystemServices.setBatteryConservationMode(false)
                                }
                            }
                        }

                        // Presets Row for Generic Thresholds (ThinkPad, ASUS, etc.)
                        Row {
                            visible: SystemServices.batteryThresholdType === "threshold"
                            width: parent.width
                            spacing: 6

                            Repeater {
                                model: [80, 85, 90, 100]

                                delegate: Rectangle {
                                    readonly property bool active: SystemServices.batteryThresholdValue === modelData
                                    width: (parent.width - 18) / 4
                                    height: 32
                                    radius: 10
                                    color: active ? StyleTokens.accent : StyleTokens.moduleHover
                                    opacity: SystemServices.batteryThresholdBusy ? 0.6 : 1.0

                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData + "%"
                                        color: active ? StyleTokens.textOnAccent : StyleTokens.textPrimary
                                        font.pixelSize: 11
                                        font.family: root.textFontFamily
                                        font.weight: active ? Font.DemiBold : Font.Normal
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: !SystemServices.batteryThresholdBusy
                                        onClicked: SystemServices.setBatteryThreshold(modelData)
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: SystemServices.batteryThresholdType === "conservation"
                                ? (SystemServices.batteryConservationMode
                                    ? "Stops charging at 80% to preserve battery lifespan while plugged in."
                                    : "Charges battery to 100% capacity for extended mobile use.")
                                : ("Charging stops at " + SystemServices.batteryThresholdValue + "% to reduce battery degradation.")
                            color: StyleTokens.textMuted
                            font.pixelSize: 10
                            font.family: root.textFontFamily
                            wrapMode: Text.Wrap
                        }
                    }
                }



                Text {
                    width: parent.width
                    visible: root.isWifi && root.provider
                        && root.provider.wifiSupported
                        && root.provider.wifiAvailable
                        && !root.provider.wifiEnabled
                    text: "Turn on Wi-Fi to see nearby networks."
                    color: StyleTokens.textMuted
                    font.pixelSize: 12
                    font.family: root.textFontFamily
                    wrapMode: Text.Wrap
                }

                Text {
                    width: parent.width
                    visible: root.isWifi && root.provider && root.provider.wifiListRunning
                    text: "Scanning nearby networks..."
                    color: StyleTokens.textMuted
                    font.pixelSize: 12
                    font.family: root.textFontFamily
                }

                Repeater {
                    model: root.isWifi && root.provider ? root.provider.wifiNetworks : null

                    delegate: Rectangle {
                        width: contentColumn.width
                        height: visible ? 52 : 0
                        radius: 14
                        color: StyleTokens.transparent
                        visible: root.wifiEntryVisible(connected)
                        clip: true

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.provider
                                && root.provider.wifiSupported
                                && root.provider.wifiAvailable
                                && root.provider.wifiEnabled
                                && !root.provider.wifiBusy
                            onClicked: {
                                if (!root.provider) return;
                                root.provider.connectWifiNetwork({
                                    ssid: ssid,
                                    type: type,
                                    secure: secure,
                                    savedConnection: savedConnection,
                                    connected: connected
                                });
                            }
                        }

                        Item {
                            anchors.fill: parent
                            anchors.margins: 12

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.provider ? root.provider.wifiGlyph : ""
                                color: connected ? StyleTokens.accent : StyleTokens.disabledControl
                                font.pixelSize: 14
                                font.family: root.iconFontFamily
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 26
                                anchors.top: parent.top
                                anchors.right: rightInfo.left
                                anchors.rightMargin: 8
                                text: displayName
                                color: StyleTokens.textPrimary
                                font.pixelSize: 12
                                font.family: root.textFontFamily
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 26
                                anchors.bottom: parent.bottom
                                anchors.right: rightInfo.left
                                anchors.rightMargin: 8
                                text: secure ? "Secure network" : "Open network"
                                color: StyleTokens.textMuted
                                font.pixelSize: 10
                                font.family: root.textFontFamily
                                elide: Text.ElideRight
                            }

                            Row {
                                id: rightInfo
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Text {
                                    text: signal + "%"
                                    color: "#f0f0f3"
                                    font.pixelSize: 11
                                    font.family: root.textFontFamily
                                    visible: signal >= 0
                                }

                                Text {
                                    text: ""
                                    color: StyleTokens.textSubtle
                                    font.pixelSize: 11
                                    font.family: root.iconFontFamily
                                    visible: secure
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: root.isBluetooth && root.provider && root.provider.bluetoothAvailable && !root.provider.bluetoothEnabled
                    text: "Turn on Bluetooth to see nearby devices."
                    color: StyleTokens.textMuted
                    font.pixelSize: 12
                    font.family: root.textFontFamily
                    wrapMode: Text.Wrap
                }

                Text {
                    width: parent.width
                    visible: root.isBluetooth && root.provider
                        && root.provider.bluetoothEnabled
                        && root.bluetoothScanning
                    text: "Scanning nearby devices..."
                    color: StyleTokens.textMuted
                    font.pixelSize: 12
                    font.family: root.textFontFamily
                }

                Text {
                    width: parent.width
                    visible: root.isBluetooth && root.provider
                        && root.provider.bluetoothEnabled
                        && !root.bluetoothScanning
                        && root.bluetoothDeviceCount === 0
                    text: "No devices found. Put your device in pairing mode, then scan again."
                    color: StyleTokens.textMuted
                    font.pixelSize: 12
                    font.family: root.textFontFamily
                    wrapMode: Text.Wrap
                }

                Item {
                    width: parent.width
                    height: btConnectedSection.visible ? btConnectedSection.implicitHeight : 0
                    visible: root.isBluetooth && root.bluetoothConnectedDevices.length > 0

                    Column {
                        id: btConnectedSection
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "Connected"
                            color: StyleTokens.textTertiary
                            font.pixelSize: 10
                            font.family: root.textFontFamily
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: root.bluetoothConnectedDevices

                            delegate: BluetoothDeviceRow {
                                width: btConnectedSection.width
                                provider: root.provider
                                device: modelData
                                section: "connected"
                                iconFontFamily: root.iconFontFamily
                                textFontFamily: root.textFontFamily
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: btPairedSection.visible ? btPairedSection.implicitHeight : 0
                    visible: root.isBluetooth && root.bluetoothPairedDevices.length > 0

                    Column {
                        id: btPairedSection
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "Paired"
                            color: StyleTokens.textTertiary
                            font.pixelSize: 10
                            font.family: root.textFontFamily
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: root.bluetoothPairedDevices

                            delegate: BluetoothDeviceRow {
                                width: btPairedSection.width
                                provider: root.provider
                                device: modelData
                                section: "paired"
                                iconFontFamily: root.iconFontFamily
                                textFontFamily: root.textFontFamily
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: btAvailableSection.visible ? btAvailableSection.implicitHeight : 0
                    visible: root.isBluetooth && root.bluetoothAvailableDevices.length > 0

                    Column {
                        id: btAvailableSection
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "Available"
                            color: StyleTokens.textTertiary
                            font.pixelSize: 10
                            font.family: root.textFontFamily
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: root.bluetoothAvailableDevices

                            delegate: BluetoothDeviceRow {
                                width: btAvailableSection.width
                                provider: root.provider
                                device: modelData
                                section: "available"
                                iconFontFamily: root.iconFontFamily
                                textFontFamily: root.textFontFamily
                            }
                        }
                    }
                }
            }
        }

    }
}
