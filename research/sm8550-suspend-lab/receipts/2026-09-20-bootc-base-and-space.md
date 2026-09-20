# Current bootc base and device storage preflight

Captured 2026-09-20 14:47 UTC. Read-only inspection; no image was pulled,
built, staged, or deployed.

## Active and rollback deployments

Unprivileged `rpm-ostree status --json` reports two deployments with the same
OSTree checksum `ec096ad2fdb64e35dd9b2ac691690d80f6e62d80c2617704d2a5788c7b95294b`
and version `20260915.feca679`. One is booted (`.3`), the other is not (`.2`);
neither is staged. Both refer to
`ostree-image-signed:docker://ghcr.io/armada-os/armada:beta`, image manifest
digest
`sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88`.

Both current BLS entries point to the installed kernel files under
`/ostree/.../vmlinuz-7.2.3` and `initramfs-7.2.3.img`. The running kernel is
`7.2.3`. This confirms the prospective test must preserve the existing
7.2.3 module tree and use the current Armada base digest. The older
`device-kernel-layer.Containerfile` is explicitly based on
`localhost/armada-rsc:20260901` and replaces kernel 7.2.0; it is historical and
must not be used unchanged.

## Storage check

Rootful Podman currently has only the 199 MB Fedora builder image, not the
Armada base. `/var` is Btrfs on `/dev/sda20`, 92 GB total, 53 GB used, 37 GB
available. The Armada OCI manifest's compressed layer sizes sum to
6,068,940,860 bytes (about 5.65 GiB). This is only the compressed transfer
size; extracted Podman layers and bootc/OSTree staging also consume space.
Do not pull the base until the unpacked/staged storage budget has a safe margin.

The base layer-size list was parsed from the active deployment's embedded OCI
manifest in `rpm-ostree status --json`; no image-layer download was needed.
The deployment and storage readings can be refreshed cheaply before any
future stage. No device state changed in this preflight.
