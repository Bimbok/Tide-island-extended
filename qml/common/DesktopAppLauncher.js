.pragma library

// DesktopAppLauncher.js - Shared application execution engine for Tide Island

function sanitizeCommand(command) {
    if (!command || !command.length)
        return [];
    const sanitized = [];
    for (let i = 0; i < command.length; ++i) {
        const arg = String(command[i]);
        // Filter out freedesktop field codes (%f, %F, %u, %U, %d, %D, %n, %N, %i, %c, %k, %v, %m)
        if (/^%[a-zA-Z]$/.test(arg))
            continue;
        sanitized.push(arg);
    }
    return sanitized;
}

function findEntryById(id, desktopEntries) {
    if (!id || !desktopEntries || !desktopEntries.applications)
        return null;
    const apps = desktopEntries.applications.values || [];
    const targetId = String(id);
    for (let i = 0; i < apps.length; ++i) {
        if (apps[i] && String(apps[i].id) === targetId)
            return apps[i];
    }
    return null;
}

function launch(entryOrId, quickshell, systemServices, desktopEntries) {
    if (!entryOrId)
        return false;

    let entry = entryOrId;
    if (typeof entryOrId === "string") {
        entry = findEntryById(entryOrId, desktopEntries);
    } else if (entryOrId && !entryOrId.command && entryOrId.appId) {
        entry = findEntryById(entryOrId.appId, desktopEntries) || entryOrId;
    }

    if (!entry)
        return false;

    let desktopCommand = [];
    if (entry.command && entry.command.length > 0) {
        for (let i = 0; i < entry.command.length; ++i)
            desktopCommand.push(String(entry.command[i]));
    }
    desktopCommand = sanitizeCommand(desktopCommand);

    // Prefer C++ backend SystemServices when available
    if (typeof systemServices !== "undefined" && systemServices && typeof systemServices.launchApplication === "function") {
        if (desktopCommand.length > 0) {
            const launched = systemServices.launchApplication(desktopCommand, !!entry.runInTerminal, String(entry.workingDirectory || ""));
            if (launched)
                return true;
        }
    }

    if (desktopCommand.length === 0) {
        if (typeof entry.execute === "function") {
            try {
                entry.execute();
                return true;
            } catch (e) {
                return false;
            }
        }
        return false;
    }

    if (entry.runInTerminal) {
        if (typeof systemServices !== "undefined" && systemServices && typeof systemServices.wrapTerminalCommand === "function") {
            desktopCommand = systemServices.wrapTerminalCommand(desktopCommand);
        } else {
            const terminal = (quickshell && typeof quickshell.env === "function" && quickshell.env("TERMINAL")) || "kitty";
            desktopCommand = [terminal, "-e"].concat(desktopCommand);
        }
    }

    const scopedCommand = [
        "systemd-run",
        "--user",
        "--scope",
        "--quiet",
        "--collect",
        "--slice=app.slice",
        "--expand-environment=no"
    ];

    const workingDirectory = String(entry.workingDirectory || "").trim();
    if (workingDirectory !== "")
        scopedCommand.push("--working-directory=" + workingDirectory);
    scopedCommand.push("--");
    for (let i = 0; i < desktopCommand.length; ++i)
        scopedCommand.push(desktopCommand[i]);

    if (quickshell && typeof quickshell.execDetached === "function") {
        try {
            quickshell.execDetached(scopedCommand);
            return true;
        } catch (e) {
            if (typeof entry.execute === "function") {
                entry.execute();
                return true;
            }
        }
    } else if (typeof entry.execute === "function") {
        entry.execute();
        return true;
    }

    return false;
}
