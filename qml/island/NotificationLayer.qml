import QtQuick
import QtQuick.Layouts
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
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.effectiveActions.length > 0) {
                root.actionTriggered(root.effectiveActions[0].id);
                event.accepted = true;
            }
        }
    }

    // --- OTP Extraction & Feedback State ---
    property bool otpCopied: false

    Timer {
        id: otpFeedbackTimer
        interval: 2200
        repeat: false
        onTriggered: root.otpCopied = false
    }

    function extractOtp(title, text) {
        const combined = ((title || "") + " " + (text || "")).trim();
        if (!combined) return "";

        // Explicit pattern: "OTP: 123456", "code is 492019", "verification code 948-201", "PIN: 5821"
        const explicitMatch = combined.match(/(?:otp|code|pin|verification|passcode|token|password)[\s:=#\-]+([0-9]{4,8}|[0-9]{3}[-\s][0-9]{3})\b/i);
        if (explicitMatch && explicitMatch[1]) {
            return explicitMatch[1].replace(/[\s\-]/g, "");
        }

        // Contextual pattern: presence of verification keywords
        const hasContext = /\b(otp|code|verification|verify|pin|passcode|secret|token|auth|2fa|login|confirm|authenticate)\b/i.test(combined);
        if (hasContext) {
            const numbers = combined.match(/\b[0-9]{4,8}\b/g);
            if (numbers && numbers.length > 0) {
                // Prefer 6-digit code (industry standard TOTP/SMS)
                const sixDigit = numbers.find(n => n.length === 6);
                if (sixDigit) return sixDigit;
                const notYear = numbers.find(n => !n.startsWith("202") && !n.startsWith("19"));
                if (notYear) return notYear;
                return numbers[0];
            }
            const split = combined.match(/\b([0-9]{3})[-\s]([0-9]{3})\b/);
            if (split) return split[1] + split[2];
        }
        return "";
    }

    readonly property string extractedOtp: extractOtp(summary, body)
    readonly property bool hasOtp: extractedOtp !== ""

    function copyOtpToClipboard() {
        if (!extractedOtp) return;
        SystemServices.copyToClipboard(extractedOtp);
        root.otpCopied = true;
        otpFeedbackTimer.restart();
    }

    // --- App, Agent & Avatar Detection ---
    readonly property bool isMessagingApp: {
        const lower = (appName || "").toLowerCase();
        const keywords = [
            "telegram", "discord", "slack", "whatsapp", "signal",
            "element", "thunderbird", "matrix", "kdeconnect", "messages",
            "sms", "wechat", "teams", "skype", "viber", "revolt", "cinny", "fluffychat"
        ];
        return keywords.some(k => lower.includes(k));
    }

    readonly property bool isAgentNotification: {
        const lowerApp = (appName || "").toLowerCase();
        const lowerSum = (summary || "").toLowerCase();
        const lowerBody = (body || "").toLowerCase();
        const agents = [
            "antigravity", "codex", "cursor", "opencode", "claude code",
            "claude", "copilot", "aider", "gemini", "codeium", "cody"
        ];
        return agents.some(a => lowerApp.includes(a) || lowerSum.includes(a))
            || lowerSum.includes("tool confirmation")
            || lowerSum.includes("permission request")
            || lowerSum.includes("allow tool")
            || lowerSum.includes("action required")
            || lowerBody.includes("tool confirmation")
            || lowerBody.includes("permission");
    }

    // Resolved sender avatar (photo/image file)
    readonly property string resolvedSenderAvatar: {
        if (imagePath !== "" && (imagePath.startsWith("/") || imagePath.startsWith("file://"))) {
            return imagePath;
        }
        if (appIcon !== "" && (appIcon.startsWith("/") || appIcon.startsWith("file://"))) {
            return appIcon;
        }
        return "";
    }
    readonly property bool hasSenderAvatar: resolvedSenderAvatar !== ""

    // Resolved official app icon (symbolic / theme icon)
    readonly property string resolvedAppIcon: {
        if (appIcon !== "" && !appIcon.startsWith("/") && !appIcon.startsWith("file://")) {
            const p = Quickshell.iconPath(appIcon, true);
            if (p !== "") return p;
        }
        if (appName !== "") {
            const p = Quickshell.iconPath(appName.toLowerCase(), true);
            if (p !== "") return p;
        }
        if (imagePath !== "" && !imagePath.startsWith("/") && !imagePath.startsWith("file://")) {
            const p = Quickshell.iconPath(imagePath, true);
            if (p !== "") return p;
        }
        if (isAgentNotification) {
            const p = Quickshell.iconPath("terminal", true);
            if (p !== "") return p;
        }
        return "";
    }
    readonly property bool hasResolvedAppIcon: resolvedAppIcon !== ""
    readonly property bool hasImageAttachment: imagePath !== "" && (imagePath.startsWith("/") || imagePath.startsWith("file://")) && imagePath !== resolvedSenderAvatar

    // --- Actions Handling ---
    readonly property bool hasActions: actions && actions.length > 0
    readonly property var effectiveActions: {
        if (hasActions) return actions;
        if (isAgentNotification) {
            return [{ id: "focus", text: "Open & Focus" }];
        }
        return [];
    }
    readonly property bool hasEffectiveActions: effectiveActions.length > 0
    readonly property bool hasInlineActions: hasOtp || (hasEffectiveActions && effectiveActions.length <= 2)

    // --- Content Texts & Sizing Probes ---
    readonly property string displayTitle: summary !== "" ? summary : (appName !== "" ? appName : "Notification")
    readonly property string displayBody: {
        if (body !== "" && body !== summary) return body;
        return "";
    }
    readonly property string combinedPreviewText: {
        if (summary !== "" && body !== "" && body !== summary) return summary + "  •  " + body;
        if (summary !== "") return summary;
        if (body !== "") return body;
        return "New notification";
    }

    readonly property real minimumWidth: 320
    readonly property real compactMaximumWidth: 480
    readonly property real expandedMaximumWidth: 520
    readonly property real maximumWidth: expanded ? expandedMaximumWidth : compactMaximumWidth

    readonly property real horizontalPadding: 14
    readonly property real compactVerticalPadding: 7
    readonly property real expandedVerticalPadding: 12

    readonly property bool hasOverflowContent: true

    readonly property real compactPreferredWidth: {
        let textW = Math.max(contentMetrics.advanceWidth, titleMetrics.advanceWidth);
        let extraW = 38 + horizontalPadding * 2 + 12; // icon slot + padding + spacing
        if (hasOtp) {
            extraW += 120; // OTP pill button
        } else if (hasEffectiveActions) {
            extraW += Math.min(2, effectiveActions.length) * 75; // action buttons
        }
        return Math.max(minimumWidth, Math.min(compactMaximumWidth, textW + extraW));
    }

    readonly property real compactPreferredHeight: (hasInlineActions || displayBody !== "") ? 64 : 56
    readonly property real expandedPreferredWidth: expandedMaximumWidth
    readonly property real expandedPreferredHeight: Math.max(
        130,
        Math.min(380, expandedColumn.implicitHeight + (hasEffectiveActions ? 40 : 0) + 48 + expandedVerticalPadding * 2)
    )

    readonly property real preferredWidth: expanded ? expandedPreferredWidth : compactPreferredWidth
    readonly property real preferredHeight: expanded ? expandedPreferredHeight : compactPreferredHeight

    anchors.fill: parent
    anchors.margins: 0
    opacity: showCondition ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: showCondition ? 260 : 140
            easing.type: Easing.InOutQuad
        }
    }

    TextMetrics {
        id: contentMetrics
        font.family: textFontFamily
        font.pixelSize: userConfig.bodyFontSize
        font.weight: Font.DemiBold
        font.letterSpacing: -0.15
        text: combinedPreviewText
    }

    TextMetrics {
        id: titleMetrics
        font.family: textFontFamily
        font.pixelSize: 13
        font.weight: Font.Bold
        font.letterSpacing: -0.1
        text: displayTitle
    }

    Text {
        id: compactContentProbe
        x: -10000
        y: -10000
        height: 0
        opacity: 0
        width: 260
        text: displayBody !== "" ? displayBody : displayTitle
        font.pixelSize: 12
        font.family: textFontFamily
        wrapMode: Text.WordWrap
    }

    // =========================================================================
    // COMPACT CAPSULE VIEW
    // =========================================================================
    Item {
        id: compactView
        anchors.fill: parent
        anchors.leftMargin: horizontalPadding
        anchors.rightMargin: horizontalPadding
        anchors.topMargin: compactVerticalPadding
        anchors.bottomMargin: compactVerticalPadding
        visible: !root.expanded

        RowLayout {
            anchors.fill: parent
            spacing: 11

            // --- Left: Avatar / App Icon Slot ---
            Item {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                Layout.alignment: Qt.AlignVCenter

                // Circular contact avatar
                Rectangle {
                    anchors.centerIn: parent
                    width: 34
                    height: 34
                    radius: 17
                    color: StyleTokens.cardFillActive
                    clip: true
                    visible: root.hasSenderAvatar
                    border.color: StyleTokens.withAlpha(StyleTokens.white, 0.22)
                    border.width: 1

                    Image {
                        anchors.fill: parent
                        source: root.resolvedSenderAvatar
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        mipmap: true
                    }
                }

                // Mini app badge overlay at bottom-right
                Rectangle {
                    width: 15
                    height: 15
                    radius: 7.5
                    x: 21
                    y: 21
                    color: StyleTokens.mainBackground
                    border.color: StyleTokens.withAlpha(StyleTokens.white, 0.28)
                    border.width: 1
                    clip: true
                    visible: root.hasSenderAvatar && root.hasResolvedAppIcon

                    Image {
                        anchors.centerIn: parent
                        width: 11
                        height: 11
                        source: root.resolvedAppIcon
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                    }
                }

                // Standard App Icon slot (when no avatar photo is present)
                Rectangle {
                    anchors.centerIn: parent
                    width: 32
                    height: 32
                    radius: 9
                    visible: !root.hasSenderAvatar
                    color: root.isAgentNotification
                        ? StyleTokens.withAlpha("#6366f1", 0.25)
                        : (root.urgency === 2 ? StyleTokens.withAlpha(StyleTokens.danger, 0.2) : StyleTokens.cardFillActive)
                    border.color: root.isAgentNotification
                        ? StyleTokens.withAlpha("#818cf8", 0.5)
                        : (root.urgency === 2 ? StyleTokens.danger : StyleTokens.withAlpha(StyleTokens.white, 0.14))
                    border.width: 1

                    Image {
                        id: appIconImage
                        anchors.centerIn: parent
                        width: 20
                        height: 20
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
                        text: root.isAgentNotification ? "✦" : (root.urgency === 2 ? "" : root.iconText)
                        color: root.isAgentNotification
                            ? "#a5b4fc"
                            : (root.urgency === 2 ? StyleTokens.danger : StyleTokens.textPrimaryBright)
                        font.pixelSize: 13
                        font.family: root.isAgentNotification ? root.textFontFamily : root.iconFontFamily
                    }
                }
            }

            // --- Center: Text Content Column ---
            Column {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                clip: true

                Text {
                    id: compactTitleText
                    width: parent.width
                    text: root.displayTitle
                    color: StyleTokens.textPrimaryBright
                    font.pixelSize: 13
                    font.family: root.textFontFamily
                    font.weight: Font.Bold
                    font.letterSpacing: -0.1
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    id: compactBodyText
                    width: parent.width
                    visible: root.displayBody !== ""
                    text: root.displayBody
                    color: StyleTokens.textSecondary
                    font.pixelSize: 11
                    font.family: root.textFontFamily
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            // --- Right: Smart Inline Action Pill (OTP or Actions) ---
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 30
                implicitWidth: actionRow.implicitWidth

                Row {
                    id: actionRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    // OTP Copy Pill Button
                    Rectangle {
                        id: otpCopyBtn
                        visible: root.hasOtp
                        height: 28
                        width: otpBtnLayout.implicitWidth + 18
                        radius: 14
                        color: root.otpCopied
                            ? StyleTokens.withAlpha("#10b981", 0.3)
                            : (otpMouse.pressed
                                ? StyleTokens.accentPressed
                                : (otpMouse.containsMouse ? StyleTokens.cardFillHover : StyleTokens.cardFillActive))
                        border.color: root.otpCopied
                            ? "#10b981"
                            : StyleTokens.withAlpha(StyleTokens.accent, 0.45)
                        border.width: 1

                        Row {
                            id: otpBtnLayout
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                text: root.otpCopied ? "✓" : "📋"
                                font.pixelSize: 11
                                font.family: root.textFontFamily
                                color: root.otpCopied ? "#10b981" : StyleTokens.textPrimaryBright
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: root.otpCopied ? "Copied!" : ("Copy " + root.extractedOtp)
                                font.pixelSize: 11
                                font.family: root.textFontFamily
                                font.weight: Font.Bold
                                color: root.otpCopied ? "#10b981" : StyleTokens.textPrimaryBright
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: otpMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.copyOtpToClipboard();
                            }
                        }
                    }

                    // Compact Action Buttons (Allow / Deny or Focus)
                    Repeater {
                        model: (!root.hasOtp && root.hasEffectiveActions && root.effectiveActions.length <= 2) ? root.effectiveActions : []
                        delegate: Rectangle {
                            id: inlineBtn
                            height: 28
                            width: inlineLabel.implicitWidth + 16
                            radius: 14

                            readonly property string btnText: modelData.text || modelData.id
                            readonly property bool isPositive: {
                                const t = btnText.toLowerCase();
                                return t.includes("allow") || t.includes("approve") || t.includes("yes") || t.includes("focus") || t.includes("proceed");
                            }
                            readonly property bool isNegative: {
                                const t = btnText.toLowerCase();
                                return t.includes("deny") || t.includes("reject") || t.includes("no") || t.includes("cancel");
                            }

                            color: inlineMouse.pressed
                                ? StyleTokens.accentPressed
                                : (inlineMouse.containsMouse
                                    ? (isPositive ? StyleTokens.withAlpha("#10b981", 0.28) : (isNegative ? StyleTokens.withAlpha(StyleTokens.danger, 0.28) : StyleTokens.cardFillHover))
                                    : (isPositive ? StyleTokens.withAlpha("#10b981", 0.18) : (isNegative ? StyleTokens.withAlpha(StyleTokens.danger, 0.14) : StyleTokens.cardFillActive)))
                            border.color: isPositive
                                ? StyleTokens.withAlpha("#10b981", 0.5)
                                : (isNegative ? StyleTokens.withAlpha(StyleTokens.danger, 0.45) : StyleTokens.withAlpha(StyleTokens.white, 0.18))
                            border.width: 1

                            Row {
                                id: inlineLabel
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    visible: inlineBtn.isPositive || inlineBtn.isNegative
                                    text: inlineBtn.isPositive ? "✓" : "✕"
                                    font.pixelSize: 10
                                    font.family: root.textFontFamily
                                    font.weight: Font.Bold
                                    color: inlineBtn.isPositive ? "#34d399" : (inlineBtn.isNegative ? StyleTokens.danger : StyleTokens.textPrimaryBright)
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: inlineBtn.btnText
                                    color: StyleTokens.textPrimaryBright
                                    font.pixelSize: 11
                                    font.family: root.textFontFamily
                                    font.weight: Font.DemiBold
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: inlineMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.actionTriggered(modelData.id)
                            }
                        }
                    }

                    // Subtle Expand Indicator (if overflow exists and no action pill is displayed)
                    Rectangle {
                        visible: !root.hasOtp && (!root.hasEffectiveActions || root.effectiveActions.length > 2) && root.hasOverflowContent
                        width: 22
                        height: 22
                        radius: 11
                        color: StyleTokens.withAlpha(StyleTokens.white, 0.08)
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "⌄"
                            font.pixelSize: 13
                            font.family: root.textFontFamily
                            color: StyleTokens.textMuted
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // EXPANDED RICH DETAILS VIEW
    // =========================================================================
    Item {
        id: expandedView
        anchors.fill: parent
        anchors.leftMargin: horizontalPadding
        anchors.rightMargin: horizontalPadding
        anchors.topMargin: expandedVerticalPadding
        anchors.bottomMargin: expandedVerticalPadding
        visible: root.expanded

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            // --- Header: App Name, Urgency / Source, Close Button ---
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                spacing: 8

                // Header icon
                Item {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 11
                        color: StyleTokens.cardFillActive
                        clip: true
                        visible: root.hasSenderAvatar

                        Image {
                            anchors.fill: parent
                            source: root.resolvedSenderAvatar
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }

                    Image {
                        anchors.fill: parent
                        visible: !root.hasSenderAvatar && root.hasResolvedAppIcon
                        source: root.resolvedAppIcon
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !root.hasSenderAvatar && !root.hasResolvedAppIcon
                        text: root.isAgentNotification ? "✦" : root.iconText
                        color: root.isAgentNotification ? "#818cf8" : StyleTokens.textSecondary
                        font.pixelSize: 12
                        font.family: root.isAgentNotification ? root.textFontFamily : root.iconFontFamily
                    }
                }

                // App Title and Subtitle
                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    Row {
                        spacing: 6
                        Text {
                            text: root.appName !== "" ? root.appName : "Notification"
                            color: StyleTokens.textPrimaryBright
                            font.pixelSize: 12
                            font.family: root.textFontFamily
                            font.weight: Font.Bold
                        }

                        Text {
                            text: "•"
                            color: StyleTokens.textMuted
                            font.pixelSize: 10
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: root.isAgentNotification
                                ? "Agent Prompt"
                                : (root.isMessagingApp ? "Message" : (root.urgency === 2 ? "High Priority" : "Just now"))
                            color: root.isAgentNotification
                                ? "#a5b4fc"
                                : (root.urgency === 2 ? StyleTokens.danger : StyleTokens.textMuted)
                            font.pixelSize: 11
                            font.family: root.textFontFamily
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // Explicit Close Button [✕]
                Rectangle {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    radius: 12
                    color: closeMouse.containsMouse ? StyleTokens.withAlpha(StyleTokens.white, 0.15) : StyleTokens.withAlpha(StyleTokens.white, 0.06)

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 11
                        font.family: root.textFontFamily
                        font.weight: Font.Bold
                        color: closeMouse.containsMouse ? StyleTokens.white : StyleTokens.textMuted
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }

            // Divider Line
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: StyleTokens.withAlpha(StyleTokens.white, 0.08)
            }

            // --- Scrollable Body Content ---
            Flickable {
                id: expandedFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: expandedColumn.implicitHeight
                interactive: contentHeight > height

                Column {
                    id: expandedColumn
                    width: expandedFlickable.width
                    spacing: 8

                    // Title / Summary
                    Text {
                        id: expandedSummaryText
                        width: parent.width
                        text: root.displayTitle
                        color: StyleTokens.textPrimaryBright
                        font.pixelSize: 14
                        font.family: root.textFontFamily
                        font.weight: Font.Bold
                        font.letterSpacing: -0.1
                        wrapMode: Text.WordWrap
                    }

                    // Full Body
                    Text {
                        id: expandedBodyText
                        visible: root.displayBody !== ""
                        width: parent.width
                        text: root.displayBody
                        color: StyleTokens.textSecondary
                        font.pixelSize: 12
                        font.family: root.textFontFamily
                        font.weight: Font.Normal
                        lineHeight: 1.2
                        wrapMode: Text.WordWrap
                    }

                    // --- Dedicated OTP Banner Card ---
                    Rectangle {
                        visible: root.hasOtp
                        width: parent.width
                        height: 52
                        radius: 10
                        color: root.otpCopied ? StyleTokens.withAlpha("#10b981", 0.16) : StyleTokens.withAlpha(StyleTokens.accent, 0.12)
                        border.color: root.otpCopied ? "#10b981" : StyleTokens.withAlpha(StyleTokens.accent, 0.4)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            spacing: 12

                            Column {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                Text {
                                    text: root.extractedOtp
                                    color: StyleTokens.textPrimaryBright
                                    font.pixelSize: 17
                                    font.family: root.heroFontFamily || root.textFontFamily
                                    font.weight: Font.Bold
                                    font.letterSpacing: 2
                                }

                                Text {
                                    text: root.otpCopied ? "✓ Copied to clipboard!" : "Verification code detected"
                                    color: root.otpCopied ? "#10b981" : StyleTokens.textMuted
                                    font.pixelSize: 11
                                    font.family: root.textFontFamily
                                }
                            }

                            Rectangle {
                                Layout.preferredHeight: 28
                                Layout.preferredWidth: otpCardBtnText.implicitWidth + 20
                                radius: 14
                                color: root.otpCopied
                                    ? "#10b981"
                                    : (otpCardMouse.containsMouse ? StyleTokens.cardFillHover : StyleTokens.cardFillActive)
                                border.color: root.otpCopied ? "#10b981" : StyleTokens.withAlpha(StyleTokens.white, 0.2)
                                border.width: 1

                                Text {
                                    id: otpCardBtnText
                                    anchors.centerIn: parent
                                    text: root.otpCopied ? "Copied" : "Copy Code"
                                    color: root.otpCopied ? StyleTokens.white : StyleTokens.textPrimaryBright
                                    font.pixelSize: 11
                                    font.family: root.textFontFamily
                                    font.weight: Font.Bold
                                }

                                MouseArea {
                                    id: otpCardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.copyOtpToClipboard()
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.copyOtpToClipboard()
                        }
                    }

                    // --- Image Attachment Preview ---
                    Rectangle {
                        visible: root.hasImageAttachment && imageAttachment.status !== Image.Error
                        width: Math.min(parent.width, 220)
                        height: visible ? 100 : 0
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
                }
            }

            // --- Bottom Action Bar ---
            Row {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 8
                visible: root.hasEffectiveActions

                Repeater {
                    model: root.effectiveActions
                    delegate: Rectangle {
                        id: expandedActionBtn
                        height: 30
                        width: expandedActionLabel.implicitWidth + 24
                        radius: 15

                        readonly property string btnText: modelData.text || modelData.id
                        readonly property bool isPositive: {
                            const t = btnText.toLowerCase();
                            return t.includes("allow") || t.includes("approve") || t.includes("yes") || t.includes("focus") || t.includes("proceed");
                        }
                        readonly property bool isNegative: {
                            const t = btnText.toLowerCase();
                            return t.includes("deny") || t.includes("reject") || t.includes("no") || t.includes("cancel");
                        }

                        color: expandedActionMouse.pressed
                            ? StyleTokens.accentPressed
                            : (expandedActionMouse.containsMouse
                                ? (isPositive ? "#059669" : (isNegative ? StyleTokens.withAlpha(StyleTokens.danger, 0.35) : StyleTokens.cardFillHover))
                                : (isPositive ? "#10b981" : (isNegative ? StyleTokens.withAlpha(StyleTokens.danger, 0.2) : StyleTokens.cardFillActive)))
                        border.color: isPositive
                            ? "#10b981"
                            : (isNegative ? StyleTokens.danger : StyleTokens.withAlpha(StyleTokens.white, 0.2))
                        border.width: 1

                        Row {
                            id: expandedActionLabel
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                visible: expandedActionBtn.isPositive || expandedActionBtn.isNegative
                                text: expandedActionBtn.isPositive ? "✓" : "✕"
                                font.pixelSize: 11
                                font.family: root.textFontFamily
                                font.weight: Font.Bold
                                color: StyleTokens.white
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: expandedActionBtn.btnText
                                color: StyleTokens.white
                                font.pixelSize: 11
                                font.family: root.textFontFamily
                                font.weight: Font.Bold
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: expandedActionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.actionTriggered(modelData.id)
                        }
                    }
                }

                // Dismiss / Close Button in Action Bar
                Rectangle {
                    height: 30
                    width: dismissLabel.implicitWidth + 20
                    radius: 15
                    color: dismissMouse.containsMouse ? StyleTokens.cardFillHover : StyleTokens.cardFillActive
                    border.color: StyleTokens.withAlpha(StyleTokens.white, 0.16)
                    border.width: 1

                    Text {
                        id: dismissLabel
                        anchors.centerIn: parent
                        text: "Dismiss"
                        color: StyleTokens.textSecondary
                        font.pixelSize: 11
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: dismissMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }
        }
    }

    // Tap outside interactive buttons toggles expansion
    TapHandler {
        enabled: root.hasOverflowContent
        acceptedButtons: root.toggleButton
        onTapped: root.expansionToggleRequested()
    }
}
