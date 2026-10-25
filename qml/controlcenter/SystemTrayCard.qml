import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import IslandBackend

Item {
    id: root

    readonly property var userConfig: UserConfig
    readonly property var trayItems: SystemTray.items.values
    readonly property int itemCount: trayItems ? trayItems.length : 0
    readonly property bool hasItems: itemCount > 0

    readonly property color cardAccent: StyleTokens.accent
    readonly property color buttonBg: StyleTokens.cardFill
    readonly property color buttonBgHover: StyleTokens.cardFillHover
    readonly property color buttonBgPressed: StyleTokens.cardFillActive

    width: parent ? parent.width : 180
    height: 80

    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: StyleTokens.radiusModule
        color: StyleTokens.clearBlack
        clip: true

        MatteSurface {
            anchors.fill: parent
            radius: parent.radius
        }

        // Top Header Row
        Item {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.top: parent.top
            anchors.topMargin: 11
            height: 20

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Tray"
                    color: StyleTokens.textPrimary
                    font.pixelSize: 12
                    font.family: userConfig.textFontFamily
                    font.weight: Font.DemiBold
                }
            }

            // Item count pill badge
            Rectangle {
                visible: root.hasItems
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 18
                width: Math.max(18, countText.implicitWidth + 10)
                radius: 9
                color: StyleTokens.cardFillActive
                border.color: StyleTokens.withAlpha(StyleTokens.white, 0.08)
                border.width: 1

                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: root.itemCount.toString()
                    font.pixelSize: 10
                    font.family: userConfig.textFontFamily
                    font.weight: Font.Bold
                    color: StyleTokens.textSecondary
                }
            }
        }

        // Empty state when no tray items are present
        Row {
            visible: !root.hasItems
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            spacing: 6
            opacity: 0.55

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf115"
                color: StyleTokens.textDisabled
                font.pixelSize: 12
                font.family: userConfig.iconFontFamily
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "No items"
                color: StyleTokens.textDisabled
                font.pixelSize: 11
                font.family: userConfig.textFontFamily
                font.weight: Font.Medium
            }
        }

        // Content Area: Horizontal Scrolling Tray
        Item {
            visible: root.hasItems
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            height: 36
            clip: true

            Flickable {
                id: trayFlickable
                anchors.fill: parent
                contentWidth: trayRow.implicitWidth
                contentHeight: height
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                clip: true

                Row {
                    id: trayRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Repeater {
                        model: root.trayItems

                        delegate: Item {
                            id: trayDelegate
                            width: 34
                            height: 34
                            scale: trayMouse.pressed ? 0.90 : (trayMouse.containsMouse ? 1.08 : 1.0)

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 9
                                color: trayMouse.pressed
                                    ? root.buttonBgPressed
                                    : (trayMouse.containsMouse ? root.buttonBgHover : StyleTokens.transparent)
                                border.color: modelData.status === 2
                                    ? root.cardAccent
                                    : (trayMouse.containsMouse ? StyleTokens.withAlpha(StyleTokens.white, 0.12) : StyleTokens.transparent)
                                border.width: 1

                                Behavior on color {
                                    ColorAnimation { duration: 120 }
                                }

                                Image {
                                    anchors.centerIn: parent
                                    width: 20
                                    height: 20
                                    sourceSize: Qt.size(40, 40)
                                    source: modelData.icon || ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                    mipmap: true
                                }
                            }

                            MouseArea {
                                id: trayMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor

                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.LeftButton) {
                                        modelData.activate();
                                    } else if (mouse.button === Qt.RightButton || mouse.button === Qt.MiddleButton) {
                                        modelData.secondaryActivate();
                                    }
                                }

                                onWheel: function(wheel) {
                                    modelData.scroll(wheel.angleDelta.y);
                                }
                            }

                            // Tooltip on hover
                            Rectangle {
                                id: tooltipBox
                                visible: trayMouse.containsMouse && tooltipLabel.text !== ""
                                z: 999
                                anchors.bottom: parent.top
                                anchors.bottomMargin: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: tooltipLabel.implicitWidth + 14
                                height: 20
                                radius: 6
                                color: StyleTokens.prompt
                                border.color: StyleTokens.inputBorder
                                border.width: 1

                                Text {
                                    id: tooltipLabel
                                    anchors.centerIn: parent
                                    text: modelData.tooltipTitle || modelData.title || modelData.id || ""
                                    color: StyleTokens.textPrimaryBright
                                    font.pixelSize: 10
                                    font.family: userConfig.textFontFamily
                                    font.weight: Font.Medium
                                }
                            }
                        }
                    }
                }
            }

            // Left fade gradient when scrolled
            Rectangle {
                visible: trayFlickable.contentX > 2
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 14
                z: 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: StyleTokens.module }
                    GradientStop { position: 1.0; color: StyleTokens.transparent }
                }
            }

            // Right fade gradient when content overflows
            Rectangle {
                visible: trayFlickable.contentWidth > trayFlickable.width && (trayFlickable.contentX < trayFlickable.contentWidth - trayFlickable.width - 2)
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 14
                z: 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: StyleTokens.transparent }
                    GradientStop { position: 1.0; color: StyleTokens.module }
                }
            }

            // Wheel scroll support on entire flickable area
            MouseArea {
                anchors.fill: parent
                z: 1
                propagateComposedEvents: true
                acceptedButtons: Qt.NoButton
                onWheel: function(wheel) {
                    trayFlickable.contentX = Math.max(0, Math.min(trayFlickable.contentWidth - trayFlickable.width, trayFlickable.contentX - wheel.angleDelta.y));
                }
            }
        }
    }
}
