import QtQuick
import IslandBackend

Rectangle {
    id: root

    property string title: ""
    property string subtitle: ""
    property string iconText: ""
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property bool active: false
    property bool clickable: true
    property real iconBubbleSize: 34
    property real cardRadius: 16

    property color activeBorderColor: StyleTokens.accent
    property color inactiveBorderColor: StyleTokens.inputBorder
    property color activeCardColor: StyleTokens.withAlpha(StyleTokens.accent, 0.15)
    property color inactiveCardColor: StyleTokens.cardFill
    property color hoverCardColor: StyleTokens.moduleHover

    property color activeIconBubbleColor: StyleTokens.accent
    property color inactiveIconBubbleColor: StyleTokens.module
    property color activeIconColor: StyleTokens.textOnAccent
    property color inactiveIconColor: StyleTokens.textPrimary

    default property alias bottomContent: bottomSlot.data
    property alias rightAccessory: rightSlot.data

    signal clicked()

    radius: cardRadius
    clip: true
    color: active ? activeCardColor : (cardMouse.containsMouse ? hoverCardColor : inactiveCardColor)
    border.width: 1
    border.color: active ? activeBorderColor : (cardMouse.containsMouse ? StyleTokens.surfaceBorder : inactiveBorderColor)

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        enabled: root.clickable
        hoverEnabled: root.clickable
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }

    Item {
        id: contentContainer
        anchors.fill: parent
        anchors.margins: 10

        // Top Row: Icon + Title/Subtitle Column + Right Slot
        Item {
            id: topRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: root.iconBubbleSize

            // Left Icon Bubble
            Rectangle {
                id: iconBubble
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.iconBubbleSize
                height: root.iconBubbleSize
                radius: width / 2
                color: root.active ? root.activeIconBubbleColor : root.inactiveIconBubbleColor

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: root.iconText
                    font.pixelSize: 15
                    font.family: root.iconFontFamily
                    color: root.active ? root.activeIconColor : root.inactiveIconColor
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
            }

            // Title & Subtitle Column
            Column {
                id: textColumn
                anchors.left: iconBubble.right
                anchors.leftMargin: 10
                anchors.right: rightSlot.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    width: parent.width
                    text: root.title
                    color: root.active ? StyleTokens.textPrimary : StyleTokens.textSecondary
                    font.pixelSize: 12
                    font.family: root.textFontFamily
                    font.weight: root.active ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.subtitle
                    color: StyleTokens.textMuted
                    font.pixelSize: 10
                    font.family: root.textFontFamily
                    elide: Text.ElideRight
                    visible: text.length > 0
                }
            }

            // Right Accessory Slot (Checkmark, Pill, Chevron, etc.)
            Row {
                id: rightSlot
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
            }
        }

        // Bottom Expandable Slot (e.g., volume slider)
        Item {
            id: bottomSlot
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: topRow.bottom
            anchors.bottom: parent.bottom
        }
    }
}
