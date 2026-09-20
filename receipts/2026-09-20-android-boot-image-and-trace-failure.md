# Android boot image and RPMh trace attempt

Captured 2026-09-20 over Wireless ADB on the rooted Nova. Device-side module,
partition, and runtime inspection was read-only except for one temporary
tracefs instance, a short-lived `mem_sleep=deep` selection, and an RTC wake
alarm. No Android image, module, interconnect vote, PCI state, or persistent
sleep policy was changed.

## Active Android boot image

The active slot was `_a`; Wireless ADB reported:

```text
fingerprint: qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys
kernel:      5.15.123-android13-8-g697b78910a71-dirty
```

I copied `/dev/block/by-name/boot_a` to external scratch without writing to
the device. The partition image is 100,663,296 bytes, SHA-256
`3e143173f3112984b012f4bf69f9d5172ffdc913550723e3056ffc9de367d26c`. AOSP's
`unpack_bootimg.py` identifies an Android boot-image v4 header, OS 13.0.0,
patch level 2024-01, 56,048,128-byte kernel payload, and 360,843-byte ramdisk.
The extracted kernel SHA-256 is
`700138039d1116b0fd4724414113285738da4cecfc17b97e893194ff14a1ae41`.
Image and extracted files remain outside Git at
`/Volumes/NovaKernelBuild/android-binaries/` and `/tmp/nova-boot-a-unpacked/`.

Printable kernel strings include build paths such as
`/home/liuwen/q9ex/VENDOR.13.2.6/kernel_platform/common/drivers/interconnect/core.c`
and `.../drivers/soc/qcom/...`. This identifies the vendor build-tree label,
not its exact source revision. Searching that label and the reported
`g697b78910a71` suffix did not locate a matching public kernel source tree.

The exact `vendor_boot` RPMh/ICC modules and the mounted 120 MiB
`/vendor_dlkm/lib/modules` tree were searched for printable `MC4`, `SH5`,
`bcm_mc4`, and `bcm_sh5` names; no matching module file was found. The boot
kernel has no meaningful paired `MC4`/`SH5` printable reference. A raw byte
search found one `MC4` coincidence in a high-entropy region and no `SH5`; it
does not identify code or a table. The two little-endian address byte
sequences also do not appear in the boot kernel. These negative string scans
do not rule out generated names, indirect tables, or firmware-preloaded TCS
contents.

The live read-only `/sys/kernel/debug/cmd-db` dump reconfirmed:

```text
0x50060: MC4 [40 16 40 00 10 00 00 00]
0x50064: SH5 [40 16 40 00 40 00 01 00]
```

This validates the names and addresses, not which driver stages those TCS
commands. The existing `cmd-db` receipt has the broader resource mapping.

## Tracepoint attempt and result

The live kernel has `CONFIG_KPROBES=y`, `CONFIG_KPROBE_EVENTS=y`, and
`CONFIG_STACKTRACE=y`. Existing tracepoints expose
`interconnect_qcom:bcm_voter_commit` fields `state_name`, `addr`, `data`, and
`wait`, plus `rpmh:rpmh_send_msg` fields including controller name, TCS index,
command index, address, data, and wait flag. Global tracing was off, both
global event enables were off, and there were no existing kprobes.

The vendor tracefs rejected the event filter `addr == 327776` (decimal for
`0x50060`) with `Invalid argument`; reading back the filter showed `Error:
(0)`. I then created an isolated instance and enabled only the two events
without filters. The first unfiltered attempt stopped before arming RTC because
`/sys/power/suspend_stats` is a directory on this build; it was corrected to
`/sys/kernel/debug/suspend_stats`. Neither setup failure attempted suspend.

The corrected capture selected `deep`, verified an `rtc0` alarm at +8 seconds,
and called `service call suspend_control_internal 2`. Android returned false
(`Parcel(00000000 00000000 ...)`). `suspend_stats` changed as follows:

