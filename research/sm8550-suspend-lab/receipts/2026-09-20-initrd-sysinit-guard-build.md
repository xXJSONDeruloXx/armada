# Candidate-only `sysinit.target` initrd guard build

Captured 2026-09-20 23:35 UTC. This produced and inspected a local OCI
candidate only. It did not stage/apply a bootc deployment, write the ESP,
reboot the Nova, or run a suspend test.

## Change

The initrd timer is now linked from
`usr/lib/systemd/system/sysinit.target.wants/` and declares
`Before=sysinit.target`. Armada's device systemd 259 unit files show that
`basic.target` requires and follows `sysinit.target`, and the initrd's
`initrd.target` requires and follows `basic.target`. This starts the recovery
countdown while sysinit dependencies are pending, earlier than the previous
link from `basic.target.wants`.

The timer still depends on initrd systemd starting and queuing the initrd
target graph. It cannot recover a kernel failure or an initrd systemd failure
before `sysinit.target` is pulled in. Manual ABL recovery is still required
for that remaining failure window.

## Build

- Tag: `localhost/armada-pcie-opp-test-initrd-guard:20260920-06`
- Version: `20260920.pcie-opp-test-initrd-guard-04`
- Manifest digest: `sha256:21ba7a30b3585f3f438b32a1dbd8e4d4c2435d7ab968e9b91ed39acfa4a3cad6`
- Image ID: `9bdbc4f0c2f57eb07f0a46b663dcc1561b46dddab73b3094257c3ac6bf187f55`
- Reported image size: 12,634,082,431 bytes
- Candidate kernel SHA-256: `15b46efc40d15200523b5c7ec623f54d4ac03bddfe798f1d8842ebf1fa2824d9`
- Nova DTB SHA-256: `72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422`
- Generated initramfs SHA-256: `ef68e9b36f053a624b64209632267c12e8be3cb98e9def1fa93fb813d5f84a6d`

Build hash assertions passed. No kernel compile ran; the existing candidate
kernel and DTB were reused.

## Verification

- `bash -n` passed for the guard module and recovery script.
- `tests/test-initrd-recovery.sh` passed its backup-hash, marker, mount, and
  read-only-ESP cases.
- The build's `lsinitrd` assertion passed. Unpacking the generated initramfs
  confirmed the timer symlink in `sysinit.target.wants`, the exact
  `Before=sysinit.target basic.target dracut-pre-mount.service
  initrd-switch-root.target` ordering, and the executable recovery helper.
- Isolated `systemd-analyze verify` passed for the recovery service/timer after
  using `/bin/true` in a temporary service copy because the real helper exists
  only inside the initramfs. Verifying every extracted initrd unit exits 1 on
  the existing `armada-splash-initrd.service` `KillMode=none` warning; no
  recovery-unit error was reported.

## Live state

After the build, SSH still reported kernel `7.2.3` and boot ID
`aa40c55e-d558-46a9-a710-3a7d926b9e9e`. `ostree admin status` listed only the
booted default deployment. The new image is in rootful Podman storage only;
no deployment is staged and no boot/ESP state changed. Manual ABL recovery is
still the gate before the PCIe OPP A/B.
