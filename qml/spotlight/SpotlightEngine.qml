pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import IslandBackend
import "Calc.js" as Calc
import "Match.js" as Match
import "Frecency.js" as Frecency
import "Web.js" as Web
import "../common/ApplicationSearch.js" as ApplicationSearch
import "../common/DesktopAppLauncher.js" as DesktopAppLauncher

Item {
    id: root

    property string query: ""
    property bool active: false
    property string homeDirectory: Quickshell.env("HOME") || ""

    // Results exposed to QML UI
    property var calcResult: null
    property var urlResult: null
    property var actionResults: []
    property var applicationResults: []
    property var clipboardResults: []
    property var fileResults: []
    property var webResult: null

    // In-memory cached clipboard history items
    property var cachedClips: []

    readonly property string helperScriptPath: {
        const candidate = Qt.resolvedUrl("../../scripts/cliphist-helper.sh").toString();
        if (candidate.startsWith("file://")) {
            return decodeURIComponent(candidate.substring(7));
        }
        return "/usr/share/tide-island/scripts/cliphist-helper.sh";
    }

    onActiveChanged: {
        if (root.active) {
            loadClipboardHistory();
        }
    }

    Component.onCompleted: {
        if (root.active) {
            loadClipboardHistory();
        }
    }

    function loadClipboardHistory() {
        if (!cliphistProcess.running) {
            cliphistProcess.running = true;
        }
    }

    // Combined flat list for easy keyboard navigation
    property var allResults: []
    property int selectedIndex: 0
    readonly property int totalResultCount: allResults.length

    signal executeRequested(var item)
    signal actionTriggered(string actionKey)

    // Curated Tide Island native system actions
    readonly property var systemActions: [
        {
            id: "action:lock",
            key: "lock",
            title: "Lock Screen",
            subtitle: "Lock current Wayland session (tide-island-lock)",
            icon: "\uf023",
            category: "System Action",
            keywords: ["lock", "lockscreen", "screen", "session", "sleep", "protect"]
        },
        {
            id: "action:control_center",
            key: "control_center",
            title: "Control Center",
            subtitle: "Open quick settings, toggles & sliders",
            icon: "\uf013",
            category: "System Action",
            keywords: ["control", "center", "controlcenter", "settings", "wifi", "bluetooth", "brightness", "volume", "tray"]
        },
        {
            id: "action:equalizer",
            key: "equalizer",
            title: "Audio Equalizer",
            subtitle: "Open 10-band DSP audio equalizer flyout",
            icon: "\uf001",
            category: "System Action",
            keywords: ["equalizer", "eq", "audio", "sound", "dsp", "bass", "treble", "music", "pipewire", "audioequalizer"]
        },
        {
            id: "action:recorder",
            key: "recorder",
            title: "Screen Recorder",
            subtitle: "Start or stop hardware screen recording",
            icon: "\uf03d",
            category: "System Action",
            keywords: ["record", "screen", "video", "capture", "recording", "screenrecorder", "gpu-screen-recorder"]
        },
        {
            id: "action:replay",
            key: "replay",
            title: "Save Instant Replay",
            subtitle: "Save rolling 30s screen replay buffer to disk",
            icon: "\uf1da",
            category: "System Action",
            keywords: ["replay", "instant", "buffer", "clip", "save"]
        },
        {
            id: "action:glance",
            key: "glance",
            title: "System Glance Dashboard",
            subtitle: "Open mini hardware & telemetry dashboard",
            icon: "\uf2db",
            category: "System Action",
            keywords: ["glance", "system", "dashboard", "hardware", "cpu", "ram", "temp", "stats", "updates"]
        },
        {
            id: "action:clipboard",
            key: "clipboard",
            title: "Clipboard History",
            subtitle: "Open clipboard manager & history search",
            icon: "\uf0ea",
            category: "System Action",
            keywords: ["clipboard", "copy", "paste", "history", "cliphist"]
        },
        {
            id: "action:shelf",
            key: "shelf",
            title: "File Shelf",
            subtitle: "Open temporary drag-and-drop file shelf",
            icon: "\uf07b",
            category: "System Action",
            keywords: ["shelf", "file", "drop", "drag", "storage", "fileshelf"]
        },
        {
            id: "action:calendar",
            key: "calendar",
            title: "Calendar & Notes",
            subtitle: "Browse calendar months and view daily notes",
            icon: "\uf073",
            category: "System Action",
            keywords: ["calendar", "date", "month", "notes", "todo", "day"]
        },
        {
            id: "action:weather",
            key: "weather",
            title: "Weather & Forecast",
            subtitle: "View current weather and forecast conditions",
            icon: "\uf185",
            category: "System Action",
            keywords: ["weather", "forecast", "temperature", "temp", "rain", "sun", "cloud"]
        },
        {
            id: "action:style",
            key: "style",
            title: "Toggle Island / Notch Style",
            subtitle: "Switch between floating Dynamic Island and top MacBook Notch",
            icon: "\uf108",
            category: "System Action",
            keywords: ["style", "notch", "island", "macbook", "switch", "toggle", "morph"]
        },
        {
            id: "action:power",
            key: "power",
            title: "Power Menu",
            subtitle: "Open session power controls (sleep, reboot, poweroff)",
            icon: "\uf011",
            category: "System Action",
            keywords: ["power", "powermenu", "power-menu", "menu", "shutdown", "reboot", "restart", "sleep", "suspend", "logout"]
        }
    ]

    // Persistent frecency store
    property var historyStore: Frecency.empty()

    FileView {
        id: historyFile
        path: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)
            + "/tide-island/spotlight-history.json"
        preload: true
        watchChanges: false
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                const text = historyFile.readText();
                if (text && text.trim() !== "")
                    root.historyStore = Frecency.parse(text);
            } catch (e) {
                root.historyStore = Frecency.empty();
            }
        }
    }

    function saveHistory() {
        try {
            historyFile.writeText(JSON.stringify(root.historyStore, null, 2));
        } catch (e) {
            // Ignore write errors
        }
    }

    function recordExecution(key) {
        if (!key) return;
        root.historyStore = Frecency.record(root.historyStore, key, root.query, Date.now());
        saveHistory();
    }

    // Debounced search trigger
    Timer {
        id: searchDebounce
        interval: 16
        repeat: false
        onTriggered: root.performSearch()
    }

    onQueryChanged: {
        searchDebounce.restart();
    }

    onActiveChanged: {
        if (active) {
            root.performSearch();
        } else {
            fileSearchProcess.running = false;
        }
    }

    Connections {
        target: typeof DesktopEntries !== "undefined" ? DesktopEntries : null

        function onApplicationsChanged() {
            if (root.active) {
                root.performSearch();
            }
        }
    }

    function performSearch() {
        const raw = String(root.query || "").trim();
        const now = Date.now();

        // 1. Calculations & Conversions
        if (raw !== "") {
            const ans = Calc.answer(raw);
            if (ans) {
                root.calcResult = {
                    type: "calc",
                    kind: ans.kind,
                    title: ans.text,
                    subtitle: ans.expression + (ans.dimension ? " • " + ans.dimension : ""),
                    copyText: ans.copy,
                    icon: "\uf1ec",
                    category: ans.kind === "convert" ? "Conversion" : "Calculation"
                };
            } else {
                root.calcResult = null;
            }
        } else {
            root.calcResult = null;
        }

        // 2. Direct Web URL or Search
        if (raw !== "") {
            const url = Web.addressUrl(raw);
            if (url) {
                root.urlResult = {
                    type: "url",
                    title: "Open " + url,
                    subtitle: "Open URL in default web browser",
                    url: url,
                    icon: "\uf0c1",
                    category: "Web Address"
                };
            } else {
                root.urlResult = null;
            }

            const searchUrl = Web.searchUrl("google", raw);
            root.webResult = {
                type: "web",
                title: "Search Google for \"" + raw + "\"",
                subtitle: "Search web in default browser",
                url: searchUrl,
                icon: "\uf0ac",
                category: "Web Search"
            };
        } else {
            root.urlResult = null;
            root.webResult = null;
        }

        // 3. System Actions
        const matchedActions = [];
        if (raw !== "") {
            for (let i = 0; i < root.systemActions.length; ++i) {
                const action = root.systemActions[i];
                let score = Match.score(raw, action.title);
                if (action.keywords) {
                    for (let k = 0; k < action.keywords.length; ++k) {
                        const kwScore = Match.score(raw, action.keywords[k]);
                        if (kwScore > score) score = kwScore;
                    }
                }
                const boost = Frecency.boost(root.historyStore, action.id, raw, now);
                if (score > 100 || boost > 0) {
                    matchedActions.push({
                        item: {
                            type: "action",
                            actionKey: action.key,
                            key: action.id,
                            title: action.title,
                            subtitle: action.subtitle,
                            icon: action.icon,
                            category: action.category
                        },
                        totalScore: score + boost + 300 // baseline weight for native actions
                    });
                }
            }
            matchedActions.sort((a, b) => b.totalScore - a.totalScore);
        }
        root.actionResults = matchedActions.map(x => x.item).slice(0, 4);

        // 4. Applications
        const availableApps = (typeof DesktopEntries !== "undefined" && DesktopEntries.applications && DesktopEntries.applications.values) ? DesktopEntries.applications.values : [];
        const matchedApps = [];

        if (raw === "") {
            // Empty query: show recent or popular apps
            const recentKeys = Frecency.recent(root.historyStore, "app:", 8);
            const keyMap = ({});
            for (let r = 0; r < recentKeys.length; ++r) {
                keyMap[recentKeys[r].replace(/^app:/, "")] = r;
            }

            for (let i = 0; i < availableApps.length; ++i) {
                const entry = availableApps[i];
                if (!entry || entry.noDisplay || String(entry.name).trim() === "") continue;
                const entryId = String(entry.id);
                if (keyMap[entryId] !== undefined) {
                    matchedApps.push({
                        item: {
                            type: "app",
                            appId: entryId,
                            entry: entry,
                            key: "app:" + entryId,
                            title: entry.name,
                            subtitle: entry.comment || entry.genericName || "Application",
                            icon: entry.icon ? String(entry.icon) : "application-x-executable",
                            category: "Application"
                        },
                        order: keyMap[entryId]
                    });
                }
            }
            matchedApps.sort((a, b) => a.order - b.order);

            // If history is small, fill up with top alphabetically
            if (matchedApps.length < 8) {
                const existingIds = ({});
                matchedApps.forEach(x => { existingIds[x.item.appId] = true; });
                for (let i = 0; i < availableApps.length && matchedApps.length < 8; ++i) {
                    const entry = availableApps[i];
                    if (!entry || entry.noDisplay || String(entry.name).trim() === "" || existingIds[String(entry.id)]) continue;
                    matchedApps.push({
                        item: {
                            type: "app",
                            appId: String(entry.id),
                            entry: entry,
                            key: "app:" + String(entry.id),
                            title: entry.name,
                            subtitle: entry.comment || entry.genericName || "Application",
                            icon: entry.icon ? String(entry.icon) : "application-x-executable",
                            category: "Application"
                        },
                        order: 999
                    });
                }
            }
        } else {
            // Search apps using ApplicationSearch + Frecency boost
            for (let i = 0; i < availableApps.length; ++i) {
                const entry = availableApps[i];
                if (!entry || entry.noDisplay || String(entry.name).trim() === "") continue;

                const baseScore = ApplicationSearch.applicationScore(entry, raw);
                const boost = Frecency.boost(root.historyStore, "app:" + String(entry.id), raw, now);

                if (baseScore > 0 || boost > 0) {
                    matchedApps.push({
                        item: {
                            type: "app",
                            appId: String(entry.id),
                            entry: entry,
                            key: "app:" + String(entry.id),
                            title: entry.name,
                            subtitle: entry.comment || entry.genericName || "Application",
                            icon: entry.icon ? String(entry.icon) : "application-x-executable",
                            category: "Application"
                        },
                        totalScore: baseScore + boost + 400
                    });
                }
            }
            matchedApps.sort((a, b) => b.totalScore - a.totalScore);
        }
        root.applicationResults = matchedApps.map(x => x.item).slice(0, 8);

        // 5. Clipboard History Search
        let isClipPrefix = false;
        let clipQuery = raw;
        if (/^(clip|cb|paste)\s+/i.test(raw)) {
            isClipPrefix = true;
            clipQuery = raw.replace(/^(clip|cb|paste)\s+/i, "").trim();
        } else if (raw.toLowerCase() === "clip" || raw.toLowerCase() === "cb") {
            isClipPrefix = true;
            clipQuery = "";
        }

        const matchedClips = [];
        if (root.cachedClips && root.cachedClips.length > 0 && (clipQuery !== "" || isClipPrefix)) {
            const queryToUse = clipQuery;
            for (let i = 0; i < root.cachedClips.length; ++i) {
                const clip = root.cachedClips[i];
                if (!clip || !clip.text) continue;

                let score = 0;
                if (queryToUse === "") {
                    score = Math.max(100, 900 - i * 10);
                } else {
                    const clipTextFolded = clip.text.toLowerCase();
                    const qFolded = queryToUse.toLowerCase();

                    if (clipTextFolded === qFolded) {
                        score = 1000;
                    } else if (clipTextFolded.startsWith(qFolded)) {
                        score = 900;
                    } else if (clipTextFolded.includes(qFolded)) {
                        score = 750;
                    } else {
                        score = Match.score(queryToUse, clip.text);
                    }
                }

                if (score > 150) {
                    const boost = Frecency.boost(root.historyStore, "clip:" + clip.id, queryToUse, now);
                    let titleStr = clip.text.replace(/[\r\n\t]+/g, " ").trim();
                    if (titleStr.length > 70) {
                        titleStr = titleStr.substring(0, 67) + "...";
                    }
                    matchedClips.push({
                        item: {
                            type: "clipboard",
                            clipId: clip.id,
                            key: "clip:" + clip.id,
                            title: titleStr,
                            subtitle: clip.isImage ? "Image snippet · Enter to copy" : "Clipboard snippet · Enter to copy",
                            copyText: clip.text,
                            isImage: clip.isImage,
                            imagePath: clip.imagePath,
                            icon: clip.isImage ? "\uf03e" : "\uf0ea",
                            category: "Clipboard"
                        },
                        totalScore: score + boost + (isClipPrefix ? 600 : 250)
                    });
                }
            }
            matchedClips.sort((a, b) => b.totalScore - a.totalScore);
        }
        root.clipboardResults = matchedClips.slice(0, 5).map(x => x.item);

        // 6. Trigger File Search (debounced)
        if (raw.length >= 3 && !root.calcResult) {
            fileSearchDebounce.restart();
        } else {
            fileSearchProcess.running = false;
            root.fileResults = [];
        }

        root.rebuildAllResults();
    }

    // Debounced file searching
    Timer {
        id: fileSearchDebounce
        interval: 120
        repeat: false
        onTriggered: {
            const raw = String(root.query || "").trim();
            if (raw.length >= 3 && root.homeDirectory !== "") {
                fileSearchProcess.command = [
                    "/usr/bin/fd",
                    "--absolute-path",
                    "--color=never",
                    "--ignore-case",
                    "--type=f",
                    "--type=d",
                    "--max-results=8",
                    "--exclude=node_modules",
                    "--exclude=.git",
                    "--exclude=__pycache__",
                    raw,
                    root.homeDirectory
                ];
                fileSearchProcess.running = true;
            }
        }
    }

    Process {
        id: fileSearchProcess
        stdout: SplitParser {
            onRead: function(line) {
                const path = String(line || "").trim();
                if (!path) return;
                const parts = path.split("/");
                const filename = parts[parts.length - 1];
                const isDir = !filename.includes(".");
                
                const existing = root.fileResults.slice();
                if (existing.length < 8 && !existing.some(x => x.path === path)) {
                    existing.push({
                        type: "file",
                        key: "file:" + path,
                        title: filename,
                        subtitle: path.replace(root.homeDirectory, "~"),
                        path: path,
                        icon: isDir ? "folder" : "text-x-generic",
                        category: isDir ? "Folder" : "File"
                    });
                    root.fileResults = existing;
                    root.rebuildAllResults();
                }
            }
        }
    }

    Process {
        id: cliphistProcess
        command: ["bash", root.helperScriptPath, "list", "100"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(l => l.length > 0);
                const parsed = [];
                for (let i = 0; i < lines.length; ++i) {
                    const line = lines[i];
                    const tabIdx = line.indexOf("\t");
                    if (tabIdx === -1) continue;
                    const id = line.substring(0, tabIdx).trim();
                    let rest = line.substring(tabIdx + 1);
                    let imgPath = "";
                    let isImg = false;
                    const nullIdx = rest.indexOf("\x00");
                    if (nullIdx !== -1) {
                        const iconPart = rest.substring(nullIdx + 1);
                        rest = rest.substring(0, nullIdx);
                        const splitPart = iconPart.split("\x1f");
                        if (splitPart.length > 1) {
                            imgPath = splitPart[1];
                        }
                        isImg = true;
                    } else if (rest.includes("[[ binary data")) {
                        isImg = true;
                    }
                    parsed.push({
                        id: id,
                        text: rest.trim(),
                        isImage: isImg,
                        imagePath: imgPath
                    });
                }
                root.cachedClips = parsed;
                if (root.query.trim() !== "") {
                    root.updateSearch(root.query);
                }
            }
        }
    }

    function rebuildAllResults() {
        const list = [];

        // 1. Calculation takes prime Top Hit priority
        if (root.calcResult) {
            list.push(root.calcResult);
        }

        // 2. Direct URL
        if (root.urlResult) {
            list.push(root.urlResult);
        }

        const isClipPrefix = /^(clip|cb|paste)\b/i.test(String(root.query || "").trim());
        if (isClipPrefix) {
            for (let i = 0; i < root.clipboardResults.length; ++i) {
                list.push(root.clipboardResults[i]);
            }
        }

        // 3. Actions & Applications
        for (let i = 0; i < root.actionResults.length; ++i) {
            list.push(root.actionResults[i]);
        }
        for (let i = 0; i < root.applicationResults.length; ++i) {
            list.push(root.applicationResults[i]);
        }

        // 4. Clipboard matches (when not explicitly prefixed)
        if (!isClipPrefix) {
            for (let i = 0; i < root.clipboardResults.length; ++i) {
                list.push(root.clipboardResults[i]);
            }
        }

        // 5. Files
        for (let i = 0; i < root.fileResults.length; ++i) {
            list.push(root.fileResults[i]);
        }

        // 6. Web Search at bottom
        if (root.webResult && !root.calcResult) {
            list.push(root.webResult);
        }

        root.allResults = list;
        if (root.selectedIndex >= list.length) {
            root.selectedIndex = Math.max(0, list.length - 1);
        }
    }

    function moveSelection(step) {
        if (root.totalResultCount === 0) {
            root.selectedIndex = 0;
            return;
        }
        root.selectedIndex = (root.selectedIndex + step + root.totalResultCount) % root.totalResultCount;
    }

    function executeSelected() {
        if (root.totalResultCount === 0 || root.selectedIndex < 0 || root.selectedIndex >= root.totalResultCount)
            return;
        executeItem(root.allResults[root.selectedIndex]);
    }

    function executeItem(item) {
        if (!item) return;

        // Record usage to frecency
        if (item.key) {
            recordExecution(item.key);
        }

        if (item.type === "calc") {
            // Copy calculation result to clipboard
            if (typeof SystemServices !== "undefined" && SystemServices && SystemServices.copyToClipboard) {
                SystemServices.copyToClipboard(item.copyText);
            }
        } else if (item.type === "action") {
            root.actionTriggered(item.actionKey);
        } else if (item.type === "app") {
            launchApplication(item.entry || item.appId);
        } else if (item.type === "clipboard") {
            if (item.clipId) {
                Quickshell.execDetached(["bash", root.helperScriptPath, "copy", String(item.clipId)]);
            } else if (item.copyText && typeof SystemServices !== "undefined" && SystemServices && SystemServices.copyToClipboard) {
                SystemServices.copyToClipboard(item.copyText);
            }
        } else if (item.type === "file") {
            Quickshell.execDetached(["xdg-open", item.path]);
        } else if (item.type === "url" || item.type === "web") {
            Quickshell.execDetached(["xdg-open", item.url]);
        }

        // Emit executeRequested at the very end so app/action has already launched
        root.executeRequested(item);
    }

    function launchApplication(entry) {
        if (!entry) return;
        DesktopAppLauncher.launch(entry, Quickshell, typeof SystemServices !== "undefined" ? SystemServices : null, DesktopEntries);
    }
}
