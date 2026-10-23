import TideIsland 1.0
import QtQuick.Controls
import QtQuick
import QtCore
import QtQuick.Effects

PagePanel {
    id: root

    HiddenPathDialog {
        id: avatarFileDialog

        directoryMode: false
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.svg", "*.gif", "*.bmp"]
        onPathAccepted: function(path) {
            avatarRow.setPath(path)
        }
    }

    HiddenPathDialog {
        id: lockscreenWallpaperFileDialog

        directoryMode: false
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.svg", "*.gif", "*.bmp"]
        onPathAccepted: function(path) {
            lockscreenWallpaperRow.setPath(path)
        }
    }

    function intValue(key, fallback) {
        return String(ConfigStore.value(key, fallback))
    }

    function boolValue(key, fallback) {
        const val = ConfigStore.value(key, fallback);
        return val === undefined || val === null ? fallback : Boolean(val);
    }

    function saveInt(key, value, fallback, minimumValue, maximumValue) {
        if (String(value).trim().length === 0) {
            return fallback
        }

        const parsedValue = Number(value)
        if (isNaN(parsedValue)) {
            return fallback
        }

        const roundedValue = Math.min(maximumValue, Math.max(minimumValue, Math.round(parsedValue)))
        ConfigStore.setValue(key, roundedValue)
        ConfigStore.save()
        return roundedValue
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: content.height
        boundsBehavior: Flickable.StopAtBounds
        boundsMovement: Flickable.StopAtBounds
        interactive: false

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            onWheel: function(event) {
                const rawDelta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * 64
                const maxY = Math.max(0, scroller.contentHeight - scroller.height)
                scroller.contentY = Math.max(0, Math.min(maxY, scroller.contentY - rawDelta))
                event.accepted = true
            }
        }

        Item {
            id: content
            width: scroller.width
            height: weatherPanel.y + weatherPanel.height + 40

            Text {
                id: title
                font.family: Theme.titleFontFamily
                text: "General"
                color: Theme.textColor
                font.pixelSize: 30
                x: 60
                y: 50
            }

            Text {
                id: apperanceTitle
                text: "Island apperance"
                anchors.top: title.bottom
                anchors.topMargin: 34
                anchors.left: parent.left
                anchors.leftMargin: 32
                anchors.right: parent.right
                anchors.rightMargin: 40
                font.family: Theme.titleFontFamily
                font.pixelSize: 23
                color: Theme.textColor
            }

            Rectangle {
                id: apperance
                color: Theme.cardBgColor
                radius: 16
                border.width: 1
                border.color: Theme.splitLineColor

                anchors.top: apperanceTitle.bottom
                anchors.topMargin: 15
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.right: parent.right
                anchors.rightMargin: 40
                height: apperanceColumn.implicitHeight + 36

                Column {
                    id: apperanceColumn

                    anchors.top: parent.top
                    anchors.topMargin: 18
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    spacing: 16

                    IslandStyleRow { width: parent.width }

                    SplitLine { width: parent.width }

                    ConfigRow {
                        title: "Island Width"
                        description: "Width of island in clock mode"
                        keyName: "islandWidth"
                        fallbackText: "140"
                        numeric: true
                        width: parent.width
                    }

                    SplitLine { width: parent.width }

                    ConfigRow {
                        title: "Island Height"
                        description: "Height of island in clock mode"
                        keyName: "islandHeight"
                        fallbackText: "38"
                        numeric: true
                        width: parent.width
                    }

                    SplitLine { width: parent.width }

                    ConfigRow {
                        title: "Background Transparency"
                        description: "Opacity of the island background (0 = fully transparent, 100 = solid)"
                        keyName: "islandBackgroundOpacity"
                        fallbackText: "60"
                        numeric: true
                        minimumValue: 0
                        maximumValue: 100
                        width: parent.width
                    }

                    SplitLine { width: parent.width }

                    ClockFormatRow { width: parent.width }

                    SplitLine { width: parent.width }

                    ConfigRow {
                        title: "Reserved Top Space"
                        description: "Screen space reserved for the island (exclusive zone)"
                        keyName: "islandExclusiveZone"
                        fallbackText: "45"
                        numeric: true
                        minimumValue: 0
                        width: parent.width
                    }

                    SplitLine { width: parent.width }

                    ConfigRow {
                        title: "Top Margin"
                        description: "Distance between the island and the top of the screen"
                        keyName: "islandTopMargin"
                        fallbackText: "4"
                        numeric: true
                        minimumValue: 0
                        width: parent.width
                    }

                    SplitLine { width: parent.width }

                    ConfigRow {
                        title: "Island Position"
                        description: "X position of island"
                        keyName: "islandPositionX"
                        fallbackText: "50"
                        numeric: true
                        minimumValue: 0
                        maximumValue: 100
                        width: parent.width
                    }
                }
            }

            Text {
                id: profileTitle
                text: "Profile & System Glance"
                anchors.top: apperance.bottom
                anchors.topMargin: 34
                anchors.left: parent.left
                anchors.leftMargin: 32
                anchors.right: parent.right
                anchors.rightMargin: 40
                font.family: Theme.titleFontFamily
                font.pixelSize: 23
                color: Theme.textColor
            }

            Rectangle {
                id: profilePanel
                color: Theme.cardBgColor
                radius: 16
                border.width: 1
                border.color: Theme.splitLineColor

                anchors.top: profileTitle.bottom
                anchors.topMargin: 15
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.right: parent.right
                anchors.rightMargin: 40
                height: profileColumn.implicitHeight + 36

                Column {
                    id: profileColumn

                    anchors.top: parent.top
                    anchors.topMargin: 18
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    spacing: 16

                    AvatarRow {
                        id: avatarRow
                        title: "Profile Avatar"
                        description: "Avatar shown in the System Glance dashboard and Lockscreen"
                        keyName: "avatarPath"
                        width: parent.width
                    }
                }
            }

            Text {
                id: lockscreenTitle
                text: "Lockscreen"
                anchors.top: profilePanel.bottom
                anchors.topMargin: 34
                anchors.left: parent.left
                anchors.leftMargin: 32
                anchors.right: parent.right
                anchors.rightMargin: 40
                font.family: Theme.titleFontFamily
                font.pixelSize: 23
                color: Theme.textColor
            }

            Rectangle {
                id: lockscreenPanel
                color: Theme.cardBgColor
                radius: 16
                border.width: 1
                border.color: Theme.splitLineColor

                anchors.top: lockscreenTitle.bottom
                anchors.topMargin: 15
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.right: parent.right
                anchors.rightMargin: 40
                height: lockscreenColumn.implicitHeight + 36

                Column {
                    id: lockscreenColumn

                    anchors.top: parent.top
                    anchors.topMargin: 18
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    spacing: 16

                    LockscreenWallpaperRow {
                        id: lockscreenWallpaperRow
                        title: "Lockscreen Wallpaper"
                        description: "Custom wallpaper. If empty, the desktop wallpaper is used with blur"
                        keyName: "lockscreenWallpaperPath"
                        width: parent.width
                    }

                    SplitLine {
                        width: parent.width
                    }

                    SwitchRow {
                        title: "Blur Wallpaper"
                        description: "Apply blur effect to the lockscreen wallpaper"
                        keyName: "lockscreenBlur"
                        fallbackValue: true
                        width: parent.width
                    }

                    SplitLine {
                        width: parent.width
                    }

                    SwitchRow {
                        title: "Media Player"
                        description: "Show active media player and track controls on the lockscreen"
                        keyName: "lockscreenMedia"
                        fallbackValue: true
                        width: parent.width
                    }

                    SplitLine {
                        width: parent.width
                    }

                    SwitchRow {
                        title: "Power Actions"
                        description: "Show sleep, restart, and power off buttons on the lockscreen"
                        keyName: "lockscreenPowerActions"
                        fallbackValue: true
                        width: parent.width
                    }

                    SplitLine {
                        width: parent.width
                    }

                    SwitchRow {
                        title: "Battery Status"
                        description: "Show live battery percentage and charging indicator"
                        keyName: "lockscreenShowBattery"
                        fallbackValue: true
                        width: parent.width
                    }
                }
            }

            Text {
                id: customPageTitle
                text: "Custom Page"
                anchors.top: lockscreenPanel.bottom
                anchors.topMargin: 34
                anchors.left: parent.left
                anchors.leftMargin: 32
                anchors.right: parent.right
                anchors.rightMargin: 40
                font.family: Theme.titleFontFamily
                font.pixelSize: 23
                color: Theme.textColor
            }

            CustomPage {
                id: customPagePanel
                anchors.top: customPageTitle.bottom
                anchors.topMargin: 15
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.right: parent.right
                anchors.rightMargin: 40
                height: implicitHeight
            }

            Text {
                id: tlpTitle
                text: "Power Profiles"
                anchors.top: customPagePanel.bottom
                anchors.topMargin: 34
                anchors.left: parent.left
                anchors.leftMargin: 32
                anchors.right: parent.right
                anchors.rightMargin: 40
                font.family: Theme.titleFontFamily
                font.pixelSize: 23
                color: Theme.textColor
            }

            TlpSettings {
                id: tlpPanel
                anchors.top: tlpTitle.bottom
                anchors.topMargin: 15
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.right: parent.right
                anchors.rightMargin: 40
                height: implicitHeight
            }

            Text {
                id: weatherTitle
                text: "Weather"
                anchors.top: tlpPanel.bottom
                anchors.topMargin: 34
                anchors.left: parent.left
                anchors.leftMargin: 32
                anchors.right: parent.right
                anchors.rightMargin: 40
                font.family: Theme.titleFontFamily
                font.pixelSize: 23
                color: Theme.textColor
            }

            WeatherSettings {
                id: weatherPanel
                anchors.top: weatherTitle.bottom
                anchors.topMargin: 15
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.right: parent.right
                anchors.rightMargin: 40
                height: implicitHeight
            }

        }
    }

    component SplitLine: Rectangle {
        height: 1
        color: Theme.splitLineColor
    }

    component ConfigRow: Item {
        id: row

        property string title: ""
        property string description: ""
        property string keyName: ""
        property string fallbackText: ""
        property bool numeric: false
        property int minimumValue: 1
        property int maximumValue: 1000

        height: 49

        Text {
            id: rowTitle
            text: row.title
            font.family: Theme.textFontFamily
            font.pixelSize: 18
            color: Theme.textColor
            anchors.top: parent.top
            anchors.left: parent.left
        }

        Text {
            text: row.description
            font.family: Theme.textFontFamily
            font.pixelSize: 14
            anchors.top: rowTitle.bottom
            anchors.topMargin: 5
            anchors.left: rowTitle.left
            color: Theme.subtleTextColor
        }

        ConfigTextField {
            id: field
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: row.numeric ? 100 : 230
            height: 36
            placeholderText: row.fallbackText
            inputMethodHints: row.numeric ? Qt.ImhDigitsOnly : Qt.ImhNone
            validator: row.numeric ? intValidator : null

            Component.onCompleted: {
                text = root.intValue(row.keyName, Number(row.fallbackText))
            }

            onAccepted: row.commit()
            onEditingFinished: row.commit()
        }

        IntValidator {
            id: intValidator
            bottom: row.minimumValue
            top: row.maximumValue
        }

        function commit() {
            if (numeric) {
                field.text = String(root.saveInt(row.keyName, field.text, Number(row.fallbackText), row.minimumValue, row.maximumValue))
            }
        }
    }

    component IslandStyleRow: Item {
        id: styleRow

        property string selectedStyle: String(ConfigStore.value("islandStyle", "island")).toLowerCase() === "notch" ? "notch" : "island"

        height: 49

        Text {
            id: styleTitle
            text: "Island Style"
            font.family: Theme.textFontFamily
            font.pixelSize: 18
            color: Theme.textColor
            anchors.top: parent.top
            anchors.left: parent.left
        }

        Text {
            text: "Choose between floating Dynamic Island or top-attached Notch"
            font.family: Theme.textFontFamily
            font.pixelSize: 14
            anchors.top: styleTitle.bottom
            anchors.topMargin: 5
            anchors.left: styleTitle.left
            color: Theme.subtleTextColor
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                model: [
                    { id: "island", name: "Island" },
                    { id: "notch", name: "Notch" }
                ]

                Rectangle {
                    id: styleButton
                    readonly property bool selected: styleRow.selectedStyle === modelData.id

                    width: 82
                    height: 36
                    radius: 7
                    color: selected ? Theme.cardBgColor
                                    : styleMouse.pressed ? Theme.controlPressedColor
                                                         : Theme.componentBgColor
                    border.width: 1
                    border.color: Theme.inputBorderColor

                    Behavior on color { ColorAnimation { duration: Theme.animationDuration } }
                    Behavior on border.color { ColorAnimation { duration: Theme.animationDuration } }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.name
                        color: styleButton.selected ? Theme.textColor : Theme.secondaryTextColor
                        font.family: Theme.textFontFamily
                        font.pixelSize: 14
                        font.weight: styleButton.selected ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                        id: styleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            styleRow.selectedStyle = modelData.id
                            ConfigStore.setValue("islandStyle", modelData.id)
                            ConfigStore.save()
                        }
                    }
                }
            }
        }
    }

    component ClockFormatRow: Item {
        id: clockRow

        property string selectedFormat: String(ConfigStore.value("clockFormat", "12")) === "24" ? "24" : "12"

        height: 49

        Text {
            id: clockTitle
            text: "Clock Format"
            font.family: Theme.textFontFamily
            font.pixelSize: 18
            color: Theme.textColor
            anchors.top: parent.top
            anchors.left: parent.left
        }

        Text {
            text: "Choose 12-hour or 24-hour time"
            font.family: Theme.textFontFamily
            font.pixelSize: 14
            anchors.top: clockTitle.bottom
            anchors.topMargin: 5
            anchors.left: clockTitle.left
            color: Theme.subtleTextColor
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                model: ["12", "24"]

                Rectangle {
                    id: formatButton
                    readonly property bool selected: clockRow.selectedFormat === modelData

                    width: 82
                    height: 36
                    radius: 7
                    color: selected ? Theme.cardBgColor
                                    : formatMouse.pressed ? Theme.controlPressedColor
                                                          : Theme.componentBgColor
                    border.width: 1
                    border.color: Theme.inputBorderColor

                    Behavior on color { ColorAnimation { duration: Theme.animationDuration } }
                    Behavior on border.color { ColorAnimation { duration: Theme.animationDuration } }

                    Text {
                        anchors.centerIn: parent
                        text: modelData + " hour"
                        color: formatButton.selected ? Theme.textColor : Theme.secondaryTextColor
                        font.family: Theme.textFontFamily
                        font.pixelSize: 14
                        font.weight: formatButton.selected ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                        id: formatMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            clockRow.selectedFormat = modelData
                            ConfigStore.setValue("clockFormat", modelData)
                            ConfigStore.save()
                        }
                    }
                }
            }
        }
    }

    component ButtonLike: Rectangle {
        id: button

        signal clicked

        property string text: ""
        property bool primary: false

        width: 76
        height: 36
        radius: 6
        color: !button.enabled ? Theme.componentBgColor
                               : button.primary
                                   ? mouseArea.pressed ? Theme.buttonPressedColor
                                                       : mouseArea.containsMouse ? Theme.buttonHoverColor
                                                                                : Theme.buttonColor
                                   : mouseArea.pressed ? Theme.controlPressedColor
                                                       : mouseArea.containsMouse ? Theme.mutedButtonHoverColor
                                                                                : Theme.mutedButtonColor
        border.width: 1
        border.color: button.primary && button.enabled ? color : Theme.inputBorderColor

        Behavior on color { ColorAnimation { duration: Theme.animationDuration } }
        Behavior on border.color { ColorAnimation { duration: Theme.animationDuration } }

        Text {
            anchors.centerIn: parent
            text: button.text
            color: !button.enabled ? Theme.subtleTextColor
                                   : button.primary ? Theme.buttonTextColor
                                                    : Theme.mutedButtonTextColor
            font.family: Theme.textFontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            enabled: button.enabled
            hoverEnabled: true
            cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: button.clicked()
        }
    }

    component AvatarRow: Item {
        id: row

        property string title: ""
        property string description: ""
        property string keyName: "avatarPath"
        property int avatarVersion: 0

        height: 64

        function cleanHome() {
            let h = String(StandardPaths.writableLocation(StandardPaths.HomeLocation) || "");
            if (h.startsWith("file://"))
                h = h.substring(7);
            return h.replace(/\/+$/, "");
        }

        function resolveAvatarUrl(path) {
            if (!path || path.trim() === "")
                return "";
            let clean = path.trim();
            if (clean.startsWith("~")) {
                clean = cleanHome() + clean.substring(1);
            }
            if (clean.startsWith("/")) {
                return "file://" + clean;
            }
            return clean;
        }

        function effectiveAvatarSource() {
            const dummy = avatarVersion;
            const custom = ConfigStore.value(row.keyName, "");
            if (custom && String(custom).trim().length > 0)
                return resolveAvatarUrl(String(custom));

            const disp = ConfigStore.value("displayPicture", "");
            if (disp && String(disp).trim().length > 0)
                return resolveAvatarUrl(String(disp));

            return "file://" + cleanHome() + "/.config/tide-island/avatar.png";
        }

        Item {
            id: avatarContainer
            width: 52
            height: 52
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                id: avatarBg
                anchors.fill: parent
                radius: 26
                color: Theme.componentBgColor
                border.width: 1
                border.color: avatarMouseArea.containsMouse ? Theme.accentColor : Theme.inputBorderColor
                Behavior on border.color { ColorAnimation { duration: 150 } }
            }

            Text {
                id: monogramText
                anchors.centerIn: parent
                visible: !avatarContainer.hasValidImage
                text: {
                    const home = row.cleanHome();
                    const parts = home.split('/');
                    const user = parts.length > 0 ? parts[parts.length - 1] : "U";
                    return user.charAt(0).toUpperCase();
                }
                font.family: Theme.textFontFamily
                font.pixelSize: 20
                font.weight: Font.Bold
                color: Theme.accentColor
            }

            Image {
                id: rawImage
                anchors.fill: parent
                source: row.effectiveAvatarSource()
                fillMode: Image.PreserveAspectCrop
                visible: false
                asynchronous: true
                cache: false
            }

            Rectangle {
                id: circleMask
                anchors.fill: parent
                radius: 26
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: rawImage
                maskEnabled: true
                maskSource: circleMask
                visible: avatarContainer.hasValidImage
            }

            readonly property bool hasValidImage: rawImage.status === Image.Ready && (rawImage.source != "")

            Rectangle {
                anchors.fill: parent
                radius: 26
                color: Qt.rgba(0, 0, 0, 0.45)
                opacity: avatarMouseArea.containsMouse ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "Change"
                    font.family: Theme.textFontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: "#ffffff"
                }
            }

            MouseArea {
                id: avatarMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: avatarFileDialog.openForPath(field.text)
            }

            DropArea {
                anchors.fill: parent
                onDropped: function(drop) {
                    let p = "";
                    if (drop.hasUrls && drop.urls.length > 0) {
                        p = drop.urls[0].toString();
                    } else if (drop.hasText) {
                        p = drop.text.trim();
                    }
                    if (p.length > 0) {
                        if (p.startsWith("file://")) {
                            p = decodeURIComponent(p.substring(7));
                        }
                        row.setPath(p);
                    }
                }
            }
        }

        Column {
            anchors.left: avatarContainer.right
            anchors.leftMargin: 16
            anchors.right: controlsRow.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Text {
                text: row.title
                font.family: Theme.textFontFamily
                font.pixelSize: 18
                color: Theme.textColor
            }

            Text {
                text: row.description
                font.family: Theme.textFontFamily
                font.pixelSize: 13
                color: Theme.subtleTextColor
                elide: Text.ElideRight
                width: parent.width
            }
        }

        Row {
            id: controlsRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            ConfigTextField {
                id: field
                width: Math.max(160, Math.min(260, (row.width - 320) / 2))
                height: 36
                placeholderText: "Auto-detect (~/.face, avatar.png)"
                textPixelSize: 13

                Component.onCompleted: {
                    text = String(ConfigStore.value(row.keyName, ""))
                }

                onAccepted: row.commit()
                onEditingFinished: row.commit()
            }

            ButtonLike {
                text: "Browse"
                primary: true
                onClicked: avatarFileDialog.openForPath(field.text)
            }

            ButtonLike {
                text: "Clear"
                enabled: field.text.length > 0
                onClicked: row.clear()
            }
        }

        function setPath(path) {
            field.text = path;
            commit();
        }

        function clear() {
            field.text = "";
            ConfigStore.remove(row.keyName);
            ConfigStore.save();
            avatarVersion++;
        }

        function commit() {
            const val = field.text.trim();
            if (val.length === 0) {
                clear();
            } else {
                ConfigStore.setValue(row.keyName, val);
                ConfigStore.save();
                avatarVersion++;
            }
        }
    }

    component SwitchRow: Item {
        id: row

        property string title: ""
        property string description: ""
        property string keyName: ""
        property bool fallbackValue: true

        height: 49

        Text {
            id: switchTitle
            text: row.title
            font.family: Theme.textFontFamily
            font.pixelSize: 18
            color: Theme.textColor
            anchors.top: parent.top
            anchors.left: parent.left
        }

        Text {
            text: row.description
            font.family: Theme.textFontFamily
            font.pixelSize: 14
            anchors.top: switchTitle.bottom
            anchors.topMargin: 5
            anchors.left: switchTitle.left
            width: Math.max(80, parent.width - sw.width - 28)
            color: Theme.subtleTextColor
            elide: Text.ElideRight
        }

        StyledSwitch {
            id: sw
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.boolValue(row.keyName, row.fallbackValue)

            onToggled: function(checked) {
                ConfigStore.setValue(row.keyName, checked)
                ConfigStore.save()
            }
        }
    }

    component StyledSwitch: Item {
        id: control

        signal toggled(bool checked)

        property bool checked: false

        width: 48
        height: 26

        Rectangle {
            id: track

            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            width: 40
            height: 24
            radius: 12
            color: control.checked ? Theme.accentColor : Theme.componentBgColor
            border.width: 1
            border.color: control.checked ? Theme.accentColor : Theme.inputBorderColor

            Behavior on color {
                ColorAnimation { duration: 180; easing.type: Easing.InOutQuad }
            }
        }

        Rectangle {
            id: knob

            width: 18
            height: 18
            radius: 9
            x: control.checked ? 22 : 6
            y: 3
            color: Theme.cardBgColor
            border.width: 0

            Behavior on x {
                NumberAnimation { duration: 180; easing.type: Easing.InOutQuad }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: control.toggled(!control.checked)
        }
    }

    component LockscreenWallpaperRow: Item {
        id: row

        property string title: ""
        property string description: ""
        property string keyName: ""

        property int wallpaperVersion: 0

        height: 60

        function cleanHome() {
            return backend.homeDirectory || "";
        }

        function effectiveSource() {
            wallpaperVersion;
            const explicit = String(ConfigStore.value(row.keyName, "")).trim();
            if (explicit.length > 0 && explicit !== "null" && explicit !== "undefined") {
                return explicit.startsWith("/") ? "file://" + explicit : explicit;
            }
            const deskWp = String(ConfigStore.value("wallpaperPath", "")).trim();
            if (deskWp.length > 0 && deskWp !== "null" && deskWp !== "undefined") {
                return deskWp.startsWith("/") ? "file://" + deskWp : deskWp;
            }
            const detected = backend.detectActiveWallpaper();
            if (detected.length > 0) {
                return "file://" + detected;
            }
            return "";
        }

        Item {
            id: wpContainer
            width: 80
            height: 48
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Theme.componentBgColor
                border.width: 1
                border.color: wpMouseArea.containsMouse ? Theme.accentColor : Theme.inputBorderColor
                Behavior on border.color { ColorAnimation { duration: 150 } }
                clip: true

                Image {
                    id: wpThumbnail
                    anchors.fill: parent
                    source: row.effectiveSource()
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    visible: status === Image.Ready

                    layer.enabled: String(ConfigStore.value(row.keyName, "")).trim().length === 0
                    layer.effect: MultiEffect {
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blurMax: 8
                        blur: 0.6
                        brightness: -0.1
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: wpThumbnail.status !== Image.Ready
                    text: "Default"
                    font.family: Theme.textFontFamily
                    font.pixelSize: 11
                    color: Theme.subtleTextColor
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.40)
                    opacity: wpMouseArea.containsMouse ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Change"
                        font.family: Theme.textFontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: "#ffffff"
                    }
                }
            }

            MouseArea {
                id: wpMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: lockscreenWallpaperFileDialog.openForPath(field.text)
            }

            DropArea {
                anchors.fill: parent
                onDropped: function(drop) {
                    let p = "";
                    if (drop.hasUrls && drop.urls.length > 0) {
                        p = drop.urls[0].toString();
                    } else if (drop.hasText) {
                        p = drop.text.trim();
                    }
                    if (p.length > 0) {
                        if (p.startsWith("file://")) {
                            p = decodeURIComponent(p.substring(7));
                        }
                        row.setPath(p);
                    }
                }
            }
        }

        Column {
            anchors.left: wpContainer.right
            anchors.leftMargin: 16
            anchors.right: controlsRow.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Text {
                text: row.title
                font.family: Theme.textFontFamily
                font.pixelSize: 18
                color: Theme.textColor
            }

            Text {
                text: row.description
                font.family: Theme.textFontFamily
                font.pixelSize: 13
                color: Theme.subtleTextColor
                elide: Text.ElideRight
                width: parent.width
            }
        }

        Row {
            id: controlsRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            ConfigTextField {
                id: field
                width: Math.max(160, Math.min(260, (row.width - 320) / 2))
                height: 36
                placeholderText: {
                    const det = backend.detectActiveWallpaper();
                    return det.length > 0 ? "Default: " + det.split('/').pop() + " (blurred)" : "Default: Desktop wallpaper (blurred)"
                }
                textPixelSize: 13

                Component.onCompleted: {
                    text = String(ConfigStore.value(row.keyName, ""))
                }

                onAccepted: row.commit()
                onEditingFinished: row.commit()
            }

            ButtonLike {
                text: "Browse"
                primary: true
                onClicked: lockscreenWallpaperFileDialog.openForPath(field.text)
            }

            ButtonLike {
                text: "Clear"
                enabled: field.text.length > 0
                onClicked: row.clear()
            }
        }

        function setPath(path) {
            field.text = path;
            commit();
        }

        function clear() {
            field.text = "";
            ConfigStore.remove(row.keyName);
            ConfigStore.save();
            wallpaperVersion++;
        }

        function commit() {
            const val = field.text.trim();
            if (val.length === 0) {
                clear();
            } else {
                ConfigStore.setValue(row.keyName, val);
                ConfigStore.save();
                wallpaperVersion++;
            }
        }
    }

}
