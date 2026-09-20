# Initrd recovery helper on scratch VFAT

Captured 2026-09-20 21:48 UTC. This was a filesystem integration test only.
It did not stage or boot the PCIe OPP candidate, mount the Nova ESP, or run a
suspend test.

## Setup

- Device was in Armada Linux on kernel `7.2.3`.
- Candidate image: `localhost/armada-pcie-opp-test-initrd-guard:20260920-04`,
  digest `sha256:f2aa1e6b6dea32ac27a8324c6215685d0121bfee4ac7e5430e7ddcf179325682`.
- Extracted `/usr/libexec/armada/sm8550-pcie-opp-initrd-recover` from that
  image's generated `/usr/lib/modules/7.2.3/initramfs.img` with `lsinitrd -f`.
  Its SHA-256 `fac5cfe70bbcdf24a566b0dda2daef2ad8ea8f193177858f56fa72f8b39c87b6`
  matched both the tracked `recover.sh` and the copy in the dracut module.
- Created a 256 MiB FAT32 image in a temporary directory below
  `/var/home/armada/.cache`, attached it to otherwise-unused `/dev/loop2`, and
  mounted it inside the candidate OCI container. The container received only
  that scratch directory plus `/dev/loop-control` and `/dev/loop2`; the actual
  `/boot/efi` was not exposed.
- Overrode every recovery path to point to the loop filesystem and a scratch
  marker. A `systemctl` stub recorded the reboot request without rebooting.

The successful invocation used rootful Podman with `--network=host`,
`--cap-add=SYS_ADMIN`, `--security-opt=label=disable`, the two loop devices,
and `-i` to pass the test script to the container. No privileged container or
direct host ESP access was used.

## Results

- **Success path passed.** Backup fixture hash was
  `93140f66a789cdabf4cba3bc6b7dbdd4b162e8b23dbf5af38e74c30ba998e497`. The
  helper restored `KERNEL` byte-for-byte from `KERNEL.BAK`, set the active
  image ID to the test stock ID, left `.armada-bootimg.prev.id` untouched,
  and invoked the stub with `reboot --force`.
- **Wrong-hash path passed.** With expected hash set to `deadbeef`, the helper
  returned failure. The candidate `KERNEL` and image ID remained unchanged,
  and no additional reboot was requested.
- The scratch directory was removed; `/dev/loop2` was detached. A final
  read-only `bootc status` still showed the stock beta image digest
  `sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88`.

## Boundary

This verifies the generated helper against a real VFAT mount and validates
its hash-check/copy/rename/stamp operations. It does not exercise initrd
systemd ordering, a candidate boot, the actual ESP, or failures before the
initrd recovery timer starts. The previous candidate's stall phase remains
unknown, so this does not remove the need for manual ABL recovery if the
kernel or initrd systemd fails early.
