pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import IslandBackend
import "../island"

Scope {
    id: root

    readonly property var userConfig: UserConfig

    // Configuration & Environment
    readonly property string envWallpaper: Quickshell.env("LOCK_WALLPAPER") || ""
    readonly property string userName: Quickshell.env("USER") || "user"
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property bool oneshot: Quickshell.env("LOCK_NOW") === "1"
    readonly property string pamConfig: (userConfig && userConfig.lockscreenPamService !== "")
        ? userConfig.lockscreenPamService
        : "login"

    property bool locked: false

    function lock(): void {
        sessionLock.locked = true;
    }

    function unlock(): void {
        sessionLock.locked = false;
    }

    function toggle(): void {
        sessionLock.locked = !sessionLock.locked;
    }

    function expandHome(p) {
        return (p && p.startsWith("~")) ? home + p.slice(1) : p;
    }

    readonly property string textFont: (userConfig && userConfig.textFontFamily !== "") ? userConfig.textFontFamily : "Sans Serif"
    readonly property string heroFont: (userConfig && userConfig.heroFontFamily !== "") ? userConfig.heroFontFamily : textFont
    readonly property string nerdFont: (userConfig && userConfig.iconFontFamily !== "") ? userConfig.iconFontFamily : "JetBrainsMono Nerd Font"
    readonly property string clockFmt: (userConfig && userConfig.clockFormat === "24") ? "HH:mm" : "hh:mm AP"

    readonly property bool isNotchMode: userConfig ? (userConfig.islandStyle === "notch") : false
    readonly property real islandW: userConfig ? userConfig.islandWidth : 280
    readonly property real islandH: userConfig ? userConfig.islandHeight : 38
    readonly property real islandR: isNotchMode ? 16 : islandH / 2
    readonly property real islandTopMargin: isNotchMode ? 0 : (userConfig ? userConfig.islandTopMargin : 6)

    readonly property string avatarPath: {
        if (userConfig && userConfig.avatarPath !== "")
            return expandHome(userConfig.avatarPath);
        return "";
    }

    readonly property bool confirmPower: true
    readonly property bool showPowerActions: userConfig ? userConfig.lockscreenPowerActions : true
    readonly property bool showLockscreenMedia: userConfig ? userConfig.lockscreenMedia : true
    readonly property bool showBatteryPill: userConfig ? userConfig.lockscreenShowBattery : true

    // Battery straight from SystemGlance
    readonly property int batPct: SystemGlance.batteryCapacity
    readonly property bool batCharging: SystemGlance.batteryStatus === "Charging" || SystemGlance.batteryStatus === "Full"
    readonly property bool hasBattery: showBatteryPill && batPct >= 0

    readonly property var batGlyphs: [0xf0083, 0xf007a, 0xf007d, 0xf007c, 0xf007d, 0xf007e, 0xf007f, 0xf0082, 0xf0081, 0xf0079]

    function batteryGlyph(pct) {
        if (!(pct >= 0)) return "";
        const base = String.fromCodePoint(root.batGlyphs[Math.min(Math.floor(pct / 10), 9)]);
        return root.batCharging ? base + String.fromCodePoint(0xf140b) : base;
    }

    function batteryColor(pct) {
        return pct > 30 ? StyleTokens.success : (pct <= 15 ? StyleTokens.danger : StyleTokens.warning);
    }

    // Wallpaper resolution
    readonly property string customLockscreenWallpaper: (userConfig && userConfig.lockscreenWallpaperPath !== "")
        ? expandHome(userConfig.lockscreenWallpaperPath)
        : ""
    readonly property bool hasExplicitWallpaper: customLockscreenWallpaper !== ""

    readonly property string detectedWallpaper: {
        if (userConfig && userConfig.wallpaperPath !== "")
            return userConfig.wallpaperPath;
        let p = wpFile.text().split("\n")[0].trim();
        if (p.startsWith("file://"))
            p = p.slice(7);
        return expandHome(p);
    }

    readonly property string wallpaper: {
        if (envWallpaper !== "") return envWallpaper;
        if (hasExplicitWallpaper) return customLockscreenWallpaper;
        return detectedWallpaper;
    }

    readonly property bool blurEnabled: userConfig ? userConfig.lockscreenBlur : true

    FileView {
        id: wpFile
        path: root.home + "/.cache/tide-island/last_wallpaper"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    // Weather Service instance
    WeatherService {
        id: weatherService
    }

    // Media Player detection
    property var activePlayer: {
        const list = Mpris.players.values !== undefined ? Mpris.players.values : Mpris.players;
        for (let i = 0; i < list.length; i++) {
            const p = list[i];
            if (p && p.playbackState === MprisPlaybackState.Playing)
                return p;
        }
        return list.length > 0 ? list[0] : null;
    }
    readonly property bool hasMedia: showLockscreenMedia && activePlayer !== null
    readonly property string trackTitle: activePlayer ? (activePlayer.trackTitle || activePlayer.title || "Unknown") : ""
    readonly property string trackArtist: {
        if (!activePlayer) return "";
        let art = activePlayer.artist;
        if (!art && activePlayer.metadata) art = activePlayer.metadata["xesam:artist"];
        if (art) return Array.isArray(art) ? art.join(", ") : String(art);
        return "";
    }
    readonly property string trackArtUrl: activePlayer ? (activePlayer.trackArtUrl || activePlayer.artUrl || "") : ""
    readonly property bool isMediaPlaying: activePlayer ? (activePlayer.playbackState === MprisPlaybackState.Playing) : false

    // Authentication state
    property string buffer: ""
    property bool checking: false
    property bool failed: false
    property bool unlocking: false
    property int failCount: 0
    property int cooldown: 0
    property bool pamRecord: false
    property bool confirmArmed: false

    readonly property bool lockedOut: cooldown > 0
    readonly property bool pamRisky: pamRecord || failCount > 0
    readonly property bool pamLocked: failCount >= 3

    readonly property string statusText: {
        if (unlocking)
            return "Welcome back";
        if (pamLocked)
            return "Locked by PAM · reset required";
        if (lockedOut)
            return "Too many attempts · wait " + cooldown + "s";
        if (checking)
            return "Verifying credentials…";
        if (confirmArmed)
            return "Press Enter again to submit";
        if (failed)
            return "Wrong password · " + failCount + (failCount === 1 ? " attempt" : " attempts");
        if (pamRisky)
            return "PAM recorded earlier failures · Enter again to submit";
        return "Press Enter to unlock · Esc to clear";
    }

    signal shake()

    function greeting() {
        const h = clock.hours;
        const t = h < 5 ? "Burning the midnight oil" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : h < 22 ? "Good evening" : "Late night";
        return t + ", " + userName;
    }

    function onFailure() {
        root.checking = false;
        root.failed = true;
        root.failCount++;
        root.buffer = "";
        root.confirmArmed = false;
        root.shake();
        root.cooldown = root.failCount === 1 ? 0 : (root.failCount === 2 ? 5 : 60);
        refreshFailTally();
    }

    function submit() {
        if (checking || unlocking || lockedOut || buffer.length === 0)
            return;
        if (pamLocked) {
            resetPamTally();
            return;
        }
        if (pamRisky && !confirmArmed) {
            confirmArmed = true;
            confirmTimer.restart();
            return;
        }
        confirmArmed = false;
        checking = true;
        failed = false;
        pam.start();
    }

    function refreshFailTally() {
        if (!faillockProc.running)
            faillockProc.running = true;
    }

    function resetPamTally() {
        resetProc.command = ["pkexec", "faillock", "--user", Quickshell.env("USER") || "root", "--reset"];
        resetProc.running = true;
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    PamContext {
        id: pam
        config: root.pamConfig

        onPamMessage: {
            if (pam.responseRequired)
                pam.respond(root.buffer);
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                root.checking = false;
                root.unlocking = true;
                root.failed = false;
                root.cooldown = 0;
                unlockTimer.start();
            } else {
                root.onFailure();
            }
        }

        onError: root.onFailure()
    }

    Timer {
        id: pamWatchdog
        interval: 10000
        running: root.checking
        onTriggered: if (root.checking) root.onFailure()
    }

    Timer {
        id: confirmTimer
        interval: 2500
        onTriggered: root.confirmArmed = false
    }

    Timer {
        id: cooldownTimer
        interval: 1000
        repeat: true
        running: root.cooldown > 0
        onTriggered: {
            root.cooldown = Math.max(0, root.cooldown - 1);
            if (root.cooldown === 0) {
                root.failed = false;
                refreshFailTally();
            }
        }
    }

    Timer {
        id: failReset
        interval: 45000
        onTriggered: {
            root.failCount = 0;
            root.failed = false;
        }
    }

    Timer {
        id: unlockTimer
        interval: 400
        onTriggered: {
            sessionLock.locked = false;
            root.buffer = "";
            root.unlocking = false;
            if (root.oneshot)
                quitTimer.start();
        }
    }

    Timer {
        id: quitTimer
        interval: 300
        onTriggered: Qt.quit()
    }

    Process {
        id: powerProc
    }

    Process {
        id: faillockProc
        command: ["faillock", "--user", Quickshell.env("USER") || "root"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = text.trim().split("\n").filter(l => /^\s*\d{4}-\d{2}-\d{2}/.test(l));
                root.pamRecord = rows.length > 0;
            }
        }
    }

    Process {
        id: resetProc
    }

    Component.onCompleted: {
        if (root.oneshot)
            sessionLock.locked = true;
    }

    // =========================================================================
    // WAYLAND SESSION LOCK
    // =========================================================================
    WlSessionLock {
        id: sessionLock

        onLockedChanged: {
            root.locked = locked;
            if (locked) {
                root.buffer = "";
                root.failed = false;
                root.checking = false;
                root.unlocking = false;
                root.cooldown = 0;
                root.confirmArmed = false;
                confirmTimer.stop();
                failReset.stop();
                refreshFailTally();
                wpFile.reload();
            }
        }

        WlSessionLockSurface {
            id: lockSurface
            color: StyleTokens.black

            readonly property bool isMainOutput: {
                if (!lockSurface.screen) return true;
                if (Quickshell.screens && Quickshell.screens.length > 0)
                    return lockSurface.screen === Quickshell.screens[0];
                return true;
            }

            Item {
                id: scene
                anchors.fill: parent
                focus: true
                opacity: root.unlocking ? 0 : scene.intro

                Timer {
                    interval: 40
                    running: lockSurface.visible
                    onTriggered: scene.arm()
                }

                property bool armed: false
                function arm() {
                    if (scene.armed) return;
                    scene.armed = true;
                }

                property real intro: 0
                NumberAnimation on intro {
                    running: scene.armed
                    from: 0
                    to: 1
                    duration: 220
                    easing.type: Easing.OutQuad
                }

                // Island / Notch to Card morphing animation
                property real openW: 0
                property real openH: 0
                readonly property real morph: Math.min(1, (openW + openH) / 2)
                readonly property bool shown: scene.armed && !root.unlocking

                onShownChanged: {
                    if (shown) {
                        closeAnim.stop();
                        openAnim.restart();
                    } else if (armed) {
                        openAnim.stop();
                        closeAnim.restart();
                    }
                }

                ParallelAnimation {
                    id: openAnim
                    NumberAnimation { target: scene; property: "openW"; to: 1; duration: 380; easing.type: Easing.OutCubic }
                    SequentialAnimation {
                        PauseAnimation { duration: 90 }
                        NumberAnimation { target: scene; property: "openH"; to: 1; duration: 440; easing.type: Easing.OutCubic }
                    }
                }

                ParallelAnimation {
                    id: closeAnim
                    NumberAnimation { target: scene; property: "openH"; to: 0; duration: 280; easing.type: Easing.InOutCubic }
                    SequentialAnimation {
                        PauseAnimation { duration: 70 }
                        NumberAnimation { target: scene; property: "openW"; to: 0; duration: 260; easing.type: Easing.InOutCubic }
                    }
                }

                readonly property real reveal: Math.max(0, Math.min(1, (openH - 0.50) / 0.50))

                property real contentIn: 0
                SequentialAnimation {
                    running: scene.armed
                    PauseAnimation { duration: 160 }
                    NumberAnimation { target: scene; property: "contentIn"; from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic }
                }

                function stage(i) {
                    return Math.max(0, Math.min(1, scene.contentIn * 1.5 - i * 0.25));
                }

                Behavior on opacity {
                    NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                }

                Component.onCompleted: forceActiveFocus()

                Keys.onPressed: event => {
                    event.accepted = true;
                    if (root.checking || root.unlocking)
                        return;
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.submit();
                        return;
                    }
                    if (root.lockedOut || root.pamLocked)
                        return;
                    root.confirmArmed = false;
                    if (event.key === Qt.Key_Backspace) {
                        root.buffer = root.buffer.slice(0, -1);
                    } else if (event.key === Qt.Key_Escape || (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier))) {
                        root.buffer = "";
                    } else if (event.text.length > 0 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                        const ch = event.text.charCodeAt(0);
                        if (ch >= 32 && ch !== 127) {
                            root.buffer += event.text;
                            root.failed = false;
                            failReset.restart();
                        }
                    }
                }

                // -------------------------------------------------------------
                // WALLPAPER BACKDROP WITH BLUR & VIGNETTE
                // -------------------------------------------------------------
                Rectangle {
                    anchors.fill: parent
                    color: StyleTokens.panel
                }

                Image {
                    id: wpImage
                    anchors.fill: parent
                    source: root.wallpaper !== "" ? (root.wallpaper.startsWith("/") || root.wallpaper.startsWith("file://") ? (root.wallpaper.startsWith("file://") ? root.wallpaper : "file://" + encodeURI(root.wallpaper)) : root.wallpaper) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    scale: 1.08
                    opacity: status === Image.Ready ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: 250 }
                    }

                    layer.enabled: root.blurEnabled
                    layer.effect: MultiEffect {
                        autoPaddingEnabled: false
                        blurEnabled: root.blurEnabled
                        blurMax: 32
                        blur: root.blurEnabled ? Math.min(1, scene.intro * 1.25) : 0
                        saturation: root.hasExplicitWallpaper ? 0.90 : 0.06
                        brightness: root.hasExplicitWallpaper ? -0.06 : -0.16
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(StyleTokens.panel.r, StyleTokens.panel.g, StyleTokens.panel.b, root.hasExplicitWallpaper ? 0.25 : 0.40)
                }

                // -------------------------------------------------------------
                // AMBIENT SECONDARY SCREEN VIEW
                // -------------------------------------------------------------
                Item {
                    anchors.fill: parent
                    visible: !lockSurface.isMainOutput

                    Column {
                        anchors.centerIn: parent
                        spacing: 16

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(clock.date, root.clockFmt)
                            font.family: root.heroFont
                            font.pixelSize: 64
                            font.weight: Font.Bold
                            color: StyleTokens.textPrimaryBright
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                            font.family: root.textFont
                            font.pixelSize: 22
                            color: StyleTokens.textSecondary
                        }
                    }
                }

                // -------------------------------------------------------------
                // PRIMARY SCREEN INTERACTIVE LOCK CARD
                // -------------------------------------------------------------
                Item {
                    id: ui
                    anchors.fill: parent
                    visible: lockSurface.isMainOutput

                    Item {
                        id: boxWrap
                        property real shakeOff: 0
                        width: box.width
                        height: box.height

                        readonly property real targetCenterX: ui.width * (userConfig ? userConfig.islandPositionX : 50) / 100
                        readonly property real startTopY: root.islandTopMargin
                        readonly property real finalCenterY: (ui.height - height) / 2

                        x: targetCenterX - width / 2 + shakeOff
                        y: startTopY + (finalCenterY - startTopY) * scene.openH

                        opacity: Math.min(1, scene.morph * 6)
                        scale: 0.98 + 0.02 * scene.morph

                        Connections {
                            target: root
                            function onShake() { shakeAnim.restart(); }
                        }

                        SequentialAnimation {
                            id: shakeAnim
                            NumberAnimation { target: boxWrap; property: "shakeOff"; to: -22; duration: 45 }
                            NumberAnimation { target: boxWrap; property: "shakeOff"; to: 20; duration: 65 }
                            NumberAnimation { target: boxWrap; property: "shakeOff"; to: -12; duration: 65 }
                            NumberAnimation { target: boxWrap; property: "shakeOff"; to: 6; duration: 55 }
                            NumberAnimation { target: boxWrap; property: "shakeOff"; to: 0; duration: 55 }
                        }

                        RectangularGlow {
                            anchors.fill: box
                            glowRadius: 36
                            spread: 0.2
                            color: Qt.rgba(0, 0, 0, 0.55)
                            cornerRadius: box.radius
                            opacity: scene.morph
                        }

                        Rectangle {
                            id: box
                            clip: true
                            readonly property real finalW: 820
                            readonly property real finalH: col.implicitHeight + 36
                            readonly property real finalR: 28

                            width: root.islandW + (finalW - root.islandW) * scene.openW
                            height: root.islandH + (finalH - root.islandH) * scene.openH
                            radius: root.islandR + (finalR - root.islandR) * Math.min(1, scene.openH)
                            topLeftRadius: root.isNotchMode ? (finalR * (1 - (1 - scene.openH))) : radius
                            topRightRadius: root.isNotchMode ? (finalR * (1 - (1 - scene.openH))) : radius
                            color: Qt.rgba(StyleTokens.panel.r, StyleTokens.panel.g, StyleTokens.panel.b, 0.78)
                            border.width: 1
                            border.color: StyleTokens.cardBorder

                            Column {
                                id: col
                                x: 18
                                y: 18
                                width: box.finalW - 36
                                spacing: 14
                                opacity: scene.reveal

                                Row {
                                    id: panels
                                    width: parent.width
                                    height: 310
                                    spacing: 14

                                    // -----------------------------------------
                                    // LEFT PANEL: CLOCK, GREETING & MEDIA
                                    // -----------------------------------------
                                    Rectangle {
                                        id: leftP
                                        width: (parent.width - parent.spacing) / 2
                                        height: parent.height
                                        radius: 20
                                        color: StyleTokens.cardFillActive
                                        border.width: 1
                                        border.color: StyleTokens.cardBorder
                                        opacity: scene.stage(1)
                                        transform: Translate { x: (1 - scene.stage(1)) * -16 }

                                        Column {
                                            anchors.centerIn: parent
                                            width: parent.width - 36
                                            spacing: root.hasMedia ? 10 : 16

                                            // Time Display
                                            Text {
                                                id: clockText
                                                width: parent.width
                                                horizontalAlignment: Text.AlignHCenter
                                                text: Qt.formatDateTime(clock.date, root.clockFmt)
                                                font.family: root.heroFont
                                                font.pixelSize: root.hasMedia ? 34 : 44
                                                font.weight: Font.Bold
                                                color: StyleTokens.textPrimaryBright
                                            }

                                            // Date Display
                                            Text {
                                                id: dateText
                                                width: parent.width
                                                horizontalAlignment: Text.AlignHCenter
                                                text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                                                font.family: root.textFont
                                                font.pixelSize: root.hasMedia ? 14 : 17
                                                color: StyleTokens.textSecondary
                                            }

                                            // Greeting Label
                                            Text {
                                                id: greetingText
                                                width: parent.width
                                                horizontalAlignment: Text.AlignHCenter
                                                text: root.greeting()
                                                font.family: root.textFont
                                                font.pixelSize: root.hasMedia ? 12 : 14
                                                font.weight: Font.DemiBold
                                                color: StyleTokens.accent
                                                elide: Text.ElideRight
                                            }

                                            // Rich Media Player Card
                                            Rectangle {
                                                id: mediaCard
                                                width: parent.width
                                                height: root.hasMedia ? 112 : 0
                                                visible: root.hasMedia
                                                radius: 14
                                                color: StyleTokens.cardFill
                                                border.width: 1
                                                border.color: StyleTokens.cardBorder
                                                clip: true

                                                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 10
                                                    spacing: 12

                                                    // Album Art
                                                    ClippingRectangle {
                                                        Layout.preferredWidth: 64
                                                        Layout.preferredHeight: 64
                                                        radius: 10
                                                        color: StyleTokens.cardFillHover

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: ""
                                                            font.family: root.nerdFont
                                                            font.pixelSize: 22
                                                            color: StyleTokens.textMuted
                                                            visible: artImage.status !== Image.Ready
                                                        }

                                                        Image {
                                                            id: artImage
                                                            anchors.fill: parent
                                                            source: root.trackArtUrl
                                                            fillMode: Image.PreserveAspectCrop
                                                            asynchronous: true
                                                        }
                                                    }

                                                    // Track Info & Controls
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 4

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: root.trackTitle
                                                            font.family: root.textFont
                                                            font.pixelSize: 13
                                                            font.weight: Font.Bold
                                                            color: StyleTokens.textPrimaryBright
                                                            elide: Text.ElideRight
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: root.trackArtist
                                                            font.family: root.textFont
                                                            font.pixelSize: 11
                                                            color: StyleTokens.textSecondary
                                                            elide: Text.ElideRight
                                                        }

                                                        // Playback Controls
                                                        RowLayout {
                                                            spacing: 10

                                                            Rectangle {
                                                                width: 28
                                                                height: 28
                                                                radius: 14
                                                                color: prevMouse.containsMouse ? StyleTokens.cardFillHover : StyleTokens.transparent
                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: "󰒮"
                                                                    font.family: root.nerdFont
                                                                    font.pixelSize: 16
                                                                    color: StyleTokens.textPrimaryBright
                                                                }
                                                                MouseArea {
                                                                    id: prevMouse
                                                                    anchors.fill: parent
                                                                    hoverEnabled: true
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: if (root.activePlayer && root.activePlayer.canGoPrevious) root.activePlayer.previous()
                                                                }
                                                            }

                                                            Rectangle {
                                                                width: 32
                                                                height: 32
                                                                radius: 16
                                                                color: StyleTokens.accent
                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: root.isMediaPlaying ? "󰏤" : "󰐊"
                                                                    font.family: root.nerdFont
                                                                    font.pixelSize: 16
                                                                    color: StyleTokens.textPrimaryBright
                                                                }
                                                                MouseArea {
                                                                    id: playMouse
                                                                    anchors.fill: parent
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: if (root.activePlayer && root.activePlayer.canControl) root.activePlayer.togglePlaying()
                                                                }
                                                            }

                                                            Rectangle {
                                                                width: 28
                                                                height: 28
                                                                radius: 14
                                                                color: nextMouse.containsMouse ? StyleTokens.cardFillHover : StyleTokens.transparent
                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: "󰒭"
                                                                    font.family: root.nerdFont
                                                                    font.pixelSize: 16
                                                                    color: StyleTokens.textPrimaryBright
                                                                }
                                                                MouseArea {
                                                                    id: nextMouse
                                                                    anchors.fill: parent
                                                                    hoverEnabled: true
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: if (root.activePlayer && root.activePlayer.canGoNext) root.activePlayer.next()
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // -----------------------------------------
                                    // RIGHT PANEL: USER PROFILE & PASSWORD
                                    // -----------------------------------------
                                    Rectangle {
                                        id: rightP
                                        width: (parent.width - parent.spacing) / 2
                                        height: parent.height
                                        radius: 20
                                        color: StyleTokens.cardFillActive
                                        border.width: 1
                                        border.color: StyleTokens.cardBorder
                                        opacity: scene.stage(1)
                                        transform: Translate { x: (1 - scene.stage(1)) * 16 }

                                        Column {
                                            anchors.centerIn: parent
                                            width: parent.width - 40
                                            spacing: 14

                                            // Avatar
                                            ClippingRectangle {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: 96
                                                height: 96
                                                radius: 48
                                                color: StyleTokens.cardFillHover
                                                border.width: 2
                                                border.color: StyleTokens.withAlpha(StyleTokens.accent, 0.4)

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: root.userName.charAt(0).toUpperCase()
                                                    color: StyleTokens.accent
                                                    font.family: root.heroFont
                                                    font.pixelSize: 42
                                                    font.weight: Font.Bold
                                                    visible: avatarImg.status !== Image.Ready
                                                }

                                                Image {
                                                    id: avatarImg
                                                    anchors.fill: parent
                                                    source: root.avatarPath !== "" ? (root.avatarPath.startsWith("/") || root.avatarPath.startsWith("file://") ? (root.avatarPath.startsWith("file://") ? root.avatarPath : "file://" + encodeURI(root.avatarPath)) : root.avatarPath) : ""
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    visible: status === Image.Ready
                                                }
                                            }

                                            // Username
                                            Text {
                                                width: parent.width
                                                horizontalAlignment: Text.AlignHCenter
                                                text: root.userName
                                                font.family: root.textFont
                                                font.pixelSize: 20
                                                font.weight: Font.Bold
                                                color: StyleTokens.textPrimaryBright
                                                elide: Text.ElideRight
                                            }

                                            // Password Input Field
                                            Rectangle {
                                                id: field
                                                width: parent.width
                                                height: 44
                                                radius: 22
                                                color: StyleTokens.cardFill
                                                border.width: 1.5
                                                border.color: (root.failed || root.lockedOut)
                                                    ? StyleTokens.danger
                                                    : (root.buffer.length > 0 ? StyleTokens.accent : StyleTokens.cardBorder)

                                                Behavior on border.color {
                                                    ColorAnimation { duration: 180 }
                                                }

                                                SequentialAnimation {
                                                    id: typePulse
                                                    NumberAnimation { target: field; property: "scale"; to: 1.015; duration: 70; easing.type: Easing.OutQuad }
                                                    NumberAnimation { target: field; property: "scale"; to: 1.0; duration: 120; easing.type: Easing.OutQuad }
                                                }

                                                Connections {
                                                    target: root
                                                    function onBufferChanged() {
                                                        if (root.buffer.length > 0)
                                                            typePulse.restart();
                                                    }
                                                }

                                                // Placeholder Text
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Enter Password"
                                                    font.family: root.textFont
                                                    font.pixelSize: 14
                                                    color: StyleTokens.textMuted
                                                    opacity: root.buffer.length === 0 ? 0.85 : 0
                                                    Behavior on opacity {
                                                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                                    }
                                                }

                                                // Password Bullets
                                                Item {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 40
                                                    anchors.rightMargin: 40
                                                    clip: true

                                                    Row {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        spacing: 6

                                                        Repeater {
                                                            model: Math.min(root.buffer.length, 16)

                                                            Rectangle {
                                                                required property int index
                                                                width: 8
                                                                height: 8
                                                                radius: 4
                                                                color: root.failed ? StyleTokens.danger : StyleTokens.accent

                                                                property real pop: 0
                                                                opacity: 0.6 + 0.4 * pop
                                                                scale: 0.8 + 0.2 * pop

                                                                NumberAnimation on pop {
                                                                    from: 0
                                                                    to: 1
                                                                    duration: 250
                                                                    easing.type: Easing.OutCubic
                                                                }

                                                                Behavior on color {
                                                                    ColorAnimation { duration: 160 }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                // Submit Button
                                                Rectangle {
                                                    id: goBtn
                                                    readonly property bool live: root.buffer.length > 0 || root.checking || root.unlocking || root.pamLocked
                                                    width: 32
                                                    height: 32
                                                    radius: 16
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: 6
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    color: StyleTokens.accent
                                                    opacity: live ? (root.lockedOut ? 0.4 : 1.0) : 0
                                                    scale: goArea.pressed ? 0.92 : (live ? 1.0 : 0.6)

                                                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                                    Text {
                                                        id: goIcon
                                                        anchors.centerIn: parent
                                                        text: root.unlocking ? "✓" : (root.checking ? "󰑮" : (root.pamLocked ? "" : "➜"))
                                                        color: StyleTokens.textPrimaryBright
                                                        font.family: root.nerdFont
                                                        font.pixelSize: 15

                                                        NumberAnimation on rotation {
                                                            running: root.checking
                                                            from: 0
                                                            to: 360
                                                            duration: 800
                                                            loops: Animation.Infinite
                                                            onRunningChanged: if (!running) goIcon.rotation = 0
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: goArea
                                                        anchors.fill: parent
                                                        enabled: goBtn.live && !root.lockedOut
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            root.submit();
                                                            scene.forceActiveFocus();
                                                        }
                                                    }
                                                }
                                            }

                                            // Status Text
                                            RowLayout {
                                                width: parent.width
                                                spacing: 6

                                                Text {
                                                    visible: root.failed || root.lockedOut
                                                    text: ""
                                                    color: StyleTokens.danger
                                                    font.family: root.nerdFont
                                                    font.pixelSize: 13
                                                    Layout.alignment: Qt.AlignVCenter
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    horizontalAlignment: Text.AlignHCenter
                                                    wrapMode: Text.WordWrap
                                                    font.family: root.textFont
                                                    font.pixelSize: 11
                                                    color: (root.failed || root.lockedOut) ? StyleTokens.danger : StyleTokens.textSecondary
                                                    text: root.statusText
                                                }
                                            }
                                        }
                                    }
                                }

                                // ---------------------------------------------
                                // BOTTOM BAR: WEATHER + BATTERY & POWER
                                // ---------------------------------------------
                                Item {
                                    id: bottomBar
                                    width: parent.width
                                    height: 44
                                    opacity: scene.stage(2)
                                    transform: Translate { y: (1 - scene.stage(2)) * 8 }

                                    // Left: Weather & Battery Pills
                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8

                                        // Weather Pill
                                        Rectangle {
                                            visible: weatherService.hasData
                                            height: 34
                                            width: weatherRow.implicitWidth + 24
                                            radius: 17
                                            color: StyleTokens.cardFill
                                            border.width: 1
                                            border.color: StyleTokens.cardBorder

                                            RowLayout {
                                                id: weatherRow
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Text {
                                                    text: weatherService.iconGlyph
                                                    color: weatherService.iconColor
                                                    font.family: root.nerdFont
                                                    font.pixelSize: 16
                                                    Layout.alignment: Qt.AlignVCenter
                                                }

                                                Text {
                                                    text: weatherService.tempString
                                                    font.family: root.textFont
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: StyleTokens.textPrimaryBright
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                            }
                                        }

                                        // Battery Pill
                                        Rectangle {
                                            visible: root.hasBattery
                                            height: 34
                                            width: batteryRow.implicitWidth + 24
                                            radius: 17
                                            color: StyleTokens.cardFill
                                            border.width: 1
                                            border.color: StyleTokens.cardBorder

                                            RowLayout {
                                                id: batteryRow
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Text {
                                                    text: root.batteryGlyph(root.batPct)
                                                    color: root.batteryColor(root.batPct)
                                                    font.family: root.nerdFont
                                                    font.pixelSize: 16
                                                    Layout.alignment: Qt.AlignVCenter
                                                }

                                                Text {
                                                    text: root.batPct + "%"
                                                    font.family: root.textFont
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    color: StyleTokens.textPrimaryBright
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                            }
                                        }
                                    }

                                    // Right: Power Action Pills
                                    Row {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8
                                        visible: root.showPowerActions

                                        // Sleep Button
                                        Rectangle {
                                            id: sleepBtn
                                            property bool armed: false
                                            height: 34
                                            width: armed ? 76 : 40
                                            radius: 17
                                            color: armed ? StyleTokens.withAlpha(StyleTokens.danger, 0.45) : (sleepMouse.containsMouse ? StyleTokens.cardFillHover : StyleTokens.cardFill)
                                            border.width: 1
                                            border.color: armed ? StyleTokens.danger : StyleTokens.cardBorder

                                            Behavior on width { NumberAnimation { duration: 120 } }
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text {
                                                    text: ""
                                                    font.family: root.nerdFont
                                                    font.pixelSize: 14
                                                    color: sleepBtn.armed ? StyleTokens.danger : StyleTokens.textPrimaryBright
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Text {
                                                    visible: sleepBtn.armed
                                                    text: "sure?"
                                                    font.family: root.textFont
                                                    font.pixelSize: 11
                                                    color: StyleTokens.danger
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                            }

                                            Timer {
                                                id: sleepTimer
                                                interval: 2600
                                                onTriggered: sleepBtn.armed = false
                                            }

                                            MouseArea {
                                                id: sleepMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (sleepBtn.armed || !root.confirmPower) {
                                                        sleepTimer.stop();
                                                        sleepBtn.armed = false;
                                                        powerProc.command = ["systemctl", "suspend"];
                                                        powerProc.running = true;
                                                    } else {
                                                        sleepBtn.armed = true;
                                                        sleepTimer.restart();
                                                    }
                                                }
                                            }
                                        }

                                        // Reboot Button
                                        Rectangle {
                                            id: rebootBtn
                                            property bool armed: false
                                            height: 34
                                            width: armed ? 76 : 40
                                            radius: 17
                                            color: armed ? StyleTokens.withAlpha(StyleTokens.danger, 0.45) : (rebootMouse.containsMouse ? StyleTokens.cardFillHover : StyleTokens.cardFill)
                                            border.width: 1
                                            border.color: armed ? StyleTokens.danger : StyleTokens.cardBorder

                                            Behavior on width { NumberAnimation { duration: 120 } }
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text {
                                                    text: ""
                                                    font.family: root.nerdFont
                                                    font.pixelSize: 14
                                                    color: rebootBtn.armed ? StyleTokens.danger : StyleTokens.textPrimaryBright
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Text {
                                                    visible: rebootBtn.armed
                                                    text: "sure?"
                                                    font.family: root.textFont
                                                    font.pixelSize: 11
                                                    color: StyleTokens.danger
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                            }

                                            Timer {
                                                id: rebootTimer
                                                interval: 2600
                                                onTriggered: rebootBtn.armed = false
                                            }

                                            MouseArea {
                                                id: rebootMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (rebootBtn.armed || !root.confirmPower) {
                                                        rebootTimer.stop();
                                                        rebootBtn.armed = false;
                                                        powerProc.command = ["systemctl", "reboot"];
                                                        powerProc.running = true;
                                                    } else {
                                                        rebootBtn.armed = true;
                                                        rebootTimer.restart();
                                                    }
                                                }
                                            }
                                        }

                                        // Shutdown Button
                                        Rectangle {
                                            id: shutdownBtn
                                            property bool armed: false
                                            height: 34
                                            width: armed ? 76 : 40
                                            radius: 17
                                            color: armed ? StyleTokens.withAlpha(StyleTokens.danger, 0.45) : (shutdownMouse.containsMouse ? StyleTokens.cardFillHover : StyleTokens.cardFill)
                                            border.width: 1
                                            border.color: armed ? StyleTokens.danger : StyleTokens.cardBorder

                                            Behavior on width { NumberAnimation { duration: 120 } }
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text {
                                                    text: ""
                                                    font.family: root.nerdFont
                                                    font.pixelSize: 14
                                                    color: shutdownBtn.armed ? StyleTokens.danger : StyleTokens.textPrimaryBright
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Text {
                                                    visible: shutdownBtn.armed
                                                    text: "sure?"
                                                    font.family: root.textFont
                                                    font.pixelSize: 11
                                                    color: StyleTokens.danger
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                            }

                                            Timer {
                                                id: shutdownTimer
                                                interval: 2600
                                                onTriggered: shutdownBtn.armed = false
                                            }

                                            MouseArea {
                                                id: shutdownMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (shutdownBtn.armed || !root.confirmPower) {
                                                        shutdownTimer.stop();
                                                        shutdownBtn.armed = false;
                                                        powerProc.command = ["systemctl", "poweroff"];
                                                        powerProc.running = true;
                                                    } else {
                                                        shutdownBtn.armed = true;
                                                        shutdownTimer.restart();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
