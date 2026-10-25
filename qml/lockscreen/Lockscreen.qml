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
import "../common"

Scope {
    id: root

    readonly property var userConfig: UserConfig

    // -------------------------------------------------------------------------
    // FONTS & TYPOGRAPHY
    // -------------------------------------------------------------------------
    FontLoader {
        id: interFont
        source: "../fonts/InterVariable.ttf"
    }

    readonly property string displayFont: (interFont.status === FontLoader.Ready && interFont.name !== "")
        ? interFont.name
        : "Red Hat Display"

    readonly property string textFont: (userConfig && userConfig.textFontFamily !== "" && userConfig.textFontFamily !== "Sans Serif")
        ? userConfig.textFontFamily
        : ((interFont.status === FontLoader.Ready && interFont.name !== "") ? interFont.name : "Red Hat Text")

    readonly property string heroFont: (userConfig && userConfig.heroFontFamily !== "" && userConfig.heroFontFamily !== "Sans Serif")
        ? userConfig.heroFontFamily
        : displayFont

    // For the lockscreen clock, a modern display typeface elevates the aesthetic immensely
    readonly property string timeFont: (userConfig && userConfig.timeFontFamily !== "" && userConfig.timeFontFamily !== "Sans Serif" && !userConfig.timeFontFamily.includes("Mono") && !userConfig.timeFontFamily.includes("FiraCode"))
        ? userConfig.timeFontFamily
        : displayFont

    readonly property string nerdFont: (userConfig && userConfig.iconFontFamily !== "")
        ? userConfig.iconFontFamily
        : "JetBrainsMono Nerd Font"

    readonly property string clockFmt: (userConfig && userConfig.clockFormat === "24") ? "HH:mm" : "hh:mm AP"
    readonly property bool is24h: clockFmt.indexOf("AP") === -1

    // -------------------------------------------------------------------------
    // ENVIRONMENT & ISLAND SIZING
    // -------------------------------------------------------------------------
    readonly property string envWallpaper: Quickshell.env("LOCK_WALLPAPER") || ""
    readonly property string userName: Quickshell.env("USER") || "user"
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property bool oneshot: Quickshell.env("LOCK_NOW") === "1"
    readonly property string pamConfig: (userConfig && userConfig.lockscreenPamService !== "")
        ? userConfig.lockscreenPamService
        : "login"

    property bool locked: false

    function lock(): void {
        wpQueryProc.running = true;
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

    readonly property bool isNotchMode: userConfig ? (userConfig.islandStyle === "notch") : false
    readonly property real islandW: userConfig ? userConfig.islandWidth : 280
    readonly property real islandH: userConfig ? userConfig.islandHeight : 38
    readonly property real islandR: isNotchMode ? 16 : islandH / 2
    readonly property real islandTopMargin: isNotchMode ? 0 : (userConfig ? userConfig.islandTopMargin : 6)

    readonly property string avatarPath: {
        if (userConfig && userConfig.avatarPath !== "")
            return expandHome(userConfig.avatarPath);
        if (typeof SystemGlance !== "undefined" && SystemGlance.avatarPath !== "")
            return SystemGlance.avatarPath;
        return "";
    }

    readonly property bool confirmPower: true
    readonly property bool showPowerActions: userConfig ? userConfig.lockscreenPowerActions : true
    readonly property bool showLockscreenMedia: userConfig ? userConfig.lockscreenMedia : true
    readonly property bool showBatteryPill: userConfig ? userConfig.lockscreenShowBattery : true

    // -------------------------------------------------------------------------
    // BATTERY REPORTING
    // -------------------------------------------------------------------------
    readonly property int batPct: {
        if (typeof SysBackend !== "undefined" && SysBackend.batteryCapacity > 0)
            return SysBackend.batteryCapacity;
        if (typeof SystemGlance !== "undefined" && SystemGlance.batteryCapacity > 0)
            return SystemGlance.batteryCapacity;
        return -1;
    }
    readonly property bool batCharging: {
        const s = (typeof SysBackend !== "undefined" && SysBackend.batteryStatus !== "" && SysBackend.batteryStatus !== "Unknown")
            ? SysBackend.batteryStatus
            : (typeof SystemGlance !== "undefined" ? SystemGlance.batteryStatus : "");
        return s === "Charging" || s === "Full";
    }
    readonly property bool hasBattery: showBatteryPill && batPct > 0

    // Smooth horizontal rounded battery icons matching the control center & system glance
    function batteryGlyph(pct) {
        if (!(pct >= 0)) return "\uf240";
        if (pct >= 85) return "\uf240"; // Full rounded battery
        if (pct >= 60) return "\uf241"; // 3/4
        if (pct >= 35) return "\uf242"; // 1/2
        if (pct >= 15) return "\uf243"; // 1/4
        return "\uf244"; // Empty
    }

    function batteryColor(pct) {
        return StyleTokens.batteryColor(pct, root.batCharging);
    }

    // -------------------------------------------------------------------------
    // WALLPAPER RESOLUTION
    // -------------------------------------------------------------------------
    property string liveDetectedWallpaper: ""

    readonly property string customLockscreenWallpaper: (userConfig && userConfig.lockscreenWallpaperPath !== "")
        ? expandHome(userConfig.lockscreenWallpaperPath)
        : ""
    readonly property bool hasExplicitWallpaper: customLockscreenWallpaper !== ""

    readonly property string detectedWallpaper: {
        if (liveDetectedWallpaper !== "")
            return liveDetectedWallpaper;
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

    Process {
        id: wpQueryProc
        command: [
            "sh", "-c",
            "if command -v awww >/dev/null 2>&1; then "
                + "p=$(awww query 2>/dev/null | sed -n 's/.*image: //p' | head -n1); "
                + "if [ -n \"$p\" ]; then echo \"$p\"; exit 0; fi; "
            + "fi; "
            + "if command -v swww >/dev/null 2>&1; then "
                + "p=$(swww query 2>/dev/null | sed -n 's/.*image: //p' | head -n1); "
                + "if [ -n \"$p\" ]; then echo \"$p\"; exit 0; fi; "
            + "fi; "
            + "if command -v hyprctl >/dev/null 2>&1; then "
                + "p=$(hyprctl hyprpaper listactive 2>/dev/null | head -n1 | awk '{print $NF}'); "
                + "if [ -n \"$p\" ]; then echo \"$p\"; exit 0; fi; "
            + "fi; "
            + "if [ -f ~/.cache/tide-island/last_wallpaper ]; then "
                + "head -n1 ~/.cache/tide-island/last_wallpaper; "
            + "fi"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p.length > 0) {
                    root.liveDetectedWallpaper = p;
                    wpCacheProc.command = ["sh", "-c", "mkdir -p ~/.cache/tide-island && printf '%s\\n' \"$1\" > ~/.cache/tide-island/last_wallpaper", "_", p];
                    wpCacheProc.running = true;
                }
            }
        }
    }

    Process {
        id: wpCacheProc
    }

    // -------------------------------------------------------------------------
    // WEATHER SERVICE
    // -------------------------------------------------------------------------
    WeatherService {
        id: weatherService
    }

    // -------------------------------------------------------------------------
    // MEDIA PLAYER DETECTION (MPRIS)
    // -------------------------------------------------------------------------
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

    property real trackProgress: 0
    property string timePlayed: "0:00"
    property string timeTotal: "0:00"
    property real visualizerPhase: 0

    onActivePlayerChanged: root.syncProgress()

    NumberAnimation {
        id: visualizerAnim
        target: root
        property: "visualizerPhase"
        from: 0
        to: Math.PI * 2
        duration: 1300
        loops: Animation.Infinite
        running: root.isMediaPlaying && root.locked
    }

    function visualizerLevel(index) {
        if (typeof SystemServices !== "undefined" && SystemServices.cavaLevels && SystemServices.cavaLevels.length > index) {
            const val = Number(SystemServices.cavaLevels[index]);
            if (!isNaN(val) && val > 0) return Math.min(1.0, val);
        }
        const phase = root.visualizerPhase + index * 0.88;
        const primary = (Math.sin(phase) + 1) * 0.5;
        const secondary = (Math.sin(phase * 2 + index * 1.15) + 1) * 0.5;
        return 0.18 + primary * 0.48 + secondary * 0.26;
    }

    function formatTime(value) {
        const numberValue = Number(value);
        if (isNaN(numberValue) || numberValue <= 0) return "0:00";

        let totalSeconds = 0;
        if (numberValue < 10000) totalSeconds = Math.floor(numberValue);
        else if (numberValue < 100000000) totalSeconds = Math.floor(numberValue / 1000);
        else totalSeconds = Math.floor(numberValue / 1000000);

        const minutes = Math.floor(totalSeconds / 60);
        const seconds = Math.floor(totalSeconds % 60);
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
    }

    function syncProgress(positionOverride) {
        const player = root.activePlayer;
        if (!player) {
            root.trackProgress = 0;
            root.timePlayed = "0:00";
            root.timeTotal = "0:00";
            return;
        }

        const currentPosition = positionOverride !== undefined
            ? Number(positionOverride) || 0
            : (player.position !== undefined ? Number(player.position) || 0 : 0);
        let totalLength = (player.length !== undefined ? Number(player.length) || 0 : 0);
        if (totalLength <= 0 && player.metadata && player.metadata["mpris:length"])
            totalLength = Number(player.metadata["mpris:length"]);

        if (totalLength > 0) {
            root.trackProgress = Math.max(0, Math.min(1.0, currentPosition / totalLength));
            root.timePlayed = root.formatTime(currentPosition);
            root.timeTotal = root.formatTime(totalLength);
        } else {
            root.trackProgress = 0;
            root.timePlayed = root.formatTime(currentPosition);
            root.timeTotal = "--:--";
        }
    }

    function seekToRatio(ratio) {
        const player = root.activePlayer;
        if (!player) return;

        let totalLength = (player.length !== undefined ? Number(player.length) || 0 : 0);
        if (totalLength <= 0 && player.metadata && player.metadata["mpris:length"])
            totalLength = Number(player.metadata["mpris:length"]);

        if (totalLength > 0) {
            const clampedRatio = Math.max(0, Math.min(1.0, ratio));
            const targetPos = clampedRatio * totalLength;
            if (player.canSeek) {
                if (player.positionSupported)
                    player.position = targetPos;
                else if (typeof player.seek === "function")
                    player.seek(targetPos - (Number(player.position) || 0));
            }
            root.syncProgress(targetPos);
        }
    }

    Timer {
        id: progressPoller
        interval: 500
        repeat: true
        running: root.hasMedia && root.locked
        onTriggered: root.syncProgress()
    }

    // -------------------------------------------------------------------------
    // AUTHENTICATION STATE & LOGIC
    // -------------------------------------------------------------------------
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
            return "Welcome back, " + userName;
        if (pamLocked)
            return "Locked by PAM · Admin reset required";
        if (lockedOut)
            return "Too many attempts · Please wait " + cooldown + "s";
        if (checking)
            return "Verifying credentials…";
        if (confirmArmed)
            return "Press Enter again to submit";
        if (failed)
            return "Incorrect password · " + failCount + (failCount === 1 ? " attempt" : " attempts");
        if (pamRisky)
            return "PAM recorded earlier failures · Press Enter to confirm";
        return "Press Enter to unlock · Esc to clear";
    }

    signal shake()

    function greeting() {
        const h = clock.hours;
        const t = h < 5 ? "Late night" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : h < 22 ? "Good evening" : "Late night";
        return t + ", " + userName;
    }

    function greetingIcon() {
        const h = clock.hours;
        if (h >= 5 && h < 17) return "󰖙"; // Cute sun
        if (h >= 17 && h < 21) return "󰖐"; // Cute sunset cloud
        return "󰖔"; // Cute crescent moon
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

    // 420ms provides a silky exit animation before the session lock surface is dropped
    Timer {
        id: unlockTimer
        interval: 420
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
        wpQueryProc.running = true;
        if (root.oneshot)
            sessionLock.locked = true;
    }

    // =========================================================================
    // WAYLAND SESSION LOCK (ext-session-lock-v1)
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
                wpQueryProc.running = true;
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

                // -------------------------------------------------------------
                // ANIMATION CONTROLLER (IN & OUT)
                // -------------------------------------------------------------
                property bool armed: false
                property real animProgress: 0
                property real exitProgress: 0

                Timer {
                    interval: 30
                    running: lockSurface.visible
                    onTriggered: {
                        scene.armed = true;
                        scene.animProgress = 0;
                        scene.exitProgress = 0;
                        introAnim.restart();
                    }
                }

                NumberAnimation {
                    id: introAnim
                    target: scene
                    property: "animProgress"
                    from: 0
                    to: 1
                    duration: 520
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    id: exitAnim
                    target: scene
                    property: "exitProgress"
                    from: 0
                    to: 1
                    duration: 400
                    easing.type: Easing.OutCubic
                }

                Connections {
                    target: root
                    function onUnlockingChanged() {
                        if (root.unlocking) {
                            exitAnim.restart();
                        } else {
                            scene.exitProgress = 0;
                        }
                    }
                    function onLockedChanged() {
                        if (root.locked) {
                            scene.exitProgress = 0;
                            scene.animProgress = 0;
                            introAnim.restart();
                        }
                    }
                }

                // Stagger helper
                function stage(index) {
                    return Math.max(0, Math.min(1, scene.animProgress * 1.5 - index * 0.25));
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
                // WALLPAPER BACKDROP WITH DYNAMIC BLUR & LUXURIOUS ZOOM
                // -------------------------------------------------------------
                Rectangle {
                    anchors.fill: parent
                    color: StyleTokens.black
                }

                Image {
                    id: wpImage
                    anchors.fill: parent
                    source: root.wallpaper !== "" ? (root.wallpaper.startsWith("/") || root.wallpaper.startsWith("file://") ? (root.wallpaper.startsWith("file://") ? root.wallpaper : "file://" + encodeURI(root.wallpaper)) : root.wallpaper) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize: Qt.size(Math.ceil(parent.width * 1.05), Math.ceil(parent.height * 1.05))

                    // Smooth cinematic zoom: 1.0 -> 1.05 during lock, eases back to 1.0 on unlock
                    scale: 1.00 + 0.05 * scene.animProgress * (1 - scene.exitProgress)
                    opacity: status === Image.Ready ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: 300 }
                    }

                    layer.enabled: root.blurEnabled
                    layer.effect: MultiEffect {
                        autoPaddingEnabled: false
                        blurEnabled: root.blurEnabled
                        blurMax: 36
                        // Blur eases from 0 to 36 on entrance, and from 36 back to 0 on unlock!
                        blur: root.blurEnabled ? Math.max(0, scene.animProgress * (1.0 - scene.exitProgress)) : 0
                        saturation: 0.95
                        brightness: -0.08
                    }
                }

                // Deep ambient glass tint with smooth fade
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(StyleTokens.panel.r * 0.4, StyleTokens.panel.g * 0.4, StyleTokens.panel.b * 0.4, 0.46)
                    opacity: scene.animProgress * (1 - scene.exitProgress)
                }

                // Vignette gradient overlay for depth
                Rectangle {
                    anchors.fill: parent
                    opacity: 0.35 * scene.animProgress * (1 - scene.exitProgress)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.55) }
                        GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.10) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.65) }
                    }
                }

                // -------------------------------------------------------------
                // AMBIENT SECONDARY SCREEN VIEW (MINIMALIST & SLEEK)
                // -------------------------------------------------------------
                Item {
                    anchors.fill: parent
                    visible: !lockSurface.isMainOutput
                    opacity: (1 - scene.exitProgress) * scene.animProgress

                    Column {
                        anchors.centerIn: parent
                        spacing: 20

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(clock.date, root.clockFmt)
                            font.family: root.timeFont
                            font.pixelSize: 96
                            font.weight: Font.Bold
                            font.letterSpacing: -2.5
                            color: StyleTokens.textPrimaryBright
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
                            font.family: root.textFont
                            font.pixelSize: 22
                            font.weight: Font.Medium
                            color: StyleTokens.textSecondary
                        }

                        // Cute ambient weather / greeting pill on secondary screens
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 36
                            width: secRow.implicitWidth + 32
                            radius: 18
                            color: Qt.rgba(255, 255, 255, 0.06)
                            border.width: 1
                            border.color: Qt.rgba(255, 255, 255, 0.10)

                            RowLayout {
                                id: secRow
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: weatherService.hasData ? weatherService.iconGlyph : root.greetingIcon()
                                    color: weatherService.hasData ? weatherService.iconColor : StyleTokens.accent
                                    font.family: root.nerdFont
                                    font.pixelSize: 16
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Text {
                                    text: weatherService.hasData ? (weatherService.tempString + " · " + weatherService.condition) : root.greeting()
                                    font.family: root.textFont
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: StyleTokens.textPrimaryBright
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
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
                        // Fluid morph downwards on open, and gentle upwards float on unlock
                        y: startTopY + (finalCenterY - startTopY) * scene.animProgress - (scene.exitProgress * 18)

                        // Luxurious scale-in on entry, and blooming scale-up on unlock
                        scale: (0.94 + 0.06 * scene.animProgress) * (1.0 + 0.035 * scene.exitProgress)
                        opacity: Math.min(1.0, scene.animProgress * 1.5) * (1.0 - scene.exitProgress)

                        Connections {
                            target: root
                            function onShake() { shakeAnim.restart(); }
                        }

                        // Organic decaying shake on password fail
                        SequentialAnimation {
                            id: shakeAnim
                            NumberAnimation { target: boxWrap; property: "shakeOff"; to: -18; duration: 45; easing.type: Easing.OutQuad }
                            NumberAnimation { target: boxWrap; property: "shakeOff"; to: 16; duration: 55; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: boxWrap; property: "shakeOff"; to: -10; duration: 55; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: boxWrap; property: "shakeOff"; to: 6; duration: 50; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: boxWrap; property: "shakeOff"; to: 0; duration: 45; easing.type: Easing.OutQuad }
                        }

                        // Deep diffused dark drop shadow
                        RectangularGlow {
                            anchors.fill: box
                            glowRadius: 56
                            spread: 0.12
                            color: Qt.rgba(0, 0, 0, 0.70)
                            cornerRadius: box.radius
                            opacity: scene.animProgress * (1 - scene.exitProgress)
                        }

                        // Subtle warm ambient accent glow for depth
                        RectangularGlow {
                            anchors.fill: box
                            glowRadius: 72
                            spread: 0.05
                            color: StyleTokens.withAlpha(StyleTokens.accent, 0.18)
                            cornerRadius: box.radius
                            opacity: scene.animProgress * (1 - scene.exitProgress)
                        }

                        Rectangle {
                            id: box
                            clip: true
                            readonly property real finalW: 800
                            readonly property real finalH: col.implicitHeight + 44
                            readonly property real finalR: 36

                            width: root.islandW + (finalW - root.islandW) * scene.animProgress
                            height: root.islandH + (finalH - root.islandH) * scene.animProgress
                            radius: root.islandR + (finalR - root.islandR) * scene.animProgress
                            topLeftRadius: root.isNotchMode ? (finalR * scene.animProgress) : radius
                            topRightRadius: root.isNotchMode ? (finalR * scene.animProgress) : radius

                            // Premium multi-layered frosted glass body
                            color: Qt.rgba(StyleTokens.panel.r, StyleTokens.panel.g, StyleTokens.panel.b, 0.76)
                            border.width: 1
                            border.color: StyleTokens.surfaceBorder
                            antialiasing: true

                            // Specular glass highlight reflection
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Math.max(0, box.radius - 1)
                                topLeftRadius: box.topLeftRadius > 0 ? Math.max(0, box.topLeftRadius - 1) : 0
                                topRightRadius: box.topRightRadius > 0 ? Math.max(0, box.topRightRadius - 1) : 0
                                bottomLeftRadius: Math.max(0, box.bottomLeftRadius - 1)
                                bottomRightRadius: Math.max(0, box.bottomRightRadius - 1)
                                color: StyleTokens.transparent
                                border.width: 1
                                border.color: StyleTokens.surfaceHighlight
                                gradient: Gradient {
                                    GradientStop { position: 0; color: "#0cffffff" }
                                    GradientStop { position: 0.45; color: "#02ffffff" }
                                    GradientStop { position: 1; color: "#04000000" }
                                }
                                antialiasing: true
                            }

                            Column {
                                id: col
                                x: 22
                                y: 22
                                width: box.finalW - 44
                                spacing: 18
                                opacity: Math.max(0, Math.min(1, (scene.animProgress - 0.20) / 0.50))

                                Row {
                                    id: panels
                                    width: parent.width
                                    height: 312
                                    spacing: 16

                                    // -----------------------------------------
                                    // LEFT PANEL: CLOCK, GREETING & MEDIA/GLANCE
                                    // -----------------------------------------
                                    Rectangle {
                                        id: leftP
                                        width: (parent.width - parent.spacing) / 2
                                        height: parent.height
                                        radius: 26
                                        color: "#13ffffff"
                                        border.width: 1
                                        border.color: StyleTokens.surfaceHighlight
                                        opacity: scene.stage(1)
                                        transform: Translate {
                                            y: (1 - scene.stage(1)) * 14
                                        }
                                        antialiasing: true

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            radius: Math.max(0, leftP.radius - 1)
                                            color: StyleTokens.transparent
                                            border.width: 1
                                            border.color: StyleTokens.surfaceHighlight
                                            gradient: Gradient {
                                                GradientStop { position: 0; color: "#08ffffff" }
                                                GradientStop { position: 0.5; color: "#01ffffff" }
                                                GradientStop { position: 1; color: "#02000000" }
                                            }
                                            antialiasing: true
                                        }

                                        Column {
                                            anchors.centerIn: parent
                                            width: parent.width - 28
                                            spacing: root.hasMedia ? 8 : 16

                                            // Time Display (Modern, Bold, Perfectly Proportioned)
                                            Text {
                                                id: clockText
                                                width: parent.width
                                                horizontalAlignment: Text.AlignHCenter
                                                text: Qt.formatDateTime(clock.date, root.clockFmt)
                                                font.family: root.timeFont
                                                font.pixelSize: root.hasMedia ? (root.is24h ? 50 : 42) : (root.is24h ? 78 : 68)
                                                font.weight: Font.Bold
                                                font.letterSpacing: -1.8
                                                color: StyleTokens.textPrimaryBright
                                            }

                                            // Date Display
                                            Text {
                                                id: dateText
                                                width: parent.width
                                                horizontalAlignment: Text.AlignHCenter
                                                text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
                                                font.family: root.textFont
                                                font.pixelSize: root.hasMedia ? 12 : 15
                                                font.weight: Font.Medium
                                                color: StyleTokens.textSecondary
                                            }

                                            // Cute Greeting Badge with ambient icon
                                            Rectangle {
                                                id: greetingCap
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                height: root.hasMedia ? 24 : 28
                                                width: greetingRow.implicitWidth + 24
                                                radius: height / 2
                                                color: StyleTokens.withAlpha(StyleTokens.accent, 0.12)
                                                border.width: 1
                                                border.color: StyleTokens.withAlpha(StyleTokens.accent, 0.28)
                                                antialiasing: true

                                                RowLayout {
                                                    id: greetingRow
                                                    anchors.centerIn: parent
                                                    spacing: 6

                                                    Text {
                                                        text: root.greetingIcon()
                                                        font.family: root.nerdFont
                                                        font.pixelSize: 13
                                                        color: StyleTokens.accent
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }

                                                    Text {
                                                        text: root.greeting()
                                                        font.family: root.textFont
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                        color: StyleTokens.accent
                                                        Layout.alignment: Qt.AlignVCenter
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            // ---------------------------------
                                            // Rich Media Player Showcase Card (Active)
                                            // ---------------------------------
                                            Rectangle {
                                                id: mediaCard
                                                width: parent.width
                                                height: root.hasMedia ? 164 : 0
                                                visible: root.hasMedia
                                                radius: 20
                                                color: "#30000000"
                                                border.width: 1
                                                border.color: StyleTokens.surfaceHighlight
                                                clip: true
                                                antialiasing: true

                                                Behavior on height {
                                                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                                                }

                                                Column {
                                                    anchors.fill: parent
                                                    anchors.margins: 14
                                                    spacing: 10

                                                    // Row 1: Album Art + Track Info + Live Audio Waveform Visualizer
                                                    RowLayout {
                                                        width: parent.width
                                                        spacing: 12

                                                        // Album Art with rounded squircle and subtle border
                                                        ClippingRectangle {
                                                            Layout.preferredWidth: 48
                                                            Layout.preferredHeight: 48
                                                            radius: 14
                                                            color: StyleTokens.cardFillHover

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "󰝚" // Cute music note
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
                                                                sourceSize: Qt.size(96, 96)
                                                            }
                                                        }

                                                        // Track Title & Artist
                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 2

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
                                                                font.weight: Font.Medium
                                                                color: StyleTokens.textSecondary
                                                                elide: Text.ElideRight
                                                            }
                                                        }

                                                        // Live Animated Audio Visualizer Bars
                                                        Row {
                                                            spacing: 3
                                                            Layout.alignment: Qt.AlignVCenter

                                                            Repeater {
                                                                model: 5

                                                                Rectangle {
                                                                    required property int index
                                                                    width: 3.5
                                                                    height: root.isMediaPlaying
                                                                        ? (4 + 18 * root.visualizerLevel(index))
                                                                        : (4 + 14 * [0.35, 0.65, 0.85, 0.65, 0.35][index])
                                                                    radius: 1.75
                                                                    color: root.isMediaPlaying
                                                                        ? StyleTokens.accent
                                                                        : StyleTokens.withAlpha(StyleTokens.accent, 0.40)
                                                                    anchors.verticalCenter: parent.verticalCenter

                                                                    Behavior on height {
                                                                        NumberAnimation { duration: 75; easing.type: Easing.OutQuad }
                                                                    }
                                                                    Behavior on color {
                                                                        ColorAnimation { duration: 150 }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Row 2: Seekable Progress Bar & Timestamps (Mac / Control Center style)
                                                    RowLayout {
                                                        width: parent.width
                                                        spacing: 8

                                                        Text {
                                                            text: root.timePlayed
                                                            font.family: root.textFont
                                                            font.pixelSize: 10
                                                            font.weight: Font.Medium
                                                            color: trackContainer.isHovered ? StyleTokens.textPrimaryBright : StyleTokens.textMuted
                                                            Layout.alignment: Qt.AlignVCenter
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }

                                                        Item {
                                                            id: trackContainer
                                                            Layout.fillWidth: true
                                                            height: 22

                                                            readonly property bool isHovered: progressMouse.containsMouse || progressMouse.pressed
                                                            readonly property real currentTrackHeight: isHovered ? 14 : 8

                                                            // Mac / Control Center style rounded capsule track
                                                            Rectangle {
                                                                id: trackBg
                                                                anchors.left: parent.left
                                                                anchors.right: parent.right
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                height: trackContainer.currentTrackHeight
                                                                radius: height / 2
                                                                color: trackContainer.isHovered
                                                                    ? Qt.rgba(255, 255, 255, 0.16)
                                                                    : Qt.rgba(255, 255, 255, 0.10)
                                                                border.width: 1
                                                                border.color: trackContainer.isHovered
                                                                    ? Qt.rgba(255, 255, 255, 0.20)
                                                                    : Qt.rgba(255, 255, 255, 0.06)
                                                                clip: true

                                                                Behavior on height {
                                                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                                                }
                                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                                                // Active filled progress capsule
                                                                Rectangle {
                                                                    id: trackFill
                                                                    anchors.left: parent.left
                                                                    anchors.top: parent.top
                                                                    anchors.bottom: parent.bottom
                                                                    radius: parent.radius
                                                                    color: StyleTokens.accent
                                                                    width: root.trackProgress <= 0.001
                                                                        ? 0
                                                                        : Math.min(parent.width, parent.width * Math.max(0, Math.min(1.0, root.trackProgress)))

                                                                    Behavior on width {
                                                                        enabled: !progressMouse.pressed
                                                                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                                                                    }
                                                                }
                                                            }

                                                            MouseArea {
                                                                id: progressMouse
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onPressed: mouse => root.seekToRatio(mouse.x / width)
                                                                onClicked: mouse => root.seekToRatio(mouse.x / width)
                                                                onPositionChanged: mouse => {
                                                                    if (pressed) root.seekToRatio(mouse.x / width)
                                                                }
                                                            }
                                                        }

                                                        Text {
                                                            text: root.timeTotal
                                                            font.family: root.textFont
                                                            font.pixelSize: 10
                                                            font.weight: Font.Medium
                                                            color: trackContainer.isHovered ? StyleTokens.textPrimaryBright : StyleTokens.textMuted
                                                            Layout.alignment: Qt.AlignVCenter
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }
                                                    }

                                                    // Row 3: Perfectly Spaced Hero Playback Controls
                                                    Item {
                                                        width: parent.width
                                                        height: 44

                                                        Row {
                                                            anchors.centerIn: parent
                                                            spacing: 28

                                                            // Previous Button
                                                            Rectangle {
                                                                width: 36
                                                                height: 36
                                                                radius: 18
                                                                color: prevMouse.containsMouse
                                                                    ? StyleTokens.withAlpha(StyleTokens.white, 0.15)
                                                                    : "#13ffffff"
                                                                border.width: 1
                                                                border.color: prevMouse.containsMouse ? StyleTokens.accent : StyleTokens.surfaceHighlight
                                                                scale: prevMouse.pressed ? 0.90 : (prevMouse.containsMouse ? 1.08 : 1.0)
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                antialiasing: true

                                                                Behavior on scale { NumberAnimation { duration: 100 } }
                                                                Behavior on color { ColorAnimation { duration: 120 } }
                                                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: "󰒮"
                                                                    font.family: root.nerdFont
                                                                    font.pixelSize: 16
                                                                    color: prevMouse.containsMouse ? StyleTokens.accent : StyleTokens.textPrimaryBright
                                                                }
                                                                MouseArea {
                                                                    id: prevMouse
                                                                    anchors.fill: parent
                                                                    hoverEnabled: true
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: if (root.activePlayer && root.activePlayer.canGoPrevious) root.activePlayer.previous()
                                                                }
                                                            }

                                                            // Play / Pause Hero Pill
                                                            Rectangle {
                                                                width: 44
                                                                height: 44
                                                                radius: 22
                                                                color: StyleTokens.accent
                                                                scale: playMouse.pressed ? 0.90 : (playMouse.containsMouse ? 1.08 : 1.0)
                                                                anchors.verticalCenter: parent.verticalCenter

                                                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                                                // Ambient glow on play button
                                                                RectangularGlow {
                                                                    anchors.fill: parent
                                                                    glowRadius: 14
                                                                    spread: 0.08
                                                                    color: StyleTokens.withAlpha(StyleTokens.accent, 0.40)
                                                                    cornerRadius: 22
                                                                    opacity: root.isMediaPlaying ? 1.0 : 0.4
                                                                }

                                                                // Pause state: two crisp rounded vertical bars
                                                                Row {
                                                                    anchors.centerIn: parent
                                                                    spacing: 4
                                                                    visible: root.isMediaPlaying

                                                                    Rectangle {
                                                                        width: 3.5
                                                                        height: 14
                                                                        radius: 1.75
                                                                        color: StyleTokens.textOnAccent
                                                                    }
                                                                    Rectangle {
                                                                        width: 3.5
                                                                        height: 14
                                                                        radius: 1.75
                                                                        color: StyleTokens.textOnAccent
                                                                    }
                                                                }

                                                                // Play state: right-pointing triangle
                                                                Canvas {
                                                                    id: playCanvas
                                                                    width: 14
                                                                    height: 14
                                                                    anchors.centerIn: parent
                                                                    anchors.horizontalCenterOffset: 1
                                                                    visible: !root.isMediaPlaying

                                                                    property color fillColor: StyleTokens.textOnAccent
                                                                    onFillColorChanged: requestPaint()
                                                                    onVisibleChanged: if (visible) requestPaint()

                                                                    onPaint: {
                                                                        var ctx = getContext("2d");
                                                                        ctx.reset();
                                                                        ctx.fillStyle = fillColor;
                                                                        ctx.beginPath();
                                                                        ctx.moveTo(1.5, 0.5);
                                                                        ctx.lineTo(13.5, 7.0);
                                                                        ctx.lineTo(1.5, 13.5);
                                                                        ctx.closePath();
                                                                        ctx.fill();
                                                                    }
                                                                }

                                                                MouseArea {
                                                                    id: playMouse
                                                                    anchors.fill: parent
                                                                    hoverEnabled: true
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: if (root.activePlayer && root.activePlayer.canControl) root.activePlayer.togglePlaying()
                                                                }
                                                            }

                                                            // Next Button
                                                            Rectangle {
                                                                width: 36
                                                                height: 36
                                                                radius: 18
                                                                color: nextMouse.containsMouse
                                                                    ? StyleTokens.withAlpha(StyleTokens.white, 0.15)
                                                                    : "#13ffffff"
                                                                border.width: 1
                                                                border.color: nextMouse.containsMouse ? StyleTokens.accent : StyleTokens.surfaceHighlight
                                                                scale: nextMouse.pressed ? 0.90 : (nextMouse.containsMouse ? 1.08 : 1.0)
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                antialiasing: true

                                                                Behavior on scale { NumberAnimation { duration: 100 } }
                                                                Behavior on color { ColorAnimation { duration: 120 } }
                                                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: "󰒭"
                                                                    font.family: root.nerdFont
                                                                    font.pixelSize: 16
                                                                    color: nextMouse.containsMouse ? StyleTokens.accent : StyleTokens.textPrimaryBright
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

                                            // ---------------------------------
                                            // Atmospheric Glance Card (Inactive Media fallback)
                                            // ---------------------------------
                                            Rectangle {
                                                width: parent.width
                                                height: 44
                                                visible: !root.hasMedia
                                                radius: 22
                                                color: "#30000000"
                                                border.width: 1
                                                border.color: StyleTokens.surfaceHighlight
                                                antialiasing: true

                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 8

                                                    Text {
                                                        text: weatherService.hasData ? weatherService.iconGlyph : "󰌾"
                                                        color: weatherService.hasData ? weatherService.iconColor : StyleTokens.accent
                                                        font.family: root.nerdFont
                                                        font.pixelSize: 15
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }

                                                    Text {
                                                        text: weatherService.hasData
                                                            ? (weatherService.tempString + " · " + weatherService.condition)
                                                            : "Session Protected"
                                                        font.family: root.textFont
                                                        font.pixelSize: 12
                                                        font.weight: Font.Medium
                                                        color: StyleTokens.textSecondary
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // -----------------------------------------
                                    // RIGHT PANEL: USER PROFILE & PASSWORD INPUT
                                    // -----------------------------------------
                                    Rectangle {
                                        id: rightP
                                        width: (parent.width - parent.spacing) / 2
                                        height: parent.height
                                        radius: 26
                                        color: "#13ffffff"
                                        border.width: 1
                                        border.color: StyleTokens.surfaceHighlight
                                        opacity: scene.stage(1)
                                        transform: Translate {
                                            y: (1 - scene.stage(1)) * 14
                                        }
                                        antialiasing: true

                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            radius: Math.max(0, rightP.radius - 1)
                                            color: StyleTokens.transparent
                                            border.width: 1
                                            border.color: StyleTokens.surfaceHighlight
                                            gradient: Gradient {
                                                GradientStop { position: 0; color: "#08ffffff" }
                                                GradientStop { position: 0.5; color: "#01ffffff" }
                                                GradientStop { position: 1; color: "#02000000" }
                                            }
                                            antialiasing: true
                                        }

                                        Column {
                                            anchors.centerIn: parent
                                            width: parent.width - 36
                                            spacing: 12

                                            // Avatar with Living Breathing Glass Halo
                                            Item {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: 96
                                                height: 96

                                                // Breathing halo glow
                                                Rectangle {
                                                    id: avatarHalo
                                                    anchors.fill: parent
                                                    radius: width / 2
                                                    color: "transparent"
                                                    border.width: 2
                                                    border.color: StyleTokens.withAlpha(StyleTokens.accent, 0.50)

                                                    SequentialAnimation on opacity {
                                                        loops: Animation.Infinite
                                                        running: true
                                                        NumberAnimation { to: 0.85; duration: 2200; easing.type: Easing.InOutSine }
                                                        NumberAnimation { to: 0.35; duration: 2200; easing.type: Easing.InOutSine }
                                                    }
                                                }

                                                ClippingRectangle {
                                                    anchors.centerIn: parent
                                                    width: 86
                                                    height: 86
                                                    radius: 43
                                                    color: StyleTokens.withAlpha(StyleTokens.panel, 0.85)

                                                    // Monogram fallback with modern typography
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        visible: avatarImg.status !== Image.Ready
                                                        gradient: Gradient {
                                                            GradientStop { position: 0.0; color: StyleTokens.withAlpha(StyleTokens.accent, 0.35) }
                                                            GradientStop { position: 1.0; color: Qt.rgba(255, 255, 255, 0.05) }
                                                        }

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: root.userName.charAt(0).toUpperCase()
                                                            color: StyleTokens.accent
                                                            font.family: root.heroFont
                                                            font.pixelSize: 38
                                                            font.weight: Font.Bold
                                                        }
                                                    }

                                                    Image {
                                                        id: avatarImg
                                                        anchors.fill: parent
                                                        source: {
                                                            if (root.avatarPath === "") return "";
                                                            if (root.avatarPath.startsWith("file://")) return root.avatarPath;
                                                            if (root.avatarPath.startsWith("/")) return "file://" + encodeURI(root.avatarPath);
                                                            return root.avatarPath;
                                                        }
                                                        fillMode: Image.PreserveAspectCrop
                                                        asynchronous: true
                                                        sourceSize: Qt.size(172, 172)
                                                        visible: status === Image.Ready
                                                    }
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
                                                font.letterSpacing: 0.2
                                                color: StyleTokens.textPrimaryBright
                                                elide: Text.ElideRight
                                            }

                                            // Password Input Field (Modern Frosted Glass Pill)
                                            Rectangle {
                                                id: field
                                                width: parent.width
                                                height: 48
                                                radius: 24
                                                color: "#30000000"
                                                border.width: 1.5
                                                border.color: (root.failed || root.lockedOut)
                                                    ? StyleTokens.danger
                                                    : (root.buffer.length > 0 ? StyleTokens.accent : StyleTokens.surfaceHighlight)
                                                antialiasing: true

                                                Behavior on border.color {
                                                    ColorAnimation { duration: 180 }
                                                }

                                                SequentialAnimation {
                                                    id: typePulse
                                                    NumberAnimation { target: field; property: "scale"; to: 1.018; duration: 60; easing.type: Easing.OutQuad }
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
                                                    font.pixelSize: 13
                                                    font.weight: Font.Medium
                                                    color: StyleTokens.textMuted
                                                    opacity: root.buffer.length === 0 ? 0.75 : 0
                                                    Behavior on opacity {
                                                        NumberAnimation { duration: 160 }
                                                    }
                                                }

                                                // Password Bullets (Cute Glowing Pearls)
                                                Item {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 44
                                                    anchors.rightMargin: 44
                                                    clip: true

                                                    Row {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        spacing: root.buffer.length > 8 ? Math.max(5, 9 - (root.buffer.length - 8) * 0.6) : 9

                                                        Repeater {
                                                            model: Math.min(root.buffer.length, 16)

                                                            Rectangle {
                                                                required property int index
                                                                width: 14
                                                                height: 14
                                                                radius: 7
                                                                color: root.failed ? StyleTokens.danger : StyleTokens.accent

                                                                property real pop: 0
                                                                opacity: 0.6 + 0.4 * pop
                                                                scale: 0.4 + 0.6 * pop

                                                                NumberAnimation on pop {
                                                                    from: 0
                                                                    to: 1
                                                                    duration: 220
                                                                    easing.type: Easing.OutBack
                                                                }

                                                                Behavior on color {
                                                                    ColorAnimation { duration: 160 }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                // Submit Button with Cute Animated State
                                                Rectangle {
                                                    id: goBtn
                                                    readonly property bool live: root.buffer.length > 0 || root.checking || root.unlocking || root.pamLocked
                                                    width: 36
                                                    height: 36
                                                    radius: 18
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: 6
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    color: root.unlocking ? StyleTokens.success : StyleTokens.accent
                                                    opacity: live ? (root.lockedOut ? 0.4 : 1.0) : 0
                                                    scale: goArea.pressed ? 0.90 : (live ? 1.0 : 0.6)

                                                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                    Behavior on color { ColorAnimation { duration: 180 } }

                                                    Text {
                                                        id: goIcon
                                                        anchors.centerIn: parent
                                                        text: root.unlocking ? "󰄬" : (root.checking ? "󰑮" : (root.pamLocked ? "󰌾" : "󰁔"))
                                                        color: StyleTokens.textOnAccent
                                                        font.family: root.nerdFont
                                                        font.pixelSize: 17
                                                        font.weight: Font.Bold

                                                        NumberAnimation on rotation {
                                                            running: root.checking
                                                            from: 0
                                                            to: 360
                                                            duration: 750
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

                                            // Status Feedback Row
                                            RowLayout {
                                                width: parent.width
                                                spacing: 6

                                                Text {
                                                    visible: root.failed || root.lockedOut
                                                    text: "󰀦" // Warning
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
                                                    font.weight: Font.Medium
                                                    color: (root.failed || root.lockedOut) ? StyleTokens.danger : StyleTokens.textSecondary
                                                    text: root.statusText
                                                }
                                            }
                                        }
                                    }
                                }

                                // ---------------------------------------------
                                // BOTTOM DOCK: WEATHER, BATTERY & POWER ACTIONS
                                // ---------------------------------------------
                                Item {
                                    id: bottomBar
                                    width: parent.width
                                    height: 40
                                    opacity: scene.stage(2)
                                    transform: Translate {
                                        y: (1 - scene.stage(2)) * 8
                                    }

                                    // Left: Weather & Battery Pills
                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10

                                        // Weather Pill
                                        Rectangle {
                                            visible: weatherService.hasData
                                            height: 36
                                            width: weatherRow.implicitWidth + 24
                                            radius: 18
                                            color: "#13ffffff"
                                            border.width: 1
                                            border.color: StyleTokens.surfaceHighlight
                                            antialiasing: true

                                            RowLayout {
                                                id: weatherRow
                                                anchors.centerIn: parent
                                                spacing: 7

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
                                            height: 36
                                            width: batteryRow.implicitWidth + 24
                                            radius: 18
                                            color: "#13ffffff"
                                            border.width: 1
                                            border.color: StyleTokens.surfaceHighlight
                                            antialiasing: true

                                            RowLayout {
                                                id: batteryRow
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Row {
                                                    spacing: 4
                                                    Layout.alignment: Qt.AlignVCenter

                                                    Text {
                                                        text: root.batteryGlyph(root.batPct)
                                                        color: root.batteryColor(root.batPct)
                                                        font.family: root.nerdFont
                                                        font.pixelSize: 15
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }

                                                    Text {
                                                        visible: root.batCharging
                                                        text: "\uf0e7" // Cute charging bolt from Control Center
                                                        color: StyleTokens.batteryCharging
                                                        font.family: root.nerdFont
                                                        font.pixelSize: 12
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
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

                                    // Right: Cute Power Action Pills
                                    Row {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8
                                        visible: root.showPowerActions

                                        // Sleep Button (Cute Snooze)
                                        Rectangle {
                                            id: sleepBtn
                                            property bool armed: false
                                            height: 36
                                            width: armed ? 90 : 36
                                            radius: 18
                                            color: armed ? StyleTokens.withAlpha(StyleTokens.danger, 0.45)
                                                         : (sleepMouse.containsMouse ? StyleTokens.withAlpha(StyleTokens.accent, 0.22)
                                                                                     : "#13ffffff")
                                            border.width: 1
                                            border.color: armed ? StyleTokens.danger
                                                                : (sleepMouse.containsMouse ? StyleTokens.accent
                                                                                            : StyleTokens.surfaceHighlight)
                                            scale: sleepMouse.pressed ? 0.92 : (sleepMouse.containsMouse ? 1.05 : 1.0)
                                            antialiasing: true

                                            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Behavior on border.color { ColorAnimation { duration: 150 } }
                                            Behavior on scale { NumberAnimation { duration: 100 } }

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 5
                                                Text {
                                                    text: "󰒲" // Cute Zzz snooze moon
                                                    font.family: root.nerdFont
                                                    font.pixelSize: 16
                                                    color: sleepBtn.armed ? StyleTokens.danger
                                                                          : (sleepMouse.containsMouse ? StyleTokens.accent
                                                                                                      : StyleTokens.textPrimaryBright)
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Text {
                                                    visible: sleepBtn.armed
                                                    text: "Sleep?"
                                                    font.family: root.textFont
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
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

                                        // Reboot Button (Cute Rounded Refresh)
                                        Rectangle {
                                            id: rebootBtn
                                            property bool armed: false
                                            height: 36
                                            width: armed ? 94 : 36
                                            radius: 18
                                            color: armed ? StyleTokens.withAlpha(StyleTokens.danger, 0.45)
                                                         : (rebootMouse.containsMouse ? StyleTokens.withAlpha(StyleTokens.accent, 0.22)
                                                                                      : "#13ffffff")
                                            border.width: 1
                                            border.color: armed ? StyleTokens.danger
                                                                : (rebootMouse.containsMouse ? StyleTokens.accent
                                                                                             : StyleTokens.surfaceHighlight)
                                            scale: rebootMouse.pressed ? 0.92 : (rebootMouse.containsMouse ? 1.05 : 1.0)
                                            antialiasing: true

                                            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Behavior on border.color { ColorAnimation { duration: 150 } }
                                            Behavior on scale { NumberAnimation { duration: 100 } }

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 5
                                                Text {
                                                    text: "󰑓" // Cute rounded sync
                                                    font.family: root.nerdFont
                                                    font.pixelSize: 16
                                                    color: rebootBtn.armed ? StyleTokens.danger
                                                                           : (rebootMouse.containsMouse ? StyleTokens.accent
                                                                                                        : StyleTokens.textPrimaryBright)
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Text {
                                                    visible: rebootBtn.armed
                                                    text: "Restart?"
                                                    font.family: root.textFont
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
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

                                        // Shutdown Button (Cute Soft Power)
                                        Rectangle {
                                            id: shutdownBtn
                                            property bool armed: false
                                            height: 36
                                            width: armed ? 90 : 36
                                            radius: 18
                                            color: armed ? StyleTokens.withAlpha(StyleTokens.danger, 0.45)
                                                         : (shutdownMouse.containsMouse ? StyleTokens.withAlpha(StyleTokens.danger, 0.25)
                                                                                        : "#13ffffff")
                                            border.width: 1
                                            border.color: armed ? StyleTokens.danger
                                                                : (shutdownMouse.containsMouse ? StyleTokens.danger
                                                                                               : StyleTokens.surfaceHighlight)
                                            scale: shutdownMouse.pressed ? 0.92 : (shutdownMouse.containsMouse ? 1.05 : 1.0)
                                            antialiasing: true

                                            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Behavior on border.color { ColorAnimation { duration: 150 } }
                                            Behavior on scale { NumberAnimation { duration: 100 } }

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 5
                                                Text {
                                                    text: "󰐥" // Cute soft power
                                                    font.family: root.nerdFont
                                                    font.pixelSize: 16
                                                    color: shutdownBtn.armed ? StyleTokens.danger
                                                                             : (shutdownMouse.containsMouse ? StyleTokens.danger
                                                                                                            : StyleTokens.textPrimaryBright)
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Text {
                                                    visible: shutdownBtn.armed
                                                    text: "Power?"
                                                    font.family: root.textFont
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
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
