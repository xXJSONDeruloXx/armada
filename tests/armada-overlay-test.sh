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

test -x "$ROOT/system_files/usr/libexec/armada/armada-overlay-call"
test -x "$ROOT/system_files/usr/libexec/armada/armada-steam-call"
grep -Fq 'armada-steam-call' "$ROOT/docs/ogui-spike-v046/backend.gd"
grep -Fq 'armada-overlay-call' "$ROOT/system_files/usr/libexec/armada/armada-overlay-call"
grep -Fq 'inputplumber-intercept reset' "$ROOT/docs/ogui-spike-v046/armada-opengamepadui"
grep -Fq 'opengamepadui.pid' "$ROOT/docs/ogui-spike-v046/armada-opengamepadui"
grep -Fq 'SendButtonChord' "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept"
if grep -Fq 'exec /usr/share/armada/ogui/opengamepad-ui.aarch64' "$ROOT/docs/ogui-spike-v046/armada-opengamepadui"; then
    echo "OGUI launcher bypasses cleanup trap" >&2
    exit 1
fi
test -f "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
test -x "$ROOT/docs/ogui-spike-v046/build-plugin.sh"
test -x "$ROOT/docs/ogui-spike-v046/build-ogui.sh"
grep -Fq 'b149644f46b71e175a2ad223e84c18361596691e' "$ROOT/docs/ogui-spike-v046/build-ogui.sh"
grep -Fq 'make -B' "$ROOT/docs/ogui-spike-v046/build-ogui.sh"
grep -Fq 'ARMADA_OGUI_PCK_ONLY' "$ROOT/docs/ogui-spike-v046/build-ogui.sh"
grep -Fq -- '--export-pack' "$ROOT/docs/ogui-spike-v046/build-ogui.sh"
if grep -Fq 'overlay.gd' "$ROOT/docs/ogui-spike-v046/build-plugin.sh"; then
    echo "plugin archive must not ship the retired overlay provider" >&2
    exit 1
fi
grep -Fq 'source checkout contains an embedded Armada plugin' "$ROOT/docs/ogui-spike-v046/build-ogui.sh"
if grep -Fq 'cp "$root"/{backend.gd' "$ROOT/docs/ogui-spike-v046/build-ogui.sh"; then
    echo "OGUI build still embeds the Armada plugin in the PCK" >&2
    exit 1
fi
grep -Fq 'migrate_compat' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'get_compat_mapped_appids' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
test -f "$ROOT/.github/workflows/build-ogui.yml"
grep -Fq 'build-ogui.sh' "$ROOT/.github/workflows/build-ogui.yml"
if grep -Fq 'general["default_profile"] = name' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"; then
    echo "OGUI profile selection changes the persisted default" >&2
    exit 1
fi
grep -Fq 'profile["gpu_max"] = "%.2f" % normalized' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'profile["gpu_min"] = "%.2f" % normalized' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'Refresh device state' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'func _rebuild_sections()' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq '"auto_apply": _global_tweak("autoApplyCompat")' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
test ! -e "$ROOT/docs/ogui-spike-v046/overlay.gd"
test ! -e "$ROOT/docs/ogui-spike-v046/overlay.tscn"
grep -Fq 'touch -t 198001010000' "$ROOT/docs/ogui-spike-v046/build-plugin.sh"
grep -Fq 'zip -X' "$ROOT/docs/ogui-spike-v046/build-plugin.sh"
# Summon chords are owned by OGUI core + stock InputPlumber triggers.
# The plugin must never program intercept activation (single-writer slot).
if grep -Fq 'set_intercept_activation' "$ROOT/docs/ogui-spike-v046/plugin.gd"; then
    echo "plugin must not override the overlay summon chord; see overlay-summon.md" >&2
    exit 1
fi
if grep -Fq 'Centered activation\|Slide-out activation' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"; then
    echo "chord dropdowns must stay out while OGUI owns summoning" >&2
    exit 1
fi
grep -Fq 'Overlay layout' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'Edge swipe to open' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'DirAccess.rename_absolute' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'config = response["result"]' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
if grep -Fq '_register_overlay\|OVERLAY_SCENE\|overlay_container' "$ROOT/docs/ogui-spike-v046/plugin.gd"; then
    echo "plugin must mount cards into OGUI native quick bar menu, not a private container" >&2
    exit 1
fi
grep -Fq 'call_deferred("_register_quick_bar")' "$ROOT/docs/ogui-spike-v046/plugin.gd"
# OGUI core owns Gamescope focus/overlay atoms and the intercept mode;
# the plugin must never write them (see overlay-summon.md).
for banned in set_intercept_mode set_input_focus set_overlay manage_all_devices _claim_overlay_window _release_overlay_window overlay_window_id; do
    if grep -Fq "$banned" "$ROOT/docs/ogui-spike-v046/plugin.gd"; then
        echo "plugin must not touch Gamescope/input ownership: $banned" >&2
        exit 1
    fi
done
grep -Fq '_watch_menu_state' "$ROOT/docs/ogui-spike-v046/plugin.gd"
grep -Fq 'Native Quick Bar opened' "$ROOT/docs/ogui-spike-v046/plugin.gd"
grep -Fq 'Mounted %d Armada cards into native Quick Bar' "$ROOT/docs/ogui-spike-v046/plugin.gd"
test -f "$ROOT/docs/ogui-spike-v046/text-input-default.patch"
grep -Fq '@export var description: String = "":' "$ROOT/docs/ogui-spike-v046/text-input-default.patch"
grep -Fq 'line_edit.text_submitted.connect(on_text_submitted)' "$ROOT/docs/ogui-spike-v046/text-input-default.patch"
grep -Fq 'qb_card.tscn' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'text_input.tscn' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'save_fan_curves' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'selected_game_appid' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'factoryFanCurves' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'Fix minimum PWM' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'Point PWM' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'var minimum_pwm_slider' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'Reset curve to factory' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'Revert changes' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq '_other_curve_has_fan_stop' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'RGB color' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq '_rgb_hue' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'Apply to new games' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'calibration_sliders' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq '_update_calibration_sliders' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq '_build_environment' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'Variable staged' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'Invalid CPU list' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'Environment variable' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'Reset profile' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'get_app_compat_tools' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'set_launch_options' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'Enter AppID manually' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
for section in Power Fans Games Compatibility System Actions; do
    grep -Fq "_section(content, \"$section\"" "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
