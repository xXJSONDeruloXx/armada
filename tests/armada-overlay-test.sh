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
assert service.OVERLAY_CHORDS == {"start_select", "guide", "quick_access", "select_l1", "select_r1"}
try:
    service.handle_overlay({"action": "set_overlay_activation", "chord": "arbitrary"})
except ValueError as exc:
    assert str(exc) == "invalid overlay activation chord"
else:
    raise AssertionError("overlay API accepted an arbitrary activation chord")

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
grep -Fq 'armada-overlay-gestures.service' "$ROOT/build_files/40-vendor-system-files.sh"
test -x "$ROOT/system_files/usr/libexec/armada/overlay-gestures"
test -x "$ROOT/system_files/usr/libexec/armada/armada-overlay-call"
test -x "$ROOT/system_files/usr/libexec/armada/armada-steam-call"
grep -Fq 'armada-steam-call' "$ROOT/docs/ogui-spike-v046/backend.gd"
grep -Fq 'armada-overlay-call' "$ROOT/system_files/usr/libexec/armada/armada-overlay-call"
test -f "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
test -x "$ROOT/docs/ogui-spike-v046/build-plugin.sh"
test -x "$ROOT/docs/ogui-spike-v046/build-ogui.sh"
grep -Fq 'b149644f46b71e175a2ad223e84c18361596691e' "$ROOT/docs/ogui-spike-v046/build-ogui.sh"
grep -Fq 'make -B' "$ROOT/docs/ogui-spike-v046/build-ogui.sh"
grep -Fq 'overlay.gd' "$ROOT/docs/ogui-spike-v046/build-ogui.sh"
test -f "$ROOT/docs/ogui-spike-v046/plugin-resource-pack.patch"
grep -Fq 'plugin-resource-pack.patch' "$ROOT/docs/ogui-spike-v046/build-ogui.sh"
grep -Fq 'migrate_compat' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'get_compat_mapped_appids' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'size_changed.connect(_update_overlay_geometry)' "$ROOT/docs/ogui-spike-v046/plugin.gd"
test -f "$ROOT/docs/ogui-spike-v046/text-input-default.patch"
grep -Fq '@export var description: String = "":' "$ROOT/docs/ogui-spike-v046/text-input-default.patch"
grep -Fq 'line_edit.text_submitted.connect(on_text_submitted)' "$ROOT/docs/ogui-spike-v046/text-input-default.patch"
grep -Fq 'qb_card.tscn' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
grep -Fq 'text_input.tscn' "$ROOT/docs/ogui-spike-v046/quick_bar.gd"
test -f "$ROOT/docs/ogui-spike-v046/overlay.gd"
test -f "$ROOT/docs/ogui-spike-v046/overlay.tscn"
grep -Fq 'OVERLAY_SCENE' "$ROOT/docs/ogui-spike-v046/plugin.gd"
grep -Fq '_register_overlay' "$ROOT/docs/ogui-spike-v046/plugin.gd"
grep -Fq 'ScrollContainer' "$ROOT/docs/ogui-spike-v046/overlay.gd"
grep -Fq 'ogui_back' "$ROOT/docs/ogui-spike-v046/overlay.gd"
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
grep -Fq 'PartOf=armada-control-overlay.service' "$ROOT/system_files/usr/lib/systemd/user/armada-overlay-gestures.service"
grep -Fq -- '--cleanup' "$ROOT/system_files/usr/lib/systemd/user/armada-control-overlay.service"
grep -Fq 'ExecStartPre=-/usr/bin/armada-control-overlay --cleanup' \
    "$ROOT/system_files/usr/lib/systemd/user/armada-control-overlay.service"
grep -Fq 'After=gamescope-session-plus@steam.service' \
    "$ROOT/system_files/usr/lib/systemd/user/armada-control-overlay.service"
