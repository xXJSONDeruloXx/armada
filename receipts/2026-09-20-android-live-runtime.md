# Live Android runtime capture

Captured 2026-09-20 06:27 UTC over the Wireless debugging TLS endpoint after
the user enabled Wireless debugging. The endpoint is ephemeral; the prior
Wi-Fi ADB port 5555 is not listening.

## Build and access

- ADB identifies `product=kalama`, `model=Retroid_Pocket_Nova`, `device=kalama`.
- Fingerprint: `qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys`.
- Kernel: `5.15.123-android13-8-g697b78910a71-dirty`, AArch64; active slot `_a`.
- `su -c id` returns uid 0, context `u:r:magisk:s0`.
- Loaded modules include `kiwi_v2`, `cnss2`, `pci_msm_drv`, `rpmh_regulator`,
  `icc_rpmh`, and `icc_bcm_voter`.

## Merged runtime device tree

- Model string: `Qualcomm Technologies, Inc. KalamaP HDK`.
- Runtime `qcom,msm-id` bytes decode to `<0x25b 0x200>` and `qcom,board-id`
  to `<0x1001f 0>`, matching the public Nova/KalamaP DTBO candidate previously
  identified as entry 51.
- Active WCN host is `soc/qcom,pcie@1c00000`: boot log reports the `pci-msm`
  host at `1c00000`, and PCI `0000:01:00.0` is beneath that root.
- The active pcie0 node has `qcom,drv-name = "lpass"`. It has no
  `qcom,drv-supported`, `qcom,apss-based-l1ss-sleep`,
  `qcom,no-client-based-bw-voting`, or `qcom,pcie-switch-type` property.
- `soc/qcom,pcie@1c08000` has `status = "disabled"`; it contains
  `qcom,apss-based-l1ss-sleep` and `qcom,no-client-based-bw-voting`.
- Exact installed `cnss2.ko` reconstruction says CNSS falls back from missing
  `qcom,drv-supported` to `qcom,drv-name`. Thus pcie0's `lpass` name makes
  DRV support likely; the disable-DRV quirk and live `drv_connected` value
  remain unknown. The APSS/L1SS noirq property shown in the merged tree is on
  disabled pcie1, not the active WCN host.

## Suspend evidence in this boot

`/sys/power/mem_sleep` is `[s2idle] deep`. Kernel log shows one attempt:

```text
[ 579.145811] PM: suspend entry (s2idle)
[ 579.351854] kiwi_v2: __wlan_hdd_bus_suspend: bus suspend succeeded
[ 579.380232] Wakeup pending, aborting suspend
[ 579.380255] active wakeup source: NETLINK
[ 579.380273] PM: Pending Wakeup Sources: NETLINK
[ 579.380369] PM: Some devices failed to suspend, or early wake event detected
[ 579.437760] PM: suspend exit
```

The complete read-only `suspend_stats` counters are success 0, fail 1,
failed_freeze 0, failed_prepare 0, failed_suspend 1, failed_suspend_late 0,
and failed_suspend_noirq 0. `qcom_sleep_stats/{apss,aosd,cxsd,ddr}` each report
all-zero records. This boot has no successful suspend counter yet. The log
proves a NETLINK wakeup abort and WLAN bus-suspend callback success; it does
not identify whether the PCIe noirq callback ran or which CNSS host mode was
selected. The abort followed Android's `adbd`/`mdnsd` startup by seconds, but
that timing is correlation only.

No kernel/module, PCI configuration, regulator, interconnect request,
device-tree, power policy, or sleep control was changed by this capture.

## Follow-up at 06:34 UTC

A direct `rtcwake -u -m mem -s 15 -d /dev/rtc0` call returned
`xwrite: Device or resource busy`. It left `/sys/class/rtc/rtc0/wakealarm`
set to `153393`; I cleared it using a confirmed Magisk-root command and
verified the sysfs alarm was empty and `/proc/driver/rtc` reported
`alarm_IRQ: no` and `alrm_pending: no`.

After the call, `dmesg` showed a second short `PM: suspend entry (s2idle)` /
exit interval (about 38 ms); suspend statistics changed from success 0 / fail
1 to success 0 / fail 2 (`failed_suspend=1`, late/noirq failures zero). The
event occurred while the RTC alarm was armed, but its cause cannot be
attributed to the direct `rtcwake` call. AOSD/CXSD/DDR/APSS remained zero.

Correction from the earlier lab record: direct `rtcwake -m mem` is already
known to conflict with Android `system_suspend`, which owns the
`wakeup_count`/`state` protocol. I repeated that known-failing route before
noticing the 2026-09-19 01:21 entry; do not repeat it. The documented bounded
route is Android `suspend_control_internal` transaction 2 (`forceSuspend()`),
with the previously proven short RTC wake and temporary `mem_sleep` selection.

Also, `adb shell su -c 'multi word command'` did not preserve quoting across
the ADB shell boundary for several earlier reads (kernel audit entries show
some `cat` commands ran as `u:r:shell:s0`). Those files were readable and the
device was separately verified as Magisk root, but future privileged commands
must use `adb shell "su -c '...'"`. The RTC cleanup used and verified this
correct form.

## Follow-up at 06:39 UTC

While probing service availability, I inadvertently invoked
`service call suspend_control_internal 2` before arming a recovery alarm. It
returned `Result: Parcel(...00000000...)` (`false`). The boot ID remained
`d927cfaa-54f1-428d-9f3b-1298aa1982fc`, `mem_sleep` remained
`[s2idle] deep`, the RTC wakealarm remained empty, and AOSD/CXSD/DDR/APSS
remained zero. `suspend_stats` rose to success 0 / fail 3; a later dmesg
interval at uptime 1520.553879–1520.638005 shows an 84 ms s2idle entry/exit.
The service's read-only `--suspend_controls` snapshot reports one failed
attempt and zero total suspend time; the `--wakeups` snapshot lists one
NETLINK abort. I cannot attribute the 84 ms attempt to the service call.

The correct next capture is already validated in notebook entries
2026-09-19 15:06 and 15:09 UTC: use the downstream read-only
`/sys/kernel/debug/interconnect/debug_suspend` hook, temporarily select
`deep`, arm `rtc0/wakealarm` for `+8`, then invoke
`service call suspend_control_internal 2`. Restore the original
`mem_sleep`, hook value `0`, and empty wakealarm after resume. Do not probe
this service with a call before arming the alarm.
