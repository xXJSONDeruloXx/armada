#!/bin/bash
set -euo pipefail

ESP_DEVICE=${ARMADA_PCIE_TEST_ESP_DEVICE:-/dev/disk/by-uuid/81DC-CB41}
ESP_MOUNT=${ARMADA_PCIE_TEST_ESP_MOUNT:-/run/armada/pcie-opp-esp}
SYSROOT_ESP=${ARMADA_PCIE_TEST_SYSROOT_ESP:-/sysroot/boot/efi}
MARKER=${ARMADA_PCIE_TEST_MARKER:-/usr/lib/armada/suspend-lab/pcie-opp-test-rollback}
EXPECTED_BACKUP_SHA256=${ARMADA_PCIE_TEST_BACKUP_SHA256:-0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000}
STOCK_IMAGE_ID=${ARMADA_PCIE_TEST_STOCK_ID:-d7755f13ac5a1224fef222e2d104192045fd01d61924f9b1ae31e941b73f049b}

log() {
    { printf 'sm8550-pcie-opp-initrd-recover: %s\n' "$*" > /dev/kmsg; } 2>/dev/null || true
}

fail() {
    log "$*; leaving the current boot image untouched"
    exit 1
}

[[ -f "$MARKER" ]] || fail "candidate marker missing"

for ((attempt = 0; attempt < 30; attempt++)); do
    [[ -e "$ESP_DEVICE" ]] && break
    ESP_DEVICE=$(blkid -U 81DC-CB41 2>/dev/null || true)
    [[ -e "$ESP_DEVICE" ]] && break
    sleep 1
done
[[ -e "$ESP_DEVICE" ]] || fail "ESP device not present: $ESP_DEVICE"

mkdir -p "$ESP_MOUNT"
owned_mount=0
mount_target=$SYSROOT_ESP
fstype=$(findmnt --noheadings --raw --target "$mount_target" --output FSTYPE 2>/dev/null || true)
if [[ "$fstype" == vfat ]]; then
    options=$(findmnt --noheadings --raw --target "$mount_target" --output OPTIONS 2>/dev/null || true)
    [[ ",$options," == *,rw,* ]] || fail "ESP already mounted read-only"
    ESP_MOUNT=$mount_target
else
    mount -t vfat -o rw,shortname=winnt "$ESP_DEVICE" "$ESP_MOUNT" ||
        fail "could not mount ESP"
    owned_mount=1
    mount_target=$ESP_MOUNT
fi

fstype=$(findmnt --noheadings --raw --target "$mount_target" --output FSTYPE 2>/dev/null || true)
options=$(findmnt --noheadings --raw --target "$mount_target" --output OPTIONS 2>/dev/null || true)
[[ "$fstype" == vfat ]] || fail "ESP mount is not vfat: $fstype"
[[ ",$options," == *,rw,* ]] || fail "ESP mount is not writable"

cleanup() {
    if (( owned_mount )); then
        umount "$ESP_MOUNT" || log "could not unmount ESP after syncing it"
    fi
}
trap cleanup EXIT

backup="$ESP_MOUNT/KERNEL.BAK"
[[ -f "$backup" ]] || fail "KERNEL.BAK is missing"
digest=$(sha256sum "$backup") || fail "could not hash KERNEL.BAK"
digest=${digest%% *}
[[ "$digest" == "$EXPECTED_BACKUP_SHA256" ]] ||
    fail "KERNEL.BAK hash mismatch: $digest"

kernel_tmp="$ESP_MOUNT/KERNEL.TMP"
cp -f "$backup" "$kernel_tmp" || fail "could not copy KERNEL.BAK"
sync "$kernel_tmp" || fail "could not sync temporary kernel"
digest=$(sha256sum "$kernel_tmp") || fail "could not verify temporary kernel"
digest=${digest%% *}
[[ "$digest" == "$EXPECTED_BACKUP_SHA256" ]] ||
    fail "temporary kernel hash mismatch: $digest"
mv -f "$kernel_tmp" "$ESP_MOUNT/KERNEL" || fail "could not replace KERNEL"
sync

stamp_tmp="$ESP_MOUNT/.armada-bootimg.id.tmp"
if printf '%s' "$STOCK_IMAGE_ID" > "$stamp_tmp" &&
   sync "$stamp_tmp" &&
   mv -f "$stamp_tmp" "$ESP_MOUNT/.armada-bootimg.id"; then
    sync
else
    rm -f "$stamp_tmp" 2>/dev/null || true
    log "restored KERNEL but could not update its image ID stamp"
fi

log "restored stock KERNEL after initrd timeout; requesting reboot"
systemctl reboot --force