| Counter | Before | After |
|---|---:|---:|
| success | 3 | 3 |
| fail | 3 | 4 |
| failed_prepare | 0 | 1 |

The last failed device was `3da0000.kgsl-smmu`, errno `-115`
(`EINPROGRESS`). Kernel log:

```text
PM: suspend entry (deep)
arm-smmu 3da0000.kgsl-smmu: PM: not prepared for power transition: code -115
PM: Some devices failed to suspend, or early wake event detected
Abort: Device 3da0000.kgsl-smmu not prepared for power transition: code -115
PM: suspend exit
```

The display was ON and Android reported `mWakefulness=Awake`. The 180-event
trace therefore contains awake activity, not a completed low-power transition;
its command records cannot be used to attribute the `MC4`/`SH5` sleep entries.
The tool output was truncated and the full trace was not preserved, so this
receipt intentionally makes no event-level claim about those resources.

Cleanup was verified: boot ID unchanged; `mem_sleep` restored to
`[s2idle] deep`; RTC alarm empty and `alarm_IRQ=no`; temporary tracefs
instance removed; global `tracing_on=0`; `debug_suspend=0`; `wlan0` remained
`UP/LOWER_UP`; Wireless ADB stayed connected. No ICC votes or regulator
requests were changed.

## Screen-off retry and retained trace

After the screen was switched off, Android reported `mWakefulness=Asleep`,
but KGSL runtime status was still `active`. One more bounded request used the
same isolated, unfiltered tracepoints, a temporary `deep` selection, and an
RTC alarm. This time the command wrapper exited zero, but the Binder result
was still false. `suspend_stats` did not record a successful suspend:

| Counter | Before | After |
|---|---:|---:|
| success | 99 | 99 |
| fail | 6 | 8 |
| failed_freeze | 2 | 3 |
| failed_prepare | 1 | 1 |
| failed_suspend | 3 | 3 |

The last recorded failure was `alarmtimer.0.auto`, errno `-16`; the trace
window also contained ordinary short s2idle/freeze activity. This run did not
produce evidence of completed deep residency. The trace is retained outside
the repository at
`/Volumes/NovaKernelBuild/android-binaries/trace/rpmh-screen-off-deep-attempt.txt`,
SHA-256
`ad0e367a94a98f309b7bed8e633e3160b55d362e3f558027634dbf259242d49b` (748
lines, 107,372 bytes; 679 trace entries).

Post-processing counted 283 `bcm_voter_commit` records and 396
`rpmh_send_msg` records. The BCM commit addresses were `0x50000` (ACTIVE 48,
WAKE 94, SLEEP 94), `0x50008` (ACTIVE 41), `0x5002c` (ACTIVE 3), and
`0x5004c` (ACTIVE 3). Neither the commit records nor the send records contain
`0x50060` or `0x50064`. Since suspend did not complete and tracing started
after boot, this only says no such runtime write was observed in this awake /
aborted window; it does not rule out commands staged earlier or loaded by a
firmware path outside these tracepoints. Do not treat it as ownership evidence.

Cleanup restored `[s2idle] deep`, emptied the RTC wakealarm, removed the
temporary tracefs instance, and left global tracing off. Wireless ADB later
reconnected; I sent `KEYCODE_WAKEUP` and verified `mWakefulness=Awake`,
`mScreenState=ON`, `wlan0=up`, empty wakealarm, and `tracing_on=0`. The Android
boot ID is unchanged. No driver, module, image, bandwidth vote, regulator, or
PCI state was altered.

## Next useful diagnostic

Further retries are not useful until the Android freeze/prepare blockers are
identified; the latest trace did not enter deep. The previous screen-on run
was blocked by KGSL SMMU `-115`, while this screen-off run ended with
`alarmtimer.0.auto` `-16`. Resolve those blockers read-only before another
attempt. This is separate from the Linux-only low-bandwidth PCIe OPP A/B,
which still needs the device returned to Linux and a boot/rollback preflight.
