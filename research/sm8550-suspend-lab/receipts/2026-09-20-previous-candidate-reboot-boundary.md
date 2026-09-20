# Previous candidate apply and reboot boundary

Captured 2026-09-20 21:55 UTC from the Nova's persistent journal. This was
read-only. No boot, ESP, or deployment state was changed.

## Observed sequence

The previous Linux boot was `55fdad18019d4c928ebd8a558574c1d3`. Its journal
records:

| Device time (EDT) | Record |
| --- | --- |
| 13:07:41.042 | `sudo bootc switch --from-downloaded --apply` |
| 13:07:41.255 | systemd-logind: reboot initiated by bootc |
| 13:07:45.856 | OSTree: deployment finalized |
| 13:07:46.637 | OSTree: bootconfig swap completed |
| 13:08:02.444 | `armada-bootimg-finalize`: wrote `/boot/efi/KERNEL` for `vmlinuz-7.2.3` |
| 13:08:02.649 | `armada-bootimg-sync`: `/KERNEL already current (vmlinuz-7.2.3)` |
| 13:08:02.703 | last journal entry for the old boot |

The Armada boot-image finalizer runs after OSTree finalizes the next-boot BLS
entry and asks `armada-bootimg-update` to assemble its kernel, initramfs, and
DTBs. The source path is
[`armada-bootimg-finalize`](../../../system_files/usr/libexec/armada/armada-bootimg-finalize)
and the update logic selects the default next-boot BLS entry in
[`armada-bootimg-update`](../../../system_files/usr/libexec/armada/armada-bootimg-update).

## What this establishes

- The apply command triggered an orderly system shutdown.
- OSTree finalized a staged deployment and changed its boot configuration.
- Armada regenerated the ABL `/KERNEL` image immediately before restart.
- The log records only the common `vmlinuz-7.2.3` version string. It does not
  contain the KERNEL, initramfs, or DTB digest, so it cannot prove which exact
  bytes ABL subsequently loaded.
- `journalctl --list-boots` lists previous Linux ID
  `55fdad18019d4c928ebd8a558574c1d3` and current stock Linux ID
  `aa40c55ed55846a9a7103a7d926b9e9e`. There is no separate persistent Linux
  root journal for the candidate between them.

This narrows the missing-SSH interval to after the old system's clean reboot
sequence, but it does not show whether the candidate kernel started, whether
initrd systemd reached its recovery timer, or why Wi-Fi/SSH did not return.
The identical “Preparing Armada” splash can be emitted from initrd or real
root, so it does not locate the stall. Early ABL/manual recovery remains
necessary before repeating a candidate boot that could fail before the timer.

The current device remains on the stock beta digest
`sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88`,
with no staged deployment.

## Pstore check

At 21:58 UTC, root-readable `/sys/fs/pstore` was empty. The running kernel
reports `CONFIG_PSTORE=y` and `CONFIG_PSTORE_RAM=m`, but `/sys/module/ramoops`
and `/dev/pmsg0` are absent. A read-only search of the live
`/sys/firmware/devicetree/base/reserved-memory` compatible properties found no
`ramoops` or `pstore` backend node. No prior panic/console record is available
through pstore. Do not load ramoops against a guessed physical memory region.