grep -Fq 'qt6-qtbase-gui' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'qt6-qtdeclarative' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'qt6-qtsvg' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'xcb-util-cursor' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'armada-control-overlay' "$ROOT/build_files/40-vendor-system-files.sh"
grep -Fq '/usr/share/armada/overlay' "$ROOT/build_files/40-vendor-system-files.sh"
grep -Fq 'AS ogui-build' "$ROOT/Containerfile"
grep -Fq 'AS armada-ogui' "$ROOT/Containerfile"
grep -Fq 'ARMADA_OGUI_IN_BUILDER=1' "$ROOT/Containerfile"
grep -Fq 'armada-opengamepadui' "$ROOT/Containerfile"
test -x "$ROOT/docs/ogui-spike-v046/armada-opengamepadui"
grep -Fq 'opengamepadui/plugins' "$ROOT/docs/ogui-spike-v046/armada-opengamepadui"
grep -Fq 'armada-control.zip' "$ROOT/docs/ogui-spike-v046/armada-opengamepadui"
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
grep -Fq 'OVERLAY_CHORDS' "$ROOT/system_files/usr/libexec/armada/armada-control"
grep -Fq 'INTERCEPT_MODES = {"pass", "overlay", "reset"}' "$ROOT/system_files/usr/libexec/armada/armada-control"
grep -Fq -- '--standalone' "$ROOT/system_files/usr/share/applications/armada-control-overlay.desktop"
grep -Fq 'STEAM_OVERLAY' "$ROOT/overlay/main.cpp"
grep -Fq 'STEAM_INPUT_FOCUS' "$ROOT/overlay/main.cpp"
grep -Fq 'StackView' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'anchors.left: navigation.right' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'root.navigationActive = false' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'SettingsPage' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'CalibrationPage' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'GamePage' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'CompatibilityPage' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'transparent' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'property color scrim' "$ROOT/overlay/qml/Theme.qml"
if rg -n 'color: "#[0-9A-Fa-f]' "$ROOT/overlay/qml" -g '*.qml' -g '!Theme.qml'; then
    echo "unexpected literal QML color outside Theme.qml" >&2
    exit 1
fi
grep -Fq 'save_power_config' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'save_calibration' "$ROOT/overlay/qml/CalibrationPage.qml"
grep -Fq 'set_sleep_mode' "$ROOT/overlay/qml/SettingsPage.qml"
grep -Fq 'save_tweaks' "$ROOT/overlay/qml/GamePage.qml"
grep -Fq 'FEX preset' "$ROOT/overlay/qml/GamePage.qml"
grep -Fq 'reapply_perf' "$ROOT/overlay/qml/GamePage.qml"
grep -Fq 'environmentMode' "$ROOT/overlay/qml/GamePage.qml"
grep -Fq 'get_global_compat_tools' "$ROOT/overlay/qml/CompatibilityPage.qml"
grep -Fq 'set_launch_options' "$ROOT/overlay/qml/CompatibilityPage.qml"
grep -Fq 'reset_game' "$ROOT/overlay/qml/CompatibilityPage.qml"
grep -Fq 'get_current_temp' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'Canvas' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'Reset curve to factory' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'Fix minimum PWM' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'Fan stop temperature' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'setGraphPoint' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'preventStealing' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'Create fan curve' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'curveSlug' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'steamCall' "$ROOT/overlay/qml/CompatibilityPage.qml"
grep -Fq 'SetAppLaunchOptions' "$ROOT/system_files/usr/libexec/armada/steam-bridge"
grep -Fq 'sweep_compat' "$ROOT/system_files/usr/libexec/armada/steam-bridge"
grep -Fq 'migrate_compat' "$ROOT/system_files/usr/libexec/armada/steam-bridge"
grep -Fq 'get_compat_mapped_appids' "$ROOT/overlay/qml/CompatibilityPage.qml"
grep -Fq 'Enter AppID manually' "$ROOT/overlay/qml/CompatibilityPage.qml"
grep -Fq 'targetOptions' "$ROOT/overlay/qml/CompatibilityPage.qml"
grep -Fq 'compatibilitySweep' "$ROOT/overlay/main.cpp"
grep -Fq 'compatibilityProcess_' "$ROOT/overlay/main.cpp"
grep -Fq 'python3-websocket-client' "$ROOT/build_files/10-base-packages.sh"
grep -Fq 'FROM ${BASE_IMAGE} AS overlay-build' "$ROOT/Containerfile"
grep -Fq 'COPY overlay/ ./' "$ROOT/Containerfile"
grep -Fq 'cmake --install build --prefix /build/overlay/install' "$ROOT/Containerfile"
grep -Fq 'source=/build/overlay/install,target=/packages/overlay-build' "$ROOT/Containerfile"
test "$(grep -n 'WORKDIR /build/armada-store' "$ROOT/Containerfile" | cut -d: -f1)" -lt \
    "$(grep -n 'FROM ${BASE_IMAGE} AS overlay-build' "$ROOT/Containerfile" | cut -d: -f1)"
