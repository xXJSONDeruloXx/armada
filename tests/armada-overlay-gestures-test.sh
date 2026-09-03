#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 -B - "$ROOT" <<'PYEOF'
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
path = root / "system_files/usr/libexec/armada/overlay-gestures"
spec = importlib.util.spec_from_loader(
    "armada_overlay_gestures",
    importlib.machinery.SourceFileLoader("armada_overlay_gestures", str(path)),
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

assert module.gesture_started("left", 0.05, 0.5)
assert not module.gesture_started("left", 0.2, 0.5)
assert module.gesture_started("right", 0.95, 0.5)
assert module.gesture_started("bottom", 0.5, 0.95)
assert module.gesture_reached("left", 0.05, 0.5, 0.20, 0.5, 0.1)
assert module.gesture_reached("right", 0.95, 0.5, 0.80, 0.5, 0.1)
assert module.gesture_reached("bottom", 0.5, 0.95, 0.5, 0.80, 0.1)
assert not module.gesture_reached("left", 0.05, 0.5, 0.10, 0.6, 0.1)
assert module.has_bit(root / "tests" / "missing-capability-file", 53) is False

with tempfile.TemporaryDirectory() as directory:
    config = pathlib.Path(directory) / "overlay.json"
    config.write_text(json.dumps({"swipeEnabled": False, "swipeEdge": "right", "swipeDistance": 999}))
    module.CONFIG = config
    loaded = module.load_config()
    assert loaded == {"swipeEnabled": False, "swipeEdge": "right", "swipeDistance": 320}, loaded

    read_fd, write_fd = os.pipe()
    os.set_blocking(read_fd, False)
    device = object.__new__(module.TouchDevice)
    device.fd = read_fd
    device.multitouch = True
    device.x_code = module.ABS_MT_POSITION_X
    device.y_code = module.ABS_MT_POSITION_Y
    device.x_range = (0, 1279)
    device.y_range = (0, 959)
    device.slot = 0
    device.contacts = {}
    device.single = {"x": 0, "y": 0, "touching": False}
    device.buffer = b""

    def event(event_type, code, value):
        return module.INPUT_EVENT.pack(0, 0, event_type, code, value)

    frame = b"".join([
        event(module.EV_ABS, module.ABS_MT_TRACKING_ID, 1),
        event(module.EV_ABS, module.ABS_MT_POSITION_X, 64),
        event(module.EV_ABS, module.ABS_MT_POSITION_Y, 480),
        event(module.EV_SYN, module.SYN_REPORT, 0),
        event(module.EV_ABS, module.ABS_MT_SLOT, 1),
        event(module.EV_ABS, module.ABS_MT_TRACKING_ID, 2),
        event(module.EV_ABS, module.ABS_MT_POSITION_X, 1000),
        event(module.EV_ABS, module.ABS_MT_POSITION_Y, 480),
        event(module.EV_SYN, module.SYN_REPORT, 0),
    ])
    os.write(write_fd, frame)
    snapshots = device.read_contacts()
    assert len(snapshots) == 2 and len(snapshots[-1]) == 2, snapshots
    device.close()
    os.close(write_fd)
print("Armada overlay gesture tests passed")
PYEOF
