# Android-side ESP rollback after the Linux boot stall

Captured 2026-09-20 18:21 UTC while the Nova was running Android 13. The user
reported that the preceding Linux boot stopped at “Preparing Armada.” Android
was selected through ABL and was reachable through authenticated wireless ADB.

## Android access

- ADB serial: `192.168.0.163:45935`; product/device `kalama`, model
  `Retroid_Pocket_Nova`, slot `_a`.
- Build fingerprint:
  `qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys`.
- `su -c id` returned UID 0 in Magisk's SELinux domain.
- Wireless debugging was enabled. I reasserted Android's native settings with
  `settings put global adb_wifi_enabled 1` and
  `setprop persist.adb.tls_server.enable 1`; readback was `1` for both.
  `service.adb.tls.port` was `45935`, while `persist.adb.tcp.port` was empty.
  No unauthenticated TCP ADB mode was enabled. Cross-reboot persistence has
  not yet been tested, and no Magisk boot script was installed.

## ESP identity and preservation

Read-only `blkid` identified `/dev/block/sda18` (`ARMADA`, vfat) as the ABL
ESP. `/dev/block/sda19` is the ext4 `ARMADA_BOOT` partition; `/dev/block/sda20`
is the Btrfs `ARMADA_ROOT` partition. Android's kernel does not list Btrfs as
supported, so no attempt was made to mount or change the root partition.

Before writing, the read-only ESP hashes were:

| File | SHA-256 |
| --- | --- |
| Candidate `KERNEL` | `ef8aa073ebafdbc54ba0281728ff5c87cd5fa03d9af2edd06a4c08f19be4a4f1` |
| Stock `KERNEL.BAK` | `0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000` |

Both were copied off-device and verified. Candidate image:
`/Volumes/NovaKernelBuild/backups/nova-esp-20260920T1634Z/KERNEL-candidate.abl`.
Stock image:
`/Volumes/NovaKernelBuild/backups/nova-esp-20260920T1634Z/KERNEL-stock-from-device.abl`.

## Rollback performed

After confirming the two pre-write hashes, I remounted only the ESP read-write,
copied `KERNEL.BAK` to `KERNEL.TMP`, synced, and renamed the temporary file
over `KERNEL`. I did not change `KERNEL.BAK`, the BLS entries, or either
`.armada-bootimg.*.id` stamp. A fresh read-only remount verified:

| File | SHA-256 after rollback |
| --- | --- |
| `KERNEL` | `0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000` |
| `KERNEL.BAK` | `0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000` |

The restored image is byte-identical to the preserved pre-test stock image.
The candidate remains available off-device. The boot-image ID stamp still
reflects the candidate's BLS content; this was left untouched deliberately.
The boot-image updater trusts that stamp, so inspect its behavior after Linux
starts before making any further ESP or bootc changes.

## Linux after the restart

At 18:36 UTC, `adb reboot` had completed and SSH to `armada` was back. The new
boot ID is `aa40c55e-d558-46a9-a710-3a7d926b9e9e`; Linux reports Fedora 44,
kernel `7.2.3`, and cmdline `ostree=/ostree/boot.0/default/fe4d16bd4878cae9447e4453800c638fd8db80d199c88204f22f99837008da9a/0`, matching the old base rather than the candidate checksum.

`bootc status --json` reports the stock Armada beta image booted at digest
`sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88`.
The candidate `localhost/armada-pcie-opp-test:20260920-01` remains in the
`rollback` slot at digest
`sha256:d7eb055720a28bddc8f6a3e7267d6e56c54c53de719963ed06c1228f851e101b`;
`staged` is null, `spec.bootOrder` is `rollback`, and `rollbackQueued` is
`true`. The live `bootc rollback --help` says the deployment in the rollback
slot is queued for the next boot. No `bootc rollback` command appears in the
sudo audit; the only recorded operation was the earlier
`bootc switch --from-downloaded --apply`. Do not infer the next boot target or
reboot again until this queue is understood.

