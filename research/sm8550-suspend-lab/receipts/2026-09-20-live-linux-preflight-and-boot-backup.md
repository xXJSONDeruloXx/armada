# Live Linux preflight and boot-image backup

Captured 2026-09-20 16:34 UTC over the existing `armada` SSH key. Read-only
device checks and copying the current ESP files to the external build drive;
the OS image, ESP, and power configuration were not changed.

## Live device

- Fedora 44 / Armada Linux, kernel `7.2.3`.
- Boot ID `55fdad18-019d-4c92-8ebd-8a558574c1d3`.
- Wi-Fi `wlp1s0` connected; systemd reports `running`.
- `/var` has 37 GB free.
- `bootc status` reports booted and rollback deployments on
  `ghcr.io/armada-os/armada:beta` at manifest digest
  `sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88`
  and OSTree checksum
  `ec096ad2fdb64e35dd9b2ac691690d80f6e62d80c2617704d2a5788c7b95294b`;
  there is no staged deployment.
- Rootful Podman contains only the 199 MB Fedora builder image. The Armada
  base is not cached.
- The current sudoers rules allow the lab runner, rootful Podman, and bootc
  without a password. Generic root commands such as `sudo -n id` require the
  device password; no sudoers or SSH policy was changed.

## ESP backup

The active `/boot/efi/KERNEL` and `/boot/efi/KERNEL.BAK` each measured
75,522,048 bytes and had SHA-256
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000` on the
device. Both files were streamed from the root-owned ESP into this external
archive:

`/Volumes/NovaKernelBuild/backups/nova-esp-20260920T1634Z/boot-esp-kernel-pair.tar`

Archive SHA-256:
`0760f9acf1399a98186233800185b8a37a781247c0a10f12b98999da409eee16`.
The tar was enumerated and each extracted member independently hashed; both
match the device values above. The tar file is mode `0600` on the external
volume. It is intentionally outside Git.

## Gate

The original ESP image pair is preserved off-device, and bootc still has the
known base as both current and rollback deployment. This supports proceeding
with an OCI build and download-only stage, subject to rechecking free space,
the staged image identity, both deployments, and ESP hashes before any reboot.
This is not automatic recovery from a kernel hang; the retained ESP backup is
a manual recovery artifact.
