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
    "get_capabilities", "get_config", "get_installed_games", "save_power_config",
    "save_tweaks", "get_fans_state", "save_fan_curves", "get_controller_state",
    "save_calibration", "get_rgb", "set_rgb", "set_controller_type",
    "set_ssh_enabled", "set_mtp_enabled", "set_abl_auto_enabled",
    "inputplumber_intercept", "reapply_perf", "restart_game_mode",
    "set_overlay_activation",
}
assert required <= actions.keys(), sorted(required - actions.keys())
assert service.overlay_actions()["get_capabilities"]({})["api"] == 1

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
grep -Fq 'Environment=DISPLAY=:0' \
    "$ROOT/system_files/usr/lib/systemd/user/armada-control-overlay.service"
grep -Fq 'ExecStopPost=-/usr/libexec/armada/inputplumber-intercept reset' \
    "$ROOT/system_files/usr/lib/systemd/user/armada-control-overlay.service"
grep -Fq 'qt6-qtbase-gui' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'armada-control-overlay' "$ROOT/build_files/40-vendor-system-files.sh"
grep -Fq 'SetInterceptActivation' "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept"
grep -Fq -- '--standalone' "$ROOT/system_files/usr/share/applications/armada-control-overlay.desktop"
grep -Fq 'STEAM_INPUT_FOCUS' "$ROOT/overlay/main.cpp"

printf 'Armada overlay API tests passed\n'
