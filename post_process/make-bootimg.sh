#!/bin/bash
# Assemble an ABL-bootable Android boot.img and stage it as /KERNEL.
set -euxo pipefail

RAW="${1:-output/image/disk.raw}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MKBOOTIMG="${MKBOOTIMG:-${SCRIPT_DIR}/../vendor/mkbootimg/mkbootimg.py}"

# SM8550 devices share board-id; list all supported DTBs.
SUPPORTED_DTBS="qcs8550-ayaneo-pocketevo qcs8550-ayn-odin2portal qcs8550-ayn-odin2 qcs8550-ayn-odin2mini qcs8550-retroidpocket-rp6 qcs8550-retroidpocket-rp6-top-dpad qcs8550-ayaneo-pocketace qcs8550-ayaneo-pocketdmg qcs8550-ayaneo-pocketds qcs8550-ayaneo-pockets2k qcs8550-ayn-thor"

[[ -f "${RAW}" ]] || { echo "raw image not found: ${RAW} (run a build first)"; exit 1; }

WORK=$(mktemp -d)
LOOP=$(sudo losetup -fP --show "${RAW}")
trap 'sudo umount "${WORK}/p1" 2>/dev/null||true; sudo umount "${WORK}/p2" 2>/dev/null||true; sudo losetup -d "${LOOP}" 2>/dev/null||true; rm -rf "${WORK}"' EXIT

mkdir -p "${WORK}/p1" "${WORK}/p2"
sudo mount "${LOOP}p2" "${WORK}/p2"          # /boot

DEPLOY=$(sudo ls "${WORK}/p2/ostree" | grep '^default-' | head -1)
BOOTDIR="${WORK}/p2/ostree/${DEPLOY}"
KVER=$(basename "$(sudo ls "${BOOTDIR}"/vmlinuz-* | head -1)" | sed 's/^vmlinuz-//')
CMDLINE=$(sudo grep -h '^options ' "${WORK}/p2"/loader*/entries/*.conf | head -1 | sed 's/^options //')

# Fit the 512-byte cmdline: drop serial console, ostree= first, keep splash kargs.
_drop=" console=ttyS0 "
_ostree=""; _rest=""
for _t in ${CMDLINE}; do
    case "${_drop}" in *" ${_t} "*) continue ;; esac
    case "${_t}" in ostree=*) _ostree="${_t}" ;; *) _rest="${_rest} ${_t}" ;; esac
done
CMDLINE="${_ostree}${_rest}"

# ROCKNIX ABL expects gzip(Image) with DTBs appended.
sudo cat "${BOOTDIR}/vmlinuz-${KVER}" > "${WORK}/vmlinuz"
sudo cat "${BOOTDIR}/initramfs-${KVER}.img" > "${WORK}/initramfs"
gzip -c "${WORK}/vmlinuz" > "${WORK}/kernel.gz"
for _name in ${SUPPORTED_DTBS}; do
    _dtb="${BOOTDIR}/dtb/qcom/${_name}.dtb"
    sudo test -f "${_dtb}" || { echo "ERROR: supported DTB missing: ${_dtb}"; exit 1; }
    sudo cat "${_dtb}" >> "${WORK}/kernel.gz"
done

python3 "${MKBOOTIMG}" \
    --kernel "${WORK}/kernel.gz" --ramdisk "${WORK}/initramfs" \
    --kernel_offset 0x00008000 --ramdisk_offset 0x06000000 --tags_offset 0x00000100 \
    --os_version 12.0.0 --os_patch_level "$(date '+%Y-%m')" --header_version 0 \
    --cmdline "${CMDLINE}" \
    -o "${WORK}/KERNEL"

sudo mount "${LOOP}p1" "${WORK}/p1"
sudo cp "${WORK}/KERNEL" "${WORK}/p1/KERNEL"
sudo sync

echo "Staged /KERNEL ($(du -h "${WORK}/KERNEL" | cut -f1)) on the FAT partition of ${RAW}"
echo "deploy=${DEPLOY} kver=${KVER}"
echo "cmdline=${CMDLINE}"
