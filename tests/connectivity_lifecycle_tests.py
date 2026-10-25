#!/usr/bin/env python3
"""Exercise real Quickshell components on a private bus without showing a window.

Requires a running Wayland session and Quickshell. Run after building:
    python3 tests/connectivity_lifecycle_tests.py build-spotify-check
The fake network service is reused from wifi_controller_tests.
"""

import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    build = Path(sys.argv[1]).resolve()
    if not os.environ.get("WAYLAND_DISPLAY"):
        raise SystemExit("This integration test requires a Wayland session.")
    with tempfile.TemporaryDirectory(prefix="tide-connectivity-test-") as work:
        directory = Path(work)
        # No service directories: tests must not start desktop daemons.
        config = directory / "bus.conf"
        config.write_text("""<busconfig>
            <type>session</type><listen>unix:tmpdir=/tmp</listen><auth>EXTERNAL</auth>
            <policy context="default">
                <allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/>
            </policy>
        </busconfig>""")
        bus = subprocess.Popen(
            ["dbus-daemon", "--nofork", "--print-address=1", f"--config-file={config}"],
            stdout=subprocess.PIPE, text=True,
        )
        helper = None
        try:
            if not select.select([bus.stdout], [], [], 3)[0]:
                raise RuntimeError("Private D-Bus did not start")
            address = bus.stdout.readline().strip()
            env = os.environ.copy()
            env.update(
                DBUS_SESSION_BUS_ADDRESS=address, DBUS_SYSTEM_BUS_ADDRESS=address,
                TIDE_ISLAND_WIFI_TEST_ISOLATED="1", QT_QPA_PLATFORM="wayland",
                QML_IMPORT_PATH=str(build), XDG_CONFIG_HOME=str(directory / "config"),
                XDG_CACHE_HOME=str(directory / "cache"), XDG_STATE_HOME=str(directory / "state"),
                QT_QUICK_CONTROLS_STYLE="Basic",
            )
            settings = directory / "config" / "tide-island"
            settings.mkdir(parents=True)
            (settings / "userconfig.json").write_text("{}")
            fixture = directory / "fixture"
            fixture.mkdir()
            shutil.copy2(root / "DynamicIslandWindow.qml", fixture)
            shutil.copytree(root / "qml", fixture / "qml")
            shutil.copy2(root / "tests/connectivity_lifecycle.qml", fixture / "shell.qml")
            provider = fixture / "qml/controlcenter/ControlCenterLayer.qml"
            source = provider.read_text()
            hook = "    function clearWifiMessages() {"
            assert source.count(hook) == 1
            provider.write_text(source.replace(hook, """    property bool injectCleanupFailure: false
    function clearWifiMessages() {
        if (injectCleanupFailure) throw new Error("injected connectivity cleanup failure");"""))
            helper = subprocess.Popen(
                [str(build / "wifi_controller_tests"), "--fake-networkmanager"],
                env=env, stdout=subprocess.PIPE, text=True,
            )
            if not select.select([helper.stdout], [], [], 3)[0] or helper.stdout.readline().strip() != "ready":
                raise RuntimeError("Fake NetworkManager did not start")
            try:
                result = subprocess.run(
                    ["quickshell", "--no-color", "-p", str(fixture)], env=env,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20,
                )
            except subprocess.TimeoutExpired as error:
                log = (error.stdout or b"").decode(errors="replace")
                (build / "connectivity-lifecycle.log").write_text(log)
                raise RuntimeError(log) from error
            log = result.stdout
            (build / "connectivity-lifecycle.log").write_text(log)
            unexpected = [line for line in log.splitlines()
                          if "injected connectivity cleanup failure" not in line and any(
                              pattern in line for pattern in (
                                  " ERROR:", "TypeError:", "ReferenceError:",
                                  "Unable to assign [undefined]", "CONNECTIVITY_TEST_FAIL"))]
            if result.returncode or "CONNECTIVITY_TEST_PASS" not in log or unexpected:
                raise RuntimeError(log)
            print(next(line for line in log.splitlines() if "CONNECTIVITY_TEST_PASS" in line))
        finally:
            for process in (helper, bus):
                if process is not None:
                    process.terminate()
                    process.wait(timeout=3)


if __name__ == "__main__":
    main()
