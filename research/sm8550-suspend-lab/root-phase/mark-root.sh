#!/bin/bash
set -euo pipefail

STATE_FILE=${ARMADA_PCIE_TEST_STATE_FILE:-/var/lib/sm8550-pcie-opp-test/boot-phases.log}
VERSION_FILE=${ARMADA_PCIE_TEST_VERSION_FILE:-/usr/lib/armada/version}

boot_id=unknown
version=unknown
if [[ -r /proc/sys/kernel/random/boot_id ]]; then
    IFS= read -r boot_id < /proc/sys/kernel/random/boot_id || true
fi
IFS= read -r version < "$VERSION_FILE" 2>/dev/null || true

state_dir=${STATE_FILE%/*}
mkdir -p "$state_dir"
printf 'root boot_id=%s version=%s\n' "$boot_id" "$version" >> "$STATE_FILE"
sync "$STATE_FILE"
