#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/busctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${BUSCTL_LOG}"
if [[ "$*" == *"get-property org.shadowblip.InputPlumber /org/shadowblip/InputPlumber/Manager"* ]]; then
    printf 'as 2 "/org/shadowblip/InputPlumber/CompositeDevice9" "/org/shadowblip/InputPlumber/CompositeDevice2"\n'
elif [[ "$*" == *"CompositeDevice9"*"DbusDevices"* ]]; then
    printf 'as 1 "/org/shadowblip/InputPlumber/devices/target/dbus3"\n'
elif [[ "$*" == *"CompositeDevice2"*"DbusDevices"* ]]; then
    printf 'as 0\n'
elif [[ "$*" == *"get-property"*"InterceptMode"* ]]; then
    printf 'u 0\n'
fi
EOF
chmod 755 "$WORK/busctl"

BUSCTL_LOG="$WORK/busctl.log" PATH="$WORK:$PATH" \
    "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept" status >/dev/null
grep -Fq '/org/shadowblip/InputPlumber/CompositeDevice9' "$WORK/busctl.log"

: > "$WORK/busctl.log"
BUSCTL_LOG="$WORK/busctl.log" PATH="$WORK:$PATH" \
    "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept" activation select_l1 >/dev/null
grep -Fq 'CompositeDevice9' "$WORK/busctl.log"
grep -Fq 'ass 2 Gamepad:Button:Select Gamepad:Button:LeftBumper Gamepad:Button:Guide' "$WORK/busctl.log"

: > "$WORK/busctl.log"
BUSCTL_LOG="$WORK/busctl.log" PATH="$WORK:$PATH" \
    "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept" pass >/dev/null
grep -Fq 'CompositeDevice9' "$WORK/busctl.log"
grep -Fq 'set-property org.shadowblip.InputPlumber /org/shadowblip/InputPlumber/CompositeDevice9 org.shadowblip.Input.CompositeDevice InterceptMode u 1' "$WORK/busctl.log"

: > "$WORK/busctl.log"
BUSCTL_LOG="$WORK/busctl.log" PATH="$WORK:$PATH" \
    "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept" trigger >/dev/null
grep -Fq 'SendButtonChord as 1 Gamepad:Button:QuickAccess2' "$WORK/busctl.log"

if BUSCTL_LOG="$WORK/busctl.log" PATH="$WORK:$PATH" \
    "$ROOT/system_files/usr/libexec/armada/inputplumber-intercept" activation arbitrary >/dev/null 2>&1; then
    echo "helper accepted an arbitrary activation chord" >&2
    exit 1
fi

printf 'InputPlumber interception helper tests passed\n'
