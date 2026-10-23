import TideIsland 1.0
import QtQuick
import QtQuick.Controls

Rectangle {
    id: root

    color: Theme.cardBgColor
    radius: 16
    border.width: 1
    border.color: Theme.splitLineColor
    implicitHeight: paletteColumn.implicitHeight + 36

    function boolValue(key, fallback) {
        const val = ConfigStore.value(key, fallback);
        return val === undefined || val === null ? fallback : Boolean(val);
    }

    Column {
        id: paletteColumn

        anchors.top: parent.top
        anchors.topMargin: 18
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.right: parent.right
        anchors.rightMargin: 18
        spacing: 16

        Item {
            width: parent.width
            height: 49

            Text {
                id: paletteToggleTitle
                text: "Dynamic Color Palette"
                font.family: Theme.textFontFamily
                font.pixelSize: 18
                color: Theme.textColor
                anchors.top: parent.top
                anchors.left: parent.left
            }

            Text {
                text: "Sync island and controls with system theme (Matugen / colors.json)"
                font.family: Theme.textFontFamily
                font.pixelSize: 14
                anchors.top: paletteToggleTitle.bottom
                anchors.topMargin: 5
                anchors.left: paletteToggleTitle.left
                color: Theme.subtleTextColor
            }

            StyledSwitch {
                id: paletteSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.boolValue("colorPaletteEnabled", true)
                onToggled: function(val) {
                    checked = val;
                    ConfigStore.setValue("colorPaletteEnabled", val);
                    ConfigStore.save();
                }
            }
        }

        SplitLine { width: parent.width }

        Item {
            width: parent.width
            height: 49

            Text {
                id: colorsPathTitle
                text: "Colors File Path"
                font.family: Theme.textFontFamily
                font.pixelSize: 18
                color: Theme.textColor
                anchors.top: parent.top
                anchors.left: parent.left
            }

            Text {
                text: "Custom colors.json path (empty for ~/.config/tide-island/colors.json)"
                font.family: Theme.textFontFamily
                font.pixelSize: 14
                anchors.top: colorsPathTitle.bottom
                anchors.topMargin: 5
                anchors.left: colorsPathTitle.left
                color: Theme.subtleTextColor
            }

            ConfigTextField {
                id: colorsPathField
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 260
                height: 36
                placeholderText: "~/.config/tide-island/colors.json"

                Component.onCompleted: {
                    text = String(ConfigStore.value("colorsFilePath", ""))
                }

                onAccepted: commit()
                onEditingFinished: commit()

                function commit() {
                    ConfigStore.setValue("colorsFilePath", text.trim())
                    ConfigStore.save()
                }
            }
        }

        SplitLine { width: parent.width }

        Column {
            id: matugenGuide
            width: parent.width
            spacing: 12

            property bool copiedSnippet: false
            property bool copiedTemplate: false
            property bool templateInstalled: backend.isMatugenTemplateInstalled()
            property string selectedTab: "toml"

            Timer {
                id: matugenCopyResetTimer
                interval: 1800
                repeat: false
                onTriggered: {
                    matugenGuide.copiedSnippet = false;
                    matugenGuide.copiedTemplate = false;
                }
            }

            Item {
                width: parent.width
                height: 32

                Text {
                    text: "Matugen System Palette Setup"
                    font.family: Theme.textFontFamily
                    font.pixelSize: 18
                    color: Theme.textColor
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Rectangle {
                        width: installBtnText.implicitWidth + 24
                        height: 32
                        radius: 8
                        color: matugenGuide.templateInstalled
                            ? Theme.cardBgColor
                            : (installMouse.containsMouse ? Theme.buttonHoverColor : Theme.buttonColor)
                        border.width: 1
                        border.color: matugenGuide.templateInstalled ? Theme.splitLineColor : Theme.buttonColor

                        Text {
                            id: installBtnText
                            anchors.centerIn: parent
                            text: matugenGuide.templateInstalled ? "✓ Template Installed" : "Install Template"
                            color: matugenGuide.templateInstalled ? Theme.textColor : Theme.buttonTextColor
                            font.family: Theme.textFontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: installMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (backend.installMatugenTemplate()) {
                                    matugenGuide.templateInstalled = true;
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: copyBtnText.implicitWidth + 24
                        height: 32
                        radius: 8
                        color: (matugenGuide.copiedSnippet || matugenGuide.copiedTemplate)
                            ? Theme.buttonColor
                            : (copyMouse.containsMouse ? Theme.mutedButtonHoverColor : Theme.mutedButtonColor)
                        border.width: 1
                        border.color: Theme.splitLineColor

                        Text {
                            id: copyBtnText
                            anchors.centerIn: parent
                            text: {
                                if (matugenGuide.copiedSnippet || matugenGuide.copiedTemplate)
                                    return "Copied!";
                                return matugenGuide.selectedTab === "toml" ? "Copy TOML" : "Copy Template JSON";
                            }
                            color: (matugenGuide.copiedSnippet || matugenGuide.copiedTemplate)
                                ? Theme.buttonTextColor
                                : Theme.mutedButtonTextColor
                            font.family: Theme.textFontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: copyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (matugenGuide.selectedTab === "toml") {
                                    if (backend.copyToClipboard(backend.matugenTomlSnippet())) {
                                        matugenGuide.copiedSnippet = true;
                                        matugenCopyResetTimer.restart();
                                    }
                                } else {
                                    if (backend.copyToClipboard(backend.matugenTemplateContent())) {
                                        matugenGuide.copiedTemplate = true;
                                        matugenCopyResetTimer.restart();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: "Sync island colors automatically with your wallpaper via Matugen. Click 'Install Template' to place the template in ~/.config/matugen/templates/, then ensure the block below is in ~/.config/matugen/config.toml:"
                font.family: Theme.textFontFamily
                font.pixelSize: 14
                color: Theme.subtleTextColor
                wrapMode: Text.WordWrap
            }

            Row {
                spacing: 8

                Rectangle {
                    width: 130
                    height: 28
                    radius: 6
                    color: matugenGuide.selectedTab === "toml" ? Theme.cardBgColor : Theme.componentBgColor
                    border.width: 1
                    border.color: matugenGuide.selectedTab === "toml" ? Theme.accentColor : Theme.inputBorderColor

                    Text {
                        anchors.centerIn: parent
                        text: "1. config.toml"
                        font.family: Theme.textFontFamily
                        font.pixelSize: 13
                        font.weight: matugenGuide.selectedTab === "toml" ? Font.DemiBold : Font.Normal
                        color: matugenGuide.selectedTab === "toml" ? Theme.textColor : Theme.secondaryTextColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: matugenGuide.selectedTab = "toml"
                    }
                }

                Rectangle {
                    width: 160
                    height: 28
                    radius: 6
                    color: matugenGuide.selectedTab === "template" ? Theme.cardBgColor : Theme.componentBgColor
                    border.width: 1
                    border.color: matugenGuide.selectedTab === "template" ? Theme.accentColor : Theme.inputBorderColor

                    Text {
                        anchors.centerIn: parent
                        text: "2. Template JSON"
                        font.family: Theme.textFontFamily
                        font.pixelSize: 13
                        font.weight: matugenGuide.selectedTab === "template" ? Font.DemiBold : Font.Normal
                        color: matugenGuide.selectedTab === "template" ? Theme.textColor : Theme.secondaryTextColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: matugenGuide.selectedTab = "template"
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: Math.min(230, Math.max(70, codeFlick.contentHeight + 20))
                radius: 8
                color: Theme.inputBgColor
                border.width: 1
                border.color: Theme.inputBorderColor
                clip: true

                Flickable {
                    id: codeFlick
                    anchors.fill: parent
                    anchors.margins: 10
                    contentWidth: codeText.implicitWidth
                    contentHeight: codeText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    Text {
                        id: codeText
                        text: matugenGuide.selectedTab === "toml"
                            ? backend.matugenTomlSnippet()
                            : backend.matugenTemplateContent()
                        color: Theme.textColor
                        font.family: "monospace"
                        font.pixelSize: 12
                        lineHeight: 1.2
                    }
                }
            }

            Text {
                width: parent.width
                text: "• Template path: ~/.config/matugen/templates/tide-island-colors.json\n• Generated colors: ~/.config/tide-island/colors.json\n• Battery colors (charging, high, medium, low, critical) are automatically harmonized with your theme.\n• Background transparency is independently preserved using the 'Background Transparency' slider in General."
                font.family: Theme.textFontFamily
                font.pixelSize: 13
                color: Theme.subtleTextColor
                wrapMode: Text.WordWrap
                lineHeight: 1.3
            }
        }
    }

    component SplitLine: Rectangle {
        height: 1
        color: Theme.splitLineColor
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
            onClicked: {
                control.checked = !control.checked;
                control.toggled(control.checked);
            }
        }
    }
}
