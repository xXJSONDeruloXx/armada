# Android deep suspend follow-up

Captured approximately 2026-09-20 06:47 UTC over Android Wireless debugging.
The test used the existing Android suspend service, the read-only ICC
`debug_suspend` hook, and an RTC wake alarm. No kernel, module, PCI state,
regulator, interconnect request, boot image, or persistent sleep policy was
changed.

## Identity and preflight

- Device: Retroid Pocket Nova (`product=kalama`, `device=kalama`), rooted Android.
- Kernel/build: `5.15.123-android13-8-g697b78910a71-dirty`, fingerprint
  `qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys`.
- Boot ID before and after: `d927cfaa-54f1-428d-9f3b-1298aa1982fc`.
- Preflight: `mem_sleep=[s2idle] deep`, `debug_suspend=0`, RTC wakealarm empty,
  RTC `alarm_IRQ=no`; `suspend_stats` success 0 / fail 3.
- APSS, AOSD, CXSD, and DDR records all had count and accumulated duration 0.

## Bounded run

With verified root-shell quoting (`adb shell "su -c '...'"`), the temporary
sequence was:

1. Set `/sys/kernel/debug/interconnect/debug_suspend` to `1` and verify it.
2. Select `deep` in `/sys/power/mem_sleep` and verify `s2idle [deep]`.
3. Arm `rtc0` with `rtcwake -u -m no -s 8 -d /dev/rtc0`; the alarm file was
   nonempty and `/proc/driver/rtc` reported `alarm_IRQ=yes`.
4. Call `service call suspend_control_internal 2`; it returned `true`.
5. Read the kernel log, sleep records, suspend stats, and Wi-Fi state.
6. Restore `mem_sleep` to `[s2idle] deep`, `debug_suspend=0`, and clear the
   wakealarm.

## Results

The kernel logged `PM: suspend entry (deep)`, then the WLAN bus-suspend
callback succeeded. The wake IRQ was `pm8xxx_rtc_alarm`; the kernel logged
`PM: suspend exit`. `suspend_stats` changed to success 1 / fail 3, with
`failed_suspend=1` and `failed_suspend_noirq=0`.

The firmware-backed Android sleep-stat records, which were all zero directly
before this run, then reported:

| Record | Count | Last entered | Last exited | Accumulated duration (raw) |
|---|---:|---:|---:|---:|
| APSS | 1 | 39210381954 | 39329667858 | 119285904 |
| AOSD | 165 | 39328957040 | 39329668432 | 111831600 |
| CXSD | 17 | 39328952352 | 39329671960 | 112746986 |
| DDR | 17 | 39328948799 | 39329686864 | 113022361 |

This establishes that this successful Android `deep` suspend advanced AOSD,
CXSD, and DDR records on the same Nova where Armada's corresponding records
remain zero. These are raw driver-reported values; this receipt does not
interpret the duration units as wall-clock suspend time.

At the suspend boundary the downstream ICC hook printed only these enabled
clients:

- `soc:qcom,dcvs:ddr:sp`, tag `3`: average `1593832`, peak `2188000` on
  `llcc_mc` and `ebi`.
- `soc:qcom,dcvs:llcc:sp`, tag `3`: average `2589968`, peak `4800000` on
  `chm_apps` and `qns_llcc`.

There was no PCIe client in this printed request list. Android's tag definition
identifies tag `3` as ACTIVE_ONLY (AMC + WAKE), excluding SLEEP. This is a
suspend-boundary client snapshot, not proof of the final firmware TCS contents
or that AOP accepted each request. It also does not identify which PCIe
host/client suspend branch ran.

The run's Wi-Fi interface returned `UP/LOWER_UP`, Android reported Wi-Fi
connected, and Wireless ADB remained available. After restoration,
`mem_sleep=[s2idle] deep`, `debug_suspend=0`, wakealarm empty, and RTC
`alarm_IRQ=no`; the boot ID was unchanged.

## Interpretation and remaining gap

This confirms Android's bounded `forceSuspend()` route can complete `deep`
and produce nonzero APSS/AOSD/CXSD/DDR counters with Wi-Fi configured and
connected. The captured ICC list is consistent with Android clearing the
PCIe request before the suspend boundary, but it does not distinguish the
connected-DRV path, the root-device late fixup, or the APSS/L1SS host path.
It does not prove that the differing PCIe request alone causes the Armada
residency difference. The next useful device work is to find a read-only,
runtime-safe way to identify the exact CNSS/PCIe branch and suspend-time PCI
state; do not repeat this identical run or deploy a behavior change on this
evidence alone.
