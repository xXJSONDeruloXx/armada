#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

python3 -B - "$ROOT" <<'PYEOF'
import importlib.machinery
import importlib.util
import json
import os
import socket
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
sys.path.insert(0, str(root / "system_files/usr/lib/armada"))
service_path = root / "system_files/usr/libexec/armada/armada-control"
spec = importlib.util.spec_from_loader(
    "armada_control_overlay_service",
    importlib.machinery.SourceFileLoader("armada_control_overlay_service", str(service_path)),
)
service = importlib.util.module_from_spec(spec)
spec.loader.exec_module(service)

assert service.OVERLAY_SOCKET == Path("/run/armada/overlay.sock")
assert service.handle_overlay({"action": "get_capabilities"}, None)["api"] == 1
actions = service.overlay_actions()
required = {
    "get_capabilities", "get_config", "get_runtime_game", "get_installed_games", "save_power_config",
    "save_tweaks", "get_fans_state", "save_fan_curves", "get_controller_state",
    "save_calibration", "get_rgb", "set_rgb", "set_controller_type",
    "set_ssh_enabled", "set_mtp_enabled", "set_abl_auto_enabled",
    "inputplumber_intercept", "reapply_perf", "restart_game_mode",
    "set_overlay_activation",
}
assert required <= actions.keys(), sorted(required - actions.keys())
assert service.overlay_actions()["get_capabilities"]({})["api"] == 1
assert service.overlay_actions()["get_runtime_game"]({}) is None

try:
    service.handle_overlay({"action": "root_only_maintenance"})
except ValueError as exc:
    assert str(exc) == "unsupported overlay action"
else:
    raise AssertionError("overlay API accepted an unallowlisted action")

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "overlay.sock"
    sock = service.bind_socket(path, 0o600)
    try:
        assert path.exists()
        assert (path.stat().st_mode & 0o777) == 0o600
        sock.listen(1)
    finally:
        sock.close()
        path.unlink()
PYEOF

grep -Fq 'ExecStart=/usr/bin/armada-control-overlay --persistent' \
    "$ROOT/system_files/usr/lib/systemd/user/armada-control-overlay.service"
if grep -Fq 'Environment=DISPLAY=:0' \
    "$ROOT/system_files/usr/lib/systemd/user/armada-control-overlay.service"; then
    echo "unexpected hard-coded Gamescope display" >&2
    exit 1
fi
grep -Fq 'ExecStopPost=-/usr/libexec/armada/inputplumber-intercept reset' \
    "$ROOT/system_files/usr/lib/systemd/user/armada-control-overlay.service"
grep -Fq -- '--cleanup' "$ROOT/system_files/usr/lib/systemd/user/armada-control-overlay.service"
grep -Fq 'ExecStartPre=-/usr/bin/armada-control-overlay --cleanup' \
    "$ROOT/system_files/usr/lib/systemd/user/armada-control-overlay.service"
grep -Fq 'qt6-qtbase-gui' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'qt6-qtdeclarative' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'qt6-qtsvg' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'armada-control-overlay' "$ROOT/build_files/40-vendor-system-files.sh"
grep -Fq '/usr/share/armada/overlay' "$ROOT/build_files/40-vendor-system-files.sh"
grep -Fq 'SetInterceptActivation' "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept"
grep -Fq -- '--standalone' "$ROOT/system_files/usr/share/applications/armada-control-overlay.desktop"
grep -Fq 'STEAM_OVERLAY' "$ROOT/overlay/main.cpp"
grep -Fq 'STEAM_INPUT_FOCUS' "$ROOT/overlay/main.cpp"
grep -Fq 'StackView' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'SettingsPage' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'CalibrationPage' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'GamePage' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'CompatibilityPage' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'transparent' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'save_power_config' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'save_calibration' "$ROOT/overlay/qml/CalibrationPage.qml"
grep -Fq 'set_sleep_mode' "$ROOT/overlay/qml/SettingsPage.qml"
grep -Fq 'save_tweaks' "$ROOT/overlay/qml/GamePage.qml"
grep -Fq 'FEX preset' "$ROOT/overlay/qml/GamePage.qml"
grep -Fq 'reapply_perf' "$ROOT/overlay/qml/GamePage.qml"
grep -Fq 'environmentMode' "$ROOT/overlay/qml/GamePage.qml"
grep -Fq 'get_global_compat_tools' "$ROOT/overlay/qml/CompatibilityPage.qml"
grep -Fq 'set_launch_options' "$ROOT/overlay/qml/CompatibilityPage.qml"
grep -Fq 'steamCall' "$ROOT/overlay/qml/CompatibilityPage.qml"
grep -Fq 'SetAppLaunchOptions' "$ROOT/system_files/usr/libexec/armada/steam-bridge"
grep -Fq 'python3-websocket-client' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'QQmlApplicationEngine' "$ROOT/overlay/main.cpp"
grep -Fq 'inputAction' "$ROOT/overlay/main.cpp"
grep -Fq 'ui_up' "$ROOT/overlay/main.cpp"
grep -Fq 'ui_accept' "$ROOT/overlay/main.cpp"
grep -Fq 'navigationActive' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'pageIcons' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'font.pixelSize: root.theme.bodySize' "$ROOT/overlay/qml/FocusRow.qml"
for control in SelectRow SliderRow ToggleRow; do
    test -f "$ROOT/overlay/qml/$control.qml"
    grep -Fq "import QtQuick.Controls" "$ROOT/overlay/qml/$control.qml"
done
grep -Fq 'navigationActive' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'SliderRow' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'ToggleRow' "$ROOT/overlay/qml/SettingsPage.qml"
grep -Fq 'SelectRow' "$ROOT/overlay/qml/CompatibilityPage.qml"
for icon in status power fans games settings calibration; do
    test -f "$ROOT/overlay/qml/icons/$icon.svg"
done

printf 'Armada overlay API tests passed\n'
