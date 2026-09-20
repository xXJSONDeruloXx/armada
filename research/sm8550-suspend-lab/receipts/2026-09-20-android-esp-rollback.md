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

## Next action

The ESP rollback is complete; Android has not yet been rebooted. The user said
an Android restart should choose Linux by default. Reboot once, then verify
Linux boot ID, kernel and Armada version, bootc booted/staged/rollback state,
Wi-Fi/SSH, ESP image hashes, and whether the system reaches the UI. Do not
repeat the suspend test until the device is healthy and the running deployment
is known.