Systemd reports `running` with no failed units, Wi-Fi is connected, and the
Gamescope Steam session is active. Steam's local CEF target list includes
`Steam Big Picture Mode`, `MainMenu_uid2`, and `QuickAccess_uid2`. This shows
the Steam UI is running, though the physical panel was not captured.

The current-boot `armada-bootimg-sync` log says it saved a known-good
`KERNEL.BAK` and then reported `/KERNEL already current (vmlinuz-7.2.3)`.
The updater source compares the boot-image ID stamp with the selected BLS
entry, not the bytes of `/KERNEL`; the restored stock bytes still have the
candidate stamp. The pre-reboot hashes are verified, and the running cmdline
confirms the stock boot image was used, but post-boot ESP hashes could not be
read as the unprivileged SSH user. No stamp, BLS entry, or bootc state was
changed after boot.

The PCIe-MEM OPP suspend A/B remains unrun. Keep the working stock boot active
while determining how to clear or safely control the queued candidate and
reconcile the stale image stamp. Do not reboot or start a suspend test yet.

## Queue cleared and stock boot image normalized

At 18:44 UTC, `rpm-ostree cleanup --rollback` returned `Deployments unchanged`.
`ostree admin status` showed why: the candidate was the pending deployment,
not a conventional rollback deployment. The candidate image was still present
in rootful Podman's local store at digest
`sha256:d7eb055720a28bddc8f6a3e7267d6e56c54c53de719963ed06c1228f851e101b`.

I then ran `rpm-ostree cleanup --pending`. It removed exactly one pending
deployment, reported a deployment-count change of `-1`, and freed 64.1 MiB.
The candidate OCI image/tag remains in Podman's local store and can be staged
again without rebuilding. `bootc status --json` now reports the stock beta
image booted, `rollback=null`, `rollbackQueued=false`, `staged=null`, and
`bootOrder=default`. OSTree lists only the booted stock deployment; the BLS
directory contains only its version-1 entry.

With the BLS state back to stock, I ran Armada's own
`/usr/libexec/armada/armada-bootimg-update`. It wrote `/boot/efi/KERNEL` for
`vmlinuz-7.2.3` without rebooting or changing `KERNEL.BAK`. Root-level hashes
of both files are again
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`. The
active image stamp is now the stock ID
`d7755f13ac5a1224fef222e2d104192045fd01d61924f9b1ae31e941b73f049b`; the
previous-image stamp records candidate ID
`2fde9022665b5aef44d538eb1d4930548627519b16d1a6fe49ca033d3c2a91fe`.

The current boot remains healthy: systemd is `running`, there are no failed
units, the Steam user session is active, and Steam CEF lists Big Picture, Main
Menu, and Quick Access. No further reboot or suspend test was run. The earlier
candidate boot did not return SSH and the user saw “Preparing Armada”; the
precise point of failure remains unknown. The PCIe-MEM OPP suspend A/B has not
run.

Before leaving Android, Wireless debugging was reasserted through the native
global setting and persistent TLS-server property. It was enabled over
authenticated TLS, with legacy TCP ADB unset. Because the immediate restart
went to Linux, persistence after a subsequent Android boot remains unverified.

## Wireless ADB follow-up from Linux

At 18:52 UTC, Linux remained reachable over SSH. `adb devices -l` was empty;
an explicit reconnect to the last Android TLS endpoint
`192.168.0.163:45935` timed out. The Linux system has no `adbd` process or
listener on the checked ADB ports. `lsblk` identifies Android `userdata` as
`/dev/sda17`; it is not mounted and Linux reports no filesystem type. No
offline mount or modification was attempted.

The native Android wireless-debugging setting and TLS-server property were
reasserted before the Android-to-Linux restart, with legacy TCP ADB unset. The
reboot persistence remains unverified. When Android is reachable again, use a
Magisk late-start service to reassert the native controls and confirm TLS ADB;
do not enable the legacy TCP ADB port. The device was not rebooted during this
follow-up.
