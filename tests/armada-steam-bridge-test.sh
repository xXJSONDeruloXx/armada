#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PYEOF'
import importlib.machinery
import importlib.util
import pathlib
import sys
import types

root = pathlib.Path(sys.argv[1])
fake_websocket = types.SimpleNamespace()
sys.modules["websocket"] = fake_websocket
spec = importlib.util.spec_from_loader(
    "armada_steam_bridge",
    importlib.machinery.SourceFileLoader("armada_steam_bridge", str(root / "system_files/usr/libexec/armada/steam-bridge")),
)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

assert bridge.tools([
    {"strToolName": "proton", "strDisplayName": "Proton"},
    {"strToolName": "", "strDisplayName": "ignored"},
    "ignored",
]) == [{"id": "proton", "label": "Proton"}]
assert bridge.appid("123") == 123
for invalid in ("", "-1", "1.5", "1" * 13, None):
    try:
        bridge.appid(invalid)
    except ValueError as error:
        assert str(error) == "invalid appid"
    else:
        raise AssertionError(f"accepted invalid AppID: {invalid!r}")

for invalid in ("x\x00y", "x" * (bridge.MAX_TEXT + 1)):
    try:
        bridge.js_string(invalid)
    except ValueError as error:
        assert str(error) == "text value is too long"
    else:
        raise AssertionError("accepted invalid text")

expressions = []
def evaluate(expression):
    expressions.append(expression)
    if "GetGlobalCompatTools" in expression:
        return [{"strToolName": "proton", "strDisplayName": "Proton"}]
    if "SetAppLaunchOptions" in expression:
        return True
    return "Default"

bridge.evaluate = evaluate
assert bridge.main({"action": "get_global_compat_tools"}) == {"tools": [{"id": "proton", "label": "Proton"}]}
assert bridge.main({"action": "set_launch_options", "appid": "123", "options": "%command%; $(id)"}) is True
assert expressions[-1] == 'window.SteamClient.Apps.SetAppLaunchOptions(123, "%command%; $(id)")'

try:
    bridge.main({"action": "set_resolution", "appid": "123", "value": "1920x1080"})
except ValueError as error:
    assert str(error) == "invalid resolution"
else:
    raise AssertionError("accepted invalid resolution")

try:
    bridge.main({"action": "unknown"})
except ValueError as error:
    assert str(error) == "unsupported Steam bridge action"
else:
    raise AssertionError("accepted unsupported action")
PYEOF

echo "Armada Steam bridge tests passed"
