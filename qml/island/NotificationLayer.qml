import QtQuick
import Quickshell
import IslandBackend

Item {
    id: root

    readonly property var userConfig: UserConfig

    property bool showCondition: false
    property int notificationId: 0
    property string appName: ""
    property string appIcon: ""
    property string summary: ""
    property string body: ""
    property var actions: []
    property string imagePath: ""
    property int urgency: 1
    property string iconText: ""
    property bool expanded: false
    property int toggleButton: Qt.LeftButton
    property var configSource: null
    readonly property var activeConfig: configSource || userConfig
    property string iconFontFamily: activeConfig.iconFontFamily
    property string textFontFamily: activeConfig.textFontFamily
    property string heroFontFamily: activeConfig.heroFontFamily

    signal expansionToggleRequested()
    signal actionTriggered(string actionKey)
    signal closeRequested()

    focus: true
    Keys.onEscapePressed: function(event) {
        root.closeRequested();
        event.accepted = true;
    }
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true;
        }
    }

    readonly property string resolvedAppIcon: {
        if (appIcon !== "") {
            const p = Quickshell.iconPath(appIcon, true);
            if (p !== "") return p;
            if (appIcon.startsWith("/") || appIcon.startsWith("file://") || appIcon.startsWith("image://")) return appIcon;
        }
        if (imagePath !== "" && !imagePath.startsWith("/") && !imagePath.startsWith("file://")) {
            const p = Quickshell.iconPath(imagePath, true);
            if (p !== "") return p;
        }
        if (appName !== "") {
            const p = Quickshell.iconPath(appName.toLowerCase(), true);
            if (p !== "") return p;
        }
        return "";
    }
    readonly property bool hasResolvedAppIcon: resolvedAppIcon !== ""
    readonly property bool hasImageAttachment: imagePath !== "" && (imagePath.startsWith("/") || imagePath.startsWith("file://"))
    readonly property bool hasActions: actions && actions.length > 0
    readonly property real actionsHeight: hasActions ? 36 : 0
    readonly property real imageHeight: hasImageAttachment ? 100 : 0

    readonly property string contentText: {
        if (summary !== "" && body !== "" && body !== summary) return summary + "  " + body;
        if (summary !== "") return summary;
        if (body !== "") return body;
        return "New notification";
    }
    readonly property real minimumWidth: 272
    readonly property real compactMaximumWidth: 400
    readonly property real expandedMaximumWidth: 520
    readonly property real maximumWidth: expanded && hasOverflowContent ? expandedMaximumWidth : compactMaximumWidth
    readonly property real iconSlotWidth: 20
    readonly property real contentSpacing: 13
    readonly property real horizontalPadding: 16
    readonly property real compactVerticalPadding: 7
    readonly property real expandedVerticalPadding: 13
    readonly property real verticalPadding: expanded && hasOverflowContent ? expandedVerticalPadding : compactVerticalPadding
    readonly property real compactMaximumContentHeight: 68 - compactVerticalPadding * 2
    readonly property real expandedMaximumContentHeight: 320 - expandedVerticalPadding * 2
    readonly property real textBlockWidthAtMaximum: compactMaximumWidth - horizontalPadding * 2 - iconSlotWidth - contentSpacing
    readonly property real expandedTextBlockWidthAtMaximum: expandedMaximumWidth - horizontalPadding * 2 - iconSlotWidth - contentSpacing
    readonly property real availableWidth: Math.max(0, width - horizontalPadding * 2 - iconSlotWidth - contentSpacing)
    readonly property bool prefersWrappedContent: contentMetrics.advanceWidth > textBlockWidthAtMaximum
    readonly property bool hasOverflowContent: compactContentProbe.lineCount > 2
        || contentMetrics.advanceWidth > textBlockWidthAtMaximum * 2
        || (contentMetrics.advanceWidth > textBlockWidthAtMaximum && compactContentProbe.lineCount <= 1)
        || hasActions
        || hasImageAttachment
    readonly property real compactPreferredWidth: prefersWrappedContent
        ? maximumWidth
        : Math.max(minimumWidth, Math.min(maximumWidth, contentMetrics.advanceWidth + iconSlotWidth + contentSpacing + horizontalPadding * 2))
    readonly property real compactPreferredHeight: prefersWrappedContent ? compactMaximumContentHeight + compactVerticalPadding * 2 : 56
    readonly property real expandedPreferredWidth: expandedMaximumWidth
    readonly property real expandedPreferredHeight: Math.max(
        84,
        Math.min(320, Math.min(expandedMaximumContentHeight, expandedContentProbe.implicitHeight + actionsHeight + imageHeight) + expandedVerticalPadding * 2)
    )
    readonly property real preferredWidth: expanded && hasOverflowContent ? expandedPreferredWidth : compactPreferredWidth
    readonly property real preferredHeight: expanded && hasOverflowContent ? expandedPreferredHeight : compactPreferredHeight

    anchors.fill: parent
    anchors.margins: 0
    opacity: showCondition ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: showCondition ? 280 : 140
            easing.type: Easing.InOutQuad
        }
    }

    TextMetrics {
        id: contentMetrics
        font.family: textFontFamily
        font.pixelSize: userConfig.bodyFontSize
        font.weight: Font.DemiBold
        font.letterSpacing: -0.15
        text: contentText
    }

    Text {
        id: compactContentProbe
        x: -10000
        y: -10000
        height: 0
        opacity: 0
        width: textBlockWidthAtMaximum
        text: contentText
        font.pixelSize: userConfig.bodyFontSize
        font.family: textFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.15
        wrapMode: Text.WordWrap
        lineHeight: 0.95
    }

    Text {
        id: expandedContentProbe
        x: -10000
        y: -10000
        height: 0
        opacity: 0
        width: expandedTextBlockWidthAtMaximum
        text: contentText
        font.pixelSize: userConfig.bodyFontSize
        font.family: textFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.15
        wrapMode: Text.WordWrap
        lineHeight: 1.05
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: horizontalPadding
        anchors.rightMargin: horizontalPadding
        anchors.topMargin: verticalPadding
        anchors.bottomMargin: verticalPadding
        spacing: contentSpacing
        anchors.verticalCenter: parent.verticalCenter

        Item {
            width: iconSlotWidth
            height: iconSlotWidth
            anchors.verticalCenter: parent.verticalCenter

            Image {
                id: appIconImage
                anchors.fill: parent
                visible: root.hasResolvedAppIcon && status !== Image.Error
                source: root.resolvedAppIcon
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
            }

            Text {
                anchors.centerIn: parent
                visible: !root.hasResolvedAppIcon || appIconImage.status === Image.Error
                text: iconText
                color: root.urgency === 2 ? StyleTokens.danger : StyleTokens.textPrimaryBright
                font.pixelSize: userConfig.iconFontSize
                font.family: iconFontFamily
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Item {
            width: parent.width - iconSlotWidth - contentSpacing
            height: parent.height

            Text {
                visible: !(root.expanded && root.hasOverflowContent)
                anchors.verticalCenter: parent.verticalCenter
                text: contentText
                color: StyleTokens.textPrimaryBright
                font.pixelSize: userConfig.bodyFontSize
                font.family: textFontFamily
                font.weight: Font.DemiBold
                font.letterSpacing: -0.15
                width: parent.width
                wrapMode: prefersWrappedContent ? Text.WordWrap : Text.NoWrap
                maximumLineCount: prefersWrappedContent ? 2 : 1
                elide: Text.ElideRight
                lineHeight: 0.95
            }

            Flickable {
                id: expandedFlickable
                visible: root.expanded && root.hasOverflowContent
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: expandedColumn.implicitHeight
                interactive: contentHeight > height

                Column {
                    id: expandedColumn
                    width: expandedFlickable.width
                    spacing: 8

                    Text {
                        id: expandedContentText
                        width: parent.width
                        text: contentText
                        color: StyleTokens.textPrimaryBright
                        font.pixelSize: userConfig.bodyFontSize
                        font.family: textFontFamily
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.15
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                        lineHeight: 1.05
                    }

                    Rectangle {
                        visible: root.hasImageAttachment && imageAttachment.status !== Image.Error
                        width: Math.min(parent.width, 180)
                        height: visible ? 90 : 0
                        radius: 8
                        color: StyleTokens.clearBlack
                        clip: true

                        Image {
                            id: imageAttachment
                            anchors.fill: parent
                            source: root.imagePath
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }

                    Row {
                        visible: root.hasActions
                        spacing: 8

                        Repeater {
                            model: root.actions
                            delegate: Rectangle {
                                id: actionBtn
                                height: 26
                                width: actionLabel.implicitWidth + 20
                                radius: 13
                                color: actionMouse.pressed
                                    ? StyleTokens.accentPressed
                                    : (actionMouse.containsMouse ? StyleTokens.cardFillHover : StyleTokens.cardFillActive)
                                border.color: StyleTokens.withAlpha(StyleTokens.white, 0.18)
                                border.width: 1

                                Text {
                                    id: actionLabel
                                    anchors.centerIn: parent
                                    text: modelData.text || modelData.id
                                    color: StyleTokens.textPrimaryBright
                                    font.pixelSize: 11
                                    font.family: root.textFontFamily
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: actionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.actionTriggered(modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    TapHandler {
        enabled: root.hasOverflowContent
        acceptedButtons: root.toggleButton
        onTapped: root.expansionToggleRequested()
    }
}