done
grep -Fq 'ScrollContainer/Viewport' "$ROOT/docs/ogui-spike-v046/plugin.gd"
grep -Fq 'is_node_ready' "$ROOT/docs/ogui-spike-v046/plugin.gd"
grep -Fq 'armada_control_quick_bar' "$ROOT/docs/ogui-spike-v046/plugin.gd"
grep -Fq '_mount_quick_bar_cards' "$ROOT/docs/ogui-spike-v046/plugin.gd"
grep -Fq 'ArmadaContent' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'ArmadaStatus' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'mounted_status' "$ROOT/docs/ogui-spike-v046/plugin.gd"
grep -Fq 'dropdown.clear()' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'if not values.is_empty():' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq '_hide_component_description' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'func _exit_tree' "$ROOT/docs/ogui-spike-v046/plugin.gd"
grep -Fq 'Guide+B' "$ROOT/docs/ogui-spike-v046/README.md"
test -f "$ROOT/system_files/usr/lib/systemd/user/armada-opengamepadui.service"
grep -Fq 'ExecStart=/usr/bin/armada-opengamepadui --overlay-mode' \
    "$ROOT/system_files/usr/lib/systemd/user/armada-opengamepadui.service"
grep -Fq 'enable armada-opengamepadui.service' "$ROOT/Containerfile"
grep -Fq 'qt6-qtbase-gui' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'qt6-qtdeclarative' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'qt6-qtsvg' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'xcb-util-cursor' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'AS ogui-build' "$ROOT/Containerfile"
grep -Fq 'AS armada-ogui' "$ROOT/Containerfile"
grep -Fq 'ARMADA_OGUI_IN_BUILDER=1' "$ROOT/Containerfile"
test -f "$ROOT/docs/ogui-spike-v046/overlay-existing-steam.patch"
grep -Fq 'overlay-existing-steam.patch' "$ROOT/docs/ogui-spike-v046/build-ogui.sh"
grep -Fq 'Adopted existing Steam window' "$ROOT/docs/ogui-spike-v046/overlay-existing-steam.patch"
grep -Fq 'armada-opengamepadui' "$ROOT/Containerfile"
test -x "$ROOT/docs/ogui-spike-v046/armada-opengamepadui"
grep -Fq 'opengamepadui/plugins' "$ROOT/docs/ogui-spike-v046/armada-opengamepadui"
grep -Fq 'armada-control.zip' "$ROOT/docs/ogui-spike-v046/armada-opengamepadui"
grep -Fq 'discover_display' "$ROOT/docs/ogui-spike-v046/armada-opengamepadui"
grep -Fq 'GAMESCOPE_FOCUSED_WINDOW' "$ROOT/docs/ogui-spike-v046/armada-opengamepadui"
# launcher prefers the X socket with Gamescope focus state, else the first socket
discover_tmp="$(mktemp -d)"
mkdir -p "$discover_tmp/sock" "$discover_tmp/bin"
touch "$discover_tmp/sock/X0" "$discover_tmp/sock/X1"
cat > "$discover_tmp/bin/xprop" <<'XPROP_EOF'
#!/bin/sh
[ "$DISPLAY" = ":1" ]
XPROP_EOF
chmod +x "$discover_tmp/bin/xprop"
discover_fn="$(sed -n '/^discover_display() {/,/^}/p' "$ROOT/docs/ogui-spike-v046/armada-opengamepadui")"
[ "$(X11_SOCKET_DIR="$discover_tmp/sock" PATH="$discover_tmp/bin:$PATH" sh -c "$discover_fn; discover_display")" = ":1" ]
cat > "$discover_tmp/bin/xprop" <<'XPROP_EOF'
#!/bin/sh
exit 1
XPROP_EOF
[ "$(X11_SOCKET_DIR="$discover_tmp/sock" PATH="$discover_tmp/bin:$PATH" sh -c "$discover_fn; discover_display")" = ":0" ]
rm -rf "$discover_tmp"
grep -Fq 'SetInterceptActivation' "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept"
grep -Fq 'pass)' "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept"
grep -Fq 'GamepadOrder' "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept"
grep -Fq 'DbusDevices' "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept"
if grep -Fq "path='/org/shadowblip/InputPlumber/CompositeDevice0'" "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept"; then
    echo "inputplumber helper still hard-codes CompositeDevice0" >&2
    exit 1
fi
grep -Fq 'start_select' "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept"
grep -Fq 'select_l1' "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept"
grep -Fq 'INTERCEPT_MODES = {"pass", "overlay", "reset"}' "$ROOT/system_files/usr/libexec/armada/armada-control"
grep -Fq 'SetAppLaunchOptions' "$ROOT/system_files/usr/libexec/armada/steam-bridge"
grep -Fq 'sweep_compat' "$ROOT/system_files/usr/libexec/armada/steam-bridge"
grep -Fq 'migrate_compat' "$ROOT/system_files/usr/libexec/armada/steam-bridge"

printf 'Armada overlay API tests passed\n'
