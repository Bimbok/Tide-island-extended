import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
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
    signal dismissRequested()

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
    readonly property var filteredActions: {
        if (!actions || actions.length === 0) return [];
        const result = [];
        for (let i = 0; i < actions.length; i++) {
            const a = actions[i];
            const aid = (a.id || "").toLowerCase();
            const atext = (a.text || "").toLowerCase();
            if (aid === "settings" || aid === "app-settings" || atext === "settings" || atext === "configure") {
                continue;
            }
            result.push(a);
        }
        return result;
    }

    readonly property bool hasActions: filteredActions.length > 0
    readonly property var effectiveActions: {
        if (hasActions) return filteredActions;
        if (isAgentNotification) {
            return [{ id: "focus", text: "Focus" }];
        }
        return [];
    }
    readonly property bool hasEffectiveActions: effectiveActions.length > 0

    function cleanActionText(rawText) {
        if (!rawText) return "";
        return rawText.replace(/^[0-9]+[\.\)\s\-]+/, "").trim();
    }

    function shortenActionText(rawText, isPositiveHint) {
        const clean = cleanActionText(rawText);
        const lower = clean.toLowerCase();

        // 1. Permission / Allow
        if (lower.startsWith("yes") || lower.startsWith("allow") || lower.startsWith("approve") || lower.startsWith("proceed") || lower.startsWith("run") || lower.startsWith("grant") || lower.startsWith("accept") || lower.startsWith("confirm")) {
            return "Allow";
        }
        // 2. Deny / Cancel
        if (lower.startsWith("no") || lower.startsWith("deny") || lower.startsWith("reject") || lower.startsWith("cancel") || lower.startsWith("abort") || lower.startsWith("block") || lower.startsWith("decline")) {
            return "Deny";
        }
        // 3. Explicit Focus / Default / Activate / Generic
        if (lower === "default" || lower === "" || lower === "activate" || lower === "focus" || lower.startsWith("focus") || lower.startsWith("open & focus") || lower === "action" || lower === "click") {
            return "Focus";
        }
        // 4. Positive / Negative Hint
        if (isPositiveHint === true) return "Allow";
        if (isPositiveHint === false) return "Deny";

        // 5. Common action verbs
        if (lower.startsWith("reply")) return "Reply";
        if (lower.startsWith("join")) return "Join";
        if (lower.startsWith("snooze")) return "Snooze";
        if (lower.startsWith("view") || lower.startsWith("open") || lower.startsWith("show")) return "View";
        if (lower.startsWith("call")) return "Call";
        if (lower.startsWith("play")) return "Play";
        if (lower.startsWith("pause")) return "Pause";
        if (lower.startsWith("mute")) return "Mute";
        if (lower.startsWith("copy")) return "Copy";

        // 6. Clean concise labels (<= 12 chars)
        if (clean.length > 0 && clean.length <= 12 && lower !== "default") {
            return clean;
        }

        // 7. Unknown category fallback -> "Focus"
        return "Focus";
    }

    readonly property var compactActions: {
        if (!hasEffectiveActions) return [];

        if (effectiveActions.length <= 2) {
            const list = [];
            for (let i = 0; i < effectiveActions.length; i++) {
                const a = effectiveActions[i];
                const raw = a.text || a.id || "";
                list.push({
                    id: a.id,
                    text: shortenActionText(raw),
                    rawText: raw
                });
            }
            return list;
        }

        // More than 2 actions (e.g. Antigravity CLI with 4 permission choices)
        let posAction = null;
        let negAction = null;

        for (let i = 0; i < effectiveActions.length; i++) {
            const act = effectiveActions[i];
            const t = cleanActionText(act.text || act.id || "").toLowerCase();
            if (!posAction && (t.startsWith("yes") || t.startsWith("allow") || t.startsWith("approve") || t.startsWith("run") || t.startsWith("proceed") || t.includes("allow"))) {
                posAction = act;
            }
            if (!negAction && (t.startsWith("no") || t.startsWith("deny") || t.startsWith("cancel") || t.startsWith("reject") || t.startsWith("abort") || t.includes("cancel") || t.includes("deny"))) {
                negAction = act;
            }
        }

        const res = [];
        if (posAction) {
            res.push({
                id: posAction.id,
                text: shortenActionText(posAction.text || posAction.id, true),
                rawText: posAction.text || posAction.id
            });
        }
        if (negAction) {
            res.push({
                id: negAction.id,
                text: shortenActionText(negAction.text || negAction.id, false),
                rawText: negAction.text || negAction.id
            });
        }
        if (res.length > 0) return res;

        // Fallback: take first 2 actions
        const fallback = [];
        const limit = Math.min(2, effectiveActions.length);
        for (let i = 0; i < limit; i++) {
            const a = effectiveActions[i];
            const raw = a.text || a.id || "";
            fallback.push({
                id: a.id,
                text: shortenActionText(raw),
                rawText: raw
            });
        }
        return fallback;
    }

    readonly property bool hasCompactActions: compactActions.length > 0
    readonly property bool hasInlineActions: hasOtp || hasCompactActions

    // --- Content Texts & Sizing Probes ---
    readonly property string displayTitle: summary !== "" ? summary : (appName !== "" ? appName : "Notification")
    readonly property string displayBody: {
        if (body !== "" && body !== summary) return body;
        return "";
    }

    function formatNotificationBody(rawText) {
        if (!rawText) return "";
        let formatted = rawText.replace(/\[([^\]]+)\]\(["']?([^)"']+)["']?\)/g, '<a href="$2">$1</a>');
        formatted = formatted.replace(/(^|[^"'>])(https?:\/\/[^\s<]+)/g, '$1<a href="$2">$2</a>');
        return formatted;
    }
    readonly property string combinedPreviewText: {
        if (summary !== "" && body !== "" && body !== summary) return summary + "  •  " + body;
        if (summary !== "") return summary;
        if (body !== "") return body;
        return "New notification";
    }

    readonly property real minimumWidth: 320
    readonly property real compactMaximumWidth: 520
    readonly property real expandedMaximumWidth: 540
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
        } else if (hasCompactActions) {
            for (let i = 0; i < compactActions.length; i++) {
                const a = compactActions[i];
                if (a.text === "Focus" || a.id === "focus" || a.id === "default") {
                    extraW += 36;
                } else {
                    extraW += 82;
                }
            }
        }
        return Math.max(minimumWidth, Math.min(compactMaximumWidth, textW + extraW));
    }

    readonly property real compactPreferredHeight: (hasInlineActions || displayBody !== "") ? 64 : 56
    readonly property real expandedPreferredWidth: expandedMaximumWidth
    readonly property real expandedPreferredHeight: Math.max(
        130,
        Math.min(420, expandedColumn.implicitHeight + (hasEffectiveActions ? 48 : 0) + 48 + expandedVerticalPadding * 2)
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
                Item {
                    anchors.centerIn: parent
                    width: 34
                    height: 34
                    visible: root.hasSenderAvatar

                    Rectangle {
                        id: compactAvatarMask
                        anchors.fill: parent
                        radius: 17
                        visible: false
                        layer.enabled: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 17
                        color: StyleTokens.cardFillActive
                    }

                    Image {
                        id: compactAvatarImg
                        anchors.fill: parent
                        source: root.resolvedSenderAvatar
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        mipmap: true
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: compactAvatarMask
                        }
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        visible: compactAvatarImg.status !== Image.Ready && root.hasResolvedAppIcon
                        source: root.resolvedAppIcon
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: compactAvatarImg.status !== Image.Ready && !root.hasResolvedAppIcon
                        text: root.iconText
                        color: StyleTokens.textSecondary
                        font.pixelSize: 13
                        font.family: root.iconFontFamily
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 17
                        color: StyleTokens.transparent
                        border.color: StyleTokens.withAlpha(StyleTokens.white, 0.22)
                        border.width: 1
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
                    width: 34
                    height: 34
                    radius: 17
                    clip: true
                    visible: !root.hasSenderAvatar
                    color: root.isAgentNotification
                        ? StyleTokens.withAlpha(StyleTokens.accent, 0.22)
                        : (root.urgency === 2 ? StyleTokens.withAlpha(StyleTokens.danger, 0.2) : StyleTokens.cardFillActive)
                    border.color: root.isAgentNotification
                        ? StyleTokens.withAlpha(StyleTokens.accent, 0.5)
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
                            ? StyleTokens.accent
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
                    text: root.displayBody.replace(/\[([^\]]+)\]\(["']?([^)"']+)["']?\)/g, "$1")
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
                            ? StyleTokens.withAlpha(StyleTokens.success, 0.25)
                            : (otpMouse.pressed
                                ? StyleTokens.accentPressed
                                : (otpMouse.containsMouse ? StyleTokens.withAlpha(StyleTokens.accent, 0.28) : StyleTokens.withAlpha(StyleTokens.accent, 0.16)))
                        border.color: root.otpCopied
                            ? StyleTokens.success
                            : StyleTokens.withAlpha(StyleTokens.accent, 0.5)
                        border.width: 1

                        Row {
                            id: otpBtnLayout
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                text: root.otpCopied ? "✓" : "📋"
                                font.pixelSize: 11
                                font.family: root.textFontFamily
                                color: root.otpCopied ? StyleTokens.success : StyleTokens.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: root.otpCopied ? "Copied!" : ("Copy " + root.extractedOtp)
                                font.pixelSize: 11
                                font.family: root.textFontFamily
                                font.weight: Font.Bold
                                color: root.otpCopied ? StyleTokens.success : StyleTokens.textPrimaryBright
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

                    // Compact Action Buttons (Allow / Deny or Circular Focus Icon Button)
                    Repeater {
                        model: (!root.hasOtp && root.hasCompactActions) ? root.compactActions : []
                        delegate: Rectangle {
                            id: inlineBtn
                            readonly property string btnText: modelData.text || modelData.id
                            readonly property bool isFocusAction: btnText === "Focus" || modelData.id === "focus" || modelData.id === "default"
                            readonly property bool isPositive: {
                                const t = (modelData.rawText || btnText).toLowerCase();
                                return btnText === "Allow" || t.includes("allow") || t.includes("approve") || t.includes("yes") || t.includes("proceed") || t.includes("run");
                            }
                            readonly property bool isNegative: {
                                const t = (modelData.rawText || btnText).toLowerCase();
                                return btnText === "Deny" || t.includes("deny") || t.includes("reject") || t.includes("no") || t.includes("cancel") || t.includes("abort");
                            }

                            height: 28
                            width: isFocusAction ? 28 : (inlineLabel.implicitWidth + 18)
                            radius: 14

                            color: inlineMouse.pressed
                                ? StyleTokens.accentPressed
                                : (inlineMouse.containsMouse
                                    ? (isFocusAction ? StyleTokens.withAlpha(StyleTokens.accent, 0.32)
                                        : (isPositive ? StyleTokens.withAlpha(StyleTokens.success, 0.30)
                                        : (isNegative ? StyleTokens.withAlpha(StyleTokens.danger, 0.28)
                                        : StyleTokens.cardFillHover)))
                                    : (isFocusAction ? StyleTokens.withAlpha(StyleTokens.accent, 0.18)
                                        : (isPositive ? StyleTokens.withAlpha(StyleTokens.success, 0.18)
                                        : (isNegative ? StyleTokens.withAlpha(StyleTokens.danger, 0.14)
                                        : StyleTokens.cardFillActive))))

                            border.color: isFocusAction
                                ? (inlineMouse.containsMouse ? StyleTokens.accent : StyleTokens.withAlpha(StyleTokens.accent, 0.55))
                                : (isPositive
                                    ? StyleTokens.withAlpha(StyleTokens.success, 0.55)
                                    : (isNegative ? StyleTokens.withAlpha(StyleTokens.danger, 0.5) : StyleTokens.withAlpha(StyleTokens.textMuted, 0.35)))
                            border.width: 1

                            // Circular Focus Icon (↗)
                            Text {
                                anchors.centerIn: parent
                                visible: inlineBtn.isFocusAction
                                text: "↗"
                                font.pixelSize: 14
                                font.family: root.textFontFamily
                                font.weight: Font.Bold
                                color: inlineMouse.containsMouse ? StyleTokens.accent : StyleTokens.textPrimaryBright
                                scale: inlineMouse.pressed ? 0.90 : (inlineMouse.containsMouse ? 1.12 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 120 } }
                            }

                            // Action Pill Label (Allow, Deny, etc.)
                            Row {
                                id: inlineLabel
                                anchors.centerIn: parent
                                visible: !inlineBtn.isFocusAction
                                spacing: 4

                                Text {
                                    visible: inlineBtn.isPositive || inlineBtn.isNegative
                                    text: inlineBtn.isPositive ? "✓" : "✕"
                                    font.pixelSize: 10
                                    font.family: root.textFontFamily
                                    font.weight: Font.Bold
                                    color: inlineBtn.isPositive ? StyleTokens.success : (inlineBtn.isNegative ? StyleTokens.danger : StyleTokens.textPrimaryBright)
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

                // Header icon (circular 24x24)
                Item {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: root.hasSenderAvatar
                            ? StyleTokens.cardFillActive
                            : (root.isAgentNotification
                                ? StyleTokens.withAlpha(StyleTokens.accent, 0.22)
                                : (root.urgency === 2 ? StyleTokens.withAlpha(StyleTokens.danger, 0.2) : StyleTokens.cardFillActive))
                        border.color: root.isAgentNotification
                            ? StyleTokens.withAlpha(StyleTokens.accent, 0.45)
                            : (root.urgency === 2 ? StyleTokens.danger : StyleTokens.withAlpha(StyleTokens.white, 0.15))
                        border.width: 1
                        Rectangle {
                            id: expandedAvatarMask
                            anchors.fill: parent
                            radius: 12
                            visible: false
                            layer.enabled: true
                        }

                        Image {
                            anchors.fill: parent
                            visible: root.hasSenderAvatar && status === Image.Ready
                            source: root.resolvedSenderAvatar
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                            mipmap: true
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: expandedAvatarMask
                            }
                        }

                        Image {
                            id: appIconHeaderImage
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            visible: !root.hasSenderAvatar && root.hasResolvedAppIcon && status !== Image.Error
                            source: root.resolvedAppIcon
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            mipmap: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !root.hasSenderAvatar && (!root.hasResolvedAppIcon || appIconHeaderImage.status === Image.Error)
                            text: root.isAgentNotification ? "✦" : (root.urgency === 2 ? "" : root.iconText)
                            color: root.isAgentNotification ? StyleTokens.accent : (root.urgency === 2 ? StyleTokens.danger : StyleTokens.textSecondary)
                            font.pixelSize: 11
                            font.family: root.isAgentNotification ? root.textFontFamily : root.iconFontFamily
                        }
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
                                ? StyleTokens.accent
                                : (root.urgency === 2 ? StyleTokens.danger : StyleTokens.textMuted)
                            font.pixelSize: 11
                            font.family: root.textFontFamily
                            anchors.verticalCenter: parent.verticalCenter
                        }
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
                        text: root.formatNotificationBody(root.displayBody)
                        textFormat: Text.StyledText
                        linkColor: StyleTokens.accent
                        onLinkActivated: function(link) {
                            Qt.openUrlExternally(link);
                        }
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
                        color: root.otpCopied ? StyleTokens.withAlpha(StyleTokens.success, 0.16) : StyleTokens.withAlpha(StyleTokens.accent, 0.12)
                        border.color: root.otpCopied ? StyleTokens.success : StyleTokens.withAlpha(StyleTokens.accent, 0.4)
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
                                    color: root.otpCopied ? StyleTokens.success : StyleTokens.textMuted
                                    font.pixelSize: 11
                                    font.family: root.textFontFamily
                                }
                            }

                            Rectangle {
                                Layout.preferredHeight: 28
                                Layout.preferredWidth: otpCardBtnText.implicitWidth + 20
                                radius: 14
                                color: root.otpCopied
                                    ? StyleTokens.success
                                    : (otpCardMouse.containsMouse ? StyleTokens.accent : StyleTokens.accentSoft)
                                border.color: root.otpCopied ? StyleTokens.success : StyleTokens.withAlpha(StyleTokens.accent, 0.6)
                                border.width: 1

                                Text {
                                    id: otpCardBtnText
                                    anchors.centerIn: parent
                                    text: root.otpCopied ? "Copied" : "Copy Code"
                                    color: root.otpCopied ? StyleTokens.textPrimaryBright : StyleTokens.textOnAccent
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
            Flow {
                Layout.fillWidth: true
                spacing: 8
                visible: root.hasEffectiveActions

                Repeater {
                    model: root.effectiveActions
                    delegate: Rectangle {
                        id: expandedActionBtn
                        height: 30
                        width: expandedActionLabel.implicitWidth + 24
                        radius: 15

                        readonly property string btnText: root.shortenActionText(modelData.text || modelData.id)
                        readonly property bool isFocusAction: btnText === "Focus" || modelData.id === "focus" || modelData.id === "default"
                        readonly property bool isPositive: {
                            const t = (modelData.rawText || modelData.text || btnText).toLowerCase();
                            return btnText === "Allow" || t.includes("allow") || t.includes("approve") || t.includes("yes") || t.includes("proceed") || t.includes("run");
                        }
                        readonly property bool isNegative: {
                            const t = (modelData.rawText || modelData.text || btnText).toLowerCase();
                            return btnText === "Deny" || t.includes("deny") || t.includes("reject") || t.includes("no") || t.includes("cancel") || t.includes("abort");
                        }

                        color: expandedActionMouse.pressed
                            ? StyleTokens.accentPressed
                            : (expandedActionMouse.containsMouse
                                ? (isPositive ? StyleTokens.withAlpha(StyleTokens.success, 0.35)
                                    : (isFocusAction ? StyleTokens.withAlpha(StyleTokens.accent, 0.35)
                                    : (isNegative ? StyleTokens.withAlpha(StyleTokens.danger, 0.30)
                                    : StyleTokens.cardFillHover)))
                                : (isPositive ? StyleTokens.withAlpha(StyleTokens.success, 0.22)
                                    : (isFocusAction ? StyleTokens.withAlpha(StyleTokens.accent, 0.22)
                                    : (isNegative ? StyleTokens.withAlpha(StyleTokens.danger, 0.16)
                                    : StyleTokens.cardFillActive))))

                        border.color: isPositive
                            ? StyleTokens.withAlpha(StyleTokens.success, 0.6)
                            : (isFocusAction
                                ? StyleTokens.withAlpha(StyleTokens.accent, 0.6)
                                : (isNegative ? StyleTokens.withAlpha(StyleTokens.danger, 0.55) : StyleTokens.withAlpha(StyleTokens.textMuted, 0.3)))
                        border.width: 1

                        Row {
                            id: expandedActionLabel
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                visible: expandedActionBtn.isPositive || expandedActionBtn.isNegative || expandedActionBtn.isFocusAction
                                text: expandedActionBtn.isFocusAction ? "↗" : (expandedActionBtn.isPositive ? "✓" : "✕")
                                font.pixelSize: expandedActionBtn.isFocusAction ? 13 : 11
                                font.family: root.textFontFamily
                                font.weight: Font.Bold
                                color: expandedActionBtn.isPositive
                                    ? StyleTokens.success
                                    : (expandedActionBtn.isFocusAction ? StyleTokens.accent : (expandedActionBtn.isNegative ? StyleTokens.danger : StyleTokens.textPrimaryBright))
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: expandedActionBtn.isFocusAction ? "Focus Window" : expandedActionBtn.btnText
                                color: expandedActionBtn.isPositive
                                    ? StyleTokens.success
                                    : (expandedActionBtn.isFocusAction ? StyleTokens.accent : (expandedActionBtn.isNegative ? StyleTokens.danger : StyleTokens.textPrimaryBright))
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
                    color: dismissMouse.pressed
                        ? StyleTokens.accentPressed
                        : (dismissMouse.containsMouse ? StyleTokens.cardFillHover : StyleTokens.cardFillActive)
                    border.color: StyleTokens.withAlpha(StyleTokens.textMuted, 0.3)
                    border.width: 1

                    Text {
                        id: dismissLabel
                        anchors.centerIn: parent
                        text: "Dismiss"
                        color: dismissMouse.containsMouse ? StyleTokens.textPrimaryBright : StyleTokens.textSecondary
                        font.pixelSize: 11
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: dismissMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissRequested()
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
