# Candidate-only earlier initrd recovery timer build

Captured 2026-09-20 22:43 UTC. This built and inspected an OCI candidate only.
It did not stage/apply a bootc deployment, write the ESP, reboot, or run a
suspend test.

## Change

The previous initrd recovery timer was wanted by
`dracut-pre-mount.service`. The candidate now installs a symlink in
`basic.target.wants` and orders the timer before `basic.target` as well as
`dracut-pre-mount.service` and `initrd-switch-root.target`. This moves its
120-second countdown earlier in initrd boot. It still cannot recover a kernel
failure or an initrd systemd failure before systemd queues `basic.target`.

## Build

- Tag: `localhost/armada-pcie-opp-test-initrd-guard:20260920-05`
- Version label: `20260920.pcie-opp-test-initrd-guard-03`
- Manifest digest: `sha256:ee083828400828329df59ad7ca9084a8a745894d95831efeb8e77a1f1d5688cc`
- Image ID: `a0455586b6be5aa5770e0afcd69523cd07ca6e849bfe45efc6af7acb3676b0b2`
- Generated initramfs SHA-256:
  `9d71e262d0190f220c3cf685b656986fc6001b3cc775ee795460c793aa91379d`

The pinned Armada beta base was used with the existing hash-verified Linux
7.2.3 kernel and Nova DTB. The first build regenerated the initramfs, then
failed only at the final assertion for the systemd symlink: `lsinitrd` prints
the symlink path before `->` and its target last, so the generic `$NF` test
looked at the target. The Containerfile now checks the symlink path directly.
The rebuild passed all assertions and tagged the image. Dracut printed
`No '/dev/log' or 'logger' included for syslog logging`; it exited successfully.

## Verification

- `bash -n` passed for the dracut module, recovery script, and test harness.
- `tests/test-initrd-recovery.sh` passed its valid-backup, wrong-hash, missing
  marker, mount-failure, and read-only-ESP cases.
- `git diff --check` passed.
- `lsinitrd` shows
  `basic.target.wants/sm8550-pcie-opp-initrd-recover.timer` as a symlink to
  the recovery timer.
- The generated timer contains
  `Before=basic.target dracut-pre-mount.service initrd-switch-root.target`.
- `systemd-analyze verify` passed for the extracted initrd service/timer and
  the image's real-root rollback service/timer.

## Device state and limit

After the build, SSH still reported boot ID
`aa40c55e-d558-46a9-a710-3a7d926b9e9e`, kernel `7.2.3`, and Armada version
`20260915.feca679`. `bootc status` reported the default image, no staged
deployment, no rollback, and no queued rollback. The image exists only in
rootful Podman storage; no live boot state changed.

This improves timer coverage but does not prove that initrd systemd reaches
the `basic.target` transaction on the previously failing candidate. The
kernel/initrd-systemd gap still requires manual ABL recovery. Do not treat the
new guard as sufficient to stage or reboot the PCIe OPP candidate unattended.
