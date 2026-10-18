import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import IslandBackend
import "../controlcenter"

Item {
    id: root

    readonly property var userConfig: UserConfig

    property var notificationModel: null
    property string iconFontFamily: userConfig.iconFontFamily
    property string textFontFamily: userConfig.textFontFamily
    property string heroFontFamily: userConfig.heroFontFamily

    readonly property real headerHeight: 28
    readonly property real listTopGap: 9
    readonly property real cardHeight: 49
    readonly property real cardRadius: 16
    readonly property real cardGap: 7
    readonly property int maxVisibleItems: 3
    readonly property int itemCount: notificationModel ? notificationModel.count : 0
    readonly property bool hasNotifications: itemCount > 0
    readonly property real rawListContentHeight: hasNotifications
        ? itemCount * cardHeight + (itemCount - 1) * cardGap
        : 0
    readonly property real listContentHeight: Math.min(
        rawListContentHeight,
        maxVisibleItems * cardHeight + (maxVisibleItems - 1) * cardGap
    )

    Item {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.headerHeight

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            spacing: 8

            Item {
                width: 18
                height: 18

                Shape {
                    width: 24
                    height: 24
                    scale: 0.75
                    transformOrigin: Item.TopLeft
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: StyleTokens.transparent
                        strokeColor: StyleTokens.textSecondary
                        strokeWidth: 1.8
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin

                        PathSvg {
                            path: "M3.7 8.2V3.9 M3.7 3.9H8 M3.7 3.9l3 3 M4 12a8.3 8.3 0 1 0 2.7-6.1"
                        }
                    }

                    ShapePath {
                        fillColor: StyleTokens.transparent
                        strokeColor: StyleTokens.textSecondary
                        strokeWidth: 1.8
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin

                        PathSvg {
                            path: "M12 7.5V12l3 1.8"
                        }
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Notification History"
                textFormat: Text.PlainText
                color: StyleTokens.textPrimaryBright
                font.pixelSize: 15
                font.family: root.textFontFamily
                font.weight: Font.Bold
                font.letterSpacing: 0.1
            }
        }
    }

    Item {
        id: listViewport

        anchors.top: header.bottom
        anchors.topMargin: root.listTopGap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true

        Text {
            visible: !root.hasNotifications
            anchors.centerIn: parent
            text: "No notifications"
            textFormat: Text.PlainText
            color: StyleTokens.textMuted
            font.pixelSize: 10
            font.family: root.textFontFamily
            font.weight: Font.Medium
        }

        ListView {
            id: listView

            anchors.fill: parent
            visible: root.hasNotifications
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: root.notificationModel
            currentIndex: -1
            spacing: root.cardGap

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                    if (count > 0) {
                        currentIndex = (currentIndex + 1) % count;
                        positionViewAtIndex(currentIndex, ListView.Contain);
                    }
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                    if (count > 0) {
                        currentIndex = currentIndex <= 0 ? count - 1 : currentIndex - 1;
                        positionViewAtIndex(currentIndex, ListView.Contain);
                    }
                    event.accepted = true;
                } else if (event.key === Qt.Key_Delete) {
                    if (currentIndex >= 0 && currentIndex < count) {
                        const item = model.get(currentIndex);
                        if (item && item.id !== undefined) {
                            SystemServices.closeNotification(item.id, 2);
                        }
                    }
                    event.accepted = true;
                }
            }

            remove: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        property: "opacity"
                        to: 0
                        duration: 170
                        easing.type: Easing.InOutCubic
                    }

                    NumberAnimation {
                        property: "scale"
                        to: 0.94
                        duration: 190
                        easing.type: Easing.InOutCubic
                    }
                }
            }

            removeDisplaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: 260
                    easing.type: Easing.OutCubic
                }
            }

            ScrollBar.vertical: ScrollBar {
                active: listView.moving || listView.dragging
                policy: ScrollBar.AsNeeded
                width: 3

                contentItem: Rectangle {
                    radius: 1.5
                    color: StyleTokens.textMuted
                }

                background: Rectangle {
                    color: StyleTokens.transparent
                }
            }

            delegate: Item {
                id: delegateItem

                width: listView.width
                height: root.cardHeight

                readonly property string titleText: model.summary !== ""
                    ? model.summary
                    : "Notification"
                readonly property string bodyText: model.body !== "" && model.body !== model.summary
                    ? model.body
                    : ""
                readonly property bool hasAvatar: (model.imagePath && (model.imagePath.startsWith("/") || model.imagePath.startsWith("file://")))
                    || (model.appIcon && (model.appIcon.startsWith("/") || model.appIcon.startsWith("file://")))
                readonly property string resolvedAppIcon: {
                    if (model.imagePath && (model.imagePath.startsWith("/") || model.imagePath.startsWith("file://")))
                        return model.imagePath;
                    if (model.appIcon) {
                        const p = Quickshell.iconPath(model.appIcon, true);
                        if (p !== "") return p;
                        if (model.appIcon.startsWith("/") || model.appIcon.startsWith("file://") || model.appIcon.startsWith("image://")) return model.appIcon;
                    }
                    if (model.imagePath && !model.imagePath.startsWith("/") && !model.imagePath.startsWith("file://")) {
                        const p = Quickshell.iconPath(model.imagePath, true);
                        if (p !== "") return p;
                    }
                    if (model.appName) {
                        const p = Quickshell.iconPath(model.appName.toLowerCase(), true);
                        if (p !== "") return p;
                    }
                    return "";
                }
                readonly property bool hasImage: model.imagePath !== undefined && model.imagePath !== "" && (model.imagePath.startsWith("/") || model.imagePath.startsWith("file://"))
                readonly property bool isCritical: model.urgency === 2

                MatteSurface {
                    anchors.fill: parent
                    radius: root.cardRadius
                    hovered: cardMouse.containsMouse || listView.currentIndex === index
                    pressed: cardMouse.pressed
                }

                Rectangle {
                    anchors.fill: parent
                    radius: root.cardRadius
                    color: StyleTokens.transparent
                    border.color: delegateItem.isCritical ? StyleTokens.danger : StyleTokens.transparent
                    border.width: 1
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 4
                    anchors.bottomMargin: 4
                    spacing: 10

                    // Circular App icon or avatar
                    Item {
                        width: 28
                        height: 28
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: 14
                            color: StyleTokens.cardFillActive
                            clip: true
                            visible: delegateItem.resolvedAppIcon !== ""
                            border.color: StyleTokens.withAlpha(StyleTokens.white, 0.15)
                            border.width: 1

                            Image {
                                anchors.centerIn: parent
                                width: delegateItem.hasAvatar ? 28 : 18
                                height: delegateItem.hasAvatar ? 28 : 18
                                source: delegateItem.resolvedAppIcon
                                fillMode: delegateItem.hasAvatar ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                                mipmap: true
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 14
                            color: StyleTokens.cardFillActive
                            clip: true
                            visible: delegateItem.resolvedAppIcon === ""
                            border.color: StyleTokens.withAlpha(StyleTokens.white, 0.15)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "\uf0f3"
                                color: delegateItem.isCritical ? StyleTokens.danger : StyleTokens.textSecondary
                                font.pixelSize: 13
                                font.family: root.iconFontFamily
                            }
                        }
                    }

                    // Content text
                    Item {
                        width: parent.width - 28 - (delegateItem.hasImage ? 42 : 0) - (parent.spacing * (delegateItem.hasImage ? 2 : 1))
                        height: parent.height

                        Text {
                            anchors.top: parent.top
                            anchors.topMargin: delegateItem.bodyText !== "" ? 1 : 8
                            width: parent.width
                            height: 18
                            text: (model.count && model.count > 1) ? (delegateItem.titleText + "  (" + model.count + ")") : delegateItem.titleText
                            textFormat: Text.PlainText
                            color: StyleTokens.textPrimaryBright
                            font.pixelSize: 14
                            font.family: root.textFontFamily
                            font.weight: Font.Bold
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: delegateItem.bodyText !== ""
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            width: parent.width
                            height: 16
                            text: delegateItem.bodyText.replace(/\[([^\]]+)\]\(["']?([^)"']+)["']?\)/g, "$1")
                            textFormat: Text.PlainText
                            color: StyleTokens.textSecondary
                            font.pixelSize: 12
                            font.family: root.textFontFamily
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }

                    // Thumbnail image if present
                    Rectangle {
                        visible: delegateItem.hasImage
                        width: 34
                        height: 34
                        radius: 6
                        color: StyleTokens.clearBlack
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: model.imagePath || ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                }

                MouseArea {
                    id: cardMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.notificationModel && index >= 0 && index < root.notificationModel.count)
                            root.notificationModel.remove(index);
                    }
                }
            }
        }
    }
}
