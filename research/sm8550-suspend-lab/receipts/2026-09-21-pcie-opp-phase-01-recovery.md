# Phase-marker candidate recovered in initrd before candidate-root marker

Captured 2026-09-21 01:08 UTC on `feat/sm8550-suspend-lab`. The phase-marker
PCIe OPP image was staged and applied while the owner was available for ABL
recovery. It did not reach a confirmed candidate userspace, and no suspend
command was run.

## Boot phase evidence

- Candidate manifest: `sha256:54ab4a31d2669ed6fe4d48f782396f6a44464c239d86ee69b3dabc74424089d5`
- Candidate test boot ID, from ESP `SUSDIAG.LOG`:
  `5debf421-a407-40be-926b-3803174e6291`
- Persisted ESP event:
  `event=stock_kernel_restored boot_id=5debf421-a407-40be-926b-3803174e6291`
- The candidate-root marker
  `/var/lib/sm8550-pcie-opp-test/boot-phases.log` is absent.
- The candidate boot ID is absent from `journalctl --list-boots`; the current
  stock boot and prior stock boot are present, but the candidate initrd's
  journal was not retained in the root filesystem.

The persisted event proves the initrd recovery helper executed on the
candidate boot, verified the expected stock backup hash, restored the backup
to `KERNEL`, updated the stock image ID stamp, and requested a forced reboot.
The missing root-phase marker means Armada's boot-image sync service never
recorded a candidate root/version. Combined with the initrd helper being the
only producer of this event and its conflict with `initrd-switch-root.target`,
the strongest current interpretation is that candidate boot remained in the
initrd beyond its 120-second recovery timer and did not complete switch-root.
This does not identify the specific initrd failure. The possibility of
additional manual ABL intervention is also not distinguishable from these
records.

## ESP and bootc state

Before cleanup, root `bootc status --json` showed stock beta booted, the test
image in the rollback slot, `rollbackQueued=true`, and
`spec.bootOrder=rollback`. ESP `KERNEL` had SHA-256
`b45365f5d3e2729907b18b0a31bde17fcdeaf5ba95fafe480a103c2993b9712c`; the
`KERNEL.BAK` hash was the verified stock value
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`. The
current stock boot's `armada-bootimg-sync.service` log says it wrote
`/boot/efi/KERNEL` for `vmlinuz-7.2.3` after the recovery reboot, while the
failed deployment was still queued. This matches the prior finding that a
stock boot can regenerate the next-boot kernel from the pending BLS target.

Restored the known-good state without another reboot using:

```sh
sudo rpm-ostree cleanup --pending
sudo /usr/libexec/armada/armada-bootimg-update
```

Cleanup removed one deployment and pruned one image (137 layers; 114.2 MB
freed). Bootc then reported `bootOrder=default`, `rollback=null`,
`rollbackQueued=false`, and `staged=null`. Both ESP kernel files again match
the stock SHA-256; both image-ID stamps are the stock ID
`d7755f13ac5a1224fef222e2d104192045fd01d61924f9b1ae31e941b73f049b`.

The device is healthy on stock `20260915.feca679` / kernel `7.2.3`, boot ID
`5263e173-9323-426b-aee2-6fe6f3dc4bfd`, systemd `running` with zero failed
units, Wi-Fi connected, and RTC wakealarm empty.

## Next diagnostic

The candidate initrd already contains both `systemd-journald` and
`/usr/bin/journalctl`, so no additional package or kernel build is needed.
Before another boot attempt, modify the recovery helper to atomically persist
a bounded snapshot of the last initrd journal lines to ESP
`SUSDIAG.JRN` before replacing `KERNEL`. Keep the recovery timer and PCIe OPP
unchanged for that attempt. Inspect the snapshot before deciding whether to
extend the guard or retry the OPP A/B. The current run provides no evidence
about PCIe OPP, Apps-RSC, PSCI, AOSD/CXSD/DDR, or Wi-Fi resume behavior.
