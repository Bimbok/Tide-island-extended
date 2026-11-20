import QtQuick
import IslandBackend

Rectangle {
    id: root

    property string text: ""
    property string icon: ""
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property bool active: false
    property bool clickable: true
    property bool highlighted: false

    property color activeColor: StyleTokens.withAlpha(StyleTokens.accent, 0.25)
    property color activeBorderColor: StyleTokens.accent
    property color activeTextColor: StyleTokens.accent

    property color inactiveColor: StyleTokens.cardFill
    property color hoverColor: StyleTokens.moduleHover
    property color inactiveBorderColor: StyleTokens.inputBorder
    property color inactiveTextColor: StyleTokens.textSecondary

    property int fontSize: 10
    property int iconSize: 11
    property int horizontalPadding: 8

    signal clicked()

    implicitHeight: 22
    implicitWidth: contentRow.implicitWidth + horizontalPadding * 2
    radius: height / 2

    color: active || highlighted
        ? activeColor
        : (clickable && mouseArea.containsMouse ? hoverColor : inactiveColor)
    border.width: 1
    border.color: active || highlighted ? activeBorderColor : inactiveBorderColor

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 5

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font.pixelSize: root.iconSize
            font.family: root.iconFontFamily
            color: root.active || root.highlighted
                ? root.activeTextColor
                : (root.clickable && mouseArea.containsMouse ? StyleTokens.textPrimary : root.inactiveTextColor)
            visible: root.icon.length > 0
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.pixelSize: root.fontSize
            font.family: root.textFontFamily
            font.weight: root.active || root.highlighted ? Font.DemiBold : Font.Normal
            color: root.active || root.highlighted
                ? root.activeTextColor
                : (root.clickable && mouseArea.containsMouse ? StyleTokens.textPrimary : root.inactiveTextColor)
            visible: root.text.length > 0
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.clickable
        hoverEnabled: root.clickable
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
