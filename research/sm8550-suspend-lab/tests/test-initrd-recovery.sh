#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT/initrd-guard/recover.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mock="$tmp/mock-bin"
mkdir -p "$mock"
cat > "$mock/findmnt" <<'SH'
#!/bin/sh
target=
output=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --target) shift; target=$1 ;;
        --output) shift; output=$1 ;;
    esac
    shift
done
if [ "$target" = "$MOCK_ESP_MOUNT" ] && [ -f "$MOCK_MOUNTED" ]; then
    case "$output" in
        FSTYPE) printf '%s\n' vfat ;;
        OPTIONS) printf '%s\n' rw,relatime ;;
        *) exit 1 ;;
    esac
    exit 0
fi
if [ "$target" = "$MOCK_SYSROOT_ESP" ] && [ -n "${MOCK_ROOT_FSTYPE:-}" ]; then
    case "$output" in
        FSTYPE) printf '%s\n' "$MOCK_ROOT_FSTYPE" ;;
        OPTIONS) printf '%s\n' "${MOCK_ROOT_OPTIONS:-}" ;;
        *) exit 1 ;;
    esac
    exit 0
fi
exit 1
SH
cat > "$mock/mount" <<'SH'
#!/bin/sh
[ "${MOCK_MOUNT_FAIL:-0}" = 0 ] || exit 1
: > "$MOCK_MOUNTED"
SH
cat > "$mock/umount" <<'SH'
#!/bin/sh
rm -f "$MOCK_MOUNTED"
exit 0
SH
cat > "$mock/systemctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_REBOOT_LOG"
SH
cat > "$mock/sha256sum" <<'SH'
#!/usr/bin/env python3
import hashlib
import sys

for name in sys.argv[1:]:
    digest = hashlib.sha256()
    with open(name, "rb") as stream:
        for block in iter(lambda: stream.read(65536), b""):
            digest.update(block)
    digest = digest.hexdigest()
    print(f"{digest}  {name}")
SH
chmod +x "$mock"/*

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

new_case() {
    case_dir="$tmp/$1"
    esp="$case_dir/esp"
    mkdir -p "$esp" "$case_dir/run" "$case_dir/sysroot-esp"
    : > "$case_dir/device"
    printf 'stock boot image fixture\n' > "$esp/KERNEL.BAK"
    printf 'candidate boot image fixture\n' > "$esp/KERNEL"
    printf 'candidate-id\n' > "$esp/.armada-bootimg.id"
    printf 'stale-previous-id\n' > "$esp/.armada-bootimg.prev.id"
    : > "$case_dir/marker"
    : > "$case_dir/reboots"
    stock_hash=$(shasum -a 256 "$esp/KERNEL.BAK" | awk '{print $1}')
}

run_guard() {
    env PATH="$mock:$PATH" \
        MOCK_REBOOT_LOG="$case_dir/reboots" \
        MOCK_MOUNTED="$case_dir/mounted" \
        MOCK_ESP_MOUNT="$esp" \
        MOCK_SYSROOT_ESP="$case_dir/sysroot-esp" \
        MOCK_ROOT_FSTYPE="${MOCK_ROOT_FSTYPE:-}" \
        MOCK_ROOT_OPTIONS="${MOCK_ROOT_OPTIONS:-}" \
        MOCK_MOUNT_FAIL="${MOCK_MOUNT_FAIL:-0}" \
        ARMADA_PCIE_TEST_ESP_DEVICE="$case_dir/device" \
        ARMADA_PCIE_TEST_ESP_MOUNT="$esp" \
        ARMADA_PCIE_TEST_SYSROOT_ESP="$case_dir/sysroot-esp" \
        ARMADA_PCIE_TEST_MARKER="$case_dir/marker" \
        ARMADA_PCIE_TEST_BACKUP_SHA256="${EXPECTED_HASH:-$stock_hash}" \
        ARMADA_PCIE_TEST_STOCK_ID=known-stock-id \
        "$SCRIPT"
}

new_case valid
run_guard || fail 'valid backup was rejected'
cmp -s "$esp/KERNEL" "$esp/KERNEL.BAK" || fail 'stock KERNEL was not restored'
[[ $(cat "$esp/.armada-bootimg.id") == known-stock-id ]] || fail 'active ID was not repaired'
[[ $(cat "$esp/.armada-bootimg.prev.id") == stale-previous-id ]] || fail 'previous ID was changed'
grep -qx 'reboot --force' "$case_dir/reboots" || fail 'reboot was not requested'

new_case wrong_hash
EXPECTED_HASH=deadbeef
if run_guard; then fail 'wrong backup hash was accepted'; fi
unset EXPECTED_HASH
grep -q 'candidate boot image' "$esp/KERNEL" || fail 'wrong-hash case changed KERNEL'
grep -q 'candidate-id' "$esp/.armada-bootimg.id" || fail 'wrong-hash case changed stamp'
[[ ! -s "$case_dir/reboots" ]] || fail 'wrong-hash case requested reboot'

new_case missing_marker
rm "$case_dir/marker"
if run_guard; then fail 'missing marker was accepted'; fi
[[ ! -s "$case_dir/reboots" ]] || fail 'missing-marker case requested reboot'

new_case mount_failure
MOCK_MOUNT_FAIL=1
if run_guard; then fail 'mount failure was accepted'; fi
unset MOCK_MOUNT_FAIL
grep -q 'candidate boot image' "$esp/KERNEL" || fail 'mount-failure case changed KERNEL'
[[ ! -s "$case_dir/reboots" ]] || fail 'mount-failure case requested reboot'

new_case readonly_existing_mount
MOCK_ROOT_FSTYPE=vfat
MOCK_ROOT_OPTIONS=ro,relatime
if run_guard; then fail 'read-only ESP was accepted'; fi
unset MOCK_ROOT_FSTYPE MOCK_ROOT_OPTIONS
grep -q 'candidate boot image' "$esp/KERNEL" || fail 'read-only case changed KERNEL'
[[ ! -s "$case_dir/reboots" ]] || fail 'read-only case requested reboot'

printf '%s\n' 'initrd recovery tests passed'
