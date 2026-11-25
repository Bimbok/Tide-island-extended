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
            root.closeRequested();
        }

        onExecuteRequested: function(item) {
            root.closeRequested();
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

        // Search Input Bar
        Rectangle {
            id: searchBar
            width: parent.width
            height: 48
            radius: StyleTokens.radiusCard
            color: StyleTokens.input
            border.width: 1
            border.color: searchInput.activeFocus ? StyleTokens.accent : StyleTokens.inputBorder

            Behavior on border.color { ColorAnimation { duration: 150 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 14
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
                        text: "Spotlight Search, math, files, or actions..."
                        color: StyleTokens.textMuted
                        font.family: root.textFontFamily
                        font.pixelSize: 15
                        visible: !searchInput.text && !searchInput.inputMethodComposing
                    }
                }

                // Clear button
                Rectangle {
                    width: 22
                    height: 22
                    radius: 11
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

                // Esc shortcut badge
                Rectangle {
                    width: 32
                    height: 20
                    radius: 6
                    color: StyleTokens.cardFill
                    border.width: 1
                    border.color: StyleTokens.surfaceBorder
                    Layout.alignment: Qt.AlignVCenter

                    Text {
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

        // Hero Calculator / Conversion Banner (when math detected)
        Rectangle {
            id: heroCalcBanner
            width: parent.width
            height: visible ? 58 : 0
            radius: StyleTokens.radiusCard
            visible: engine.calcResult !== null
            clip: true
            color: StyleTokens.cardFillActive
            border.width: 1
            border.color: StyleTokens.accent

            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Text {
                    text: "\uf1ec"
                    font.family: root.iconFontFamily
                    font.pixelSize: 22
                    color: StyleTokens.accent
                    Layout.alignment: Qt.AlignVCenter
                }

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    Text {
                        text: engine.calcResult ? engine.calcResult.title : ""
                        font.family: root.textFontFamily
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        color: StyleTokens.textPrimary
                    }

                    Text {
                        text: engine.calcResult ? engine.calcResult.subtitle : ""
                        font.family: root.textFontFamily
                        font.pixelSize: 12
                        color: StyleTokens.textSecondary
                    }
                }

                Rectangle {
                    radius: StyleTokens.radiusPill
                    color: StyleTokens.accentSoft
                    implicitWidth: copyPillText.implicitWidth + 18
                    implicitHeight: 26
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: copyPillText
                        anchors.centerIn: parent
                        text: "Enter to Copy"
                        font.family: root.textFontFamily
                        font.pixelSize: 11
                        font.weight: Font.Medium
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

        // Results List
        ListView {
            id: resultsList
            width: parent.width
            height: parent.height - searchBar.height - (heroCalcBanner.visible ? heroCalcBanner.height + 10 : 0) - 10
            clip: true
            model: engine.allResults
            spacing: 4

            delegate: Rectangle {
                id: resultRow
                required property var modelData
                required property int index

                readonly property bool isSelected: engine.selectedIndex === index
                width: resultsList.width
                height: 44
                radius: StyleTokens.radiusModule
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
                        width: 28
                        height: 28
                        Layout.alignment: Qt.AlignVCenter

                        IconImage {
                            id: rowAppIcon
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            visible: resultRow.modelData.type === "app" || resultRow.modelData.type === "file"
                            source: visible ? (Quickshell.iconPath(resultRow.modelData.icon || (resultRow.modelData.type === "file" ? "text-x-generic" : "application-x-executable"), true) || "") : ""
                            asynchronous: true
                            mipmap: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: (resultRow.modelData.type === "app" || resultRow.modelData.type === "file") && (!rowAppIcon.source || rowAppIcon.source.toString() === "")
                            text: String(resultRow.modelData.title || "?").charAt(0).toLocaleUpperCase()
                            color: StyleTokens.textPrimary
                            font.family: root.textFontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: resultRow.modelData.type !== "app" && resultRow.modelData.type !== "file"
                            text: resultRow.modelData.icon || "\uf002"
                            font.family: root.iconFontFamily
                            font.pixelSize: 16
                            color: resultRow.isSelected ? StyleTokens.accent : StyleTokens.textSecondary
                        }
                    }

                    // Title & Subtitle
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

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

                    // Category Pill badge
                    Rectangle {
                        implicitWidth: categoryText.implicitWidth + 14
                        implicitHeight: 20
                        radius: 6
                        color: resultRow.isSelected ? StyleTokens.cardFill : StyleTokens.cardFillHover
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
