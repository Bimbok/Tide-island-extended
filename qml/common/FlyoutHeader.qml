import QtQuick
import IslandBackend

Item {
    id: root

    property string title: ""
    property string heroFontFamily: ""
    property string textFontFamily: ""
    property string iconFontFamily: ""

    default property alias actions: rightActions.data

    implicitHeight: 24
    width: parent ? parent.width : 286

    Text {
        id: titleLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        color: StyleTokens.textPrimary
        font.pixelSize: 15
        font.family: root.heroFontFamily
        font.weight: Font.Bold
    }

    Row {
        id: rightActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
    }
}
