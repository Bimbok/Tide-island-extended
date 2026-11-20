import QtQuick
import IslandBackend

Rectangle {
    id: root

    property var model: []
    property string currentId: ""
    property int currentIndex: 0
    property string iconFontFamily: ""
    property string textFontFamily: ""

    property color accentColor: StyleTokens.accent
    property color activeTextColor: StyleTokens.textOnAccent
    property color inactiveTextColor: StyleTokens.textSecondary
    property color hoverColor: StyleTokens.moduleHover

    signal tabSelected(string id, int index)

    implicitHeight: 36
    implicitWidth: 280
    radius: height / 2
    color: StyleTokens.input
    border.width: 1
    border.color: StyleTokens.inputBorder
    clip: true

    Row {
        id: tabsRow
        anchors.fill: parent

        Repeater {
            model: root.model

            delegate: Rectangle {
                id: tabDelegate
                required property var modelData
                required property int index

                readonly property string tabId: typeof modelData === "object" ? String(modelData.id !== undefined ? modelData.id : "") : String(modelData)
                readonly property string tabLabel: typeof modelData === "object" ? (modelData.label !== undefined ? modelData.label : modelData.id) : String(modelData)
                readonly property string tabIcon: typeof modelData === "object" ? (modelData.icon || "") : ""
                readonly property string tabBadge: typeof modelData === "object" ? (modelData.badge || "") : ""
                readonly property bool isSelected: root.currentId !== ""
                    ? root.currentId === tabId
                    : root.currentIndex === index

                width: tabsRow.width / Math.max(1, (root.model ? (root.model.length || 0) : 1))
                height: tabsRow.height
                radius: root.radius
                color: isSelected ? root.accentColor : (tabMouse.containsMouse ? root.hoverColor : StyleTokens.transparent)

                Behavior on color { ColorAnimation { duration: 140 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tabDelegate.tabIcon
                        font.pixelSize: 12
                        font.family: root.iconFontFamily
                        color: tabDelegate.isSelected ? root.activeTextColor : root.inactiveTextColor
                        visible: tabDelegate.tabIcon.length > 0
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tabDelegate.tabLabel + (tabDelegate.tabBadge.length > 0 ? " " + tabDelegate.tabBadge : "")
                        font.pixelSize: 11
                        font.family: root.textFontFamily
                        font.weight: tabDelegate.isSelected ? Font.DemiBold : Font.Normal
                        color: tabDelegate.isSelected ? root.activeTextColor : root.inactiveTextColor
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                }

                MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.currentId = tabDelegate.tabId;
                        root.currentIndex = tabDelegate.index;
                        root.tabSelected(tabDelegate.tabId, tabDelegate.index);
                    }
                }
            }
        }
    }
}
