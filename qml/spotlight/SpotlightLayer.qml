pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import IslandBackend
import "../common"

FocusScope {
    id: root

    signal closeRequested
    signal actionTriggered(string actionKey)

    property bool showCondition: false
    property string iconFontFamily: ""
    property string textFontFamily: ""

    readonly property bool showBatteryHero: {
        const q = searchInput.text.trim().toLowerCase();
        if (!q || engine.calcResult !== null) return false;
        if (q.startsWith("clip ") || q.startsWith("cb ")) return false;
        return q === "battery" || q === "power" || q === "power profile" || q === "battery profile"
            || q === "saver" || q === "powersaver" || q === "power-saver"
            || q === "balanced" || q === "performance" || q === "perf"
            || q === "tlp" || q === "powerprofilesctl"
            || (q.length >= 4 && ("battery".startsWith(q) || "power".startsWith(q) || "profile".startsWith(q)));
    }

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: root.showCondition ? 200 : 120
            easing.type: Easing.InOutQuad
        }
    }

    SpotlightEngine {
        id: engine
        active: root.showCondition
        query: searchInput.text

        onActionTriggered: function(key) {
            root.actionTriggered(key);
        }

        onExecuteRequested: function(item) {
            if (!item || item.type !== "action") {
                root.closeRequested();
            }
        }
    }

    function grabKeyboardFocus() {
        root.forceActiveFocus();
        searchInput.forceActiveFocus();
    }

    onShowConditionChanged: {
        if (showCondition) {
            searchInput.text = "";
            focusTimer.restart();
        }
    }

    Timer {
        id: focusTimer
        interval: 16
        repeat: false
        onTriggered: root.grabKeyboardFocus()
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            engine.moveSelection(1);
            resultsList.positionViewAtIndex(engine.selectedIndex, ListView.Contain);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
            engine.moveSelection(-1);
            resultsList.positionViewAtIndex(engine.selectedIndex, ListView.Contain);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            engine.executeSelected();
            event.accepted = true;
        }
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: 14
        anchors.bottomMargin: 12
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 10

        // Search Input Bar (Smooth Capsule Pill)
        Rectangle {
            id: searchBar
            width: parent.width
            height: 50
            radius: height / 2
            color: StyleTokens.input
            border.width: 1
            border.color: searchInput.activeFocus ? StyleTokens.accent : StyleTokens.surfaceBorder

            Behavior on border.color { ColorAnimation { duration: 150 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 16
                spacing: 12

                Text {
                    text: "\uf002"
                    color: searchInput.activeFocus ? StyleTokens.accent : StyleTokens.textMuted
                    font.family: root.iconFontFamily
                    font.pixelSize: 16
                    Layout.alignment: Qt.AlignVCenter
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    color: StyleTokens.textPrimary
                    selectionColor: StyleTokens.accent
                    font.family: root.textFontFamily
                    font.pixelSize: 15
                    font.weight: Font.Normal
                    clip: true

                    Text {
                        anchors.fill: parent
                        text: "Spotlight Search, clipboard, math, files..."
                        color: StyleTokens.textMuted
                        font.family: root.textFontFamily
                        font.pixelSize: 15
                        visible: !searchInput.text && !searchInput.inputMethodComposing
                    }
                }

                // Clear button (Circular Pill)
                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: StyleTokens.cardFillActive
                    visible: searchInput.text.length > 0
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.centerIn: parent
                        text: "\uf00d"
                        font.family: root.iconFontFamily
                        font.pixelSize: 11
                        color: StyleTokens.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchInput.text = "";
                            searchInput.forceActiveFocus();
                        }
                    }
                }

                // Esc shortcut badge (Pill Capsule Badge)
                Rectangle {
                    implicitWidth: escBadgeText.implicitWidth + 16
                    height: 24
                    radius: height / 2
                    color: StyleTokens.cardFill
                    border.width: 1
                    border.color: StyleTokens.surfaceBorder
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: escBadgeText
                        anchors.centerIn: parent
                        text: "ESC"
                        font.family: root.textFontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: StyleTokens.textMuted
                    }
                }
            }
        }

        // Hero Calculator / Conversion Banner (Rounded Card with Soft Glow)
        Rectangle {
            id: heroCalcBanner
            width: parent.width
            height: visible ? 64 : 0
            radius: 20
            visible: engine.calcResult !== null
            clip: true
            color: StyleTokens.cardFillActive
            border.width: 1
            border.color: StyleTokens.surfaceHighlight

            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 14

                // Circular Tinted Calculator Icon
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: StyleTokens.accentSoft
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.centerIn: parent
                        text: "\uf1ec"
                        font.family: root.iconFontFamily
                        font.pixelSize: 18
                        color: StyleTokens.accent
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    Text {
                        text: engine.calcResult ? engine.calcResult.title : ""
                        font.family: root.textFontFamily
                        font.pixelSize: 19
                        font.weight: Font.Bold
                        color: StyleTokens.textPrimaryBright
                    }

                    Text {
                        text: engine.calcResult ? engine.calcResult.subtitle : ""
                        font.family: root.textFontFamily
                        font.pixelSize: 12
                        color: StyleTokens.textSecondary
                    }
                }

                // Enter to Copy Pill
                Rectangle {
                    radius: height / 2
                    color: StyleTokens.accentSoft
                    border.width: 1
                    border.color: StyleTokens.surfaceHighlight
                    implicitWidth: copyPillText.implicitWidth + 20
                    implicitHeight: 28
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: copyPillText
                        anchors.centerIn: parent
                        text: "Enter to Copy"
                        font.family: root.textFontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: StyleTokens.accent
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (engine.calcResult) {
                        engine.executeItem(engine.calcResult);
                    }
                }
            }
        }

        // Hero Battery Profile Card (Reusing Control Center component with lazy Loader)
        Loader {
            id: heroBatteryLoader
            width: parent.width
            height: active && item && item.visible ? 80 : 0
            active: root.showBatteryHero
            visible: active
            clip: true

            Behavior on height {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            sourceComponent: BatteryModeCard {
                width: heroBatteryLoader.width
                height: 80
                cardRadius: 20
                textFontFamily: root.textFontFamily
                iconFontFamily: root.iconFontFamily
            }
        }

        // Results List
        ListView {
            id: resultsList
            width: parent.width
            height: parent.height - searchBar.height - (heroCalcBanner.visible ? heroCalcBanner.height + 10 : 0) - (heroBatteryLoader.height > 0 ? heroBatteryLoader.height + 10 : 0) - 10
            clip: true
            model: engine.allResults
            spacing: 5

            // Minimalistic Empty State
            Item {
                anchors.centerIn: parent
                visible: engine.totalResultCount === 0 && searchInput.text.trim() !== ""
                width: parent.width
                height: 120

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "\uf002"
                        font.family: root.iconFontFamily
                        font.pixelSize: 22
                        color: StyleTokens.textMuted
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No matching results"
                        font.family: root.textFontFamily
                        font.pixelSize: 13
                        color: StyleTokens.textMuted
                    }
                }
            }

            delegate: Rectangle {
                id: resultRow
                required property var modelData
                required property int index

                readonly property bool isSelected: engine.selectedIndex === index
                width: resultsList.width
                height: 48
                radius: 16
                color: isSelected ? StyleTokens.cardFillActive : (rowHover.hovered ? StyleTokens.cardFillHover : "transparent")
                border.width: isSelected ? 1 : 0
                border.color: StyleTokens.surfaceHighlight

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    // Icon (App icon, File icon, or FontAwesome glyph)
                    Item {
                        width: 32
                        height: 32
                        Layout.alignment: Qt.AlignVCenter

                        IconImage {
                            id: rowAppIcon
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            visible: resultRow.modelData.type === "app" || resultRow.modelData.type === "file"
                            source: visible ? (Quickshell.iconPath(resultRow.modelData.icon || (resultRow.modelData.type === "file" ? "text-x-generic" : "application-x-executable"), true) || "") : ""
                            asynchronous: true
                            mipmap: true
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            radius: 14
                            color: StyleTokens.accentSoft
                            visible: (resultRow.modelData.type === "app" || resultRow.modelData.type === "file") && (!rowAppIcon.source || rowAppIcon.source.toString() === "")

                            Text {
                                anchors.centerIn: parent
                                text: String(resultRow.modelData.title || "?").charAt(0).toLocaleUpperCase()
                                color: StyleTokens.accent
                                font.family: root.textFontFamily
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            radius: 14
                            color: resultRow.isSelected ? StyleTokens.accentSoft : StyleTokens.cardFill
                            visible: resultRow.modelData.type !== "app" && resultRow.modelData.type !== "file" && (!resultRow.modelData.imagePath || resultRow.modelData.imagePath === "")

                            Text {
                                anchors.centerIn: parent
                                text: resultRow.modelData.icon || "\uf002"
                                font.family: root.iconFontFamily
                                font.pixelSize: 14
                                color: resultRow.isSelected ? StyleTokens.accent : StyleTokens.textSecondary
                            }
                        }

                        Image {
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            fillMode: Image.PreserveAspectCrop
                            visible: !!resultRow.modelData.imagePath && resultRow.modelData.imagePath !== ""
                            source: visible ? ("file://" + resultRow.modelData.imagePath) : ""
                            asynchronous: true
                        }
                    }

                    // Title & Subtitle
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: resultRow.modelData.title || ""
                            font.family: root.textFontFamily
                            font.pixelSize: 14
                            font.weight: resultRow.isSelected ? Font.DemiBold : Font.Normal
                            color: resultRow.isSelected ? StyleTokens.textPrimaryBright : StyleTokens.textPrimary
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: resultRow.modelData.subtitle || ""
                            font.family: root.textFontFamily
                            font.pixelSize: 11
                            color: StyleTokens.textMuted
                            elide: Text.ElideRight
                        }
                    }

                    // Category Pill badge (Capsule Shape)
                    Rectangle {
                        implicitWidth: categoryText.implicitWidth + 16
                        implicitHeight: 22
                        radius: height / 2
                        color: resultRow.isSelected ? StyleTokens.accentSoft : StyleTokens.cardFillHover
                        border.width: 1
                        border.color: StyleTokens.surfaceBorder
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            id: categoryText
                            anchors.centerIn: parent
                            text: resultRow.modelData.category || "Item"
                            font.family: root.textFontFamily
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            color: resultRow.isSelected ? StyleTokens.accent : StyleTokens.textMuted
                        }
                    }
                }

                HoverHandler {
                    id: rowHover
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        engine.selectedIndex = resultRow.index;
                        if (engine.allResults && resultRow.index < engine.allResults.length) {
                            engine.executeItem(engine.allResults[resultRow.index]);
                        } else {
                            engine.executeItem(resultRow.modelData);
                        }
                    }
                }
            }
        }
    }
}
