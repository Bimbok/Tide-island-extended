#!/usr/bin/env bash
set -Eeuo pipefail

# Quick synchronization script to copy modified QML files directly into
# the installed Tide Island directory without running a full reinstallation.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="/usr/share/tide-island"

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: Target directory $TARGET_DIR does not exist." >&2
    exit 1
fi

echo "Copying modified files to $TARGET_DIR..."
sudo cp -rv "$ROOT_DIR/qml/spotlight" "$TARGET_DIR/qml/"
sudo cp -rv "$ROOT_DIR/qml/common" "$TARGET_DIR/qml/"
sudo cp -v "$ROOT_DIR/qml/island/ApplicationLauncherLayer.qml" "$TARGET_DIR/qml/island/"
sudo cp -v "$ROOT_DIR/DynamicIslandWindow.qml" "$TARGET_DIR/"
sudo cp -v "$ROOT_DIR/shell.qml" "$TARGET_DIR/"

echo "Restarting tide-island user service..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user restart tide-island.service || true
fi

echo "Synchronization complete."
