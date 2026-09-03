#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 -B - "$ROOT" <<'PYEOF'
import importlib.machinery
import importlib.util
import pathlib
import sys

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
print("Armada overlay gesture tests passed")
PYEOF
