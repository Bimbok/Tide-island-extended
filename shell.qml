import QtQuick
import Quickshell
import Quickshell.Io
import IslandBackend
import "qml/island"

Scope {
    id: shellRoot

    readonly property bool screenRecordingActive: SystemServices.screenRecordingActive
    readonly property bool micActive: SystemServices.micActive
    readonly property bool cameraActive: SystemServices.cameraActive
    readonly property bool privacyActive: SystemServices.privacyActive
    readonly property var activePrivacyApps: SystemServices.activePrivacyApps
    property bool focusEnabled: false
    property bool nightLightEnabled: false
    property bool shuttingDown: false
    property bool islandAutoHideRuntimeEnabled: true

    readonly property var userConfig: UserConfig
    readonly property string clipboardHelperScriptPath: {
        const candidate = Qt.resolvedUrl("scripts/cliphist-helper.sh").toString();
        return candidate.startsWith("file://")
            ? decodeURIComponent(candidate.substring(7))
            : "/usr/share/tide-island/scripts/cliphist-helper.sh";
    }

    // Keep clipboard history recording for the lifetime of the shell, even
    // while the clipboard panel is closed.
    Process {
        command: ["bash", shellRoot.clipboardHelperScriptPath, "watch"]
        running: true
    }

    WeatherService {
        id: globalWeatherService
    }
    readonly property var weatherService: globalWeatherService

    function forEachWindow(callback) {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window)
                callback(window);
        }
    }

    function showNotificationAll(id, appName, appIcon, summary, body, actions, imagePath, urgency, senderPid) {
        if (focusEnabled)
            return;

        shellRoot.forEachWindow((window) => {
            if (window && window.showNotification)
                window.showNotification(id, appName, appIcon, summary, body, actions, imagePath, urgency, senderPid);
        });
    }

    function anyOverviewOpen() {
        if (CompositorBackend.compositor === "niri")
            return false;

        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && window.overviewPhase !== "closed")
                return true;
        }

        return false;
    }

    function prepareOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        shellRoot.forEachWindow((window) => window.prepareOverview());
    }

    function cancelPreparedOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        shellRoot.forEachWindow((window) => window.cancelPreparedOverview());
    }

    function openOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        shellRoot.forEachWindow((window) => window.openOverview());
    }

    function closeOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        shellRoot.forEachWindow((window) => window.closeOverview());
    }

    function toggleOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        if (shellRoot.anyOverviewOpen())
            shellRoot.closeOverviewAll();
        else
            shellRoot.openOverviewAll();
    }

    function anyIslandShown() {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && window.autoHideTargetVisible)
                return true;
        }

        return false;
    }

    function showIslandAll() {
        shellRoot.forEachWindow((window) => {
            if (window && window.showIslandWindow)
                window.showIslandWindow();
        });
    }

    function hideIslandAll() {
        shellRoot.forEachWindow((window) => {
            if (window && window.hideIslandWindow)
                window.hideIslandWindow();
        });
    }

    function toggleIslandAll() {
        if (shellRoot.anyIslandShown())
            shellRoot.hideIslandAll();
        else
            shellRoot.showIslandAll();
    }

    function refreshIslandAutoHideAll() {
        shellRoot.forEachWindow((window) => {
            if (window && window.refreshAutoHideWindow)
                window.refreshAutoHideWindow();
        });
    }

    function refreshOverviewWallpaperCaches(wallpaperPath) {
        shellRoot.forEachWindow((window) => {
            if (window
                    && wallpaperPath !== undefined
                    && wallpaperPath !== null
                    && String(wallpaperPath) !== "") {
                window.wallpaperPickerActiveWallpaper = String(wallpaperPath);
            }
            if (window && window.prewarmWallpaperCache)
                window.prewarmWallpaperCache();
        });
    }

    function forFocusedWindow(callback) {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        let fallbackWindow = null;
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && !fallbackWindow)
                fallbackWindow = window;
            if (window && window.monitorFocused) {
                callback(window);
                return;
            }
        }

        if (fallbackWindow)
            callback(fallbackWindow);
    }

    IpcHandler {
        target: "overview"

        function toggle() {
            shellRoot.toggleOverviewAll();
        }

        function open() {
            shellRoot.openOverviewAll();
        }

        function close() {
            shellRoot.closeOverviewAll();
        }

        function refreshWallpaperCache() {
            shellRoot.refreshOverviewWallpaperCaches();
        }
    }

    IpcHandler {
        target: "island"

        function show() {
            shellRoot.showIslandAll();
        }

        function open() {
            shellRoot.showIslandAll();
        }

        function reveal() {
            shellRoot.showIslandAll();
        }

        function hide() {
            shellRoot.hideIslandAll();
        }

        function toggle() {
            shellRoot.toggleIslandAll();
        }

        function enableAutoHide() {
            shellRoot.islandAutoHideRuntimeEnabled = true;
            shellRoot.refreshIslandAutoHideAll();
        }

        function disableAutoHide() {
            shellRoot.islandAutoHideRuntimeEnabled = false;
            shellRoot.showIslandAll();
        }

        function toggleStyle() {
            shellRoot.userConfig.toggleIslandStyle();
        }

        function setStyle(styleName) {
            shellRoot.userConfig.setIslandStyle(styleName);
        }
    }

    IpcHandler {
        target: "tide"

        function toggleStyle() {
            shellRoot.userConfig.toggleIslandStyle();
        }

        function setStyle(styleName) {
            shellRoot.userConfig.setIslandStyle(styleName);
        }

        function showClock() {
            shellRoot.forFocusedWindow((window) => window.showClockWindow());
        }

        function showTimer() {
            shellRoot.forFocusedWindow((window) => window.showTimerWindow());
        }

        function showCustom() {
            shellRoot.forFocusedWindow((window) => window.showCustomInfoWindow());
        }

        function showLyrics() {
            shellRoot.forFocusedWindow((window) => window.showLyricsWindow());
        }

        function swipeRight() {
            shellRoot.forFocusedWindow((window) => window.swipeRightWindow());
        }

        function swipeLeft() {
            shellRoot.forFocusedWindow((window) => window.swipeLeftWindow());
        }

        function togglePlayer() {
            shellRoot.forFocusedWindow((window) => window.togglePlayerWindow());
        }

        function showPlayer() {
            shellRoot.forFocusedWindow((window) => window.togglePlayerWindow());
        }

        function toggleControlCenter() {
            shellRoot.forFocusedWindow((window) => window.toggleControlCenterWindow());
        }

        function showControlCenter() {
            shellRoot.forFocusedWindow((window) => window.toggleControlCenterWindow());
        }

        function togglePowerMenu() {
            shellRoot.forFocusedWindow((window) => window.togglePowerMenuWindow());
        }

        function showPowerMenu() {
            shellRoot.forFocusedWindow((window) => window.togglePowerMenuWindow());
        }

        function toggleNotificationCenter() {
            shellRoot.forFocusedWindow((window) => window.toggleNotificationCenterWindow());
        }

        function showNotificationCenter() {
            shellRoot.forFocusedWindow((window) => window.toggleNotificationCenterWindow());
        }

        function toggleWallpaperPicker() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }

        function showWallpaperPicker() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }

        function toggleWallpaperSwitcher() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }

        function toggleApplicationLauncher() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }

        function showApplicationLauncher() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }

        function toggleLauncher() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }

        function toggleAppLauncher() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }

        function toggleFileShelf() {
            shellRoot.forFocusedWindow((window) => window.toggleFileShelfWindow());
        }

        function showFileShelf() {
            shellRoot.forFocusedWindow((window) => window.toggleFileShelfWindow());
        }

        function togglePrivacyHud() {
            shellRoot.forFocusedWindow((window) => window.togglePrivacyHudWindow());
        }

        function showPrivacyHud() {
            shellRoot.forFocusedWindow((window) => window.showPrivacyHudWindow());
        }

        function toggleRecording() {
            ScreenRecorder.toggleRecording();
        }

        function toggleRecorderMic() {
            ScreenRecorder.toggleMic();
        }

        function toggleReplay() {
            ScreenRecorder.toggleReplay();
        }

        function saveReplay() {
            ScreenRecorder.saveReplay(0);
        }

        function toggleClipboard() {
            shellRoot.forFocusedWindow((window) => window.toggleClipboardWindow());
        }

        function showClipboard() {
            shellRoot.forFocusedWindow((window) => window.showClipboardWindow ? window.showClipboardWindow() : window.toggleClipboardWindow());
        }

        function openClipboard() {
            shellRoot.forFocusedWindow((window) => window.showClipboardWindow ? window.showClipboardWindow() : window.toggleClipboardWindow());
        }

        function closeClipboard() {
            shellRoot.forFocusedWindow((window) => window.closeClipboardWindow ? window.closeClipboardWindow() : window.toggleClipboardWindow());
        }

        function toggleWeather() {
            shellRoot.forFocusedWindow((window) => window.toggleWeatherWindow());
        }

        function showWeather() {
            shellRoot.forFocusedWindow((window) => window.showWeatherWindow ? window.showWeatherWindow() : window.toggleWeatherWindow());
        }

        function openWeather() {
            shellRoot.forFocusedWindow((window) => window.showWeatherWindow ? window.showWeatherWindow() : window.toggleWeatherWindow());
        }

        function closeWeather() {
            shellRoot.forFocusedWindow((window) => window.closeWeatherWindow ? window.closeWeatherWindow() : window.toggleWeatherWindow());
        }

        function toggleCalendar() {
            shellRoot.forFocusedWindow((window) => window.toggleCalendarWindow());
        }

        function showCalendar() {
            shellRoot.forFocusedWindow((window) => window.showCalendarWindow ? window.showCalendarWindow() : window.toggleCalendarWindow());
        }

        function openCalendar() {
            shellRoot.forFocusedWindow((window) => window.showCalendarWindow ? window.showCalendarWindow() : window.toggleCalendarWindow());
        }

        function closeCalendar() {
            shellRoot.forFocusedWindow((window) => window.closeCalendarWindow ? window.closeCalendarWindow() : window.toggleCalendarWindow());
        }

        function togglePrivacy() {
            shellRoot.forFocusedWindow((window) => window.togglePrivacyHudWindow());
        }

        function showPrivacy() {
            shellRoot.forFocusedWindow((window) => window.showPrivacyHudWindow());
        }

        function openPrivacy() {
            shellRoot.forFocusedWindow((window) => window.showPrivacyHudWindow());
        }

        function closePrivacy() {
            shellRoot.forFocusedWindow((window) => window.closePrivacyHudWindow ? window.closePrivacyHudWindow() : window.togglePrivacyHudWindow());
        }

        function toggleGlance() {
            shellRoot.forFocusedWindow((window) => window.toggleGlanceWindow ? window.toggleGlanceWindow() : null);
        }

        function showGlance() {
            shellRoot.forFocusedWindow((window) => window.showGlanceWindow ? window.showGlanceWindow() : null);
        }

        function openGlance() {
            shellRoot.forFocusedWindow((window) => window.showGlanceWindow ? window.showGlanceWindow() : null);
        }

        function closeGlance() {
            shellRoot.forFocusedWindow((window) => window.closeGlanceWindow ? window.closeGlanceWindow() : null);
        }

        function toggleDashboard() {
            shellRoot.forFocusedWindow((window) => window.toggleGlanceWindow ? window.toggleGlanceWindow() : null);
        }

        function showDashboard() {
            shellRoot.forFocusedWindow((window) => window.showGlanceWindow ? window.showGlanceWindow() : null);
        }

        function openDashboard() {
            shellRoot.forFocusedWindow((window) => window.showGlanceWindow ? window.showGlanceWindow() : null);
        }

        function closeDashboard() {
            shellRoot.forFocusedWindow((window) => window.closeGlanceWindow ? window.closeGlanceWindow() : null);
        }

        function reloadTheme() {
            StyleTokens.reload();
        }

        function reloadColors() {
            StyleTokens.reload();
        }
    }

    IpcHandler {
        target: "theme"

        function reload() {
            StyleTokens.reload();
        }
    }

    IpcHandler {
        target: "clipboard"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.toggleClipboardWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.showClipboardWindow ? window.showClipboardWindow() : window.toggleClipboardWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.showClipboardWindow ? window.showClipboardWindow() : window.toggleClipboardWindow());
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.closeClipboardWindow ? window.closeClipboardWindow() : window.toggleClipboardWindow());
        }
    }

    IpcHandler {
        target: "weather"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.toggleWeatherWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.showWeatherWindow ? window.showWeatherWindow() : window.toggleWeatherWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.showWeatherWindow ? window.showWeatherWindow() : window.toggleWeatherWindow());
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.closeWeatherWindow ? window.closeWeatherWindow() : window.toggleWeatherWindow());
        }

        function refresh() {
            if (shellRoot.weatherService)
                shellRoot.weatherService.refresh();
        }
    }

    IpcHandler {
        target: "calendar"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.toggleCalendarWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.showCalendarWindow ? window.showCalendarWindow() : window.toggleCalendarWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.showCalendarWindow ? window.showCalendarWindow() : window.toggleCalendarWindow());
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.closeCalendarWindow ? window.closeCalendarWindow() : window.toggleCalendarWindow());
        }
    }

    IpcHandler {
        target: "privacy"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.togglePrivacyHudWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.showPrivacyHudWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.showPrivacyHudWindow());
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.closePrivacyHudWindow ? window.closePrivacyHudWindow() : window.togglePrivacyHudWindow());
        }
    }

    IpcHandler {
        target: "glance"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.toggleGlanceWindow ? window.toggleGlanceWindow() : null);
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.showGlanceWindow ? window.showGlanceWindow() : null);
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.showGlanceWindow ? window.showGlanceWindow() : null);
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.closeGlanceWindow ? window.closeGlanceWindow() : null);
        }
    }

    IpcHandler {
        target: "dashboard"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.toggleGlanceWindow ? window.toggleGlanceWindow() : null);
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.showGlanceWindow ? window.showGlanceWindow() : null);
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.showGlanceWindow ? window.showGlanceWindow() : null);
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.closeGlanceWindow ? window.closeGlanceWindow() : null);
        }
    }

    IpcHandler {
        target: "recorder"

        function toggle() {
            ScreenRecorder.toggleRecording();
        }

        function start() {
            ScreenRecorder.startRecording();
        }

        function stop() {
            ScreenRecorder.stopRecording();
        }

        function pause() {
            ScreenRecorder.pauseRecording();
        }

        function toggleMic() {
            ScreenRecorder.toggleMic();
        }

        function toggleReplay() {
            ScreenRecorder.toggleReplay();
        }

        function saveReplay(seconds: int) {
            ScreenRecorder.saveReplay(seconds);
        }

        function openRecordings() {
            ScreenRecorder.openRecordingsFolder();
        }

        function openReplays() {
            ScreenRecorder.openReplaysFolder();
        }
    }

    IpcHandler {
        target: "controlCenter"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.toggleControlCenterWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.toggleControlCenterWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.toggleControlCenterWindow());
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.toggleControlCenterWindow());
        }
    }

    IpcHandler {
        target: "player"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.togglePlayerWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.togglePlayerWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.togglePlayerWindow());
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.togglePlayerWindow());
        }
    }

    IpcHandler {
        target: "powerMenu"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.togglePowerMenuWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.togglePowerMenuWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.togglePowerMenuWindow());
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.togglePowerMenuWindow());
        }
    }

    IpcHandler {
        target: "notificationCenter"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.toggleNotificationCenterWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.toggleNotificationCenterWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.toggleNotificationCenterWindow());
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.toggleNotificationCenterWindow());
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }
    }

    IpcHandler {
        target: "appLauncher"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }
    }

    IpcHandler {
        target: "fileShelf"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.toggleFileShelfWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.toggleFileShelfWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.toggleFileShelfWindow());
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.toggleFileShelfWindow());
        }
    }

    IpcHandler {
        target: "wallpaperPicker"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }
    }

    IpcHandler {
        target: "wallpaperSwitcher"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }

        function close() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }
    }

    IpcHandler {
        target: "clock"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.showClockWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.showClockWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.showClockWindow());
        }
    }

    IpcHandler {
        target: "timer"

        function toggle() {
            shellRoot.forFocusedWindow((window) => window.showTimerWindow());
        }

        function show() {
            shellRoot.forFocusedWindow((window) => window.showTimerWindow());
        }

        function open() {
            shellRoot.forFocusedWindow((window) => window.showTimerWindow());
        }
    }

    Connections {
        target: SystemServices

        function onNotificationReceived(id, appName, appIcon, summary, body, actions, imagePath, urgency, senderPid) {
            shellRoot.showNotificationAll(id, appName, appIcon, summary, body, actions, imagePath, urgency, senderPid);
        }
    }

    Component.onDestruction: {
        shuttingDown = true;
    }

    Component.onCompleted: {
        SystemServices.ensureUserConfigAvailable();
        SystemServices.requestScreenRecordingSnapshot();
    }

    Variants {
        id: panelVariants

        model: Quickshell.screens

        DynamicIslandWindow {
            required property var modelData

            screen: modelData
            shellRootController: shellRoot
        }
    }
}
