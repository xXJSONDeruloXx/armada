# Android PCIe suspend branch and RPMh TCS capture

Captured on the rooted Nova's Android boot on 2026-09-20. This was a second,
instrumented bounded `deep` suspend, using the existing Android
`suspend_control_internal` path and a verified `rtc0` wake alarm. It did not
change kernel/module binaries, PCI state, regulator requests, ICC votes, or
persistent power policy.

The full ftrace instance output is preserved in
[`2026-09-20-android-pcie-branch-trace.txt`](2026-09-20-android-pcie-branch-trace.txt).
It contains the trace stream only. The trace header reports 5,790 events
written and buffered, with no lost events indicated.

## Instrumentation and run result

The running kernel has `CONFIG_KPROBE_EVENTS=y` and exports the exact loaded
CNSS/PCIe symbols in kallsyms; `CONFIG_FUNCTION_TRACER` is disabled. A new
tracefs instance was used, leaving global `tracing_on=0`. Temporary kprobes
recorded CNSS suspend entry/return, PCIe PM-control mode, DRV/noirq/clock
paths, and the PCIe ICC helper arguments. RPMh tracepoints recorded Apps-RSC
TCS writes and suspend phases.

The `adb shell` command lost its transport while the Nova suspended and
returned exit 255 without the Binder parcel result. Wireless ADB returned on
the same TLS endpoint after the RTC wake. The kernel confirms this was a
successful run: `PM: suspend entry (deep)`, `pm8xxx_rtc_alarm` wake,
`PM: suspend exit`, and `suspend_stats` success increased from 1 to 2 while
fail remained 3. Wi-Fi reconnected.

The exact system-suspend callback sequence at trace time ~2955.7 s was:

| Trace event | Observation |
|---|---|
| `cnss_pci_suspend` | Entered; return code 0 |
| `cnss_pci_suspend_bus` | Entered; return code 0 |
| `cnss_set_pci_link` → `msm_pcie_pm_control` | Mode 0 |
| `msm_pcie_drv_suspend` | Entered |
| `qcom_pcie_icc_bw_update` | `avg=0`, `peak=0` |
| `msm_pcie_pm_suspend_noirq` | Callback entry observed later in noirq |
| `msm_pcie_pm_suspend` / `msm_pcie_clk_deinit` | No hits in the captured run |

The subsequent `cnss_set_pci_link` resume used PM-control mode 2 and restored
the nonzero helper request. The active runtime pcie0 DT has no
`qcom,pcie-switch-type`; the installed CNSS binary defaults that property to
0 and chooses mode 0 when `drv_connected_last` is true (or switch type is 1).
Together with entry into `msm_pcie_drv_suspend`, this identifies the
connected-DRV suspend path. It does not directly read the private
`drv_connected_last` byte.

In this exact CNSS branch the installed binary skips the explicit
`pci_disable_device()` / `pci_set_power_state(..., D3hot)` calls. No probe of
the endpoint's PCI config state was installed, so this result does not claim
the endpoint's physical PCI state. The host noirq callback entry is not proof
that its APSS/L1SS route ran; the active pcie0 node lacks the property that
selects that route. The no-hits for `msm_pcie_pm_suspend()` and
`msm_pcie_clk_deinit()` are consistent with the root-device late-fixup path
not running after CNSS moved the link to DRV state.

## Apps-RSC SLEEP and WAKE commands

The runtime mapping recorded in
[`2026-09-19-android-deep-rpmh/tcs-sequence.txt`](2026-09-19-android-deep-rpmh/tcs-sequence.txt)
places Apps-RSC global TCS 3 at SLEEP and TCS 5 at WAKE. The current run
staged 14 commands in each TCS immediately before `machine_suspend`:

| n | Resource | CMD-DB address | TCS 3 SLEEP data | TCS 5 WAKE data |
|---:|---|---:|---:|---:|
| 0 | MC0 | `0x50000` | `0x40000000` | `0x60238823` |
| 1 | SH0 | `0x50004` | `0x00000000` | `0x208251db` |
| 2 | SH1 | `0x50008` | `0x40000000` | `0x60000001` |
| 3 | SN0 | `0x50010` | `0x40000000` | `0x60004001` |
| 4 | CN0 | `0x50038` | `0x40000000` | `0x60004001` |
| 5 | QUP1 | `0x50048` | `0x00000000` | `0x20004001` |
| 6 | QUP2 | `0x5004c` | `0x00000000` | `0x20004001` |
| 7 | QUP0 | `0x50044` | `0x40000000` | `0x60004001` |
| 8 | ACV | `0x50068` | `0x40000000` | `0x60000008` |
| 9 | LDOE1 + `0x08` | `0x43908` | `0x00000004` | `0x00000007` |
| 10 | LDOE1 + `0x04` | `0x43904` | `0x00000000` | `0x00000001` |
| 11 | LDOE3 + `0x04` | `0x43a04` | `0x00000000` | `0x00000001` |
| 12 | MC4 | `0x50060` | `0x60000000` | `0x60000001` |
| 13 | SH5 | `0x50064` | `0x60000000` | `0x60000001` |

The RPMh `complete` flags for all TCS 3 SLEEP commands were 0. The TCS 5
WAKE flags, in command order, were `1,0,1,1,1,0,0,1,1,0,0,0,0,0`. Those
flags describe completion handling, not AOP acceptance. The trace proves the
kernel staged these command words; the independently advanced sleep records
show firmware-recorded residency during this run.

The two memory resources that carried Armada's nonzero SLEEP floor, MC0 and
SH0, are zero/off in this Android SLEEP TCS. This is directly adjacent to the
observed successful connected-DRV callback clearing the PCIe ICC request to
`0/0`. It is a strong runtime correlation and a concrete path difference; it
does not isolate ICC clearing as the sole cause because Android also stages
LDOE sleep requests and a larger SLEEP command set.

## Sleep-record delta and cleanup

Immediately before this run, after the prior successful Android sample, the
records were APSS `Count=1` / accumulated `119285904`, AOSD `165` /
`111831600`, CXSD `17` / `112746986`, and DDR `17` / `113022361`. Afterward:

| Record | Count | Accumulated duration (raw) | Delta in count | Delta in raw duration |
|---|---:|---:|---:|---:|
| APSS | 2 | `947370080` | +1 | +`828084176` |
| AOSD | 386 | `918190480` | +221 | +`806358880` |
| CXSD | 85 | `920716754` | +68 | +`807969768` |
| DDR | 85 | `922096679` | +68 | +`809074318` |

The raw duration deltas are not interpreted as elapsed wall time here.

After collecting the trace, the temporary instance and all kprobe events were
removed. Verification showed `kprobe_events` empty, no trace instances,
global tracing off, `mem_sleep=[s2idle] deep`, `debug_suspend=0`, wakealarm
empty, RTC `alarm_IRQ=no`, and the same boot ID. No permanent device state
changed.

## Consequence for the Linux comparison

Android's successful path does not depend on the normal root-fixup clock
deinit route or an explicit endpoint D3hot transition. CNSS invokes the
vendor-specific DRV suspend API, which clears the PCIe ICC vote. Linux's
observed path is different: the DesignWare/QCOM host's D3cold eligibility is
vetoed by the root port's `PCI_UNKNOWN` state, leaving the host active and its
SLEEP-tagged PCIe memory request contributing to MC0/SH0. The capture makes a
targeted test of the PCIe request's SLEEP contribution plausible, but source
review must first confirm the supported ICC tagging API and wake-safety
semantics. Do not force D3hot or bypass the generic D3cold check.