grep -Fq 'QQmlApplicationEngine' "$ROOT/overlay/main.cpp"
grep -Fq 'inputAction' "$ROOT/overlay/main.cpp"
grep -Fq 'ui_up' "$ROOT/overlay/main.cpp"
grep -Fq 'ui_accept' "$ROOT/overlay/main.cpp"
grep -Fq 'ui_guide' "$ROOT/overlay/main.cpp"
grep -Fq 'Gamepad:Button:QuickAccess' "$ROOT/overlay/main.cpp"
grep -Fq 'GamepadOrder' "$ROOT/overlay/main.cpp"
grep -Fq 'DbusDevices' "$ROOT/overlay/main.cpp"
grep -Fq 'org.freedesktop.DBus.Properties' "$ROOT/overlay/main.cpp"
grep -Fq 'qvariant_cast<QDBusVariant>' "$ROOT/overlay/main.cpp"
if grep -Fq 'devices/target/dbus0' "$ROOT/overlay/main.cpp"; then
    echo "overlay still hard-codes the InputPlumber DBus target" >&2
    exit 1
fi
grep -Fq 'navigationActive' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'Qt.callLater(function() { navigation.forceActiveFocus(); })' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'focus: false' "$ROOT/overlay/qml/FocusRow.qml"
grep -Fq 'sidePanel' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'overlay-gestures' "$ROOT/tests/armada-overlay-gestures-test.sh"
grep -Fq 'panelAnimationMs' "$ROOT/overlay/qml/Theme.qml"
grep -Fq 'saveOverlayConfig' "$ROOT/overlay/main.cpp"
grep -Fq 'QStringLiteral("pass")' "$ROOT/overlay/main.cpp"
grep -Fq 'activationReady_' "$ROOT/overlay/main.cpp"
grep -Fq 'overlayVisible' "$ROOT/overlay/main.cpp"
grep -Fq 'centeredChord' "$ROOT/overlay/qml/SettingsPage.qml"
grep -Fq 'sideChord' "$ROOT/overlay/qml/SettingsPage.qml"
grep -Fq 'Edge swipe to open' "$ROOT/overlay/qml/SettingsPage.qml"
grep -Fq 'config[key] !== undefined' "$ROOT/overlay/qml/SettingsPage.qml"
grep -Fq 'onErrorMessage' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'property color error' "$ROOT/overlay/qml/Theme.qml"
grep -Fq 'property int bodySize: 23' "$ROOT/overlay/qml/Theme.qml"
grep -Fq 'property color rowFocused: "#1A9FFF"' "$ROOT/overlay/qml/Theme.qml"
grep -Fq 'focusRecoveryTimer_' "$ROOT/overlay/main.cpp"
grep -Fq 'acceptedButtons: Qt.AllButtons' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'QDir::AllEntries' "$ROOT/overlay/main.cpp"
grep -Fq 'pageIcons' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'property var backend: armada' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'armada: root.backend' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'font.pixelSize: root.theme.bodySize' "$ROOT/overlay/qml/FocusRow.qml"
for control in SelectRow SliderRow ToggleRow; do
    test -f "$ROOT/overlay/qml/$control.qml"
    grep -Fq "import QtQuick.Controls" "$ROOT/overlay/qml/$control.qml"
done
grep -Fq 'navigationActive' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'SliderRow' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'ToggleRow' "$ROOT/overlay/qml/SettingsPage.qml"
grep -Fq 'SelectRow' "$ROOT/overlay/qml/CompatibilityPage.qml"
grep -Fq 'SelectRow' "$ROOT/overlay/qml/GamePage.qml"
grep -Fq 'SliderRow' "$ROOT/overlay/qml/GamePage.qml"
grep -Fq 'ToggleRow' "$ROOT/overlay/qml/GamePage.qml"
grep -Fq 'onPressedChanged' "$ROOT/overlay/qml/SelectRow.qml"
grep -Fq 'property bool popupOpen' "$ROOT/overlay/qml/SelectRow.qml"
grep -Fq 'function handleAction(action)' "$ROOT/overlay/qml/SelectRow.qml"
grep -Fq 'target: selector.popup' "$ROOT/overlay/qml/SelectRow.qml"
grep -Fq 'handlePopupAction(action)' "$ROOT/overlay/qml/Main.qml"
grep -Fq 'onPressedChanged' "$ROOT/overlay/qml/SliderRow.qml"
grep -Fq 'onPressedChanged' "$ROOT/overlay/qml/ToggleRow.qml"
grep -Fq 'Vulkan realtime queue' "$ROOT/overlay/qml/GamePage.qml"
grep -Fq 'Reset all game compatibility' "$ROOT/overlay/qml/CompatibilityPage.qml"
for icon in status power fans games settings calibration; do
    test -f "$ROOT/overlay/qml/icons/$icon.svg"
done

printf 'Armada overlay API tests passed\n'
