# Candidate-only initrd recovery guard

Captured 2026-09-20 21:29 UTC. This work built and verified a candidate image
only. It did not stage/apply an OSTree deployment, write the device ESP, reboot,
or run a suspend test.

## Behavior

The guard is included only in the temporary PCIe OPP test image. A
`dracut-pre-mount.service` drop-in wants a 120-second initrd timer. The timer
is ordered before the pre-mount unit, so its clock starts when pre-mount is
queued rather than after it completes. If `initrd-switch-root.target` has not
started when the timer fires, the recovery service:

1. Requires the candidate marker and the Nova ESP.
2. Uses the existing mounted vfat ESP or mounts UUID `81DC-CB41` read/write.
3. Requires `KERNEL.BAK` to match the previously verified stock SHA-256:
   `0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`.
4. Copies the backup to `KERNEL.TMP`, syncs and hash-checks it, then renames it
   to `KERNEL`.
5. Writes the known stock image ID
   `d7755f13ac5a1224fef222e2d104192045fd01d61924f9b1ae31e941b73f049b`
   directly to `.armada-bootimg.id`; it never trusts the stale
   `.armada-bootimg.prev.id`.
6. Requests a reboot.

The helper stops on missing/mismatched inputs and never replaces `KERNEL`
before checking the backup and temporary copy. The existing five-minute
real-root rollback timer remains active in the image.

This is partial recovery only. The timer cannot run if the kernel or initrd
systemd fails before `dracut-pre-mount.service` is queued. The prior candidate
failure phase remains unknown, and there is no remote ABL, EFI BootNext, or
watchdog fallback. Do not treat this guard as proof that a boot cannot strand
the device.

## Build artifact

Built on the Nova from the pinned beta base and the existing hash-verified
kernel/DTB artifacts, without compiling the kernel:

- Tag: `localhost/armada-pcie-opp-test-initrd-guard:20260920-04`
- Version: `20260920.pcie-opp-test-initrd-guard-02`
- Manifest digest: `sha256:f2aa1e6b6dea32ac27a8324c6215685d0121bfee4ac7e5430e7ddcf179325682`
- Image ID: `2c67bc32cabdbc2147a02280069414a41bf883ea6a57788be77e31a81de4cc81`
- Initramfs size: `50,081,314` bytes
- Initramfs SHA-256: `c5d3275ea48c03c5f2ee5b64e4bf3b7afba07fc01db9f06998f6643d09ec2369`

The first un-staged build (`20260920-03`) was superseded before use after
review found that its timer waited for the pre-mount unit to finish. Version
`20260920-04` starts the timer before pre-mount work begins and does not order
the recovery service behind that work.

Dracut regenerated the initramfs with Armada's normal `ostree`,
`armada-splash`, and `armada-ostree-fallback` modules plus
`armada-pcie-opp-initrd-recovery`. It emitted a nonfatal
`No '/dev/log' or 'logger' included for syslog logging` message because the
container lacks those logging endpoints. The build exited successfully.

## Verification

- `bash -n` passed for the dracut module, recovery script, and test harness.
- `git diff --check` passed.
- `tests/test-initrd-recovery.sh` passed for a valid backup, wrong hash,
  missing marker, mount failure, and read-only existing ESP.
- `lsinitrd` confirmed the marker, recovery service/timer, pre-mount drop-in,
  helper, and required `blkid`, `cp`, `findmnt`, `mount`, `mv`, `sha256sum`,
  `sleep`, `sync`, `systemctl`, and `umount` programs.
- `systemd-analyze verify` passed for both initrd recovery units after exposing
  the initrd helper at its `ExecStart` path in a disposable container run; the
  existing real-root rollback service/timer also passed verification.
- `lsinitrd -f` confirmed the final timer has
  `Before=dracut-pre-mount.service initrd-switch-root.target`, and the
  pre-mount drop-in wants that timer.

No real ESP mount/write test or candidate boot was performed. The running
device remained on stock kernel `7.2.3`, boot ID
`aa40c55e-d558-46a9-a710-3a7d926b9e9e`. The candidate is not staged.
