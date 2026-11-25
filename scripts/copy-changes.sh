#!/usr/bin/env bash
set -Eeuo pipefail

# Quick synchronization script to copy modified QML files and backend
# libraries directly into the installed directories without a full reinstall.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="/usr/share/tide-island"

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: Target directory $TARGET_DIR does not exist." >&2
    exit 1
fi

echo "Copying modified QML and JS files to $TARGET_DIR..."
sudo cp -rv "$ROOT_DIR/qml/spotlight" "$TARGET_DIR/qml/"
sudo cp -rv "$ROOT_DIR/qml/common" "$TARGET_DIR/qml/"
sudo cp -v "$ROOT_DIR/qml/island/ApplicationLauncherLayer.qml" "$TARGET_DIR/qml/island/"
sudo cp -v "$ROOT_DIR/DynamicIslandWindow.qml" "$TARGET_DIR/"
sudo cp -v "$ROOT_DIR/shell.qml" "$TARGET_DIR/"

# Copy compiled backend binaries if present
BUILD_DIR=""
if [[ -f "$ROOT_DIR/build-release-installer/libIslandBackend.so" ]]; then
    BUILD_DIR="$ROOT_DIR/build-release-installer"
elif [[ -f "$ROOT_DIR/build/libIslandBackend.so" ]]; then
    BUILD_DIR="$ROOT_DIR/build"
fi

if [[ -n "$BUILD_DIR" ]]; then
    echo "Copying backend libraries from $BUILD_DIR..."
    sudo cp -v "$BUILD_DIR/libIslandBackend.so" /usr/lib/
    if [[ -d /usr/lib/qt6/qml/IslandBackend && -f "$BUILD_DIR/IslandBackend/libIslandBackendplugin.so" ]]; then
        sudo cp -v "$BUILD_DIR/IslandBackend/libIslandBackendplugin.so" /usr/lib/qt6/qml/IslandBackend/
    fi
    if [[ -f "$BUILD_DIR/Tide-island-app/tide-island-config-app" ]]; then
        sudo cp -v "$BUILD_DIR/Tide-island-app/tide-island-config-app" /usr/bin/
    fi
fi

echo "Restarting tide-island user service..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user restart tide-island.service || true
fi

echo "Synchronization complete."
