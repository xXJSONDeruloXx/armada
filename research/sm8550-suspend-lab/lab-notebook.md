# SM8550 suspend lab notebook

This is the running observation log for the Retroid Pocket Nova at
`192.168.0.20` (`node=fedora`, user `armada`). Every device experiment gets a
dated entry here before the next experiment starts. Raw receipts remain in the
host output directory
`/Users/danhimebauch/Developer/.external-research/armada-suspend-lab-runs/`;
the paths below are intentionally exact so an observation can be audited back
to the device archive.

## 2026-09-17 current-image refresh

The lab branch was rebased on current `upstream/main` (`b3ee817`) before these
checks. A live read-only inventory found the Retroid Pocket Nova on Armada
`20260915.feca679`, kernel `7.2.3`, with `/etc/armada/sleep.conf` selecting
`s2idle` and `/sys/power/mem_sleep` showing `[s2idle] deep`. The merged
SM8550 IRQ routing change is active (`ARMADA_IRQ_CORES=3-7`), CPU0's deep idle
state is enabled, and the USB controller is runtime-suspended. Bluetooth was
powered off at the end of the checks; the original sleep policy was preserved.

Two timer-woken current-image runs are archived under
`../sm8550-suspend-lab-runs/`:

- `20260917T192057Z-0bdd5ed7bb62` used Armada's configured `policy`, observed
  kernel mode `s2idle`, and completed with the expected RTC IRQ/source and
  unchanged boot ID. Qualcomm ADSP count advanced by 188; AOSD, CXSD, and
  scalar DDR counts stayed at zero.
- `20260917T192358Z-291ec26457c5` requested `deep`, but the kernel recorded
  `s2idle`. The test-only `deep` value was ignored when `device-env` loaded its
  defaults and parsed a mode outside its supported `fake`/`s2idle` values.
  `suspend-dispatch` also guards against unsupported modes. This archive is a
  second s2idle observation, not evidence from deep. Its RTC source
  advanced, but `pm_wakeup_irq` was unchanged. ADSP count advanced by 211;
  AOSD, CXSD, and scalar DDR counts stayed at zero.
- The second run's RPMh/AOSS trace captured RPMh messages and interconnect
  votes but no `qcom_aoss` events. Existing tracepoints therefore did not
  resolve whether firmware accepted a deeper low-power request. No reset,
  kernel change, or image deployment was made.

The old harness incorrectly called the second run successful despite the
requested/observed mode mismatch. The first correction rejected `deep` until
the separate direct-kernel test path described below was added; the runner
still requires a requested/observed mode match. Historical run archives
remain unchanged. The same run exposed a Bluetooth cleanup bug:
restoring an unblocked rfkill state powered BlueZ back on after it had been
off. The adapter was manually returned to `Powered: no`, verified live, and
the runner now checks/restores BlueZ power after rfkill cleanup. The host-only
self-test covers both cases.

### Direct kernel `deep` result, 2026-09-17

- After fixing a harness lookup for `systemd-sleep`, one 60-second direct
  kernel-mode run completed on image `20260915.feca679`, kernel `7.2.3`. The
  earlier attempt failed before suspend and cleanup restored the RTC alarm,
  trace instance, debug setting, and selected sleep mode. The successful run
  selected `/sys/power/mem_sleep=deep`, invoked
  `/usr/lib/systemd/systemd-sleep suspend` (bypassing Armada's dispatcher),
  woke from the armed RTC alarm, returned status 0, and retained the same boot
  ID. Clock deltas show 59.217 seconds of suspend separation within 61.547
  seconds of elapsed boottime.
- This establishes that the kernel's `deep`/PSCI system-suspend path can enter
  a real suspend interval and resume on this image. It does **not** establish
  that firmware entered the desired AOSD, CXSD, or DDR low-power states:
  Qualcomm APSS count advanced once and duration by 1,136,914,131 ticks, while
  the labeled AOSD, CXSD, and scalar DDR counters all remained zero. The
  separate DDR IDs remain opaque, so they do not resolve those named states.
- The gauge reported 13.1 mAh used during this 61.55-second deep interval
  (about 767 mA average), versus 9.8 mAh/about 573 mA in the adjacent
  61.83-second s2idle interval. These one-minute readings are too noisy to
  establish a real drain-rate difference or explain the reported 5%/hour.
- Sleep TCS 3 staged valid MC0/SH0 values `0x600001dc` in `deep` versus
  `0x60000001` in the prior s2idle run. These are materially different BCM
  votes, but RPMh's send trace records the non-waiting buffer writes; it does
  not show that firmware triggered or accepted the sleep set. Linux v7.2's
  [RPMh RSC implementation](https://github.com/torvalds/linux/blob/v7.2/drivers/soc/qcom/rpmh-rsc.c)
  treats these sleep/wake TCS writes as staging for firmware to trigger at the
  low-power boundary.
- The separate DDR LPM record `0xd0` kept `count=1` but its duration rose from
  `512820586959` to `514108441334` ticks (+`1287854375`) across the run. The
  scalar `/sys/kernel/debug/qcom_stats/ddr` record stayed zero. Upstream
  documents `0xd4`, `0xd3`, `0x11`, and `0xd0` only as numeric DDR LPM IDs, so
  this is evidence of a changing firmware counter, not a safe semantic label
  for a specific DDR state.
- The current image has no `rpmh:rpmh_rsc_snapshot` trace event in
  `available_events`. Its captured debugfs tree has `qcom_stats` and `cmd-db`,
  but no RSC TCS register/status dump. Therefore the existing `rsc-success`
  harness profile cannot run on this kernel and there is no useful no-build
  readback of RSC command-enable/status/response or IRQ state.
- This successful-path instrumentation was already built and exercised once
  on the previous Nova image/kernel (`7.2.0`) on September 2. Sleep/wake TCS
  records had `cmd_enable=0x3f`, `tcs_status=1`, `tcs_in_use=0`,
  `irq_status=0`, `cmd_status=0`, and zero response data, with the programmed
  commands still visible. That rules out an obvious Linux-side active-TCS or
  reported command-status failure in that run; it still cannot report whether
  AOP triggered the sleep set or selected AOSD/CXSD/DDR residency.
- A source-only compare of upstream stable `v7.2` to `v7.2.3` found no changes
  in `rpmh-rsc.c`, `rpmh.c`, `rpmh-internal.h`, `cmd-db.c`, or `qcom_stats.c`.
  The current `armada-packages` checkout uses `VERSION=7.2.3`; its active
  kernel patch series has no non-diagnostic patch changing those five files.
  A read-only scan of the current runtime device-tree firmware-name properties
  and boot kernel log also found no AOP firmware version. This makes a repeat
  diagnostic build less likely to answer the central question: it would likely
  reproduce the already-recorded TCS status, not expose AOP acceptance.
- The successful run and checksum-verified raw archive are
  `20260917T202121Z-68c0c9fe55a3` and
  `/Users/danhimebauch/Developer/.external-research/armada-suspend-lab-runs/nova-deep-20260917.tar.gz`
  (SHA-256 `0400a559e8a3d2c44e3b7d60c8a2f4528d4b961ae5d334b682d1364dfc6215b7`).
  The mode-selection change is test-harness-only; no image, sleep policy,
  kernel, or firmware was changed by this run. The selected kernel mode was
  restored to `[s2idle] deep`.

### 2026-09-17 — five-minute s2idle control and interrupted radio-off run

- `20260917T211339Z-432d8588b823` completed a full 299.657-second s2idle
  separation under Armada policy. Wi-Fi was enabled and associated; Bluetooth
  was already powered off. The battery charge counter fell by 66,902 uAh over
  the 301.9-second measurement window (gauge-derived average 798 mA, capacity
  -1%). This is a high short-window reading, not a stable hourly drain rate.
  The `battery` wakeup source's active/event counts each rose by one, as did
  RTC's. Battery `total_time` rose by 4 ms, but its `wakeup_count` stayed zero;
  kernel logs say IRQ 199 (`pm8xxx_rtc_alarm`) triggered resume, with no battery
  event in the captured logs. The brief battery-source activation is unexplained
  and was not a system wake; snapshots also bracket awake setup/cleanup. It is
  not evidence for the unusually large charge delta. Labeled AOSD, CXSD, and
  DDR counters stayed at zero; APSS count increased by two. The DDR `0xd0`
  counter changed, but its state meaning remains unknown.
- IRQ totals over the same run rose by 17,191 `arch_timer`, 9,929 `ufshcd`,
  8,775 `apps_rsc`, 668 fan, 665 display, and 629 GPU interrupts. These are
  counters across the capture interval, not proof that each IRQ resumed the
  system. Before the run, Wi-Fi PCIe `0000:01:00.0` had `power/control=on`,
  `runtime_status=active`, and zero runtime-suspended time. The radio-off
  follow-up was intended to test whether that activity mattered.
- `20260917T212320Z-8a52983d8c18` requested another 300-second s2idle window
  with Wi-Fi and Bluetooth off. The user plugged in the charger and woke the
  device early. The run observed only 69.813 seconds of suspend separation;
  qcom-battmgr USB and UCSI wakeup sources changed, and the RTC target had not
  fired. The battery counter included the charger transition, so its reported
  19,677 uAh decrease / 985 mA average is not a drain measurement and cannot
  be compared to the Wi-Fi-on run. The paired test is inconclusive.
- The second run restored Wi-Fi to enabled and cleared its RTC alarm. Bluetooth
  was off before the run and showed `Powered: no` after the harness restored
  rfkill; a later live check showed it had become powered on, so it was manually
  returned to `Powered: no`. Current post-check: Wi-Fi enabled, Bluetooth
  `Powered: no`, RTC wakealarm empty, battery charging, and kernel selection
  `[s2idle] deep`. No persistent policy, kernel, firmware, or image setting was
  changed.
- A source inspection of upstream Linux `sm8550.dtsi` confirms it provides CPU
  and cluster idle domains but no `system_pd` or `domain_ss3`. The Nova's
  `qcs8550-ayn-common.dtsi` adds regulator children under `&apps_rsc` but no
  system power-domain connection. Upstream `sm8750.dtsi` has a `system_pd`
  linked to `domain_ss3` ([SM8550 source](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/sm8550.dtsi), [SM8750 source](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/sm8750.dtsi)). This is a concrete DT-level reason Linux cannot
  request that PSCI system-domain idle state on the current SM8550 description.
  It does not prove that AOP cannot independently select deeper residency from
  RPMh sleep votes, so it is not yet a complete explanation for the zero AOSD
  counters.
- Live-kernel evidence now confirms `PSCIv1.1`, `PSCI OSI mode supported`, and
  `CPUidle PSCI: Initialized CPU PM domain topology using OSI mode`. The running
  DT has CPU and cluster PSCI domains but no `system_pd`/`domain_ss3`; this
  narrows the live s2idle path to the described CPU/cluster hierarchy, while
  leaving AOP's independent handling of RPMh sleep votes unresolved. Do not
  infer that the missing system node alone causes the observed battery drain.
- Linux genpd has a more specific read-only diagnostic than
  `pm_genpd_summary`: each domain's `idle_states` reports per-state usage and
  rejection counts, and `idle_states_desc` maps indexes to state names and
  residency definitions. A `Usage` delta indicates a successful kernel genpd
  transition, not verified physical rail collapse; `Time(ms)` is kernel
  accounting, and the `S2idle` column is not a generic count of cpuidle entries.
  Correlate any deltas with QMP AOSD/CXSD/DDR residency counters. The first
  unprivileged SSH check hit root-only `/sys/kernel/debug` (`0700`), so its
  `test -d /sys/kernel/debug/pm_genpd` result was inconclusive, not evidence
  those files are missing. Follow-up confirmed debugfs is already mounted
  `rw`; the installed suspend-lab helper has a scoped passwordless-sudo rule.
  The helper now stores read-only pre/post snapshots of these files; no mount
  or power controls were changed. Linux v7.2 sources:
  [genpd idle-state files](https://raw.githubusercontent.com/torvalds/linux/v7.2/drivers/pmdomain/core.c#L3707-L3905),
  [PSCI OSI-domain construction](https://raw.githubusercontent.com/torvalds/linux/v7.2/drivers/cpuidle/cpuidle-psci-domain.c#L641-L834).
- The existing `rpmh-aoss` trace profile also attempts optional
  `power:psci_domain_idle_enter/exit` events. Linux v7.2 records CPU ID, the
  exact PSCI `state` value, and whether it is s2idle; the enter event is just
  before `psci_cpu_suspend_enter(state)` and exit is emitted after it returns.
  This identifies the requested PSCI parameter and can be correlated with
  genpd rejection counts, but does not by itself prove physical firmware
  residency:
  [power tracepoint definition](https://raw.githubusercontent.com/torvalds/linux/v7.2/include/trace/events/power.h#L61-L96),
  [PSCI suspend call site](https://raw.githubusercontent.com/torvalds/linux/v7.2/drivers/cpuidle/cpuidle-psci.c#L59-L99).
- `20260917T235546Z-abddde5f1710` completed 44.048 seconds of unplugged
  s2idle with the `rpmh-aoss` profile. The trace instance exposed and selected
  both PSCI events; all eight CPUs emitted one `is_s2idle=yes` enter/exit pair.
  Seven CPUs passed `0x40000004`; cpu4 passed `0x4100c344`, matching the
  upstream SM8550 `cluster-sleep-1` parameter and the one
  `power-domain-cluster` S1 Usage increment (132 to 133; Rejected stayed 271).
  Its runtime descriptor's 7,200 us latency and 10,150 us residency match the
  DTS entry/exit and minimum-residency values.
  The cpu4 trace call remained inside PSCI across the 44-second suspend and
  returned at the RTC wake, so Linux did not see an immediate PSCI rejection
  of that cluster request. No `0x41000044` request appeared in this sample.
  These values establish which CPU/cluster states Linux submitted, not why the
  SoC did not record deeper named states. The same run had zero AOSD, CXSD, and
  scalar DDR deltas, ADSP +185, 1,248 RPMh sends and 605 completions, but no
  `qcom_aoss:aoss_send` events. Every trace CPU reported zero dropped events.
  Upstream mapping:
  [SM8550 DTS cluster states](https://github.com/torvalds/linux/blob/v7.2/arch/arm64/boot/dts/qcom/sm8550.dtsi).
  Charge_now fell 5,248 uAh over 46.513 seconds (406 mA derived average), with
  capacity unchanged; this short-window reading remains too noisy for an
  hourly drain estimate. Exact archive:
  `../sm8550-suspend-lab-runs/20260917T235546Z-abddde5f1710`.
- Follow-up source review confirms that `0x4100c344` is Qualcomm's SM8550
  cluster E3 `llcc-off` state, not a system-level sleep state. Qualcomm's
  downstream Kalama DTS labels `0x41000044` as cluster D4 `l3-off` and gives
  E3 the same 2.8 ms entry, 4.4 ms exit, and 10.15 ms minimum-residency values
  observed in the live genpd descriptor. The public SM8550/QCS8550 hierarchies
  reviewed contain CPU and cluster domains but no `system_pd`/SS3 mapping.
  Sources: [Qualcomm Kalama DTS](https://android.googlesource.com/kernel/msm-extra/devicetree/+/refs/heads/android-msm-eos-android13-wear-kr3-pixel-watch/qcom/kalama.dtsi#L283-L333),
  [SM8550 DTS](https://github.com/torvalds/linux/blob/v7.2/arch/arm64/boot/dts/qcom/sm8550.dtsi#L341-L384),
  [PSCI domain topology](https://android.googlesource.com/kernel/msm-extra/devicetree/+/refs/heads/android-msm-eos-android13-wear-kr3-pixel-watch/qcom/kalama.dtsi#L713-L760).
  PSCI's lower state-ID bits are platform-defined, so this mapping comes from
  the SoC DT description rather than a generic PSCI level encoded in the hex
  value. Linux's trace shows a request and return across RTC wake, not a
  firmware residency confirmation; the unchanged genpd rejection count also
  cannot prove physical rail collapse.
- Do not copy SM8750's `domain_ss3` value `0x0200c354` to SM8550 by analogy.
  No exact-SoC public source found here validates it. Review of the analogous
  X1E80100 change notes that its timings were copied from SM8750 and tuned for
  a phone; a separate Glymur/X2 report describes hard resets on first SS3 entry
  after heavy load. These are different SoCs, but demonstrate that the tuple
  is not portable evidence. Sources: [X1E80100 review](https://lkml.rescloud.iu.edu/hypermail/linux/kernel/2510.1/04745.html),
  [Glymur SS3 failure report](https://lists.openwall.net/linux-kernel/2026/09/14/1222),
  [SM8750 DTS](https://github.com/torvalds/linux/blob/v7.2/arch/arm64/boot/dts/qcom/sm8750.dtsi#L2535-L2545).
  Current evidence supports a missing public system-state mapping as a
  hypothesis for the absent named system residency, not yet a proven cause of
  the measured drain.
- The read-only pre-suspend snapshots also identify the radio topology for
  the matched radio test: Bluetooth `hci0` is attached through the
  `898000.serial` GENI UART (`/sys/class/rfkill/rfkill0`, `RFKILL_STATE=1`),
  while Wi-Fi is the `wcn7850` PCIe device at `1c00000.pcie`. Thus the paired
  run can power off the Bluetooth HCI while preserving Wi-Fi, separating it
  from the already-tested Wi-Fi variable. Source is the captured
  `runtime_pm.json` and sysfs uevent in run
  `20260917T235546Z-abddde5f1710`. In that capture, `hci0` and `rfkill0` both
  report runtime PM as `unsupported`; those snapshots cannot tell us whether
  the UART/controller enters a hardware low-power state while Bluetooth stays
  powered, which is one reason the controlled rfkill-off comparison is useful.
- `20260918T000616Z-9d84ab5a1824` is the first five-minute Bluetooth-on,
  Wi-Fi-preserved s2idle run. Clock separation showed 298.385 seconds in
  s2idle; the charge-counter measurement interval was 301.016 seconds. The
  device retained its boot ID, returned on the RTC, and reported USB unplugged.
  Bluetooth was preserved powered on. `charge_now` fell 32,795 uAh (392.2 mA
  derived average); integer capacity did not change. This first on-run was
  about 1.8–2.0x the earlier five-minute Bluetooth-off runs, but that charge
  difference did not reproduce in the reverse-order repeat below. The
  `battery` wakeup source advanced once and
  the RTC IRQ remained the observed wake source; that battery event is not
  evidence that it woke the system. The `qcom_geni_serial_uart1` IRQ advanced
  by eight, but it advanced by 14 and 15 in the earlier Bluetooth-off runs, so
  it is not discriminating evidence for Bluetooth activity. AOSD, CXSD, and
  scalar DDR residency again remained zero, as in the Bluetooth-off controls;
  the charge-counter evidence alone does not yet establish a repeatable
  Bluetooth-related drain increase.
- `20260918T001242Z-f2a7ef9e103e` completed that adjacent Bluetooth-off,
  Wi-Fi-preserved counterpart. Clock separation showed 299.059 seconds in
  s2idle; the charge-counter measurement interval was 301.555 seconds. The
  boot ID stayed stable, and the RTC was the expected wake source. `charge_now`
  fell 20,989 uAh (250.6 mA derived average) and integer capacity fell by one
  point. Compared with the immediately prior Bluetooth-on run, that is 11,806
  uAh less over a similar interval (about 36% lower charge use). This supports
  Bluetooth as a possible contributor, but not the whole explanation: the off
  result is still above the earlier five-minute Bluetooth-off values of
  16,397 and 18,365 uAh. The harness restored Bluetooth to powered on
  afterward. The reverse-order repeat below did not preserve most of this
  charge-counter difference.
- `20260918T002025Z-34af6d3a1820` repeated the Bluetooth-on condition after the
  off run. Clock separation showed 298.963 seconds in s2idle, the charge
  measurement interval was 301.548 seconds, the boot ID stayed stable, and the
  RTC was the expected wake source. `charge_now` fell 22,956 uAh (274.1 mA
  derived average); integer capacity did not change. This was only 1,967 uAh
  (9.4%) above the immediately preceding Bluetooth-off result, rather than the
  11,806 uAh gap in the first pair. The initial 392.2 mA Bluetooth-on result
  is therefore an outlier so far; charge data shows only a small, noisy
  on/off difference. Bluetooth was restored and remains powered on.
- The cluster-genpd counter difference has a source-defined meaning. In the
  first Bluetooth-on run, S1 changed by Usage +15, Rejected +16, and S2idle
  +31; the Bluetooth-off run changed by +1, +0, and +1; and the Bluetooth-on
  repeat `20260918T002025Z-34af6d3a1820` changed by +13, +13, and +26.
  Its AOSD/CXSD/DDR counters were also zero, while ADSP advanced by 334. The
  PSCI cpuidle path stages the
  cluster state and calls
  `psci_cpu_suspend_enter()`; when that call returns an error, Linux calls
  `pm_genpd_inc_rejected()`, which increments Rejected and subtracts Usage.
  Thus Bluetooth-on coincides twice with many more candidate cluster-state
  handoffs and PSCI error returns (16/31 and 13/26), while Bluetooth-off had
  one handoff and no recorded error. The exact PSCI error code and reason are
  not recorded. This is a repeatable association in the counters, not yet
  proof that Bluetooth caused the failures. A non-error return also does not
  prove named AOSD/CXSD/DDR residency; all three counters stayed zero in all
  three runs. Sources: [PSCI domain-state staging](https://github.com/gregkh/linux/blob/v7.2.3/drivers/cpuidle/cpuidle-psci-domain.c#L32-L44),
  [PSCI suspend entry and rejected accounting](https://github.com/gregkh/linux/blob/v7.2.3/drivers/cpuidle/cpuidle-psci.c#L64-L105),
  [genpd rejected counter](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pmdomain/core.c#L802-L824),
  [S2idle state accounting](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pmdomain/core.c#L1404-L1443),
  [PSCI firmware error mapping](https://github.com/gregkh/linux/blob/v7.2.3/drivers/firmware/psci/psci.c#L127-L183).
- Before that reverse-order repeat, live state at 2026-09-18 00:20:18 UTC was
  unplugged/discharging at 94% (`charge_now=6212684`), Bluetooth powered on,
  Wi-Fi enabled with `wlp1s0` up, `[s2idle] deep`, and no RTC wake alarm. Run
  `20260918T002025Z-34af6d3a1820` completed the reverse-order five-minute
  s2idle interval with both radios preserved, as recorded above. A live
  post-run check at 00:28:45 UTC confirmed the device awake at 94%, unplugged,
  with Bluetooth powered on, Wi-Fi enabled and up, `[s2idle] deep`, and no RTC
  alarm; the test restored the original radio state.
- `20260918T002946Z-d404cb093fb9` captured one minute of the Bluetooth-on
  condition with the `rpmh-aoss` trace profile. The 58.481-second kernel
  s2idle interval had a single `is_s2idle=yes` cluster request on CPU2 for
  `0x4100c344`; its PSCI enter/exit pair spans the interval and returns at the
  expected RTC wake. The cluster S1 genpd counters changed by Usage +1,
  Rejected +0, S2idle +1. This is a clean Linux-visible return, unlike the
  13–16 rejected cluster requests in the two five-minute Bluetooth-on samples.
  Therefore the rejected-return pattern is intermittent; Bluetooth-on does
  not make every cluster PSCI request fail. All eight CPUs also submitted
  their CPU-local `0x40000004` state during the s2idle window. The trace had
  1,030,364 bytes, eight selected events, and zero per-CPU overruns or dropped
  events. It does not show named AOSD/CXSD/DDR residency; those counters again
  stayed at zero. The charge counter fell 7,215 uAh over 60.904 seconds
  (426.5 mA derived average), but the interval is too short/noisy and was
  traced, so it is not usable as a battery-rate result. The exact PSCI Linux
  return code remains unknown because the current tracepoint records state and
  timing, not retval. Full evidence is in
  `../sm8550-suspend-lab-runs/20260918T002946Z-d404cb093fb9`.
- Next diagnostic: first perform a read-only preflight for the running kernel's
  `psci_cpu_suspend_enter` symbol, kprobe blacklist, and tracefs kprobe-event
  support. If available, the smallest targeted capture is a temporary
  kretprobe recording that function's Linux return value and PSCI state, scoped
  to the private trace instance and filtered to state `0x4100c344` with
  nonzero retval. This can identify the errno behind `Rejected` without a
  kernel rebuild. It must be added without clearing the global kprobe list and
  removed in harness cleanup. Even an identified errno would explain Linux's
  rejected count, not prove why AOSD/CXSD/DDR remain inactive or establish the
  battery drain rate.
- The first live preflight was attempted as the regular SSH user. It confirmed
  kernel `7.2.3`, but reads of `available_filter_functions`, `kprobe_events`,
  `available_tracers`, `debug/kprobes/blacklist/list`, and
  `options/funcgraph-retval` all failed with permission denied. This is an
  access boundary, not evidence that kprobes or those files are unavailable.
  Next, collect only the symbol match and small kprobe/blacklist/tracer
  metadata through the already-installed narrow root lab helper; do not grant
  new sudo commands or modify tracefs during this inventory.
- Root-only preflight `preflight-20260918T003757Z-629cdc39011b` now confirms
  that `psci_cpu_suspend_enter` is present in `available_filter_functions`,
  `/sys/kernel/tracing/kprobe_events` is readable, and the kernel lists
  `function_graph`, `function`, and `nop` tracers. My first blacklist path was
  wrong: this kernel exposes `/sys/kernel/debug/kprobes/blacklist` as a file,
  not `blacklist/list`; `options/funcgraph-retval` is also absent. The
  corrected read-only preflight `preflight-20260918T003940Z-a489835d85bd`
  found no blacklist entry for the target function, no currently registered
  probe on that function, and `/sys/kernel/debug/kprobes/enabled=1`. The
  preflight's matching-event grep still used the old fixed event name, so it
  is not evidence about run-unique definitions; the active-probe list and the
  harness's exact unique-name collision check are the relevant guards. The
  target is not blocked by the live blacklist and kprobes are enabled. Both
  inventories were read-only; no trace event or kernel control was written.
- Linux v7.2.3 source review confirms that a return probe can preserve the
  entry argument: use the saved first argument rather than reading ARM64 `x0`
  after return, and record the signed Linux result. The run profile will use a
  run-unique event group with definition
  `r:<group>/cluster_ret psci_cpu_suspend_enter state=$arg1:u32
  retval=$retval:s32` and private-instance filter
  `state == 1090569028` (`0x4100c344`). The registration itself is still
  gated on a one-run registration/format/filter check and guaranteed cleanup.
  Sources: [kprobe trace documentation](https://github.com/gregkh/linux/blob/v7.2.3/Documentation/trace/kprobetrace.rst#L203-L249),
  [saved return-probe arguments](https://github.com/gregkh/linux/blob/v7.2.3/kernel/trace/trace_kprobe.c#L1515-L1535),
  [ARM64 function arguments](https://github.com/gregkh/linux/blob/v7.2.3/arch/arm64/include/asm/ptrace.h#L314-L333).
- Before the first probe run, use a run-unique event group to avoid collision
  with another trace client, and filter only on state `0x4100c344` so the
  return stream includes both zero and nonzero results. That preserves the
  denominator and can distinguish an intermittent failure from a clean
  return. Enable the event only in the run's private trace instance; cleanup
  must unregister only this run's exact definition after disabling and
  removing the instance. This is a temporary diagnostic profile in the
  existing suspend harness, with the same RTC orchestration, raw capture, and
  checksums. It removes the run probe immediately after saving the trace,
  before post-resume collection; no product code or kernel build is involved.
- Live pre-run check at 2026-09-18 00:47:30 UTC: device awake at 92%,
  discharging with USB online `0`, Bluetooth `Powered: yes`, Wi-Fi enabled and
  `wlp1s0` linked, `[s2idle] deep`, and RTC wakealarm empty. This is the
  intended unplugged/preserve-radio baseline for the temporary return-value
  capture; no suspend or kprobe event has been run yet.
- Repeated root preflight `preflight-20260918T005245Z-cc0e4da61b1b` immediately
  before the probe test: the target function remains available, the blacklist
  and active-probe matches are empty, no registered kprobe event targets the
  function, and global kprobes remain enabled. Bluetooth is powered and Wi-Fi
  remains enabled. No probe has been registered yet; USB state is checked
  again immediately before the run.
- Direct live check at 2026-09-18 00:53:16 UTC confirms USB online `0`,
  battery 91%/discharging (`charge_now=6004764`), `[s2idle] deep`, empty RTC
  wakealarm, Bluetooth powered on, and Wi-Fi `wlp1s0` linked. The remote Nova
  lacks `rg`; a follow-up `grep` verified Bluetooth state. This is the
  confirmed pre-run unplugged baseline.
- Probe setup run `20260918T005407Z-6cc202559cec` failed before starting
  suspend. The kernel accepted and normalized the dynamic event name from the
  requested `r:<group>/cluster_ret` to `r16:<group>/cluster_ret` (default
  `maxactive=16`); the runner's exact-string verification expected the former
  and stopped safely before trace start/RTC suspend. Raw evidence is
  `device/raw/trace/kprobe_events.registered.txt`. More seriously, my cleanup
  matcher accepted only `r:`/`p:` and misreported the normalized registration
  as already absent; cleanup therefore did not remove it. This run did not
  sleep and does not count as a suspend observation. The run-unique event must
  be removed now with the corrected `r16:`-aware exact-name cleanup before any
  further probe test. This is a harness bug, not evidence of a kernel failure.
- Root preflight `preflight-20260918T005631Z-49cad7565992` verified the
  leftover registration is exactly
  `r16:s2lab_20260918T005407Z_6cc202559cec/cluster_ret` and that
  `kprobes/list` shows the target as `[DISABLED]`. This confirms the probe
  definition remained registered but its event was not active; no suspend or
  trace capture occurred. The fixed cleanup now canonicalizes the kernel's
  `r16:` spelling and will remove only this archived run's unique group/event.
- Recovery of `20260918T005407Z-6cc202559cec` ran with the corrected helper.
  The post-recovery root preflight `preflight-20260918T005724Z-6c0a0898d97c`
  now shows no `psci_cpu_suspend_enter` line in `kprobe_events`, `kprobes/list`,
  or `kprobe_profile`; this independently confirms the run-unique definition
  is gone. The device remained on the same boot ID, awake in `[s2idle] deep`,
  unplugged (`usb_online=0`), Bluetooth on, Wi-Fi linked, and with no RTC
  wakealarm. No product, kernel, firmware, or persistent sleep setting changed.
- Retry pre-run check at 2026-09-18 00:59:22 UTC: USB online `0`, battery
  90%/discharging, Bluetooth powered on, Wi-Fi linked, `[s2idle] deep`, RTC
  wakealarm empty. Local `py_compile`, host self-test (including the `r16:`
  normalization regression check), and `git diff --check` all pass. The retry
  will use the same five-minute Bluetooth-on, Wi-Fi-preserved condition.
- The corrected five-minute kretprobe run
  `20260918T005938Z-f9ed9257d8db` completed successfully in observed `s2idle`
  with 301.210504 seconds of suspend-clock separation, unchanged boot ID, and
  the expected RTC wake. The runner reports `trace_state=cleaned` and status
  `complete`; its buffered trace is 229,513 bytes with three selected events.
  `charge_now` fell 55,096 uAh over a 301.210504-second measurement window
  (658.5 mA gauge-derived), with capacity down one point. Because this was a
  five-minute trace-instrumented interval, that figure remains unsuitable as
  an hourly drain estimate.
- Analysis of the full kretprobe trace now resolves the PSCI return-code
  question. It contains 34 calls for state `0x4100c344`; all 34 matching
  `psci_domain_idle_enter` and `...exit` tracepoints are marked
  `is_s2idle=yes`, and all per-CPU trace buffers report zero drops/overruns.
  There are 22 `-95` (`-EOPNOTSUPP`, PSCI `NOT_SUPPORTED`) returns on CPU0 and
  9 `-1` (`-EPERM`, PSCI `DENIED`) returns on CPU7, all rapid retries within
  about 7 ms around 71 seconds into the sleep. Three calls return zero. The
  cluster genpd counters move from Usage 163 / Rejected 300 / S2idle 460 to
  Usage 166 / Rejected 331 / S2idle 494, exactly matching 3 successful,
  31 rejected, and 34 s2idle calls respectively. This is a tight accounting
  correlation between the return probe and genpd statistics. Two successful
  calls on CPU1 and CPU6 span most of the suspend interval and return at wake;
  the third is an immediate CPU0 return. A zero PSCI return establishes that
  the firmware call succeeded, but it does not prove entry into a named
  top-level system or DDR state. Separately, `qcom_stats/ddr_stats` LPM code
  `0xd0` kept `count=1` while its duration advanced from `833342380742` to
  `839242071539` ticks (`+5899690797`); scalar `qcom_stats/ddr` remained
  `0/0`. Linux exposes these as separate records and the public mapping does
  not define what this platform's `0xd0` means. This is evidence that the
  separate firmware DDR-LPM counter is advancing, not proof of a particular
  DDR state or of no DDR low-power residency. The exact trace is in
  `../sm8550-suspend-lab-runs/20260918T005938Z-f9ed9257d8db/device/raw/trace/trace.txt`;
  the before/after genpd snapshots are in that run's `device/pre` and
  `device/post` directories. The kprobe profile reports 1,002 function hits
  and zero misses, so this remains temporary instrumentation and not a battery
  measurement.
- Read-only live preflight at 2026-09-18 01:09 UTC confirms the target symbol
  is available, not blacklisted, and has no registered kprobe/event; global
  kprobes remain enabled. Bluetooth is powered on, Wi-Fi enabled, the device
  kept the same boot ID, and `[s2idle] deep` remains selected. The run's
  post-snapshot records USB online `0`. The run-specific event and trace
  instance have been cleaned up.
- Pre-run baseline for the Bluetooth comparison at 2026-09-18 01:16 UTC:
  USB online `0`, battery discharging at 88% (`charge_now=5798156`), Bluetooth
  powered on and unblocked, Wi-Fi `wlp1s0` linked, `[s2idle] deep`, empty
  `/sys/class/rtc/rtc0/wakealarm`, and unchanged boot ID. The 01:09 root
  preflight showed no remaining kprobe; no probe has been registered since.
  This led into the matched run below, which changed only Bluetooth to
  rfkill-blocked, kept Wi-Fi on, and repeated the same five-minute s2idle
  kretprobe capture. The comparison focuses on PSCI return counts and genpd
  deltas, not the noisy battery gauge.
- Bluetooth-off comparison `20260918T011816Z-656072014367` completed with
  Bluetooth hard-blocked through `rfkill`, Wi-Fi preserved, USB online `0`,
  and the same boot ID. The device measured 298.523 seconds of s2idle
  separation (300.948 seconds boottime). For state `0x4100c344`, the trace has
  one `is_s2idle=yes` enter/exit pair and one `retval=0` return on CPU3, which
  spans nearly the full sleep; there are no `-95` or `-1` returns. Cluster
  genpd counters changed Usage 166 to 167, Rejected 331 to 331, and S2idle
  494 to 495, matching one success and zero rejections. The Bluetooth-on
  matched run had three successes and 31 rejections, so hard-blocking
  Bluetooth coincided with no rejection burst in this one comparison. This
  supports a Bluetooth association with the retries but does not prove that
  Bluetooth caused them or explain battery drain. AOSD, CXSD, and scalar DDR
  counters still stayed at zero; separate `ddr_stats` `0xd0` duration rose
  from `854798553285` to `860688362435` ticks (`+5889809150`), with its count
  still one and no documented state mapping. The charge gauge fell 51,160 uAh
  in this short interval (about 612 mA derived), another noisy result that
  cannot establish a drain rate or Bluetooth benefit. During cleanup,
  `rfkill unblock bluetooth` succeeded but `bluetoothctl power on` returned
  1; a direct follow-up check then showed Powered yes and rfkill unblocked, so
  the original radio state was restored. The exact trace, counters, and
  cleanup receipts are in
  `../sm8550-suspend-lab-runs/20260918T011816Z-656072014367`.
- A fresh read-only root preflight at 2026-09-18 01:27 UTC independently
  confirms the Bluetooth-off run's temporary kprobe is absent from
  `kprobe_events`, `kprobes/list`, and `kprobe_profile`, while global kprobes
  remain enabled. Bluetooth is `Powered: yes` and unblocked, Wi-Fi is enabled,
  the boot ID is unchanged, and `[s2idle] deep` is still selected. This closes
  the apparent Bluetooth restore-command error in the run receipt without
  leaving a radio or trace change on the device.
- Fresh live-tree inspection at 2026-09-18 01:28 UTC confirms the current
  image's PSCI topology directly: the Nova compatible is
  `retroidpocket,rpnova` / `qcom,qcs8550` / `qcom,sm8550`, PSCI uses SMC, and
  `/cpus/domain-idle-states` contains only `cluster-sleep-0` and
  `cluster-sleep-1`. A full node-name search finds neither `system_pd` nor
  `domain_ss3`; the current genpd summary likewise lists the CPU0-7 and
  cluster PSCI domains, without a system domain. Linux therefore has no
  described system/SS3 PSCI domain to request through this s2idle OSI
  hierarchy. This does not rule out AOP autonomously applying deeper residency
  from RPMh sleep votes, so the missing node is not yet a proven cause of the
  zero named counters or reported drain. No device setting was changed.
- Read-only firmware/status inventory at 2026-09-18 01:36 UTC narrows the
  remaining AOP question. The live firmware tree has no AOP image/version
  path, and all 120 files under `qcom_socinfo` contain no AOP entry. The only
  AOP-named device-tree paths are reserved-memory regions
  `aop-cmd-db-region@81c60000` and `aop-config-merged-region@81c80000`; these
  confirm shared-memory plumbing exists but reveal no firmware build or sleep
  decision. The kernel does expose `qcom_aoss/{prevent_aoss_sleep,
  prevent_cx_collapse,prevent_ddr_collapse,ddr_frequency_mhz}`, but read-only
  `cat` of each returns `EINVAL`, so they are not status readouts. No AOP
  acceptance/residency interface is currently available through the inspected
  read-only sysfs/debugfs/firmware inventory. Do not write the `prevent_*`
  controls as a diagnostic. This leaves AOP firmware behavior unresolved and
  means deeper acceptance tracing would need a different existing tracepoint
  or temporary kernel instrumentation; it does not establish that AOP is
  rejecting a valid request. Source/preflight receipt:
  `/private/tmp/sm8550-after-btoff-preflight/preflight-20260918T012750Z-16dbf3a7045d.json`.
- Public-source follow-up found no exact SM8550 `domain_ss3` mapping to use.
  Upstream SM8750 does define `system_pd` -> `domain_ss3` with PSCI parameter
  `0x0200c354`, but that is a different SoC and remains unsafe to copy. A
  related X1E80100 tree has a `system_pd` parent but explicitly leaves its
  system-wide idle-state list as TODO; adding only a parent node is not a
  functional deep-state fix. The plausible DTS path therefore requires the
  SM8550-specific firmware parameter and timing tuple, or a maintainer/vendor
  confirmation that firmware accepts the state. Current searches did not
  reveal that mapping. References: [X1E80100 PSCI domains](https://android.googlesource.com/kernel/common/+/dc99c0ff53f588bb210b1e8b3314c7581cde68a2/arch/arm64/boot/dts/qcom/x1e80100.dtsi#L346-L365),
  [SM8750 system idle state](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/sm8750.dtsi#L2520-L2545).
- A completed five-minute unplugged s2idle comparison with Wi-Fi off and
  Bluetooth off is archived as `20260917T230920Z-e03e810704f8`. USB online
  stayed zero; the kernel observed 298.549 seconds of s2idle separation, the
  boot ID was unchanged, suspend succeeded, and the RTC was the only observed
  wake source. The battery charge counter fell by 656 uAh over 301.101 seconds
  (about 7.8 mA derived average), while the independent Qualcomm capacity
  percentage changed from 100 to 99. Since that property is an integer from
  `BATT_CAPACITY`, it is coarse and does not mean a full 1% charge loss; this
  one near-ceiling measurement remains provisional. Labeled AOSD, CXSD, and
  scalar DDR counters remained zero; APSS increased by one, ADSP by 223, and
  DDR LPM `0xd0` duration increased by about 5.896 billion ticks. Those
  counter labels still do not identify a specific accepted system/DDR state.
- After the Wi-Fi-off run, the harness restored Wi-Fi to enabled, left the
  original Bluetooth powered-off state intact, cleared the RTC alarm, and
  restored debug settings.
- `20260917T231840Z-d5195f1b8ba3` completed 299.563 seconds of s2idle with
  Wi-Fi on and Bluetooth off, also unplugged (`qcom-battmgr-usb/online=0`).
  The boot ID stayed unchanged, suspend succeeded, and only the expected RTC
  wake source changed. With capacity at 99% before and after, `charge_now` /
  `charge_counter` fell 16,397 uAh (about 196 mA derived average), versus
  656 uAh in the preceding Wi-Fi-off run. Armada's 0902 patch exposes the same
  Qualcomm `BATT_CHG_COUNTER` value through both names, so these are one gauge
  reading, not two corroborating sensors; `capacity` is a separate integer
  firmware property. AOSD, CXSD, and scalar DDR stayed zero; APSS increased
  by one and ADSP by 204, similar to the off-radio interval. Wi-Fi was linked
  before sleep (`wlp1s0` up with carrier); after resume it was briefly down,
  then SSH and Bluetooth recovered. The Wi-Fi-off repeat at 99% below shows
  similar charge loss, so these two matched runs do not demonstrate a Wi-Fi
  effect. The exact archive is
  `../sm8550-suspend-lab-runs/20260917T231840Z-d5195f1b8ba3`.
- The QCOM property semantics explain why `charge_now` and `charge_counter`
  are not independent checks here: both are populated from the same firmware
  `BATT_CHG_COUNTER` field. The upstream patch author describes that SM8350-
  class field as remaining charge in uAh (tested at 59% and 85.6%) and maps it
  to `CHARGE_NOW`; Armada also retains the `CHARGE_COUNTER` mapping. Linux's
  generic class docs describe `CHARGE_COUNTER` as relative/time-based, so the
  Qualcomm-specific behavior matters. See the
  [upstream patch](https://lkml.iu.edu/2608.3/10890.html) and
  [power-supply class docs](https://github.com/torvalds/linux/blob/master/Documentation/power/power_supply_class.rst).
- The subsequent matched Wi-Fi-off repeat started at 99% with charge_now
  6,509,807 uAh, battery discharging, Wi-Fi enabled/linked before the harness
  disabled it, Bluetooth powered on before the harness blocked it, and USB
  online zero. Run `20260917T232717Z-4f4794c002ca` completed 298.732 seconds of
  s2idle, unchanged boot ID, successful suspend, and expected RTC-only wake.
  Charge_now fell 18,365 uAh over 301.222 seconds (about 220 mA derived
  average), while capacity changed 99% to 98%. Compared with the matched
  Wi-Fi-on result of 16,397 uAh over 301.79 seconds (capacity remained 99%),
  this does not show a meaningful Wi-Fi drain effect; both readings are of the
  same order and the off run was slightly higher. AOSD, CXSD, and scalar DDR
  stayed zero; APSS increased by one and ADSP by 238. Exact archive:
  `../sm8550-suspend-lab-runs/20260917T232717Z-4f4794c002ca`.
- `20260917T235022Z-6e38cb425e6b` was a 60-second unplugged s2idle run with
  Wi-Fi and Bluetooth preserved. Suspend separation was 59.247 seconds;
  suspend succeeded, boot ID stayed stable, and the expected RTC was the only
  wake source. The new root-side read-only capture found 48 genpd domains. All
  eight CPUs recorded one s2idle entry in their PSCI cpuidle state counters
  (`cpu-sleep-0-0` on cpu0-2, `cpu-sleep-1-0` on cpu3-6, and `cpu-sleep-2-0`
  on cpu7). `power-domain-cluster` state S1 Usage increased 131 to 132 while
  Rejected stayed 271; its descriptor reports 7,200 us latency and 10,150 us
  residency but labels the state `N/A`. The cluster genpd S2idle column stayed
  zero, consistent with this being a cpuidle/PSCI transition rather than the
  separate synchronous-genpd s2idle statistic. In the same interval, QCOM
  AOSD, CXSD, and scalar DDR remained zero; ADSP count increased by 213. This
  directly confirms Linux selected CPU and cluster idle states, but does not
  show that firmware entered the deeper named system/DDR states or identify
  the PSCI parameter behind cluster S1. The battery gauge fell 9,183 uAh over
  the 61.735-second measurement window (about 535 mA derived average), with no
  capacity percentage change; this short result is too noisy to treat as an
  hourly drain estimate. Exact archive:
  `../sm8550-suspend-lab-runs/20260917T235022Z-6e38cb425e6b`.
  Read-only postcheck confirmed discharging, USB online zero, Bluetooth
  powered on, `[s2idle]` selected, and an empty RTC wakealarm.
- The closed [#274](https://github.com/armada-os/armada/issues/274) reports
  the same zero AOSD/CXSD counters on Odin 2 and an active `88e8000.phy` while
  the storage controllers are suspended. It identifies a UFS/SD interrupt
  storm and the shared Qualcomm USB PHY as candidate blockers. Nova also has
  `88e8000.phy` at `power/control=on`, `runtime_status=active`, and zero
  runtime-suspended time, while `a600000.usb` is suspended. However, Nova uses
  internal UFS for root and its CPU0 deep cpuidle state is enabled, unlike the
  Odin 2 report's SD-root and disabled CPU0 state. The Odin 2 findings are a
  close analogue, not proof that the same IRQ source is responsible here.
- The fork branch `feat/sm8550-dwc3-skip-phy` carries the July proposal that
  creates a software node in `dwc3_qcom_probe()`. Do not deploy that commit:
  an upstream report found duplicate software-node creation, a refcount
  use-after-free, and an Oops when DRD switched to gadget mode ([review](https://lkml.iu.edu/2609.1/02793.html)). A September 14 revision moves
  the skip flag into DWC3 core properties and host initialization (11 added
  lines across five files, tested by its author on SM8750 MTP). It is still a
  proposed upstream patch, not a fix validated on Nova. Separately, the
  September 2 cable-free A/B of the xHCI skip-PHY-init patch did not change the
  combo PHY's active/on state, its clocks, regulator votes, callback sequence,
  or named residency counters. Do not prioritize another DWC3 port without a
  changed workload that demonstrates the targeted xHCI reference is relevant;
  any future port must use the revised upstream approach and test
  host/gadget/charger transitions.
- `20260917T213335Z-d3f423182f8b` was the first 45-second UFS trace, but it
  used tracefs `local`; that clock stops across suspend and the archive cannot
  distinguish in-suspend events from transition events. Its pre/post captures
  remain intact but are not evidence of IRQ frequency during s2idle.
- The harness now selects tracefs `boot` in the run-private instance and
  records the original and selected clock. Python compilation, host self-test,
  and `git diff --check` passed. With that correction,
  `20260917T213812Z-1f8ded068061` completed 44.220 seconds of measured s2idle
  separation, retained the boot ID, and produced a 921,543-byte trace with no
  per-CPU overruns or dropped events. It recorded 1,624 UFS IRQ entries and
  3,230 UFS command events, but these clustered around suspend entry and RTC
  resume: there were no filtered UFS IRQ or command events during the central
  roughly 44-second interval. The large aggregate IRQ count is therefore not
  evidence of a Nova UFS IRQ storm during stable s2idle. The short event burst
  at entry appears before steady low power is reached; the trace does not
  explain its source or power cost.
- The five-minute unplugged comparison now has a matched 99% Wi-Fi-off repeat:
  the Wi-Fi-on run lost 16,397 uAh and the Wi-Fi-off run lost 18,365 uAh. These
  are the same order, with the off run slightly higher, so the tests do not
  support Wi-Fi as the cause. The 656 uAh result began at exactly 100% and is
  treated as a near-ceiling gauge edge. The Qualcomm charge value is not
  independently checked by `capacity`. The live DWC3 PHY state is a lead, but
  the closest targeted
  cable-free kernel A/B produced no observable change, so it is not currently
  a supported root-cause candidate. AOSD/CXSD/DDR acceptance still needs a
  firmware-visible status source; more untraced RTC runs will not establish
  that.

### Current sleep reports and low-cost next steps

- [#264](https://github.com/armada-os/armada/issues/264) remains open and
  reports Odin 2 drain with Bluetooth powered in both s2idle and deep; its
  reported `rfkill block bluetooth` workaround reduces drain to about 1%/hour.
  The latest Nova run preserved Bluetooth powered on and found 31 rejected
  cluster PSCI calls (22 `-EOPNOTSUPP`, 9 `-EPERM`) plus three successful
  calls, all during s2idle. This is consistent with a Bluetooth-related
  low-power issue but does not establish that Bluetooth caused the rejections
  or the drain. One matched five-minute rfkill-blocked Nova capture had one
  accepted cluster call and no rejections, compared with 31 rejections while
  Bluetooth was on. This is a useful association, not a drain-rate result or
  a proven root cause. [#235](https://github.com/armada-os/armada/pull/235)
  only gates radios in fake suspend and does not address native s2idle.
- [#265](https://github.com/armada-os/armada/issues/265) reports localized
  warmth even after the Bluetooth workaround, with a similar Odin 3 report.
  The least work is a longer matched sleep-debug/current/wakeup-source capture
  on an affected device; the Nova's 45-second cycle is too short to identify
  an intermittent wake source or local hot rail.
- [#403](https://github.com/armada-os/armada/issues/403) has no logs for a
  Pocket FIT Elite wake failure. Ask for `armada-sleep-debug prepare/collect`,
  boot ID, and post-reboot journal/pstore before changing the kernel.
- [#428](https://github.com/armada-os/armada/issues/428) is empty. The Nova
  already had a persistent journal (124.7 MB across three listed boots), so
  first ask what log is missing instead of adding a global always-on logger.
- [#438](https://github.com/armada-os/armada/issues/438) has Pocket ACE
  Synaptics I2C failures and a concrete source-level resume/polling failure
  path. A deliberate touch check plus a controlled `pm_async=0` comparison
  can test it before spending time on a kernel build.
- [#442](https://github.com/armada-os/armada/pull/442) has merged, removing
  blanket USB autosuspend rules that could power off hub downstream ports.
  It does not explain the Nova's zero AOSD/CXSD/DDR counters. [#234](https://github.com/armada-os/armada/pull/234)
  addresses fake-suspend audio unmute, while [#273](https://github.com/armada-os/armada/pull/273)
  is charge-aware sleep for Pocket EVO and conflicting.

The next source-level diagnostic is **not another or longer suspend**. The
current direct `deep` run already reproduces the zero named-state counters, and
the prior instrumented `7.2.0` run found no Linux-visible active-TCS or
command-status error. The upstream RPMh and stats sources are unchanged through
`7.2.3`, and the current package patch series does not modify those drivers, so
a kernel-only rebuild is unlikely to change what the observer can tell us. The
remaining gap is AOP decision/status and the meaning of the firmware DDR IDs.
No public readback of current AOP acceptance has been found. The mainline
QMP/stats source review below confirms that the available kernel interface has
no read-only acceptance query. The remaining path is vendor AOP/QMP
documentation or a maintainer-provided status interface. For issue #265, longer matched
sleep-debug/current/wakeup-source captures remain useful only on an affected
warm/draining device.

### 2026-09-17 source review: what Linux can prove about AOP

- The v7.2 AOSS QMP driver sends a text command through shared message RAM and
  waits until the AOSS empties that buffer; its completion trace reports that
  transport acknowledgement. That proves the message was consumed, not that
  AOP selected or entered a particular sleep mode. The upstream driver exposes
  only four QMP debugfs writes: set DDR frequency and toggle prevention of
  AOSS, CX, or DDR collapse. There is no read-only sleep-state query in this
  interface, and those writes can alter the state under investigation, so they
  are not suitable probes. See
  [qcom_aoss.c QMP send/ack](https://github.com/torvalds/linux/blob/v7.2/drivers/soc/qcom/qcom_aoss.c#L1858-L1955)
  and [its debugfs controls](https://github.com/torvalds/linux/blob/v7.2/drivers/soc/qcom/qcom_aoss.c#L491-L541).
- `qcom_stats` reads AOSD/CXSD/DDR records from the stats memory exposed by
  firmware and formats the record names into debugfs. For DDR, it sends the
  documented `freqsync` QMP message before rereading the table to refresh
  duration counters. These are the best existing low-cost outcome counters,
  but they do not expose the sleep request accepted by AOP or map the Nova's
  undocumented DDR LPM IDs to named states. See
  [qcom_stats.c record reads](https://github.com/torvalds/linux/blob/v7.2/drivers/soc/qcom/qcom_stats.c#L130-L145),
  [DDR refresh](https://github.com/torvalds/linux/blob/v7.2/drivers/soc/qcom/qcom_stats.c#L148-L222),
  and [record-name discovery](https://github.com/torvalds/linux/blob/v7.2/drivers/soc/qcom/qcom_stats.c#L244-L287).
- Therefore the successful direct-`deep` run proves Linux selected the PSCI
  system-suspend path and resumed, while its zero AOSD/CXSD/scalar-DDR deltas
  show no recorded residency in those named states. The staged sleep TCS values
  and their RSC register status do not close the AOP decision gap. The current
  `7.2.3` image has no RSC snapshot tracepoint or register readback captured in
  its debugfs tree. More RTC cycles or a kernel rebuild that only repeats the
  existing RPMh trace would not answer whether AOP accepted the sleep vote.
- A public search found no SM8550 AOP/QMP status command or documentation that
  supplies that missing acknowledgement or names the `0xd0` DDR state. The
  next meaningful source-level lead is Qualcomm/vendor AOP firmware protocol
  documentation or a maintainer-provided status interface. On the device, the
  latest read-only check after the user's plug/wake confirms Wi-Fi enabled,
  Bluetooth powered off, no RTC alarm, `[s2idle] deep`, and charging at 88%.
- Keep the missing `system_pd`/`domain_ss3` clue scoped to **s2idle**. Linux
  documents s2idle as allowing processors to spend time in their deepest
  configured idle states; PSCI's cpuidle domain driver builds that hierarchy
  from DT and sends domain states only when PSCI OSI support is active. In PC
  mode it leaves those generic power domains always on. By contrast, the
  successful `deep` run uses the separate PSCI `SYSTEM_SUSPEND` system-sleep
  operation. Live logs now confirm this device uses PSCI OSI mode, and live DT
  inspection confirms there is no `system_pd`/`domain_ss3`. A SM8550-specific
  system-domain state parameter is still unknown; do not copy SM8750's PSCI
  parameter by analogy. Before considering a DTS change, compare per-domain
  genpd `idle_states` usage deltas over s2idle with QMP residency counters.
  The current unprivileged account cannot read `/sys/kernel/debug`; check its
  mount state and arrange a temporary read-only privileged capture. See the
  [s2idle contract](https://cdn.kernel.org/doc/html/latest/admin-guide/pm/sleep-states.html#suspend-to-idle),
  [PSCI domain mode handling](https://github.com/torvalds/linux/blob/v7.2/drivers/cpuidle/cpuidle-psci-domain.c#L620-L690),
  and [PSCI SYSTEM_SUSPEND path](https://github.com/torvalds/linux/blob/v7.2/drivers/firmware/psci/psci.c#L2734-L2777).

## 2026-09-01 correction addendum

The device image used for all historical entries through the supported update
boundary is Armada `20260817.8b49045` with kernel `7.2.0-rc7`. The source checkout used to build the harness is newer,
currently at Armada `main` commit
`71e45aa956ad53834ebaaefd6070f28f43d4462d`. Therefore every run through
that boundary is a historical pre-current-fixes control, not the current
Armada baseline. The archives and their original result documents are
retained unchanged. A fresh read-only preflight and a supported Armada update
must complete before a new current-image baseline is named; current-image
experiments will be appended after the boundary.

The clock interpretation is also corrected here without rewriting old run
archives: every new run records the signed separation
`delta(CLOCK_BOOTTIME) - delta(CLOCK_MONOTONIC)` and labels zero/negative
separation as unexpected or negative. Kernel suspend markers and
`suspend_stats` remain independent evidence; a missing clock separation is not
silently treated as normal for either s2idle or deep.

The fresh corrected preflight at `2026-09-01T15:10:21Z` again identified the
historical booted image as Armada `20260817.8b49045` / kernel `7.2.0-rc7`,
bootc image digest
`sha256:275a67b09e6c60fcd3148e09a2b954bbae3b6105725273caeff880247fa0441d`,
with no staged deployment. The supported beta update check at
`2026-09-01T15:12:39Z` returned exit 7 with no output because the beta remote
digest was identical to the booted digest. The complete receipts are
`/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T151021Z-6af837b23e98.json`
and
`/Users/kurt/Developer/sm8550-suspend-lab-runs/supported-update-20260901T151238Z-e96c61cf6e7f.json`.

At `2026-09-01T15:14:40Z`, the shipped selector was used to select the
`main` token, which Armada maps to the `testing` channel. The selector exited
zero and changed only `/var/lib/armada/update-channel`; it did not reboot or
write kernel/boot files. Receipt:
`/Users/kurt/Developer/sm8550-suspend-lab-runs/supported-channel-20260901T151440Z-5d805e252e76.json`.

After that supported channel selection, the shipped update hook was checked at
`2026-09-01T15:15:19Z`. `/usr/bin/steamos-update check` exited zero and
reported target version `20260830.71e45aa`; the receipt is
`/Users/kurt/Developer/sm8550-suspend-lab-runs/supported-update-20260901T151519Z-649e292716e7.json`.

At `2026-09-01T15:26:31Z`, `/usr/bin/steamos-update` staged the selected
testing deployment successfully. The hook imported 128 missing layers
(`6.1 GB`), queued signed image digest
`sha256:cae66b751f6376c7a2da84e7bca7fa81293e9689f7cc9b6bd682ebe83d852c25`
with version `20260830.71e45aa`, and exited zero. It did not reboot; the
receipt is
`/Users/kurt/Developer/sm8550-suspend-lab-runs/supported-update-20260901T152631Z-6bbdb6ec7311.json`.

The pre-apply read-only inventory at `2026-09-01T15:27:44Z` captured the
booted beta image (`20260817.8b49045`, digest
`sha256:275a67b09e6c60fcd3148e09a2b954bbae3b6105725273caeff880247fa0441d`)
and the queued testing image (`20260830.71e45aa`, digest
`sha256:cae66b751f6376c7a2da84e7bca7fa81293e9689f7cc9b6bd682ebe83d852c25`)
together. Receipt:
`/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T152744Z-bc2684c2a174.json`.

At `2026-09-01T15:28:05Z`, the staged deployment was applied through an
autonomous root-owned unit running bootc's supported
`upgrade --apply --from-downloaded` operation. This was the normal apply step
after Armada's `steamos-update` hook staged the image; no kernel or boot file
was manually replaced. Receipt:
`/Users/kurt/Developer/sm8550-suspend-lab-runs/supported-update-20260901T152804Z-36e09b5bac57.json`.

## Device and scope

- Device identity: `Retroid Pocket Nova`; device-tree compatible values
  `retroidpocket,rpnova`, `qcom,qcs8550`, `qcom,sm8550`.
- Historical completed runs before the update boundary used kernel
  `7.2.0-rc7`, Armada `20260817.8b49045`. The post-update current-image
  provenance is recorded below; no current-image suspend run has yet been
  counted as a baseline.
- Host source anchor: Armada `main` at
  `71e45aa956ad53834ebaaefd6070f28f43d4462d` when the lab started.
- Physical condition requested for the sleep baselines: no USB/charger/dock or
  hub attached, no touch or button input during the timed window, device awake
  at the desktop before launch, and microSD left mounted. The harness disabled
  Wi-Fi and Bluetooth only inside the run and restored both afterward.
- No kernel, firmware, ABL, boot-image, storage-controller, device-binding, or
  persistent suspend-policy change has been made by this lab.

## How to read the results

The autonomous root-owned agent invokes Armada's shipped
`/usr/libexec/armada/suspend-dispatch` and writes the post snapshot only after
that command returns. Each run records the signed clock separation
`delta(CLOCK_BOOTTIME) - delta(CLOCK_MONOTONIC)` without clamping it. A
zero/negative separation is reported as unexpected/negative for both modes;
kernel entry/exit markers and `suspend_stats` remain separate evidence.
`suspend_success` is not a claim that every subsystem functionally recovered;
the health and gamepad/display/audio/USB/Steam gates are separate.

The first four current-image receipts (A-D) were generated while the derived
summary still used the legacy basis labels
`kernel-s2idle-markers-plus-waited-systemd-job` and
`kernel-markers-plus-waited-systemd-job`. This was a text-label defect only:
their immutable raw command receipts and `meta/suspend-dispatch.json` files
show the direct Armada dispatcher path, and no existing run archive or ID is
being rewritten. New receipts use `...-waited-dispatcher-job`.

## Experiments

### 2026-09-01 — harness preflight and target identity

Before a suspend attempt, the target was verified by SSH and non-destructive
inventory. It reported the Nova model/compatible strings above, kernel
`7.2.0-rc7`, `[s2idle] deep`, `/etc/armada/sleep.conf=suspend_mode=s2idle`,
internal root on `/dev/sda20`, and a mounted microSD at `/run/media/armada/sd`.
CPU0 `cpu-sleep-0-0` was disabled while awake; the corresponding SM8550 sleep
hook is expected to enable it only inside a real suspend window. Wi-Fi and
Bluetooth were initially enabled/unblocked. No physical change was required
after this inventory beyond keeping the requested no-cable/no-input state.

### 2026-09-01 14:28 UTC — preflight failure, no suspend

- Run: `20260901T142834Z-7123ecd62ba8`
- Request: explicit `s2idle`, Wi-Fi off, Bluetooth off, RTC wake in 45 seconds.
- Observation: the run stopped before arming/suspending because the first
  harness version passed `disabled` to `nmcli radio wifi` instead of its
  accepted `off` value. The exact remote error was `invalid 'wifi' argument:
  'disabled' (use on/off)`.
- Device effect: no suspend was attempted and no physical device action was
  needed. The run archive is retained, including the partial retrieval
  quarantine, as failure provenance.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T142834Z-7123ecd62ba8`.
- Follow-up: fixed the command mapping and verified the host/device archive
  path with the narrow sudo rule.

### 2026-09-01 14:31 UTC — first actual s2idle, boundary bug discovered

- Run: `20260901T143106Z-2221133205fa`
- Request: explicit `s2idle`, Wi-Fi off, Bluetooth off, 45-second RTC wake.
- Observation: raw kernel evidence shows the Nova entered
  `PM: suspend entry (s2idle)` and exited about 45 seconds later, with the
  boot ID unchanged and the kernel success counter incremented. However,
  `systemctl suspend` returned immediately to the lab process; its post
  snapshot and clock receipt were captured before the actual suspend completed.
  The old derived receipt consequently showed only `0.000001` clock-proven
  seconds and incorrectly called the run successful.
- Wake evidence: the first receipt saw an unchanged/stale `pm_wakeup_irq=21`
  (`pmic_pwrkey`) while the RTC IRQ and RTC wakeup-source counters also
  changed. The old broad text match was not trustworthy.
- Device health: `armada-powerd` watchdog timeout/core dump was present in the
  later journal, along with RCU-stall/journal-loss evidence.
- Device effect: the device resumed without reboot; radio state was restored.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T143106Z-2221133205fa`.
- Follow-up: changed the harness to wait on the actual oneshot service and to
  report IRQ, interrupt, and wakeup-source evidence separately.

### 2026-09-01 14:40 UTC — waited s2idle, mode-semantics bug discovered

- Run: `20260901T144034Z-836df46368b1`
- Request: same explicit `s2idle`/off-radio/45-second baseline, now using
  `systemctl start --wait systemd-suspend.service`.
- Observation: the waited systemd job took `46.293496` seconds; the device
  entered/exited s2idle, boot ID stayed unchanged, the success counter rose by
  one, and RTC IRQ 199 plus the RTC wakeup source changed. Both clocks
  advanced by about 46.3 seconds, which is expected for s2idle—not evidence
  that no suspend occurred.
- Device health: the same `armada-powerd` watchdog failure reproduced.
- Device effect: resumed without reboot; radio state was restored.
- Harness effect: the new deep-style clock-only gate marked this valid s2idle
  run failed. No device defect was inferred from that harness result.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T144034Z-836df46368b1`.
- Follow-up: made the verdict mode-aware and added explicit kernel-marker and
  waited-job metrics.

### 2026-09-01 14:43 UTC — baseline A, valid s2idle

- Run: `20260901T144353Z-5bec2b5d5aa1`
- Request: explicit `s2idle`, Wi-Fi off, Bluetooth off, no external cable,
  no user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `s2idle`; waited job
  `46.671013` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`; RTC IRQ 199 (`pm8xxx_rtc_alarm`) delta `+1`; RTC wakeup source
  `c400000.spmi:pmic@0:rtc@6100` active/event deltas `+1/+1`.
- Power/depth: AOSD, CXSD, and DDR counters remained at zero; ADSP count
  delta was `+225`. CPU1-7 s2idle state counters advanced for roughly 44.47
  seconds, while CPU0 `cpu-sleep-0-0` remained disabled/unused in the awake
  snapshot model.
- Resume health: the journal recorded an `armada-powerd.service` watchdog
  timeout and failure, two `rsinput serial1-0: Checksum mismatch` lines, and
  kernel-message loss around resume. The harness still found all 10 input
  devices present, the internal DSI display connected/enabled, no failed
  systemd units at health capture, and no reboot. Functional gamepad,
  display/touch, audio, USB, Wi-Fi, Bluetooth, Steam, and gamescope tests were
  not run.
- Device effect: Wi-Fi and Bluetooth were restored to their pre-run enabled /
  unblocked / powered-on state by cleanup.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T144353Z-5bec2b5d5aa1`;
  summary is under `device/derived/summary.json` and raw evidence under
  `device/raw/`.
- Interpretation: current Armada can complete a timer-woken s2idle cycle, but
  it does not reach the observed AOSD/CXSD/DDR counters and has a repeatable
  powerd/watchdog resume-health problem during this 45-second s2idle setup.

### 2026-09-01 14:47 UTC — baseline B, valid deep

- Run: `20260901T144700Z-fb2eea03ed31`
- Request: explicit `deep`, Wi-Fi off, Bluetooth off, same no-cable/no-input
  condition, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `deep`; waited systemd job
  `2.343243` seconds; clock-separated suspended interval
  `44.314054` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`. The short job duration is expected because the monotonic clock
  does not advance through deep suspend.
- Wake evidence: RTC IRQ 199 delta `+1` and RTC wakeup-source active/event
  deltas `+1/+1`; `pm_wakeup_irq` remained 199 before/after, so the receipt
  labels the primary sysfs value as unchanged rather than treating it as a
  fresh IRQ transition.
- Power/depth: AOSD, CXSD, and DDR counters remained at zero; ADSP count
  delta was `+188`. No reboot was observed.
- Resume health: this run did not produce the powerd/watchdog or rsinput
  errors found in the s2idle baselines; the harness still did not perform
  functional subsystem tests.
- Device effect: Wi-Fi and Bluetooth were restored by cleanup.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T144700Z-fb2eea03ed31`.
- Interpretation: the current image completes an RTC-woken deep suspend and
  resumes cleanly at the coarse health gate, but the available Qualcomm stats
  still show no AOSD/CXSD/DDR residency. This is an observation, not yet a
  reason to import Thor/PockNix patches.

The first deep receipt's battery-rate derivation used the short post-resume
systemd-job duration and therefore overstated current. The harness now uses
the boottime wall interval for battery-rate derivation; no battery-rate number
from that first deep receipt will be used for comparison.

### 2026-09-01 14:51 UTC — baseline C, Bluetooth on s2idle

- Run: `20260901T145153Z-8e6d1986f36c`
- Request: explicit `s2idle`, Bluetooth on, Wi-Fi off, no external cable,
  no user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `s2idle`; waited job
  `46.566521` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`; RTC IRQ 199 delta `+1`; RTC wakeup-source active/event deltas
  `+1/+1`.
- Radio observation: Bluetooth was still powered and unblocked at the post
  health capture; Wi-Fi was disabled as requested. Cleanup restored the
  original Wi-Fi state.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+188`. The same CPU s2idle pattern and no observed CPU0 `cpu-sleep-0-0`
  residency remained.
- Resume health: `armada-powerd.service` again hit its 15-second watchdog;
  gamescope also logged a touchscreen event-processing lag of about 46.1
  seconds. The input inventory still contained all 10 devices, but this is a
  functional-health warning requiring a later direct touch/gamepad check.
- Device effect: no reboot; Wi-Fi/Bluetooth state was restored by cleanup.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T145153Z-8e6d1986f36c`.
- Interpretation: keeping Bluetooth powered did not prevent this short s2idle
  cycle, but it did not alter the missing AOSD/CXSD/DDR counters or the
  repeatable s2idle resume-health warnings.

### 2026-09-01 14:53 UTC — baseline D, Wi-Fi on s2idle

- Run: `20260901T145347Z-5bd093b36a95`
- Request: explicit `s2idle`, Wi-Fi on, Bluetooth off, no external cable,
  no user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `s2idle`; waited job
  `46.764753` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`; RTC IRQ 199 delta `+1`; RTC wakeup-source active/event deltas
  `+2/+2`.
- Radio observation: Wi-Fi was enabled and the `wlp1s0` link was up at the
  post health capture. Bluetooth was intentionally blocked. Cleanup left the
  original enabled/unblocked radio state intact.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+209`; the same lack of observed CPU0 deep s2idle residency remained.
- Resume health: `armada-powerd.service` again hit its 15-second watchdog.
  All 10 input devices remained present and the internal DSI display was
  connected/enabled. This run did not reproduce C's gamescope touchscreen-lag
  line, but the functional input gate is still pending.
- Device effect: no reboot; Wi-Fi and Bluetooth were restored/left in their
  original state by cleanup.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T145347Z-5bd093b36a95`.
- Interpretation: Wi-Fi being enabled at suspend entry did not prevent the
  s2idle cycle or change the missing Qualcomm low-power-domain counters; the
  powerd watchdog behavior remains s2idle-associated.

### 2026-09-01 14:55 UTC — baseline E, normal Armada policy

- Run: `20260901T145520Z-7f85d0048651`
- Request: `--mode policy`, both radios preserved, no external cable, no user
  input, 45-second RTC wake.
- Result: `suspend_success=true`; the installed policy resolved to observed
  `s2idle`; waited job `46.408543` seconds; boot ID unchanged; suspend success
  delta `+1`, failure delta `0`; RTC IRQ 199 delta `+1`; RTC wakeup-source
  active/event deltas `+1/+1`.
- Radio observation: Wi-Fi was enabled with `wlp1s0` up, and Bluetooth was
  powered/unblocked at post capture. This confirms the explicit s2idle mode
  was not required to make the current user-facing policy enter real s2idle.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+210`; CPU1-7 s2idle residency continued while CPU0's deep state remained
  unused in the captured window.
- Resume health: `armada-powerd.service` again hit its 15-second watchdog;
  input count remained 10 and the internal DSI display remained connected and
  enabled. No reboot occurred and no additional functional gate was run.
- Device effect: no persistent policy or radio change; cleanup preserved the
  pre-run radio state.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T145520Z-7f85d0048651`.
- Interpretation: the normal Armada policy on this install is currently a
  working timer-woken s2idle path, but the same missing low-power-domain
  counters and powerd watchdog behavior remain.

### 2026-09-01 14:56 UTC — repeat F, s2idle/off-radio

- Run: `20260901T145657Z-ab63c6967007`
- Request: explicit `s2idle`, Wi-Fi off, Bluetooth off, no external cable,
  no user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `s2idle`; waited job
  `46.510413` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`; RTC IRQ 199 delta `+1`; RTC wakeup-source active/event deltas
  `+1/+1`.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+206`; CPU1-7 s2idle residency continued while CPU0's deep state remained
  unused in the captured window.
- Resume health: `armada-powerd.service` again hit its 15-second watchdog.
  The 10-device input inventory and internal DSI display inventory remained
  present; no reboot occurred and no functional gate was run.
- Device effect: Wi-Fi and Bluetooth were restored by cleanup.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T145657Z-ab63c6967007`.
- Interpretation: this repeat reinforces that the explicit off-radio s2idle
  path is reliable at the coarse suspend gate but does not reach the observed
  Qualcomm AOSD/CXSD/DDR counters and continues to trigger the powerd
  watchdog-health issue.

### 2026-09-01 14:58 UTC — repeat G, deep/off-radio

- Run: `20260901T145840Z-89aefa2cd598`
- Request: explicit `deep`, Wi-Fi off, Bluetooth off, no external cable, no
  user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `deep`; waited job
  `2.252502` seconds; clock-separated suspended interval `44.382355` seconds;
  boot ID unchanged; suspend success delta `+1`, failure delta `0`; RTC IRQ
  199 delta `+1`; RTC wakeup-source active/event deltas `+1/+1`.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+191`. The corrected charge-counter estimate used the `46.654073` second
  boottime interval and was approximately `244 mA`.
- Resume health: no watchdog, rsinput, failed-unit, or inventory-loss error
  was reported by the coarse health capture; the functional gates remain
  pending. No reboot occurred.
- Device effect: Wi-Fi and Bluetooth were restored by cleanup.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T145840Z-89aefa2cd598`.
- Interpretation: deep suspend remains reproducible and cleaner than the
  45-second s2idle path at the coarse health gate, but the available Qualcomm
  low-power-domain counters still do not show AOSD/CXSD/DDR residency.

### 2026-09-01 15:00 UTC — repeat H, Bluetooth-on s2idle

- Run: `20260901T150031Z-abf77a9a349b`
- Request: explicit `s2idle`, Bluetooth on, Wi-Fi off, no external cable, no
  user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `s2idle`; waited job
  `46.423561` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`; RTC IRQ 199 delta `+1`; RTC wakeup-source active/event deltas
  `+1/+1`.
- Radio observation: Bluetooth was powered/unblocked at post capture; Wi-Fi
  was intentionally disabled. Cleanup restored the original radio state.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+215`; CPU1-7 s2idle residency continued and CPU0 deep state remained
  unused in the captured awake/suspend model.
- Resume health: the powerd 15-second watchdog failure reproduced. The input
  and display inventories remained present; no reboot occurred and no
  functional gate was run.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T150031Z-abf77a9a349b`.
- Interpretation: the Bluetooth-on variant is repeatable and does not explain
  the missing Qualcomm low-power-domain counters; the s2idle powerd watchdog
  remains independent of this radio variant.

### 2026-09-01 15:02 UTC — repeat I, Wi-Fi-on s2idle

- Run: `20260901T150249Z-2b9c27538a3e`
- Request: explicit `s2idle`, Wi-Fi on, Bluetooth off, no external cable, no
  user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `s2idle`; waited job
  `46.081041` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`; RTC IRQ 199 delta `+1`; RTC wakeup-source active/event deltas
  `+1/+1`.
- Radio observation: Wi-Fi was enabled and `wlp1s0` was up at post capture;
  Bluetooth was intentionally blocked. Cleanup restored the original state.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+220`; the CPU s2idle/CPU0 pattern remained unchanged.
- Resume health: the powerd 15-second watchdog failure reproduced. All 10
  input devices and the internal DSI display remained present; no touchscreen
  lag line or reboot was observed, and no functional gate was run.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T150249Z-2b9c27538a3e`.
- Interpretation: the Wi-Fi-on repeat remains a reliable s2idle cycle and
  does not explain the missing Qualcomm low-power-domain counters; the
  s2idle watchdog finding persists.

## 2026-09-01 supported update boundary

The historical-control phase ended before the update. The selected Armada
channel was changed only through the shipped `steamos-select-branch` hook and
the image was staged only through `steamos-update`; the deployment was applied
through bootc's supported `--from-downloaded --apply` operation. No kernel,
boot image, ABL, or partition was manually replaced.

The post-update preflight at
`/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T152929Z-35f46c0021d0.json`
shows the booted signed image as Armada `20260830.71e45aa`, digest
`sha256:cae66b751f6376c7a2da84e7bca7fa81293e9689f7cc9b6bd682ebe83d852c25`,
with rollback retained as the historical beta image
`20260817.8b49045` / digest
`sha256:275a67b09e6c60fcd3148e09a2b954bbae3b6105725273caeff880247fa0441d`.
The boot ID changed from the historical control's
`cb38c234-b832-48f7-8519-9c73dbc930ef` to
`be074ba4-8dc3-43e0-ac75-77257f38a7fe`; no deployment remained staged.

The current image reports kernel `7.2.0` (`Linux fedora 7.2.0 #1 SMP PREEMPT
Sun Aug 30 15:09:15 UTC 2026 aarch64`), still identifies the same Nova/SM8550
DT compatibles, and still reports `[s2idle] deep` with
`suspend_mode=s2idle`. Relevant package changes include bootc `1.16.10`,
Terra gamescope `137.13e1dd19`, updated gamescope-session packages, and the
new `armada-rgb` package. The current device-env now has empty primary display
connector fields and explicit RGB targets, so those values must be treated as
current-image baseline facts rather than inherited from the old image.

The preflight had no command failures. This is the point at which the new
current-image Phase 2 baseline begins; none of the earlier suspend receipts
are counted as current-image baseline data.

### 2026-09-01 15:35 UTC — current-image baseline A, direct-dispatch s2idle/off-radio

- Run: `20260901T153527Z-a7399e37863d`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `s2idle`, Wi-Fi off, Bluetooth off, 45-second RTC wake. The pre/post boot ID
  was unchanged at `be074ba4-8dc3-43e0-ac75-77257f38a7fe`; current mem-sleep
  remained `[s2idle] deep` and the Nova/SM8550 DT identity was unchanged.
- Physical condition: no USB/charger/dock/hub, no user input, microSD left
  mounted, device awake before launch. The device had been moved closer to the
  router; no other manual action was taken. SSH loss occurred while radios
  were disabled and was expected.
- Exact suspend path: the autonomous root-owned unit invoked
  `/usr/libexec/armada/suspend-dispatch` with run-local
  `ARMADA_SUSPEND_MODE=s2idle` and `ARMADA_SLEEP_CONFIG`; the command returned
  zero after `2.371608` seconds. The raw stderr says systemd froze the user
  slice, performed the suspend operation, returned, and thawed the slice.
  No direct `systemd-suspend.service` start was used.
- Clock evidence: `CLOCK_BOOTTIME` delta `46.796019` seconds minus
  `CLOCK_MONOTONIC` delta `2.381174` seconds gives signed separation
  `44.414845` seconds, status `observed`. This is independent of the kernel
  markers: `PM: suspend entry (s2idle)` and `PM: suspend exit` were both
  present. `suspend_stats` independently changed from success `0`, fail `0`
  to success `1`, fail `0`.
- Wake/depth: the expected RTC source fired: IRQ 200
  (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta `+1`, and
  `c400000.spmi:pmic@0:rtc@6100` wakeup-source active/event deltas `+1/+1`.
  AOSD, CXSD, and DDR count deltas were all `0`; ADSP count delta was `+290`.
  CPU0's `cpu-sleep-0-0` s2idle counters became visible in this current image
  run (`usage +24`, `time +933` in the captured counter units), while the
  other CPU sleep-state counters also advanced.
- Resume health: `suspend_success=true`, boot survived without reset, no
  systemd failed units, and no new error-like log lines. Ten input devices
  remained present and internal `DSI-1` remained connected/enabled. Steam and
  gamescope processes were present, but no functional gamepad, touch, audio,
  Steam UI, or game test was run. `lsusb` is not installed on the device, so
  USB enumeration was not assessed by this receipt.
- Cleanup: Wi-Fi and Bluetooth rfkill state were restored. The first
  `bluetoothctl power on` cleanup attempt returned `org.bluez.Error.Busy`, but
  the subsequent read-only check confirmed Wi-Fi enabled/up, Bluetooth
  unblocked and powered on. This cleanup transient is retained as evidence;
  no persistent radio change remains.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T153527Z-a7399e37863d`;
  checksum verification covered `4241` files with no mismatches.
- Interpretation: this is the first valid current-image s2idle baseline
  receipt. It demonstrates real RTC-woken s2idle through Armada's supported
  dispatcher with clock separation and kernel/stat evidence, while the zero
  AOSD/CXSD/DDR counters and elevated ADSP delta remain observations, not a
  causal diagnosis. No kernel patch has been made.

### 2026-09-01 15:38 UTC — current-image baseline B, direct-dispatch deep/off-radio

- Run: `20260901T153837Z-528c7ba0975a`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `deep`, Wi-Fi off, Bluetooth off, 45-second RTC wake. The pre/post boot ID
  remained `be074ba4-8dc3-43e0-ac75-77257f38a7fe`; the Nova/SM8550 DT identity
  and `[s2idle] deep` availability were unchanged.
- Physical condition: same no-USB/charger/dock/hub, no-input, microSD-mounted
  condition as baseline A. No manual device action was taken between runs;
  Wi-Fi and Bluetooth were controlled only inside the autonomous run.
- Exact suspend path: the root-owned agent invoked
  `/usr/libexec/armada/suspend-dispatch` with run-local
  `ARMADA_SUSPEND_MODE=deep` and `ARMADA_SLEEP_CONFIG`; it returned zero after
  `2.245466` seconds. The dispatcher stderr again records the freeze,
  suspend, return, and thaw sequence. No direct `systemd-suspend.service`
  start was used.
- Clock evidence: `CLOCK_BOOTTIME` delta `46.618300` seconds minus
  `CLOCK_MONOTONIC` delta `2.263929` seconds gives signed separation
  `44.354371` seconds, status `observed`. Independent kernel evidence shows
  `PM: suspend entry (deep)` and `PM: suspend exit`. Independent
  `suspend_stats` changed from success `1`, fail `0` to success `2`, fail `0`.
- Wake/depth: the expected RTC fired through IRQ 200
  (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta `+1`, and the RTC
  wakeup-source active/event deltas were `+1/+1`. AOSD, CXSD, and DDR count
  deltas were all `0`; ADSP count delta was `+182`. The deep run's s2idle
  residency fields were zero for the CPU sleep states, while generic cpuidle
  usage counters advanced.
- Resume health: `suspend_success=true`, no reset, no systemd failed units,
  and no new error-like log lines. Ten input devices remained present and
  internal `DSI-1` remained connected/enabled. Steam and gamescope processes
  were present, but no functional gamepad, touch, audio, Steam UI, or game
  test was run. `lsusb` remains unavailable on-device, so USB enumeration was
  not assessed by this receipt.
- Cleanup: the recorded BlueZ power-on action again returned
  `org.bluez.Error.Busy` while restoring the per-run off state, but the
  subsequent read-only check confirmed Wi-Fi enabled/up and Bluetooth
  unblocked/powered on. The transient cleanup result is retained; no
  persistent radio change remains.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T153837Z-528c7ba0975a`.
- Interpretation: this is a valid current-image deep baseline paired with A.
  Both modes reach the requested kernel path and wake from the expected RTC,
  but neither produces nonzero AOSD/CXSD/DDR counters. The ADSP deltas differ
  between the two single cycles, so they are not yet a diagnosis. No kernel
  patch has been made.

### 2026-09-01 15:40 UTC — current-image baseline C, Bluetooth-on s2idle/off-Wi-Fi

- Run: `20260901T154048Z-4f8b83e02e0f`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `s2idle`, Bluetooth on, Wi-Fi off, 45-second RTC wake. The boot ID remained
  `be074ba4-8dc3-43e0-ac75-77257f38a7fe`; mem-sleep stayed `[s2idle] deep`.
- Physical condition: unchanged no-cable/no-input/microSD-mounted condition;
  no manual device action. Wi-Fi was disabled only inside the run, so SSH
  loss was expected. Bluetooth was left powered by the experiment policy.
- Exact suspend path: the autonomous root-owned agent invoked
  `/usr/libexec/armada/suspend-dispatch` with run-local s2idle environment;
  it returned zero after `2.087467` seconds. No direct
  `systemd-suspend.service` start was used.
- Clock evidence: `CLOCK_BOOTTIME` delta `46.190723` seconds minus
  `CLOCK_MONOTONIC` delta `2.115305` seconds gives signed separation
  `44.075419` seconds, status `observed`. Kernel markers independently show
  `PM: suspend entry (s2idle)` and `PM: suspend exit`. `suspend_stats`
  independently changed from success `2`, fail `0` to success `3`, fail `0`.
- Wake/depth: RTC IRQ 200 (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta
  `+1` and RTC wakeup-source active/event deltas `+1/+1`; the PM wakeup IRQ
  remained 200 and no competing wake source was recorded. AOSD, CXSD, and
  DDR count deltas remained `0`; ADSP count delta was `+181`.
- Resume health: `suspend_success=true`, no reset, no failed systemd units,
  and no new error-like log lines. Bluetooth was powered/on in the post
  snapshot, Wi-Fi was disabled as requested, ten input devices remained
  present, and internal `DSI-1` remained connected/enabled. Steam/gamescope
  processes were present; no functional gamepad, touch, audio, Steam UI, or
  game test was run. `lsusb` is unavailable, so USB enumeration was not
  assessed.
- Cleanup: Wi-Fi was restored successfully; Bluetooth was not changed because
  it was already on. A subsequent read-only check confirmed both radios
  enabled/unblocked/on.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T154048Z-4f8b83e02e0f`.
- Interpretation: Bluetooth-on did not prevent a valid current-image s2idle
  cycle or alter the RTC wake classification in this single run. The
  low-power-domain counters remain zero, and the modest ADSP delta is only an
  observation pending repeated samples. No kernel patch has been made.

### 2026-09-01 15:42 UTC — current-image baseline D, Wi-Fi-on s2idle/off-Bluetooth

- Run: `20260901T154249Z-b22ef7622799`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `s2idle`, Wi-Fi on, Bluetooth off, 45-second RTC wake. The boot ID remained
  `be074ba4-8dc3-43e0-ac75-77257f38a7fe`; the requested and observed modes
  matched.
- Physical condition: unchanged no-cable/no-input/microSD-mounted condition;
  no manual action. Wi-Fi remained available as the requested radio variable,
  although SSH still timed out during the suspend interval. Bluetooth was
  blocked only inside the run.
- Exact suspend path: the autonomous root-owned agent invoked
  `/usr/libexec/armada/suspend-dispatch` with run-local s2idle environment;
  it returned zero after `2.231535` seconds. No direct
  `systemd-suspend.service` start was used.
- Clock evidence: `CLOCK_BOOTTIME` delta `45.873797` seconds minus
  `CLOCK_MONOTONIC` delta `2.237828` seconds gives signed separation
  `43.635969` seconds, status `observed`. Kernel markers independently show
  `PM: suspend entry (s2idle)` and `PM: suspend exit`. `suspend_stats`
  independently advanced by success `+1` with failure delta `0`.
- Wake/depth: RTC IRQ 200 (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta
  `+1` and RTC wakeup-source active/event deltas `+1/+1`; PM wakeup IRQ stayed
  200 with no competing wake source recorded. AOSD, CXSD, and DDR count
  deltas were all `0`; ADSP count delta was `+182`.
- Resume health: `suspend_success=true`, no reset, no failed systemd units,
  and no new error-like log lines. Wi-Fi was enabled/up in the post snapshot;
  Bluetooth was off/blocked as requested. Ten input devices remained present
  and internal `DSI-1` remained connected/enabled. Steam/gamescope processes
  were present, but no functional gamepad, touch, audio, Steam UI, or game
  test was run. `lsusb` is unavailable, so USB enumeration was not assessed.
- Cleanup: Wi-Fi restoration succeeded and Bluetooth rfkill/power state was
  restored; a read-only follow-up confirmed Wi-Fi enabled/up and Bluetooth
  enabled, unblocked, and powered on.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T154249Z-b22ef7622799`.
- Interpretation: Wi-Fi-on/Bluetooth-off did not prevent a valid current-image
  s2idle cycle or change the expected RTC wake classification in this sample.
  The zero low-power-domain counters persist. No kernel patch has been made.

### 2026-09-01 15:44 UTC — current-image policy sample retained from prior run

- Run: `20260901T154437Z-64317bfc6a02`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, Armada
  `policy`, radios preserved, 45-second RTC wake. Policy selected and
  observed `s2idle`; the boot ID remained unchanged. This completed sample was
  present in the archive before the later notebook reconciliation and is
  documented here without rewriting its receipt.
- Physical condition: no cable, charger, dock, hub, or user input; microSD
  remained inserted and mounted. No manual device action was recorded.
- Exact path: the root-owned agent invoked
  `/usr/libexec/armada/suspend-dispatch` and received return code `0` after
  `2.342269` seconds.
- Clock/evidence: signed clock separation was `43.911823` seconds and status
  `observed`; kernel policy/s2idle entry and exit markers were present.
  `suspend_stats` advanced from success `4`, fail `0` to success `5`, fail
  `0`. RTC IRQ 200 advanced by one and the matching wakeup source advanced
  active/event by `+1/+1`.
- Qualcomm/depth: AOSD, CXSD, and scalar DDR count/duration deltas were zero;
  ADSP count delta was `+197`. No new error-like log lines or failed systemd
  units were observed; ten inputs remained present and `DSI-1` remained
  connected/enabled.
- Aggregate IRQ observation: IRQ 169 (`ufshcd`) increased by `10,509` and
  mmc0 by `47` between the pre/post snapshots. As established by the later
  trace, these are aggregate pre/post-window values rather than proven
  in-suspend rates; the low mmc0 delta does not support the historical SDHCI
  storm.
- Cleanup: no radio state needed restoration because policy preserved it; the
  RTC and temporary diagnostic controls were restored. The archive checksum
  verification covered `4,226` files with no mismatches.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T154437Z-64317bfc6a02`.
- Interpretation: this is an additional clean current-image policy sample,
  not a new candidate-fix experiment. It contributes to the reliability
  evidence and preserves the same zero AOSD/CXSD/DDR result; no kernel patch
  was made.

### 2026-09-01 15:46 UTC — current-image baseline E, Armada policy/preserve-radio

- Run: `20260901T154633Z-016dc93da017`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, Armada
  `policy`, both radios preserved, 45-second RTC wake. Policy selected and
  observed `s2idle`; the boot ID remained
  `be074ba4-8dc3-43e0-ac75-77257f38a7fe` and mem-sleep remained
  `[s2idle] deep`.
- Physical condition: unchanged no-cable/no-input/microSD-mounted condition;
  no manual action was taken. Both Wi-Fi and Bluetooth were enabled/up/on
  before and after the run, and SSH loss during the suspend interval was
  expected.
- Exact suspend path: with no transient mode environment override, the
  autonomous root-owned agent invoked the shipped
  `/usr/libexec/armada/suspend-dispatch`; it returned zero after `2.318356`
  seconds. No direct `systemd-suspend.service` start was used.
- Clock evidence: `CLOCK_BOOTTIME` delta `46.539722` seconds minus
  `CLOCK_MONOTONIC` delta `2.345078` seconds gives signed separation
  `44.194644` seconds, status `observed`. Kernel markers independently show
  `PM: suspend entry (s2idle)` and `PM: suspend exit`. `suspend_stats`
  independently advanced from success `5`, fail `0` to success `6`, fail `0`.
- Wake/depth: RTC IRQ 200 (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta
  `+1` and RTC wakeup-source active/event deltas `+1/+1`; PM wakeup IRQ stayed
  200 with no competing wake source recorded. AOSD, CXSD, and DDR count
  deltas were all `0`; ADSP count delta was `+184`.
- Resume health: `suspend_success=true`, no reset, no failed systemd units,
  and no new error-like log lines. Wi-Fi was enabled/up and Bluetooth was
  powered/on; ten input devices remained present and internal `DSI-1` remained
  connected/enabled. Steam/gamescope processes were present, but no
  functional gamepad, touch, audio, Steam UI, or game test was run. `lsusb`
  is unavailable, so USB enumeration was not assessed.
- Cleanup: no radio cleanup was necessary because policy preserved the
  existing state. A follow-up read-only check confirmed both radios remained
  enabled, unblocked, and powered on.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T154633Z-016dc93da017`.
- Interpretation: Armada's normal policy currently resolves to the same
  real s2idle path measured by the explicit runs. This fifth current-image
  cycle is valid and reinforces RTC-woken s2idle, but the zero low-power-domain
  counters remain unexplained. No kernel patch has been made.

### 2026-09-01 15:48 UTC — current-image repeat F, s2idle/off-radio

- Run: `20260901T154832Z-8a5193ddaeb5`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `s2idle`, Wi-Fi off, Bluetooth off, 45-second RTC wake. The boot ID was
  unchanged and the dispatcher observed the requested mode.
- Physical condition: unchanged no-cable/no-input/microSD-mounted condition;
  no manual device action. SSH loss was expected while both radios were off.
- Exact path: the autonomous root-owned agent invoked
  `/usr/libexec/armada/suspend-dispatch` with run-local s2idle environment and
  received return code zero after `2.219483` seconds.
- Clock evidence: `CLOCK_BOOTTIME` delta `46.493743` seconds minus
  `CLOCK_MONOTONIC` delta `2.244774` seconds gives signed separation
  `44.248969` seconds, status `observed`. Kernel entry/exit markers were
  present. `suspend_stats` advanced independently from success `6`, fail `0`
  to success `7`, fail `0`.
- Wake/depth: RTC IRQ 200 (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta
  `+1` and RTC wakeup-source active/event deltas `+1/+1`; PM wakeup IRQ stayed
  200 with no competing wake source. AOSD, CXSD, and DDR count deltas were
  `0`; ADSP count delta was `+182`.
- Resume health: `suspend_success=true`, no reset, no new error-like log
  lines, ten inputs present, and internal `DSI-1` connected/enabled. Steam and
  gamescope processes were present; no functional gamepad, touch, audio,
  Steam UI, game, or USB test was run (`lsusb` is unavailable). The post
  snapshot correctly showed Wi-Fi disabled and Bluetooth off/blocked.
- Cleanup: Wi-Fi and Bluetooth were restored. The recorded BlueZ power-on
  action returned `org.bluez.Error.Busy` transiently, but the follow-up
  read-only check confirmed Wi-Fi enabled/up and Bluetooth enabled,
  unblocked, and powered on.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T154832Z-8a5193ddaeb5`.
- Interpretation: the first independent repeat of current baseline A
  reproduces real s2idle, expected RTC wake, and zero low-power-domain
  counters. The repeated ADSP delta is an observation only; no kernel patch
  has been made.

### 2026-09-01 15:50 UTC — current-image repeat G, deep/off-radio

- Run: `20260901T155052Z-87c9c373b27c`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `deep`, Wi-Fi off, Bluetooth off, 45-second RTC wake. The boot ID remained
  `be074ba4-8dc3-43e0-ac75-77257f38a7fe`; requested and observed modes
  matched.
- Physical condition: unchanged no-cable/no-input/microSD-mounted condition;
  no manual device action. SSH loss was expected while both radios were off.
- Exact path: the autonomous root-owned agent invoked
  `/usr/libexec/armada/suspend-dispatch` with run-local deep environment and
  received return code zero after `2.457125` seconds.
- Clock evidence: `CLOCK_BOOTTIME` delta `45.846394` seconds minus
  `CLOCK_MONOTONIC` delta `2.477252` seconds gives signed separation
  `43.369142` seconds, status `observed`. Kernel deep entry/exit markers were
  present. `suspend_stats` advanced independently from success `7`, fail `0`
  to success `8`, fail `0`.
- Wake/depth: RTC IRQ 200 (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta
  `+1`; the matching RTC wakeup source reported active/event deltas `+2/+2`
  in this archive. PM wakeup IRQ stayed 200 and no competing source was
  recorded. AOSD, CXSD, and DDR count deltas were `0`; ADSP count delta was
  `+180`.
- Resume health: `suspend_success=true`, no reset, no new error-like log
  lines, ten inputs present, and internal `DSI-1` connected/enabled. Steam and
  gamescope processes were present; no functional gamepad, touch, audio,
  Steam UI, game, or USB test was run (`lsusb` is unavailable). The post
  snapshot showed both radios disabled/blocked during the requested window.
- Cleanup: Wi-Fi and Bluetooth were restored; a follow-up read-only check
  confirmed Wi-Fi enabled/up and Bluetooth enabled, unblocked, and powered on.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T155052Z-87c9c373b27c`;
  checksum verification covered `4241` files with no mismatches.
- Interpretation: this independent deep repeat is valid and preserves the
  qualitative result already established by A/B: real deep sleep, RTC wake,
  clock separation, and zero AOSD/CXSD/DDR delta. The ten-cycle reliability
  objective remains open; blind repeats are paused here for the requested
  forensic differential. No kernel patch has been made.

## 2026-09-01 16:10 UTC — read-only A/B forensic differential

- Scope: completed without rerunning A or B and without changing device state.
  Compared current-image off-radio s2idle A
  (`20260901T153527Z-a7399e37863d`) with paired off-radio deep B
  (`20260901T153837Z-528c7ba0975a`). Run G
  (`20260901T155052Z-87c9c373b27c`) had already completed normally and remains
  preserved; blind repeats are paused at seven clean current-image cycles.
- Qualcomm stats: both archives contain all 17 `/sys/kernel/debug/qcom_stats`
  filenames in pre/post captures, with exact raw files retained. `aosd`,
  `cxsd`, and scalar `ddr` remained absolute zero in both modes, while ADSP,
  APSS, CDSP, and separate `ddr_stats` data changed. The Linux 7.2
  implementation and current Armada sleep-debug semantics classify this as
  valid named-state zero evidence, not a wrong parser or presumed dead
  firmware. `ddr_stats` is a separate export and was not collapsed into the
  scalar `ddr` result.
- Interrupts: all 126 IRQ IDs were compared. A had 34 nonzero rows / 44,150
  positive events; B had 33 / 40,886. UFS IRQ 169 (`ufshcd`) measured
  287.426/s in A and 240.179/s in B after normalization by signed suspended
  seconds. `mmc0` measured only 1.126/s and 1.172/s, so the historical
  tens-per-second SDHCI symptom was not present.
- Runtime-PM: UFS controller/host/target and root LUN remained active in the
  snapshots; PCIe and ath12k endpoint were active with `control=on`; combo PHY
  `88e8000.phy` was active/on. DWC3 was suspended pre and active post, with no
  attached UDC/xHCI device. No runtime usage-count field was available in any
  captured record. Kernel PM callbacks for UFS, DWC3/PHY, SDHCI, PCIe/WLAN,
  remoteproc, and display returned zero.
- Clocks/regulators: complete clk/regulator summaries were present in A/B
  pre/post; no interconnect summary was available in the archives or live
  debugfs. UFS and PCIe consumers were referenced; USB3 combo-PHY clocks and
  regulators appeared in post-resume state. No in-suspend vote value was
  captured.
- ADSP/audio: ADSP count is a firmware subsystem low-power-entry statistic,
  not an audio PCM count. All captured PCM status files were `closed`, DAPM
  was Off except HDMI codec Standby, and Armada reported approximately 99%
  ADSP sleep over its coarse diagnostic window. Audio is not a supported
  primary blocker from this evidence.
- Result: the complete forensic analysis, ranked hypotheses, unknowns, raw
  archive paths, and exactly one recommended next experiment are in
  `research/sm8550-suspend-lab/current-image-forensic-differential.md`.
  No kernel or package patch was made, and no SDHCI/USB/runtime-PM/control
  value was changed.

## 2026-09-01 16:28 UTC — current-stock deep UFS IRQ/PM trace experiment

- Run: `20260901T162647Z-5c6d44f7dcf7`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `deep`, Wi-Fi off, Bluetooth off, 45-second RTC wake, microSD left inserted
  and mounted. The boot ID stayed unchanged. No kernel, package, firmware,
  SDHCI, runtime-PM control, or power-policy value was changed.
- Physical condition: no cable, dock, hub, charger, or user input; no manual
  device action was required. SSH loss during the sleep interval was expected.
- Exact path: the root-owned detached agent armed the RTC, created a private
  tracefs instance, invoked `/usr/libexec/armada/suspend-dispatch`, stopped
  tracing after the dispatcher returned, archived the post-resume snapshot,
  and removed the private instance. Dispatcher return code was `0` and the
  run is `suspend_success=true`.
- Clock/evidence: `CLOCK_BOOTTIME` delta `45.871318` seconds minus
  `CLOCK_MONOTONIC` delta `2.385984` seconds gives signed separation
  `43.485335` seconds, status `observed`. Kernel deep entry/exit markers were
  present. `suspend_stats` advanced independently from success `8`, fail `0`
  to success `9`, fail `0`. RTC IRQ 200 and its matching wakeup source each
  advanced by one.
- Trace configuration: the archive preserves all 2,812 available-event lines,
  event formats, filter/enable receipts, control snapshots, the 1,229,227-byte
  trace buffer, and per-CPU statistics. Twelve events were selected: IRQ 169
  entry/exit, both device-PM callback events, and eight `ufs:` tracepoints.
  The run used the then-current helper, so the PM tracepoint filter remained
  `none` because this kernel exposes the field as `device`, not `dev_name`;
  UFS PM lines were selected by exact device text during analysis. The trace
  used the kernel's `[local]` trace clock; its timestamps therefore cover the
  awake suspend/resume portions, while the signed clock pair proves the
  43.485-second suspended interval.
- IRQ/UFS result: the trace contains `1,069` IRQ-169 handler entries and
  `1,029` exits, with `0` per-CPU overruns and `0` dropped events. There were
  `1,758` `ufshcd_command` records (`879` sends and `879` completions), `126`
  UIC commands, and `7` hibern8 profile records; runtime suspend/resume and
  exception UFS tracepoints were absent. The UFS IRQ trace events were before
  the no-IRQ suspend boundary or after the no-IRQ resume boundary; none fell
  in the boundary gap. This demonstrates UFS activity around the transition,
  but not a Linux UFS interrupt handler executing during hardware suspend.
- PM result: `ufshcd-qcom 1d84000.ufshc`, `qcom-qmp-ufs-phy 1d80000.phy`, the
  SCSI host, UFS WLUN, devfreq, and UFS BSG paths all emitted suspend/resume
  callbacks with `err=0`, including the no-IRQ power-domain callbacks. The
  raw trace also records PCIe, ath12k, DWC3, SDHCI, display, and RPMh no-IRQ
  callbacks completing with `err=0`.
- Qualification of A/B: A/B `/proc/interrupts` deltas span pre-snapshot
  through post-snapshot collection, not only the hardware-suspended interval.
  This trace run's post-snapshot UFS total was `255,923 - 237,861 = 18,062`,
  but only `1,069` IRQ-169 entries were captured in the traced suspend/resume
  window. Therefore the earlier normalized UFS rates (`287.426/s` and
  `240.179/s`) are useful as aggregate pre/post-window rates, not proven
  in-suspend rates. The historical mmc0 storm remains unsupported by the
  observed trace and earlier low `mmc0` deltas.
- Qualcomm depth/result: AOSD, CXSD, and scalar DDR remained zero; ADSP was
  `+183`. Resume health had no new error-like lines, no failed systemd units,
  ten inputs remained present, and `DSI-1` remained connected/enabled.
- Cleanup: all selected events were disabled, the private trace instance was
  removed, Wi-Fi and Bluetooth were restored, and checksum verification
  covered `4,330` files with no mismatches. The trace run remains a distinct
  instrumented sample and is not counted as an uninstrumented stock repeat.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T162647Z-5c6d44f7dcf7`.
- Interpretation: UFS is active and busy around suspend entry/resume and has a
  strong Linux-visible association with the earlier aggregate IRQ deltas, but
  this experiment does not prove that UFS prevents AOSD/CXSD/DDR entry. The
  zero hardware counters remain unresolved; no kernel patch has been made.

## 2026-09-01 16:36 UTC — current-image stock repeat 8, s2idle/off-radio

- Run: `20260901T163453Z-c55f8534886a`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `s2idle`, Wi-Fi off, Bluetooth off, 45-second RTC wake, with no trace
  profile. The boot ID stayed unchanged. This is uninstrumented stock repeat
  8 of the ten-cycle current-image reliability target.
- Physical condition: no cable, charger, dock, hub, or user input; microSD
  remained inserted and mounted. No manual device action was required. SSH
  loss during the sleep interval was expected.
- Exact path: the root-owned detached agent invoked Armada's shipped
  `/usr/libexec/armada/suspend-dispatch` with the run-local s2idle request and
  received return code `0` after `2.120831` seconds.
- Clock/evidence: `CLOCK_BOOTTIME` delta `45.755710` seconds minus
  `CLOCK_MONOTONIC` delta `2.146865` seconds gives signed separation
  `43.608845` seconds, status `observed`. Kernel s2idle entry/exit markers
  were present. `suspend_stats` advanced independently from success `9`, fail
  `0` to success `10`, fail `0`. RTC IRQ 200 advanced by one and its matching
  wakeup source advanced active/event by `+2/+2`.
- Qualcomm/depth: AOSD, CXSD, and scalar DDR count/duration deltas were all
  zero; ADSP count delta was `+186`. The post snapshot had no new error-like
  lines and no failed systemd units. Ten input devices remained present and
  internal `DSI-1` remained connected/enabled.
- Aggregate IRQ observation: IRQ 169 (`ufshcd`) increased by `16,065` and
  mmc0 by `54` between the harness pre/post snapshots. As established by the
  traced run, these counters span post-resume collection and are not claimed
  as in-suspend rates; mmc0 still does not show the historical tens-per-second
  storm in this stock sample.
- Cleanup: the private trace profile was disabled (`none`), the RTC and
  temporary controls were restored, and a post-cleanup read-only SSH check
  confirmed Wi-Fi enabled/up, Bluetooth unblocked/powered on, and no hard
  radio block. The Bluetooth power-on command returned a transient failure in
  the cleanup receipt, but the subsequent check showed the desired restored
  state. Checksum verification covered `4,243` files with no mismatches.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T163453Z-c55f8534886a`.
- Interpretation: repeat 8 is a clean current-image s2idle reliability sample
  and reproduces the zero AOSD/CXSD/DDR result. The ten-cycle objective is
  still open; no kernel patch has been made.

## 2026-09-01 16:39 UTC — current-image stock repeat 9, deep/off-radio

- Run: `20260901T163731Z-e91f1b27bc6e`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `deep`, Wi-Fi off, Bluetooth off, 45-second RTC wake, with no trace
  profile. The boot ID stayed unchanged. This is uninstrumented stock repeat
  9 of the ten-cycle current-image reliability target.
- Physical condition: no cable, charger, dock, hub, or user input; microSD
  remained inserted and mounted. No manual device action was required. SSH
  loss during the sleep interval was expected.
- Exact path: the root-owned detached agent invoked Armada's shipped
  `/usr/libexec/armada/suspend-dispatch` with the run-local deep request and
  received return code `0` after `2.322498` seconds.
- Clock/evidence: `CLOCK_BOOTTIME` delta `46.097678` seconds minus
  `CLOCK_MONOTONIC` delta `2.346724` seconds gives signed separation
  `43.750954` seconds, status `observed`. Kernel deep entry/exit markers were
  present. `suspend_stats` advanced independently from success `10`, fail `0`
  to success `11`, fail `0`. RTC IRQ 200 advanced by one and its matching
  wakeup source advanced active/event by `+1/+1`.
- Qualcomm/depth: AOSD, CXSD, and scalar DDR count/duration deltas were all
  zero; ADSP count delta was `+182`. The post snapshot had no new error-like
  lines and no failed systemd units. Ten input devices remained present and
  internal `DSI-1` remained connected/enabled.
- Aggregate IRQ observation: IRQ 169 (`ufshcd`) increased by `16,879` and
  mmc0 by `53` between the harness pre/post snapshots. As established by the
  traced run, these counters span post-resume collection and are not claimed
  as in-suspend rates; mmc0 still does not show the historical tens-per-second
  storm in this stock sample.
- Cleanup: the RTC and temporary controls were restored. The Bluetooth
  power-on command again returned a transient failure in the cleanup receipt,
  but a subsequent read-only SSH check confirmed Wi-Fi enabled/up, Bluetooth
  unblocked/powered on, and no hard radio block. Checksum verification covered
  `4,243` files with no mismatches.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T163731Z-e91f1b27bc6e`.
- Interpretation: repeat 9 is a clean current-image deep reliability sample
  and reproduces the zero AOSD/CXSD/DDR result. One uninstrumented sample
  remains; no kernel patch has been made.

## 2026-09-01 16:41 UTC — current-image stock repeat 10, s2idle/off-radio

- Run: `20260901T163944Z-dab05e4ee675`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `s2idle`, Wi-Fi off, Bluetooth off, 45-second RTC wake, with no trace
  profile. The boot ID stayed unchanged. This is uninstrumented stock repeat
  10 of 10 for the current-image short-cycle reliability target.
- Physical condition: no cable, charger, dock, hub, or user input; microSD
  remained inserted and mounted. No manual device action was required. SSH
  loss during the sleep interval was expected.
- Exact path: the root-owned detached agent invoked Armada's shipped
  `/usr/libexec/armada/suspend-dispatch` with the run-local s2idle request and
  received return code `0` after `2.250809` seconds.
- Clock/evidence: `CLOCK_BOOTTIME` delta `46.526572` seconds minus
  `CLOCK_MONOTONIC` delta `2.278667` seconds gives signed separation
  `44.247905` seconds, status `observed`. Kernel s2idle entry/exit markers
  were present. `suspend_stats` advanced independently from success `11`, fail
  `0` to success `12`, fail `0`. RTC IRQ 200 advanced by one and its matching
  wakeup source advanced active/event by `+1/+1`.
- Qualcomm/depth: AOSD, CXSD, and scalar DDR count/duration deltas were all
  zero; ADSP count delta was `+180`. The post snapshot had no new error-like
  lines and no failed systemd units. Ten input devices remained present and
  internal `DSI-1` remained connected/enabled.
- Aggregate IRQ observation: IRQ 169 (`ufshcd`) increased by `16,141` and
  mmc0 by `53` between the harness pre/post snapshots. These are not claimed
  as in-suspend rates because the traced run established that the pre/post
  interval includes post-resume collection; mmc0 still does not show the
  historical tens-per-second storm.
- Cleanup: the RTC and temporary controls were restored. The Bluetooth
  power-on command returned a transient failure in the cleanup receipt, but a
  subsequent read-only SSH check confirmed Wi-Fi enabled/up, Bluetooth
  unblocked/powered on, and no hard radio block. Checksum verification covered
  `4,243` files with no mismatches.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T163944Z-dab05e4ee675`.
- Interpretation: repeat 10 is a clean current-image s2idle reliability
  sample. The ten uninstrumented current-image short cycles are complete and
  all ten meet the harness's suspend-success gates; no kernel patch has been
  made.

## 2026-09-01 16:47 UTC — current-stock deep RPMh/AOSS/ICC trace experiment

- Run: `20260901T164522Z-62f40512d811`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `deep`, Wi-Fi off, Bluetooth off, 45-second RTC wake, with the new
  observation-only `rpmh-aoss` private trace profile. The boot ID stayed
  unchanged. No kernel, package, firmware, SDHCI, USB, runtime-PM,
  regulator, interconnect, or power-control value was changed.
- Physical condition: no cable, charger, dock, hub, or user input; microSD
  remained inserted and mounted. No manual device action was required. SSH
  loss during the sleep interval was expected.
- Exact path: the root-owned detached agent armed the RTC, created a private
  tracefs instance, held it stopped during setup, invoked
  `/usr/libexec/armada/suspend-dispatch`, stopped tracing after return, saved
  the post-resume snapshot, and removed the instance. Dispatcher return code
  was `0` and `suspend_success=true`.
- Clock/evidence: `CLOCK_BOOTTIME` delta `45.579892` seconds minus
  `CLOCK_MONOTONIC` delta `2.567737` seconds gives signed separation
  `43.012155` seconds, status `observed`. Kernel deep entry/exit markers were
  present. `suspend_stats` advanced independently from success `12`, fail `0`
  to success `13`, fail `0`. RTC IRQ 200 and its matching wakeup source each
  advanced by one.
- Trace configuration: all four required existing events were available and
  selected: `rpmh:rpmh_send_msg`, `rpmh:rpmh_tx_done`,
  `qcom_aoss:aoss_send`, and `qcom_aoss:aoss_send_done`. Both existing
  interconnect events, `interconnect:icc_set_bw` and
  `interconnect:icc_set_bw_end`, were also selected. The archive preserves
  all `2,812` available-event lines, exact formats and control receipts, a
  `861,385`-byte trace buffer, and per-CPU statistics. The trace instance was
  verified stopped after collection and removed; every selected event was
  disabled during cleanup.
- RPMh/AOSS result: the trace contains `1,347` `rpmh_send_msg` records and
  `658` `rpmh_tx_done` records, with no per-CPU overrun or dropped-event
  indication. RPMh send states were `1,335` `[active]`, `6` `[wake]`, and
  `6` `[sleep]`. At one suspend-transition point, `systemd-sleep` programmed
  an RPMh wake set on `apps_rsc` TCS 5 and a sleep set on TCS 3. The six wake
  writes were addresses `0x50000`, `0x50004`, `0x50010`, `0x50038`, `0x50048`,
  and `0x50044`; the six sleep writes targeted the same addresses with raw
  data retained in `raw/trace/trace.txt`. There were no traced RPMh error
  records. The sleep/wake sequence is evidence that Linux issued the
  firmware-facing set programming; it is not proof that firmware accepted or
  entered the requested hardware states.
- AOSS result: `qcom_aoss:aoss_send` and `qcom_aoss:aoss_send_done` both had
  zero records. This means no AOSS QMP message was emitted during this traced
  window; it does not establish that AOSS firmware or the AOSD residency
  counter is nonfunctional.
- Interconnect result: there were `1,934` `icc_set_bw` and `844`
  `icc_set_bw_end` records. The dominant senders were CPU-frequency governor
  tasks (`sugov`) and suspend/resume worker paths. The raw trace includes
  UFS-specific paths such as `xm_ufs_mem` and `qhs_ufs_mem_cfg` with the UFS
  device `1d84000.ufshc`, plus LLCC/EBI aggregate values; those changes occur
  around the suspend/resume plumbing and are not an in-suspend vote dump.
- Timing qualification: the private instance used the kernel's `[local]`
  trace clock, so its timestamps cover the awake portions of the transition
  while the signed clock pair proves the `43.012155`-second hardware-suspend
  interval. The trace shows the one-time sleep/wake programming and active
  traffic around it, not a direct firmware residency decision log.
- Qualcomm/depth: AOSD, CXSD, and scalar DDR count/duration deltas were all
  zero; ADSP count delta was `+199`. Resume health had no new error-like
  lines or failed systemd units, ten inputs remained present, and `DSI-1`
  remained connected/enabled.
- Cleanup: the RTC and temporary controls were restored; Wi-Fi and Bluetooth
  were restored and a read-only check confirmed enabled/up and
  unblocked/powered-on state. Checksum verification covered `4,305` files
  with no mismatches.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T164522Z-62f40512d811`.
- Interpretation: this run rules out the narrow hypothesis that the current
  Linux path never programs an RPMh sleep set. It does not show a failed
  RPMh transaction, a persistent Linux-visible request stream during the
  actual hardware-suspend interval, or an AOSS message that explains the
  zero AOSD/CXSD/DDR counters. The strongest remaining boundary is the
  firmware-side RPMh/AOP low-power decision and residency reporting, not a
  justified UFS, SDHCI, or kernel patch. No kernel patch has been made.

## Counting correction

The archive contains one additional current-image uninstrumented policy run,
`20260901T154437Z-64317bfc6a02`, which is documented in chronological order
above. Therefore there were eight clean uninstrumented current-image cycles
before the later forensic pause, followed by the three newly labeled stock
samples `20260901T163453Z-c55f8534886a`,
`20260901T163731Z-e91f1b27bc6e`, and
`20260901T163944Z-dab05e4ee675`. The final total is 11 clean stock cycles;
the ten-cycle objective is exceeded. The original run IDs, receipts, and
labels are preserved; this note only corrects the aggregate count.

## 2026-09-01 — read-only supported RPMh/AOP diagnostic inventory

- Source-side inventory: Armada ships `armada-sleep-debug` and the
  `40-armada-wake-ledger` system-sleep hook. The checkout contains no
  Armada-shipped AOP debug executable or package; the external
  `jaewun/qcom-aop-debug` source recorded in `upstream-state.md` is not
  installed or invoked by this lab.
- Device-side inventory: `/usr/bin/armada-sleep-debug` is present and
  executable, `/usr/libexec/armada/suspend-dispatch` is present and
  executable, and `/var/lib/armada/wake-ledger.log` is present as a root-owned
  readable 923-byte file. Its retained entries for the current runs all
  identify RTC IRQ 200 (`pm8xxx_rtc_alarm`) as the wake source.
- Supported evidence already available: `armada-sleep-debug` reports
  qcom-stats, wake IRQs, wake ledger, IRQ deltas, cpuidle, audio, thermal, and
  power-supply state. The lab archives add complete qcom-stats files,
  clock-pair evidence, runtime-PM snapshots, clk/regulator summaries, and
  scoped ftrace buffers.
- Firmware-facing trace availability: the current kernel exposes
  `rpmh:rpmh_send_msg`, `rpmh:rpmh_tx_done`, `qcom_aoss:aoss_send`,
  `qcom_aoss:aoss_send_done`, and interconnect bandwidth tracepoints. The
  completed RPMh run used these existing tracepoints without issuing a
  command or changing a vote. A normal SSH user cannot enumerate the root-only
  debugfs tree; no AOP-specific interface was assumed from that denied view.
- Boundary: the existing supported diagnostics and traces show Linux RPMh
  sleep/wake-set programming but not the firmware's acceptance decision or
  hardware residency result. No undocumented AOP/QMP command, vote forcing,
  kernel patch, or package change is justified yet.

## 2026-09-01 17:07 UTC — read-only root debugfs preflight follow-up

- Scope: this was a read-only inventory after the completed stock and trace
  runs. It did not suspend the Nova, write a debugfs value, alter runtime-PM
  or power controls, unbind SDHCI, or modify the microSD state. No physical
  device action was required; the Nova stayed awake with the microSD mounted
  and no cable attached.
- Receipt: `/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T170713Z-4aa81059d0be.json`.
  The device agent was the current checkout copy with SHA-256
  `6435788de07b8c27b9eb4dd5dcc88b0a99e23c413455f4417ca01946b52d34fa`.
- Current provenance: Armada `20260830.71e45aa`, bootc image digest
  `sha256:cae66b751f6376c7a2da84e7bca7fa81293e9689f7cc9b6bd682ebe83d852c25`,
  ostree checksum
  `c799737eff3f3e4a4299701d5d4ee7099d6ce498941bf6655ae7e158f49de79f`,
  Linux `7.2.0` (`#1 SMP PREEMPT Sun Aug 30 15:09:15 UTC 2026`), model
  `Retroid Pocket Nova`, and `mem_sleep=[s2idle] deep` with
  `/etc/armada/sleep.conf` still `suspend_mode=s2idle`.
- Qualcomm/AOSS controls: reads of
  `qcom_aoss/{prevent_ddr_collapse,prevent_cx_collapse,prevent_aoss_sleep,ddr_frequency_mhz}`
  each returned exit 1 with `Invalid argument`. No write was attempted. They
  are not readable scalar-state files on this build; the error does not say
  whether a collapse-prevention value is set.
- Interconnect: both
  `/sys/kernel/debug/interconnect/interconnect_summary` and
  `interconnect_graph` were readable. Complete payloads were retained in the
  receipt (344 and 565 lines). The awake summary showed nonzero aggregate
  activity including `llcc_mc`/`ebi` average `1471610`, peak `6832000`,
  display-subsystem average `1471610` with peaks `800000` and `400000`, PCIe
  `1c00000.pcie` peak `500000`, `qns_llcc` average `1471610` and peak
  `9600000`, and `qhs_qup2` average `3315` and peak `3200`. UFS
  `1d84000.ufshc` and USB `a600000.usb` rows were present but zero in this
  awake snapshot. These are aggregate/debug views, not in-suspend votes.
- Generic PM domains: `pm_genpd_summary` was readable and retained in full
  (111 lines). Awake state showed `cx on` usage `64`, `mmcx on` usage `64`,
  `ufs_phy_gdsc on` usage `64` with `1d84000.ufshc active` usage `64`, and
  `pcie_0_gdsc on` usage `64` with `1c00000.pcie active` usage `64`.
  `usb3_phy_gdsc` and `usb30_prim_gdsc` were on while `a600000.usb` was
  suspended; `mdss_gdsc` and the display subsystem were on/active; GPU GDSCs,
  EBI, MX/LCX/LMX, and GFX were off. The `17a00000.rsc` device was
  runtime-suspended. These are genpd usage/status values while awake, not
  the missing per-device runtime-PM usage-count field from A/B.
- CMD-DB: `stat` reported `-r-------- root root 0`, but a read succeeded and
  returned the complete 162-line, 5,893-byte dump. It maps the low-power ARC
  resources (`cx.lvl`, `mx.lvl`, `ebi.lvl`, `ddr.lvl`, `mmcx.lvl`, and
  `gfx.lvl`), BCM resources such as `MC0`, `SH0`, `SN0`, `CN0`, `QUP0/1`, and
  `ACV`, and VRM resources including `vrm.aoss`, `vrm.wlan`, `vrm.cx`, and
  `vrm.ebi`. It is a resource descriptor map, not live RPMh vote readback.
  Payload SHA-256:
  `3859059d49db26681cafdac268b6abed10c3003d23370e0dd85c419de4756e0d`.
- Debugfs availability: the root-only inventory retained `qcom_stats`, all
  four `qcom_aoss` nodes, both interconnect views, `pm_genpd_summary`,
  `cmd-db`, `clk_summary`, and `regulator_summary`. The complete file and
  directory listings remain in the receipt; no AOP-specific userspace helper
  was found.
- Correction to the earlier A/B entry: the statement that no interconnect
  view was available was accurate for the A/B archives and their first live
  probe, but is superseded for the current device inventory by this later
  root-readable preflight. It does not retroactively add an in-suspend vote
  capture to A or B. No Linux-visible awake-state value alone explains why
  the named qcom residency counters stayed zero during the clean cycles.

## 2026-09-01 17:28 UTC — read-only CMD-DB/RSC differential and source review

- Scope: no new suspend cycle was run. The completed RPMh archive and current
  read-only preflight were analyzed on the host; no qcom_aoss/QMP control was
  written, no vote was forced, no kernel was built, and no device/package
  state was changed. No physical action was required; the Nova stayed awake
  with the microSD mounted and no cable attached.
- Receipts: RPMh trace
  `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T164522Z-62f40512d811`
  and final schema-2 preflight
  `/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T172752Z-d0cace201f60.json`.
- CMD-DB result: the current full 5,893-byte/162-line dump contains ARC
  v16.0, BCM v16.0, and VRM v1.0 entries. All 38 unique addresses seen in
  both RPMh trace event types mapped successfully. ARC/BCM addresses matched
  exact entries; VRM sub-addresses matched their base resource using the
  documented bits-19:4 rule. The complete mapping and counts are in
  `current-image-forensic-differential.md` under “RPMh address reverse
  mapping and sleep-set contents.”
- Six-set result: the wake/sleep TCS commands are BCM `MC0` (`0x50000`),
  `SH0` (`0x50004`), `SN0` (`0x50010`), `CN0` (`0x50038`), `QUP1`
  (`0x50048`), and `QUP0` (`0x50044`). MC0/SH0 carry valid nonzero sleep
  `vote_y=476`; SN0/CN0/QUP0 carry `commit=1, valid=0`; QUP1 carries
  `commit=0, valid=0` in the sleep word. Wake values decode to valid
  `vote_y=2083` for MC0, `4571` for SH0, and valid `x=y=1` for the four
  remaining BCM commands. This is not malformed-address evidence and is not
  proof that AOP honored the set.
- Immediate ownership: just before the set, the trace shows `a80000.i2c`
  using QUP1, `890000.i2c` using QUP2, and `98c000.i2c` using QUP0. Their
  paths traverse `qns_gemnoc_sf`, `qns_llcc`, `llcc_mc`, and `ebi`; the last
  active ARC writes were `mmcx.lvl=0` and `cx.lvl=0`. The final preflight's
  live summary independently shows LLCC/EBI, configuration, display, and
  PCIe aggregate values, but those values are awake samples and are not
  promoted to in-suspend votes.
- Firmware identity boundary: the preflight identifies `QCS_KAILUA` and
  reports ADSP/CDSP/boot/TZ strings, but AOP-specific identity is blank. The
  only AOP-related device-tree evidence is reserved memory at
  `aop-cmd-db-region@81c60000` and
  `aop-config-merged-region@81c80000`; no AOP/RPMh firmware file was found in
  `/usr/lib/firmware`. The external `qcom-aop-debug` monitor operations are
  therefore not firmware-matched and were not used.
- Upstream/RSC result: reviewed RSC v3 adds accelerator type/name decoding and
  TCS/GIC/status output on transfer timeout. Current Linux master and Armada's
  package do not carry it. It would not produce evidence for this clean run,
  because there was no timeout and it has no successful sleep-set readback or
  AOP acceptance report. The current Armada AOSS debugfs entries are
  write-only, consistent with the observed read-side `EINVAL`.
- Harness result: future phase snapshots now retain raw plus parsed
  `cmd_db`, `interconnect_summary`, `interconnect_graph`, and
  `pm_genpd_summary` structures under schema version 2. Local parser tests and
  validation against the exact preflight passed. No kernel/package patch has
  been built or deployed.
- Conclusion: branch 1 (malformed/unknown set) is not supported; branch 2
  (persistent Linux vote) remains unproven because the low-power interval has
  no direct vote snapshot; branch 3 (firmware-side decline) is the strongest
  unresolved boundary; branch 4 is reduced by the source-checked qcom-stats
  semantics but not fully eliminated. The next smallest observation is a
  successful-path, read-only RSC TCS snapshot around the sleep-set handoff,
  using reviewed CMD-DB helpers. It is a future diagnostic design, not a
  patch/build/deployment decision.
- Archived kernel/journal logs add no AOP firmware version, acceptance, or
  low-power-decision breadcrumb. They do show RSC, RPMh regulator, power
  controller, BCM voter, AOSS-QMP, and CMD-DB PM callbacks returning zero;
  this is Linux PM completion evidence, not proof of firmware state entry.

## 2026-09-01 — source-only successful-path RSC hook review

- The v7.2 RSC implementation makes `rpmh_rsc_write_ctrl_data()` the
  non-triggering sleep/wake path. It allocates a sleep/wake TCS slot and calls
  `__tcs_buffer_write()`, which writes the command registers and emits the
  existing `rpmh_send_msg` tracepoint. Firmware is responsible for triggering
  those sets when the execution environment reaches the deepest low-power
  mode.
- The completed trace already records state, TCS number, command number,
  address, data, message ID, and wait/complete flag. It does not record the
  selected TCS's post-write `CMD_ENABLE`, controller control/status, per-command
  status/response, or IRQ status. The active-transfer busy check is separate
  and cannot prove sleep-set acceptance.
- Source-only conclusion: the minimal future diagnostic is a read-only
  post-buffer-write TCS-register snapshot for the sleep/wake slots, decoded
  with the reviewed CMD-DB helpers. It must not trigger/rewrite the TCS or
  send any QMP/AOSS message. No patch was created, built, or deployed.

## 2026-09-01 17:45 UTC — live RSC boundary and host consistency check

- Scope: no suspend cycle was run and no device state was changed. The live
  check read only sysfs and device-tree metadata; the host check re-parsed the
  retained RPMh trace and CMD-DB receipt. No MMIO was read, no qcom_aoss/QMP
  control was written, no vote was forced, and no kernel/package patch was
  created, built, or deployed. No physical action was required; the Nova
  remained awake with the microSD mounted and no cable attached.
- Receipt: the fresh root preflight is
  `/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T174854Z-45d0702ef09c.json`;
  its device-agent SHA-256 is
  `7dd127a2e532764b039c1bd051a85a25a6b9d99407b760b78e8c55931fe52b1b`.
- Live RSC metadata: `apps_rsc` is compatible with `qcom,rpmh-rsc` at
  `/soc@0/rsc@17a00000`. The device tree exposes four `drv-0` through `drv-3`
  windows at `0x17a00000`, `0x17a10000`, `0x17a20000`, and `0x17a30000`, each
  `0x100` bytes; `qcom,drv-id=2`, `qcom,tcs-offset=0xd0000`, and
  `qcom,tcs-config` rows `2,3,0,2` and `1,2,3,0`. Sysfs exposes no readable
  RSC resource/register/status/TCS view, so an unpatched observation is not
  available.
- Host consistency result: re-parsing
  `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T164522Z-62f40512d811/device/raw/trace/trace.txt`
  against the CMD-DB dump in
  `/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T172752Z-d0cace201f60.json`
  found 38 unique trace addresses and zero unresolved addresses. The six
  transition addresses and all VRM sub-addresses resolve exactly as recorded
  in the forensic result document.
- The same receipt now contains parsed structures, not only raw text: CMD-DB
  `152` resources, interconnect `127` aggregates and `214` consumers, graph
  `127` nodes and `135` edges, and genpd `48` domains and `50` device rows.
- Verification: `py_compile`, both harness self-tests, and `git diff --check`
  passed. This is a tooling/source verification, not new device evidence.
- Decision unchanged: the smallest next diagnostic remains a successful-path
  in-driver read-only RSC/TCS snapshot immediately after Linux programs the
  sleep/wake buffers and again after resume. It must use `readl` only and
  capture command/control/status, response, and IRQ state; no trigger, write,
  QMP, forced vote, or AOP monitor operation is allowed.

## 2026-09-01 17:50 UTC — upstream diagnostic freshness recheck

- The freshness check found no newer successful-path RSC diagnostic revision.
  The latest reviewed Qualcomm series remains v3, posted 2026-08-12; its RSC
  patch is explicitly timeout-triggered and the 2026-08-17 maintainer reply
  contained only minor review comments. Qualcomm's kernel PR #907 was in fact
  merged on 2026-08-20 into `qualcomm-linux/kernel:qcom-6.18.y`, with RSC
  commit `403d2a6ac9213a7454fa31744f8ad6089d368cd8` and CMD-DB commits
  `946390ea27648ac0e76ecd1950405f1ce3ed5640` and
  `b98e95ae006480d4d6c384725beede55ed3092d7`. The live Torvalds Linux master
  and Armada package still lack those helpers.
- A direct remote check recorded Qualcomm `qcom-6.18.y` at
  `681580d43f243496bce246326979dddabfb5d8bd`; its current raw
  `rpmh-rsc.c` and `cmd-db.c` contain `rpmh_rsc_debug()`,
  `cmd_db_read_name()`, and `cmd_db_hw_type_str()`. This confirms the patch is
  present in that vendor branch, while not making it part of the Nova image.
- Armada's current package script fetches the `linux-7.2` kernel.org stable
  tarball and applies only `kernel/patches/series`, so the Qualcomm vendor
  branch cannot be substituted as the Nova build source. A line-level source
  comparison found the merged diagnostic hunks' expected contexts in the
  Linux v7.2 RSC/RPMh files, with unrelated allocator differences in
  `rpmh.c`; this is porting evidence only, not a patch application check.
- The merged Qualcomm implementation remains timeout-only: it prints TCS
  command/control/status and GIC state only when a blocking RPMh operation
  times out. It does not provide a successful sleep-set snapshot or AOP
  acceptance result. This is source-status evidence only, not device evidence.
  No device command, control, suspend cycle, patch, build, or deployment was
  performed for this check.
- Decision unchanged: use the merged reviewed series as the decoding/reference
  starting point, and design a separate successful-path read-only snapshot for
  Nova if that experiment is later authorized.

## 2026-09-01 17:58 UTC — exact RSC TCS allocation for future observation

- Source inspection confirmed the running device-tree `qcom,tcs-config`
  sequence is `(ACTIVE_TCS,3), (SLEEP_TCS,2), (WAKE_TCS,2),
  (CONTROL_TCS,0)`, using the v7.2 binding constants. The resulting global
  slots are ACTIVE `0--2`, SLEEP `3--4`, and WAKE `5--6`; the completed RPMh
  trace's final sleep TCS `3` and wake TCS `5` match this allocation.
- The merged Qualcomm `rpmh_rsc_debug()` source iterates only
  `drv->tcs_in_use`, the active-transfer bookkeeping bitmap. Sleep/wake
  control writes instead reserve `tcs->slots`, so simply carrying that helper
  into Armada would not inspect the clean-run sleep TCS 3 or wake TCS 5.
- The future observation must enumerate the sleep/wake group slots explicitly,
  use the driver's version-selected register-offset table, and read only
  `CMD_ENABLE`, `CONTROL`, `STATUS`, global `IRQ_STATUS`, and enabled-command
  `MSGID`, `ADDR`, `DATA`, `STATUS`, and `RESP_DATA`. This refines the design;
  it does not authorize a patch, build, deployment, TCS trigger, IRQ clear,
  QMP/AOSS operation, or vote change.

## 2026-09-01 18:03 UTC — supported package compatibility audit

- The current Armada package source was inspected read-only. Its kernel build
  script fetches the kernel.org stable `linux-7.2` tarball and applies the
  package-local `kernel/patches/series`; the current series contains no RSC or
  CMD-DB diagnostic entry.
- The merged Qualcomm branch was compared line-by-line with the v7.2 RPMh
  source. The expected insertion contexts are present in `rpmh-rsc.c`,
  `rpmh-internal.h`, and `rpmh.c`; `rpmh.c` also has unrelated allocator
  differences. This establishes a plausible reviewed porting base, not a
  successful patch application or build.
- No source patch was created or applied, and no package, kernel, boot, device,
  QMP/AOSS, or vote state changed. No physical action was required. The next
  allowed implementation step remains gated by the explicit no-build/no-patch
  instruction.

## 2026-09-01 21:03 UTC — observation-only diagnostic package built

- The user-authorized diagnostic build completed through the Armada package
  checkout. Package base was `2c93e73cbe1bcf4d443495e94fbaa5e7a8cf7141` on
  branch `feat/sm8550-rsc-observation`; kernel source remained the package's
  kernel.org stable `linux-7.2` input. No kernel source, firmware, ABL, boot,
  device, QMP/AOSS, or power-control state was changed on the Nova.
- The final build used the arm64 Fedora container
  `registry.fedoraproject.org/fedora@sha256:0c6072366ebf8ea1c8c0f3a118aad3e9a9247d3065d499e54d62968f69351966`,
  applied all `136` series patches, passed config validation, linked Image,
  built DTBs/modules, and exited 0. `CONFIG_QCOM_RPMH_SUCCESS_DEBUG=y` and
  `CONFIG_DEBUG_INFO_BTF=y` were retained. A prior Docker-store I/O failure
  during module BTF finalization was preserved as a build observation; it was
  not treated as a source failure. The ccache mount was removed before the
  successful retry and its generated files were cleaned.
- Artifact: `/Users/kurt/Developer/armada-packages-suspend-lab/kernel/out/armada-kernel-7.2.0.tar.zst`;
  SHA-256 `3fc078ffc04e59471538269abe442fab907f3c792a0b42c048d816715af72cc1`.
  The embedded `vmlinuz` SHA-256 is
  `5d7348afe15a71ef5918c47eea9d3d995f88d3e157bd65b6907eed352e71d867`.
  `zstd -t`, checksum verification, extraction, tar listing, and required Nova
  DTB/module entry checks passed. Embedded metadata reports aarch64 build,
  136 applied patches, 20 DTBs, and Armada repackaging.
- The source package remains uncommitted and undeployed at this notebook point;
  the main checkout has the deployment-preparation document and the package
  checkout has the patch/config/series changes. Generated `kernel/out` is kept
  locally for delivery preparation and is not source history.

## 2026-09-01 21:03 UTC — live supported-update gate rechecked

- Read-only SSH inventory to `retroid-nova` (`192.168.0.20`) confirmed the
  expected Armada userspace: `/usr/lib/armada/version` is `20260830.71e45aa`,
  the running kernel is `7.2.0`, the booted origin is the signed Armada
  `testing` image, and the Nova DT/RSC identity remains unchanged. The OS
  identifies as Fedora 44, which is the Armada bootc base and is not evidence
  of a wrong host.
- The supported update entry points are `/usr/bin/steamos-update` and
  `/usr/libexec/armada/armada-update`; the latter is not on the normal user's
  `PATH`. Root is required for `bootc status` and update application. The
  current account's generic `sudo -n` check requires the installed default
  password, while Armada's narrow passwordless rules cover only selected
  management operations. No update, reboot, kernel/boot-file write, or lab run
  was started during this gate.
- The raw kernel tarball is therefore not yet a deployable device input. It
  must be wrapped into a signed Armada bootc image and applied through the
  shipped update workflow. If a custom image cannot satisfy the device's
  signature policy, deployment will stop rather than bypassing that policy.
- A first post-boot direct tracefs probe reported `absent`, but that probe ran
  as the normal `armada` user and tracefs denied directory/file reads. The
  kernel config is root-readable and reports `CONFIG_QCOM_RPMH_SUCCESS_DEBUG=y`.
  The harness is being refreshed to capture the root-only complete
  `/sys/kernel/tracing/available_events` file in the next preflight; the direct
  unprivileged result is not evidence that the event is missing.

## Next controlled step

The ten-cycle stock reliability objective is exceeded: 11 uninstrumented
current-image cycles completed cleanly, and the two scoped read-only trace
experiments are complete. The observation-only successful-path RSC/TCS kernel
is now built and source-ready but not deployed. First publish the source/docs
to the user's fork(s), then complete the supported signed-image assembly and
update gate. After boot verification, run exactly one `rsc-success` deep cycle
with RTC wake, parse the successful-path snapshots, and classify the four
outstanding branches before selecting any functional fix. Remaining blind
repetitions stay deferred, not cancelled.

## 2026-09-02 00:12 UTC — corrected diagnostic boot and RSC observation

- Root preflight receipt
  `/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260902T001225Z-bfa21e4b672a.json`
  was rerun after the diagnostic image correction. The target was the current
  Nova image, kernel `7.2.0`, package commit `f595f0f`, and the image contained
  `CONFIG_QCOM_COMMAND_DB=y`, `CONFIG_QCOM_RPMH_SUCCESS_DEBUG=y`, and
  `CONFIG_DEBUG_INFO_BTF=y`. The root-readable available-event inventory was
  captured in full. The four qcom_aoss debugfs controls still rejected reads
  with `EINVAL`; no write was attempted.
- The full-image Docker build failure and each device-local image attempt remain
  preserved. The full build failed in standard Proton extraction with Docker
  VM/ext4 storage I/O (`metadata_v2.db: input/output error` and failed
  unwritten extents), not with a source/compiler error. The first three local
  layer attempts (`pmcb`, `pmcb2`, `pmcb3`) rolled back for inherited metadata,
  missing/incorrect initramfs, or an overlong BLS command line. The successful
  `pmcb4` layer used the exact Armada initramfs modules and booted as
  `localhost/armada-rsc:20260901-pmcb4`; its image digest is
  `sha256:c31703b2c4d6f8273a10f017cd3951580458fc946afa6ca98a131c747bf77d76`
  and its version is `20260901.rsc-f595f0f-pmcb`. No loose kernel or boot-file
  replacement was used.
- Run `20260902T001240Z-f80f54f6b742`, label
  `sm8550-rsc-success-corrected-deep`, exercised Armada's
  `/usr/libexec/armada/suspend-dispatch` through the autonomous root-owned
  agent with an independently armed RTC wake. It resumed cleanly with boot ID
  unchanged, `PM: suspend entry (deep)`/exit markers, suspend-stat success
  increment, and no new error-like log lines. The clock deltas were boottime
  `45.864759 s`, monotonic `2.629642 s`, separation `43.235117 s`, status
  `observed`.
- Its raw successful-path RSC archive
  `device/derived/rpmh-rsc-snapshots.json` contains 35 events: 17 pre-suspend
  and 18 post-resume, with 14 sleep and 14 wake records. Sleep TCS 3 contains
  `MC0=0x600003b8`, `SH0=0x600003b8`, `SN0=0x40000000`,
  `CN0=0x40000000`, `QUP1=0`, and `QUP0=0x40000000`; wake TCS 5 contains
  `MC0=0x60000823`, `SH0=0x600011db`, `SN0=0x60004001`,
  `CN0=0x60004001`, `QUP1=0x20004001`, and `QUP0=0x60004001`.
  All six addresses reverse-mapped to BCM resources (`MC0`, `SH0`, `SN0`,
  `CN0`, `QUP1`, `QUP0`). The involved TCSes reported `cmd_enable=0x3f`,
  `tcs_status=1`, `tcs_in_use=0`, `irq_status=0`, `cmd_status=0`, and zero
  response data. Post-resume active TCS activity was normal concurrent RPMh
  traffic, not evidence of sleep-set rejection.
- The current run's raw qcom_stats preserved complete pre/post files. AOSD,
  CXSD, and scalar DDR remained zero, while the independent `ddr_stats`
  `0xd0` duration changed from `1,956,015,136` to `2,939,234,367` ticks. This
  confirms that the qcom_stats interface is not globally frozen, but it does
  not by itself establish the platform meaning of the zero scalar records.

## 2026-09-02 00:20 UTC — UFS trace filter correction receipt

- Run `20260902T002021Z-a66419f43ef9`, label `sm8550-ufs-irq-deep`, completed
  cleanly as a deep RTC cycle: boottime delta `46.018452 s`, monotonic delta
  `2.186243 s`, separation `43.832210 s`, and unchanged boot ID. It is retained
  as a partial/invalid experiment because the then-current harness hard-coded
  IRQ 169. On this boot IRQ 169 is `mmc0`; the live UFS `ufshcd` IRQ is 170.
  Its UFS command trace is still useful transition evidence, but its IRQ filter
  cannot answer the UFS IRQ question and is not reclassified as valid.
- The harness was corrected to resolve the `ufshcd` row in `/proc/interrupts`
  before configuring the trace, to record the resolved IRQ in `meta/trace.json`,
  and to refuse the run if no live UFS IRQ exists. Host compile and self-test
  passed. The failed receipt and all raw files were preserved.

## 2026-09-02 00:27 UTC — corrected live-UFS deep differential

- Run `20260902T002708Z-4e8666167435`, label
  `sm8550-ufs-irq-deep-corrected`, used the corrected dynamic resolver and
  recorded `trace_irq_number=170`. It completed cleanly through
  `suspend-dispatch`: boottime delta `45.731723 s`, monotonic delta
  `2.363174 s`, separation `43.368549 s`, status `observed`, unchanged boot ID,
  RTC wake, successful suspend stats, and no failed systemd units.
- The raw trace contains 501 matching IRQ-170 entry/exit pairs, 1,122
  `ufshcd_command` events, 126 UIC events, and 7 hibern8 profile events. The
  full `/proc/interrupts` delta has UFS IRQ 170 `+11,814` and `mmc0` IRQ 169
  `+47`; the naive ratios over the 43.368549 separated seconds are 272.4/s
  and 1.08/s, respectively, but these are not in-suspend rates. The ftrace
  events are clustered around the Linux suspend/resume transition: 464 IRQ
  entries and 1,084 commands precede timekeeping resume, while 37 IRQ entries
  and 38 commands follow it. There is no UFS activity during the actual
  43.368-second deep-sleep interval. Kernel UFS suspend/noirq and resume
  callbacks completed without error.
- This rejects the historical microSD/SDHCI IRQ-storm hypothesis on this Nova
  and provides no evidence for a UFS or SDHCI functional patch. The remaining
  high-value boundary is a read-only observation of the RPMh/AOP decision or a
  precise validation of the platform-specific qcom_stats semantics. No vote,
  qcom_aoss/QMP control, or firmware interface was written.

## 2026-09-02 00:43 UTC — DWC3 control pair

- Control run `20260902T004312Z-8ddc7114e866`, label
  `sm8550-dwc3-control-deep`, used the current corrected diagnostic image with
  no functional kernel change. It completed cleanly through Armada's
  `suspend-dispatch`: boottime delta `45.595271 s`, monotonic delta
  `2.545525 s`, signed separation `43.049745 s`, unchanged boot ID, deep
  suspend markers, successful suspend stats, expected RTC wake, and no failed
  units or new error-like lines. The top interrupt deltas were UFS IRQ 170
  `+15,737` and `mmc0` IRQ 169 `+52`.
- Control run `20260902T004451Z-3059aa2a8a40`, label
  `sm8550-dwc3-control-s2idle`, likewise completed cleanly after the SSH
  control connection timed out and the autonomous on-device agent was allowed
  to finish. Boottime delta `46.176895 s`, monotonic delta `2.570843 s`, signed
  separation `43.606052 s`, unchanged boot ID, s2idle marker, successful
  suspend stats, expected RTC wake, and no failed units or new error-like
  lines were observed. The top interrupt deltas were UFS IRQ 170 `+9,069` and
  `mmc0` IRQ 169 `+52`. The raw device archive and recovery receipt are
  preserved; the SSH timeout is not classified as a suspend failure.
- These matched controls provide the pre-change deep and s2idle references for
  the DWC3 skip-PHY-init candidate. The candidate is one variable only: the
  reviewed Qualcomm software-node property that prevents the USB core from
  taking an extra PHY init reference. No regulator, PCIe, RPMh, SDHCI, UFS,
  DT, runtime-PM, autosuspend, or other functional change is included.

## 2026-09-02 01:05–01:37 UTC — candidate build infrastructure receipt

- The first local candidate build used Linux 7.2, the Armada package commit
  base `f595f0f`, all 137 patch-series entries including
  `0910-usb-dwc3-qcom-skip-phy.patch`, the existing diagnostic RSC patch, the
  unchanged config, and the pinned Fedora builder input
  `registry.fedoraproject.org/fedora@sha256:0c6072366ebf8ea1c8c0f3a118aad3e9a9247d3065d499e54d62968f69351966`. The
  candidate-specific `drivers/usb/dwc3/dwc3-qcom.o` compiled successfully and
  all 137 patches applied; the build failed only in the final module stage
  with `ccache: ... /usr/bin/gcc failed: Input/output error`, followed by
  Docker containerd metadata `input/output error`. No candidate archive was
  produced and the previously verified `kernel/out` artifact was not used for
  deployment.
- At the failure, the host had only about `408 MiB` free. The bounded recovery
  removed the exact disposable `armada-kernel-build-cache` created by this
  attempt and two stale, unregistered Podman machine base-image cache files,
  recovering about 3.8 GiB. Docker was restarted once; metadata/content-store
  operations still returned I/O errors, so Docker repair stopped. The failed
  build container was prevented from running further by stopping Docker; no
  source checkout, Git state, run archive, verified kernel artifact, or device
  rollback image was deleted.
- Candidate commit `5aa8e4c` (`feat(kernel): skip qcom dwc3 usb-core phy init`)
  was pushed to the fork. A clean native arm64 GitHub workflow run
  `33580043873` was dispatched from that exact commit using the package's
  existing workflow and pinned builder. The run is the clean disposable build
  boundary; no local Docker retry is permitted while its metadata remains
  corrupt.

## 2026-09-02 02:21–02:32 UTC — DWC3 skip-PHY-init candidate A/B

- The clean workflow completed successfully in 41m2s. The published carrier
  digest was
  `sha256:80d2ae7b5664c723cffcd477db784ea3a939f209bb9c1d0bdad2f1dc643a525e`.
  The extracted archive
  `sm8550-suspend-lab-runs/artifacts/dwc3-5aa8e4cf/carrier/kernel/armada-kernel-7.2.0.tar.zst`
  passed SHA-256 (`dbe3f05b967374d5c4a7386ebfc22362fa107fa7b58f7653cc314a70a3fd5fe3`),
  checksum-file, zstd, tar-entry, Nova-DTB, and source-metadata checks. It
  reports Linux 7.2 and 137 applied Armada patches. The carrier was retrieved
  with `skopeo`, leaving the corrupt local Docker store unused.
- Pre-deployment preflight
  `preflight-20260902T0220Z-before-dwc3-deploy.json` recorded the diagnostic
  `pmcb4` image and 35 GiB free on `/var/home`. The archive and checksum were
  copied to `/var/home/armada/sm8550-dwc3`; the device verified the checksum.
  A new local OCI layer was built from `localhost/armada-rsc:20260901` with
  tag `localhost/armada-dwc3:20260902-5aa8e4c`, image digest
  `sha256:32e8f1f3b8c89443c5201258136ab4d0a45afaf53af7e091d72a2e4ad8184054`,
  version `20260902.dwc3-5aa8e4c`, and OSTree commit
  `e1851199a26f178aaafc0e352df000371226ed2abb12414f635f5feacfd133fc`.
  `bootc switch --transport containers-storage --download-only` staged it;
  `bootc switch --from-downloaded --apply` activated it on the next boot.
- Candidate run `20260902T022513Z-59a89502b494`, label
  `sm8550-dwc3-candidate-deep`, completed cleanly: boottime delta
  `46.669971 s`, monotonic delta `2.579147 s`, separation `44.090824 s`
  (`observed`), deep markers, unchanged boot ID, suspend success `+1`, RTC
  IRQ/source wake, no failed units, and no new suspend error. Full qcom_stats,
  runtime-PM, clocks, regulators, genpd, interconnect graph/summary, raw
  traces, callback logs, wake sources, and power-supply snapshots are in the
  run archive.
- Against control `20260902T004312Z-8ddc7114e866`, `a600000.usb` remained
  suspended before dispatch and active after resume; `88e8000.phy` remained
  active with `power/control=on`; `usb3_phy_gdsc` stayed on and
  `usb30_prim_gdsc` showed the same suspended/active transition with usage 0.
  Filtered USB clock lines, USB regulator lines, USB genpd lines, and
  post-resume DWC3 interconnect votes were identical. DWC3/combo-PHY callback
  order and return status were identical, including successful
  `dwc3_qcom_pm_resume`.
- AOSD, CXSD, and scalar DDR stayed zero in both runs. The independent DDR
  `0xd0` duration delta was `986707923` ticks in the control and `995380207`
  ticks in the candidate, comparable and not used as a deep-residency claim.
  Battery metrics were unavailable (`battery_metrics={}`); no short-run power
  improvement is claimed. Unchanged Qualcomm counters are not, by themselves,
  evidence against this patch, but there was no observable USB/PHY mechanism,
  relevant ownership, residency, or power improvement either.
- This is a negative result for the cable-free workload. Candidate s2idle was
  not run under the predeclared gate. `bootc rollback --apply` restored the
  known diagnostic image; post-rollback preflight
  `preflight-20260902T023217Z-1381e03a5c7d` confirms
  `localhost/armada-rsc:20260901-pmcb4`, version
  `20260901.rsc-f595f0f-pmcb`, and kernel `7.2.0`. Full comparison and raw
  paths are documented in `dwc3-skip-phy-ab.md`.

## 2026-09-02 02:40–02:45 UTC — Steam and real-game workload validation

- Run `20260902T024026Z-cf3ff260ae4e`, label
  `sm8550-workload-steam-ui-deep`, exercised the live Steam/gamescope UI on
  the restored diagnostic image with radios temporarily off and no external
  cable. It completed cleanly in observed deep mode: boottime delta
  `46.662533 s`, monotonic delta `2.340043 s`, separation `44.322490 s`,
  unchanged boot ID, RTC wake, suspend success `+1`, no failed units, and no
  suspend error. Steam/gamescope, PipeWire/WirePlumber, DSI-1, and the input
  inventory remained present after resume. ALSA reported no soundcards, so no
  audio playback gate was claimed.
- Geometry Wars (AppID 8400) was launched from the installed Steam library
  under Proton/pressure-vessel. Steam logged `Fully Installed,App Running`,
  with the Wine executable and `GeometryWars.exe` present. Run
  `20260902T024238Z-e1dab9c98808`, label
  `sm8550-workload-geometry-wars-deep`, then completed cleanly in deep mode:
  boottime delta `47.077548 s`, monotonic delta `2.214649 s`, separation
  `44.862898 s`, unchanged boot ID, RTC wake, suspend success `+1`, and no
  failed units. The Geometry Wars process tree, Steam service, PipeWire
  processes, DSI-1 connected/enabled state, and eight input devices were still
  present after resume.
- Run `20260902T024422Z-254284611e94`, label
  `sm8550-workload-geometry-wars-s2idle`, repeated the live game workload in
  s2idle. It completed cleanly: boottime delta `46.887604 s`, monotonic delta
  `2.517194 s`, separation `44.370410 s`, s2idle markers, unchanged boot ID,
  RTC wake, suspend success `+1`, and no failed units. The Geometry Wars
  process tree and Steam session remained present; DSI-1 and all eight input
  devices remained enumerated. The run's s2idle CPU-sleep deltas were small
  but nonzero on every CPU, and are retained as independent evidence.
- These are real workload/process and suspend-health passes, not a visual or
  input acceptance claim. SSH has no trustworthy display-surface readback, and
  the gamepad's physical event node is permission-restricted while the
  virtual mapper is readable. The remaining manual gate is to look at the Nova
  after resume and confirm that Geometry Wars is visibly rendered, then tap
  the screen or press one gamepad button and confirm the game responds. Until
  that happens, gameplay/input recovery remains unverified. Full raw archives,
  qcom_stats, PM, clock, IRQ, RSC, display, input, audio, and log snapshots
  are retained under each run ID.
- A read-only visual-readback attempt after the s2idle game run used the
  installed ffmpeg. X11 captures from both `DISPLAY=:0` and `DISPLAY=:1` were
  valid 1280x960 PNGs but black except for the cursor. KMS capture failed with
  `No handle set on framebuffer`, and the fbdev path rejected the input option;
  no privileged capture or compositor change was attempted. The frames and
  exact hashes are preserved under
  `20260902T024422Z-254284611e94/functional/README.md`. This leaves the
  visible-surface and actual touch/gamepad-response gates explicitly pending
  manual confirmation.
- The user then confirmed that the real Nova was visibly showing the game and
  that the framebuffer/X11 captures were not representative of the handheld's
  visible output. This confirms rendered game presence by direct device
  observation, but does not claim a measured touch/gamepad event response.
  The device-side game launch log was copied into
  `20260902T024238Z-e1dab9c98808/functional/geometry-wars-launch.log` with
  SHA-256 `8a363c42495bd4246088e47093ae2deb9a7f9fb406a9a1ede1144e93f98e6140`.
- A live read-only post-run check also captured
  `dwc3-qcom a600000.usb: port-1 HS-PHY not in L2` at kernel timestamp
  `689.444032`, about 5.8 seconds after the s2idle run's `PM: suspend exit`
  at `683.615414`. The warning was also visible in prior persistent logs, so
  it is an important DWC3 resume symptom but not yet a causal regression or a
  justification for another patch. A later persistent log recorded
  `GeometryWars.exe` SIGSEGV after the run; because it was not timestamped to
  the suspend boundary, it is retained as a workload-health observation, not
  attributed to suspend. The complete command output and screenshots/raw
  frames remain preserved under the run archive.

## 2026-09-02 02:53–03:00 UTC — upstream restore and device cleanup

- The user confirmed that the real Nova visibly showed the game; the host-side
  framebuffer/X11 captures were not representative of the handheld display.
  This direct observation is retained separately from the automated process
  and display-inventory evidence.
- A fresh preflight recorded the lab image before restoration:
  `preflight-20260902T025315Z-4720de683f51`. Armada's supported channel selector
  was set to `main` using `/usr/bin/steamos-select-branch main`. The supported
  `/usr/bin/steamos-update check` resolved `20260830.71e45aa`; stage/apply were
  performed through the supported update path, not by copying kernel or boot
  files.
- Post-update inspection confirms the Nova is booted into
  `ghcr.io/armada-os/armada:testing` (the Armada `main` channel target), version
  `20260830.71e45aa`, kernel `7.2.0`, image digest
  `sha256:cae66b751f6376c7a2da84e7bca7fa81293e9689f7cc9b6bd682ebe83d852c25`,
  with no staged deployment. The prior diagnostic deployment was only the
  rollback entry at that point.
- After upstream boot verification, the exact lab images/tags and unreferenced
  layers were removed: `armada-dwc3:20260902-5aa8e4c`,
  `armada-rsc:20260901`, `pmcb`, `pmcb2`, `pmcb3`, and `pmcb4`, plus the
  dangling lab image. The exact device staging/workload directories
  `/var/home/armada/sm8550-dwc3`, `/var/home/armada/sm8550-rsc-pmcb`, and
  `/var/home/armada/sm8550-workload` were removed after relevant evidence was
  copied to host archives. `/var/home` free space increased from 32 GiB to
  40 GiB. Steam/user data and installed games were not removed.
- The temporary `/etc/sudoers.d/90-sm8550-suspend-lab` rule was removed. A
  read-only verification confirms the file is absent and `sudo -n true` fails;
  no generic passwordless sudo remains from the lab. The empty
  `/var/lib/sm8550-suspend-lab` path is retained as a zero-byte system path.
- All host source checkouts, Git history, verified kernel artifacts, raw run
  archives, failed-run receipts, and documentation remain preserved. The
  cleanup is complete without deleting experiment evidence or user content.

## Iteration rule

The quickest safe kernel loop is now documented in
`diagnostic-kernel-build-and-deployment-prep.md` and implemented by
`device-kernel-layer.Containerfile`: build the verified package artifact,
transfer it with its checksum, build a uniquely tagged OCI layer on the device,
regenerate the Armada initramfs, then use bootc's downloaded-image apply flow.
Every layer has a distinct tag and a preserved rollback receipt. This rule is
also stored in the persistent Codex memory note for future sessions.

## 2026-09-18 01:27 UTC — dedicated AOP partitions found

- The fresh root preflight
  `/private/tmp/sm8550-after-btoff-preflight/preflight-20260918T012750Z-16dbf3a7045d.json`
  lists two dedicated UFS partitions: `/dev/sde9` (`aop_a`) and `/dev/sde28`
  (`aop_b`). Sysfs reports 1024 sectors (512 KiB) for each. Both are readable
  only by root/the `disk` group, so the normal SSH account cannot hash them
  directly. `/proc/cmdline` has no `androidboot.slot_suffix` or `boot_slot`,
  so the active slot is not identified yet.
- This is a concrete read-only route to fingerprint the installed AOP images,
  after prior searches found no AOP image/version under `/usr/lib/firmware`,
  `/sys/firmware`, or `qcom_socinfo`. Hashing both raw partitions is useful,
  but their hashes cannot be compared directly with the community
  `qcom-aop-debug` example hash unless the partition bytes are exactly that
  complete image. The public example is a 32-bit ARM ELF for other SM8550
  handhelds; its notes do not establish Nova's partition format or slot.
- Next inspect both partitions read-only, preserving a raw SHA-256, byte size,
  `file`/ELF metadata and any format-derived embedded-image boundary. Do not
  trim padding or strip a presumed MBN wrapper by guesswork. First find a
  trustworthy active-slot indicator; until then, treat both partition
  fingerprints as installed-slot inventory only, not proof of the running AOP
  build. No partition bytes have been read or changed yet.

### 2026-09-18 01:51 UTC — both AOP partition hashes match the published SM8550 ELF

- A fresh preflight using the updated, read-only lab inventory completed on
  boot ID `7dc5e1e8-3b94-4479-8b16-c297c8f1c7ba`, image
  `20260915.feca679`, kernel `7.2.3`. Its receipt is
  `/private/tmp/sm8550-aop-partition-preflight/preflight-20260918T015158Z-27830d9c4849.json`.
- `/dev/disk/by-partlabel/aop_a` resolves to `/dev/sde9`; `_b` resolves to
  `/dev/sde28`. Each is exactly 524,288 bytes (512 KiB), and each full raw
  partition SHA-256 is
  `6aceb38f5ef10663ac5c29ffc4e9ee27b6339e8746ff3490485f8cf2640ef687`.
  Both start with `7f 45 4c 46` (ELF magic). This exactly matches the 32-bit
  ARM ELF hash published by `qcom-aop-debug` for its SM8550 handheld example;
  there is no wrapper or partition-padding mismatch in these bytes. Because
  both A/B images are identical, the unresolved active-slot selector does not
  leave uncertainty about which AOP build either slot would supply. This is a
  firmware identity match, not yet proof of runtime acceptance or residency.
- The lab helper edit only added the root preflight's fixed hash/metadata read;
  the refreshed helper was installed under `/var/lib/sm8550-suspend-lab`.
  Neither partition nor system image was written. The full receipt preserves
  commands and output; no suspend cycle was run for this inventory.
- The exact firmware match removes the earlier “unknown AOP build” blocker.
  Next review the published monitor request and decoder against this exact
  image, then decide whether one read-only AOP low-power monitor query is
  sufficiently supported on Nova. The request's QMP transport ACK alone is
  still not proof that a valid report was produced or correctly decoded; do
  not infer a blocker or residency from an ACK alone.

### 2026-09-18 01:55 UTC — matching firmware has a tested CXPC query, but no Nova interface

- The public `qcom-aop-debug` record ties the exact matched hash to an AOP
  image from SM8550 AYN Thor / Retroid Pocket 6. It says the compact request
  `{class:lpm_mon,type:cxpc,dur:2000,flush:1,log_once:1}` was accepted by that
  firmware and produced an awake/idle CXPC row. The project labels it low risk,
  but still firmware-specific. This is strong support for the request syntax
  on Nova's installed AOP image; it is not a Nova runtime result.
- The same project warns that its decoder assumes a Kalama-family monitor
  sink at QMP message-RAM offset `0x20000` and a 22-driver row layout, and says
  the address and layout must be validated before porting. Its experimental
  kernel patch only enables debugfs endpoints for `ayn,thor` and
  `retroidpocket,rp6`, so Nova has no `thor_lpm_mon_cxpc`, raw dump, or raw QMP
  sender. Stock Linux describes `qmp_send()` as a kernel API and does not
  expose an unrestricted userspace sender. The running Nova has `qcom_aoss`
  built into the kernel; no unloadable module shortcut exists.
- The published CXPC query is a bounded diagnostic sample, not a power-vote
  change. “Read-only” does not mean no state writes: it sends a QMP request
  and asks AOP to write a transient MSGRAM log, so it may slightly perturb
  sampled timing. The guidance is one known request while fully awake,
  preserving raw output and avoiding unknown-message discovery in a suspend
  loop. A transport ACK only establishes that firmware handled the request;
  output must be read from the separate sink and validated.
- Thus exact firmware identity has narrowed the remaining gap to whether Nova
  uses the same mapped message-RAM window and monitor sink layout, plus a
  minimal safe diagnostic interface to issue the query and preserve raw output.
  The live DT resource check below shows Nova's mapping is only 0x400 bytes.
  No QMP message has been sent to Nova. Do not use the sample decoder on Nova
  solely because the firmware hash matches: device-specific RAM layout still
  matters.
- Sources reviewed: [SM8550 handheld observations](https://github.com/jaewun/qcom-aop-debug/blob/main/docs/sm8550-handhelds.md),
  [QMP interface and risk notes](https://github.com/jaewun/qcom-aop-debug/blob/main/docs/qmp.md),
  and the project's `patches/sm8550-thor/0001-soc-qcom-qcom_aoss-add-Thor-AOP-diagnostics.patch`.

### 2026-09-18 01:58 UTC — published MSGRAM offset is outside Nova's live QMP mapping

- Read the live Nova FDT node
  `/sys/firmware/devicetree/base/soc@0/power-management@c300000`. Its
  `compatible` is `qcom,sm8550-aoss-qmp`, and its `reg` bytes decode big-endian
  to base `0x0c300000`, size `0x400` (1 KiB). This agrees with upstream
  `sm8550.dtsi`'s `aoss_qmp` resource.
- The published Thor/RP6 patch's monitor dump uses
  `qmp->msgram + 0x20000` for the CXPC log. Its DDR vote collector reads at
  offsets around `0xf0000`. Neither is within Nova's `0x400`-byte mapping.
  The patch itself adds a `msgram_size` guard requiring enough space for the
  DDR vote area before creating its diagnostic files; against Nova's live
  resource size it would decline to create those nodes. Reading those offsets
  through the current mapping would be out of bounds and is not a safe test.
- This means the exact AOP binary match validates the known request grammar,
  but not the sample monitor buffer address or decoder. It also explains why
  the existing debugfs directory has no monitor nodes: this kernel's device
  tree only maps QMP's 1-KiB protocol window. No QMP command or out-of-range
  MMIO read was attempted.
- The next investigation is source-only: determine whether Nova has a
  separately described AOP monitor/shared-memory region or whether a platform
  firmware/device-tree change would be required to expose it. Do not build the
  sample patch until the buffer mapping and bounds are resolved; the current
  minimal route cannot safely query or decode CXPC output.

### 2026-09-18 02:02 UTC — widening QMP to cover all sample diagnostics conflicts with qcom_stats

- The sample patch uses QMP-relative DDR-vote offset `0xf01f0`, which resolves
  from base `0x0c300000` to physical `0x0c3f01f0`. Upstream SM8550 separately
  declares `qcom,rpmh-stats` at `0x0c3f0000` with size `0x400`, covering that
  exact location, and the current Nova image has the `qcom_stats` debugfs
  driver bound there. The sample patch's minimum `msgram_size` of `0xf0240`
  would extend the QMP resource through and beyond this separate stats window.
- Therefore do not enlarge Nova's single QMP `reg` to make the copied Thor/RP6
  patch pass its full diagnostic size check. That range is already described
  and owned as a separate qcom_stats resource on this kernel. The CXPC-only
  sink at `0x0c320000` is a smaller separate mapping question; it is still
  outside QMP's declared `0x400` resource and has no Nova DT node.
- A safe diagnostic design would need a separate, explicitly validated CXPC
  sink resource and must leave the existing `qcom_stats` mapping alone. The
  sample's DDR-vote extension is unnecessary to answer the immediate CXPC
  question and should not be carried over without a separate design review.
- Evidence: upstream v7.2.3 `sm8550.dtsi` declares both the QMP resource and
  the adjacent `sram@c3f0000` stats resource; the qcom-aop-debug patch uses the
  matching absolute DDR-vote address and requires one large QMP mapping.
  Armada's preflight records `qcom_stats` debugfs active on Nova. No resource
  enlargement, QMP message, or MMIO read was attempted.

### 2026-09-18 02:04 UTC — the community patch needs an undocumented DT difference

- Compared the community patch's stated upstream v7.1 base with v7.2.3. Both
  upstream SM8550 device trees declare QMP `reg` as `0x0c300000/0x400` and
  separately declare `qcom,rpmh-stats` at `0x0c3f0000/0x400`. Yet the sample
  Thor/RP6 patch requires one QMP mapping of at least `0xf0240` bytes before it
  creates any monitor node. That condition cannot pass against either vanilla
  upstream SM8550 tree.
- The community repository calls the patch experimental and device-specific,
  but does not include a matching device-tree patch that supplies the larger
  region. Therefore its reported Thor/RP6 captures imply an additional local
  DT/resource setup or another tree difference that is not in the published
  patch set. We cannot treat the sample's `qmp->msgram + 0x20000` pointer as a
  generally available QMP mapping just because the AOP ELF hash matches.
- The remaining research target is the exact downstream FDT/resource setup
  used to obtain the published `0x0c320000` CXPC capture. If it cannot be
  established from public source, a Nova test would need a separately
  described and validated resource; do not copy the undocumented mapping or
  widen QMP through the existing `qcom_stats` block.

### 2026-09-18 02:00 UTC — no separate Nova CXPC sink appears in the device tree

- Armada's Nova source DT includes the RP6 DT, which changes model/compatible
  and panel/input details. Its shared QCS8550 common DT removes standalone
  `aop_image_mem` and `aop_config_mem`, then reserves merged XBL/AOP-image
  memory at `0x81a00000..0x81c60000`, keeps AOP cmd-db at
  `0x81c60000..0x81c80000`, and reserves merged AOP config at
  `0x81c80000..0x81cf4000`. These are distinct from the published monitor
  sink at physical `0x0c320000` (the `0x20000` offset from QMP base).
- No Nova DT node separately describes the published CXPC sink. The running
  QMP node maps only `0x0c300000..0x0c300400`; `qcom_aoss` maps resource 0 via
  `devm_platform_ioremap_resource()`, so the current driver cannot read the
  sink through its existing mapping. The kernel binding defines `reg` as the
  QMP client's message-RAM base and size. The community patch's 1-MiB check
  is not satisfied, and its 22-driver dump path is unavailable.
- The current live `/proc/iomem` redacts physical ranges to zero, so it cannot
  tell us whether `0x0c320000` is claimed by another resource. No separate AOP
  monitor mapping, userspace QMP sender, or output reader has been found in
  Armada's source/runtime inventory. No direct physical-memory read or QMP
  write was attempted.
- Remaining possibilities are to find a device-specific vendor DT/resource
  definition for the same tested Thor/RP6 image, or to stop pursuing this
  monitor path until such a sink mapping is documented. Do not enlarge the
  live QMP mapping or read `/dev/mem` based only on adjacency or the AOP hash.

## Next controlled step

Keep the current image and existing run IDs intact. Source research should now
find the exact Thor/RP6 downstream FDT/resource setup used by the published
capture, especially the separate `0x0c320000` CXPC sink. Do not expand QMP's
existing resource across `qcom_stats`, read `/dev/mem`, or build a diagnostic
until the CXPC sink has an independently validated Nova resource. The exact
AOP hash supports the request syntax, but does not make an out-of-range sink
safe to read.

### 2026-09-18 02:08 UTC — historical monitor patch used a separate physical sink

- Compared the two published revisions of the community diagnostic patch.
  Initial commit `8668843` defines the CXPC sink at physical `0x0c320000` and
  calls `ioremap(0x0c320000, 0x1000)` from both the decoded dump and raw dump
  paths. The later commit `adbfcdf` replaces that physical base with
  `THOR_VX_OFFSET = 0x20000`, reads `qmp->msgram + 0x20000`, and adds a global
  gate requiring the QMP resource to cover the DDR vote area (at least
  `0xf0240` bytes).
- This resolves the apparent conflict between captures documented as live on
  Thor/RP6 and the current patch's impossible size gate under upstream's
  `0x400`-byte QMP `reg`: the published capture can have come from the original
  separate-physical-map version, while the later relative-map version cannot
  pass with vanilla upstream DT. Public docs do not yet identify which exact
  patch revision produced each capture or provide a matching DT resource node.
- The initial implementation is historical evidence that the monitor output
  resides at the separate physical address on those tested boards. It is not
  proof that Nova reserves, exposes, or permits safe access to that range.
  Nova's live DT still has no separate sink node, and `/proc/iomem` is
  redacted; do not copy the old hard-coded `ioremap` onto Nova without an
  independently validated resource/ownership source.
- Evidence: [initial patch, direct physical map](https://github.com/jaewun/qcom-aop-debug/blob/866884393d6322fd0598cebc52a9e34391c53ba0/patches/sm8550-thor/0001-soc-qcom-qcom_aoss-add-Thor-AOP-diagnostics.patch#L75-L104);
  [follow-up patch, QMP-relative map and size gate](https://github.com/jaewun/qcom-aop-debug/blob/adbfcdfcbd64ed795400fdf324c78bc317f3e048/patches/sm8550-thor/0001-soc-qcom-qcom_aoss-add-Thor-AOP-diagnostics.patch#L109-L141).
  No device read, mapping, QMP send, build, or suspend occurred.

### 2026-09-18 02:07 UTC — upstream QMP APIs do not provide a userspace monitor read path

- Re-read upstream `qcom_aoss.c` and the public `qcom,aoss-qmp` binding while
  checking for a safe way to access the CXPC sink. The binding describes `reg`
  as the message RAM for that QMP client's communication with AOSS; it does not
  define the separate CXPC monitor-output sink as part of this resource.
- Upstream exposes `qmp_get()`/`qmp_send()` as a GPL-exported kernel API for
  other kernel devices. Its generic debugfs files are fixed control writes
  (`prevent_*_collapse` and DDR frequency), with no read operation or monitor
  buffer dump. The existing `qcom_aoss` tracepoints report messages and
  acknowledgements, not the contents of the monitor sink.
- Public AYN QCS8550 common-DT and Retroid Nova/RP6 DTS sources show the device
  DT layering but add no independent `0x0c320000` monitor resource; the Nova
  definition includes the shared SoC/common tree. No safe read-only userspace
  path to validate the CXPC buffer has surfaced. A future kernel diagnostic
  would need a separately justified, explicitly mapped resource and ownership
  check; the current `0x400` QMP resource is not such a mapping. Avoid `/dev/mem`
  and avoid widening the existing QMP resource.
- Sources checked: [QMP binding](https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/soc/qcom/qcom%2Caoss-qmp.yaml),
  [upstream AOSS/QMP driver](https://github.com/torvalds/linux/blob/master/drivers/soc/qcom/qcom_aoss.c),
  [Nova/RP6 DTS series context](https://lkml.rescloud.iu.edu/hypermail/linux/kernel/2608.1/00453.html),
  and [AYN common QCS8550 DTS patch](https://patchew.org/linux/20260727-ayn-qcs8550-v9-0-e3db456e10e5%40gmail.com/20260727-ayn-qcs8550-v9-3-e3db456e10e5@gmail.com/).

### 2026-09-18 02:09 UTC — correction: historical direct mapping needs no QMP DT enlargement

- The 02:04 inference that Thor/RP6 captures necessarily imply a larger QMP
  DT resource is too strong. The initial public diagnostic patch used a
  separate hard-coded `ioremap()` of the CXPC sink, so that version could read
  the sink without enlarging QMP's `0x400` resource. The later revision changed
  to an offset in the QMP mapping and added the larger-size gate.
- Therefore the unresolved Nova question is whether `0x0c320000` has a
  documented memory owner and safe, conflict-free mapping on this board, not
  whether the QMP `reg` should be widened. Public source has not yet shown that
  owner or a separate resource for Nova. Keep both unsafe paths closed: do not
  widen QMP across `qcom_stats`, and do not reproduce the old hard-coded
  `ioremap()` without an ownership/resource justification.
- The next useful source check is the exact version used for the documented
  live captures and any downstream declaration/ownership for the separate
  sink. If neither is public, stop this monitor path pending a documented
  Nova resource rather than treating a guessed physical map as a diagnostic.

### 2026-09-18 02:11 UTC — Qualcomm declares a separate 1 KiB sys-pm-vx window

- Qualcomm's public Kalama DTSI declares AOSS QMP at `0x0c300000/0x400` and a
  separate `sys-pm-vx@c320000` region at `0x0c320000/0x400`. An AYN Thor
  Android running-DT dump has the same standalone region. The Qualcomm-derived
  `sys_pm_vx.c` driver maps its own platform resource with `of_iomap(..., 0)`;
  this confirms `0x0c320000` is a distinct monitor-output interface on the
  documented vendor/Thor platform, not an extension of QMP's mailbox window.
- The archived `cxpc-raw-head.txt` explicitly labels its physical addresses as
  coming from the original lab patch and starts at `0c320000`. This ties that
  capture to the original patch's separate physical mapping. The later patch
  conversion to `qmp->msgram + 0x20000` was not shown to have produced the
  archived sample and cannot work with the `0x400` QMP resource as written.
- This narrows the Nova path: if Nova exposes the same vendor region, it should
  be represented as a separate bounded resource (at most the vendor-declared
  `0x400`) and consumed through an owned platform mapping. No Nova-specific
  active `sys-pm-vx` node or RP6 running FDT has been found yet, and the
  community patch's original `ioremap(..., 0x1000)` exceeds the vendor DT's
  declared `0x400` span. Do not copy that mapping. First inspect Nova's live
  flattened DT for any matching node/resource, then check kernel resource
  ownership before designing a bounded diagnostic.
- Evidence: [Kalama DTSI AOSS QMP and sys-pm-vx nodes](https://android.googlesource.com/kernel/msm-extra/devicetree/+/refs/heads/android-msm-eos-android13-wear-kr3-pixel-watch/qcom/kalama.dtsi#2073);
  [Thor running DT sys-pm-vx node](https://gist.github.com/TheGammaSqueeze/69ddf2254b7a9be2a0b7d23bd7c450be#file-thor-dts-L18622-L18627);
  [sys_pm_vx resource mapping](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/sys_pm_vx.c#L417-L434);
  [raw sample provenance](https://github.com/jaewun/qcom-aop-debug/blob/main/examples/sm8550-6aceb38f/cxpc-raw-head.txt#L1-L3).
  No Nova mapping, QMP request, build, or suspend was attempted.

### 2026-09-18 02:15 UTC — active Nova FDT does not declare the vendor monitor window

- Read-only SSH preflight confirms the current Nova is awake, unplugged and
  discharging at 80% (`qcom-battmgr-usb/online=0`, `charge_now=5297704`,
  `charge_full=6559000`). Wi-Fi and Bluetooth are both enabled. Current image
  remains `20260915.feca679`, kernel `7.2.3`, boot ID unchanged from the prior
  preflight.
- Walked every live FDT `reg` property using the parent address/size cell
  counts and checked the platform-device `resource` files for an overlap with
  `0x0c320000..0x0c320400`. No node/resource describes or claims that range.
  The live QMP node remains `0x0c300000/0x400`. No `sys-pm-vx` node was found.
  This independently confirms the previous source-only finding against the
  active Nova device tree; the public vendor/Thor declaration cannot be
  assumed to be present in Armada's FDT.
- Receipt: `/private/tmp/sm8550-latest-unplugged-preflight/preflight-20260918T021051Z-70db1d5b031c.json`.
  Follow-up remote command was read-only and returned no address claim for the
  CXPC window. No QMP message, MMIO access, build, or suspend occurred.

### 2026-09-18 02:24 UTC — Armada can use qcom_aoss API without vendor QMP mailbox

- The Qualcomm `sys_pm_vx.c` reference uses `mbox_request_channel(..., 0)` and
  an AOP mailbox packet to send `lpm_mon/cxpc`; its Kalama DTS supplies a
  `qcom,qmp-mbox` provider and a separate `sys-pm-vx` node. Those mailbox
  provider properties are vendor-specific and are not needed for a small
  Armada diagnostic because upstream `qcom_aoss` exports `qmp_get()` and
  `qmp_send()`. `qmp_get()` resolves a consumer node's `qcom,qmp` phandle;
  Armada's kernel config already selects `CONFIG_QCOM_AOSS_QMP=y`.
- A minimal out-of-tree diagnostic driver could bind to a new Nova DT node with
  a separately declared `reg = <0x0c320000 0x400>` resource and
  `qcom,qmp = <&aoss_qmp>`. It can use `devm_platform_ioremap_resource()` for
  the bounded sink mapping and `qmp_get()/qmp_send()` for the CXPC query,
  avoiding Qualcomm's `qcom,qmp-mbox` provider and the vendor-only
  `subsystem_sleep_stats.h` helpers. The existing Nova FDT has no such node,
  so adding only the DT node would not send a query or produce a decoded
  capture; a driver/module (or an in-tree kernel patch) is also required.
- Do not copy the full vendor parser unchanged: it trusts the sink's `logsize`
  and loops over the reported rows without checking that the reads fit the
  mapped region. The vendor DT declares only `0x400` bytes, while the public
  experimental decoder's `0x1000` size is not valid for that resource. A small
  port should clamp rows to the declared resource size and reject malformed
  headers.
- Effort estimate (not yet built): a purpose-limited module with fixed CXPC
  request, suspend/resume trigger, and bounded raw/decoded debugfs read is
  roughly 100–180 LOC plus a DT change; it can be module-only if exact running
  kernel build artifacts and exported-symbol metadata are available. A DTB-only
  change is insufficient. Extending built-in `qcom_aoss` can avoid a separate
  module but needs a kernel image rebuild and a clean way to reference/map the
  second resource; it is not simpler than a small driver. Do not add the
  address to Nova DT until its board-level ownership is justified, even though
  Qualcomm Kalama and Thor declare the same 1 KiB window.
- Evidence: [vendor QMP packet and capture request](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/sys_pm_vx.c#L182-L205),
  [vendor parser](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/sys_pm_vx.c#L208-L263),
  [vendor debugfs/match/probe](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/sys_pm_vx.c#L391-L493),
  [vendor PM callbacks](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/sys_pm_vx.c#L522-L573),
  [v7.2.3 QMP API header](https://github.com/gregkh/linux/blob/v7.2.3/include/linux/soc/qcom/qcom_aoss.h#L12-L18),
  [v7.2.3 qmp_get/qmp_send implementation](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_aoss.c#L228-L278),
  [v7.2.3 qmp_get implementation](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_aoss.c#L442-L489),
  [Kalama QMP mailbox and 1 KiB monitor node](https://android.googlesource.com/kernel/msm-extra/devicetree/+/refs/heads/android-msm-eos-android13-wear-kr3-pixel-watch/qcom/kalama.dtsi#L2083-L2088).
  No code was changed, no module or DTB was built, and no device action or
  monitor request was performed.

### 2026-09-18 02:34 UTC — a temporary module can avoid DT overlays, but resource ownership is not proven

- `request_mem_region(0x0c320000, 0x400, ...)` followed by `ioremap()` is
  mechanically possible without a DT node. It would reserve the range in
  Linux's I/O resource tree and let a temporary module release it on unload.
  This does not establish that Nova's bus decodes the address or that firmware
  has no unreported owner; successful reservation is only a Linux-side
  conflict check. An invalid MMIO read can still fault. Because Nova's live FDT
  and platform-resource inventory contain no claim for this range, do not map
  or read it until the board/SoC ownership is independently substantiated.
- No DT overlay is needed to get the existing AOSS QMP handle either: upstream
  `qmp_get(dev)` looks for a `qcom,qmp` property on the consumer device. The
  existing `qcom,rpmh-stats` platform device has that property pointing at
  `aoss_qmp`, and is already active (`qcom_stats` debugfs exists). A temporary
  no-OF-node module could find that platform device with
  `of_find_device_by_node()` and call `qmp_get(&stats_pdev->dev)`, then use the
  exported `qmp_send()`. The QMP calls are serialized by the AOSS driver's
  transmit lock. A no-node module would need a manual trigger/read interface
  or a PM notifier; it would not get a platform device's suspend/resume
  callbacks automatically.
- Module-only build is possible in principle, but the current Armada package
  does not retain a kernel build tree or publish kernel-devel artifacts. Its
  package script pins 7.2.3, builds inside a disposable `podman run --rm`,
  always targets `Image dtbs modules`, and stages only `/lib/modules`; it
  removes `build` and `source` links and discards the container work tree.
  There is no local `.config`, `Module.symvers`, `vmlinux`, or build tree.
- Minimum reproducible module build needs the exact patched 7.2.3 source,
  effective Armada `.config`, generated Kbuild headers/scripts from
  `modules_prepare`, an AArch64 toolchain/builder, and matching `Module.symvers`
  if `CONFIG_MODVERSIONS=y`. Then Kbuild can build only the external module
  with `make -C "$KDIR" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- M="$PWD"
  modules`; it does not inherently require an Image/DTB build when
  modversions are disabled and the needed build artifacts exist. The Armada
  fragment selects `CONFIG_QCOM_AOSS_QMP=y` but does not pin
  `CONFIG_MODULES`, `CONFIG_MODVERSIONS`, or module-signature settings; arm64
  defconfig enables modules, while the final generated config and target's
  load/signing policy are not retained in the package. Inspect the effective
  target config before relying on module loadability.
- Official Kbuild docs state that `modules_prepare` does not create
  `Module.symvers` when MODVERSIONS is enabled; then a full symbol-version
  build is required. For a low-cost path, first verify the target config is
  MODVERSIONS=n, preserve the configured/prepared tree, and build only the
  diagnostic `.ko`. Do not use forced vermagic or force-load to get past ABI
  checks.
- Evidence: [Armada kernel version](../../../armada-packages/kernel/BASE.env),
  [Armada kernel build wrapper](../../../armada-packages/kernel/build.sh#L17-L30),
  [Armada build/staging steps](../../../armada-packages/kernel/scripts/build-kernel.sh#L183-L270),
  [Armada QMP config](../../../armada-packages/kernel/config/armada-kernel.config.overrides#L22-L27),
  [v7.2.3 arm64 defconfig modules setting](https://github.com/gregkh/linux/blob/v7.2.3/arch/arm64/configs/defconfig#L2429-L2432),
  [v7.2.3 qmp_get/send API](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_aoss.c#L228-L278),
  [v7.2.3 qmp_get phandle handling](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_aoss.c#L442-L489),
  [v7.2.3 QMP API declarations](https://github.com/gregkh/linux/blob/v7.2.3/include/linux/soc/qcom/qcom_aoss.h#L12-L18),
  [v7.2.3 SM8550 stats device QMP phandle](https://github.com/gregkh/linux/blob/v7.2.3/arch/arm64/boot/dts/qcom/sm8550.dtsi#L4677-L4680),
  [official external-module build and Module.symvers requirements](https://docs.kernel.org/kbuild/modules.html).
  No module was built, no device was touched, and no MMIO or QMP access was
  attempted.

### 2026-09-18 02:16 UTC — vendor sys-pm-vx is a suspend/resume monitor, not only a dump

- Qualcomm's Kalama DTS gives the `sys-pm-vx` node its own `0x0c320000/0x400`
  memory resource and an AOP QMP mailbox. The Qualcomm-derived driver maps
  resource 0 with `of_iomap()`, creates read-only debugfs
  `/sys/kernel/debug/sys_pm_violators`, and has system suspend/resume PM ops.
- With debugging enabled, its resume callback checks whether system and
  subsystem sleep counters advanced. `monitor_enable` starts false; after the
  first qualifying resume (system sleep did not occur, but a subsystem did),
  the driver arms monitoring. The next suspend sends a CXPC QMP request, and
  the following resume reads driver votes if the system still failed to sleep
  while the subsystem did. If system sleep succeeds or no subsystem slept, it
  stops the monitor. This is a direct reference implementation for the
  missing observability: it coordinates the monitor with real PM boundaries
  rather than asking userspace to guess a 2-second query window.
- The driver is a Qualcomm vendor implementation, absent from Nova's current
  FDT/runtime inventory. Its full source and any Qualcomm-only dependencies
  still need review before choosing a small port. The active Nova FDT has no
  monitor resource; the public Kalama/Thor `0x400` resource is evidence for a
  separately bounded mapping, not authorization to read the address without a
  declared/claimed resource.
- Evidence: [Kalama sys-pm-vx DT node](https://android.googlesource.com/kernel/msm-extra/devicetree/+/refs/heads/android-msm-eos-android13-wear-kr3-pixel-watch/qcom/kalama.dtsi#L2331-L2336),
  [debugfs and compatible table](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/sys_pm_vx.c#L391-L405),
  [probe maps the resource and requests its mailbox](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/sys_pm_vx.c#L417-L493),
  [suspend/resume monitor behavior](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/sys_pm_vx.c#L522-L573).
  No driver was built or loaded; no monitor request was sent.

### 2026-09-18 02:26 UTC — live configfs cannot add a device-tree overlay

- Nova has `CONFIG_OF_OVERLAY=y` and `CONFIG_CONFIGFS_FS=y`, but its running
  kernel config does not include `CONFIG_OF_CONFIGFS`; `/sys/kernel/config`
  contains only PCI endpoint directories and no `device-tree/overlays` path.
  Therefore the monitor node cannot be added as a live configfs overlay on this
  boot. Testing the proposed explicit resource would require an offline DTB or
  boot image change and reboot, or a different platform-device creation path.
- This narrows the low-build test route: there is no overlay-only live trial.
  The current kprobe harness remains the no-reboot option; a CXPC sink reader
  needs both a driver and a DT resource claim. No files on the device were
  changed, and no address mapping or read was attempted.

### 2026-09-18 02:30 UTC — one matched pair shows different PSCI returns with Bluetooth blocked

- Re-parsed the two archived five-minute `psci-kretprobe` cycles. Both ran the
  same Armada image/kernel and selected `s2idle`; Wi-Fi was enabled in both.
  Run `20260918T005938Z-f9ed9257d8db` preserved Bluetooth powered on and the
  filtered `psci_cpu_suspend_enter` event for state `0x4100c344` recorded 34
  returns: 22 `-95`, 9 `-1`, and 3 `0`. Run
  `20260918T011816Z-656072014367` hard-blocked Bluetooth with rfkill; the same
  state filter recorded one return of `0` and no negative returns. Both had
  about 298.5 seconds of clock separation and unchanged boot IDs.
- The output is a suggestive correlation from one pair, not proof Bluetooth
  causes rejection: the runs were not randomized or replicated, and the PSCI
  return values still need mapping against Armada's exact v7.2.3 call path and
  PSCI ABI. Do not infer AOSD/CXSD/DDR residency from these returns. Their
  named `qcom_stats` counters remained zero in both runs while ADSP advanced.
- Battery gauge deltas are not a usable discriminator here: the reported
  window averages were about 658 mA with Bluetooth on and 612 mA with it
  blocked. Treat these five-minute values as noisy; they neither measure the
  reported hourly drain reliably nor outweigh the one-pair design.
- Evidence: `../sm8550-suspend-lab-runs/20260918T005938Z-f9ed9257d8db/` and
  `../sm8550-suspend-lab-runs/20260918T011816Z-656072014367/`, especially each
  `device/raw/trace/trace.txt`, `device/raw/trace/kprobe_profile.txt`,
  `device/meta/radio-before.json`, and `device/derived/summary.json`. The
  recorded per-CPU trace `dropped events` counts are zero. No new suspend run
  was started for this re-analysis.

### 2026-09-18 02:33 UTC — PSCI errno values identify firmware rejection classes

- Traced `psci_cpu_suspend_enter()` in Armada's exact Linux v7.2.3 source. It
  calls the selected PSCI `cpu_suspend` operation; the PSCI driver converts
  firmware returns to Linux errors. `PSCI_RET_NOT_SUPPORTED` becomes
  `-EOPNOTSUPP` (`-95`), and `PSCI_RET_DENIED` becomes `-EPERM` (`-1`). A
  returned `0` is `PSCI_RET_SUCCESS`. Therefore the 31 negative returns in the
  Bluetooth-on run were firmware PSCI `NOT_SUPPORTED`/`DENIED` responses for
  state `0x4100c344`, while its three `0` returns were successful entries.
- This establishes that firmware sometimes rejects that CPU-idle power state;
  it does not establish why, whether Bluetooth is causal, or which AOSD/CXSD/
  DDR state was reached after successful entries. The one Bluetooth-off run
  remains a single comparison.
- Evidence: [v7.2.3 PSCI return-to-errno mapping and CPU_SUSPEND wrapper](https://github.com/gregkh/linux/blob/v7.2.3/drivers/firmware/psci/psci.c#L2094-L2173),
  [v7.2.3 PSCI result constants](https://github.com/gregkh/linux/blob/v7.2.3/include/uapi/linux/psci.h#L685-L703).

### 2026-09-18 02:34 UTC — independent Bluetooth-on PSCI replicate started

- Fresh preflight `preflight-20260918T023047Z-c758397510b9` confirmed the
  same boot ID, image `20260915.feca679`, kernel `7.2.3`, Bluetooth powered
  on/unblocked, Wi-Fi enabled, and no stale `psci_cpu_suspend_enter` probe.
  A live check at 02:26 had USB online `0`, battery discharging at 78%, and an
  empty RTC wakealarm; the run's own start gate also refuses a pre-existing
  alarm.
- Run `20260918T023202Z-2b9e17892e57` is an independent five-minute `s2idle`
  repeat with Wi-Fi and Bluetooth preserved. The run-scoped kretprobe filters
  `psci_cpu_suspend_enter` to `0x4100c344`, and the hypothesis is whether the
  prior Bluetooth-on burst of `PSCI_NOT_SUPPORTED`/`PSCI_DENIED` returns
  repeats. It makes no persistent radio, kernel, firmware, or sleep-policy
  change. SSH timed out after launch while the autonomous RTC-controlled run
  entered suspend; this is expected during the test, not a failure report.
- Do not interpret or compare battery gauge deltas as the outcome. The
  diagnostic question is reproducibility of PSCI return values and the paired
  cluster genpd Usage/Rejected/S2idle counters. Result pending resume and
  retrieval.

### 2026-09-18 02:35 UTC — separate DDR LPM duration advances during the five-minute tests

- Exact v7.2.3 `qcom_stats.c` source distinguishes the `ddr_stats` table from
  the scalar `qcom_stats/ddr` sleep counter. It calls `0xd0` a DDR low-power
  statistic ID (along with `0xd4`, `0xd3`, and `0x11`), but does not give the
  IDs stable human-readable state names. On SM8450-and-newer platforms, it
  asks AOP to synchronize the DDR table before each read when a QMP handle is
  available.
- In both archived five-minute PSCI tests, `ddr_stats` code `0xd0` kept
  `count=1` while its duration advanced about 5.89 billion ticks over 298.5
  seconds, roughly 19.7 MHz and close to the full suspend-clock separation.
  The scalar `qcom_stats/ddr`, AOSD, and CXSD counters remained zero. This is
  evidence that the separate firmware DDR LPM duration counter advances across
  the sleep interval; the numeric ID still does not identify which DDR state
  it measures, so it cannot prove the intended deepest DDR state was reached.
- Evidence: [v7.2.3 qcom_stats DDR LPM ID and QMP synchronization logic](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L1282-L1408),
  plus the exact before/after `ddr_stats` and clock receipts in
  `../sm8550-suspend-lab-runs/20260918T005938Z-f9ed9257d8db/device/` and
  `../sm8550-suspend-lab-runs/20260918T011816Z-656072014367/device/`.

### 2026-09-18 02:38 UTC — Bluetooth-on repeat reproduces PSCI NOT_SUPPORTED burst

- Run `20260918T023202Z-2b9e17892e57` completed on the unchanged boot/image,
  unplugged, with Bluetooth and Wi-Fi preserved on. It observed `s2idle`,
  298.899646 seconds of suspend-clock separation, and the expected RTC wake.
  The filtered state `0x4100c344` had 26 PSCI returns: 13 `-95`
  (`PSCI_NOT_SUPPORTED`) on CPU0 and 13 `0` returns (12 on CPU0 and one
  spanning the interval on CPU3). No `-1`/`PSCI_DENIED` occurred. Trace buffers
  reported zero drops.
- `power-domain-cluster` S1 counters moved Usage 167 to 180 (+13), Rejected
  331 to 344 (+13), and S2idle 495 to 521 (+26), exactly matching the 13
  successful calls, 13 rejected calls, and all 26 s2idle requests. This
  independently reproduces the Bluetooth-on rejection burst from
  `20260918T005938Z-f9ed9257d8db`; the prior Bluetooth-off five-minute control
  had one successful call and zero rejections. Since a separate one-minute
  Bluetooth-on run also had only a successful call, rejections are
  intermittent and Bluetooth is not established as the cause.
- AOSD, CXSD, and scalar DDR sleep-stat counters remained zero. The separate
  `ddr_stats` `0xd0` LPM duration advanced 5,906,676,200 ticks (`count=1`),
  about 19.76 MHz across the 298.9-second interval. That remains an unnamed
  DDR LPM bucket. The battery gauge reported 64,279 uAh consumed over 301.7
  seconds (about 767 mA); do not treat this noisy short-window gauge value as
  a drain-rate result.
- Cleanup verified the probe/trace instance were removed, the RTC alarm was
  restored empty, Wi-Fi/Bluetooth stayed enabled, and the device resumed on
  the same boot. Exact evidence is under
  `../sm8550-suspend-lab-runs/20260918T023202Z-2b9e17892e57/`.

### 2026-09-18 02:40 UTC — Bluetooth-off replicate planned, then re-preflighted

- Preflight `preflight-20260918T024005Z-3f4eae74db24` confirms the same boot
  ID, image `20260915.feca679`, kernel `7.2.3`, Bluetooth on/unblocked,
  Wi-Fi enabled, `[s2idle] deep`, and no registered kprobe. Direct read-only
  check confirms USB online `0`, battery discharging at 76%, and an empty RTC
  wakealarm.
- The Bluetooth-off replicate had not actually been launched at this point;
  the heading/wording in this entry was premature. A second fresh preflight at
  02:42 confirmed the same boot and image, Bluetooth on, Wi-Fi on, and no
  matching probe. Direct SSH confirmed `battery` at 76% and discharging,
  `qcom-battmgr-usb` and `ucsi-source-psy-pmic_glink.ucsi.01` both offline,
  wireless charging offline, and an empty RTC wakealarm. The matched control
  remained pending until the 02:44 launch below.

### 2026-09-18 02:42 UTC — module-only CXPC probe may avoid a full image build

- Local Armada packaging review found the build container discards its Kbuild
  tree, `.config`, `Module.symvers`, and `vmlinux`; it packages `/lib/modules`
  only. So the current checkout cannot immediately produce a matching module.
  If the exact patched 7.2.3 source and generated config are reconstructed,
  module-only compilation is plausible when `CONFIG_MODVERSIONS=n`; with
  `CONFIG_MODVERSIONS=y`, the matching `Module.symvers` is required. The
  target's final config and module-signing policy remain to be checked.
- The active `qcom,rpmh-stats` platform device can supply the existing AOSS QMP
  handle to a diagnostic module, so a Device Tree edit may not be needed just
  to send QMP. However, claiming and mapping the separate `sys-pm-vx` 0x400
  region would only show no Linux resource conflict; it would not prove
  hardware ownership or make an unsafe MMIO read safe. No module was built or
  loaded and no device register was accessed. This remains a possible later
  diagnostic, not a current sleep-drain finding.
- Source refs: SM8550's `qcom,rpmh-stats` node references `aoss_qmp` in
  [sm8550.dtsi](https://github.com/gregkh/linux/blob/v7.2.3/arch/arm64/boot/dts/qcom/sm8550.dtsi#L4677-L4681);
  [qcom_aoss.c](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_aoss.c#L442-L489)
  implements `qmp_get()` and
  [qmp_send()](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_aoss.c#L228-L278).
  Armada packaging evidence is in `armada-packages/kernel/build.sh:17-30`
  and `kernel/scripts/build-kernel.sh:183-270`: the effective config/Kbuild
  artifacts are produced in a disposable container and not retained in the
  package. `kernel/BASE.env` pins 7.2.3; the fragment sets
  `CONFIG_QCOM_AOSS_QMP=y`.
- Reference-driver nuance: `sys_pm_vx.c` sends its command as an mbox packet,
  while `qmp_send()` sends a raw formatted QMP string using the shared AOSS
  transport. This suggests a small explicit QMP diagnostic might not need the
  reference driver's extra client mbox plumbing, but the `lpm_mon` command
  has not been validated through `qmp_send()` on this device. Neither API
  solves the monitor's system-PM timing or missing MMIO ownership.

### 2026-09-18 02:44 UTC — matched Bluetooth-off PSCI replicate launched

- Run `20260918T024408Z-d8c24b37df7d` started through the host harness after
  the 02:42 preflight and direct power-state checks. It requests five minutes
  of unplugged `s2idle`, preserves Wi-Fi, temporarily blocks Bluetooth, and
  records returns from `psci_cpu_suspend_enter` for state `0x4100c344`.
- This is the independent Bluetooth-off replicate for comparison with
  Bluetooth-on run `20260918T023202Z-2b9e17892e57`. Outcome is pending RTC
  resume and retrieval. The harness is responsible for restoring Bluetooth,
  RTC wakealarm, and temporary tracing after resume.
- At about 02:44 UTC the host observed SSH loss from `192.168.0.20`, which is
  expected while this RTC-controlled run is suspended; resume and the saved
  on-device status still need verification.

### 2026-09-18 02:48 UTC — short-window battery estimate needs a mid-charge baseline

- Rechecking run `20260917T230920Z-e03e810704f8` explains its anomalous
  7.84 mA counter-derived estimate: it began at `charge_counter=6,559,000`
  uAh, exactly equal to `charge_full`, and ended at 6,558,344 uAh. The
  `current_now` point readings were -616,348 and -695,085 uA. This is
  consistent with top-of-charge clipping in that five-minute counter delta;
  the reported 100-to-99 integer capacity change is too coarse to resolve it.
  It must not be used as evidence of negligible s2idle drain.
- More generally, five-minute integrated estimates vary from about 196 to
  798 mA across non-top-clipped runs, while a 5%/hour loss at the 6.442 Ah
  design capacity is about 322 mA. The current short runs do not establish
  whether the user's reported drain rate is reproduced. Relevant exact files:
  `../sm8550-suspend-lab-runs/20260917T230920Z-e03e810704f8/device/{pre,post}/power_supplies.json`
  and `device/derived/summary.json`.
- After the current Bluetooth-off traced control resumes and verifies cleanup,
  the next measurement will be one 30-minute unplugged `s2idle` interval with
  tracing disabled and radios preserved, starting away from full charge. This
  should test the rate without extending into a multi-hour run.

### 2026-09-18 02:49 UTC — Bluetooth-off PSCI replicate had one clean entry

- Run `20260918T024408Z-d8c24b37df7d` completed on the same boot and image,
  with 299.098914 seconds of suspend-clock separation and the expected RTC
  wake. For state `0x4100c344`, the trace contains one CPU0 PSCI return of 0
  and no `-95`/`-1` rejections; all per-CPU buffers report zero dropped
  events. Cluster genpd S1 moved Usage 180 to 181, Rejected stayed 344, and
  S2idle moved 521 to 522, matching one successful transition. This repeats
  the earlier clean Bluetooth-off sample, but does not establish that
  Bluetooth causes the intermittent rejections seen in two Bluetooth-on
  runs.
- AOSD, CXSD, and scalar DDR counters again remained zero. ADSP count increased
  by 205 and APSS by one. Separate DDR LPM code `0xd0` stayed at count 1 while
  duration advanced 5,914,667,213 ticks across the interval. Its state meaning
  is still unknown, so this does not prove a specific deep DDR state.
- The short Bluetooth-off charge-counter delta was 56,407 uAh over 301.86 s
  (about 673 mA) and capacity moved 76% to 75%. This noisy five-minute value
  is not a reliable hourly-drain estimate and will be checked with the planned
  untraced mid-charge interval. Exact data is in
  `../sm8550-suspend-lab-runs/20260918T024408Z-d8c24b37df7d/`.
- Cleanup restored an empty RTC alarm; the run trace instance and kprobe were
  already absent on cleanup. `bluetoothctl power on` returned 1 in the cleanup
  receipt, but a direct post-run `bluetoothctl show` reports `Powered: yes`;
  battery is discharging at 75%, and wired/wireless supplies report offline.
  Same boot ID remained present. Check Wi-Fi and probe state again during the
  next fresh preflight before starting the no-trace interval.

### 2026-09-18 02:52 UTC — 30-minute untraced mid-charge baseline requested

- Fresh preflight `preflight-20260918T025158Z-c1a545752b29` confirmed the same
  boot/image/kernel, `[s2idle] deep`, Bluetooth and Wi-Fi powered on, no
  matching kprobe, and no active source-power input. Direct SSH check recorded
  `battery` at 75%, discharging, `charge_counter=4,930,400` uAh, all USB/wireless
  supplies offline, and an empty RTC wakealarm.
- Run `20260918T025221Z-0dd0e448a37f` requests 1,800 seconds of unplugged
  `s2idle` with tracing off and Wi-Fi/Bluetooth preserved. A status query
  shortly after launch timed out as the device became unreachable, consistent
  with entering suspend but not yet a completion receipt. Outcome remains
  pending RTC resume, retrieval, and post-run state/cleanup checks.

### 2026-09-18 02:54 UTC — DDR frequency table is dominated by the 547 MHz bin

- While the untraced baseline is suspended, compared the separate QCOM DDR
  frequency-stat deltas from three retrieved five-minute runs. In the new
  Bluetooth-off run, `ddr_freq_547mhz` advanced 5,772,146,176 ticks out of
  5,914,667,520 total ticks across frequency bins (97.6%); the next-largest
  bin, 2736 MHz, advanced 105,775,616 ticks (about 5.35 seconds at the common
  counter rate). The Bluetooth-on repeat was similar: 5,767,496,704 of
  5,906,676,224 ticks in the 547 MHz bin. The earlier Bluetooth-off sample
  was also similar at 5,734,760,960 of 5,889,808,896 ticks.
- This points to consistent low-frequency DDR reporting across Bluetooth
  conditions, rather than a radio-specific effect. It does not establish what
  DDR power mode the 547 MHz bin represents or prove self-refresh/collapse;
  the independent `0xd0` LPM ID remains unnamed. The QCOM source distinguishes
  frequency buckets from LPM IDs but provides no meaning for `0xd0`:
  [qcom_stats.c](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L1282-L1408).
  Exact counters are in the three runs' `pre/snapshot.json` and
  `post/snapshot.json` under their `qcom_stats.ddr_stats` sections.
- In each of these same three runs, the `0xd0` duration delta nearly exactly
  matched the sum of all DDR frequency-bin duration deltas: differences were
  only -307, -24, and -48 ticks against totals near 5.9 billion. Therefore
  seeing `0xd0` advance is not independent evidence of a deeper DDR state; its
  duration tracks essentially the whole interval alongside the frequency
  table. A firmware definition is still needed to interpret the ID.

### 2026-09-18 02:56 UTC — no local AOP image is available to decode 0xd0

- A read-only search of existing run archives and local research found no raw
  512 KiB AOP ELF/partition blob; the captured preflight preserves partition
  size, SHA-256, ELF identification, and only the first 64 bytes. Both Nova
  partitions hash to `6aceb38f5ef10663ac5c29ffc4e9ee27b6339e8746ff3490485f8cf2640ef687`,
  matching the cached public SM8550 example, but the associated notes say the
  image itself is not distributed. Searches of cached AOP docs for `0xd0`
  produced no DDR-state mapping. Therefore offline inspection cannot name this
  LPM bucket from the available artifacts; do not infer its state from its
  advancing duration. Receipt:
  `/private/tmp/sm8550-aop-partition-preflight/preflight-20260918T015158Z-27830d9c4849.json`;
  cached research: `/tmp/qcom-aop-debug/docs/sm8550-handhelds.md` and
  `/tmp/qcom-aop-debug/examples/sm8550-6aceb38f/README.md`.

### 2026-09-18 02:58 UTC — APSS and named AOSD/CXSD/DDR counters are different sources

- Exact v7.2.3 `qcom_stats.c` source places `apss` in the subsystem statistics
  table backed by QCOM SMEM item 631. The named `aosd`, `cxsd`, and `ddr`
  counters are a separate RPMh sleep-stat table. The `ddr_stats` frequency/LPM
  records are another separate table. Therefore APSS +1 during a run confirms
  an APSS subsystem-stat event only; it cannot substitute for missing AOSD,
  CXSD, or named DDR residency, and the `0xd0` LPM ID cannot be substituted for
  the named DDR counter either. This explains why the counters can appear
  contradictory without showing which physical rails were powered down.
- In the three latest five-minute kretprobe receipts, APSS accumulated sleep
  duration advanced by 5,742,636,637 ticks (Bluetooth off, count +1),
  5,738,424,727 ticks (Bluetooth on, count +2), and 5,731,599,095 ticks
  (earlier Bluetooth off, count +1), roughly 97% of each interval on the same
  timer scale. The named AOSD/CXSD/DDR stats remained zero in all three. This
  narrows the observation to APSS subsystem sleep with no corresponding named
  whole-system/DDR counter; it still does not identify physical rail state or
  the missing firmware decision.
- Source: [v7.2.3 qcom_stats.c subsystem registrations](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L1123-L1149),
  [APSS sleep-stat counter handling](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L1207-L1230),
  [DDR-stat encoding](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L1282-L1408),
  and [RPMh sleep-stat names](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L1485-L1510).

### 2026-09-18 03:00 UTC — related public sleep reports are still open

- Refreshed Armada GitHub state read-only. [Issue #264](https://github.com/armada-os/armada/issues/264)
  remains open with no comments since its report: an Odin 2 owner reports
  25% battery loss in 90 minutes with Bluetooth on and about 1%/hour after
  hard-blocking Bluetooth with rfkill, in both s2idle and deep. This supports
  testing the Nova radio relationship, but is cross-device evidence only; the
  current Nova short-window gauge deltas have not shown a matching reduction.
- [Issue #265](https://github.com/armada-os/armada/issues/265) remains open;
  the report says localized warmth persisted after the Bluetooth drain
  workaround, and a comment reports similar warmth on Odin 3 Max. This is a
  separate symptom from battery drain and may require a wake-source/rail
  investigation even if the radio workaround proves effective.
- [PR #235](https://github.com/armada-os/armada/pull/235) is still open on
  `main`, titled `feat(fake-suspend): opt-in radio suspend to cut idle drain`.
  Its implementation is scoped to fake suspend, not native s2idle. The latest
  file list is only `devices/defaults.conf`, `device-env`, and `fake-suspend`;
  it adds no systemd/native-suspend hook. The latest comment (September 12)
  asks the author to resolve conflicts; GitHub currently reports merge state
  `UNKNOWN`, so no current conflict status was inferred.
- A wider open-issue search also returned #428, whose body/comments are still
  empty; #438, a separate Pocket ACE Synaptics resume/input issue; and #466, a
  Retroid Pocket Flip 2 / SM8250 `qcom,pm8150b-fg` report where `current_now`
  has reversed sign. That driver is different from Nova's SM8550
  `qcom,battmgr`; do not apply its sign finding to this device's counter or
  infer sleep drain from a generic instantaneous-current convention.

### 2026-09-18 03:22 UTC — 30-minute unplugged baseline confirms roughly 5%/h drain

- Run `20260918T025221Z-0dd0e448a37f` completed after an observed
  `suspend_clock_separation_seconds=1799.475715` and measured battery interval
  of `1801.858295` seconds. It stayed on the same boot, suspend returned
  successfully, and the expected RTC alarm/IRQ was observed. The run used
  `s2idle`, no trace profile, and preserved Wi-Fi/Bluetooth policy; the
  pre/post snapshots confirm the battery remained unplugged and discharging.
- `charge_counter` fell from 4,924,497 to 4,774,296 uAh, a loss of 150,201 uAh.
  That integrated counter gives 300.09 mA average over the measurement window.
  Relative to `charge_full_design=6,442,000` uAh, it projects to 4.66 percentage
  points per hour; relative to reported `charge_full=6,559,000` uAh, 4.57%/h.
  This is strong evidence that the user's roughly 5%/h report is real on this
  device in native s2idle. It is still a one-window gauge measurement, not a
  wall-power measurement or proof of root cause.
- Integer capacity fell from 75% to 72% over the window, consistent in scale
  but coarse. Instantaneous `current_now` varied from -660,660 to -742,327 uA
  and should not replace the integrated counter. Voltage changed from 4,021,250
  to 4,009,378 uV; battery temperature from 26.0 C to 25.0 C.
- Wake attribution matched `rtc0`: IRQ 199's `pm8xxx_rtc_alarm` count advanced
  once, the PM wakeup IRQ stayed 199, and the RTC wakeup source matched. The
  separate `battery` wakeup-source counters also advanced by +2 active/+2
  events. This is an unresolved counter detail, not evidence that the battery
  woke the system; inspect source snapshots/logs before interpreting it.
- Raw receipt: `.external-research/sm8550-suspend-lab-runs/20260918T025221Z-0dd0e448a37f/`;
  derived metrics are in `device/derived/summary.json`, raw battery readings in
  `device/pre/power_supplies.json` and `device/post/power_supplies.json`, and
  wake sources/IRQ evidence in the matching pre/post snapshots plus the
  summary. The independent full-window interpretation should be reviewed
  before using the rate as anything more than strong supporting evidence.

### 2026-09-18 03:25 UTC — baseline cleanup and live device state verified

- Run cleanup restored `/sys/class/rtc/rtc0/wakealarm` to empty, left tracing
  and transient mode unchanged, and made no radio changes. The pre-run and
  post-cleanup receipts both show Bluetooth powered/on and Wi-Fi radio enabled.
  Post-resume health reported `wlp1s0` down/no carrier despite Wi-Fi radio being
  enabled, so treat “Wi-Fi preserved” as radio policy, not an active connection.
- Direct SSH at 03:25 UTC confirms the same boot ID, battery discharging at
  72%, USB/wireless/UCSI online flags all zero, Wi-Fi radio enabled, Bluetooth
  powered/on, and an empty RTC alarm. The battery counter had continued to
  decline after the 03:22 snapshot while awake, as expected for a powered-on
  idle device; this is outside the measured sleep interval.
- The `battery` wakeup-source row advanced active/event counts by +2 each, but
  its `wakeup_count` stayed 0 and `prevent_suspend_time` stayed 0. The RTC row
  advanced +2 too, and the distinct RTC IRQ evidence matches the sole expected
  wake. Therefore the battery row does not currently identify an actual
  battery-originated wake; its extra event activations remain unexplained but
  are not evidence of repeated wakeups in this run.

### 2026-09-18 03:26 UTC — launch matched Bluetooth-off 30-minute control

- Next discriminator: compare a 30-minute unplugged, untraced native s2idle
  window with Bluetooth powered off against baseline run
  `20260918T025221Z-0dd0e448a37f`, which had Bluetooth powered on. Preserve
  Wi-Fi radio policy (enabled, though its interface had no carrier/down), use
  the same boot/image/kernel, and collect the same integrated battery counter.
- Hypothesis: if Bluetooth materially accounts for Nova's roughly 5%/h drain,
  the charge-counter loss should fall substantially in the Bluetooth-off
  window. Cross-device issue #264 makes this worth testing, while earlier
  five-minute Nova samples were too noisy to decide.
- No kernel/image/software change; trace profile remains `none`. Run is
  authorized as a bounded 30-minute control, not a multi-hour test. Await the
  post-run counter, RTC-only wake evidence, and cleanup/state verification.

### 2026-09-18 03:27 UTC — independent audit refines normalization and meter caveat

- A second review of the archived raw uevents confirms `CHARGE_NOW` and
  `CHARGE_COUNTER` are the same Qualcomm BATT_CHG_COUNTER firmware value. They
  agree because they are aliases, not independent sensors; the integrated
  delta remains the best available device-side drain estimate.
- Normalizing `charge_now` by the stable `charge_full=6,559,000` uAh gives
  75.08% before and 72.79% after, a 2.29 percentage-point loss in 0.5005h,
  or 4.58%/h. A 5%/h loss at that full counter would be about 328mAh/h,
  compared with the measured 300mAh/h. This is close enough to support the
  reported approximate rate, but remains one fuel-gauge window without an
  external power meter or repeated hour-long validation.
- Integer capacity's 75%→72% is only directional corroboration: it is coarse
  and does not exactly follow charge_now normalization. Pre/post current_now
  are instantaneous endpoint samples (-660,660 and -742,327 uA), not a window
  average; prefer the 300mA counter-derived average.

### 2026-09-18 03:28 UTC — RTC wake attribution has direct IRQ and kernel-log proof

- Independent receipt review located the missing direct wake evidence in
  `device/post/logs/journal-kernel.txt`: kernel records “PM: Triggering wakeup
  from IRQ 199” before resume. The 1,800-second RTC alarm was armed, IRQ 199
  (`pm8xxx_rtc_alarm`) advanced exactly once (20→21), and the same-boot s2idle
  interval completed successfully. This confirms the intended RTC wake; the
  unchanged `pm_wakeup_irq=199` is stale pre-existing state and adds no proof.
- Battery wakeup-source active/event counts rose 176→178 and 184→186, but
  `wakeup_count` remained 0 and total active time grew only 9 ms. RTC source
  counts also rose +2 despite exactly one RTC IRQ and one resume. These
  co-increments have no timestamp/IRQ mapping in the receipt, so they cannot be
  interpreted as two wakes or as battery-caused wakes.
- The harness verified Wi-Fi radio enabled and Bluetooth powered/unblocked
  before and after; it did not test connectivity. Radio cleanup made no state
  changes, RTC was restored to empty, and temporary debug flags were restored.

### 2026-09-18 03:30 UTC — fetched upstream main has new suspend-adjacent changes

- Read-only `git fetch upstream main` advanced the local remote-tracking ref from
  `b3ee817` to `c97ecf6` while leaving the worktree untouched. Compared with
  this research branch's HEAD, upstream adds a kernel image bump associated
  with the ath12k Wi-Fi reconnect fix and changes the USB autosuspend udev rule
  to target only the DWC3 controller instead of the full USB tree (merged PRs
  #465 and #442). The latter overlaps the lab's earlier DWC3/runtime-PM
  investigation and could affect interpretation of image-level comparisons.
- The active Nova baseline and new Bluetooth-off control were captured on
  Armada version `20260915.feca679`, kernel `7.2.3`. I have not yet verified
  whether that running image includes the upstream USB-rule change or the
  exact bumped kernel package. Do not assume the stale branch's source view
  matches the device. Inspect installed receipts before rebasing/merging or
  attributing a behavior change to either commit.
- Fetch updated only Git's remote-tracking metadata; no branch merge, source
  edit, build, image change, or device mutation was made by this discovery.

### 2026-09-18 03:31 UTC — Nova's recorded source predates both fetched upstream changes

- Matched the baseline's recorded Armada version `20260915.feca679` to the
  corresponding Git tree. That tree does **not** contain upstream commit
  `98d8f53` (PR #442) or `a4daf4c` (PR #465): its USB udev rule still sets
  `power/control=auto` on every USB leaf device as well as the DWC3 controller,
  and its `Containerfile` pins kernel image digest
  `4659cccbecd0015e5ab6ffb566d59e19b5514f889914b7ecbba2dad65addb550`.
  Current fetched upstream main removes the USB-leaf rule and pins
  `9987eead115330b3ad8c0b5b73dbdbe8319e86a1c3200ae2636c5835a7a5e673`.
- Therefore both the completed Bluetooth-on baseline and in-progress control
  are from the pre-PR-442 / pre-PR-465 system image. The USB-rule correction
  explicitly says its s2idle impact should be nil because system suspend drops
  the DWC3 interconnect vote regardless of the runtime `power/control` value;
  however, the device's actual active rule and kernel image must be verified
  after wake before treating the new upstream image as equivalent.
- This is a real freshness limitation: counter comparison isolates Bluetooth
  only within the older Nova image. The next low-cost validation after the
  current control is to read the installed USB rule, active kernel package
  provenance, and USB device runtime-PM states over SSH; no build/update has
  been applied.

### 2026-09-18 03:33 UTC — research branch merged current upstream main

- Merged fetched `upstream/main` (`c97ecf6`, including PRs #442 and #465) into
  `feat/sm8550-suspend-lab`; merge commit is `15c9842`. The three in-progress
  modified research files were stashed and restored cleanly; `git diff --check`
  passes. The branch is now five commits ahead of its origin tracking branch;
  it has not been pushed.
- The merged source now uses upstream's DWC3-only USB autosuspend rule and
  kernel package digest `9987eead115330b3ad8c0b5b73dbdbe8319e86a1c3200ae2636c5835a7a5e673`.
  The live test remains on the older Nova image `20260915.feca679`; the merge
  changes only the research checkout, not the running device or detached
  experiment.

### 2026-09-18 03:35 UTC — PR #442's reverted USB-leaf rule likely did not affect this baseline

- Parsed the 30-minute baseline's pre/post runtime-PM inventory. It contains
  zero `/sys/class/usb` leaf-device entries both before and after, so the old
  blanket `SUBSYSTEM=="usb"` udev rule had no enumerated USB child to change
  during this cable-free test.
- The DWC3 platform controller itself already had
  `power/control=auto` and `runtime_status=suspended` before the test
  (`runtime_suspended_time=38,596,680 ms`). This is the controller rule retained
  by PR #442. After resume it was active in the post snapshot, which is a
  post-wake state and does not show its residency during the sleep window.
- This weakens PR #442's relevance to the measured 4.58%/h drain on the current
  cable-free Nova run: the rule's reverted leaf-device clause had no matching
  device here, and the retained DWC3 autosuspend was already active before
  sleep. It does not test USB-docked use or prove behavior inside the sleep
  transition. Receipts: run `20260918T025221Z-0dd0e448a37f`,
  `device/pre/runtime_pm.json` and `device/post/runtime_pm.json`.

- The matched Bluetooth-off control is run
  `20260918T032612Z-8e8f3f46c215`, requested at 03:26:12 UTC on the same
  `armada` target, `s2idle`, 1,800 seconds, Wi-Fi policy preserved, Bluetooth
  off, trace profile `none`. Its host manifest captured the pre-merge research
  HEAD `b42a3d5`; the upstream merge happened after launch and does not change
  the already-running device-side agent. The device has not yet returned its
  post-run receipt.

### 2026-09-18 03:36 UTC — baseline entered sleep with connected ath12k Wi-Fi

- Correction to the 03:31 and 03:35 shorthand: although the post-resume health
  snapshot showed `wlp1s0` down/no carrier, the baseline's **pre-suspend**
  runtime-PM snapshot shows Wi-Fi `carrier=1`, `operstate=up`, radio unblocked,
  and PCIe device `0000:01:00.0` driven by `ath12k_wifi7_pci` with
  `power/control=on` and runtime status `active`. Its Wi-Fi connection state
  before sleep therefore was not “radio enabled but disconnected.”
- The first 30-minute run is a connected-Wi-Fi, Bluetooth-on baseline. Its
  post-resume snapshot reports `wlp1s0` down and carrier 0, so the sleep/wake
  cycle did not preserve the link at capture time. The merged #465 change is
  specifically an ath12k reconnect kernel bump; its possible relation is
  resume/reconnect reliability, not yet battery drain.
- The ongoing Bluetooth-off run uses `--wifi-state preserve`, which does not
  guarantee identical association state. Once its receipt returns, compare
  `pre/runtime_pm.json` and radio metadata against this baseline. If Wi-Fi was
  not up/carrier before its suspend, its charge delta cannot cleanly isolate
  Bluetooth from the first run. No radio conclusion is drawn yet.

### 2026-09-18 — baseline kernel logs show Wi-Fi and DWC3 system-suspend callbacks succeeded

- Read-only analysis of the baseline's kernel PM trace shows the
  `ath12k_wifi7_pci` suspend-late callback returned 0 after ~93 ms and its
  suspend-noirq callback returned 0. The Qualcomm WCN power-sequence suspend
  callback also returned 0. On wake, ath12k resume-noirq returned 0, while
  resume-early took ~556 ms and the driver logged its chip/firmware identity.
  This is orderly callback completion, not evidence that Wi-Fi caused the
  charge loss or that firmware remained in its lowest-power state.
- DWC3's `genpd_suspend_noirq` also returned 0. Together with the controller's
  pre-run runtime-suspended state and zero USB leaf devices, these observations
  lower the priority of DWC3/USB as the immediate drain cause in this
  cable-free run. They do not expose AOP's accepted power level or DDR
  residency.
- After the cycle the netdev was `wlp1s0` down/carrier 0 in the capture. The
  newer upstream #465 kernel bump is described only as an ath12k reconnect fix;
  it may address this resume/link symptom, but no battery benefit is established.
  Raw callback timeline: `device/post/logs/journal-kernel.txt`, lines 52-53,
  338-380, 490, 565-595, and 879-904 for run
  `20260918T025221Z-0dd0e448a37f`.

### 2026-09-18 — upstream PR details narrow USB and Wi-Fi hypotheses

- Reviewed the merged PR metadata and upstream patch descriptions. PR #442's
  change is exactly deletion of the USB-leaf autosuspend rule while retaining
  DWC3's platform autosuspend rule. Its rationale is hub/input re-enumeration;
  the PR says system suspend suspends the USB tree and DWC3 drops its vote
  independently of `power/control`. Baseline snapshots show no `/sys/class/usb`
  entries and no USB child in DWC3's recorded device subtree, but the run did
  not capture a literal `/sys/bus/usb/devices` listing. After the current test,
  run that read explicitly before asserting there are no USB children.
- PR #465 changes only the kernel package image digest at the Armada layer.
  The package-side ath12k fix is about scan-priority delivery/WCN7850 scan
  refusal and reconnect delay after rfkill changes, not a documented suspend
  power-state change. The baseline log has no recorded scan refusal; its one
  system wake has only 2.38 seconds of monotonic-clock advance across the
  30-minute boottime interval, so repeated userspace reconnect loops are not
  evident. The 556 ms ath12k resume-early latency is a resume/connectivity
  lead only.
- Provenance caveat: the Nova reports source version `20260915.feca679`, whose
  source tree pins the old kernel image digest; its `uname -r` is `7.2.3`, and
  the device receipt does not include a package/image digest proving which
  kernel image was actually booted. Treat the old-digest conclusion as likely
  from image provenance, not a direct runtime package hash.

### 2026-09-18 — PR #465 kernel fix is a WMI scan-priority assignment

- Read-only `gh api` inspection of Armada Packages commit
  `adfcaf03f27faf5f8cfa1038551b6b55e78061ff` confirms the kernel patch adds
  one assignment in `ath12k_wmi_send_scan_start_cmd()`, copying the driver's
  computed scan priority into the outgoing WMI command. Its patch rationale is
  scan refusal/reconnect delay after rfkill unblock on WCN7850. It contains no
  suspend-state or power-management change. The same commit only updates the
  package patch manifest and series entry around that kernel patch.
- This makes #465 an unrelated radio-resume/connectivity fix for the drain
  question, although it may improve the observed post-resume netdev/link
  recovery. Testing its intended reconnect behavior is a simple rfkill
  block/unblock timing check; testing battery impact would require an A/B on
  the newer prebuilt kernel package and is not needed to interpret the current
  Bluetooth control.

### 2026-09-18 — the 30-minute APSS counter matches suspend time; DDR counters still do not name residency

- Baseline QCOM subsystem stats show APSS count +3 and accumulated duration
  +34,549,657,958 ticks, which converts to 1,799.461 seconds at 19.2 MHz,
  essentially the measured 1,799.476-second suspend interval. Named AOSD, CXSD,
  and scalar DDR stats did not change at all. This is consistent with APSS
  subsystem sleep across the whole interval, without a corresponding named
  system/collapse statistic; it still cannot distinguish firmware counter
  coverage from an unentered physical state.
- The separate DDR LPM `0xd0` duration advanced 34,702,115,760 ticks. The sum
  of all DDR frequency-bucket deltas was 34,702,115,840 ticks, a difference of
  only 80 ticks (about 4.2 microseconds). The 547 MHz bucket accounts for
  34,552,680,960 ticks, about 1,799.6 seconds at that scale. Thus the raw
  `0xd0` value tracks the sum of DDR frequency-duration records almost exactly;
  it is not independent evidence of memory self-refresh/collapse. The ID's
  physical mode remains undocumented.
- Exact before/after counters: `device/pre/qcom_stats.json` and
  `device/post/qcom_stats.json` in baseline run
  `20260918T025221Z-0dd0e448a37f`.

### 2026-09-18 — refreshed related issue and PR status

- Read-only `gh` refresh: [issue #264](https://github.com/armada-os/armada/issues/264)
  remains open with its Odin 2 report of 25 percentage points lost in 90 minutes
  with Bluetooth on, versus about 1%/hour after hard rfkill block. No comments
  or update since August 17. This is a cross-device hypothesis, not Nova proof.
- [Issue #265](https://github.com/armada-os/armada/issues/265) remains open;
  its Odin 2 warmth-after-Bluetooth-fix report has an Odin 3 Max confirmation
  comment from August 21. It concerns residual warmth after drain is reduced,
  a separate clue that sleep may still fail to reach deeper physical states.
- [PR #235](https://github.com/armada-os/armada/pull/235) is still an open
  fake-suspend-only radio opt-in and reports `mergeStateStatus=DIRTY` (latest
  update/comment September 12). Correction to the earlier 03:00 entry: GitHub
  no longer reports `UNKNOWN`. Its ~300→180mA Wi-Fi+Bluetooth-off measurement
  is from fake suspend on RP6, not native s2idle and not a Nova control.
  No newly open native-s2idle fix appeared in the refreshed query.

### 2026-09-18 — matched Bluetooth-off s2idle control is in progress

- Detached 30-minute run `20260918T032612Z-8e8f3f46c215` started at
  `2026-09-18T03:26:12Z`, requesting explicit `s2idle`, unplugged, Bluetooth
  off, Wi-Fi state preserved, and no tracing. Its host manifest records the
  requested controls and runner/source provenance. The first status attempt
  timed out while the Nova was suspended, consistent with the prior RTC-timed
  run; no result has been retrieved yet.
- This is intended as a matched radio control against
  `20260918T025221Z-0dd0e448a37f`, with Bluetooth as the only requested
  variable. Interpretation still depends on the new run's recorded pre-sleep
  Wi-Fi carrier/operstate matching the connected baseline; `preserve` retains
  whatever Wi-Fi state existed and does not force association.
- Harness review confirms the control: Wi-Fi changes use `nmcli radio
  wifi off/on`, while `preserve` performs no association control. The pre-run
  receipt `device/meta/radio-before.json` records the radio toggle, and
  `device/pre/runtime_pm.json` records `wlp1s0` carrier/operstate plus ath12k
  runtime state. The baseline began with Wi-Fi associated/up and Bluetooth
  powered/unblocked. If the current run's Wi-Fi link does not match, the
  least-work next isolation is another 30-minute unplugged s2idle with Wi-Fi
  explicitly off and Bluetooth preserved/on; compare it with the connected
  baseline to estimate the aggregate connected-Wi-Fi cost.
- Expected RTC resume is about `03:56:12Z`. On retrieval, first verify the
  run completed in the same boot, actual suspended duration, cleanup/radio
  restoration, battery counter delta, and Wi-Fi pre-state before attributing
  any drain difference to Bluetooth.

### 2026-09-18 — 30-minute Bluetooth-off control completed

- Run `20260918T032612Z-8e8f3f46c215` completed successfully in the same boot,
  with `s2idle` clock separation of `1799.209` seconds and battery-counter
  measurement interval `1801.729` seconds. RTC IRQ 199 incremented once and
  matched the armed wake; monotonic time advanced 2.520 seconds. No reboot or
  unintended input-power connection was recorded.
- This is a close radio match to baseline
  `20260918T025221Z-0dd0e448a37f`: both started with Wi-Fi enabled,
  `wlp1s0 carrier=1, operstate=up`, and ath12k runtime-active; Bluetooth
  started powered/unblocked in both, but was rfkill-blocked only for this run.
  Both remained cable-free. Battery charge-counter loss was `131,180 uAh`
  (`262.1 mA` gauge-derived average; capacity 72% to 70%) with Bluetooth off,
  versus `150,201 uAh` (`300.1 mA`; 75% to 72%) in the baseline. Normalized
  using `charge_full=6,559,000 uAh`, that is about `4.00%/h` versus
  `4.58%/h`, a roughly 13% reduction in this one matched pair. This suggests
  Bluetooth contributes some drain on Nova, but it does not account for all
  of the reported ~5%/h; replication is still needed before estimating effect.
- AOSD/CXSD/scalar DDR counters remained zero. APSS advanced by 3 entries and
  `34,543,989,333` ticks. Separate DDR LPM `0xd0` advanced
  `34,705,167,980` ticks, and the 547 MHz bucket advanced
  `34,571,155,456` ticks. As in baseline, those separate records span about
  the sleep interval without naming the physical DDR mode.
- Cleanup restored the Bluetooth rfkill soft-block to unblocked, but its
  follow-up `bluetoothctl power on` returned 1; the receipt captured the HCI
  as still not powered after rfkill unblock. Therefore the saved original
  Bluetooth power state (`yes`) may not have been restored. Verify current
  live state and restore it before any next suspend run.
- Evidence is in the run archive's `device/{pre,post}/power_supplies.json`,
  `device/{pre,post}/runtime_pm.json`, `device/{pre,post}/qcom_stats.json`,
  `device/meta/radio-before.json`, `device/meta/radio-cleanup-after-rfkill.json`,
  `device/cleanup/radios.json`, `device/derived/summary.json`, and
  `result.md`.
- Correction after delayed read-only verification: `bluetoothctl power on`
  returned `org.bluez.Error.Busy` during cleanup, but a fresh host preflight at
  `2026-09-18T04:00:12Z` shows `Powered: yes`, `PowerState: on`, and Bluetooth
  soft/hard block both `no`; Wi-Fi radio is also enabled. The radio recovered
  without a manual change. The first preflight output was retained under
  `../sm8550-suspend-lab-runs/preflight-after-20260918T032612Z-8e8f3f46c215.json/`.

### 2026-09-18 — source audit tightens what zero Qualcomm sleep counters mean

- Rechecked Linux v7.2 `qcom_stats.c`: `apss` is read from its own SMEM
  subsystem record, while the three scalar AOSD/CXSD/DDR files are separately
  read from the RPMh stats window. The `ddr_stats` LPM/frequency table is a
  third interface; on SM8450+ Linux asks AOP to sync its duration fields with
  QMP before displaying them. Linux decodes the `0xd0` LPM identifier but
  supplies no physical-state name for it.
- So the 30-minute baseline's APSS and DDR-table increments do not validate
  the scalar AOSD/CXSD/DDR records. Those records staying zero means no
  transition was recorded in those named firmware counters, assuming the
  firmware updates them on this image; it does not prove that DDR had no
  low-power residency or identify physical rail state. The live data rules
  out a completely static/empty stats interface, but leaves the named-counter
  update path and AOP's selected physical state unresolved. The driver formats
  firmware's fields but does not validate that these three payloads advanced
  on this Nova image, so the conditional must remain explicit.
- Source: [Linux v7.2.3 qcom-stats binding](https://github.com/gregkh/linux/blob/v7.2.3/Documentation/devicetree/bindings/soc/qcom/qcom-stats.yaml#L12-L52)
  and [qcom_stats.c](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L49-L63),
  [scalar and DDR readers](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L129-L222),
  [RPMh record naming/layout](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L244-L287),
  [SM8550 stats memory/QMP node](https://github.com/gregkh/linux/blob/v7.2.3/arch/arm64/boot/dts/qcom/sm8550.dtsi#L4651-L4666).
- A potentially useful follow-up surfaced in the kernel history: an earlier
  Qualcomm DDR-stat patch requested `{class: ddr, res: drvs_ddr_votes}` over
  AOSS QMP and read an appended table of 18 aggregated DDR AB/IB votes. The
  current upstream stats code intentionally includes DDR LPM/frequency data
  but not that vote-table request; the later series explicitly says resource
  vote tables, possibly including CX rail votes, are a separate feature.
  This could help identify active bandwidth clients, but does not yet show
  suspend-time vetoes and has not been validated against Nova's AOP firmware.
  After the current run, check whether the existing kernel can support a tiny
  diagnostic module; do not infer compatibility or issue this QMP request
  until its target memory layout and query behavior are confirmed.
- Source: [earlier qcom_stats vote-table patch](https://lkml.iu.edu/2311.3/07915.html#168),
  [later series scope that omits DDR/CX vote tables](https://patchew.org/linux/20250429-ddr._5Fstats._5F-v1-0-4fc818aab7bb%40oss.qualcomm.com/diff/20250611-ddr._5Fstats._5F-v5-0-24b16dd67c9c%40oss.qualcomm.com/).

### 2026-09-18 — next 30-minute Wi-Fi-off control launched

- Read-only preflight `preflight-20260918T040012Z-35c1744e2524` confirmed the
  Nova was back on the same boot and image, Bluetooth powered/on with both
  rfkill blocks clear, and Wi-Fi radio enabled. The earlier cleanup's
  transient BlueZ `Busy` error had cleared without manual intervention.
- Started `20260918T040206Z-2913994f60b9` at `04:02:08Z`: 1,800-second
  unplugged `s2idle`, tracing off, Wi-Fi radio off, Bluetooth preserved. This
  isolates the enabled-Wi-Fi condition against the 30-minute baseline, where
  both radios were on, and complements the Bluetooth-off run. It estimates
  each radio's effect against the common both-on baseline; interactions remain
  unmeasured. The run's pre-suspend `wlp1s0` carrier/operstate must still be
  checked before calling Wi-Fi disabled an associated-link comparison.
- Expected RTC wake is about `04:32:08Z`. Retrieve after network recovery,
  verify same boot and cleanup restored Wi-Fi/Bluetooth/RTC, then compare the
  gauge charge-counter loss per measured hour. No result is available yet.

### 2026-09-18 — QMP diagnostic route has exported APIs but no userspace read endpoint

- Linux v7.2.3 exports GPL `qmp_get()` and `qmp_send()`. `qmp_get()` requires
  a client device whose DT node has a `qcom,qmp` phandle; the SM8550
  `qcom,rpmh-stats` node already has that phandle. `qmp_send()` transmits one
  request and waits for AOSS acknowledgement. That leaves a small kernel
  diagnostic consumer technically possible without changing the sleep
  firmware interface, provided its module ABI can be satisfied.
- The shipped `/sys/kernel/debug/qcom_aoss` entries are mode `0200` and have
  only a write handler. They issue four fixed controls: DDR frequency,
  prevent AOSS sleep, prevent CX collapse, and prevent DDR collapse. They
  provide no readback or arbitrary QMP-message interface, so they cannot
  safely substitute for a stats query. No control was written.
- Before a module experiment, still verify `CONFIG_MODVERSIONS`, module
  signing policy, exported symbols in the running kernel, and availability of
  matching headers/`Module.symvers`. The historic `drvs_ddr_votes` message and
  appended table format also need confirmation against Nova's AOP/shared-memory
  layout; it is a lead, not a validated query. No module or kernel change was
  built or loaded.
- Sources: [qmp_send acknowledgement and exports](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_aoss.c#L1860-L1955),
  [qmp_get phandle lookup/export](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_aoss.c#L2206-L2258),
  [fixed write-only QMP debugfs controls](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_aoss.c#L2301-L2418),
  [SM8550 QMP phandle](https://github.com/gregkh/linux/blob/v7.2.3/arch/arm64/boot/dts/qcom/sm8550.dtsi#L4651-L4666).

### 2026-09-18 04:06 UTC — Wi-Fi-off run remains asleep at early status check

- A status attempt at `04:06:47Z`, about four minutes after the planned start,
  timed out connecting to SSH. The run is RTC-timed for about `04:32:08Z`, so
  this is consistent with the Nova being suspended and is not evidence of a
  run failure. The host archive still contains only its manifest; wait until
  the RTC wake window plus Wi-Fi recovery before checking status or retrieving
  results. No device state was changed by the failed SSH attempt.

### 2026-09-18 — if DDR votes are queried, extend qcom_stats at its owned dynamic table

- A closer source comparison refines the earlier overlap warning. Linux v7.2.3
  `qcom_stats` already owns the `0x0c3f0000/0x400` mapping. Its `ddr_stats`
  reader sends `{class: ddr, action: freqsync}`, reads the live entry count,
  then copies exactly that many 16-byte records from the table at offset 8
  within the configured DDR area (Nova's table begins at resource offset
  `0xb8`).
- Qualcomm's older vote-table patch then sends
  `{class: ddr, res: drvs_ddr_votes}` and reads 18 vote words immediately after
  the actual header plus `entry_count * sizeof(entry)` payload. The community
  diagnostic's fixed `QMP +0xf01f0` address is the same as stats-resource
  offset `0x1f0`; that assumes 19 entries. A different entry count moves the
  vote table, so copying that constant is not robust for Nova.
- If a vote snapshot becomes worth building, the smallest credible design is
  to extend the existing `qcom_stats` reader, reuse its mapping/QMP handle,
  calculate the tail from the live entry count, and bounds-check it against
  the 0x400 resource. Do not add a competing standalone `ioremap` or widen
  QMP's resource. Even a correct awake vote snapshot would identify current
  aggregate DDR bandwidth requests only; it would not establish a
  suspend-time veto or AOP's accepted sleep state. No patch or query was made.
- Sources: [v7.2.3 DDR reader, QMP sync, and dynamic entry-count copy](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L1356-L1408),
  [v7.2.3 probe mapping and stats offset configuration](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L1541-L1613),
  [Qualcomm's vote-table placement after the actual stats payload](https://lkml.iu.edu/2311.3/07915.html#168),
  plus the Nova resource declaration at
  [SM8550 DTS](https://github.com/gregkh/linux/blob/v7.2.3/arch/arm64/boot/dts/qcom/sm8550.dtsi#L4651-L4666).

#### Addendum — the current debugfs dump does not expose `entry_count`

Both completed 30-minute `ddr_stats` dumps print 14 recognized rows (four LPM
IDs and ten frequency buckets), but upstream reads `entry_count` without
printing it and skips zero/unknown frequency rows. Therefore 14 is only a
lower bound, not a safe buffer-layout value; the fixed `0x1f0` location cannot
be confirmed from existing userspace output. A diagnostic in the current
reader should report the count it already reads and derive/bounds-check the
vote tail from that value.

### 2026-09-18 04:12 UTC — related Armada sleep issues and radio PR checked

- Current open Armada issue [#264](https://github.com/armada-os/armada/issues/264)
  reports Bluetooth remaining powered on AYN Odin 2 and a user-reported fall
  from about 25%/90 min to ~1%/h after rfkill-blocking Bluetooth in both
  `s2idle` and `deep`. That is a useful SM8550-family comparison, but it is a
  different board/firmware and a much larger BT effect than the Nova's one
  matched 30-minute result so far (about 4.58%/h both radios on vs 4.00%/h BT
  blocked with Wi-Fi associated). Do not assume its root cause or magnitude
  transfers to Nova. Open follow-up [#265](https://github.com/armada-os/armada/issues/265)
  reports localized warmth despite low drain and suggests sampling current
  and wakeup sources; Odin 3 warmth is also reported in a comment.
- Open [PR #235](https://github.com/armada-os/armada/pull/235) adds opt-in
  Wi-Fi/Bluetooth rfkill around **fake-suspend** only. Its RP6 measurement is
  ~300 mA with radios on, ~180 mA off, and ~17 seconds to restore Wi-Fi; no
  device is opted in by default. It does not modify Nova's native `s2idle`
  path, but the current Wi-Fi-off control will help separate the radio
  contribution on Nova.
- Open [issue #428](https://github.com/armada-os/armada/issues/428), "Add
  always on sleep debug logs," has an empty body, so its requested behavior
  cannot be compared with this temporary per-run lab harness yet. No issue or
  PR was changed, and no message was sent.

### 2026-09-18 — DDR `0xd0` delta duplicates the frequency-bucket total in both 30-minute runs

- Recomputed the raw `ddr_stats` pre/post receipts for both completed 30-minute
  tests. In baseline `20260918T025221Z-0dd0e448a37f`, the `0xd0` duration
  increased by `34,702,116,172` ticks; the sum of all DDR-frequency bucket
  duration deltas was `34,702,116,352` ticks (180 ticks apart). In Bluetooth-off
  run `20260918T032612Z-8e8f3f46c215`, the corresponding deltas were
  `34,705,167,568` and `34,705,167,872` ticks (304 ticks apart).
- The near-exact equality means the observed `0xd0` counter is not independent
  evidence that DDR entered a deeper low-power mode. Linux source labels this
  numeric bucket as a DDR LPM statistic but does not name its physical state;
  its measured duration tracks the total frequency-table time in these runs.
  The firmware meaning and reason for this equality remain unresolved.
- This narrows/corrects the 02:35 interpretation: `0xd0` advanced across the
  sleep window, but that fact alone cannot be used to claim DDR low-power
  residency. Keep the state opaque pending a vendor definition or independent
  firmware observation.
- Raw sources: pre/post `device/{pre,post}/files/sys/kernel/debug/qcom_stats/ddr_stats`
  in the two run archives above. The public parser labels the number and
  frequency fields but does not map `0xd0` to hardware state:
  [Linux v7.2.3 qcom_stats.c](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L1282-L1408).

### 2026-09-18 — upstream history cautions against restoring the old DDR-vote patch wholesale

- The original 2023 Qualcomm DDR stats implementation, including the DDR vote
  query, was reverted after reports of boot failures on older SM8150/SDM7180
  platforms; the revert attributes the breakage to differences in shared
  RPMh-stats layouts. The author called the data useful but deferred it until
  it could be enabled conditionally.
- The later 2025 upstream implementation was reintroduced with per-SoC stats
  offsets for SM8450-and-newer and provides LPM/frequency counters. It omits
  the old DDR-vote-table query. Therefore do not restore or transplant the
  2023 patch as-is. Any vote diagnostic should be a small, explicitly guarded
  extension to the existing SM8550 `qcom_stats` config, with validated buffer
  boundaries and a known vote-table layout.
- Sources: [upstream revert and stated older-SoC layout failures](https://lkml.iu.edu/2312.1/08468.html),
  [later v5 series scope](https://patchew.org/linux/20250611-ddr._5Fstats._5F-v5-0-24b16dd67c9c%40oss.qualcomm.com/).

## 2026-09-18 04:24 UTC — SM8550 system-domain gap is an s2idle request limitation, not proof of firmware residency

Upstream Linux v7.2 DTS review found that SM8550's PSCI genpd hierarchy ends at `cluster_pd`: its CPU domains have cluster idle states, but there is no parent `system_pd` or `domain_ss3`. SM8750 adds a `system_pd` with a state labeled `domain_ss3` and parameter `0x0200c354`. In PSCI OSI mode, s2idle suspends the genpd hierarchy and passes the selected domain state to `CPU_SUSPEND`; the missing SM8550 system domain is therefore a credible limit on the system-level state Linux can request through this hierarchy. It does not show which state AOP/firmware actually enters.

Do not copy `0x0200c354` into SM8550 based on the SM8750 DTS. The generic binding defines it only as the `power_state` argument; the value's Qualcomm state mapping and firmware prerequisites are not established for Nova. A recent report of repeatable resets on a different Snapdragon X2 platform after requesting that value is a further reason to require exact platform evidence first. The existing `deep` test is not a test of this domain state: `deep` uses PSCI `SYSTEM_SUSPEND`, while the relevant s2idle OSI path uses `CPU_SUSPEND`.

Sources reviewed: [SM8550 DTS](https://github.com/torvalds/linux/blob/v7.2/arch/arm64/boot/dts/qcom/sm8550.dtsi#L369-L385), [SM8550 domain hierarchy](https://github.com/torvalds/linux/blob/v7.2/arch/arm64/boot/dts/qcom/sm8550.dtsi#L781-L833), [SM8750 SS3 state and hierarchy](https://github.com/torvalds/linux/blob/v7.2/arch/arm64/boot/dts/qcom/sm8750.dtsi#L199-L215), [PSCI genpd and s2idle path](https://github.com/torvalds/linux/blob/v7.2/drivers/cpuidle/cpuidle-psci-domain.c#L32-L43), [PSCI suspend paths](https://github.com/torvalds/linux/blob/v7.2/drivers/firmware/psci/psci.c#L501-L545), [generic PSCI binding](https://github.com/torvalds/linux/blob/v7.2/Documentation/devicetree/bindings/arm/psci.yaml#L89-L99), [separate-platform reset report](https://lkml.iu.edu/2609.1/15301.html).

## 2026-09-18 04:26 UTC — Armada Nova board DTS adds no PSCI system-domain state

Checked the checked-out Armada kernel DTS overlay and patch stack. Nova's board DTS includes `qcs8550-retroidpocket-rp6.dts`, which in turn includes `qcs8550-ayn-common.dtsi`; the Nova file only changes model/compatible and panel, touchscreen, and gamepad details. Targeted searches of `kernel/dts` and `kernel/patches` found no SM8550 `system_pd`, `domain_ss3`, or `arm,psci-suspend-param` addition. This agrees with upstream's SM8550 hierarchy finding: Armada's tracked board overlay does not currently supply the missing system-level PSCI OSI state. This is source-tree evidence, not proof of the exact live DTB; confirm the running DT/genpd after the current test resumes.

Local sources: `armada-packages/kernel/dts/qcs8550-retroidpocket-rpnova.dts` (includes RP6 board file and contains only Nova-specific display/touch/gamepad edits) and `armada-packages/kernel/dts/qcs8550-retroidpocket-rp6.dts` (includes AYN common file). Checked source tree: `armada-packages/kernel/dts/` and `armada-packages/kernel/patches/`.

### 2026-09-18 — Qualcomm downstream Kalama corroborates cluster-only OSI topology; system suspend is separate

A source review of Qualcomm's downstream SM8550-family/Kalama device tree found the PSCI domain hierarchy is CPUs under one `CLUSTER_PD`, with the cluster advertising only `CLUSTER_PWR_DN` and `APSS_OFF`. Its `APSS_OFF` label describes cluster E3 / LLCC-off and uses parameter `0x4100c344`; it is not evidence of a whole-system SS3 state. This independently corroborates the public upstream and Armada overlay result, but the downstream tree is from a different SM8550-family device/branch and is medium-confidence corroboration only, not proof of Nova's shipping firmware behavior.

Qualcomm's SM8550-family PSCI `SYSTEM_SUSPEND` implementation for suspend-to-RAM is separately reported in upstream Linux discussion. This supports the distinction already made from the Nova direct `deep` test: firmware implementing SYSTEM_SUSPEND does not show that an s2idle OSI request through CPU_SUSPEND has a system-level domain state. The generic PSCI binding represents OSI with hierarchical domains and per-domain idle-state parameters; generic TF-A documentation describes firmware validation/denial semantics, but is not a Qualcomm firmware contract.

Sources: [Qualcomm downstream Kalama PSCI hierarchy](https://android.googlesource.com/kernel/msm-extra/devicetree/+/refs/heads/android-msm-eos-android13-wear-kr3-pixel-watch/qcom/kalama.dtsi#713) and [cluster sleep-state labels/parameters](https://android.googlesource.com/kernel/msm-extra/devicetree/+/refs/heads/android-msm-eos-android13-wear-kr3-pixel-watch/qcom/kalama.dtsi#316), [SM8550 SYSTEM_SUSPEND discussion](https://lists.openwall.net/linux-kernel/2024/02/23/234#L82-L87), [PSCI DT binding](https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/arm/psci.yaml#L880-L904), [generic TF-A OSI semantics](https://trustedfirmware-a.readthedocs.io/en/v2.14.0/design_documents/psci_osi_mode.html#psci-set-suspend-mode).

### 2026-09-18 04:29 UTC — Armada Odin 2 issue #274 adds measured IRQ and PHY suspects, but is not Nova proof

Read closed Armada issue [#274](https://github.com/armada-os/armada/issues/274), a measured Odin 2 / SM8550 case. On its older `20260817.8b49045` / `7.2.0-rc7` SD-card install, AOSD/CXSD counters stayed at zero during successful `rtcwake -m freeze`; `mmc0` IRQ 170 advanced roughly 28–35 times/s during suspend even while its controller reported runtime-suspended; and the DWC3 USB PHY stayed runtime-active with `power/control=on`. The issue proposes (not confirms) SDHCI clock gating and a USB-PHY management fix; it also mentions CPU0 deep idle disabled by firmware. The issue is closed but provides no follow-up resolution for these observations.

Treat as comparison leads only: the Nova has a different board/storage setup, and our prior Nova DWC3 skip-PHY A/B showed no relevant residency or drain improvement, so the Odin2 PHY report does not override that negative Nova result. Current 30-minute Wi-Fi-off run has tracing disabled and cannot reveal in-sleep IRQ rates; do not infer that its aggregate pre/post IRQ deltas exclude an IRQ storm. Once this run returns, compare Nova's DT/storage path and inspect its captured interrupt receipts; a short targeted IRQ trace would be a separate next test only if this remains plausible.

### 2026-09-18 04:31 UTC — Nova root storage is not the mmc0 SD slot from Odin 2 issue #274

The live Nova preflight at `preflight-after-20260918T032612Z-8e8f3f46c215.json/preflight-20260918T040012Z-35c1744e2524.json` reports `/` as the expected composefs overlay and the backing `/sysroot` Btrfs partition as `/dev/sda20` (`PARTLABEL=ARMADA_ROOT`). Thus Nova is not booted from the `mmc0` SD slot described as Odin 2's rootfs in issue #274; its specific “do not gate the rootfs SDHCI” constraint does not transfer. This storage map does not rule out `mmc0` generating interrupts on Nova, and the current test's aggregate pre/post IRQ snapshots cannot expose a suspend-only rate. Check its live `mmc0`/UFS mapping and use an in-sleep trace only if evidence warrants it.

### 2026-09-18 04:32 UTC — Wi-Fi-off 30-minute run: first post-RTC SSH check timed out

At 04:32:13 UTC, about five seconds after the nominal 30-minute RTC wake, `host status` for `20260918T040206Z-2913994f60b9` timed out connecting to `192.168.0.20:22`. This is only the first reconnect check; it does not establish missed RTC wake or a failed run. Prior Wi-Fi-radio-off cleanup took several minutes for SSH/Wi-Fi to return. Wait briefly, then retry status; retrieve only after SSH and cleanup are available.

### 2026-09-18 04:39 UTC — Wi-Fi-off 30-minute control completed on Nova

Run `20260918T040206Z-2913994f60b9` completed and was retrieved. It selected/observed `s2idle`, had 1799.192 s suspend-clock separation, returned through the expected RTC wake source, kept the same boot ID, and reported suspend success. The device pre-state had Wi-Fi enabled and connected/up (`wlp1s0`, carrier 1; ath12k PCI device runtime-active), Bluetooth powered and rfkill-unblocked, battery discharging at 69%, and USB/wireless supplies offline. The run disabled only Wi-Fi; cleanup restored Wi-Fi and the RTC alarm, with no trace/debug controls changed. Device-side checksums passed for all 4,433 files.

Battery charge-counter loss was 82,644 uAh over 1801.557 s, average gauge-derived draw 165.15 mA, about 2.52%/h using the captured 6,559,000-uAh full-charge value; capacity moved 69% to 68%. The matched 30-minute single-run samples currently read: both radios on 300.09 mA / 4.575%/h; Bluetooth blocked with Wi-Fi on 262.11 mA / 3.996%/h; Wi-Fi off with Bluetooth on 165.15 mA / 2.518%/h. This points to a substantial Wi-Fi-associated reduction, but each condition has only one run and gauge/start-condition noise remains. Repeat the Wi-Fi-off/Bluetooth-on run before treating the difference as stable.

AOSD, CXSD, and scalar DDR sleep counters again had zero count/duration deltas. The opaque DDR `0xd0` duration advanced 34,702,963,010 ticks, within 190 ticks of the sum of the DDR frequency-bucket deltas (34,702,963,200); it is not independent proof of a self-refresh residency. IRQ 170 `mmc0` advanced only 48 counts during the 1799-s interval, comparable to the other two Nova runs (44 and 48), not the Odin 2 issue's reported ~28–35/s storm. `ufshcd`, `apps_rsc`, and `arch_timer` advanced 17,123, 10,600, and 19,687 counts respectively; these were similar across the other two Nova runs, so they are persistent leads, not evidence of a Wi-Fi-off-specific effect or confirmed wakeups. The pre/post IRQ snapshots cannot locate those events within suspend with per-event timing.

Evidence: `device/derived/summary.json`, `device/pre/power_supplies.json`, `device/pre/runtime_pm.json`, `device/pre/qcom_stats.json`, `device/post/qcom_stats.json`, `device/pre/interrupts.json`, `device/post/interrupts.json`, `device/cleanup/summary.json`, and `checksum-verification.json` under the run archive. Conclusion remains observation-only; no code, kernel, DTB, or device policy was changed.

### 2026-09-18 04:40 UTC — repeat Wi-Fi-off/Bluetooth-on 30-minute control started

Started run `20260918T043959Z-8e885685e77c` on target `armada`: explicit `s2idle`, 1800 seconds, Wi-Fi radio off, Bluetooth preserved, tracing disabled, unplugged per the current test setup. Nominal RTC wake is 05:10 UTC. The outcome and pre-state still need retrieval; no conclusion is attached to this repeat yet.

### 2026-09-18 04:41 UTC — existing ufs-irq trace profile can test whether UFS IRQs occur during suspend

Read-only review of the current lab runner found an existing `ufs-irq` profile that uses tracefs already present on the device: it filters `irq_handler_entry/exit` to the discovered `ufshcd` IRQ and records available UFS request/runtime-PM events plus device-PM callback events. This needs no kernel or module build and uses a private trace instance. The pre/post counters alone show UFS IRQ totals near 17k–19k across all three 30-minute runs but cannot say when they occurred. After the current Wi-Fi-off repeat is retrieved, a short 60-second `ufs-irq` trace is the lowest-cost next test to see whether those IRQs recur inside s2idle and whether they line up with UFS activity; no IRQ masking, unbind, clock gating, or storage changes are proposed.

### 2026-09-18 04:42 UTC — live Nova genpd snapshot exposes only cluster PSCI domain; S1 counters moved during the run

The retrieved run's live `/sys/kernel/debug/pm_genpd` snapshot contains 48 total genpds but only one PSCI topology domain, `power-domain-cluster`, with states S0/S1; no system-level PSCI domain appears. Its S1 debug counters changed from Usage 216 / Rejected 417 / S2idle 630 before the run to Usage 223 / Rejected 434 / S2idle 654 after it. Record this as Linux genpd accounting, not proof of AOP selection or physical residency: AOSD/CXSD/scalar DDR qcom_stats remained zero, the S1 `Time(ms)` field displayed 5 both before and after, and the precise counter semantics need source validation before interpreting the small Usage delta. This live observation matches the source-tree finding that the currently running Nova kernel has only a cluster PSCI domain, but does not show whether firmware independently selects a deeper state.

### 2026-09-18 04:45 UTC — Nova UFS and apps-RSC IRQ counters are concentrated on CPU0 across all three runs

Compared per-CPU interrupt deltas in all three successful 30-minute s2idle receipts. Every counted `ufshcd` IRQ (IRQ 169: 18,742 / 19,041 / 17,123) and `apps_rsc` IRQ (IRQ 14: 10,272 / 10,689 / 10,600) landed on CPU0; `mmc0` (IRQ 170: 48 / 44 / 48) was also CPU0-only. `arch_timer` was spread across all eight CPUs (~18.6k–19.7k total). Because each interval had ~1799 s of boot-minus-monotonic suspend separation and only about 2.4 s monotonic advancement, most of these aggregate IRQ increments occurred during the s2idle interval, not ordinary awake runtime. They are not automatically equivalent to full system wakeups: the pre/post counters do not show event timestamps, wake-source classification, or time spent servicing each IRQ. The repeated CPU0 UFS/RSC activity is now a more concrete no-build trace target than the Odin-specific mmc0 storm; use the existing short `ufs-irq` trace after the running repeat completes.

### 2026-09-18 04:50 UTC — archived UFS traces qualify the IRQ-count inference and identify one usable capture

Re-analyzed the two archived 45-second `ufs-irq` captures at `../sm8550-suspend-lab-runs/20260917T213335Z-d3f423182f8b/` and `../sm8550-suspend-lab-runs/20260917T213812Z-1f8ded068061/`. The first trace has 2,214 events over 2.589 s and zero dropped events, but its trace metadata has no suspend-inclusive clock selection; its event timestamps cover only awake transition time. This is not evidence that the middle of that suspend was quiet. The second explicitly selected `[boot]`, spans 46.687 s around a measured 44.220 s s2idle interval, and reports zero dropped events on every CPU. Its 6,612 events are concentrated at the edges: 6,220 in relative second 0, none in seconds 1–44, and 392 in seconds 45–46. In this one sampled window, the `ufshcd` IRQ/command activity appears around suspend entry and wake, with no UFS events through the middle of the actual s2idle interval.

Correction to the 04:45 interpretation: the ~1799 s boot-minus-monotonic separation proves that each 30-minute test included a long suspend interval, but aggregate pre/post IRQ deltas alone do not locate the 17k–19k UFS or ~10.6k apps-RSC events inside that interval. Do not claim those counts mostly occurred during sleep based on the clock separation. The edge-only 45-second trace conflicts with that inference for its sampled window; because it was a single charging/radios-preserved sample, it does not settle the untraced unplugged Wi-Fi-off conditions. Repeat a short `[boot]`-clock `ufs-irq` capture after the active Wi-Fi-off control, matching its unplugged/Wi-Fi-off/Bluetooth-on state. Do not mask IRQs or alter storage/power policy.

### 2026-09-18 04:50 UTC — Linux genpd counters count PSCI staging and rejected returns, not hardware residency

Checked the exact Linux v7.2.3 path used by this image (`armada-packages/kernel/BASE.env` pins 7.2.3; the patch stack does not modify genpd or PSCI accounting). On the Nova `power-domain-cluster` S1 row, S2idle +24 means 24 successful synchronous genpd power-off callbacks were accounted as s2idle requests. In PSCI OSI, that callback stages the domain state for the later `CPU_SUSPEND`; it does not itself power the cluster off. The Rejected delta of +17 is consistent with 17 nonzero PSCI returns subsequently correcting genpd Usage, leaving net Usage +7, or seven calls that Linux did not reject (assuming there were no separate genpd callback failures). This is useful evidence that the PSCI request sometimes returns successfully from Linux's perspective, but it does not prove AOSD/CXSD/DDR or physical cluster residency.

The unchanged S1 `Time(ms)=5` is expected for this path: `genpd_sync_power_off/on()` do not call the ordinary genpd idle-time accounting routine. That field is not a residency measurement for these s2idle PSCI transitions. Sources: [v7.2.3 genpd sync accounting](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pmdomain/core.c#L801-L824), [s2idle counters and idle-states output](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pmdomain/core.c#L1404-L1443), [PSCI genpd state staging](https://github.com/gregkh/linux/blob/v7.2.3/drivers/cpuidle/cpuidle-psci-domain.c#L32-L44), and [PSCI suspend return/rejection path](https://github.com/gregkh/linux/blob/v7.2.3/drivers/cpuidle/cpuidle-psci.c#L64-L106).

### 2026-09-18 04:51 UTC — IRQ trace counts do not reconcile with interrupt snapshots; suspend silence is not yet conclusive

Joined each archived 45-second UFS trace with that run's pre/post `/proc/interrupts` snapshots. In the first run, IRQ 169 (`ufshcd`) advanced by 19,066 while the local-clock trace recorded 547 IRQ-169 handler entries. In the second run, IRQ 169 advanced by 20,710 while the boot-clock trace recorded 1,624 entries; IRQ 14 (`apps_rsc`) advanced by 14,225 but was not selected by that trace profile. All per-CPU trace stats show zero drops/overruns and the trace headers report every written entry still in the buffer, so ordinary ring-buffer overflow does not explain the mismatch.

This is a material instrumentation/interval mismatch. Until the runner timeline and kernel tracing behavior explain why the snapshots count far more interrupts than the active trace, the 45-second trace's 45-second UFS-event gap cannot establish that UFS IRQs were absent during s2idle. It establishes only that the selected tracepoint recorded no UFS IRQ/request events in that portion of the recorded boot-clock window. The `ufs-irq` repeat proposed above should also snapshot `/proc/interrupts` immediately around trace start/stop and compare exact deltas; inspect when snapshots, tracing_on, suspend dispatch, and post-resume collection occur before interpreting the result. No IRQ or device policy was changed.

To isolate the mismatch, added narrow `ufshcd`/`apps_rsc` `/proc/interrupts` counter snapshots immediately before trace enable, before trace disable, and immediately after trace disable in `sm8550_suspend_lab.py`. The snapshots are saved with trace metadata and bracket the trace-active window, so the next short capture can distinguish an in-suspend tracing gap from IRQ increments that fall in the broader pre/post snapshot window. This only changes the research recorder; it does not modify device power settings. Host-only `self-test`, Python AST parsing, and `git diff --check` all pass. Deploy this updated recorder only in the next controlled UFS trace after the current 30-minute run is retrieved.

The runner ordering explains why the full pre/post IRQ delta is not a trace-window count: it captures the pre snapshot before radio/sleep preparation, RTC setup, and `trace_start()`, then calls `trace_stop()` immediately after suspend returns and only afterward captures the post snapshot. The 2026-09-17 pre IRQ snapshot was at 21:38:22, trace start at 21:38:23, trace stop around 21:39:10, and post IRQ snapshot at 21:39:14. So the counter delta includes untraced setup/teardown intervals; the archive has no per-file timestamps for the IRQ reads, so their exact contribution is unknown. This reconciles the different measurement windows as a plausible cause, but it does not prove they account for all +20,710 UFS IRQs. Keep the next bracketed trace as the discriminator. The zero-event middle in the boot-clock trace remains a one-run observation for the trace's recorded window, not a general rate claim.

The old trace selected UFS IRQ 169 only; it never enabled IRQ 14 (`apps_rsc`), so the +13,992/+14,225 apps-RSC deltas cannot be compared to handler events in those traces. In Linux v7.2.3 the generic IRQ action tracepoints bracket registered actions, while the IRQ count can also be incremented by `handle_bad_irq()` without such an action. If the new boundary-aligned UFS count still exceeds its trace entries, investigate that path or a version/config-specific IRQ flow; current archives do not establish it. Sources: [v7.2.3 action entry/exit tracepoints](https://github.com/gregkh/linux/blob/v7.2.3/kernel/irq/handle.c#L1088-L1130), [IRQ count before action dispatch](https://github.com/gregkh/linux/blob/v7.2.3/kernel/irq/chip.c#L3328-L3372), and [bad-IRQ accounting](https://github.com/gregkh/linux/blob/v7.2.3/kernel/irq/handle.c#L825-L845).

### 2026-09-18 05:10 UTC — first SSH check after repeated Wi-Fi-off RTC wake timed out

The Wi-Fi-off repeat `20260918T043959Z-8e885685e77c` reached its nominal 05:10 UTC RTC wake, but the first host SSH status check at 05:10 UTC timed out connecting to port 22. This is not enough to classify the RTC wake or suspend as failed; the previous Wi-Fi-off run also needed time for radio/SSH recovery. Wait briefly and retry status before attempting retrieval.

### 2026-09-18 05:12 UTC — Wi-Fi-off repeat completed but did not reproduce the low-drain first sample

The repeat `20260918T043959Z-8e885685e77c` is complete: `s2idle` returned through `rtc0`, the boot ID is unchanged, and boot-minus-monotonic time shows 1799.168 s of suspend over a 1801.666 s battery interval. The gauge lost 129,868 uAh, about 259.50 mA average, and capacity moved by 2 percentage points, approximately 4%/h. This is materially higher than the first Wi-Fi-off/Bluetooth-on run (`20260918T040206Z-2913994f60b9`: 165.15 mA, about 2.52%/h) and is close to the earlier Wi-Fi-on/Bluetooth-blocked sample (~4.0%/h). Thus the apparent Wi-Fi-associated drain reduction is not replicated; treat that first result as noisy or state-dependent, not a confirmed radio fix. Retrieve and inspect the complete receipt and compare starting battery/radio/runtime state before deciding whether another matched run is worthwhile.

The full archive is now retrieved and its 4,433 file checksums all pass. Pre/post battery gauge values were 67% / 4,437,163 uAh / -665 mA and 65% / 4,307,295 uAh / -698 mA; both snapshots show Discharging, USB/wireless offline, and 25.0 C. Wi-Fi was enabled before the run and was disabled by the test; Bluetooth stayed powered and unblocked. AOSD, CXSD, and scalar DDR counters stayed at zero; APSS moved 52→55 and ADSP 159,334→159,944. The full pre/post interrupt deltas were CPU0-only: `ufshcd` +12,871, `apps_rsc` +10,401, and `mmc0` +52. Because this run had no tracing, these IRQ changes still cannot be assigned to the s2idle window. Evidence is in the run's `device/{pre,post}/power_supplies.json`, `qcom_stats.json`, `interrupts.json`, `meta/radio-before.json`, `cleanup/radios.json`, `derived/summary.json`, and `checksum-verification.json`.

### 2026-09-18 05:13 UTC — 60-second boundary-bracketed UFS trace started

Started `20260918T051332Z-1a9b21946c4b` on the Nova: explicit `s2idle`, 60-second RTC wake, unplugged, Wi-Fi disabled, Bluetooth preserved, and `ufs-irq` tracing. The updated research recorder records `ufshcd` and `apps_rsc` `/proc/interrupts` counters immediately before tracing starts, before tracing stops, and just after it stops. Nominal wake is 05:14:35 UTC. This run is intended to separate IRQ changes during the trace-active suspend window from the wider pre/post collection window; it is not a physical residency or battery-drain test.

Verified the deployed runner identity from this run's host manifest: its recorded SHA-256 (`2144c4d9…9814c31d`) exactly matches the current local runner containing the boundary snapshots. The next archived trace should therefore include the new counters, rather than only the old whole-run pre/post snapshots.

At nominal wake 05:14:35 UTC, the first SSH status check timed out. This is the usual Wi-Fi-off recovery delay pattern; keep waiting/retrying before classifying the 60-second RTC trace.

### 2026-09-18 05:17 UTC — bracketed trace resolves UFS counter mismatch for this 60-second run

Retrieved `20260918T051332Z-1a9b21946c4b`; it completed `s2idle` through `rtc0` on the same boot, with 58.910 s of proven suspend and all 4,525 archive checksums passing. The boundary snapshots show UFS IRQ 169 at 1,137,011 before tracing and 1,137,594 just before trace stop: +583 during the trace-active window. The trace records exactly 583 IRQ-169 handler entries, with zero per-CPU drops/overruns. It therefore reconciles the earlier apparent mismatch: full pre/post counters advanced +19,924, but +17,575 occurred before trace start and +1,766 after trace stop. Those old broad deltas were not comparable to trace counts.

The boot-clock trace spans 61.308 s; selected UFS IRQ/request events occurred in relative seconds 0, 60, and 61, with no UFS events in seconds 1–59. The proven s2idle section lasted 58.910 s, so this one unplugged/Wi-Fi-off/Bluetooth-on sample recorded UFS activity only at the edges, not through the sleep interval. This is stronger evidence than the old traces, but remains a single 60-second sample and covers only UFS. `apps_rsc` advanced +672 during the trace-active window, but that IRQ was not selected in the trace; its timing within the interval remains unknown. Next low-cost discriminator is a matching short trace that includes IRQ 14 as well as UFS.

### 2026-09-18 05:18 UTC — repeat short trace now filters both UFS and apps-RSC IRQs

Updated the `ufs-irq` profile to resolve both `ufshcd` and `apps_rsc` by name from `/proc/interrupts`, then filter `irq_handler_entry/exit` to both live IRQ numbers. This is a small lab-recorder change only; host `self-test`, Python AST parsing, and `git diff --check` pass. Started `20260918T051831Z-94e04a2713ea`: 60-second `s2idle`, unplugged, Wi-Fi disabled, Bluetooth preserved. Its host manifest runner SHA-256 matches the updated local file, so the dual-IRQ filter and boundary counters are deployed. Nominal RTC wake is 05:19:36 UTC. The result should show whether the +672 apps-RSC events from the prior trace-active window occur during the core suspended interval or only near its boundaries.

At the 05:19:36 UTC nominal wake, the first SSH status check timed out. As with the prior radio-off captures, wait and retry; this is not yet a suspend or RTC failure.

### 2026-09-18 05:22 UTC — apps-RSC and UFS IRQ deltas match trace entries and cluster at both edges

Retrieved `20260918T051831Z-94e04a2713ea`; it completed through the expected `rtc0` wake on the same boot, with 58.746 s of proven suspend and all 4,525 checksums passing. The dual-filter boot-clock trace recorded 605 UFS entries and 628 apps-RSC entries, exactly matching their respective IRQ-counter deltas while tracing was enabled. Per-CPU trace stats report zero drops/overruns. Event bins show UFS entries only in relative seconds 0 and 60, and apps-RSC only in seconds 0, 59, and 60; there is no selected IRQ activity through seconds 1–58. These two handlers were quiet through most of this sampled sleep, with the RSC tail clustered near the wake edge. The trace lacks an explicit `machine_suspend` transition marker, so the few second-59 events cannot yet be assigned to the final suspended instant versus wake/resume; do not call this exact-boundary proof.

The full pre/post counters still look large (`ufshcd` +19,983, `apps_rsc` +11,741), but the boundary brackets show the active trace window accounts for only +605/+628 respectively; most of the difference is outside the trace interval. Evidence is in `device/meta/trace.json`, `device/raw/trace/trace.txt`, per-CPU stats, before/after interrupt snapshots, and `derived/summary.json` under this run archive. Next improvement, if exact edge timing is needed, is to include the kernel `power:suspend_resume` marker in the short trace; no long run or policy change is required.

### 2026-09-18 05:25 UTC — suspend transition marker trace started

Started `20260918T052356Z-78162af5ddc0`, a 60-second unplugged `s2idle` trace with Wi-Fi disabled and Bluetooth preserved. It extends the validated dual `ufshcd`/`apps_rsc` handler trace with `power:suspend_resume` to place the edge-clustered IRQs against suspend entry/exit. The deployed host-manifest SHA-256 `dd40bb63a9fc25dd513a882b55fd1985f07d16c286263611f403af0c68799c52` matches the local runner. Nominal RTC wake was 05:24:58 UTC. This is a short timing diagnostic, not a battery-drain/residency test; no kernel, firmware, or device policy was changed.

Retrieved the run with unchanged boot ID; observed `s2idle`, RTC wake, and 58.836 s separation between `timekeeping_freeze` begin/end (machine-suspend markers span 58.839 s). The trace filters captured 851 UFS and 647 apps-RSC IRQ handler entries total with zero per-CPU drops/overruns; only one apps-RSC handler occurred after `machine_suspend` begin and before `timekeeping_freeze` begin, and none occurred between `timekeeping_freeze` begin at 59261.402261 and end at 59320.238395. UFS recorded no handler between `machine_suspend` begin and end. The remaining IRQs are clustered before entry and immediately after resume. Thus this sample directly shows those two IRQ sources are quiet during the traced 58.836-second frozen-time interval; it does not show deeper AOSD/CXSD or DDR self-refresh residency. All 4,530 archive checksums pass. Evidence: `device/raw/trace/trace.txt`, `device/meta/trace.json`, per-CPU stats, and `checksum-verification.json` in the run archive.

### 2026-09-18 11:56 UTC — next short trace should include the architected timer IRQ

Reviewed the latest 30-minute Wi-Fi-off receipt `20260918T043959Z-8e885685e77c`: IRQ 11 (`arch_timer`) advanced by 19,747 entries (about 11/s), spread across all eight CPUs; IRQ 33 (`arch_mem_timer`) advanced by 116. The exact-boundary 60-second trace only filtered IRQs for `ufshcd` and `apps_rsc`, so it ruled out sustained activity from those two in the frozen-time interval but did not account for this timer count. Next low-cost drain-side discriminator is to add IRQ 11 by its live name to the existing boundary trace and check whether it fires between `timekeeping_freeze` markers. This is a wake/activity proxy, not a direct power-state measurement.

At 11:56 UTC, a read-only SSH check of the Nova returned `Host is down`; a second check at 12:00 UTC timed out. No additional suspend run was started and no device state was changed. Recheck reachability before the next short trace. Exact AOSD/CXSD/DDR residency remains a separate gap: it needs a validated firmware/always-on residency counter or firmware state report, since Linux PSCI/genpd request results and the current zero-valued scalar stats do not prove the physical state.

Updated the local observation harness to include the dynamically resolved `arch_timer` IRQ in the existing short boundary trace and counter snapshots, alongside UFS and apps-RSC. Host-only self-test, Python AST parsing, and `git diff --check` pass. The recorder has not been redeployed because SSH is unavailable.

Reviewed the public SM8550 handheld AOP-monitor notes as a possible residency/blocker route. They report an accepted `{class:lpm_mon,type:cxpc,dur:2000,flush:1,log_once:1}` request on inspected Thor/RP6 firmware, but explicitly say the monitor sink address and row layout are firmware-specific; the returned CXPC drivers are blockers/votes, not physical residency counters. The public QMP notes also warn that an acknowledgement only confirms request handling and that the result is written to a separate message-RAM sink. Nova's validated QMP resource remains 0x400 bytes and does not establish the public decoder's expected sink. No QMP request was sent. Next step for this route is to validate Nova's exact AOP image/DT sink mapping and decoder layout, or use an existing Armada-exposed read-only endpoint if one exists; do not widen the mapping or issue a raw request based on the other handheld's example. Sources: https://github.com/jaewun/qcom-aop-debug/blob/main/docs/sm8550-handhelds.md and https://github.com/jaewun/qcom-aop-debug/blob/main/docs/qmp.md.

### 2026-09-18 12:55 UTC — plugged-in live snapshot confirms the residency telemetry gap and defines two separate tests

The Nova is reachable and remains plugged in. Its current boot ID is `c50e87eb-d469-41eb-a899-bb774b9472b7`; `/sys/power/mem_sleep` selects `s2idle` (with `deep` listed), and `/sys/power/state` offers `freeze mem disk`. Read-only live `qcom_stats` currently reports zero count/duration for AOSD, CXSD, and scalar DDR; APSS reports Count 3 and accumulated duration 15,605,731,269 ticks. `ddr_stats` reports DDR `0xd0` and frequency-bucket durations, but upstream Linux's reader sends its built-in `{class: ddr, action: freqsync}` QMP request to refresh them. In prior receipts, the `0xd0` duration equals the sum of the frequency buckets within 80–246 ticks, so it cannot independently prove a deep DDR state. No arbitrary AOP/QMP request was sent.

Validated live topology still has no declared `sys-pm-vx` node or `0xc320000` region: Nova's FDT/IOMEM shows QMP at `0x0c300000/0x400` and RPMh stats at `0x0c3f0000/0x400`; the documented CXPC monitor sink at `0x0c320000/0x400` is a separate, presently unclaimed range. The matching AOP firmware hash makes the public request a lead, not permission to map or decode an unowned buffer. Therefore Linux currently offers no validated read-only path to the AOP blocker log, and the counters available on-device still do not reveal the physical AOSD/CXSD/DDR state.

Keep the two questions experimentally separate. To answer *what state is reached*, first find an authoritative Nova DT/firmware resource declaration and sink layout for CXPC, then expose/read it through a bounded, read-only path; treat any blocker/vote rows as reasons a collapse was rejected, not proof of the state actually entered. For decisive residency, require documented AOP/PMIC domain residency counters or a validated firmware state trace; absent those, report the exact state as unknown. To answer *what causes 4–5%/h drain*, use repeatable battery `charge_counter` deltas over matched unplugged suspend intervals, with temperature/start SOC and actual radio state captured, then change one variable per run. The Nova is plugged in now, so a charge-counter delta would be net charging and cannot quantify system drain. Existing receipts are noisy: two Wi-Fi-off/Bluetooth-on 30-minute runs measured about 165 and 260 mA, so the first low-drain sample did not reproduce; a 60-second exact-boundary trace found UFS and apps-RSC quiet in the frozen-time interval, while the architected timer remains an untested lead. Next drain test should wait until an unplugged window is available; first isolate timer/wakeup activity with the existing short `[boot]` trace, then use a matched 30-minute battery-counter run only if the short trace or repeat baseline gives a concrete hypothesis.

No device policy, source/kernel image, or power-control setting was changed. The plugged-in snapshot is a baseline only; it does not answer physical residency or unplugged drain.

### 2026-09-18 13:00 UTC — Qualcomm Waipio source makes a guarded module probe plausible

Refreshed the live Nova using read-only root commands. It is still on boot `c50e87eb-d469-41eb-a899-bb774b9472b7`, charging at 81%, with `[s2idle] deep`. AOSD, CXSD, and scalar DDR remain all-zero. The current DDR `0xd0` duration is 29,046,827,572 ticks; the ten DDR frequency-bucket durations sum to 29,046,827,520, a difference of 52 ticks. This reinforces that `0xd0` is an aggregate of the frequency buckets in this table, not an independent named residency counter.

New primary-source finding: Qualcomm's Waipio (SM8550-family) SoC DTS explicitly declares `sys-pm-vx@c320000` as compatible with `qcom,sys-pm-violators` / `qcom,sys-pm-waipio`, with a separate `reg = <0xc320000 0x0400>` resource and AOP mailbox. This is stronger than the earlier Kalama-family reference and documents the physical region/size on the matching SoC family. Nova's *active* FDT and `/proc/iomem` still omit that resource, so the source reference does not mean Linux has claimed it on this boot. However, together with the live no-overlap inventory, it supports investigating a temporary driver that must successfully reserve exactly `0xc320000..0xc3203ff` before mapping, and refuses to proceed on any conflict. Do not expand the existing QMP range or map a larger window.

The same live kernel reports `CONFIG_MODULES=y`, `CONFIG_MODULE_UNLOAD=y`, `CONFIG_QCOM_AOSS_QMP=y`, and `CONFIG_KPROBES=y`; `/proc/config.gz` explicitly says `CONFIG_MODVERSIONS` and `CONFIG_MODULE_SIG` are not set, and `SECURITY_LOCKDOWN_LSM` is not set. `/lib/modules/7.2.3` has no `build` or `source` link, so a module cannot be compiled on-device from installed headers. This makes a *module-only* host build from the exact Armada-patched 7.2.3 source/config a credible next route without rebuilding Image/DTBs, subject to matching vermagic/compiler/build metadata and confirming exported `qmp_get`/`qmp_send` availability. No module was built or loaded, and no memory mapping or QMP request was attempted.

The published CXPC request matches the installed AOP ELF hash and has been observed on that firmware image in other SM8550 handhelds, but remains a field-validated diagnostic rather than an official protocol specification. Before a Nova test, review the reference reader's exact 1-KiB bounds and synchronization, then implement the smallest one-shot awake capture with a reserve-resource failure gate, one known CXPC request, raw-buffer preservation, and automatic module unload. The captured CXPC rows can identify AOP votes/blockers; they still must not be presented as direct proof of AOSD/CXSD/DDR physical residency. Sources: [Qualcomm Waipio DTS](https://android.googlesource.com/kernel/msm-extra/devicetree/+/refs/heads/android-msm-eos-android13-wear-kr3-pixel-watch/qcom/waipio.dtsi#L2273-L2277), [SM8550 monitor notes](https://github.com/jaewun/qcom-aop-debug/blob/main/docs/sm8550-handhelds.md), and [CXPC blocker limitations](https://github.com/jaewun/qcom-aop-debug/blob/main/docs/suspend-wake-debugging.md#L223-L233). No device policy or persistent system setting changed.

### 2026-09-18 13:13 UTC — Nova is reachable and charging for low-risk residency tests

Read-only refresh over SSH confirms the existing boot `c50e87eb-d469-41eb-a899-bb774b9472b7`, selected `[s2idle]` with `deep` available, and plugged-in Charging status at 88% (charge counter 5,720,496 uAh; current 1,000,146 uA; battery temperature 31.0 C). Tracefs and debugfs are mounted. AOSD, CXSD, and scalar DDR counters are still all zero; APSS has accumulated 42,989,076,755 ticks. This makes short sleep/IRQ observation feasible without changing radio state, but the charge counter is rising while plugged in and cannot quantify system drain. `sudo -n` is not currently enabled, so the harness may need its documented noninteractive credential setup resolved before deployment; no suspend run or device setting change was made.

### 2026-09-18 13:20 UTC — Nova source lacks a sink declaration but does not rule the monitor out

A targeted search of the Armada kernel device trees, patch stack, and current upstream Nova DTS submission found no Nova-specific `sys-pm-vx`, `0xc320000`, or CXPC sink declaration. The submitted upstream Nova series explicitly omits hardware definitions not yet supported in mainline, so this absence is not evidence the SM8550-family monitor hardware is absent. Qualcomm's Waipio DTS and downstream driver remain family-level support for the exact `0xc320000/0x400` resource and 24-byte-row format; a bounded read could expose CXPC blocker votes, but not prove physical AOSD/CXSD/DDR residency. Since the live Nova FDT still does not claim the range, keep this as a later fail-closed module experiment, not a direct MMIO read.

The lower-risk immediate test needs no build or AOP request: run one 60-second `s2idle` with radios preserved and the current `ufs-irq` trace profile. The checked-out recorder filters `arch_timer`, `ufshcd`, and `apps_rsc`, brackets IRQ counters to trace start/stop, and includes suspend markers. It can establish whether the timer handler occurs inside the measured frozen interval on this boot; it cannot measure drain while charging or establish physical domain residency.

### 2026-09-18 13:18 UTC — short plugged-in trace sees timer IRQ bursts, not a sustained timer storm

Run `20260918T131706Z-c7c3d5a727bc` completed successfully on the same boot. It used Armada's real `s2idle` dispatcher, remained plugged in with Wi-Fi/Bluetooth preserved, woke from the PMIC RTC, and recorded 59.753 seconds of suspend. The `[boot]` trace bracketed `machine_suspend` and `timekeeping_freeze`; all eight per-CPU trace buffers report zero overruns and zero dropped events, and the archive's 4,536 checksums pass.

Within the outer `timekeeping_freeze` interval, the selected IRQ trace records 76 `arch_timer` handler entries: 25 in relative second 0, 25 in second 1, and 26 around second 19; none appear in seconds 2–18 or 20–59. No UFS or apps-RSC handler appears after the freeze marker begins; one apps-RSC IRQ falls just before that marker, during suspend entry. This single powered/charging sample weakens the idea of a continuous `arch_timer` storm as the explanation for multi-percent-per-hour loss. The early/bunched timer entries merit one same-condition short repeat before we rule out transient/state-dependent activity; handler counts alone do not reveal energy cost.

AOSD/CXSD/scalar DDR deltas remained zero, so this still does not identify physical SoC/DDR residency. The battery charge counter increased 86,967 uAh over the 62.018-second whole measurement interval while charging; its derived negative draw is net charge gain, not a drain measurement. This run cannot explain the unplugged 4–5%/h result. Raw trace, trace configuration/stats, and pre/post evidence are in `../sm8550-suspend-lab-runs/20260918T131706Z-c7c3d5a727bc/`; the device has returned to the same boot and trace/RTC/radio cleanup completed.

### 2026-09-18 13:27 UTC — arch_timer burst does not reproduce at the same point in a second short trace

Run `20260918T132539Z-dd80cf6119c5` repeated the plugged-in/radios-preserved 60-second `s2idle` trace on the same boot. It completed 59.539 seconds of measured suspend and woke from the RTC. Within `timekeeping_freeze`, 28 `arch_timer` IRQ handlers occurred together in relative second 6, with none in the other seconds; the first sample had 76 entries clustered in seconds 0, 1, and 19. Neither sample recorded UFS or apps-RSC IRQ handlers after `timekeeping_freeze` began. Thus short timer activity is sparse and its location varies between samples; it is not a stable periodic wake pattern. Both traces are zero-drop and leave AOSD, CXSD, and scalar DDR deltas at zero. The second run's plugged-in charge counter was unchanged, consistent with charge management near full, and is not being used to assess drain.

For the current objective, stop battery-rate experiments. Next prioritize a Nova-validated AOP/PMIC residency source: find the exact firmware/DT mapping and decoder, or identify an existing firmware counter/trace that reports accepted physical domains. Preserve the distinction between PSCI state requests/return codes and actual hardware residency.

### 2026-09-18 13:31 UTC — sleep diagnostic no longer treats zero counters as proof

Corrected `system_files/usr/bin/armada-sleep-debug`: its previous report text claimed that zero AOSD/CXSD/DDR deltas proved the SoC rails never powered down. That inference was unsupported because these are firmware-provided records and their mapping to physical Nova residency is not validated. The report now says only that the counters did not advance and that zero alone does not establish residency; the adjacent comment likewise avoids assigning generic physical meanings to firmware labels. `bash -n` and `git diff --check` both pass. This is a local diagnostic wording correction only; it has not been deployed to the device.

### 2026-09-18 13:33 UTC — Nova AOP image contains low-power monitor code strings

Read-only inspection of the live device shows both `/dev/disk/by-partlabel/aop_a` and `aop_b` are 512 KiB and have identical SHA-256 `6aceb38f5ef10663ac5c29ffc4e9ee27b6339e8746ff3490485f8cf2640ef687`. The ELF strings include `lpm_mon`, `/sleep/aoss`, `cx_collapse_fsm`, `COLLAPSED`, `AOP DDR Log`, and DDR vote/log labels. This confirms the image contains relevant low-power firmware components, but the strings do not establish the CXPC sink address/layout, counter semantics, or per-suspend accepted residency. The active device tree still exposes QMP at `0xc300000/0x400`, separate stats SRAM at `0xc3f0000/0x400`, and no `0xc320000` node/range. No firmware request, MMIO read, or device setting change was made.

### 2026-09-18 13:34 UTC — detailed DDR telemetry is distinct from the zero scalar record

Independent source review of stable Linux v7.2.3 `drivers/soc/qcom/qcom_stats.c` confirms two distinct DDR interfaces: scalar `ddr` is one of the three records read from the 0x48 stats block, while debugfs `ddr_stats` reads the detailed firmware LPM/frequency table at offset 0xb8. On SM8450 and newer, reading `ddr_stats` first sends `{class: ddr, action: freqsync}` so AOP populates that table. The source labels LPM entries only with opaque IDs `0xd4`, `0xd3`, `0x11`, and `0xd0`; it does not map `0xd0` to self-refresh, powerdown, or deepest DDR state. This explains why a zero scalar `ddr` record can coexist with an advancing `ddr_stats` 0xd0 duration and means our existing detailed-table deltas are the useful DDR signal. Next verify the harness captures that distinct table at matched boundaries, and obtain firmware documentation before assigning physical meaning. References: [stable v7.2.3 qcom_stats.c](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/drivers/soc/qcom/qcom_stats.c?h=v7.2.3#n148), [qcom-stats binding ownership](https://gbmc.googlesource.com/linux/+/9593bdfa1d146beb8773dc900e62608afcaa47a3/Documentation/devicetree/bindings/soc/qcom/qcom-stats.yaml#L16), [SM8550 stats/QMP DT](https://android.googlesource.com/kernel/common/+/refs/tags/android16-6.12-2025-09_r1/arch/arm64/boot/dts/qcom/sm8550.dtsi#L3589).

Inspection of the two latest raw `qcom_stats.json` pairs confirms the Python harness captures the complete `ddr_stats` table at its broad pre- and post-suspend phases. In the 59.753-second trace, ID `0xd0` duration increased from 47,961,740,309 to 49,271,878,378 ticks (+1,310,138,069); in the 59.539-second repeat it increased from 57,796,924,027 to 59,101,673,204 (+1,304,749,177). IDs `0xd4`, `0xd3`, and `0x11` stayed at zero in both pairs. The scalar `ddr` count/duration stayed zero. These observations show the detailed table is not globally inert, but the existing pre/post snapshots are not aligned to actual suspend entry/return and do not establish its physical DRAM state or calibrated time unit. No additional device-side interface is needed to preserve the raw table.

### 2026-09-18 13:36 UTC — `0xd0` is not independent evidence of DDR low-power residency

Recomputed the latest two `ddr_stats` snapshots row by row. In `20260918T131706Z-c7c3d5a727bc`, the `0xd0` duration delta is 1,310,138,069 ticks and the sum of all DDR frequency-bucket deltas is 1,310,137,856 (difference 213 ticks). In `20260918T132539Z-dd80cf6119c5`, the corresponding values are 1,304,749,177 and 1,304,749,056 (difference 121 ticks). This near equality means the advancing `0xd0` row is not an independent indication of self-refresh/collapse; it appears to track the aggregate frequency-duration accounting, but its firmware-defined meaning is still unproven. The other three LPM IDs remain zero. Preserve this as opaque accounting and do not use it to claim DDR residency.

The harness audit refined the timing caveat: Python `capture_qcom_stats()` does preserve raw `ddr_stats`, but phase-level pre collection happens before radio handling, RTC setup, trace setup, and the final suspend call; phase-level post collection happens after the broad resume inventory. Each `ddr_stats` read sends the driver's supported `freqsync` request, but the harness does not timestamp the actual file read. Therefore current whole-run pre/post deltas include awake setup/resume intervals and cannot be attributed solely to the 60-second sleep. The shell `armada-sleep-debug` snapshots only scalar `Count`/`Accumulated Duration` entries and skips `ddr_stats` entirely. Next improve only the research harness: take a separately labeled detailed-table snapshot immediately before the suspend command and immediately after it returns, timestamp the actual read, parse per-ID/per-frequency deltas into the summary, and retain the raw text. This will tighten the interval while still treating IDs and tick units as undocumented.

### 2026-09-18 13:36 UTC — both Nova DTBO slots lack a Nova CXPC mapping

Read-only extraction and parsing of `/dev/disk/by-partlabel/dtbo_a` and `dtbo_b` found identical 25,165,824-byte partitions (SHA-256 `1bd16dd02a532121fa1b1b3f5d3aa23c7916e880b40ae43678574c381fd3b1a5`). Each Android DTBO table has 56 entries, whose metadata/FDT contents identify generic Qualcomm Crow/Kalama reference boards. Neither slot contains Nova/Retroid markers, `sys-pm-vx`, `qcom,sys-pm-waipio`, `qcom,sys-pm-violators`, `cxpc`, or a `0x0c320000/0x400` resource. Thus the live overlay slots do not provide the missing Nova-specific monitor mapping; the active FDT and `/proc/iomem` checks agree. Qualcomm Waipio DTS remains only SM8550-family precedent, not Nova layout authority. No DTBO was flashed or changed.

### 2026-09-18 13:47 UTC — exact-boundary snapshot works; DDR table still does not identify a low-power state

Run `20260918T134559Z-33c151e23f49` validated the new userspace capture on the plugged-in Nova: requested and observed `s2idle`, 59.632 seconds of suspend, RTC wake, unchanged boot ID, and successful cleanup. The new `meta/qcom-sleep-before-suspend.json` and `after-resume.json` contain raw AOSD/CXSD/scalar-DDR/`ddr_stats` reads with BOOTTIME, MONOTONIC, and realtime timestamps around each read. The `ddr_stats` read window spans 62.059371 seconds, including the suspend and setup/resume/read overhead.

Within that boundary window, `0xd0` advanced by 1,191,534,426 ticks while the summed DDR frequency-bucket rows advanced by 1,191,534,592 ticks, a difference of -166. The observed ratio is about 19.2 million ticks per second over the read window. LPM IDs `0xd4`, `0xd3`, and `0x11` stayed at zero; scalar AOSD/CXSD/DDR also remained unchanged. The live measurement reinforces that `0xd0` tracks aggregate frequency-duration accounting; it is not an independent acceptance counter for DDR low-power residency. The harness now retains exact boundary data and summarizes rows without naming their physical state. No battery-rate comparison, arbitrary QMP message, module load, or persistent device change occurred.

### 2026-09-18 13:50 UTC — awake-only control falsifies `0xd0` as a sleep-residency signal

Read `/sys/kernel/debug/qcom_stats/ddr_stats`, waited 30 seconds while the device remained awake, then read it again. BOOTTIME elapsed 30.001599 seconds. During this awake-only interval, `0xd0` advanced 576,149,563 ticks; the sum of all DDR frequency-bucket deltas was 576,149,504 ticks (difference 59). The ratio is approximately 19.204 million ticks/s, consistent with the 19.2 MHz counter inferred from the suspend run. This controlled comparison confirms `0xd0` is continuously tracking aggregate DDR frequency/time accounting while awake; its growth during suspend cannot indicate that a low-power DDR state was entered. The LPM IDs `0xd4`, `0xd3`, and `0x11` still did not advance. The device was not suspended for this control, radios and power policy were untouched, and no battery-rate comparison was made.

### 2026-09-18 13:51 UTC — live debugfs exposes counters but no read-only AOP state query

Read-only inventory of `/sys/kernel/debug` found the expected `qcom_stats` directory with scalar AOSD/CXSD/DDR and detailed `ddr_stats`. `/sys/kernel/debug/qcom_aoss` contains only four write-only controls (`ddr_frequency_mhz`, `prevent_aoss_sleep`, `prevent_cx_collapse`, `prevent_ddr_collapse`); it has no query/counter node, so none was touched. `/sys/kernel/debug/qcom_sleep_stats` is absent. No `sys_pm_violators`, `sys-pm-vx`, CXPC dump, or AOP residency reader is exposed in the current image. This confirms that the running kernel does not provide a safe read-only AOP acknowledgement interface through debugfs.

### 2026-09-18 14:00 UTC — clarify the authority and limits of Qualcomm sleep counters

- Qualcomm's qcom-stats binding and driver source settle one ambiguity: `/sys/kernel/debug/qcom_stats/{aosd,cxsd,ddr}` reads records maintained by AOP/RPM firmware. The binding describes these as SoC low-power statistics for modes involving backbone-rail and oscillator shutdown, with entry count and accumulated duration; Linux maps the shared records and prints them rather than incrementing them. Therefore zero deltas mean **the firmware stats block recorded no entry for those named modes in the capture window**. This is meaningful negative firmware evidence, stronger than “the Linux counter did not move,” but still not a direct voltage or rail-state measurement. Public sources do not expand the acronyms or define Nova's exact electrical thresholds/topology. Sources: [Qualcomm qcom-stats binding](https://gbmc.googlesource.com/linux/+/9593bdfa1d146beb8773dc900e62608afcaa47a3/Documentation/devicetree/bindings/soc/qcom/qcom-stats.yaml#L16-L21), [Linux qcom_stats record reader](https://code.googlesource.com/linux/torvalds/linux/+/75f2c0b3690702c90863c2e138cb5520670845ea/drivers/soc/qcom/qcom_stats.c#L133-L149), [SM8550 stats SRAM mapping](https://android.googlesource.com/kernel/common/+/refs/tags/android16-6.12-2025-09_r1/arch/arm64/boot/dts/qcom/sm8550.dtsi#L3589-L3592).
- The same sources distinguish detailed `ddr_stats` from scalar `ddr`: on SM8450+, Linux sends the documented `freqsync` QMP request each time the table is read; the firmware labels LPM records only with raw numeric IDs. The live awake-only control showed `0xd0` tracks frequency-bin duration while fully awake, so `0xd0` is excluded as a standalone sleep-residency signal. Do not map it to self-refresh or collapse. Source: [Linux qcom_stats DDR table/sync](https://code.googlesource.com/linux/torvalds/linux/+/75f2c0b3690702c90863c2e138cb5520670845ea/drivers/soc/qcom/qcom_stats.c#L152-L224).
- Read-only live check on the plugged-in Nova confirms `current_driver=psci_idle`, `[s2idle] deep`, state1 `cpu-sleep-0-0` (`silver-rail-power-collapse`) with its s2idle counters available, and only `power-domain-cluster` in the PSCI genpd summary. `power:psci_domain_idle_enter/exit`, `rpmh:rpmh_send_msg/tx_done`, and `qcom_aoss:aoss_send/done` tracepoints exist. The existing `psci-kretprobe` profile records `psci_cpu_suspend_enter` state and return value; old receipts show both immediate errors (`-95`, `-1`) and `0` returns. This can separate PSCI CPU/cluster request rejection from a call that remains until wake, but neither tracepoint nor return value is an AOSD/CXSD or physical-residency acknowledgement. The current exact-boundary harness already captures the direct AOP records around the suspend command. Next useful capture is one short `psci-kretprobe` run alongside those boundary records, then correlate nonzero-return versus `-EOPNOTSUPP` attempts with the firmware AOSD/CXSD/DDR records. No power settings or firmware interfaces were written during this inventory.

### 2026-09-18 14:06 UTC — PSCI call outcome correlated with exact firmware-counter window

Run `20260918T140124Z-89bba0b6e2f6` completed a 45-second `s2idle` cycle on the plugged-in Nova: requested and observed mode matched, measured suspend-clock separation was 43.900547 seconds, the RTC woke the same boot, and the run-scoped kretprobe/trace instance was removed during cleanup. This combined the new exact-boundary qcom_stats capture with the existing `psci-kretprobe` profile.

- The exact boundary snapshots show AOSD, CXSD, and scalar DDR each unchanged at count 0, last-entered 0, last-exited 0, accumulated duration 0. Under the Qualcomm binding, that means AOP/RPM recorded no transition into these named SoC low-power modes during this window. It is not a rail-voltage probe and does not name which blocker prevented the record.
- One CPU0 `psci_cpu_suspend_enter` call for state `0x4100c344` returned `retval=0`; the associated `power:psci_domain_idle_enter/exit` pair is present. This state maps to Qualcomm Kalama cluster E3 (`llcc-off`) in downstream DTS, not a system-level AOSD/CXSD state. This establishes a successful PSCI CPU/cluster call from Linux's perspective while the independent firmware SoC stats still recorded no AOSD/CXSD/DDR entries. It does **not** prove the physical cluster rail or SoC backbone rails reached their target voltage.
- The kretprobe and matching PSCI events share a single trace timestamp (`5157.741339`) even though the outer BOOTTIME/MONOTONIC bracket proves 43.900547 seconds of s2idle. Do not treat that timestamp equality as zero residence: ftrace's `boot` clock is designed to include suspend time but can be read before the timekeeper's boot offset is injected on resume. The syscall return value and firmware counters are the reliable parts of this receipt; tracing only tells us this cluster state was attempted and the PSCI call returned without an error.
- Detailed DDR `0xd0` advanced `888,211,288` ticks, while all frequency rows summed to `888,210,944` (difference 344); `0xd4`, `0xd3`, and `0x11` stayed zero. The prior awake-only control showed the same `0xd0`/frequency accounting relationship, so this remains excluded as low-power-entry evidence.

Raw evidence is in the run archive's `device/meta/qcom-sleep-{before-suspend,after-resume}.json`, `device/raw/trace/trace.txt`, `device/meta/trace.json`, and `device/derived/summary.json`. No sleep policy, radio, device binding, kernel, or firmware setting was changed. Sources for semantics: [Qualcomm qcom-stats binding](https://gbmc.googlesource.com/linux/+/9593bdfa1d146beb8773dc900e62608afcaa47a3/Documentation/devicetree/bindings/soc/qcom/qcom-stats.yaml#L16-L21), [PSCI idle trace definition](https://raw.githubusercontent.com/torvalds/linux/v7.2/include/trace/events/power.h#L61-L96), [Qualcomm Kalama cluster states](https://android.googlesource.com/kernel/msm-extra/devicetree/+/refs/heads/android-msm-eos-android13-wear-kr3-pixel-watch/qcom/kalama.dtsi#L283-L333), [ftrace boot-clock semantics](https://github.com/torvalds/linux/blob/v7.2/Documentation/trace/ftrace.rst).

### 2026-09-18 14:14 UTC — report schema v4 independently reports requested CPU state and firmware records

Run `20260918T141126Z-d8d75c760ea7` is the end-to-end validation of the revised report. It completed the requested 30-second s2idle cycle, observed 29.047697 seconds of suspended-clock separation, woke through the expected RTC path, and returned on the same boot. The report now has distinct lines for the AOP/RPM-maintained qcom_stats records and the Linux PSCI trace, avoiding the earlier ambiguity between a requested CPU/cluster state and firmware-recorded SoC residency.

At the exact qcom_stats boundaries, AOSD, CXSD, and scalar DDR count/duration remained zero and their last-entered/exited fields remained zero. In the trace, one CPU0 `psci_cpu_suspend_enter` for `0x4100c344` returned 0; there were also seven s2idle domain-idle event pairs for `0x40000004` across CPUs 1–7. This confirms the kernel exercised those CPU/domain idle paths and the cluster PSCI call returned successfully. It does not prove physical cluster/SoC rail state. The firmware stats separately say no AOSD/CXSD/scalar-DDR entry was recorded in this window.

The detailed DDR table's `0xd0` duration increased by 609,126,359 ticks, while its frequency buckets differed from that delta by only 41 ticks; other LPM rows stayed at zero. The awake-only control already showed the same accounting relationship, so this remains aggregate DDR/frequency accounting, not residency evidence. The generated report and retrieved archive checksum manifest both validate. No drain test or device policy change was part of this run.

### 2026-09-18 14:18 UTC — AOP disassembly and SSH transfer limitation narrow the next safe step

Read-only inspection of the exact Nova `aop_a` ELF found address literals `0x0c320000`, `0x0c360000`, `0x0c3f0000`, `0x0c400000`, `0x0c300000`, and `0x0c310000` in an unlabeled packed table. The firmware is stripped and has no symbol/section metadata; neither the table fields nor the apparent `lpm_mon` strings connect `0x0c320000` to a CXPC sink, buffer bounds, or row schema. DDR LPM IDs remain unmapped. This strengthens the lead that AOP firmware knows several related physical addresses but does not supply the Nova resource/layout authority needed to safely read them. Keep direct access and experimental QMP disabled pending that mapping.

A fresh harness preflight failed at its `scp` bootstrap even though batch-mode SSH remained live on the same boot. A one-file test showed OpenSSH's default SFTP-based `scp` closes, while legacy `scp -O` transfers successfully to this image. Added `-O` to the lab host bootstrap so the existing read-only preflight and bounded diagnostics can run again; this changes only file transfer protocol selection, not device state. Re-run preflight and validate checks before another suspend test.

### 2026-09-18 14:19 UTC — correct the bootstrap diagnosis; no SCP code change is needed

Follow-up isolated the preflight failure to the supplied SSH target: this host has alias `armada` (`armada@192.168.0.20`), not `retroid-nova`. SSH worked through the valid alias; both default `scp` and `scp -O` transfer successfully to `armada`. Reverted the unnecessary `-O` change. The prior 14:18 note's attribution to an SFTP incompatibility was incorrect; it is retained here as a correction. No test file or other device state is being left behind.

### 2026-09-18 14:22 UTC — current-image `deep` also records no AOSD/CXSD/scalar-DDR entry

Run `20260918T142021Z-883484904299` tested the deeper path on the live, plugged-in Nova using the current Armada `20260915.feca679` / kernel `7.2.3` image. The harness selected and observed `deep`, completed a 30-second RTC-woken suspend window (28.961247 seconds reported suspend-clock separation), returned on the same boot, and cleaned up its trace instance.

The exact before/after AOP/RPM boundaries again show AOSD, CXSD, and scalar DDR at count 0 with zero accumulated duration and no last-entry/exit timestamps. This is now reproduced in both s2idle and `deep` on the current image: the firmware stats block recorded no entry for those named modes in either capture. It still does not tell us the physical cause or all other low-power states the firmware may use.

The trace captured 1,388 RPMh sends (1,376 active, six wake-set, six sleep-set), 668 RPMh completion records, and zero AOSS QMP messages. Around suspend, Linux staged the same six-resource `apps_rsc` TCS 5 wake set and TCS 3 sleep set as in prior runs; the sleep writes were non-waiting (`complete=0`), so this trace proves programming/staging, not firmware execution or acceptance. The detailed DDR `0xd0` counter advanced 606,966,496 ticks and again nearly matched the frequency-bucket sum; the other numeric LPM rows stayed zero. No state ID is assigned to `0xd0`.

This closes the simpler mode-selection question: merely selecting `deep` instead of `s2idle` does not make these AOP/RPM counters advance. To explain the absent firmware records or physical residency, next decode the staged RPMh resource addresses and find an authoritative Nova AOP/PMIC transition counter; the public AOP binary and Nova DT still do not provide a safe CXPC sink schema.

### 2026-09-18 14:27 UTC — live RPMh addresses decode to BCM resources; PSCI system suspend is probeable

The current image's read-only `/sys/kernel/debug/cmd-db` dump maps the six addresses in the deep run's staged sleep/wake TCS to named BCM records: `0x50000=MC0`, `0x50004=SH0`, `0x50010=SN0`, `0x50038=CN0`, `0x50048=QUP1`, and `0x50044=QUP0`. This removes the raw-address ambiguity. The trace contains sleep-set commands for those six resources, but their encoded values are still RPMh/BCM payloads; they are not PMIC rail measurements and the asynchronous sleep TCS write is not evidence firmware triggered it. No individual item is yet identified as the blocker.

A fresh root preflight on the current image also read `/sys/kernel/debug/psci`: PSCI v1.1, OSI supported, and `SYSTEM_SUSPEND` supported. Both `psci_system_suspend_enter` and `psci_system_suspend` appear in `available_filter_functions` and are not listed in the kprobe blacklist. The current trace inventory lacks `rpmh:rpmh_rsc_snapshot` and `power:machine_suspend`. Therefore the most direct remaining no-build path test is a run-scoped return probe on `psci_system_suspend_enter` during `deep`; that can establish whether the PSCI SYSTEM_SUSPEND wrapper was reached and what Linux return code it got, while qcom_stats remains the independent firmware-record layer. The device returned awake on the same boot after the previous test; no arbitrary QMP or debugfs control was written.

### 2026-09-18 14:30 UTC — direct deep suspend reaches PSCI SYSTEM_SUSPEND and returns success

Run `20260918T142856Z-ed25240db22b` used the current plugged-in Nova image (`20260915.feca679`, kernel `7.2.3`), explicitly selected and observed `deep`, and completed a 29.059135-second suspend interval before the expected RTC wake. A run-scoped kretprobe on `psci_system_suspend_enter` captured exactly one return (`retval=0`) on CPU0 from the path `suspend_devices_and_enter -> psci_system_suspend_enter`. PSCI v1.1 and the debugfs feature inventory had independently reported `SYSTEM_SUSPEND` support. This proves Linux entered the PSCI platform system-suspend callback and it returned success after resume; it does not identify electrical rails or exact DDR residency.

During the same exact before/after boundary, firmware AOSD, CXSD, and scalar DDR remained count 0, accumulated duration 0, with no last-entry/exit timestamps. Detailed DDR `0xd0` advanced 611,293,330 ticks, within 146 ticks of the summed frequency buckets; its three other numeric LPM rows stayed zero. This is the strongest current separation of layers: `deep` was selected, the PSCI SYSTEM_SUSPEND path returned success, yet the AOP/RPM stats block recorded no entry into its named AOSD/CXSD/DDR modes. The next root cause cannot be fixed by merely adding the missing Linux system-genpd description; we need the Nova firmware's accepted-state or residency telemetry, or authoritative mapping of these stats.

The dynamic probe definition was recorded as run-owned, enabled only in its private trace instance, and cleanup reports it absent after removing the instance; the summary marks run success and kprobe cleanup success. The retrieved evidence archive is `../sm8550-suspend-lab-runs/20260918T142856Z-ed25240db22b/`. No arbitrary AOP request, power policy write, or drain analysis occurred.

### 2026-09-18 14:32 UTC — PSCI standard residency counters are not advertised by this firmware

The current read-only `/sys/kernel/debug/psci` output lists PSCI v1.1, OSI, `SYSTEM_SUSPEND`, `SET_SUSPEND_MODE`, and `SYSTEM_RESET2`, but does not list `STAT_RESIDENCY`, `STAT_COUNT`, or `NODE_HW_STATE`. Linux's PSCI debugfs implementation enumerates optional calls and prints only those the firmware reports as supported, so this image does not offer those standard PSCI state/counter queries through that interface. This closes another plausible no-build route to per-state residency. Evidence: `current-sleep-focus-system-psci/preflight-20260918T142613Z-e88a431e1e46.json`; implementation: [Linux v7.2 PSCI debugfs](https://github.com/torvalds/linux/blob/v7.2/drivers/firmware/psci/psci.c#L350-L430).

### 2026-09-18 14:37 UTC — ADSP qcom_stats advances in the deep-run archive, but does not validate AOSD/CXSD/DDR

The already archived `20260918T142856Z-ed25240db22b` run's broad `pre/audio.json` and `post/audio.json` snapshots show `/sys/kernel/debug/qcom_stats/adsp` count increasing from 20,164 to 20,363 (+199) and accumulated duration from 128,352,121,441 to 129,083,153,631 (+731,032,190 ticks). In the same run, the separately captured exact-boundary AOSD, CXSD, and scalar DDR records remained all-zero; detailed DDR `0xd0` continued to match the frequency-bucket total. This is a new ancillary observation, not evidence that the named AOSD/CXSD/DDR records are advancing or that the ADSP activity occurred during the suspended portion: the audio snapshots bracket the wider run and include awake setup/resume work. ADSP counters use a distinct record and cannot validate the other records' wiring, semantics, or physical residency. The raw values are preserved in the run archive's `device/pre/audio.json`, `device/post/audio.json`, and `device/meta/qcom-sleep-{before-suspend,after-resume}.json`. No new device action or drain measurement was performed. Next, inspect the exact live ADSP debugfs provider and its source/DT binding before deciding whether an aligned awake control would clarify anything; do not treat this as a residency result.

Source audit now confirms the provider distinction: in the v7.2.3 `qcom_stats.c`, subsystem `adsp` is fetched from SMEM item 606 / host 2 with `qcom_smem_get()`, while SoC sleep-mode records such as AOSD/CXSD/DDR are read separately from the platform's mapped stats SRAM. They share `/sys/kernel/debug/qcom_stats`, not a backing record or writer. Thus ADSP's +199 count does not validate the AOSD/CXSD/DDR SRAM path. A boundary-aligned ADSP sample would answer only whether the separate ADSP subsystem record changed over the suspend bracket; it still would not tell us whether a named SoC mode or DDR state physically entered. Source: [Linux v7.2.3 qcom_stats.c](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L1123-L1250) and [Qualcomm subsystem sleep stats](https://android.googlesource.com/kernel/msm.git/+/9671bc00773d7f73172f1cf38a7cd638091d0214/drivers/soc/qcom/subsystem_sleep_stats.c#L81-L144).

### 2026-09-18 14:42 UTC — public CXPC monitor still lacks Nova-bound and parser-safety proof

Offline comparison of the exact Nova AOP ELF with Qualcomm's SM8550-family Waipio DTS and OnePlus's public `sys_pm_vx.c` did not establish a safe Nova monitor read. Waipio declares `sys-pm-vx@c320000` with a 0x400 resource and AOP mailbox, separate from the 0x400 `soc-sleep-stats@c3f0000` block. OnePlus maps its DT resource, sends `{class:lpm_mon,type:cxpc,...}`, then reads a header plus timestamped per-driver vote rows and interprets asserted votes as blockers. But the reader trusts firmware `logsize` without bounding reads to the declared resource length; the exact Nova ELF only contains `lpm_mon`/`cxpc` strings and an unreferenced address literal, with no cross-reference proving that `0xc320000` is its sink. Nova's active FDT/IOMEM still does not claim the resource. So neither the family DTS nor that reader is sufficient authority to map/read Nova memory; even a correctly bounded blocker trace would explain possible collapse prevention, not prove a state was entered. Sources: [Qualcomm Waipio DTS](https://android.googlesource.com/kernel/msm-extra/devicetree/+/refs/heads/android-msm-eos-android13-wear-kr3-pixel-watch/qcom/waipio.dtsi#L2633-L2645), [OnePlus CXPC mailbox and parser](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/sys_pm_vx.c#L1677-L1796), and [vote interpretation](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/sys_pm_vx.c#L1812-L1923). No firmware request or memory read was attempted.

### 2026-09-18 14:47 UTC — exact-boundary ADSP counter shows subsystem sleep across an s2idle window

Run `20260918T144444Z-985f246d6f69` completed a 30-second s2idle capture on the same boot; selected and observed mode matched, 28.706584 seconds of suspend-clock separation were measured, RTC wake succeeded, and the harness restored its RTC alarm and temporary debug settings. ADSP SMEM count increased from 21,251 to 21,259 (+8) across the exact qcom_stats boundary; its accumulated sleep duration increased 600,897,673 counter ticks over a 31.305051-second boundary read window. `last_entered_at` was newer than `last_exited_at` at both boundaries, so firmware reported the ADSP subsystem asleep at both reads. The duration delta is about 19.195 million ticks per second, close to the whole read window. This supports that ADSP's own subsystem sleep accounting is live and records it asleep through almost all of this bracket. It says nothing about AOSD/CXSD/DDR acceptance or the APSS/SoC electrical state.

The exact AOSD, CXSD, and scalar DDR records remained count 0 / duration 0, with unchanged entry/exit fields; detailed DDR `0xd4`, `0xd3`, and `0x11` also stayed at zero while `0xd0` tracked the frequency-bin sum within 472 ticks. This validates the new separately labeled boundary ADSP output on-device and distinguishes subsystem sleep from the unchanged SoC-mode records. Because other subsystem SMEM files are also present, next low-cost capture should include all of them rather than only ADSP; this can map which subsystem counters record sleep, while preserving the limit that none proves whole-SoC or DDR physical residency. Evidence: `../sm8550-suspend-lab-runs/20260918T144444Z-985f246d6f69/device/meta/qcom-sleep-{before-suspend,after-resume}.json` and `device/derived/summary.json`.

### 2026-09-18 14:52 UTC — exact all-subsystem capture shows APSS sleep matching the s2idle interval

Run `20260918T145032Z-684bbecf7947` validated schema v5's dynamic capture of all 17 files under `/sys/kernel/debug/qcom_stats` on the same boot. It requested and observed s2idle, measured 29.290142 seconds of suspend-clock separation, woke by RTC, returned on the original boot, and restored its RTC alarm and temporary debug settings.

New strongest subsystem-level evidence: the SMEM `apss` record changed count 15→16 and accumulated duration +562,313,765 ticks. Dividing by the measured suspend interval gives about 19.198 million ticks/s; at the independently observed ~19.2 MHz counter scale, that represents ~29.287 seconds, essentially the measured 29.290-second s2idle window. Its last-entry and last-exit timestamps both advanced, showing one APSS-recorded sleep interval occurred in the capture. This indicates the APSS subsystem's own firmware sleep record spans almost the entire s2idle interval. It is materially stronger than the prior cluster PSCI return alone, but remains subsystem SMEM evidence: it does not prove AOSD/CXSD acceptance, DDR low-power mode, or the exact physical APSS/SoC rails.

ADSP changed by +7 entries and +612,277,985 duration ticks; CDSP kept count 8 but its duration advanced +612,436,413 with `last_entered_at > last_exited_at` at both samples. Both durations match nearly all of the 31.898484-second complete qcom-stats read window, so those subsystem records were also asleep for nearly the full observation. `adsp_island` was readable but unchanged; the remaining named SMEM files returned empty data on this image and are reported unavailable rather than as zero. Meanwhile AOSD, CXSD, and scalar DDR count/duration remained all zero; detailed DDR `0xd4`, `0xd3`, and `0x11` stayed zero, while `0xd0` again followed frequency-bin time. Thus we can now say *APSS, ADSP, and CDSP subsystem sleep was recorded during s2idle*, while the firmware's named AOSD/CXSD/scalar-DDR counters recorded no entry. The physical whole-SoC/DDR state remains unresolved. Raw boundary data and checksum receipt are in `../sm8550-suspend-lab-runs/20260918T145032Z-684bbecf7947/device/`.

### 2026-09-18 15:02 UTC — direct `deep` suspend returns successfully through PSCI, but named SoC counters stay opaque

Run `20260918T145721Z-47b15190af1a` requested `deep`, the kernel log recorded `deep`, and the requested/observed modes matched. BOOTTIME advanced 31.598017 seconds while MONOTONIC advanced 2.937757 seconds, giving 28.660260 seconds of suspend-clock separation; the RTC woke the device, its boot ID remained unchanged, and the run restored the original `[s2idle] deep` selection. A run-scoped kretprobe on `psci_system_suspend_enter` recorded one return with `retval=0`. Linux v7.2 implements this callback by calling PSCI `SYSTEM_SUSPEND` through `cpu_suspend()`, so this is evidence the direct deep system-suspend path returned successfully after the observed suspend interval, not just a userspace request that failed immediately. It still does not identify physical rails or the precise firmware low-power state. Source: [Linux v7.2 PSCI system-suspend path](https://github.com/torvalds/linux/blob/v7.2/drivers/firmware/psci/psci.c#L530-L545).

The APSS SMEM record advanced from count 16 to 17 and accumulated duration by 550,193,548 ticks across a 31.596064-second stats read window; at the observed ~19.2 MHz scale this is about 28.66 seconds, matching the measured suspend-clock separation. ADSP count advanced by 26 and duration by 606,274,911 ticks; CDSP count stayed at 8 while duration advanced 606,625,170 ticks. In contrast, AOSD, CXSD, and scalar DDR count/duration and entry/exit fields remained zero. Detailed DDR LPM IDs `0xd4`, `0xd3`, and `0x11` remained zero; `0xd0` tracked the sum of frequency-bin time (difference 307 ticks), so it remains excluded as a low-power residency signal.

The generic `power-domain-cluster/idle_states` row changed S1 Usage 64→65 and its `S2idle` column 112→113 during this direct-deep run. This is a Linux genpd accounting correlate; its `S2idle` label appears surprising for a deep run and is not evidence of SoC electrical residency. Keep the raw before/after rows and resolve that column's exact provider/callback semantics before using it to classify suspend mode. The key opaque boundary remains: Linux successfully returned from PSCI system suspend and APSS firmware recorded a matching sleep interval, while AOSD/CXSD/scalar-DDR firmware records logged no named-mode entry. Raw boundary and trace evidence are in `../sm8550-suspend-lab-runs/20260918T145721Z-47b15190af1a/device/`.

### 2026-09-18 15:04 UTC — genpd `S2idle` is callback-tagged accounting, not a sleep-mode detector

Stable Linux v7.2.3 source explains the direct-deep run's genpd `S2idle` delta. `genpd_sync_power_off()` increments Usage only after the genpd power-off callback succeeds; it also increments `usage_s2idle` whenever `system_power_down_ok` is present. The source comment says that callback is currently used only for s2idle, but the increment itself does not check the selected `mem_sleep` mode. The PSCI cpuidle-domain provider assigns that governor to CPU power domains. Thus the observed S1 Usage +1 / S2idle +1 during direct deep is consistent with Linux's successful synchronized power-off accounting; it is not evidence that the run selected s2idle or that physical collapse occurred. `Rejected` increments when `_genpd_power_off()` fails, so an unchanged value only says no such counted callback rejection was recorded. Sources: [genpd sync power-off accounting](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pmdomain/core.c#L1391-L1445), [debugfs column output](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pmdomain/core.c#L3944-L3975), [PSCI genpd governor assignment](https://github.com/gregkh/linux/blob/v7.2.3/drivers/cpuidle/cpuidle-psci-domain.c#L78-L81).

### 2026-09-18 15:10 UTC — exact-boundary genpd capture validated on s2idle

The updated runner's short s2idle run `20260918T150858Z-22033088fb46` requested and observed s2idle, measured 28.827661 seconds of suspend-clock separation, woke by RTC on the same boot, restored settings, and cleaned up the scoped trace. Its new timestamped boundary read of `/sys/kernel/debug/pm_genpd/power-domain-cluster/idle_states` shows state S1 Usage +1, Rejected +0, and S2idle +1; state S0 counters did not move. This confirms the new capture/parse path and ties the Linux genpd callback counters to the same suspend bracket as qcom_stats. Its state description is `N/A`, so the runtime table does not name the underlying power-domain state.

The trace recorded the s2idle PSCI state `0x4100c344` entering and exiting once on CPU2, with `retval=0`. The APSS SMEM count advanced +1 and duration +553,445,126 ticks; at the observed ~19.2 MHz scale this corresponds to about 28.825 seconds, matching the suspend-clock interval. AOSD, CXSD, scalar DDR, and detailed DDR LPM IDs `0xd4`, `0xd3`, and `0x11` again had zero deltas. ADSP and CDSP duration advanced across nearly the whole read window, while ADSP count advanced +7. The direct-deep run also had S1 Usage +1 / S2idle +1, confirming these genpd columns do not distinguish the selected mode. As before, firmware-recorded subsystem sleep and successful Linux/PSCI callbacks do not certify physical AOSD/CXSD/DDR residency.

This runner change only adds exact-boundary cluster genpd snapshots, their separate deltas, and an explicit evidence caveat in result output; it changes no kernel, image, firmware, device policy, or suspend selection. Targeted self-test, `py_compile`, shell syntax, and whitespace checks passed before deployment. Raw evidence and checksums are in `../sm8550-suspend-lab-runs/20260918T150858Z-22033088fb46/device/`.

### 2026-09-18 15:12 UTC — exact-boundary direct-deep run matches the s2idle genpd/APSS pattern

Run `20260918T151128Z-c37641215f54` requested and observed direct `deep`, recorded 28.886978 seconds of suspend-clock separation, woke by RTC on the same boot, and restored the original suspend selection and run-scoped tracing. Its exact-boundary cluster genpd counters again showed S1 Usage +1, Rejected +0, S2idle +1. The `psci_system_suspend_enter` kretprobe captured one `retval=0`; no `0x4100c344` cluster-state event is reported for this direct-deep path. In the preceding exact-boundary s2idle run, the same S1 genpd counters changed by the same amounts, while PSCI recorded one `0x4100c344` enter/exit pair with return 0. This confirms genpd callback counters alone cannot distinguish these two suspend paths.

APSS count advanced +1 with +554,568,879 duration ticks, approximately 28.884 seconds at the observed ~19.2 MHz scale, close to the 28.887-second suspend-clock interval. ADSP advanced +8 and CDSP duration advanced across most of the full read window. AOSD, CXSD, scalar DDR, and detailed DDR LPM IDs `0xd4`, `0xd3`, and `0x11` again showed no firmware-recorded entry; `0xd0` followed frequency-bin accounting. Thus both s2idle and direct deep now have matching evidence at the exact qcom/genpd boundaries: APSS subsystem sleep and a successful Linux suspend path, with no entries in the exposed named AOSD/CXSD/scalar-DDR or recognized detailed DDR-LPM counters. The physical state represented by the remaining undocumented firmware modes is still unknown. Evidence is in `../sm8550-suspend-lab-runs/20260918T151128Z-c37641215f54/device/` and the paired s2idle run `../sm8550-suspend-lab-runs/20260918T150858Z-22033088fb46/device/`.

### 2026-09-18 15:17 UTC — live Nova device tree resolves the s2idle PSCI ID to its exact domain node

Read-only SSH traversal of `/sys/firmware/devicetree/base/cpus/{idle-states,domain-idle-states}` decoded each `arm,psci-suspend-param` as big-endian cells. The trace-observed `0x4100c344` is the parameter on the live Nova node `cpus/domain-idle-states/cluster-sleep-1` (`compatible=domain-idle-state`); the sibling `cluster-sleep-0` is `0x41000044`. Neither domain node has an `idle-state-name` property, which explains why `power-domain-cluster/idle_states_desc` displays `N/A` for S1. Thus the PSCI trace can now be named precisely as a request for Nova's `cluster-sleep-1` domain state rather than an anonymous hex value. The DT provides no human firmware state label or physical rail/residency guarantee for that node.

The CPU-local parameter `0x40000004` maps to three live FDT nodes: `cpu-sleep-0-0` / `silver-rail-power-collapse`, `cpu-sleep-1-0` / `gold-rail-power-collapse`, and `cpu-sleep-2-0` / `goldplus-rail-power-collapse`. Those are CPU idle-state labels, distinct from the cluster domain state's missing name. This closes the state-ID-to-live-DT-node ambiguity and confirms the trace matches the exact running Nova tree, not only another SM8550 board's downstream DTS. It does not tell us whether AOP accepted the target electrical state; qcom_stats still records zero named AOSD/CXSD/DDR entries. No MMIO, AOP/QMP, power policy, or firmware operation was performed.

### 2026-09-18 15:22 UTC — schema 6 state-map receipt validated on the Nova

Run `20260918T152059Z-84e958e01abf` used the updated schema-6 runner, whose local SHA-256 matched the device's recorded runner SHA. It requested/observed s2idle, measured 28.961012 seconds of suspend-clock separation, woke by RTC on the same boot, and completed trace cleanup. The new report line maps the actual trace parameter `0x4100c344` to `domain/cluster-sleep-1 (name unspecified)` and `0x40000004` to the three named CPU idle-state nodes. The raw pre/post `psci-state-map.json` also preserves compatible strings and latency/residency values. This validated the end-to-end mapping capture and report, not just the earlier manual SSH read.

In the same run, trace recorded one `cluster-sleep-1` enter/exit pair and `psci_cpu_suspend_enter` returned 0. APSS SMEM count advanced +1 and duration +555,992,481 ticks, about 28.958 seconds at the ~19.2 MHz scale. Cluster genpd S1 Usage/S2idle both advanced +1 with no Rejected delta. AOSD, CXSD, scalar DDR, and detailed DDR LPM IDs `0xd4`, `0xd3`, and `0x11` again had zero deltas. This makes the Linux requested state and firmware-recorded APSS sleep legible in one receipt while leaving the physical AOP/CXSD/DDR state unresolved. No kernel/image/config change or drain analysis was performed. Evidence: `../sm8550-suspend-lab-runs/20260918T152059Z-84e958e01abf/device/`.

### 2026-09-18 15:44 UTC — new live checks rule out a missing PCIe suspend OPP; RPMh state policy remains a candidate

User clarified that the current goal is to resolve suspend-state observability and opaque sleep behavior, not measure battery drain. No drain test was run.

Fresh read-only inspection of the awake Nova found all enumerated `qcom-rpmh-regulator` devices report `suspend_mem_state=disabled`. The only `regulator-state-mem` node in the live FDT is the fixed fan regulator; the Nova's qcom RPMh rails have no suspend-memory constraints. Public Thorch/Pocknix patches add suspend-state handling to the RPMh regulator driver/core, and Pocknix's current shared AYN DTS adds BOB2-off and L15-LPM constraints. This is a possible policy/build delta to audit, not proof that absent constraints cause the zero named-mode counters; changing rail policy without validating the board requirements would be unsafe. The related regulator patches alone would not create constraints for the live Nova tree.

Correction to the earlier missing-PCIe-OPP lead: the live FDT already contains PCIe0 `opp-suspend` with `opp-hz=1` and a 1000 kB/s peak bandwidth floor, matching Armada patches 0513/0520. Therefore “Armada lacks a PCIe suspend OPP” is ruled out. Its presence does not prove Linux staged or firmware accepted the OPP during the captured interval; it only closes the missing-node hypothesis.

The same fresh root-only check confirms `qcom_aoss` prevent-sleep/collapse controls are write-only debugfs files (mode 0200; reads return `EINVAL`) and `/proc/iomem` has no Nova claim for the community-referenced `0x0c320000` CXPC monitor. Do not treat a family-level address or blocker log as proof of Nova layout or successful state entry. Existing paired short s2idle/deep receipts remain: Linux suspend paths return successfully, APSS SMEM records a sleep interval matching the suspended window, and exposed AOSD/CXSD/scalar-DDR plus recognized DDR-LPM counters do not advance. That bounds the opaque gap but does not identify a firmware-accepted physical state.

Next useful work is to finish authoritative RP6/Nova `sys_pm_vx` DT/resource lineage, determine whether a vendor-supported status/trace interface exists, and map which source-controlled RPMh/OPP requests actually reach the platform suspend path. Any new read-only conclusion will be journaled here before further tests. No QMP writes, MMIO reads, persistent power-policy change, kernel/image build, deployment, or drain measurement was performed.

### 2026-09-18 15:49 UTC — Android family source defines CXPC monitor format, but not Nova ownership; Linux has no sleep-vote acknowledgement

Public AYN/LineageOS Kalama-family DTS declares a separate `sys-pm-vx@c320000` resource at `0x0c320000/0x400`, wired to the AOP QMP mailbox, alongside (not inside) the `0x0c3f0000/0x400` sleep-stats resource. Its binding identifies `reg` as AOP message RAM. This is useful family-level resource/layout authority, but the actual common board DTS is supplied externally and no public RP6/Nova merged runtime tree proves this node is present for this device. The current Armada Nova FDT and its device resource inventory still omit it. The family address is therefore not authorization to map or read it on Nova.

The AYN `sys_pm_vx` driver confirms the buffer is a blocker trace, not a residency counter: it sends `{class:lpm_mon, type:cxpc, ...}` only when its debug interface is enabled, and prints driver vote rows; its all-zero row annotation means entry/exit of a low-power interval. The public parser trusts firmware `logsize` without bounding reads to the declared resource length, so copying that reader unchanged would also create an out-of-range read risk. Even a Nova-validated dump could identify votes blocking collapse but could not certify which state was physically entered. Sources: [AYN Kalama DTS](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalama.dtsi#L2344-L2370), [sys-pm-violators binding](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/bindings/arm/msm/sys-pm-violators.txt#L3-L39), [AYN driver](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/sys_pm_vx.c#L178-L201).

Source audit also closes the meaning of the remaining Linux evidence. `qcom_stats` only reads firmware-owned scalar records and a separate DDR table; it has no attempt/rejection counter or writer. DDR frequency-bin changes show that table reader and its refresh path work, but do not validate the separate scalar record area or decode numeric LPM IDs. The three zero scalar counts therefore mean only that no successful dwell was recorded by those named records (or that this firmware does not populate them); they cannot distinguish denial from unreported state. Linux RPMh SLEEP/WAKE writes are staged as non-waiting TCS commands; tracepoint `rpmh_send_msg` can show the intended messages, but those messages have no firmware-application acknowledgement. PSCI SYSTEM_SUSPEND return 0 has the same boundary: it validates the suspend call returned after wake, not the physical substate. PSCI residency/count functions are optional and absent from the Nova firmware's exposed feature list.

The next potentially useful low-cost source/evidence check is to inspect the installed stock Android boot/DTBO artifacts for the exact Nova merged resource declaration. If that does not establish the Nova buffer's owner, size, and parser schema, CXPC remains unavailable as a safe diagnostic. If available, a bounded parser could safely surface blockers; residency still needs documented AOP/PMIC counters, a PSCI stats implementation with topology, or an equivalent firmware/hardware trace. No device partition was read, no firmware request or memory read was made, and no drain test or power-policy change occurred.

### 2026-09-18 15:55 UTC — live Nova gamepad holds BOB2 on, a plausible collapse blocker worth a controlled test

Read-only inspection of the running device's active FDT and sysfs found `soc@0/geniqup@8c0000/serial@89c000/gamepad` is present, and its live `serial1-0` child is bound to Armada's `rsinput` driver. The device reports `power/runtime_status=unsupported`. Its supplier symlink resolves to regulator 17, `vreg_bob2`, which is currently enabled with `suspend_mem_state=disabled` and two users. This agrees with the Armada DTS, where the UART gamepad's `vdd-supply` references `vreg_bob2`, and driver source calls `regulator_enable()` in probe and `regulator_disable()` only on remove; the driver declares no suspend/resume PM callbacks. Sources: [Armada shared Nova/QCS8550 DTS](/Users/danhimebauch/Developer/.external-research/armada-packages/kernel/dts/qcs8550-ayn-common.dtsi:1698), [rsinput driver patch](/Users/danhimebauch/Developer/.external-research/armada-packages/kernel/patches/0031_input--Add-driver-for-RSInput-Gamepad.patch:450).

This aligns with two independent leads: Pocknix's current shared AYN DTS adds `regulator-off-in-suspend` for BOB2, and the public RP6 LineageOS sleep issue reports `suspend_stats/success` stayed zero while its `moorechip-joystick` driver was bound, then incremented after unbinding `serial0-0`. The Nova Armada driver is `rsinput`, not that Android driver, so this is a hardware-path analogy rather than a reproduced cause. Pocknix's rail constraint also requires actual qcom RPMh suspend support to reach firmware; Armada has neither on the live Nova rails.

Important limit: our prior short direct-deep runs still returned success through PSCI and APSS firmware recorded sleep across nearly the full RTC interval. The gamepad therefore does not explain a failure to enter the Linux suspend path. It could still keep BOB2/UART resources active and affect which AOP collapse level is possible; current evidence cannot show that. A reversible unbind/rebind comparison or a short boundary-aligned serial wake/IRQ trace is the smallest test of this lead. No driver was unbound, no rail or policy was changed, no suspend/drain test was run, and device input remains live.

Follow-up analysis of the already captured exact-boundary archives `20260918T150858Z-22033088fb46` (s2idle), `20260918T151128Z-c37641215f54` (deep), and `20260918T152059Z-84e958e01abf` (s2idle) lowers the UART-wake hypothesis: the live-mapped `qcom_geni_serial_uart1` IRQ count was unchanged in all three runs, and among parsed wake sources only the RTC advanced by one event per run. This shows the gamepad UART did not generate a handled IRQ or recorded wake-source event during these short tests. It does not show whether its enabled BOB2 regulator vote inhibits a firmware collapse state; no rail-acceptance telemetry is exposed. Evidence is preserved in each run's `device/pre|post/interrupts.json` and `wakeup_sources.json`.

The same pre-run regulator summary shows why blindly copying Pocknix's BOB2-off-in-suspend setting is not a safe test: Armada reports two BOB2 consumers, `serial1-0-vdd` (the gamepad) and `vreg_l17b_2p5`, whose consumer is `1d84000.ufshc-vcc` (UFS VCC). Its regulator tree shows L17 is parented by BOB2. The current image keeps both users enabled while awake. We have not established that UFS reliably disables L17 before the BOB2 suspend vote, or that the QCS8550 suspend callbacks will program that constraint in this kernel. Changing BOB2 in isolation could interrupt the storage supply or fail constraint propagation. This makes a BOB2 policy patch less minimal/safe than it first appeared; inspect UFS suspend behavior and all downstream load requirements before any A/B.

### 2026-09-18 16:10 UTC — focus narrowed to sleep-state observability; stock DTBO does not expose CXPC monitor

User explicitly redirected this work away from drain-rate measurements and toward answering the remaining state-acceptance questions and reducing sleep opacity. No battery-drain run was started.

A read-only root stream of the Nova's internal `dtbo_a` partition produced a 24 MiB Android DT table: header magic `0xd7b7ab1e`, 56 entries, 13 MiB table payload. The entries are generic Qualcomm Crow overlays. Searching the entire image's printable strings found no `retroid`, `nova`, `qcs8550`, `sys-pm-vx`, `cxpc`, `lpm_mon`, `qmp_aop`, `0xc320000`, or `0x0c3f0000` identifiers. The currently selected Android slot was not established, and a DTBO table alone does not contain/validate the base Nova tree; `vendor_boot_a` remains the next read-only artifact to inspect. No partition was written or flashed. The raw temporary copy is `/tmp/nova-dtbo-a.img`, SHA-256 `1bd16dd02a532121fa1b1b3f5d3aa23c7916e880b40ae43678574c381fd3b1a5`.

Two existing diagnostic facts make another broad RPMh run unnecessary for the immediate software-request question. Archived run `20260918T002946Z-d404cb093fb9` already recorded six WAKE and six SLEEP `rpmh_send_msg` TCS rows, with the SLEEP rows at the same trace timestamp as `psci_domain_idle_enter state=0x4100c344`. That shows Linux staged the sleep vote set immediately before entering the mapped `cluster-sleep-1` state. It does not report an AOP apply acknowledgement or prove physical residency. The current trace profile is noisy because it also records active TCS traffic; a future focused profile can filter `rpmh_send_msg` to `state < 2` and add the suspend marker if a receipt is needed. Source enum: Linux v7.2 `include/soc/qcom/tcs.h` (`SLEEP_STATE=0`, `WAKE_ONLY=1`, `ACTIVE_ONLY=2`).

Likewise, saved `available_events.txt` from current-image traces includes `ufs:ufshcd_system_suspend`, `ufs:ufshcd_system_resume`, `ufs:ufshcd_wl_suspend`, and `ufs:ufshcd_wl_resume`, but the `ufs-irq` profile does not select these events; its candidate-name filter selects runtime suspend/resume but not system/WL suspend. Thus existing captures cannot answer whether UFS enters its low-power device/link state before PSCI. Adding these four event names to the research-only profile is a no-kernel-build diagnostic improvement. The kernel trace format captures callback result and software device/link state, not rail residency. No files were changed in the lab runner yet, and no device suspend or power-policy change was made in this update.

### 2026-09-18 16:13 UTC — stock vendor_boot has CXPC layout only in Kalama trees, not Crow trees

Read-only extraction of internal `/dev/disk/by-partlabel/vendor_boot_a` returned 100,663,296 bytes (SHA-256 `89a73c967f6305932fac5e397628e07b4c81c24bf08723f72538c48be054eec4`). The Android vendor_boot image contains ten valid appended FDTs. A bounded local parser decoded their root compatible and node properties:

- FDT entries 0–1 identify `qcom,crow` SoC trees. Neither has `sys-pm-vx@c320000`; they contain only the separate `soc-sleep-stats@c3f0000` (`qcom,rpmh-sleep-stats`, `reg=<0x0c3f0000 0x400>`).
- FDT entries 2–9 identify `qcom,kalama` or `qcom,kalamap` variants. Each includes `sys-pm-vx@c320000` with compatible `qcom,sys-pm-violators` / `qcom,sys-pm-kalama` and `reg=<0x0c320000 0x400>`, plus the same `0x0c3f0000/0x400` sleep-stats node.

The currently running Armada FDT identifies the board as `retroidpocket,rpnova`, `qcom,qcs8550`, `qcom,sm8550` and still has no sys-pm-vx node or memory claim for `0x0c320000`. The vendor_boot partition therefore strengthens the family-level layout evidence but does not establish that the Nova's selected Android base tree is one of the Kalama variants or that Armada may safely access this region. The Crow DTBs most closely match the QCS8550 product family and omit the monitor. The Android slot and final board/SoC DT selection remain unknown; `boot_a`/`dtbo_b` or vendor_boot_b may be needed to identify them. This validates the annotation's constraint: a monitor buffer read needs the exact active resource/layout owner, not an address inferred from a sibling SoC DTB. No firmware mailbox request or memory read was attempted; only boot metadata was streamed out of the read-only partition, with no write/flash.

The `vendor_boot_a` raw copy is at `/tmp/nova-vendor-boot-a.img`; only parser output/hash is intended as durable evidence. `dtbo_a` is a separate generic Crow overlay table and contains none of the monitor identifiers; its current-slot applicability is unverified.

### 2026-09-18 16:15 UTC — A/B slot comparison removes image-slot ambiguity; UFS suspend capture added to recorder

Follow-up to the 16:13 stock-image inspection: internal `vendor_boot_a` and `vendor_boot_b` have identical SHA-256 `89a73c967f6305932fac5e397628e07b4c81c24bf08723f72538c48be054eec4`; `dtbo_a` and `dtbo_b` are also identical at `1bd16dd02a532121fa1b1b3f5d3aa23c7916e880b40ae43678574c381fd3b1a5`. So the active Android A/B slot cannot change whether these two image classes contain the CXPC node. `boot_a` is an Android boot image with a kernel and small ramdisk but no valid appended FDT header; the SoC DTBs reside in vendor_boot. The only stock vendor_boot FDTs with the CXPC node identify as `qcom,kalama` / `qcom,kalamap`; its two `qcom,crow` SoC trees omit it. None is a board-specific Nova tree, and the running Nova DT still lacks the resource. Thus the family node is proven in bundled sibling-SoC firmware metadata but not safe for the Nova's active QCS8550 tree; no monitor query/read is warranted.

A minimal recorder-only change now includes four already-available UFS tracepoints in the `ufs-irq` profile's candidate selection: system suspend/resume and well-known-LUN suspend/resume. These events were present in archived `available_events.txt` but absent from captured trace formats because earlier profiles did not enable them. They should provide the UFS callback result plus the driver's reported current UFS device/link state, which can settle whether the driver reaches a low-power software state before PSCI; this is not physical rail-residency proof. Host `py_compile`, `host self-test`, and `git diff --check` pass. The runner has not yet been deployed for this profile test; no kernel build, policy edit, partition write, suspend run, or drain measurement occurred in this update.

### 2026-09-18 16:24 UTC — UFS system suspend succeeds in POWERDOWN with link off before PSCI

The updated research-only recorder was deployed by SCP to `/tmp` with SHA-256 `fb862b566196e39c9246e7cb34a8bf9c22f60ed4350a1de5fa6cfb900386733b`, then launched through a one-shot `sudo -S` command. Run `20260918T162030Z-e4eb3cc40e76` completed on the same boot, with a 45-second RTC-woken s2idle request, Wi-Fi/Bluetooth preserved, no kernel or policy change, and all 4,616 archive checksums valid. The device returned to SSH after Wi-Fi resumed.

The new tracepoints closed the UFS callback gap. `ufshcd_wl_suspend` at 13516.990013 reports 21,495 us, `dev_state=UFS_POWERDOWN_PWR_MODE`, `link_state=UIC_LINK_OFF_STATE`, `err=0`. `ufshcd_system_suspend` at 13517.007096 reports 15,208 us with the same powerdown/link-off state and `err=0`. Resume tracepoints also show the expected path back to `UFS_ACTIVE_PWR_MODE` / `UIC_LINK_ACTIVE_STATE`. This proves the Linux UFS callbacks succeeded and the driver reported its device in POWERDOWN with the UniPro link off before the suspend window. It does not, by itself, prove the UFS VCC rail or its parent BOB2 regulator was physically disabled, but it substantially lowers the hypothesis that an active UFS device/link prevents deeper sleep. The existing regulator summary still shows BOB2 shared with the gamepad and UFS VCC, so no BOB2 suspend vote was applied.

The harness addition is intentionally small: four existing tracepoint names were added to the existing UFS profile selection. `py_compile`, host self-test, and `git diff --check` passed before deployment. Raw trace, event format files, status, and integrity receipt are preserved under `../sm8550-suspend-lab-runs/20260918T162030Z-e4eb3cc40e76/device/`. No drain estimate was analyzed; this was a callback-state diagnostic only.

Follow-up from the same run after parsing its exact suspend markers and qcom_stats boundary: UFS `system_suspend` completed at trace time 13517.007096; Linux's `machine_suspend` began at 13517.219404 and `timekeeping_freeze` began at 13517.220853, so the successful UFS POWERDOWN/link-OFF state precedes the core suspend window by about 0.21 seconds. The RTC wake completed a 44.125-second proven s2idle interval on the same boot. APSS SMEM recorded +1 entry and +847,143,016 ticks over the 46.56-second read bracket; ADSP recorded +8 entries. AOSD, CXSD, scalar DDR, and detailed DDR LPM `0xd4`, `0xd3`, `0x11` remained at zero delta; `0xd0` again tracked frequency-bucket accounting. This repeats the central opacity under the exact callback order: UFS has moved to its successful powerdown/off-link state, Linux enters and exits s2idle, APSS firmware records the matching sleep window, yet the named SoC/DDR records show no entry. This rules out UFS failing its system-suspend callback as the explanation for those zero records, but does not prove its regulator tree or the physical SoC state.

### 2026-09-18 16:35 UTC — AOSS QMP trace confirms only a DDR frequency-sync acknowledgement, not a residency query

Run `20260918T163315Z-66531ace129a` used the existing `rpmh-aoss` trace profile during a 30-second RTC-woken s2idle cycle. Armada's normal suspend dispatcher returned successfully, the device resumed on the same boot, the measured suspend-clock separation was 29.130364 seconds, and the private trace instance was removed. The live state request was again `cluster-sleep-1` (`0x4100c344`). Full archive: `../sm8550-suspend-lab-runs/20260918T163315Z-66531ace129a/device/`.

The boot-clock trace contains exactly one AOSS message pair: `{class: ddr, action: freqsync}` at 14268.234068 and `aoss_send_done ...: 0` at 14268.234334. It precedes the PSCI cluster-state entry at 14269.189479. No AOSS message appears during the suspended interval, and none requests `lpm_mon`, CXPC, AOSD, CXSD, or residency readback. This proves a DDR frequency-sync message reached the AOSS mailbox and was acknowledged before PSCI entry; it does not prove the sleep TCS set was applied or identify the physical low-power state. Linux v7.2's `qmp_send()` waits for the AOSS mailbox message to be consumed/cleared and returns zero on that transport acknowledgement. The `qcom_aoss` debugfs entries remain write-only controls, not readback interfaces: [qmp_send implementation](https://github.com/torvalds/linux/blob/v7.2/drivers/soc/qcom/qcom_aoss.c#L1860-L1951), [debugfs implementation](https://github.com/torvalds/linux/blob/v7.2/drivers/soc/qcom/qcom_aoss.c#L2301-L2418).

Boundary qcom_stats again recorded no AOSD, CXSD, or scalar DDR entry; APSS recorded one interval matching the suspend window. Combined with the earlier exact RPMh trace, Linux's staged sleep TCS requests and AOSS mailbox transport are visible, but neither interface reports a firmware acceptance/readback status. This does not close the physical residency question. No battery-drain interpretation, QMP query/write, MMIO access, kernel build, image change, or persistent device-policy change was performed.

Source audit further narrows BOB2. Linux v7.2 UFS suspend follows the observed `UFS_POWERDOWN_PWR_MODE` plus `UIC_LINK_OFF_STATE` with `ufshcd_vreg_set_lpm()`. Its power-off branch disables the UFS device regulators; its fallback still disables VCC when the device is not active. Nova routes UFS VCC through PM8550 L17, whose parent is BOB2, while the UART gamepad consumes BOB2 directly and its RSInput driver has no suspend callback. So UFS can release its own BOB2-backed vote during suspend, but the gamepad retains a direct vote. Existing regulator summaries are taken after resume and cannot prove the physical rail changed while suspended. Source: [UFS LPM regulator path](https://github.com/torvalds/linux/blob/v7.2/drivers/ufs/core/ufshcd.c#L10103-L10143), [UFS system suspend](https://github.com/torvalds/linux/blob/v7.2/drivers/ufs/core/ufshcd.c#L10599-L10624), [Armada kernel DTS tree](https://github.com/armada-os/armada-packages/tree/main/kernel/dts).

### 2026-09-18 19:47 UTC — stock Android ADB can test whether its active Nova tree binds the vendor CXPC blocker driver

A fresh source review found a practical Android-mode diagnostic that is not available in the current Armada FDT. The public AYN QCS8550 Android kernel's `sys_pm_vx.c` binds to `qcom,sys-pm-violators`; when paired with its `sys-pm-vx@c320000` resource and AOP mailbox it exposes `/sys/kernel/debug/sys_pm_violators` plus platform sysfs `debug_enable` and `debug_time_ms`. Its debug path asks AOP for `{class: lpm_mon, type: cxpc, ...}`, then reports the driver votes associated with blocked collapse. Source: [AYN QCS8550 sys_pm_vx driver](https://raw.githubusercontent.com/Ayn8550Dev/android_kernel_ayn_qcs8550/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/sys_pm_vx.c#L167-L190), [debug interfaces and parser](https://raw.githubusercontent.com/Ayn8550Dev/android_kernel_ayn_qcs8550/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/sys_pm_vx.c#L191-L363), [suspend/resume monitor flow](https://raw.githubusercontent.com/Ayn8550Dev/android_kernel_ayn_qcs8550/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/sys_pm_vx.c#L461-L509).

This makes ADB worthwhile for one targeted, read-only check: capture Android's actual runtime FDT identity and search for a bound `sys_pm_vx` platform device, its sysfs attributes, and an existing `sys_pm_violators` debugfs file/log. The vendor_boot Crow FDTs already extracted from both slots omit the node, so the result is uncertain rather than expected; runtime inspection would settle whether Android adds a board overlay or uses another boot tree. ADB shell may read the tree and sysfs without root; reading debugfs or enabling the monitor may require root. Do not write `debug_enable` until the live tree confirms that exact driver/resource is bound and its endpoint is the documented one.

Even if available, this driver is a blocker-vote diagnostic, not a physical AOSD/CXSD/DDR residency counter. Its own logic uses subsystem/system sleep-stat deltas and can identify votes associated with collapse being blocked; it cannot by itself certify which electrical state was reached. The QCS8550 `subsystem_sleep_stats` implementation decides “system slept” from changes in firmware-owned counter values, so the known zero-counter interpretation still matters: [system sleep counter check](https://android.googlesource.com/kernel/msm.git/+/9671bc00773d7f73172f1cf38a7cd638091d0214/drivers/soc/qcom/subsystem_sleep_stats.c).

Local Mac has Android platform-tools installed at `/Users/danhimebauch/Library/Android/sdk/platform-tools/adb`; `adb devices -l` currently shows no attached device. No Android-mode access or device change has been performed.

### 2026-09-18 19:51 UTC — Rooted Android helps inspect debugfs but does not make the CXPC reader safe by itself

Closer review of the public `sys_pm_vx.c` parser shows a safety condition for any future rooted test: `read_vx_data()` trusts firmware-provided `logsize` and iterates that many records without first checking that the records fit inside the declared resource buffer. Therefore, root access alone is not a reason to `cat /sys/kernel/debug/sys_pm_violators` or set `debug_enable`. First identify the exact Android kernel/driver version, active runtime DT resource size, bound device and attribute modes; then audit that version's parser bounds. If it is the same unbounded implementation, do not invoke its reader/monitor; Android remains useful for read-only DT, bind, sysfs, debugfs-presence and kernel-log inspection. If a bounded implementation is present, its staged monitor may take multiple suspend/resume cycles and provides collapse-blocker votes, not definitive physical residency proof. No device command or change occurred while recording this caveat.

### 2026-09-18 20:00 UTC — Android runtime confirms the CXPC driver and exact buffer, but keep its parser disabled

The Nova is connected over USB ADB and already authorized (`adb devices -l` reports serial `675a2365` as `device`, not `unauthorized`). The Mac's existing `~/.android/adbkey` and `.pub` are present, so reconnects using this host key should not need a new device approval unless ADB authorizations are revoked, USB debugging is disabled, or the device is reset. No Android settings were changed.

Read-only ADB reports Android 13 build `qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys`, kernel `5.15.123-android13-8-g697b78910a71-dirty`, runtime model `Qualcomm Technologies, Inc. KalamaP HDK`, and active DT compatible `qcom,kalamap-hdk`, `qcom,kalamap`, `qcom,hdk`. The active node `/sys/firmware/devicetree/base/soc/sys-pm-vx@c320000` is compatible with `qcom,sys-pm-violators` and `qcom,sys-pm-kalama`; its `reg` bytes decode to base `0x0c320000`, size `0x400`. Platform device `c320000.sys-pm-vx` is bound to `sys-pm-violators`; the loaded module exposes `debug_enable=0` and `debug_time_ms=10000`. The debugfs endpoint exists but is root-readable only; shell did not read it. Neither control was written.

The exact loaded module was copied read-only from `/vendor_dlkm/lib/modules/sys_pm_vx.ko` to `/tmp/nova-sys_pm_vx.ko` (SHA-256 `60783c435d0ac12b778579541b8c717b222406d4e0d43698c3fd7fece8870d57`, ELF BuildID `37fcfd0060c49bc219338f1151128aec0aa115f4`). Its SCM version is `g697b78910a71-dirty`; that abbreviated commit is not resolvable in the public AYN repository, so source-version identity is not exact. The unstripped ARM64 module contains `read_vx_data`, `logsize`, and the same `lpm_mon/cxpc` messages as the public driver. Disassembly shows `read_vx_data` using the firmware count for record allocation/iteration and no apparent comparison with the `0x400` mapping length. This matches the public source's uncapped `kcalloc(logsize, ...)` and loop at [sys_pm_vx.c lines 191–237](https://raw.githubusercontent.com/Ayn8550Dev/android_kernel_ayn_qcs8550/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/sys_pm_vx.c#L191-L237), but the module was not invoked to read the firmware buffer. Since its suspend callback can call this parser automatically after staged monitoring, do not set `debug_enable` until a reliable bound is established or the driver is fixed. This is a meaningful Android-side finding: the monitor is actually present on Android despite absent Armada runtime DT, but its result path is not safe to trigger yet. ADB emitted only permissive SELinux audit records for shell metadata reads; no policy was changed and no sleep test ran.

### 2026-09-18 20:10 UTC — Quantifying the sys_pm_vx buffer overrun condition

The active Kalama driver has 22 vote columns. Each firmware record is one 32-bit timestamp plus six 32-bit vote words (ceil(22/4)), or 28 bytes; the two-word header adds 8 bytes. In the active 0x400-byte resource, at most 36 complete records fit (8 + 36*28 = 1016 bytes); 37 records require 1044 bytes. The public parser stops early on a zero timestamp, but otherwise trusts the 8-bit logsize and does not validate this limit. Therefore the concern is a possible out-of-range MMIO read and kernel fault/reboot if a nonzero log exceeds the mapped resource, not a flash/persistent-data write. The normal monitor may produce far fewer records, but its actual firmware logsize has not been observed safely. No monitor was enabled and no debugfs data was read.

### 2026-09-18 20:24 UTC — Rooted Android baseline counters expose the same zero-residency records

After the Nova rebooted back to Android, root access survived: `/debug_ramdisk/su -c id` returned uid 0 without another authorization dialog. Magisk's database reports shell uid 2000 policy=2 (allow), until=0 (permanent). No bootloader unlock, image flash, or wipe was needed; only that persistent ADB-shell grant was saved.

A read-only baseline from `/sys/kernel/debug/qcom_sleep_stats` shows Android currently selects `[s2idle] deep`. APSS has count 226 and accumulated duration 3,555,280; DDR, CXSD, and AOSD each have count 0 and all-zero timestamps/duration. Detailed DDR LPM counters `0xd4`, `0xd3`, `0x11`, `0xd0` and frequency buckets are all zero. ADSP has count 2,434 and ADSP island count 2,316; CPUSS reports per-core C4 counts plus L3 D4 count 298 / residency 4,881,333. These are boot-lifetime values, not a new test delta. No suspend test ran, no battery/drain measurement was taken, and the CXPC monitor/debugfs reader was not enabled or read.

The kernel also provides `/system/bin/devmem`, but its usage was not yet established; `/dev/mem` and `/dev/kmem` nodes are absent. The baseline command stalled when reading `/sys/power/wakeup_count`, so avoid that blocking read in subsequent collection. Next useful diagnostic is one short Android s2idle cycle with before/after snapshots of the existing qcom_sleep_stats counters, while leaving sys_pm_vx debug_enable at 0; this can establish Android's regular counter delta without entering the unbounded CXPC parser.

### 2026-09-18 20:27 UTC — Android test path and fresh pre-test counter snapshot

A fresh read before any deliberate suspend shows APSS count 771, last-entered 6,161,892,064, last-exited 6,161,903,547, accumulated 12,764,973; DDR/CXSD/AOSD remain all zero; sys_pm_vx debug_enable remains 0 and debug_time_ms remains 10000. These are a live pre-test snapshot, not a controlled delta. The interval since the earlier post-reboot snapshot included normal user/ADB activity and must not be interpreted as a sleep measurement.

The PMIC RTC is rtc-pm8xxx and Toybox provides rtcwake with mem mode; /sys/power/mem_sleep still selects s2idle. This allows a short RTC-woken s2idle check. /dev/mem and /dev/kmem are absent; Toybox devmem fails opening /dev/mem, so no raw buffer address was read and no /dev/mem node was created. The prior combined inventory stalled on the blocking /sys/power/wakeup_count read; that process was terminated. Skip wakeup_count and use rtcwake for the short controlled cycle.

### 2026-09-18 20:28 UTC — Android RTC wake is available but direct suspend is blocked while attached

One short, RTC-woken `rtcwake -u -m mem -s 15 -d /dev/rtc0` attempt did not enter suspend: Toybox reported `xwrite: Device or resource busy` when writing the selected mem state. The command returned immediately. qcom_sleep_stats snapshots immediately before and after are identical: APSS count 1163, last-entered 8,298,885,037, last-exited 8,298,901,776, accumulated 19,015,214; DDR, CXSD, AOSD, and all detailed DDR LPM/frequency counters remain zero. sys_pm_vx debug_enable stayed 0. No sleep interval or battery/drain measurement occurred. The earlier APSS count 771 was a separate snapshot before the attempt and had already advanced during ordinary Android activity; it is not the test delta. Next inspect Android kernel wakeup_sources and PowerManager blockers to explain EBUSY before retrying; do not read /sys/power/wakeup_count, which blocked the earlier shell command.

### 2026-09-18 20:31 UTC — USB SSUSB remains the likely Android direct-suspend blocker

Android's stay-awake-while-plugged-in global setting was confirmed as 15, temporarily set to 0, and the screen was explicitly put to sleep. PowerManager then reported mWakefulness=Asleep, mStayOn=false, and mHoldingDisplaySuspendBlocker=false. With that display blocker released, a second 15-second RTC-woken mem/s2idle attempt still failed immediately with EBUSY. The original setting was restored to 15 in the same command.

The nearby read-only wakeup_sources snapshot had PowerManager wake-lock count 0 but showed a600000.ssusb active_since/total_time 563,308 ms while the USB cable remained attached; the separate usb source had no active_since. Counters immediately before/after the failed attempt stayed identical (APSS 1845; DDR/CXSD/AOSD and detailed DDR counters zero), confirming the kernel did not enter the requested state. This points toward the SSUSB controller/gadget path as the remaining likely blocker, but it is still an inference until testing without the cable. No battery drain comparison or successful suspend cycle occurred. Next, use existing authorized Wi-Fi ADB (temporary port 5555) and ask the user to unplug USB so we can repeat the short RTC-woken s2idle test with control retained over Wi-Fi.

### 2026-09-18 20:32 UTC — Persistent ADB root and Wi-Fi transport are established

The device was already bootloader-unlocked and Magisk 30.7 was installed/running; no boot image, partition, or user data was changed. After the user accepted Magisk's root dialog and the device rebooted, ADB root returned uid 0 in the Magisk SELinux domain. Magisk policy now contains uid 2000, policy 2 (allow), until 0 (permanent); a second post-reboot request succeeded without another prompt. The Mac's persistent ADB key also remains trusted.

To isolate USB as a possible suspend inhibitor without losing control, adbd was switched to TCP port 5555 for this boot and the authorized Mac connected to 192.168.0.163:5555. Root over that link works without an additional prompt. This is temporary to the current boot and can be returned to USB mode after the test. The saved Android stay-awake setting is restored to 15. While the cable is still attached, wakeup_sources shows a600000.ssusb active_since=652375 ms; next test depends on disconnecting USB while retaining Wi-Fi ADB. No sleep was entered in this step.

### 2026-09-18 20:34 UTC — after USB removal, Android qcom sleep counters are now nonzero

The user physically disconnected USB while the authorized Wi-Fi ADB connection remained live. Root still works (`uid=0`, Magisk SELinux domain); Android reports `stay_on_while_plugged_in=15`, `mWakefulness=Asleep`, `mStayOn=false`, and `mHoldingDisplaySuspendBlocker=false`. The wakeup_sources row for `a600000.ssusb` now shows `active_since=0`, unlike the attached-cable snapshot, so the SSUSB source is inactive at this capture.

A fresh boot-lifetime qcom_sleep_stats read now reports APSS count 1953, DDR count 311, CXSD count 310, and AOSD count 1949; DDR LPM `0xd4` count is 311, while `0xd3` and `0x11` are zero and `0xd0` has 311 frequency-accounting samples. This differs sharply from earlier snapshots in this boot where DDR/CXSD/AOSD showed zero. It is not a matched before/after RTC test and the counter increase cannot be attributed solely to unplugging USB or to a deliberate suspend attempt. Still, it shows those Android firmware counters can become nonzero in normal device operation; they are not absent from the runtime tree. Preserve this as a lead and first capture boot ID/uptime plus immediate pre/post snapshots around one 15-second RTC-woken s2idle attempt before drawing a controlled conclusion. No battery drain measurement or sys_pm_vx parser access occurred.

### 2026-09-18 20:35 UTC — one Android RTC/mem attempt records APSS, DDR, CXSD, and AOSD entry

With USB physically disconnected, root over Wi-Fi ADB, display already asleep, original `stay_on_while_plugged_in=15` restored, and `a600000.ssusb` inactive, ran one `/system/bin/rtcwake -u -m mem -s 15 -d /dev/rtc0` attempt. It returned status 0 and kept the same boot ID (`45c48211-b345-477c-b1bb-ef163dce7b73`). Fresh before/after qcom_sleep_stats deltas were APSS +1 count / +20,935,752 duration ticks; DDR +4 / +20,008,806; CXSD +4 / +19,944,416; AOSD +31 / +19,744,656; DDR LPM `0xd4` +4 / +20,015,012 ticks. The `0xd3` and `0x11` DDR LPM counts stayed zero. This is the first controlled Android suspend request that demonstrably advanced all the named records, proving Android's runtime firmware counters are observable and at least those shallow/collapsed records can register on this device.

Limit: `/proc/uptime` advanced only from 925.11 to 926.61 seconds (about 1.5 seconds) around a requested 15-second RTC alarm, and Toybox printed an RTC date in 1970. Thus this run proves a successful suspend/resume callback and counter delta, but not a 15-second residency; an early wake or clock-domain issue remains to explain. Next inspect wakeup-source/IRQ deltas and RTC state to identify why it returned early. No battery/drain data, sys_pm_vx parser/MMIO read, kernel build, or persistent Android setting change occurred.

### 2026-09-18 20:36 UTC — Android early wake/abort evidence points to timerfd plus WLAN activity

After the short RTC/mem run, read-only inspection of `dmesg`, `/sys/kernel/debug/wakeup_sources`, RTC sysfs, and `/proc/interrupts` found repeated Android `PM: suspend entry (s2idle)` / `PM: suspend exit` cycles. The kernel logged `PM: Pending Wakeup Sources: [timerfd]` and `Abort: Pending Wakeup Sources: [timerfd]`; adjacent Qualcomm WLAN messages said `pmo_core_psoc_send_host_wakeup_ind_to_fw` and `WLAN triggered wakeup: BPF_ALLOW (39)`. The wakeup-source table currently records `alarmtimer.0.auto` with wakeup_count=1 and expire_count=1, and the PM8550 RTC alarm IRQ count is 3, consistent with the RTC path having fired at least once (the IRQ count is not a before/after delta). The kernel log and qcom counters therefore support actual s2idle attempts and firmware counter advancement, but repeated pending timerfd wake events prevent treating the requested 15 seconds as sustained residency. The current debugfs wakeup_sources rows do not map generic `timerfd` back to a particular Android process; next use read-only `dumpsys alarm`/suspend diagnostics to identify the owner or alarm source. No Android power policy was changed, no battery delta was examined, and Wi-Fi stayed enabled so ADB control remains available.

### 2026-09-18 20:37 UTC — correction: RTC alarm delivery was not demonstrated

Correction to the 20:36 note: the `alarmtimer.0.auto` and PM8550 RTC IRQ numbers were read only after the attempt and are cumulative; there was no pre-attempt value, so they cannot establish that this attempt's RTC alarm fired. The command returned status 0, but its short elapsed time and the kernel's repeated `timerfd`-pending suspend aborts make an early non-RTC wake more plausible. `/sys/class/rtc/rtc0/date` reports 1970-01-01, so the displayed Toybox alarm date is also not a sound wall-clock receipt. Accurate statement: qcom firmware counters advanced during the `rtcwake`-requested interval; the request did not prove a 15-second RTC-controlled residency or prove that the RTC alarm caused the resume. Keep the `alarmtimer`/IRQ values as cumulative context only. Next correlate an explicit before/after RTC wakeup-source/IRQ delta and inspect the generic timerfd owner; do not call this a clean timer-woken test.

### 2026-09-18 20:45 UTC — a process-level candidate for Android's generic timerfd blocker

A read-only `/proc/*/fdinfo` correlation found an epoll descriptor in `/vendor/bin/hw/android.hardware.health-service.qti` watching timerfd fd 6 with event mask `0x20000019`; this includes EPOLLWAKEUP (`0x20000000`). The watched timerfd is `CLOCK_BOOTTIME_ALARM` (`clockid=9`), periodic 600 seconds, with roughly 479 seconds remaining at this snapshot. A GNSS service also has a watched timerfd, but its event mask is `0x19` without EPOLLWAKEUP and its clock is ordinary `CLOCK_BOOTTIME` (`7`). This makes the Qualcomm health service timer a plausible owner for one generic `[timerfd]` epoll wake source, but it does not prove that this exact descriptor caused the earlier suspend abort; the timer was not captured while the source was active. The proc-wide scan was stopped after 30 seconds to avoid keeping a long diagnostic running. No process was signaled and no setting changed.

The Android device tree exposes a `qcom,rpmh-sleep-stats` node at `/sys/firmware/devicetree/base/soc/soc-sleep-stats@c3f0000`, alongside separate subsystem and CPUSS stats nodes. This confirms the counters are backed by a distinct firmware stats resource, but raw MMIO pointer words were not read. Previous source review indicates Android's private reader discovers subrecord offsets from firmware pointer words while Armada's mainline driver uses fixed offsets; comparing those values remains an attractive explanation for Android-populated versus Armada-zero records, but is not validated yet. References and source/counter semantics are being checked before we treat it as root cause.

Counter interpretation from source review: the Android records are raw architectural-timer ticks (~19.2 MHz from prior exact-boundary traces). Thus this attempt's ~20.0 million tick increases are around 1.0-1.1 seconds each, consistent with a brief s2idle residence, not 15 seconds. The rows identify firmware-recorded low-power buckets but do not map `0xd4` to a named physical DDR mode. Matching scalar DDR and `0xd4` entry counts are correlation, not proof of the same transition. No battery data was collected.

### 2026-09-18 20:48 UTC — Android stats use two bound drivers over the same 0xc3f0000 resource

Runtime sysfs confirms `/sys/bus/platform/devices/c3f0000.soc-sleep-stats` binds to `soc_sleep_stats` with compatible `qcom,rpmh-sleep-stats`, and `/sys/bus/platform/devices/c3f0000.subsystem-sleep-stats` binds to `subsystem_sleep_stats` with compatible `qcom,subsystem-sleep-stats`; both declare the same `0xc3f0000/0x400` resource. The former creates `/sys/kernel/debug/qcom_sleep_stats/{aosd,cxsd,ddr,...}`; the latter creates `/dev/stats` (root-only), whose Qualcomm driver source supports AOSD/CXSD/DDR and detailed DDR ioctls. Public Android `subsystem_sleep_stats.c` discovers the stats SRAM address by reading a firmware pointer at resource+0x4 and the DDR table pointer at resource+0x1c, then maps the discovered addresses. The exact active `soc_sleep_stats` source and pointer values still need confirmation. This provides a concrete, safe userspace-facing Android stats API, but does not by itself show whether Armada's fixed-offset parser is wrong. No ioctl was issued and no raw MMIO was read.

Timerfd attribution refinement: Linux's generic suspend-abort label `[timerfd]` can be an epoll wakeup-source name for a watched timerfd, not proof of a kernel-created timerfd wake source. The scan found the Qualcomm health service watching a `CLOCK_BOOTTIME_ALARM` timerfd through epoll with `EPOLLWAKEUP`; GNSS's timerfd was ordinary boottime without that flag. This is a plausible attribution path, not proof of the specific aborting epoll item; the broad `/proc` scan was terminated after 30 seconds and did not guarantee an exhaustive process inventory. Next inspect exact Android `soc_sleep_stats.c` source and determine whether qcom_stats pointer values are obtainable through the already-bound `/dev/stats` API or another safe existing interface.

### 2026-09-18 20:49 UTC — exact AYN Android stats reader source confirms dynamic pointer lookup

Fetched the current public `Ayn8550Dev/android_kernel_ayn_qcs8550` `lineage-23.2` source with `gh`. Its active `soc_sleep_stats.c` matches the runtime platform binding: `soc_sleep_stats_probe()` reads a 32-bit firmware offset pointer at the mapped resource plus `config->offset_addr`, computes `stats_base = res->start | readl_relaxed(offset_addr)`, and maps the resulting records (lines 514–566). For `qcom,rpmh-sleep-stats`, the config uses `offset_addr=0x4`, `ddr_offset_addr=0x1c`, three scalar records, and the same driver exposes `/sys/kernel/debug/qcom_sleep_stats` plus `ddr_stats` (lines 661–679 and 471–507). The Nova runtime confirms this driver is bound to the `0xc3f0000/0x400` node and reports nonzero values through its files. Therefore Android's counters are genuinely read from firmware-populated stats SRAM using firmware-provided addresses, not inferred from application state.

The exact pointer values at resource+0x4/+0x1c remain unobservable through this driver’s public debugfs or `/dev/stats` output. Mainline Armada `qcom_stats` uses fixed offsets 0x48 and 0xb8 for its scalar and DDR records, so a layout mismatch remains a testable hypothesis, not a conclusion. The next low-effort source/data check is to inspect whether the Nova driver exports a safe raw pointer/offset attribute or whether its ioctl only returns decoded records; do not create `/dev/mem` or issue arbitrary MMIO reads to obtain these values.

### 2026-09-18 20:51 UTC — no safe Android interface found for the literal pointer values; Wi-Fi control remains intact

The exact public Qualcomm/Ayn `subsystem_sleep_stats.c` ioctl path reads AOSD/CXSD/DDR from the firmware-selected mapped records and copies the decoded `struct sleep_stats` to userspace; it does not return the pointer words or resolved physical/relative offsets. The `soc_sleep_stats` debugfs path likewise exposes decoded counters, not its internal `reg` pointers. Runtime access confirms `/dev/stats` is present but root-only. Thus the currently available no-build interfaces cannot answer whether Android's pointer words equal Armada's fixed 0x48/0xb8 values. `/dev/mem` remains absent; no device node was created and no arbitrary MMIO read was attempted. Exact pointer comparison would require a deliberately bounded kernel-side diagnostic or a trusted vendor-provided offset interface.

After the user warned not to strand the diagnostic session, no Wi-Fi toggle was attempted. Final check: ADB over `192.168.0.163:5555` still returns persistent Magisk root; Wi-Fi remains connected and `stay_on_while_plugged_in` remains the original value 15. No Android policy, radio, boot image, or partition was changed.

### 2026-09-18 20:55 UTC — a five-second RTC request was aborted almost immediately, not RTC-woken

To preserve Wi-Fi ADB, repeated one instrumented test with Wi-Fi left enabled: captured boot ID, uptime, the PM8550 RTC alarm IRQ, `alarmtimer.0.auto`, and APSS/AOSD/CXSD/DDR/DDR-LPM counters before and after `/system/bin/rtcwake -u -m mem -s 5 -d /dev/rtc0`. The command returned status 0 in under one second; boot ID stayed `45c48211-b345-477c-b1bb-ef163dce7b73`, host-reported UTC advanced about one second, and `/proc/uptime` advanced 0.51 seconds. Crucially, the RTC IRQ stayed at 3 and both RTC/alarmtimer wakeup-source rows were byte-for-byte unchanged, so the RTC alarm did not fire and this was not a five-second RTC wake.

During the same bracket, counters advanced only briefly: APSS +1 / +1,380,753 ticks; DDR +1 / +996,730; CXSD +1 / +980,650; AOSD +2 / +955,776; DDR LPM 0xd4 +1 / +998,280. At ~19.2 MHz these are roughly 50–72 ms of recorded residency. This proves a short firmware-recorded transition occurred during the request, not sustained 5-second sleep. It also directly demonstrates the `rtcwake` command returned on an earlier wake/abort before its RTC deadline. Wi-Fi stayed enabled/connected, persistent root remained available, no radio or device settings changed, and no battery measurement was taken. Next read only the fresh kernel-log tail to tie this exact attempt to the active suspend-abort source.

### 2026-09-18 20:56 UTC — the same timerfd abort pattern continues with Wi-Fi kept connected

A fresh `dmesg` tail from the screen-off Android session shows repeated `PM: suspend entry (s2idle)` followed roughly 150–200 ms later by `Wakeup pending, aborting suspend`, active source `[timerfd]`, and `PM: Pending Wakeup Sources: [timerfd]`. Nearby Qualcomm WLAN logs repeatedly send the host-wakeup indication and report `WLAN triggered wakeup: BPF_ALLOW (39)`. This confirms the timerfd blocker remains active in the same period as the short RTC request; the WLAN event follows it, but the log does not prove WLAN is the original cause. The exact five-second command's RTC/IRQ before-after equality already proves its alarm did not cause return. No radio toggles were used; Wi-Fi ADB/root remains available.

### 2026-09-18 20:59 UTC — timerfd epoll owners broaden beyond Qualcomm Health

A second read-only `/proc/*/fdinfo` scan was stopped after it had enumerated timerfds watched by epoll with `EPOLLWAKEUP`; it did not change device state. In addition to the Qualcomm Health service CLOCK_BOOTTIME_ALARM timer (600-second period, roughly 332 seconds remaining in its earlier snapshot), the scan found `system_server` epoll fd 167 watching CLOCK_BOOTTIME_ALARM timerfd 170 (about 653.97 seconds to expiry) and CLOCK_BOOTTIME timerfd 171 (about 627.13 seconds to expiry), both with event mask `0x20000019` including EPOLLWAKEUP. `vendor.dpmd` had a CLOCK_BOOTTIME_ALARM timerfd watched with EPOLLWAKEUP but disarmed (`it_value=0`). GNSS, surfaceflinger, qcrosvm, and service managers also had timerfds without EPOLLWAKEUP. These are owners of potentially wake-capable epoll timers, not evidence any one caused the repeated ~200 ms suspend aborts: the sampled timers were not due soon, and the kernel's generic `[timerfd]` wakeup-source label carries no PID. Next use a bounded trace of the active timer and wakeup tracepoints, if tracefs is idle and supports an isolated instance, to correlate expiry and suspend abort without changing Wi-Fi or Android power policy.

### 2026-09-18 21:01 UTC — isolated tracefs capture is blocked by Android policy

Tracefs was confirmed idle (`tracing_on=0`, `current_tracer=nop`) and supports instances. Created a temporary empty `nova_diag` trace instance, but Magisk-root attempts to enable its wakeup-source and suspend events were denied with `Permission denied`; Android's SELinux policy restricts tracefs writes even in the `u:r:magisk:s0` root shell. Removed the empty instance immediately and re-read the global trace state (`tracing_on=0`); no global tracing config or event was changed, no trace was captured, and Wi-Fi ADB was not touched. Do not relax SELinux or change policy for this diagnostic. This closes the safe tracefs route on the current build unless an already-authorized vendor interface exists.

### 2026-09-18 21:03 UTC — Android exposes cumulative suspend failures and live AOP logs, but not a safe CXPC readback

Read-only Android debugfs snapshot while USB remained unplugged: `sleep_time` showed 1,489 recorded intervals in the 0–1 s bucket and 44 in 1–2 s; `/sys/kernel/debug/suspend_stats` showed success=1,529, fail=15, failed_suspend=12, last_failed_dev=`alarmtimer.0.auto`, errno=-16 (`EBUSY`). These are cumulative/runtime diagnostics, not counters bracketed around a controlled RTC interval. The last-failed-device field names a device whose suspend callback failed; it does not override the separate dmesg evidence that `pm_wakeup_pending()` repeatedly reports `[timerfd]`, nor identify the timerfd PID.

The same live Qualcomm stats snapshot had AOSD count 29,542, CXSD 2,795, scalar DDR 2,801; detailed DDR `0xd4` count was 2,857 (duration 19,604,306,156 ticks, shown as ~39%), while `0xd3` and `0x11` were zero. Scalar DDR and `0xd4` no longer have matching counts in this snapshot, so earlier count equality must be treated as coincidence/correlation, not evidence those records are the same transition. No DDR-state name was inferred.

`/sys/kernel/debug/ipc_logging/aop` exists. The static `log` read returned no data; a bounded read from `log_cont` produced old QMP shim traffic (including WLAN power-resource votes around 1.6–3.6 seconds in its trace clock), not a current suspend acceptance/result. A `tail -c` attempt on this continuous endpoint waited; it was interrupted and the read session ended. I also read `/sys/kernel/debug/sys_pm_violators` once and got a mode/violator table, despite the earlier source-audit warning that its firmware-sized log parser is uncapped. Treat this as an accidental single diagnostic read only: no crash/reboot or connection loss followed, but its content is not relied upon and the endpoint will not be read or enabled again. The temporary tracefs instance was already removed; global tracing stayed off. Final check confirmed Magisk root and Wi-Fi ADB at `192.168.0.163` still available, with Wi-Fi connected; no Android setting or radio state changed.

### 2026-09-18 21:08 UTC — Android short-sleep histogram and kernel wake-lock snapshot are not physical-state proof

Source-check correction for the 21:03 snapshot: Linux v5.15 `sleep_time` bins the elapsed suspend interval injected into timekeeping by integer `tv_sec`; the 0–1 s bin means `tv_sec=0`, and 1–2 s means `tv_sec=1`. It is elapsed host time, not AOSD/CXSD/DDR residency. Its 1,533 total bucket entries need not exactly equal `suspend_stats.success` because they update at different points and have different inclusion rules. The latest SystemSuspend dump showed success=1,811, fail=16, failed_freeze=4, last_failed_step=`freeze`; the debugfs failure fields independently name `alarmtimer.0.auto` and `-16`. Linux alarmtimer can return `-EBUSY` when the next alarm is under two seconds away, so this is a plausible explanation for some freeze/suspend failures, not proof it caused each `[timerfd]` wakeup-pending abort.

A read-only `dumpsys suspend_control_internal --wakelocks` snapshot showed all `[timerfd]` rows inactive. One row had 3,760 events / 1,878 wakeups and last-change time close to the current kernel uptime, matching recent repeated activity, but kernel wake-lock rows expose no PID. Targeted fdinfo reads showed the sampled `system_server` CLOCK_BOOTTIME_ALARM timer at ~29 s, its CLOCK_BOOTTIME timer at ~419 s, QTI Health at ~258 s, and `vendor.dpmd` disarmed; all had `ticks=0`. Thus none of the sampled watched timerfds was ready, weakening these specific descriptors as the cause, while leaving an ephemeral/other owner possible. AOSP `dumpsys` corroborates counts only; it cannot attribute the generic source.

The single prior `sys_pm_violators` output reported an empty mode label and `Max Log Entries:27`. Public `sys_pm_vx.c` only labels mode IDs `0xaa` AOSS, `0xcc` CXPC, and `0xdd` DDR. Given the unknown mode and non-identical dirty runtime module, that table cannot be presented as a validated CXPC capture. The reported 27 entries are below the public driver's 36-record capacity for a 0x400 map if the layout matches, but the parser still lacks a general bound; do not read or enable it again. No tracefs writes, process signals, radio/policy changes, or battery measurements occurred; Magisk root and Wi-Fi ADB remained available.

### 2026-09-18 21:13 UTC — Android marks the device asleep while firmware sleep records continue advancing

With USB unplugged, `dumpsys power` reported `mWakefulness=Asleep` and `mIsPowered=false`; Wi-Fi ADB remained connected. `/proc/uptime` was 3,096.33 s. Compared with the earlier unbracketed Android snapshot (AOSD 29,542; CXSD 2,795; scalar DDR 2,801; DDR `0xd4` 2,857), the live firmware records now read AOSD 39,414, CXSD 3,433, scalar DDR 3,439, and `0xd4` 3,439. Thus these Android firmware-owned records continued to advance while the framework considered the device asleep. This supports that Android is exercising the recorded low-power paths over its screen-off period; because the interval was not bracketed around one verified suspend and AOSD/CXSD/DDR numeric records are not a voltage readback, it still cannot name the exact electrical state or map every increment to a successful system-suspend entry. `0xd3` and `0x11` remained zero; current `0xd0` count also equals 3,439, which remains a count coincidence without a source-level equality contract.

### 2026-09-18 21:14 UTC — paired natural-idle snapshot confirms AOSD/CXSD/DDR records advance on Android

Took a second read-only counter snapshot after the device had naturally remained screen-off; USB stayed unplugged and no suspend request or power-policy change was issued. Android reported `mWakefulness=Asleep` at both boundaries, Wi-Fi stayed connected, and root ADB remained available. `/proc/uptime` advanced 87.05 seconds between snapshots. Firmware-record deltas were AOSD +1,430 counts / +920,816,768 ticks (~47.96 s at the independently established ~19.2 MHz scale), CXSD +93 / +928,724,249 ticks (~48.37 s), scalar DDR +93 / +930,191,013 ticks (~48.45 s), and detailed DDR `0xd4` +93 / +930,335,043 ticks (~48.45 s). `0xd3` and `0x11` stayed zero. This is the cleanest Android-side evidence so far that its firmware reports repeated AOSD, CXSD, and DDR-recorded intervals during screen-off idle, totaling about 48 seconds across this 87-second BOOTTIME bracket.

Limits: boundaries were not placed around one controlled suspend entry, so this shows cumulative firmware-recorded activity while Android was asleep, not the exact residency of each kernel suspend attempt. The matching +93 DDR/`0xd4` counts and near-equal durations in this particular bracket do not create a mapping contract; the earlier live snapshot had counts 2,801 vs 2,857. No physical rail/state name can be assigned from numeric firmware record IDs alone. Wi-Fi ADB/root remained connected after the observation; no battery/drain measurement was made.

### 2026-09-18 21:15 UTC — same Android boot and Wi-Fi ADB survived the idle observation

Post-observation check confirmed the original boot ID `45c48211-b345-477c-b1bb-ef163dce7b73` is unchanged, `su -c id` still returns Magisk root, and Wi-Fi remains connected at `192.168.0.163`; no USB cable is attached. `/proc/driver/rtc` still reports its hardware calendar as 1970-01-01, with no alarm IRQ/pending at this check. This preserves the exact-boot provenance of the 21:13→21:14 counter comparison and confirms the bounded natural-idle observation did not strand ADB or leave an RTC alarm pending.

### 2026-09-18 21:18 UTC — successful Linux suspend cycles correlate with firmware state counts, but not one-to-one

On the same Android boot, captured a second natural screen-off interval without issuing a suspend command. `/proc/uptime` advanced 33.93 seconds; `dumpsys suspend_control_internal --kernel_suspends` success increased 2,275→2,304 (+29) while fail stayed 20. Over that same read bracket AOSD advanced +579 counts / 363,861,296 ticks (~18.95 s); CXSD +38 / 367,073,604 ticks (~19.12 s); scalar DDR +39 / 367,683,013 ticks (~19.15 s); detailed `0xd4` +39 / 367,743,330 ticks (~19.15 s). `0xd3` and `0x11` remained zero. This is positive correlation between completed Linux suspend cycles and AOSD/CXSD/DDR firmware records during Android idle, but the count deltas are not 1:1 (AOSD is much more frequent; CXSD/DDR exceed kernel successes), so these counters can include additional firmware transitions and cannot identify a specific electrical state per suspend.

The failure snapshot changed to `last_failed_step=prepare`, `last_failed_dev=3da0000.kgsl-smmu`, errno `-115` (`EINPROGRESS`), while the cumulative fail count did not change in this bracket. This differs from the earlier `alarmtimer.0.auto/-EBUSY/freeze` result and reinforces that sampled PM failures have multiple paths; neither should be conflated with the separate dmesg `[timerfd]` pending-wakeup abort. Same boot ID `45c48211-b345-477c-b1bb-ef163dce7b73`, root remained available, and Wi-Fi stayed connected after the interval.

### 2026-09-18 21:22 UTC — bounded AOP IPC log read yielded no current sleep/CXPC messages

Used Android Toybox `timeout` to bound a read-only two-second sample of `/sys/kernel/debug/ipc_logging/aop/log_cont`, filtering for `lpm_mon`, `cxpc`, AOSS, sleep, and DDR text. It emitted no matching records and returned without leaving a reader running; ADB stayed connected. This is only a no-data result for that brief live stream window, not evidence that AOP receives no sleep votes or that the persistent log has no relevant records. The interface still does not provide an authoritative state-acceptance readback.

### 2026-09-18 21:25 UTC — Android atrace works where direct tracefs writes are denied

A three-second `adb shell atrace -b 2048 -t 3 power` completed without changing SELinux or leaving tracing active. It returned 60 readable events. The trace showed repeated `swrm_device_suspend` and `lpi_pinctrl_suspend` callbacks on thread 8272, TGID 940; `/proc/940/cmdline` identifies that process as `/system/bin/hw/android.system.suspend@1.0-service`. It also showed native PID 1818 acquiring/releasing `qms_event_Handler_wakeLock_` about every 1–1.5 seconds, with BatteryStats updates in between. This confirms Android's suspend HAL repeatedly enters device-suspend callbacks and identifies a periodic QTI power-manager wake-lock activity during the same trace window. It does not show `power:wakeup_source_activate` or map the generic kernel `[timerfd]` source to PID 1818; that remains a candidate only.

This exposes a viable bounded trace route: Android's `atrace` client can collect `power` events even though direct tracefs writes from the Magisk shell are SELinux-denied. A further trace limited to eventpoll/timerfd functions may identify the timerfd source. Post-trace checks confirmed same boot, root, and Wi-Fi ADB remained available; no device policy, radio, or RTC state changed.

### 2026-09-18 21:29 UTC — tracefs is mounted in the tracing service namespace; targeted event tracing may be available

Read-only mountinfo comparison for PID 1 and `traced_probes` (PID 23370 at this check) shows both share the same mounted tracefs at `/sys/kernel/tracing` and `/sys/kernel/debug/tracing`. The expected directories `/sys/kernel/tracing/events/power` and `/sys/kernel/tracing/events/sched` are present, including `wakeup_source_activate`, `sched_waking`, and `sched_wakeup` event directories. This corrects the earlier mistaken conclusion that tracefs itself was absent: the earlier lookup failed because `available_filter_functions` is not present, not because tracefs is unmounted. `CONFIG_FTRACE=y` and relevant function symbols are present, but the missing filter file means function-graph tracing via `atrace -k` is not established and should not be attempted.

A short Perfetto `linux.ftrace` capture may still request these named events through the tracing service without direct Magisk-shell writes. Next inspect its help and the event `format` files read-only, then use a narrowly scoped capture only if Perfetto confirms support. A `wakeup_source_activate` event alone may execute in callback/interrupt context and does not identify the timerfd creator; pair it with `sched_waking`/`sched_wakeup` to identify a woken thread candidate. No tracing setting was changed in this check; no trace was started. The device stayed on the same boot, rooted, with Wi-Fi ADB and USB-unplugged status intact.

### 2026-09-18 21:31 UTC — Perfetto can collect targeted ftrace events with no existing tracing session

Read-only Perfetto service query reports version 25.0, zero active tracing sessions, and a registered `linux.ftrace` data source produced by `perfetto.traced_probes` (PID 23370). Tracefs event format files exist for `power/wakeup_source_activate`, `power/wakeup_source_deactivate`, `power/suspend_resume`, `sched/sched_waking`, and `sched/sched_wakeup`; the scheduler payloads include woken thread `pid` and `comm`. Before any new capture, each selected event's `enable` file read `0`, global `tracing_on` read `0`, and `current_tracer` was `nop`. The available tracer list contains only `nop`; no function-graph tracer is available. This supports a short Perfetto tracepoint-only test without writing tracefs directly or leaving global tracing enabled. No trace has started yet.

### 2026-09-18 21:34 UTC — first bounded Perfetto attempt contained metadata but no kernel events

Ran a 12-second trace with only five `linux.ftrace` events (`wakeup_source_activate/deactivate`, `suspend_resume`, `sched_waking`, and `sched_wakeup`) to a temporary device file. Perfetto reported a completed write (1,145 bytes); host Trace Processor parsed the file and returned zero `ftrace_event` rows. Its `ftrace_setup_errors` stat was zero, so the config was accepted, but the short run did not capture a wake or suspend event. The device-side trace session returned to zero active sessions; post-run tracefs state was `tracing_on=0`, `current_tracer=nop`. The read-only audit log recorded `traced_probes` opening a tracefs event format file with an AVC marked `permissive=1`; no policy or SELinux setting was changed. This is an inconclusive no-event sample, not proof the source does not occur. Repeat only with a longer bounded interval if ADB and root remain available, then compare kernel suspend counters over that interval.

### 2026-09-18 21:38 UTC — longer background Perfetto run also produced no ftrace stream

Started a 30-second background Perfetto trace with the same power/scheduler events plus frequent `sched/sched_switch`. While it ran, Wi-Fi ADB and root stayed available on boot `45c48211-b345-477c-b1bb-ef163dce7b73`; `/sys/power/suspend_stats/success` rose 3,219→3,254 during the first ~32 seconds and later read 3,297 before trace cleanup. The trace query showed one STARTED session with zero data sources and an empty output file, so I sent SIGTERM only to the trace CLI PID that this test itself had printed. It completed on its own between the status check and signal; Perfetto then reported zero sessions, the final file was 1,280 bytes, and tracefs returned to `tracing_on=0`, `current_tracer=nop`. Host Trace Processor confirmed zero scheduler rows and no per-CPU ftrace read counters in the file. This confirms suspend successes continued during the bracket but this Perfetto attempt did not collect them. Next isolate Perfetto collection with its built-in five-second `sched/sched_switch` smoke configuration before another sleep-window attempt; do not infer anything about timerfd ownership from these empty traces.

### 2026-09-18 21:40 UTC — five-second Perfetto scheduler smoke test also recorded no ftrace events

Used Perfetto's documented light-config mode for a frequent `sched/sched_switch` event while the tracing service was idle. The five-second session finished normally and wrote a 983-byte metadata-only trace; Trace Processor found zero `sched` rows and no per-CPU ftrace read counters (`ftrace_setup_errors=0`). Post-capture `tracing_on=0`, `current_tracer=nop`, and the event's enable value was 0. `traced_probes` emitted audit records for reading tracefs event format files with `permissive=1`; there was no observed SELinux mode/policy change. Thus this host's Perfetto ftrace source is registered but is not delivering a trace stream in these tests, even for scheduler switches. Do not extend Perfetto sleep captures until that mismatch is explained. The next low-risk route is a short `atrace` `sched`/`power` capture, which had previously returned readable events, to see whether Android's atrace client can expose the needed kernel tracepoints.

### 2026-09-18 21:41 UTC — power-only atrace repeatedly shows the Android suspend HAL callbacks

A narrowed five-second `atrace -b 2048 -t 5 power` trace returned repeated `swrm_device_suspend` events (`swrm state: 3`) followed by `lpi_pinctrl_suspend: system suspend` on TID 8272 / TGID 940, spaced roughly 1.0–1.5 seconds across the captured timestamps. This is the same Android suspend HAL process previously identified as `/system/bin/hw/android.system.suspend@1.0-service`. Filtering for `wakeup_source`, `timerfd`, generic `suspend_resume`, and kernel pending-wakeup text found none in this `power`-category dump. Thus atrace is a working way to observe suspend-HAL/device callback attempts, but this category does not expose the missing generic wake-source ownership event. The sample does not prove which kernel suspend attempts completed or why they woke. No persistent trace settings remained enabled; root/Wi-Fi ADB remained connected.

### 2026-09-18 21:44 UTC — combined atrace exposes suspend cadence but scheduler tracing is too noisy to attribute wakes

Captured `sched` plus `power` through atrace to a host-only temporary text file. The sample contained 88,204 scheduler/power event lines (13.4 MB) and 11 `lpi_pinctrl_suspend` callbacks over the recorded ~12-second timestamp span. There were zero `wakeup_source_activate/deactivate` events and no `timerfd` text. More than 800 scheduler wake/wakeup records fell within 50 ms before each LPI marker, with recurring targets including `qseecomd`, `ssgtzd`, `perfetto_hprof_`, and kernel workers; the volume and the tracing workload itself make this unsuitable for assigning a wake owner or causal blocker. Keep this as evidence of frequent HAL callback attempts and an overly noisy route, not as an attribution result. Post-capture check: same boot, Wi-Fi ADB/root intact, `suspend_stats.success=3660`, no Perfetto sessions, `tracing_on=0`, `current_tracer=nop`, and Android still reports asleep. No persistent trace setting changed.

### 2026-09-18 21:48 UTC — Android firmware and CPU-idle records all advanced during a bounded asleep interval

Took paired read-only snapshots around a 30-second host sleep while `dumpsys power` reported `mWakefulness=Asleep` at both boundaries. Same boot ID `45c48211-b345-477c-b1bb-ef163dce7b73`; Wi-Fi ADB and Magisk root remained available. Linux `suspend_stats.success` rose 3,750→3,787 (+37). Qualcomm firmware records advanced: AOSD +702 counts / +451,787,664 duration ticks (~23.53 s at the previously established ~19.2 MHz scale), CXSD +45 / +455,662,820 ticks (~23.73 s), and DDR +45 / +456,369,769 ticks (~23.77 s). The L3 `D4` sleep-stat record rose +37 counts / +472,744,327 raw residency units (unit not yet verified). Per-core records also advanced: CPU0 `C4_count` +108 and CPU7 +79; their raw `C4_residency` deltas were +478,956,417 and +800,052,725. `cpu0/cpuidle` exposes `WFI` and `silver-c4` states. The CPUSS counter unit/state mapping still needs source confirmation, so these two residency values remain raw.

This independently confirms that the Android image records repeated AOSD/CXSD/DDR residency during screen-off idle and also accumulates per-CPU C4 and L3 D4 activity. The deltas are not 1:1 with Linux suspend success (AOSD +702, CXSD/DDR +45, L3 D4 +37), so do not equate each count to one kernel suspend attempt or assign a physical rail state. No battery metric or power setting was changed.

### 2026-09-18 21:51 UTC — Qualcomm source identifies C4 and L3 D4 as separate hardware counters

Source follow-up mapped the additional debugfs interface. Qualcomm's downstream `qcom_cpuss_sleep_stats` driver reads and prints raw CPUSS sequencer values: per-CPU C4 count/residency and cluster L3 D4 count/residency. The Kalama device tree labels C4 as `rail-pc` with PSCI parameter `0x40000004`, and cluster D4 as `l3-off` with parameter `0x41000044` ([driver](https://android.googlesource.com/kernel/msm/%2B/refs/heads/android-msm-p11-5.15-tm-wear-kr3-dr-p11-qpr3-release/drivers/soc/qcom/qcom_cpuss_sleep_stats.c#L86), [Kalama state definitions](https://android.googlesource.com/kernel/msm-extra/devicetree/%2B/refs/heads/android-msm-eos-android13-wear-kr3-pixel-watch/qcom/kalama.dtsi#L283)). In the paired asleep snapshot, CPU0 and CPU7 C4 counts rose +108 and +79, while L3 D4 rose +37. That is direct evidence these core/cluster modes were entered during the interval, but C4 can happen during ordinary idle and the public driver does not document residency units. These records are separate from qcom sleep-stats AOSD/CXSD/DDR records, and do not establish those system-level states by themselves.

Correction applied to the paired-snapshot entry above: the L3 D4 residency delta remains raw (`+472,744,327`); I withdrew the earlier ~24.62-second conversion because the CPUSS driver does not establish a 19.2-MHz unit. The established ~19.2-MHz conversion applies to the separate AOSD/CXSD/DDR sleep-stat counters only.

### 2026-09-18 21:53 UTC — wakeup-source deltas differ from the earlier timerfd abort samples

Compared the read-only `/sys/kernel/debug/wakeup_sources` table across another 30-second host sleep while Android remained `Asleep`. All 73 rows parsed at both boundaries and the boot ID stayed `45c48211-b345-477c-b1bb-ef163dce7b73`. Linux suspend success rose 4,075→4,113 (+38). Only three wake-source rows changed: `gh_vcpu_ws_45_0` and `_45_1` each had active/event counts +38; `qcom_rx_wakelock` had active_count +37, event_count +104, expire_count +37, with no `wakeup_count` increase and no `prevent_suspend_time` increase. No `timerfd` row delta appeared. This interval therefore did not record a timerfd wakeup; the recurring Qualcomm receive wakelock and guest-vCPU source events were not counted as wakeups or suspend-prevention time in this sample. They correlate with the period but do not establish causation. This also shows the earlier dmesg `[timerfd]` abort is intermittent rather than present in every screen-off interval. Device stayed online/rooted; no settings changed.

### 2026-09-18 21:57 UTC — Nova live DT confirms the separate sys-pm-vx window

Read-only Wi-Fi ADB inspection confirms the live platform device `/sys/bus/platform/devices/c320000.sys-pm-vx` is bound to `sys-pm-violators`, with compatible strings `qcom,sys-pm-violators` and `qcom,sys-pm-kalama`. Its device-tree `reg` decodes to `0x0c320000/0x400`. This corrects earlier notes that no Nova sys-pm-vx node had been found. The `soc_sleep_stats` and `subsystem_sleep_stats` devices separately both declare `0x0c3f0000/0x400`; neither platform device exposes a `resource` attribute, and `/dev/mem` is absent. The distinct window makes the vendor driver’s mapping plausible but gives userspace no bounded raw-register interface.

Do not read `/sys/kernel/debug/sys_pm_violators` again: the earlier one-time output had an unknown/empty mode, and the public parser trusts a firmware log size without a general bound. Do not infer that the device-tree span validates that parser or manually map/read the area. At this check, Magisk root and Wi-Fi ADB remained available with USB unplugged; the boot ID was unchanged, Android reported `Asleep` and `mIsPowered=false`, and the battery reported `Discharging`. No power, radio, or SELinux settings were changed.

### 2026-09-18 21:58 UTC — stock atrace cannot select the exposed RPMh event group

Read-only tracefs enumeration confirms this kernel has event formats for `rpmh:rpmh_send_msg`, `rpmh:rpmh_solver_set`, `rpmh:rpmh_tx_done`, and related tracepoints. However, `atrace --list_categories` has no `rpmh` category. The device's `atrace --help` says `-k` selects kernel *functions*, not trace events; its available tracer list was already limited to `nop`, and `available_filter_functions` is absent. Thus the working Android `atrace` path cannot be pointed at the RPMh tracepoint, while direct tracefs writes from Magisk root were denied by SELinux and Perfetto's ftrace producer produced no event stream in three bounded trials. Do not try `-k rpmh/rpmh_send_msg` as a workaround: it is the wrong interface. A useful RPMh command trace now requires fixing/using an authorized ftrace producer or adding a small kernel-side diagnostic; no runtime trace settings were changed in this check.

### 2026-09-18 21:59 UTC — an ADSP sleep-monitor debugfs directory exists but remains unqueried

Read-only directory metadata shows `/sys/kernel/debug/adspsleepmon` contains `master_stats`, `adsp_panic_state`, and `read_adsp_panic_state`; the first and third are mode `0444`, while `adsp_panic_state` is `0644`. No file contents were read. The name suggests another potential firmware/master sleep counter path, but semantics and read-side effects are not yet established. Identify the bound driver and source for its debugfs callbacks before querying any entry, especially the apparently writeable `adsp_panic_state` control. No device state or trace setting changed.

### 2026-09-18 22:02 UTC — ADSP master_stats contains sleep counters but reading it requests live DSPPM data

The public OnePlus SM8550 `adsp_sleepmon.c` reference identifies `master_stats` as a combined view of SysMon, DSPPM, ADSP LPM, and ADSP LPI information. Its show callback reads LPM/LPI count and accumulated-duration records from shared memory, but also sends an RPMsg request for the active DSPPM client list and waits for a completion before printing. Thus it may wake or otherwise perturb the ADSP and is not just a passive memory dump. This is promising for understanding ADSP-local sleep and active clients, but it cannot prove APSS AOSD/CXSD/DDR residency. The matching source is a close SM8550 reference, not yet verified byte-for-byte against Nova's vendor module. No `master_stats` or panic-state contents have been read; first check whether the live driver reports a negotiated ADSP version and whether the query path is available. Source: [OnePlus SM8550 adsp_sleepmon.c](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/adsp_sleepmon.c#L358-L376) and [master_stats output](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/adsp_sleepmon.c#L861-L945).

### 2026-09-18 22:04 UTC — one bounded ADSP stats query completed while Android remained asleep

Before the single `timeout 10 cat /sys/kernel/debug/adspsleepmon/master_stats` read, boot ID was `45c48211-b345-477c-b1bb-ef163dce7b73`, suspend success/fail were 4,647/46, and Android reported `Asleep`, `mIsPowered=false`. The query completed in about a second. It returned SysMon core clock 595,200, AB vote 0, IB vote 799,000,000, sleep-latency sentinel `4294967295`; DSPPM version 1 and five rows with PID 0 / zero active clients; ADSP LPM count 98,538 with raw last-enter/last-exit/accumulated values `118621839892 / 118621845931 / 115917978458`; and ADSP LPI count 2,691 with raw values `13476032934 / 13476192388 / 10457922794`. Kept the shared-memory time values raw pending device-specific unit validation. The driver source says the request fetches active DSPPM clients and waits for the response, so this result also confirms that request path returned successfully on Nova. Post-check preserved root Wi-Fi ADB and the same boot; Android still reported asleep. These are ADSP-local records, not proof of APSS AOSD/CXSD/DDR rail state. A source comment says the monitor expects ADSP power-collapse when no audio use case is active, or LPI for an active LPI use case; that is monitor policy, not a direct rail measurement. No panic flag, setting, or trace configuration was changed.

### 2026-09-18 22:06 UTC — ADSP LPM advanced across a natural screen-off interval while LPI stayed flat

Repeated the same bounded `master_stats` read after the screen-off interval. LPM count rose 98,538→100,539 (+2,001); accumulated duration rose 115,917,978,458→118,105,869,835 (+2,187,891,377 raw ticks). Its last-enter and last-exit timestamps advanced by about 2.235 billion ticks. The source constant is 19.2 MHz for this driver's elapsed-time comparisons; if that applies to these LPM deltas, it is about 116.4 seconds elapsed and 114.0 seconds accumulated in LPM (roughly 98% of that timestamp span). Keep this conversion qualified until the exact Nova build's counter clock is verified. LPI count and accumulated duration stayed exactly 2,691 and 10,457,922,794, respectively. This fits the source's expectation that, with no active DSPPM clients, ADSP LPM/power-collapse activity can accrue without LPI audio use, but it does not identify the APSS's AOSD/CXSD/DDR state. Linux suspend success rose 4,647→4,765 over the broader bracket, so ADSP LPM count is not one-for-one with AP suspend successes. The SysMon and DSPPM timestamps were unchanged from the first read; treat those snapshots as stale rather than current votes. Same boot, root Wi-Fi ADB, and Android `Asleep` state persisted after the second query; the `dumpsys` pipeline emitted a harmless broken-pipe message after the requested lines. No persistent settings changed.

### 2026-09-18 22:07 UTC — cross-check supports 19.2 MHz units for the changing ADSP LPM record

Compared the raw ADSP LPM timestamp delta between the two reads with the approximately two-minute host interval: `2,234,800,782 / 19,200,000` is about 116.4 seconds. The accumulated-duration delta converts to about 114.0 seconds, close to that span and consistent with the source's 19.2-MHz counter constant. This empirically supports using that scale for the changing LPM record on this device; the LPI record did not change, so its clock remains untested. One read-only capacity check showed 98% / `Discharging`; this was only to ensure the unplugged device had ample charge for the diagnostic, not a drain-rate measurement. No additional device settings were changed.

Source refinement: Qualcomm's public Android 5.15 driver confirms the LPM and LPI values come from ADSP-owned SMEM IDs 606 and 613, and uses its 19.2-MHz timer constant when converting duration deltas to milliseconds ([record/clock definitions](https://android.googlesource.com/kernel/msm/+/refs/heads/android-msm-p11-5.15-tm-wear-kr3-dr-p11-qpr3-release/drivers/soc/qcom/adsp_sleepmon.c#L46), [SMEM lookup](https://android.googlesource.com/kernel/msm/+/refs/heads/android-msm-p11-5.15-tm-wear-kr3-dr-p11-qpr3-release/drivers/soc/qcom/adsp_sleepmon.c#L488), [conversion](https://android.googlesource.com/kernel/msm/+/refs/heads/android-msm-p11-5.15-tm-wear-kr3-dr-p11-qpr3-release/drivers/soc/qcom/adsp_sleepmon.c#L1012)). It also confirms each `master_stats` read sends a DSPPM client-info RPMsg request and waits for its reply; no source evidence says that leaves a persistent wake lock ([request](https://android.googlesource.com/kernel/msm/+/refs/heads/android-msm-p11-5.15-tm-wear-kr3-dr-p11-qpr3-release/drivers/soc/qcom/adsp_sleepmon.c#L325), [show callback](https://android.googlesource.com/kernel/msm/+/refs/heads/android-msm-p11-5.15-tm-wear-kr3-dr-p11-qpr3-release/drivers/soc/qcom/adsp_sleepmon.c#L785)). This source supports the timebase interpretation but is still a related public Android build, not the exact Nova `-dirty` module source.

### 2026-09-18 22:13 UTC — independent source audit closes the Android no-build offset lookup

An independent review of Nova-matched AYN Android `soc_sleep_stats.c` and `subsystem_sleep_stats.c` confirms there is no decoded-output or ioctl path that returns the raw pointer words at SRAM offsets `+0x4` and `+0x1c`, and the probe does not log them. The existing debugfs and `/dev/stats` interfaces return decoded records only. Armada's upstream `qcom_stats` likewise emits decoded counters after using fixed `0x48`/`0xb8` offsets. Therefore userspace cannot safely compare Android's firmware-selected offsets against Armada's constants; do not use devmem, `/proc/kcore`, arbitrary MMIO, or a second mapping to retrieve them. The smallest exact probe is to add a bounded diagnostic log of the two already-read `u32` words inside the existing Android `soc_sleep_stats_probe()` (or log them from Armada's owned qcom_stats mapping), then compare the raw values and computed bases. This requires rebuilding the relevant kernel/module; no such build or device change was started. Sources: [Android probe and pointer use](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/soc_sleep_stats.c#L479-L543), [decoded subsystem ioctl path](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/subsystem_sleep_stats.c#L265-L356), [Armada qcom_stats offsets](https://codebrowser.dev/linux/linux/drivers/soc/qcom/qcom_stats.c.html#250).

### 2026-09-18 22:18 UTC — passive Android debugfs exposes subsystem SMEM sleep records

The live `/sys/kernel/debug/qcom_sleep_stats` directory also contains `adsp` and `adsp_island` files. The Nova-matched Android `soc_sleep_stats.c` source confirms these are passive `.show` reads: it calls `qcom_smem_get(pid, smem_item)` and prints the `sleep_stats` struct. The mapping is ADSP owner 2 / SMEM item 606 for `adsp` and item 613 for `adsp_island`; unlike `adspsleepmon/master_stats`, this callback sends no RPMsg request. This gives a lower-perturbation route to bracket ADSP LPM and LPI alongside the memory-mapped APSS/AOSD/CXSD/DDR records. Initial snapshot at the same boot while Android reported `Asleep`: suspend success/fail 5,345/53; `adsp` count 112,417 / accumulated 131,048,009,734 ticks; `adsp_island` 2,691 / 10,457,922,794; APSS 7,194 / 69,077,998,479; AOSD 103,378 / 65,801,342,240; CXSD 7,498 / 66,386,293,581; DDR 7,505 / 66,504,805,871. Detailed DDR rows showed `0xd4` and `0xd0` each at count 7,505; `0xd3` and `0x11` zero. These are cumulative baselines; next take one short paired snapshot through the passive path. Source: [subsystem SMEM mapping and passive debugfs show](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/soc_sleep_stats.c#L56-L60) and [show callback](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/soc_sleep_stats.c#L149-L179).

### 2026-09-18 22:20 UTC — passive paired snapshot ties APSS count to kernel suspend successes

Compared the above passive baseline with a second snapshot about 110 seconds later, while Android reported `Asleep` at both ends and the boot ID stayed `45c48211-b345-477c-b1bb-ef163dce7b73`. Linux suspend success rose 5,345→5,443 (+98); APSS count also rose 7,194→7,292 (+98), with APSS accumulated duration +1,246,164,434 ticks (~64.90 seconds at 19.2 MHz). This is an exact count match over this bracket, strong evidence that the APSS record tracks completed suspend cycles here; it is not a per-cycle trace of the requested physical state.

Over the same bracket ADSP SMEM `adsp` rose +2,027 counts and +2,127,140,058 ticks (~110.79 seconds), while `adsp_island`/LPI stayed unchanged. AOSD rose +1,851 counts / +1,188,922,992 ticks (~61.92 seconds); CXSD +126 / +1,199,248,890 (~62.46 seconds); scalar DDR +126 / +1,201,228,729 (~62.56 seconds). Detailed DDR `0xd4` and `0xd0` also each rose +126; `0xd3` and `0x11` remained zero. The AOSD/CXSD/DDR durations agree closely, while their counts are not 1:1 with APSS/Linux suspend success (AOSD is much more frequent; CXSD/DDR exceed it). These firmware-owned records continue to establish that Android records those named modes during natural screen-off idle, without establishing their exact rail mapping or AOP request-acceptance semantics. No `master_stats` query was used for this pair, no battery trend was measured, and root Wi-Fi ADB remained connected on the same boot.

### 2026-09-18 22:22 UTC — comparable vendor sys-pm-vx parsers also lack a resource bound

Inspected `read_vx_data()` in public Motorola, Sony, Xiaomi SM8550, OnePlus SM8550/SM8650/SM8850, Oppo SM8550, and Realme GT5pro Android-U driver sources. The versions checked extract firmware `logsize`, allocate by that value, and iterate it without comparing the byte cursor or per-record reads against the mapped resource length. This matches the already inspected loaded Nova module's unbounded parser pattern; no ready-made bounded downstream implementation was found in these comparable sources. With Nova's mapped window only `0x400` bytes, the sys-pm-violators file remains unsafe to invoke even though the runtime node exists. A future kernel-only fix needs a full cursor/remaining-length check for the header, timestamp, and all vote words before every read, then can collect the blocker log; merely limiting allocation does not bound MMIO accesses. This would still produce blocker/vote information, not authoritative physical residency. Source examples: [OnePlus SM8550](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/sys_pm_vx.c#L1677-L1796), [OnePlus SM8850](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8850/blob/fc30e54174d254ff7f33622a9278e4435f6718d2/drivers/soc/qcom/sys_pm_vx.c#L332-L380), [Realme GT5pro Android U](https://github.com/realme-kernel-opensource/realme_GT5pro-AndroidU-kernel-source/blob/ec3fa33ce1c3dbf68c6161d057b04158340ba465/drivers/soc/qcom/sys_pm_vx.c#L276-L324).

### 2026-09-18 22:26 UTC — SM8850 variant confirms `sys_pm_violators` is not a safer read path

An additional immutable-source check found that Oppo's newer SM8850 `sys_pm_violators` debugfs file still routes through the same unbounded `read_vx_data()` parser. Its new `trigger_dump` control is writable and sends a QMP dump request, so it is not a passive alternative. The checked SM8550 and SM8850 implementations both trust firmware `logsize`; no bounded public implementation was found. One earlier Nova output showed 27 entries; under the assumed Kalama 22-counter row layout this would be about 764 bytes within the 0x400 mapping, but the blank mode and unverified header make that a one-sample size estimate, not a safety guarantee. Do not reread it. Sources: [SM8550 parser](https://github.com/oppo-source/android_kernel_oppo_sm8550/blob/43de4a0d7c608e9c41e1f0bfcf5a52d6d449be98/drivers/soc/qcom/sys_pm_vx.c#L204-L253), [SM8850 parser and mode dispatch](https://github.com/oppo-source/android_kernel_oppo_sm8850/blob/6e9dd7c9bc953b000eca61447debd4ac1350fae1/drivers/soc/qcom/sys_pm_vx.c#L319-L402), [SM8850 debugfs wiring and permissions](https://github.com/oppo-source/android_kernel_oppo_sm8850/blob/6e9dd7c9bc953b000eca61447debd4ac1350fae1/drivers/soc/qcom/sys_pm_vx.c#L493-L528).

At 22:26 UTC the Wi-Fi ADB transport was still live, `su -c id` confirmed UID 0, boot ID remained `45c48211-b345-477c-b1bb-ef163dce7b73`, Android reported `mWakefulness=Asleep` and `mIsPowered=false`, and Linux suspend success/fail were 5,817/57. No device setting or kernel interface was written during this check.

### 2026-09-18 22:44 UTC — repeated 36-row monitor samples are not a hard parser bound

Further exact-firmware review found three public CXPC/RBSC captures from the AOP image matching Nova all report 36 rows, across 1,000–24,464 ms monitor intervals. This suggests a fixed logger capacity, but no firmware code or metadata proves a hard `logsize <= 36`. The AOP ELF is stripped and exposes no max-entry constant. The Android `sys_pm_vx.c` parser trusts an 8-bit firmware logsize; with 22 drivers each 28-byte row, 36 rows plus the 8-byte header fit in 0x400 (1,016 bytes), while 37 would read beyond the mapping. `debug_time_ms=10000` is only a resume eligibility threshold: the AYN driver ignores intervals at or below that threshold, and the QMP templates still request a fixed 1,000-ms monitor, so 10,000 does not prove a longer log cannot overflow. A public experimental patch assumes a 0x1000 buffer, not Nova's 0x400 mapping. Keep `sys_pm_violators` unread until the firmware count is bounded or a bounded parser exists. Sources: [AYN parser/QMP templates](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/sys_pm_vx.c#L182-L250), [threshold/resume logic](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/sys_pm_vx.c#L536-L570), and [matching-hash public captures](https://github.com/jaewun/qcom-aop-debug/tree/89a19b70f554e17ddcf64c3e84037b6532202137/examples/sm8550-6aceb38f).

Artifact cross-check: `/private/tmp/nova-sys_pm_vx.ko` (BuildID `37fcfd0060c49bc219338f1151128aec0aa115f4`) is an ARM64, unstripped copy of the exact Nova module. Its strings contain both CXPC QMP templates with `dur: 1000` and `debug_time_ms_store`, consistent with the source-level interpretation above; its disassembly sets the default threshold to 10,000 ms. No module or device file was changed.

### 2026-09-18 22:28 UTC — DDR LPM IDs are opaque mode identifiers, not frequency buckets

An audit of the Nova-matched Android formatter and Qualcomm-authored Linux `qcom_stats.c` resolves the record-format question: `name[15:8] == 0` marks a DDR low-power record and the low byte (`0xd4`, `0xd3`, `0x11`, `0xd0`) is an opaque DDR LPM name; type `1` is a separate frequency record whose fields encode CP index and MHz. Public source does not map the four LPM IDs to named electrical, DDR self-refresh, or LLCC states. In particular, do not label an observed `0xd4` increment as a specific physical state. Existing control receipts show `0xd0` duration can track aggregate frequency-bin duration, so its residency meaning is especially uncertain. Sources: [Nova-matched Android formatter](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/soc_sleep_stats.c#L217-L233) and [Qualcomm-authored Linux formatter](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L152-L176).

### 2026-09-18 22:30 UTC — distinguish Armada PSCI feature dump from current Android kernel

A live root check caught a platform mismatch in the PSCI research: the archived `/sys/kernel/debug/psci` feature list cited earlier was collected on Armada's 7.2.3 image, not the currently rooted Android 13 kernel (`5.15.123-android13-8-g697b78910a71-dirty`). The Android runtime has no `/sys/kernel/debug/psci` node, and its active DT only identifies `arm,psci-1.0` with `method=smc`; that does not reveal optional PSCI statistics support. Do not apply the Armada feature list to Android. A source/config audit of the matching Android 5.15 kernel remains pending. The live passive `/sys/kernel/debug/qcom_cpuss_sleep_stats/stats` read returned cumulative per-CPU C4 counters and cluster L3 D4 counters; it is separate from AOSD/CXSD/DDR and was not reset. Current same-boot ID remains `45c48211-b345-477c-b1bb-ef163dce7b73`; no device settings or controls were written.

### 2026-09-18 22:33 UTC — Android PSCI stats are unprobed, while a short s2idle bracket advances firmware records

The matching AYN Android 5.15 source audit confirms the live PSCI correction: this kernel has no PSCI debugfs implementation, probes ordinary `SYSTEM_SUSPEND`, `CPU_SUSPEND`, and `SYSTEM_RESET2`, and its UAPI header lacks IDs for `STAT_RESIDENCY`, `STAT_COUNT`, and `NODE_HW_STATE`. That means Android firmware support for those optional calls is unknown, not proven absent, and there is no stock userspace/debugfs route to query them. The smallest exact test would be a diagnostic inside the kernel invoking `PSCI_FEATURES`; sources: [Android PSCI driver](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/firmware/psci/psci.c#L339-L420) and [Android PSCI UAPI IDs](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/include/uapi/linux/psci.h#L48-L60).

Paired passive qcom counter reads bracketed a successful `/system/bin/rtcwake -u -m mem -s 30 -d /dev/rtc0` while `mem_sleep` was `[s2idle] deep`. The same boot returned, Android remained `Asleep`/unplugged, and Linux suspend success advanced 6,051→6,068 (+17), exactly matching APSS count +17. AOSD advanced +323; CXSD and scalar DDR each +20; detailed DDR LPM `0xd4` and `0xd0` each advanced +20, while `0xd3` and `0x11` remained zero. APSS duration advanced +213,218,394 ticks (~11.105s at the validated 19.2-MHz scale); AOSD +203,544,016 (~10.601s); CXSD +205,320,437 (~10.694s); DDR +205,635,160 (~10.710s); `0xd4` +205,666,132 (~10.712s). `0xd0` advanced 165,941,100 ticks, within 364 ticks of the summed frequency-row delta (165,940,736), so it continues to behave as frequency accounting here. CPUSS L3 D4 count also advanced +17 and raw residency +213,315,433; its tick scale is not established. The counts clearly use different granularities, especially AOSD, and must not be treated as one-to-one suspend events. This adds controlled evidence that Android's selected s2idle interval advances the firmware AOSD/CXSD/DDR records; it still does not reveal which physical state each opaque bucket names or prove AOP accepted a specific request. No drain trend, parser read, QMP request, or persistent setting change occurred.

### 2026-09-18 22:34 UTC — root cannot select Android `deep` under current SELinux policy

Attempted a temporary `deep` selection by writing `/sys/power/mem_sleep` as UID 0 through Magisk, then intended to restore `s2idle` after a 30-second RTC wake. The sysfs write was denied before selection; a live follow-up still reads `[s2idle] deep`, on the same boot, with Android `Asleep` and unplugged. No test ran in `deep`, and no setting changed. The file is owned by root with mode `0644` and SELinux label `vendor_sysfs_suspend`; the Magisk root context is `u:r:magisk:s0`. A targeted Android-policy/source check is now in progress to see if a supported privileged service can select it without weakening SELinux or rebooting. Do not infer Android deep behavior from the successful s2idle test.

After the s2idle bracket, bounded reads of `/sys/kernel/debug/ipc_logging/aop/{log,log_cont}` returned no text. This did not produce an AOP sleep/vote trace or an acknowledgement; the existing AOP logging endpoint remains unhelpful for this question in its current runtime configuration. No logging control was written.

### 2026-09-18 22:43 UTC — exact Nova AOP image has a public 36-row CXPC sample

Rechecked the local 32-bit ARM AOP ELF at `/private/tmp/sm8550-aop-live.elf`: its SHA-256 is `6aceb38f5ef10663ac5c29ffc4e9ee27b6339e8746ff3490485f8cf2640ef687`, matching both Nova A/B AOP partitions recorded earlier. The public `qcom-aop-debug` sanitized raw sample for that hash begins at `0x0c320000` with header word `0x000024cc`: type `0xcc`/CXPC and `logsize=36`. Public OnePlus SM8550 `sys_pm_vx.c` corroborates the 8-byte header and 28-byte rows for 22 named driver bytes (timestamp plus packed votes). Thus 8 + 36×28 = 1,016 bytes, which fits Nova Android's separate `0x0c320000/0x400` sys-pm-vx mapping with only 8 bytes spare. The published capture was from AYN Thor/Retroid Pocket 6 work, not a Nova live capture; firmware hash identity makes its format highly relevant but does not prove every runtime `logsize` is capped at 36. The loaded vendor parser still lacks a resource bound, and the prior Nova read showed 27 entries with an empty mode. Do not treat a sample size as a hard cap; a source/firmware bound check is still pending before any further `sys_pm_violators` read. Sources: [raw CXPC header sample](https://github.com/jaewun/qcom-aop-debug/blob/89a19b70f554e17ddcf64c3e84037b6532202137/examples/sm8550-6aceb38f/cxpc-raw-head.txt), [sample provenance and scope](https://github.com/jaewun/qcom-aop-debug/blob/89a19b70f554e17ddcf64c3e84037b6532202137/examples/sm8550-6aceb38f/README.md), and [row parser](https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550/blob/c462ef8ffab7a58e035ee04705b16cdfced494b1/drivers/soc/qcom/sys_pm_vx.c#L1677-L1796). The matching ELF remains stripped and provides no DDR state-name table; `0xd4` stays an opaque LPM identifier.


### 2026-09-18 22:52 UTC — bounded deep-selection attempt returned; counters do not prove requested physical state

Computed deltas from the snapshots bracketing the one 30-second `rtcwake -m mem` attempt made while `[deep]` was selected (selection was then restored to `[s2idle]`). Linux suspend success/fail changed by +26/+8 and APSS count by +26. AOSD changed +606 counts / +882,473,360 ticks (~45.96 s at 19.2 MHz); CXSD +101 / +886,617,510 (~46.18 s); DDR +101 / +888,203,584 (~46.26 s); DDR `0xd4` +101 / +888,359,996 (~46.27 s). DDR `0xd3` and `0x11` remained zero. These bracket totals include the Android wake/reconnect and sampling period after the timed attempt, so they are not a 30-second deep-only interval. The rtcwake command session exited 255 when Wi-Fi ADB dropped, then the same boot returned; this is evidence of a suspend/disconnect/recovery cycle, not proof that the platform reached a particular AOP/CXPC or electrical low-power state.

DDR `0xd0` duration increased by 1,298,027,090 ticks (~67.606 s), within 942 ticks of the summed frequency-row increase (1,298,028,032 ticks, also ~67.606 s). This reinforces that `0xd0` tracks frequency accounting in this capture and should not be interpreted as low-power residency. The differing counter granularities (AOSD +606, CXSD/DDR +101, APSS +26) prevent mapping one counter increment to one suspend event. Device is again reachable on the same boot, Android reports `Asleep`, `mem_sleep` reads `[s2idle] deep`, and no further suspend attempt was started. No power/drain metric was taken.

### 2026-09-18 22:53 UTC — AOSS debug endpoint is a write-only control, not safe telemetry

Rooted Android exposes `/sys/kernel/debug/aoss_send_message`, but it is write-only (`--w--w----`). The matching upstream Qualcomm AOSS driver implements its debugfs operation as a QMP sender, not a readback function; its documentation warns that AOP debug commands can hold floor votes or prevent power collapse. This cannot answer whether CXPC/AOP accepted a sleep request through passive observation, and writing speculative requests would perturb the state under investigation. No command was written. The Android image has no generic `/sys/kernel/debug/qcom_stats`; it does expose the previously sampled `qcom_sleep_stats` and CPUSS statistics. The unbounded `sys_pm_violators` parser remains unsafe to reread, leaving no known safe userspace CXPC response interface. Source citation pending a final source-line cross-check.

### 2026-09-18 22:55 UTC — source confirms AOSS debugfs only sends QMP commands

Follow-up against the Nova-family Android source confirms `/sys/kernel/debug/aoss_send_message` is created mode `0220`; its `aoss_dbg_write()` copies text and calls `qmp_send()`, with no read callback: [matched qcom_aoss.c write handler](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/qcom_aoss.c#L2950-L2985), [debugfs mode/creation](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/qcom_aoss.c#L3077-L3083). The Qualcomm QMP debug-interface patch explicitly gives examples of commands that prevent power collapse or place floor votes: [patch rationale and handler](https://lkml.rescloud.iu.edu/2307.3/09394.html). Therefore it is a power-control input, not an observational channel, and remains untouched.

No safe passive CXPC/AOP blocker readback has been found on Nova. Readable qcom sleep-stat and CPUSS records are cumulative counters; AOP/AOSS IPC logs were empty in prior bounded reads; the visible CXPC `sys_pm_violators` file is backed by an unbounded parser and remains unread. RPMh/qcom_lpm tracepoints, if captured, can show Linux-side requests/governor decisions but cannot establish AOP acceptance or physical rail residency.

### 2026-09-18 22:56 UTC — counters prove firmware-recorded mode entries, not exact rails

Clarification from the Qualcomm sleep-stats binding and Nova-matched Android parser: AOP/RPM sleep-stat records maintain counters/timestamps/accumulated durations for SoC sleep modes associated with rail/XO power-down. Thus increasing AOSD/CXSD records are positive evidence that firmware recorded entries under those named mode buckets; that is stronger than inferring success from a PSCI call alone. It still does not identify the exact rail level/voltage at pins or prove which electrical state each firmware label represents. Sources: [Qualcomm qcom-stats binding](https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/soc/qcom/qcom-stats.yaml), [Nova-matched DDR mode-count clamp](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/subsystem_sleep_stats.c#L1648-L1660), [bounded DDR record loop](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/subsystem_sleep_stats.c#L1893-L1904), [DDR record-count validation](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/subsystem_sleep_stats.c#L2509-L2517). The exposed `ddr_stats` reader is bounded by a probe-time maximum (`0x14`) and firmware `ddr_entry_count`; this makes that file safe to read, but the printed LPM IDs remain raw/unmapped. This bounded interface is separate from the unsafe `sys_pm_violators` parser.

### 2026-09-18 23:09 UTC — first passive LPM/RPMh trace proves request traffic, but the ring lost suspend phases

On the same rooted Android boot, `mem_sleep` was `[s2idle] deep` before and after. A detached trace job wrapped `/system/bin/rtcwake -u -m mem -s 12 -d /dev/rtc0`; it returned `rtcwake_rc=0`, boot ID stayed `45c48211-b345-477c-b1bb-ef163dce7b73`, and a 60-second watchdog plus normal cleanup restored `tracing_on=0`, all selected events disabled, the original 1-KiB buffer, and `[s2idle]`. Wi-Fi ADB/root recovered without user action.

The trace recorded 329 `qcom_lpm:lpm_gov_select` decisions at state index 0 and 14 at index 1; live CPU idle names are index 0 `WFI` and index 1 `silver-c4`, so these are governor selections, not proof each selected core state executed. It recorded 35 RPMh `send_msg` events and 10 `tx_done` acknowledgements, showing Linux/RPMh request and completion traffic but not AOP low-power acceptance. `power:suspend_resume` retained only `sync_filesystems end` and `freeze_processes begin`. The trace header reports 734 events in buffer versus 2,356 written, so this 1-KiB-per-CPU capture overran and cannot establish whether later suspend phases completed.

Paired firmware counter reads across the short wrapper window changed APSS +1 / +15,595,993 ticks (~0.812 s), AOSD +23 / +15,082,528 (~0.785 s), CXSD +1 / +15,202,283 (~0.792 s), DDR +1 / +15,218,011 (~0.793 s), and DDR `0xd4` +1 / +15,218,557 (~0.793 s). DDR `0xd0` advanced +8,374,596 ticks; the frequency rows summed to +8,374,784 (188 ticks apart), again matching frequency accounting. This is not evidence of 12 seconds in those buckets; the trace/counters cover background s2idle attempts too.

At the later live check the device was still online, same boot, and `[s2idle]`. Kernel logs showed repeated `PM: suspend entry (s2idle)` attempts with `Wakeup pending` / `Abort` and active `timerfd` sources; some also report `eventpoll`. `/sys/power/suspend_stats` then showed success 7,715, fail 88, most recent failure `3da0000.kgsl-smmu`, errno `-115`, step `prepare`. A read-only `/proc/*/fdinfo` scan found future timerfds in `system_server`, `android.hardware.health-service.qti`, and GNSS, plus 3-second/5-second periodic timerfds in service managers; it did not map any specific fd to the `timerfd` wakeup source. These observations identify repeated AP-side abort/prepare activity to investigate, but do not prove the timerfd/GPU failures explain battery drain.

### 2026-09-18 23:12 UTC — larger trace captures timerfd churn immediately before an EBUSY suspend attempt

Ran a second detached trace with a 64-KiB-per-CPU buffer and `power:wakeup_source_activate/deactivate`, `power:suspend_resume`, nonzero device-PM callback ends, `qcom_lpm:lpm_gov_select`, and RPMh send/ack events. The 60-second watchdog again restored all events off, tracing off, the original 1-KiB buffer, and `[s2idle]`; same boot and Wi-Fi ADB/root remained available. The trace was complete for its 137 recorded events (`137/137`, no buffer overwrite).

The explicit `rtcwake -u -m mem -s 12 -d /dev/rtc0` now returned `rtcwake: xwrite: Device or resource busy` (`rc=1`), so this attempt did not complete. Immediately before a `suspend_resume: suspend_enter[1] begin`, the trace records repeated `[timerfd]` and `eventpoll` wakeup-source activate/deactivate events within about 1.5 ms. No matching `suspend_enter end` was captured. `suspend_stats` success/fail rose 7,998/89 to 7,999/90 in the one-second bracket; the stored last-failure tuple remained `3da0000.kgsl-smmu`, `-16`, `freeze`. Thus the runtime is making system-suspend attempts while timerfd/eventpoll activity is present, and at least one request returned `EBUSY`; do not treat the RTC return code or the nearby `suspend_enter begin` as proof of a completed 12-second sleep.

The same bracket's firmware counters changed APSS +1 / +17,368,125 ticks (~0.9046 s), AOSD +26 / +16,838,128 (~0.8770 s), CXSD +1 / +16,974,933 (~0.8841 s), DDR +1 / +16,990,314 (~0.8849 s), and `0xd4` +1 / +16,991,862 (~0.8850 s). `0xd0` duration grew 85,683,404 ticks while frequency rows grew 85,683,200 (204 apart), again matching frequency accounting. These remain short mixed-window firmware counters, not a full RTC sleep duration or a decoded rail state. Trace recorded 89 state-0 and 5 state-1 qcom_lpm selections, 23 RPMh sends and 7 `tx_done` acknowledgements; there were no nonzero device-PM callback-end records and no solver-set records. Requests/acks still do not expose an AOP acceptance decision.

### 2026-09-18 23:13 UTC — traced wakeup sources are threads inside Android system_server

Mapped the task IDs from the complete trace through `/proc/<tid>/status` and `ps -AT`: TID 2142 (`android.fg`) and TID 2389 (`AlarmManager`) both have TGID 2123 (`system_server`). The `[timerfd]` activation was attributed to `android.fg`; the adjacent `eventpoll` activity came from `AlarmManager`. This narrows the visible wakeup activity to Android's system-server alarm/event loop, but does not identify the specific alarm, callback, or timerfd file descriptor responsible. No process or alarm state was changed.

The complete 64-KiB-buffer trace and paired counter snapshots are preserved under `research/sm8550-suspend-lab/receipts/2026-09-18-rooted-lpm-trace/` (`trace.txt`, `counters-before.txt`, `counters-after.txt`, and `rtcwake-output.txt`). The file is intentionally retained despite the RTC command's `EBUSY` result because the wakeup-source ordering and failed attempt are useful evidence.

### 2026-09-18 23:14 UTC — Android AlarmManager had no scheduled wake alarm near the trace attempt

Read-only `dumpsys alarm` reported its next `ELAPSED_WAKEUP` alarm from `com.google.android.gms` about 4m08s in the future, with the next network-stack wakeup several minutes later. That is not a scheduled app wakeup inside the 12-second RTC window. This narrows the trace's rapid system_server `timerfd`/`eventpoll` events to internal service timing or another source, but does not identify a specific fd/callback or rule out non-AlarmManager kernel wake causes. No alarm schedule or app state was changed.

### 2026-09-18 23:15 UTC — source audit corrects `[timerfd]` label and raises a competing-suspend explanation

Correction to the preceding task attribution: Linux `eventpoll` creates an `EPOLLWAKEUP` source named from the watched file's dentry, so `[timerfd]` is likely the name of an epoll-watched timerfd file, not proof that its timer expired or that it owns the wake lock. `eventpoll` is a separate epoll-instance source; the trace task PID is the callback context, not necessarily the logical timer owner. Matched source: [eventpoll wake-source creation/callback/delivery](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/fs/eventpoll.c#L597-L605), [timerfd only signals its wait queue](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/fs/timerfd.c#L63-L89).

A stronger explanation for the unmatched `suspend_enter[1] begin` plus `rtcwake` `EBUSY` is contention with Android's concurrent autosuspend: matched `kernel/power/suspend.c` emits that trace at the start of `enter_state()`, then `mutex_trylock(&system_transition_mutex)` can fail and return `-EBUSY` before freezer preparation, with no matching end event. Source: [enter_state transition lock and trace](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/kernel/power/suspend.c#L561-L600), [failure accounting](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/kernel/power/suspend.c#L625-L635). This is consistent with the trace but not yet proven: per-stage `failed_freeze`/`failed_prepare` deltas were not captured around the RTC attempt, and a freeze failure can also return before a matching trace end. Next discriminator is a short before/after read of those stage counters around one attempt; do not infer causation from the wakeup-source name or task comm alone.

### 2026-09-18 23:20 UTC — Wi-Fi/root access remains intact; cumulative stats show multiple failure stages

After the user removed USB, Wi-Fi ADB remained reachable on `192.168.0.163:5555`; the boot ID was still `45c48211-b345-477c-b1bb-ef163dce7b73`, Magisk `su` returned UID 0, `mem_sleep` remained `[s2idle] deep`, and tracing remained off. A fresh read-only `suspend_stats` snapshot showed success 8,496 / fail 92, with `failed_freeze=31`, `failed_prepare=5`, `failed_suspend=45`, `failed_suspend_late=2`, and `failed_suspend_noirq=0`. The two stored failure tuples were `alarmtimer.0.auto`, `-16`, `freeze` and `3da0000.kgsl-smmu`, `-16`, `suspend`. These are an unbracketed cumulative snapshot, not attributable to the prior explicit RTC attempt; they show that both freeze-stage and suspend-stage failures occur in the Android runtime, so a per-attempt bracket is still needed to distinguish the latest `EBUSY` path. No sleep, reboot, mode change, or trace configuration change was initiated. (Use `adb shell "su -c '...'"` to preserve quoting across the adb shell boundary; the prior compound command's trailing `id` ran outside `su`, but subsequent direct verification confirmed root.)

### 2026-09-18 23:22 UTC — passive interval shows Android suspend attempts continue without a manual sleep

Read-only tracepoint format and counter checks confirmed that `power:suspend_resume` and wakeup-source events are available, and that the per-stage files `/sys/power/suspend_stats/{failed_freeze,failed_prepare,failed_suspend}` can be sampled directly. Between the prior 23:20 snapshot and this check, counters moved from success/fail 8,496/92 to 8,618/96; `failed_freeze` rose 31 to 33 and `failed_suspend` 45 to 47. Both latest stored failures now name `alarmtimer.0.auto` with errno `-16`, at steps `suspend` and `freeze`. This is evidence that Android continues attempting and failing suspend paths while we only perform light reads; it is not proof of a specific transition's cause, and the bracket did not include trace events. Root, same boot, `[s2idle]`, and tracing-off state remain intact.

### 2026-09-18 23:28 UTC — sleep-stat drivers are loadable modules on the live Android boot

Read-only inspection over the still-live Wi-Fi ADB link confirms the Nova kernel is `5.15.123-android13-8-g697b78910a71-dirty` (built with Android clang 14). Both `soc_sleep_stats` and `subsystem_sleep_stats` appear in `/proc/modules`, so the diagnostic reader is not built into the kernel. The dependency chain is `soc_sleep_stats` → `subsystem_sleep_stats` → `sys_pm_vx`; replacing the middle module may therefore require unloading/reloading its `sys_pm_vx` consumer in reverse order, which must be checked before any live deployment. The device is rooted; slot `_a`, boot state `orange`, flash unlocked, SELinux permissive. These properties do not by themselves establish a safe recovery path. The same boot remains on Wi-Fi ADB, `[s2idle]` is selected, and tracing is off. No modules were unloaded, files replaced, or boot controls changed. This materially improves feasibility: a matching diagnostic `.ko` may be tested without a full kernel rebuild or reboot if the exact build tree, ABI, module signature policy, and reload dependencies check out.


### 2026-09-18 23:41 UTC — module build is feasible, but the public source does not match the live release hash

Captured the three stock Android modules (`soc_sleep_stats.ko`, `subsystem_sleep_stats.ko`, `sys_pm_vx.ko`), `modules.load`, `modules.dep`, and `/proc/config.gz` to the external case-sensitive APFS build volume at `/Volumes/NovaKernelBuild/stock-modules/`. The live config confirms `CONFIG_MODVERSIONS=y`, `CONFIG_MODULE_UNLOAD=y`, `CONFIG_MODULE_SIG_FORCE` unset, and `CONFIG_MODULE_SIG_ALL=y`; `/proc/sys/kernel/modules_disabled` is `0`. Therefore no forced signature is apparent, but module CRC compatibility is a hard gate. The module dependency file confirms reverse-unload order `sys_pm_vx` → `subsystem_sleep_stats` → `soc_sleep_stats`; originals are preserved before any contemplated swap.

The live kernel release ends in `g697b78910a71-dirty`; that hash is not present in the public AYN kernel repository. Its `lineage-23.2` HEAD is `93c5cc6ad1d0b807510cfa0fb1d06f47407881f9`, matching the source previously used to understand the driver, but it is not yet proven to be the source/build tree for the running Android module. The source confirms two configuration-selected `readl_relaxed()` words feed the sleep-stats and DDR mapped bases; the minimal diagnostic is to log those exact return values once in probe, without extra MMIO reads. The local Armada package builds Linux 7.2.3, not this Android 5.15.123 tree. A 50-GB case-sensitive APFS sparsebundle is mounted on the external FAT32 drive (90 GB free); Docker's Linux/amd64 emulation and bind mount to it were smoke-tested. No Android module, boot, or tracing state was changed.

### 2026-09-18 23:54 UTC — temporary MMIO-read trace did not expose the sleep-stat probe words

The stock Android boot already exposes the `rwmmio:rwmmio_post_read` tracepoint, which logs `readl_relaxed()` caller, width, value, and address. Its `enable` file is read-only by default. For one bounded capture, root temporarily changed only that file's mode to `666`, enabled the event with a 64-KiB trace buffer, read the existing `qcom_sleep_stats/{aosd,cxsd,ddr}` files, then disabled tracing, restored the buffer to 1 KiB, restored the file mode to `644`, and verified tracing remained off. The capture contained 788 MMIO reads, but none had `soc_sleep_stats`, `subsystem_sleep_stats`, or `qcom_sleep_stats` as the caller. Aggregate debugfs reads therefore do not expose the two base-address words read by `soc_sleep_stats_probe()` through this path. No module was reloaded, no kernel/boot state changed, and Wi-Fi ADB/root stayed available.

This closes the safe no-build trace attempt. Capturing the probe's exact words now requires either a diagnostic module built against the exact vendor kernel ABI or a controlled unload/reload of the stock module with the existing tracepoint enabled. A reload is not yet justified: the module chain is referenced by `smem` and related consumers, the live release hash is not matched by the public source tree, and unloading `sys_pm_vx`/`subsystem_sleep_stats` could temporarily remove power diagnostics. Current device state after the probe remains boot `45c48211-b345-477c-b1bb-ef163dce7b73`, `[s2idle]`, tracing off, 1-KiB buffer, and all three sleep-stat modules loaded.

### 2026-09-18 23:55 UTC — module dependency check leaves a reversible reload path, but no external holder

Read-only `/proc/modules`, `/sys/module/*/holders`, and `modules.dep` agree on the chain: `sys_pm_vx` has use count 0; `subsystem_sleep_stats` is held by `sys_pm_vx`; `soc_sleep_stats` is held by `subsystem_sleep_stats`. The vendor dependency file lists `sys_pm_vx -> subsystem_sleep_stats -> soc_sleep_stats`, and `rmmod`, `insmod`, and `modprobe` are available. No separate module holder was found. This makes a short reverse-order stock-module unload/reload technically reversible, but it remains a live power-diagnostics mutation. Any attempt must enable the MMIO trace first, unload only `sys_pm_vx`, `subsystem_sleep_stats`, `soc_sleep_stats`, reload the untouched vendor copies in forward order, then verify all debugfs files and counters; no force options or reboot should be used.

### 2026-09-19 00:07 UTC — kprobe captured the live firmware-selected sleep-stat bases

The no-build diagnostic is now resolved. The live kernel has `CONFIG_KPROBES=y` and `CONFIG_KPROBE_EVENTS=y`. A temporary entry kprobe was placed at the stock module's `soc_sleep_stats:readl_relaxed+0x58`, immediately after the wrapper copies the MMIO result into `w0`; it recorded `%x0` without changing the module. The platform device `c3f0000.soc-sleep-stats` was temporarily unbound and rebound through its sysfs driver controls (their modes were widened only for the operation), causing the existing probe to run again. The kprobe was then removed, tracing was disabled, and all permissions/buffer state were restored.

The 26 captured return values, in order, were:

`0xf0048, 0xf00b8, 0x13, 0xd4, 0xd3, 0x11, 0xd0, 0xc80101, 0x2230102, 0x3000103, 0x6130104, 0x6ac0105, 0x82c0106, 0xab00107, 0xc730108, 0xe660109, 0x1080010a, 0x20b, 0x20c, 0x20d, 0x20e, 0x20f, 0x64736f61, 0x64737863, 0x20726464, 0xa1157a75`.

The live DT node is `/sys/firmware/devicetree/base/soc/soc-sleep-stats@c3f0000`, compatible `qcom,rpmh-sleep-stats`, resource start `0x0c3f0000`, size `0x400`. Matching the public driver source, the first read is `res->start + 0x4` and the second is `res->start + 0x1c`; therefore the firmware-selected bases are:

* `stats_base = 0x0c3f0000 | 0x000f0048 = 0x0c3f0048`;
* `ddr_reg = 0x0c3f0000 | 0x000f00b8 = 0x0c3f00b8`.

The later `0x64736f61`, `0x64737863`, and `0x20726464` values are the decoded `aosd`, `cxsd`, and `ddr` record names; `0xa1157a75` is the DDR magic key. This proves the running Android module is using firmware-provided in-resource offsets and that the public aggregate debugfs values are decoded from those mapped records. It does not, by itself, map the record IDs to physical rail voltages or prove a particular suspend rail state. The device remained on the same boot ID with all modules loaded, `qcom_sleep_stats` restored, `[s2idle]` selected, tracing off, 1-KiB buffer, and Wi-Fi ADB/root intact. No kernel file, boot image, or persistent configuration was changed.

### 2026-09-19 00:10 UTC — the firmware offsets match Armada's fixed low offsets

The captured words resolve the apparent Android-versus-Armada offset question. The firmware values are `0x000f0048` and `0x000f00b8`; the driver ORs them with the `0x0c3f0000` resource base, so only the low offset bits select the records. Their low portions are exactly `0x48` and `0xb8`, matching the Armada/mainline `qcom_stats` constants previously audited. The `0xf0000` portion is part of the firmware-provided address word and is absorbed by the OR operation; it is not evidence that Armada is reading a different record layout. This rules out an offset mismatch as the explanation for opaque AOSD/CXSD/DDR values. The remaining opacity is semantic: the records expose firmware counters and mode IDs, not a public AOP/CXPC rail-state or acceptance field.

### 2026-09-19 00:10 UTC — post-probe safety verification

After the kprobe/unbind/rebind work: boot ID is still `45c48211-b345-477c-b1bb-ef163dce7b73`; `kptr_restrict=2`; `mem_sleep=[s2idle] deep`; tracing is `0`; trace buffer is `1`; `kprobe_events` is empty; `rwmmio_post_read` is disabled with mode `644`; the platform device is bound; all three stock sleep-stat modules are loaded with the original dependency chain; and `qcom_sleep_stats` exposes `adsp`, `adsp_island`, `aosd`, `apss`, `cdsp`, `cxsd`, `ddr`, `ddr_stats`, and `modem`. No persistent control or security setting remains changed.

### 2026-09-19 00:11 UTC — passive decoded-counter interval separates common and deep firmware entries

A read-only snapshot of `qcom_sleep_stats/{aosd,cxsd,ddr,apss}` was saved as `receipts/2026-09-19-sleep-stats-after-kprobe.txt`; `ddr_stats` was intentionally not read because it triggers the driver's active QMP `freqsync` path. Over a roughly two-second awake interval, counts changed AOSD `213056 -> 213291` (+235), CXSD `14722 -> 14740` (+18), DDR `14730 -> 14748` (+18), and APSS `12911 -> 12924` (+13). This shows the firmware counters are live residency-entry counters with different frequencies: AOSD is a common idle path, while CXSD and DDR collapse entries are much rarer. It is useful evidence that the hardware reaches CXSD/DDR modes during normal runtime, but it is not a system-suspend acceptance trace and does not decode the underlying AOP/CXPC rail vote.

### 2026-09-19 00:12 UTC — qcom_lpm trace maps the CPU idle choices and fallback reason

A one-second passive `qcom_lpm:lpm_gov_select` trace was captured and saved as `/private/tmp/nova-qcom-lpm-1s.txt`; the event was disabled and its mode/buffer restored. It recorded 734 selections: state 0 (`WFI`) 702 times and state 1 (`silver-c4`) 32 times. The dominant reason was `0x20` (612 events). In the public `qcom-lpm.c`, `UPDATE_REASON(i, LPM_SELECT_STATE_SCHED_BIAS)` is `BIT(5) << (8 * i)`, so `0x20` means scheduler-bias forced the governor back to the shallow WFI state. State 1 selections had mostly `reason=0`, meaning the CPU governor accepted the deeper `silver-c4` state when its residency prediction allowed it. This is a CPU-idle governor result, not proof of system-level AOP/CXPC rail collapse, but it gives a concrete software-side explanation for many shallow entries seen alongside the AOSD counter.

### 2026-09-19 00:13 UTC — cluster PM domain trace identifies the requested deep state

A one-second passive trace of `cluster_lpm/{cluster_enter,cluster_exit,cluster_pred_select}` recorded paired `cluster_enter`/`cluster_exit` events with `idx=1` and `suspend_param=0x4100c344`. The live DT maps `/soc/psci/cluster-pd/domain-idle-states` to phandles `0x21` and `0x22`; `0x21` is `cluster-d4` (`l3-off`, PSCI param `0x41000044`) and `0x22` is `cluster-e3` (`llcc-off`, PSCI param `0x4100c344`). Thus the observed `idx=1` events are real cluster power-domain off/on transitions into the `llcc-off` state, not only governor predictions. Public `qcom-cluster-lpm.c` emits `cluster_enter` on `GENPD_NOTIFY_OFF` and `cluster_exit` on `GENPD_NOTIFY_ON`, so a pair confirms a successful domain transition and return. This is the strongest available Linux-side evidence that the hardware reaches a CX/LLCC-off class state; it still does not expose the AOP's internal rail vote or an AOP acceptance code.

### 2026-09-19 00:14 UTC — cluster domain residency is observable without suspend tests

The live `pm_genpd` snapshot saved as `receipts/2026-09-19-cluster-pd-after-trace.txt` reports cluster-pd S0 `9708 ms / 2131 uses / 657 rejected` and S1 `6168 ms / 3047 uses / 2665 rejected`; `current_state` is `on` while the device is awake. DT mapping identifies S0 as `l3-off` (`0x41000044`) and S1 as `llcc-off` (`0x4100c344`). This supplies a persistent software-side residency/rejection count for the CX/LLCC domain and a way to quantify policy rejection without measuring battery drain. The high S1 rejection count is a concrete follow-up target for the cluster governor and power-domain policy, while the paired trace events prove that accepted S1 transitions do occur.

### 2026-09-19 00:15 UTC — cluster callback sample showed no NOTIFY_BAD returns

A temporary kretprobe on `qcom_lpm:cluster_power_cb` ran for one second while cluster policy remained unchanged. The entry probe's fetch-argument form was rejected by this kernel, but the return probe recorded two callback returns, both `ret=0x1` (`NOTIFY_OK`); no `NOTIFY_BAD` (`0x8002`) return appeared in that bracket. The return probe was disabled and removed; tracing is off and `kprobe_events` is empty. This is only a small awake sample, so it does not explain the cumulative S1 rejection count, but it rules out a continuously failing callback in that interval. The earlier cluster-pd rejection counter remains an aggregate policy metric rather than a direct AOP failure count.

### 2026-09-19 00:17 UTC — no AOSS QMP messages in a passive awake bracket

A temporary kprobe on the exported `qcom_aoss:qmp_send` function was registered with pointer/length fields only (string fetch was rejected by the Android shell parser), enabled for one second, then removed. The trace contained zero `qmp_send` calls while the device was awake and idle; tracing/buffer state and `kprobe_events` were restored. This is a negative observation, not proof that AOSS is inactive during a real transition: the one-second bracket did not force a power-domain change, and the existing AOSS IPC log files are streaming debugfs readers that can block. No AOSS message was sent.

### 2026-09-19 00:18 UTC — diagnostic receipts copied into the lab

The key raw traces are preserved under `receipts/`: `2026-09-19-soc-sleep-kprobe-entry.txt` (mapped read addresses), `2026-09-19-soc-sleep-kprobe-values.txt` (the 26 return values including `0xf0048`/`0xf00b8`), `2026-09-19-cluster-lpm-1s.txt` (accepted `llcc-off` enter/exit pairs), `2026-09-19-cluster-callback-1s.txt` (callback return sample), `2026-09-19-aoss-qmp-1s.txt` (negative awake-bracket sample), `2026-09-19-sleep-stats-after-kprobe.txt`, and `2026-09-19-cluster-pd-after-trace.txt`. These are research artifacts alongside this notebook; the device itself has no persistent lab files or instrumentation left enabled.

### 2026-09-19 00:24 UTC — corrected explicit-suspend bracket still fails before entering sleep

A second bounded attempt used a separately quoted watchdog and `rtcwake -u -m mem -s 5 -d /dev/rtc0`. The command returned `rc=1` with `rtcwake: xwrite: Device or resource busy`; the trace contains zero `power:suspend_resume`, `cluster_enter`, and `cluster_exit` records. Therefore this was another pre-entry failure, not a five-second sleep. The receipt is `receipts/2026-09-19-real-suspend/` (`pre.txt`, `rtcwake.txt`, `trace.txt`, `post.txt`, `state.txt`).

The device stayed on boot `45c48211-b345-477c-b1bb-ef163dce7b73`, `[s2idle]`, and Wi-Fi ADB remained available. The watchdog disabled tracing and restored the event enables; the final state was tracing off, 1-KiB buffer, no kprobes, and all three stock sleep-stat modules loaded. The cumulative suspend counters advanced independently in the background (`success=12961`, `fail=162`, `failed_freeze=75`, `failed_suspend=69`, latest `alarmtimer.0.auto`, `-16`, `freeze`), so those totals cannot be attributed to this failed bracket. `wakeup_sources` shows active Android/Wi-Fi-related sources such as `gh_vcpu_ws_45_{0,1}`, `qcom_rx_wakelock`, and `peer_set_key`, but none of this proves which holder caused the particular `EBUSY`; the direct errno is the only bounded result. No persistent setting, module, boot image, or power mode changed.

### 2026-09-19 01:21 UTC — Android system-suspend force path reaches deep and brackets firmware counters

The previous `rtcwake -m mem` failures were caused by competing with Android's `system_suspend` service, which owns the `/sys/power/wakeup_count` and `/sys/power/state` protocol. The rooted service `suspend_control_internal` exposes transaction 2 as `forceSuspend()`. Calling `service call suspend_control_internal 2` returned `true`; unlike a direct sysfs write, this path intentionally ignores held wakelocks while using the service's own state file. The internal service also provides `dumpsys suspend_control_internal --wakelocks`, `--wakeups`, and `--suspend_controls`; the live wakeup history identifies repeated `[timerfd]`, `qcom_rx_wakelock`, and `alarmtimer.0.auto` aborts. Android's AIDL definition documents `forceSuspend()` as the method that suspends even with wakelocks (`ISuspendControlServiceInternal.aidl`, lines 32–45: https://android.googlesource.com/platform/system/hardware/interfaces/+/2cd804b95d55b492457f0be461b3179fd49f74f1/suspend/aidl/android/system/suspend/internal/ISuspendControlServiceInternal.aidl).

For a bounded test, `mem_sleep` was changed from `[s2idle] deep` to `s2idle [deep]`, a four-second PMIC RTC alarm was armed, and `forceSuspend()` was called. The trace shows a complete system path: `suspend_enter`, process freeze, all CPUs off, `syscore_suspend`, `machine_suspend[3]`, then a 4.406-second interval until `cluster_lpm:cluster_exit` and `syscore_resume`, followed by CPU bring-up and thaw. The cluster event is `idx=1`, PSCI parameter `0x4100c344`, the previously mapped `llcc-off` state. This is the first authoritative explicit deep-suspend interval, rather than a passive idle inference.

The receipt is `receipts/2026-09-19-deep-stats/`. Firmware counters bracketed around that run changed as follows: AOSD `282549 -> 282707` (+158), CXSD `19192 -> 19203` (+11), DDR `19201 -> 19212` (+11), and APSS `16421 -> 16423` (+2). Accumulated durations increased AOSD by `98,087,584`, CXSD by `98,960,406`, DDR by `99,137,510`, and APSS by `103,469,263` in the driver's counter units. Two additional background suspend attempts changed the cumulative kernel stats (`success 14579 -> 14581`, `fail 195 -> 198`), so those totals are not used to infer the deep interval; the trace and paired firmware counter changes are the bounded evidence. `mem_sleep` was restored to `[s2idle]`, trace events were disabled, buffer size restored to 1 KiB, kprobes remained empty, and the original boot ID stayed unchanged.

### 2026-09-19 01:36 UTC — source audit explains the Armada versus Android mode boundary

The final live Android read is clean: boot `45c48211-b345-477c-b1bb-ef163dce7b73`, `mem_sleep=[s2idle] deep`, tracing disabled, 1-KiB trace buffer, no kprobes, and all five diagnostic event controls at `0`. `dumpsys suspend_control_internal` still attributes the direct-sysfs failures to the Android controller's normal suspend loop: 15,084 attempts, 201 failed suspends, 14,860 `Pending Wakeup Sources: [timerfd]` aborts, 100 `qcom_rx_wakelock` aborts, 39 `alarmtimer.0.auto` callbacks returning `-16`, 21 `NETLINK` aborts, and seven `kgsl-smmu` prepare failures. The active native wakelock at the sample was `qms_event_Handler_wakeLock_` from `/vendor/bin/qms`, with `qcom_rx_wakelock` also active. This is the bounded explanation for `rtcwake` returning `EBUSY`: it writes into a state machine already owned by Android `system_suspend`, while the service is repeatedly aborting or retrying around live wakeup sources and suspend callbacks. `forceSuspend()` is the supported diagnostic route because it uses the service's own protocol and deliberately ignores held wakelocks.

The Armada source audit finds a separate policy boundary. Armada's current `device-env`, `device-quirks`, and `suspend-dispatch` accept only `fake` and `s2idle`; an old `suspend_mode=deep` is rewritten to `s2idle`, and the default profile is `ARMADA_SUSPEND_MODE=s2idle`. This comes from commit `47ecdee` (`feat(sleep): default every device to native s2idle`, merged PR #370). Therefore the Android proof that the SM8550 hardware and firmware can complete a selected `deep` interval does not mean the current Armada image can ever request that state: userspace deliberately prevents it.

The Armada 7.2.3 kernel tree does contain a Nova DT (`kernel/dts/qcs8550-retroidpocket-rpnova.dts`, inheriting the RP6 SM8550 base) and a deep-suspend preparation stack. The patch series includes IPCC summary-IRQ masking for suspend-to-RAM (`0504`), TSENS lower-threshold IRQ masking (`0204`), the PCIe suspend OPP memory floor (`0513` plus `0520`), and the Nova/RP6 PCIe nodes are enabled in the common DTS. Those patches address known suspend-to-RAM transition hazards; they do not prove this exact image has been built, booted, or validated on Nova. No kernel build or device flash was performed.

Conclusion: the opaque AOP question is now bounded as far as the available interfaces permit. The Android `deep` run produced a complete kernel suspend trace with a four-second `cluster_lpm` `llcc-off` interval and paired AOSD/CXSD/DDR count and duration changes. The counters prove firmware-recorded mode entries, but public interfaces do not expose a rail voltage or an AOP acceptance bit. The remaining implementation question is Armada-specific: whether its 7.2.3 Nova image can safely re-enable `deep` behind a device-scoped diagnostic choice, using the existing kernel patch stack. Re-enabling it globally without a built-image test would be an unvalidated policy change, not a missing observation.

### 2026-09-19 01:34 UTC — live Android metadata confirms the pointer-word result

Re-read the rooted Android boot without changing it. The running build is `5.15.123-android13-8-g697b78910a71-dirty`, fingerprint `qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys`, device `kalama`, slot `_a`. The bound platform node is `c3f0000.soc-sleep-stats`, its driver is `/sys/bus/platform/drivers/soc_sleep_stats`, and its DT compatible is `qcom,rpmh-sleep-stats`. The DT `reg` property is `0c 3f 00 00 00 00 04 00`, which decodes to resource start `0x0c3f0000`, size `0x400`, and inclusive end `0x0c3f03ff`.

The reader is modular, not built in: `soc_sleep_stats`, `subsystem_sleep_stats`, and `sys_pm_vx` are present in `/proc/modules` and `/sys/module`. Their live holders are `soc_sleep_stats <- subsystem_sleep_stats <- sys_pm_vx`; the module files are in `/vendor_dlkm/lib/modules/`. The embedded vermagic for all three is `5.15.123-g697b78910a71-dirty SMP preempt mod_unload modversions aarch64`. The stock module hashes captured from that path are `soc_sleep_stats.ko` `b7a72e68683fa64f46003f04556ab95ad41fc77a5b5d1eb0fb1296df6c7da22a`, `subsystem_sleep_stats.ko` `92c69e7b5181abca9998cd76d4401cdd56e3cb4304151d3198eb0bb27a9cad85`, and `sys_pm_vx.ko` `60783c435d0ac12b778579541b8c717b222406d4e0d43698c3fd7fece8870d57`. Strings in the exact stock objects identify the vendor source path `/home/liuwen/q9ex/VENDOR.13.2.6/kernel_platform/msm-kernel/drivers/soc/qcom/soc_sleep_stats.c`. No module was unloaded, replaced, or rebuilt in this refresh.

The existing no-build kprobe receipt `receipts/2026-09-19-soc-sleep-kprobe-values.txt` captures the stock probe's own `readl_relaxed()` returns. The first two values, corresponding to the downstream `resource_start + 0x4` and `resource_start + 0x1c` pointer words, are `0x000f0048` and `0x000f00b8`. The subsequent normal-driver reads include the decoded signatures `0x64736f61` (`aosd`), `0x64737863` (`cxsd`), `0x20726464` (`ddr`), and DDR magic `0xa1157a75`, so this is the stock mapping path rather than guessed MMIO.

Normalizing the downstream expression `resource_start | raw_value` gives:

* SoC stats base: `0x0c3f0000 | 0x000f0048 = 0x0c3f0048`, normalized offset `0x48`.
* DDR stats base: `0x0c3f0000 | 0x000f00b8 = 0x0c3f00b8`, normalized offset `0xb8`.

This is outcome A from the experiment: Android's firmware-selected offsets resolve exactly to mainline/Armada's fixed `+0x48` and `+0xb8`. The zero Armada AOSD/CXSD/scalar-DDR counters are therefore not explained by a wrong stats base. Do not change Armada's `qcom_stats` offsets. The next experiment must target a real Linux-versus-Android firmware/PM request or record-semantics difference, not an address remap.

### 2026-09-19 13:11 UTC — public Android and Linux record layouts also match

Compared the public downstream `soc_sleep_stats.c` at the Android source revision used for the pointer audit with Armada's Linux v7.2 `qcom_stats.c`. Both define each SoC record as `u32 stat_type`, `u32 count`, and three `u64` timestamps/duration fields, giving a 0x20-byte record on arm64. Android places RPMh record `i` at `stats_base + i * sizeof(struct sleep_stats)` with `STAT_TYPE_ADDR=0` and no appended-vote area; mainline's RPMh path uses the same 0x20-byte stride from its `+0x48` stats base. Both use the same field order and read/copy the complete record before printing count and accumulated duration. Their detailed DDR table begins at the separately selected `+0xb8` base and starts with the same magic key.

This makes a simple stats-record stride or field-layout mismatch unlikely in addition to ruling out the base-offset mismatch. The public Android source is not proven byte-for-byte identical to the loaded dirty vendor module, but the stock module's live kprobe already confirmed that its mapping path reads the expected AOSD/CXSD/DDR signatures and DDR magic. Sources: [Android downstream reader](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/soc_sleep_stats.c) and [Linux v7.2 reader](https://github.com/torvalds/linux/blob/v7.2/drivers/soc/qcom/qcom_stats.c).

Next diagnostic should focus on the PM request path and firmware response, not rebuild or alter the stats reader: compare the already successful Android `forceSuspend()` deep path with Armada's successful PSCI deep path, especially the power-state/RPMh inputs presented to firmware. Existing Linux traces show PSCI success and cluster `llcc-off`, while the SoC counters remain unchanged; Android's paired deep bracket advances them. Avoid another identical suspend run unless it captures a missing request/response detail. Do not read the unbounded `sys_pm_violators` export or guessed AOP memory as a substitute for an authoritative acceptance interface.

### 2026-09-19 13:17 UTC — `sys_pm_vx` is diagnostic, not the suspend request path

Reviewed the public Kalama `sys_pm_vx.c` implementation. Its optional `lpm_mon`/`cxpc` mailbox message is issued only to collect a blocker report when the diagnostic is enabled; the driver defaults `debug_enable` and `monitor_enable` to false, and its suspend/resume callbacks do not choose or request a power state. This rules it out as the Android mechanism that makes the SoC enter deeper modes. On the current Android boot (`45c48211-b345-477c-b1bb-ef163dce7b73`), `sys_pm_vx` is loaded but `/sys/bus/platform/devices/c320000.sys-pm-vx` has no bound-driver link, its sysfs debug attributes are absent, and `/sys/kernel/debug/sys_pm_violators` is absent. Tracing remains off (`tracing_on=0`, `current_tracer=nop`, empty `kprobe_events`). No settings were changed and the unbounded debugfs reader was not invoked. Source: [Kalama sys_pm_vx.c](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/sys_pm_vx.c), especially its mailbox monitor and PM callbacks.

The Android kernel does expose `rpmh_send_msg`, `rpmh_tx_done`, `qcom_lpm`, `cluster_lpm`, and `power:suspend_resume` tracepoint formats, but the prior Perfetto `linux.ftrace` route returned metadata-only traces and direct tracefs writes were denied by the current SELinux policy. Therefore the immediate next move is a source-and-trace comparison of the actual Android versus Armada PSCI/RPMh request sequence, using a capture route already proven to deliver those events; do not rebuild or switch the device merely to repeat the known counter result. The sys_pm_vx debug report is not a substitute for that request trace.

### 2026-09-19 13:45 UTC — Android deep capture exposes a different staged RPMh sleep/wake profile

Used the rooted Android kernel's `perf_event_open` path through `/system/bin/simpleperf`; unlike direct tracefs writes, it records RPMh tracepoints without changing tracefs controls. The 12-second `rpmh_send_msg`/`rpmh_tx_done` capture returned 1,927 samples, zero lost (1,340 send and 587 completion records). Raw perf data SHA-256: `1dd520d8117f5473190058ee752f869a072bfc7dfeb57cd33c2f66140790fab2`. Parsed payloads and source command are in `receipts/2026-09-19-android-deep-rpmh/tcs-sequence.txt`.

The live Android RSC DT node is `/sys/firmware/devicetree/base/soc/apps_rsc@17a00000/drv@2`; it reports driver 2, TCS offset `0xd0000`, and channel-0 config pairs `(2,3), (0,2), (1,2), (3,0), (4,1)`. The matching public Android source numbers these as ACTIVE 3, SLEEP 2, WAKE 2, CONTROL 0, FAST_PATH 1, placing sleep TCS 3 and wake TCS 5. The live CMD-DB identifies Android's additional resources: `SH1`, `QUP2`, `ACV`, `MC4`, and `SH5`, plus VRM operations for LDOE1/LDOE3. Read-only resource mappings are preserved in `receipts/2026-09-19-android-deep-rpmh/cmd-db-excerpts.txt`.

At one suspend-transition window the Android sleep and wake TCSes each contain 14 commands. Armada's archived Linux transition trace contains six BCM commands. On overlapping resources Android clears the SLEEP vote for MC0 and SH0 (`0x40000000`/`0`), while the archived Linux trace retains a valid low vote (`0x600001dc`, `vote_y=476`); the Android WAKE words also carry nonzero `vote_x` for MC0/SH0 where that Linux trace had `vote_x=0`. This is a concrete policy/request-set difference worth investigating, not yet the cause of the counter difference: these tracepoints capture staged TCS writes, and do not report firmware application. Also, another Linux RSC snapshot in the notebook has MC0/SH0 SLEEP words `0x600003b8` (`vote_y=952`), so the Linux artifacts disagree on the exact floor; reconcile run/build/phase provenance before treating the numerical contrast as apples-to-apples.

The most useful next move is now a source-level audit of where Armada's MC0/SH0 and VRM sleep votes come from and why its staged set differs from Android's. Focus first on interconnect BCM voters and regulator suspend-state constraints, then identify one safe single-variable A/B for Armada. Do not change the stats offsets, infer acceptance from `rpmh_send_msg`, or build/flash merely to repeat the known suspend result. Android remains on the same boot with `[s2idle] deep` restored, tracefs off, `current_tracer=nop`, and no kprobes.

### 2026-09-19 13:56 UTC — downstream regulator deep-sleep hook is not the staged-set source

Checked the active Android FDT read-only: `find /sys/firmware/devicetree/base -type d -name qcom,regulator_deepsleep` returns no node. The public downstream `rpmh-regulator.c` sets `enable_regulator_deepsleep` only when that node exists (probe near line 2059); the flag gates `rpmh_vreg_send_ds_requests()`, which clears cached aggregate request-valid masks and re-aggregates them (near lines 923–938). That helper is reached through regulator `.resume` / `.restore` callbacks (near lines 2126–2140), not as the pre-suspend source of the observed sleep TCS writes. This feature therefore does not currently explain Android's staged sleep/wake TCS profile. The VRM LDOE1/LDOE3 words remain real captured requests, but their originating client/policy is still unknown; CMD-DB names alone do not identify the owner. Do not attribute the profile difference to this hook or add a Linux regulator change from this evidence.

### 2026-09-19 14:16 UTC — Android and Armada use different PMIC regulator request contexts

Read the live Android FDT for `rpmh-regulator-ldoe1` and `rpmh-regulator-ldoe3`. Both use `pmic5-ldo` resources and split their PMIC-E LDOs into three proxy nodes with `qcom,set` values: base `3` (active + sleep), `-ao` `1` (active only), and `-so` `2` (sleep only). The downstream binding defines these bits as ACTIVE=1, SLEEP=2, ALL=3; the downstream regulator driver maps the bits into separate active/sleep request aggregates. Android's `regulator_summary` shows both `-so` proxies disabled while the corresponding `-ao` proxies are enabled. This separate `qcom,set` mechanism, rather than the absent `qcom,regulator_deepsleep` node, is the relevant Android policy difference. Raw values and source paths are in `receipts/2026-09-19-android-deep-rpmh/regulator-state-split.txt`.

The Android trace's SLEEP TCS writes LDOE1 mode `4` and disables LDOE1 and LDOE3; its WAKE TCS restores LDOE1 mode `7` and enables both. Mainline's v7.2 `qcom-rpmh-regulator.c` sends its ordinary regulator requests using `RPMH_ACTIVE_ONLY_STATE` and has no suspend-mode/enable callbacks, so a `regulator-state-mem` DTS node alone cannot reproduce those requests with Armada's current driver. Armada's `qcs8550-ayn-common.dtsi` instead has single LDOE1/LDOE3 regulators with ordinary mode constraints and no sleep-state entries. Those rails also supply DSI, PCIe, UFS PHY, USB, and DisplayPort PHY nodes, so do not disable them blindly. References: [Android downstream regulator code](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/regulator/rpmh-regulator.c), [Android qcom,set definitions](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/include/dt-bindings/regulator/qcom,rpmh-regulator-levels.h), [Armada Nova/QCS8550 regulator DTS](/Users/danhimebauch/Developer/.external-research/armada-packages/kernel/dts/qcs8550-ayn-common.dtsi:793), and [upstream Linux v7.2 regulator driver](https://github.com/torvalds/linux/blob/v7.2/drivers/regulator/qcom-rpmh-regulator.c).

Checked the existing Armada deep run `20260918T142021Z-883484904299` before requesting another cycle. It is a matched deep/deep, 28.96-second run; AOSD, CXSD, and DDR all remained zero. In its raw RPMh trace LDOE3 mode `4` and LDOE1 mode `4` are written in the `[active]` request state just before suspend; LDOE1/LDOE3 mode `7` returns in `[active]` after resume. Across the available Linux trace text, no LDOE1/LDOE3 enable-register writes or sleep/wake requests appear. This confirms Linux's captured request stream lacks the Android-style sleep-off requests in the same experiment that recorded zero counters. The TCS trace still proves requested policy only, not firmware acceptance or causation. Preserved exact lines and run details in `receipts/2026-09-19-android-deep-rpmh/armada-ldo-context.txt`.

Next move: do not run another identical sleep cycle. First review the downstream aggregation path and design the smallest upstream-quality equivalent using regulator suspend state with explicit RPMh SLEEP/WAKE requests. The current mainline driver has no suspend callbacks, so this is a driver capability gap, not a DTS-only fix. Before testing a patch, map which active/wake consumers need LDOE1/LDOE3 and check whether the RPMh driver is modular in the installed Armada kernel; that determines whether one-module validation can avoid a full kernel image build. Then test a single bounded deep cycle with the sleep-context change and read AOSD/CXSD/DDR immediately. Treat a changed counter as evidence for the hypothesis, not a final drain or residency claim.

### 2026-09-19 14:23 UTC — Linux already stages interconnect SLEEP/WAKE TCS requests

Corrected the comparison before proposing an interconnect driver patch: upstream v7.2.3 `bcm-voter.c` already emits ACTIVE_ONLY, WAKE_ONLY, and SLEEP batches when the BCM's WAKE and SLEEP votes differ. Armada's same-run trace has both a six-command WAKE batch and a six-command SLEEP batch, so this is not a missing generic interconnect sleep-state feature. Its commands cover MC0, SH0, SN0, CN0, QUP1, and QUP0. Android's captured batches each contain eleven BCM commands plus three PMIC regulator commands; they add SH1, QUP2, ACV, MC4, and SH5. On the shared MC0/SH0 resources, Android's SLEEP words request zero/off (`0x40000000` and `0`), whereas Armada stages nonzero floor values (`0x600001dc` for both). These are concrete staged-request differences, not proof of firmware acceptance or a specific physical state.

The source-level difference is now narrower: Armada's upstream BCM voter can create the same TCS classes, but the Nova Linux interconnect graph/consumer votes produce a smaller BCM list and higher MC0/SH0 sleep floors; separately, mainline's RPMh regulator driver does not construct Android's sleep-only LDOE requests. The next audit should compare the exact Linux and Android BCM definitions, DT phandles, and runtime ICC paths for the five additional resources, and trace which Linux consumers leave the MC0/SH0 sleep floor nonzero. Check the effective kernel config before designing deployment: Armada's build starts from v7.2.3 arm64 defconfig, which sets `CONFIG_REGULATOR_QCOM_RPMH=y`; the Armada override fragment leaves that symbol untouched, and the recipe links `Image`. Replacing only the RPMh regulator module is therefore not a safe shortcut on the current build. Do not change the interconnect driver on the basis of the earlier assumption that it lacks sleep/wake batching.

### 2026-09-19 14:40 UTC — Android suspend-window RPMh events are Apps-RSC-only

Retrieved the original 1.6 MiB simpleperf capture read-only from the rooted device and verified its SHA-256 matches `tcs-sequence.txt`. A strings scan of the complete raw perf data finds `apps_rsc-drv-2` controller identifiers but no `disp_rsc` or `cam_rsc` identifiers. Thus the decoded 14-command SLEEP/WAKE pair is an Apps-RSC transaction; the extra Display/Camera voter phandles in Android's live FDT did not emit a recorded `rpmh_send_msg`/`rpmh_tx_done` event during this 12-second bracket. This narrows the immediate source audit away from treating extra controllers as the demonstrated explanation. It does not prove those RSCs are never used or cannot affect arbitration outside this capture.

The best next move is to compare the same Apps-RSC path on both systems: map Android's additional SH1, QUP2, ACV, MC4, and SH5 BCM requests to its downstream `kalama.c` definitions and DT voters, then compare with Linux's `sm8550.c`/Nova DT and the source of the nonzero MC0/SH0 SLEEP floors. The key bounded hypothesis is a difference in Apps-RSC BCM membership or sleep-vote aggregation, alongside the independently observed regulator request-context gap. Do not add Display/Camera RSCs or alter votes until that source comparison identifies a minimal, supported A/B.

Evidence receipt: `receipts/2026-09-19-android-deep-rpmh/controller-coverage.txt`.

### 2026-09-19 15:00 UTC — Android awake ICC client snapshot saved; suspend hook is not writable from current root shell

Read and saved Android's `/sys/kernel/debug/interconnect/interconnect_summary` with no writes. The live 5.15.123 Android 13 boot (`qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys`, boot ID `45c48211-b345-477c-b1bb-ef163dce7b73`) shows `llcc_mc`/`ebi` aggregates at average 1,923,660 and peak 2,188,800, with visible clients including `soc:qcom,dcvs:ddr:sp` (1,793,064 / 2,188,000) and the CNSS QCA client (2,250 / 2,188,800). The QUP2 UART path has active requests (50,000 on `qup2_core_master`, 590,000 on `qhs_qup2`). Display-RSC `llcc_mc_disp`/`ebi_disp` and all camera-specific LLCC/EBI nodes are zero in this awake snapshot. These are current ICC requests only; they do not expose SLEEP/WAKE BCM buckets or show what firmware accepted. Full provenance and selected values are in `receipts/2026-09-19-android-deep-rpmh/android-icc-awake-and-hook-access.txt`.

The Android downstream `icc-debug.c` contains a `debug_suspend` hook that would print enabled ICC requests at `machine_suspend`, but writing its debugfs value from the current Magisk root shell failed with `Permission denied`. Selecting deep through `/sys/power/mem_sleep` also failed. The shell is UID 0 with `CapEff=0`; the SELinux enforcement state is inaccessible, so the precise access-control layer is not asserted. I did not change security policy or retry the suspend. The device remained on the same Android boot with `mem_sleep=[s2idle] deep`, an empty RTC wakealarm, and `debug_suspend=0`. A read-only SSH probe to Armada alias `192.168.0.20` timed out while Android ADB remained available, so there is no live Armada interconnect snapshot to compare in this boot.

The next useful step is a matched, read-only Linux capture after the Nova returns to Armada: save its `interconnect_summary`/graph and trace the existing `bcm_voter_commit` plus `rpmh_send_msg` events through the same bounded suspend bracket. Compare Linux's per-client state with the Android awake/sleep-set evidence before patching any floor vote or adding regulator state. The stable Android FDT's extra Display/Camera voters are not the immediate demonstrated cause: this Android bracket's RPMh event stream had Apps-RSC controller identifiers only. Do not disable SELinux, guess at AOP MMIO, or change kernel offsets to reach the next comparison.

### 2026-09-19 15:06 UTC — corrected Android root-shell probe; diagnostic controls are writable

The earlier `Permission denied` result was a command-quoting error, not a kernel lock, missing root capability, or SELinux denial. The command form `adb shell su -c '...; ...'` let the remote ADB shell parse the semicolons, so only the first simple command ran under Magisk `su`; the remaining commands ran as UID 2000 (`shell`). That is why the earlier mixed output showed `id` as root but `/proc/self/status` with `Uid=2000`, and why sysfs/debugfs writes failed. Correctly passing the whole quoted script as one remote command (`adb shell "su -c '...; ...'"`) keeps the complete body inside the root shell.

The correctly scoped shell is UID 0, context `u:r:magisk:s0`, with `CapEff=CapBnd=0x1ffffffffff`. SELinux was already permissive (`getenforce` = `Permissive`, `/sys/fs/selinux/enforce` = `0`); I did not change security policy or global enforcement. While awake, I successfully wrote `deep` to `/sys/power/mem_sleep`, toggled Android's `/sys/kernel/debug/interconnect/debug_suspend` from `0` to `1` and back to `0`, and restored the original `[s2idle] deep` selection. Final checks show `debug_suspend=0`, empty `/sys/class/rtc/rtc0/wakealarm`, and the same boot ID `45c48211-b345-477c-b1bb-ef163dce7b73`. No suspend was triggered during this control test.

This clears the blocker: the downstream ICC `debug_suspend` hook can be used without changing security policy. Next, arm that hook, select `deep`, schedule a short PMIC RTC wake, and call Android's already-validated `service call suspend_control_internal 2` force-suspend path. Retrieve the post-resume kernel log and restore `[s2idle]`, hook `0`, and an empty wakealarm. The capture should reveal Android's enabled ICC clients at `machine_suspend`; it will still be a client/request snapshot, not proof of firmware acceptance.

### 2026-09-19 15:09 UTC — Android suspend-boundary hook shows its DCVS clients omit SLEEP

Ran the detached Android capture with the hook enabled, `mem_sleep` temporarily selected to `deep`, and `rtc0/wakealarm` set to `+8`; `service call suspend_control_internal 2` returned `true`. The run log brackets the setup and restoration at 15:09:16–15:09:26 UTC. The kernel logged one `machine_suspend` callback before aborting on `Pending Wakeup Sources: [timerfd]`, then retried and logged a second callback before the PMIC RTC wake. The kernel's monotonic dmesg stamps around suspend are not elapsed wall time; use the run log and RTC wake event for this bounded interval, not the apparent sub-second timestamp spacing.

At the second callback, after the aborted attempt and Android retry, `debug_suspend` printed these enabled ICC clients/nodes:

* `soc:qcom,dcvs:ddr:sp`, tag `3`: `llcc_mc` and `ebi`, average `796916`, peak `2188000`.
* `soc:qcom,dcvs:llcc:sp`, tag `3`: `chm_apps` and `qns_llcc`, average `2390752`, peak `4800000`.

The first, aborted callback showed the same two clients with lower averages (`398456` on `llcc_mc`/`ebi`, `398448` on `chm_apps`/`qns_llcc`). No QUP2 request appeared in either suspend-boundary list. The exact output and run metadata are in `receipts/2026-09-19-android-deep-rpmh/android-icc-suspend-excerpt.txt` and `android-icc-suspend-run.log`.

The printed tag is the raw Qualcomm ICC request tag. In the exact Android header, AMC is bit 0, WAKE bit 1, and SLEEP bit 2; tag `3` is therefore `ACTIVE_ONLY` (AMC + WAKE) and excludes the SLEEP bucket. This makes the Android TCS observation more coherent: its live DCVS DDR/LLCC requests do not contribute to sleep-bucket votes, which is consistent with the observed cleared MC0/SH0 SLEEP words. This does not yet explain every BCM's floor or prove what firmware accepted. It is the strongest lead so far for the Android/Linux policy delta; next map these two tagged paths through their DT paths and BCM membership against Armada's Linux per-client and SLEEP-bucket aggregation, then identify the origin of Linux's nonzero MC0/SH0 floors. References: [Android ICC suspend hook](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/interconnect/qcom/icc-debug.c#L653-L667), [Android Qualcomm ICC bucket tags](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/include/dt-bindings/interconnect/qcom%2Cicc.h#L7-L21).

The temporary controls were restored: `mem_sleep=[s2idle] deep`, `debug_suspend=0`, and `rtc0/wakealarm` empty; boot ID stayed `45c48211-b345-477c-b1bb-ef163dce7b73`. SELinux remained at its pre-existing permissive setting and no policy changes were made. The post-resume ring buffer also contains an `Unbalanced enable for IRQ 31` warning; preserve it as an observed Android suspend warning, but do not attribute it to the ICC hook without further evidence.

### 2026-09-19 15:47 UTC — the PCIe 476 match is not yet a proven live suspend vote

The archived Armada deep run has a pre-suspend ICC request `dev=1c00000.pcie`, tag 7, peak `500000` on the MC0/SH0 memory paths. Applying the unmodified v7.2.3 BCM scaling to that request gives `vote_y=476` for both resources, numerically matching the captured SLEEP payload `0x600001dc`. However, the public v7.2.3 Qualcomm PCIe noirq callback should change this request before the SLEEP batch: after `dw_pcie_suspend_noirq()`, its `pci->suspended` branch calls `icc_disable(pcie->icc_mem)`, and the other branch reduces the memory request to 1 KB/s. In v7.2.3 core ICC code, `icc_disable()` calls `icc_set_bw()` after marking the request disabled, so either path should emit an `icc_set_bw` trace event. The archived trace had that event enabled with filter `none`, includes changes by other suspend callbacks, but contains no `dev=1c00000.pcie` update anywhere. It still sends MC0/SH0 SLEEP value 476.

This conflict makes the exact 500000-to-476 match an attractive source candidate, not proof that PCIe is the live SLEEP vote. Plausible explanations still open are that the shipped Armada source differs from public v7.2.3, the PCIe host driver's noirq callback did not run despite the generic power-domain callback log, or the request/voter state is being staged differently from the simple current-source model. `genpd_suspend_noirq returned 0` is not evidence by itself that `qcom_pcie_suspend_noirq()` ran. Do not change the PCIe tag, bandwidth, or suspend behavior based on the numeric match alone.

Next, resolve the build/source identity for the archived kernel (`kernel_release=7.2.3`, Armada `20260915.feca679`) and inspect the actual Qualcomm PCIe driver and PM callback path used to build it. If source confirms the upstream callback, the next short Linux capture should instrument the driver callback and/or `icc_disable` entry/return alongside the existing `icc_set_bw` trace, then inspect the enabled ICC request snapshot immediately before RPMh stages SLEEP. This is a bounded trace change and does not require a full kernel build if the existing tracepoints/kprobes suffice. Public source references: [Qualcomm PCIe noirq callback](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-qcom.c#L2159-L2215), [ICC disable/set implementation](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L714-L796).

### 2026-09-19 16:06 UTC — the 500000 PCIe request matches the active 5 GT/s x1 OPP; deep suspend can leave it live

The Armada kernel build uses the Linux 7.2.3 stable source plus the package patch series. The series contained both PCIe changes before this run: patch 0513 changes the Qualcomm PCIe OPP handling, and patch 0520 adds a 1000 kB/s suspend-only OPP to SM8550 pcie0. The rootfs commit used by the archived run pins kernel package image digest `4659cccb…`; the run did not archive `/usr/lib/modules/7.2.3/.armada-source`, so the installed artifact's exact source-to-digest association is not directly verified.

The SM8550 PCIe OPP table has a 5 GT/s x1 entry with `opp-peak-kBps = 500000`. That exactly matches the pre-suspend `1c00000.pcie` ICC request, tag 7, in the Linux receipt. OPP-core changes to that bandwidth call `icc_set_bw()`, so the lack of a PCIe update in the trace means this request was not changed during the captured transition.

There is a source path that explains the unchanged request. DesignWare `dw_pcie_suspend_noirq()` returns 0 early if `pci_host_common_d3cold_possible()` returns false, before setting `pci->suspended = true`. Qualcomm's noirq callback then takes its unsuspended branch. For an OPP-backed controller and `PM_SUSPEND_MEM` (the run's deep mode), that branch skips selecting the s2idle suspend OPP and leaves the active OPP in place. BCM scaling maps its 500000 peak to the observed MC0/SH0 sleep vote: `500000 * 16 / 4 = 2000000`, then `2000000 * 1000 / 4200000 = 476 = 0x1dc`. If the host instead reaches `pci->suspended = true`, the deep branch drops the OPP and should produce an ICC bandwidth update, which is absent. This makes the PCIe link not reaching D3cold the leading explanation for the residual vote, but the archived run did not record the predicate or `pci->suspended` value.

The pre-suspend runtime snapshot shows the qcom-pcie controller and ath12k endpoint both active, with wakeup disabled on the PCI devices. That does not establish their PCI power state at the noirq boundary. Android's suspend-boundary hook showed no PCIe ICC request, while Linux has the tag-7 PCIe memory request; this is a concrete policy difference, but whether it alone prevents AOSD/CXSD/DDR residency remains unproven. Do not lower or retag the vote yet because it may be required for safe resume or Wi-Fi restoration.

The smallest next diagnostic is one trace-only Linux deep cycle with no build: record entry/return of `qcom_pcie_suspend_noirq`, `dw_pcie_suspend_noirq`, and `pci_host_common_d3cold_possible`; keep `interconnect:icc_set_bw` and RPMh SLEEP tracing enabled; save `d3cold_allowed`, `power/wakeup`, link speed/width, and AOSD/CXSD/DDR counts before and after. This directly distinguishes a retained active OPP from another source of 476. Only then choose a causal A/B. In this session Android ADB is reachable, but SSH to Armada at 192.168.0.20 has no route; I have made no security or device changes.

References: [Armada PCIe OPP patch](../../../armada-packages/kernel/patches/0513-PCI-qcom-honour-an-opp-suspend-opp-as-the-non-s2ram-memory-floor.patch), [Armada suspend-OPP DT patch](../../../armada-packages/kernel/patches/0520-arm64-dts-qcom-sm8550-add-a-pcie-suspend-opp.patch), [Linux 7.2.3 DesignWare suspend path](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-designware-host.c#L1223-L1293), [Linux 7.2.3 PCIe D3cold check](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/pci-host-common.c#L286-L343), [Linux 7.2.3 OPP-to-ICC path](https://github.com/gregkh/linux/blob/v7.2.3/drivers/opp/core.c#L1150-L1175).

### 2026-09-19 16:19 UTC — rooted Android is reachable; Armada remains installed but boot selection is physical

Fresh `adb devices -l` shows the Nova at `192.168.0.163:5555`. A correctly quoted root command confirms uid 0 (`u:r:magisk:s0`), Android fingerprint `qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys`, active Android slot `_a`, and SELinux already permissive (`getenforce=Permissive`, `/sys/fs/selinux/enforce=0`). `service.adb.tcp.port=5555` is set only for this boot; `persist.adb.tcp.port` and `ro.boot.bootmode` are empty. I made no security-policy or ADB persistence change.

Read-only block inventory confirms the internal Armada installation is intact: `ARMADA` is `/dev/block/sda18` (512 MiB), `ARMADA_BOOT` is `/dev/block/sda19` (1 GiB), and `ARMADA_ROOT` is `/dev/block/sda20` (98,070,167,552 bytes). SSH to the Linux alias `192.168.0.20` times out because this session is currently Android. The local `armada-boot-hotkeys` script only selects Desktop Mode after Linux has started; it is not an Android/Linux selector.

Armada's current uninstall/restore documentation says OS selection is in the ROCKNIX ABL menu: hold VOL- during power-on, then use volume and Power to change the persistent boot mode. No remote ADB command or installed Android selector was established, and the current Wi-Fi ADB port is not persistent. I have not rebooted or changed boot mode, to preserve the only live control path. The next device-side experiment still needs the Nova booted into Armada; once SSH returns, run one short direct-deep trace with the PCIe D3cold predicate and PCIe noirq callbacks, `icc_set_bw`, RPMh SLEEP messages, and before/after qcom_stats. Receipt: `receipts/2026-09-19-android-deep-rpmh/android-root-live-preflight.txt`. Reference: [Armada ABL boot-mode instructions](https://armadaos.dev/getting-started/uninstalling-and-restoring-android/).

### 2026-09-19 16:31 UTC — trace-only PCIe D3cold profile is ready; no kernel build needed

Added a `pcie-d3cold` profile to the existing suspend-lab runner. It requires and filters `interconnect:icc_set_bw{,_end}` and `power:device_pm_callback_{start,end}` to the exact controller `1c00000.pcie`, captures RPMh/AOSS plus system-suspend events, and registers one run-unique return kprobe on the exported `pci_host_common_d3cold_possible()` symbol. That boolean directly answers whether the common host helper considers D3cold safe; the filtered PM callbacks show whether the PCIe device's noirq callback ran and its return status. Before/after runtime snapshots now also save PCI function `d3cold_allowed`, `power_state`, link speed/width, and `enable` where sysfs provides them. The existing runner removes the kprobe and private trace instance after capture; there is no power-policy, interconnect, or device-state write and no kernel build.

The host validation passed: Python byte-compilation, the runner self-test (including exact trace-filter field checks), CLI profile enumeration, and `git diff --check`. The kernel-side availability of the symbol and filter syntax remains to be checked in Armada itself because the Nova is presently Android. When its ABL boots back to Armada, the prepared run is an 8-second direct-deep cycle with Wi-Fi/Bluetooth preserved and will record the pre/post qcom_stats and RPMh sleep commands along with the PCIe predicate. No device-side trace, suspend, boot-mode, or security-policy change has been made yet.

### 2026-09-19 16:42 UTC — Linux restored; PCIe trace preflight passes

The user switched the Nova to Linux. SSH to `armada` now works again; the device is running kernel `7.2.3` and Armada image `20260915.feca679`, boot ID `6341f468-6f84-4d38-ad2e-3bb220cc67bb`. A fresh read-only lab preflight is saved at `../sm8550-suspend-lab-runs/preflight-20260919T164209Z-5ccd11eecc01.json`.

All events required by `pcie-d3cold` are present: RPMh send/done, AOSS send/done, ICC `set_bw`/end, PM callback start/end, and `power:suspend_resume`. Tracefs is mounted, `pci_host_common_d3cold_possible` is present in kallsyms, and the machine exposes `[s2idle] deep`; the configured session suspend mode remains s2idle. The preflight also confirms the PSCI probe is available. No kernel build is needed for this experiment.

The device is USB-powered and charging during this capture window (`battery` status `Charging`, both Qualcomm USB and UCSI source reports online); `/sys/bus/usb/devices` is empty, so the cable is not presenting a USB data device to Linux. Treat external power as a recorded condition if interpreting sleep counters. Android's Wi-Fi ADB transport dropped during the mode switch, as expected; I did not issue a reboot or change security/boot policy. A read-only Android check found no `bootctl` or `fastboot` executable and no `/sys/firmware/efi` runtime interface; Armada's `abl/README` documents the VOL- ABL menu as the boot-mode path. Since the device is now in Linux, no bootloader change is needed.

Next: run one direct-deep cycle with `pcie-d3cold`, preserving Wi-Fi and Bluetooth. This is trace-only apart from the harness's temporary wake alarm, temporary trace instance/kretprobe, and temporary direct `mem_sleep` selection, all cleaned up by the runner.

### 2026-09-19 16:45 UTC — 8-second request rejected before suspend; cleanup verified

The lab runner enforces a 10-second minimum wake-alarm interval. The first 8-second invocation therefore failed before arming the RTC, preparing the trace, selecting direct `deep`, or calling suspend. Receipt: `../sm8550-suspend-lab-runs/20260919T164520Z-490f0957797d/`.

The runner's failure cleanup restored `/sys/power/pm_debug_messages` and `pm_print_times`, reported no radio changes, no RTC change, and no transient-mode change; trace setup never created an owned instance. The detached unit is no longer listed. Boot ID is unchanged. I will use the minimum accepted 10-second interval for the actual trace.

### 2026-09-19 16:54 UTC — deep run confirms D3cold predicate is false and records nonzero SLEEP votes

The 10-second direct-deep run completed successfully and resumed on the same boot (`20260919T164739Z-23012a86a7b3`). It observed `PM: suspend entry (deep)`, a matching RTC wake interrupt/source, and 8.670 seconds of clock-proven sleep. The PCIe D3cold return kprobe fired once, inside `qcom-pcie 1c00000.pcie`'s noirq suspend callback, with `retval=0`; that callback still returned `err=0`, so deep suspend proceeded. The helper's return is false, not a suspend error.

The before/after runtime snapshots show the root port `0000:00:00.0` and ath12k endpoint `0000:01:00.0` with `d3cold_allowed=1`, `power_state=D0`, and wakeup disabled. The endpoint is bound to `ath12k_wifi7_pci`; it was runtime-active in both snapshots. These snapshots bracket the full suspend, not the exact helper call, so they do not identify which in-suspend PCI device condition made the predicate false.

No `icc_set_bw` call for `dev=1c00000.pcie` appeared on the suspend side. The ten filtered PCIe ICC events all occur during noirq resume; the memory path is restored to `peak_bw=500000`. This matches the source path where the common helper's false result prevents the host from marking the link suspended, and supports (but does not yet prove as the sole cause) the retained active PCIe OPP explanation.

The same trace records the Apps RSC `[sleep]` TCS immediately before `machine_suspend`: CMD_DB maps `0x50000` to BCM `MC0` and `0x50004` to BCM `SH0`; both carry encoded data `0x600003b8`. Thus Linux submits nonzero MC0/SH0 SLEEP requests before the system-level suspend. I am not assigning this encoded vote solely to PCIe without an A/B. AOSD, CXSD, and DDR sleep-stat records remain available but all-zero before and after; ADSP count advances by 238. The `rpmh_rsc_snapshot` event is not part of this profile, so the captured message is the submitted SLEEP TCS, not an independent firmware residency acknowledgment.

The runner restored `mem_sleep` to `[s2idle] deep`, cleared its RTC alarm, removed its trace instance/kretprobe, left Wi-Fi/Bluetooth unchanged, and removed its systemd unit. Host artifacts are under `../sm8550-suspend-lab-runs/20260919T164739Z-23012a86a7b3/`.

Next: repeat the same 10-second deep trace with only Wi-Fi set off through NetworkManager; let the runner restore the original radio state afterward. Keep USB charging as-is. Compare the D3cold return, PCIe ICC change, MC0/SH0 SLEEP payload, and qcom_stats deltas. If the predicate turns true and the floor drops, Wi-Fi/PCIe is a causal candidate; if not, trace the per-device condition inside `pci_host_common_d3cold_possible()` rather than changing the bandwidth vote.

### 2026-09-19 16:57 UTC — Wi-Fi-off A/B removes one MC0/SH0 vote but not the D3cold veto

Ran the same 10-second direct-deep profile with only NetworkManager Wi-Fi set to off (`20260919T165514Z-0ada76b44d6d`). The test completed, resumed on the same boot, matched the RTC wake source, and restored Wi-Fi successfully (`nmcli radio wifi on` returned 0). Bluetooth was preserved; USB charging remained present.

The D3cold kretprobe still returned false inside the PCIe noirq suspend callback, which still returned `err=0`. AOSD/CXSD/DDR remained all-zero; ADSP advanced by 247 counts. Apps-RSC SLEEP TCS values for both MC0 and SH0 changed from `0x600003b8` with Wi-Fi enabled to `0x600001dc` with Wi-Fi off, a reduction of exactly `0x1dc` (476) per resource. A nonzero 476 request remains. This confirms that Wi-Fi state controls one component of the submitted sleep vote, but that component alone is not sufficient to explain the D3cold veto or the zero sleep counters.

The remaining 476 is consistent with the PCIe host's active 500000 kB/s OPP floor being retained when the D3cold helper returns false, but the trace has not attributed individual vote contributions to clients. Keep the floor unchanged. Next, capture suspend callbacks for the root port `0000:00:00.0` and Wi-Fi endpoint `0000:01:00.0`, plus their power-state transitions, to identify which device condition makes the helper return false. Compare that with the helper's source conditions before any further experiment.

Artifacts: `../sm8550-suspend-lab-runs/20260919T165514Z-0ada76b44d6d/`.

### 2026-09-19 17:13 UTC — PCI child callbacks succeed, but the D3cold predicate still rejects the host

The Mac's `adb devices` list and `system_profiler SPUSBDataType` show no USB data device; Linux also reports no `/sys/bus/usb/devices`. The cable supplies power only. Wi-Fi SSH remains available.

Expanded the `pcie-d3cold` trace filter to include PCI host `1c00000.pcie`, root port `0000:00:00.0`, and Wi-Fi endpoint `0000:01:00.0`. The 10-second direct-deep run `20260919T170802Z-07877432598f` completed on the same boot, observed 8.7258 seconds of sleep, resumed in 2.04 seconds, and restored all temporary trace/RTC state. All three devices' suspend and noirq callbacks returned `err=0`; nevertheless `pci_host_common_d3cold_possible()` returned false in the host's noirq callback. AOSD/CXSD/DDR stayed zero; ADSP count advanced by 235. Artifacts: `../sm8550-suspend-lab-runs/20260919T170802Z-07877432598f/`.

The post-resume PCI snapshot shows root port and Wi-Fi endpoint in D0, `d3cold_allowed=1`, and wakeup disabled. Those post-resume values do not establish their state at the host predicate. Linux v7.2's helper rejects an active device unless its `current_state` is `PCI_D3hot`, or rejects a wake-enabled device that cannot signal PME from D3cold. Callback success therefore does not explain which device failed the predicate. The next narrow test is a temporary kretprobe on the helper's per-device callback `__pci_host_common_d3cold_possible()`, which returns `-EOPNOTSUPP` at the first veto. PCI bus traversal is depth-first from the root port to its subordinate Wi-Fi endpoint; capture the callback return sequence to locate the first veto without altering device power policy. Source: [D3cold predicate](https://github.com/torvalds/linux/blob/v7.2/drivers/pci/controller/pci-host-common.c#L286-L343), [PCI bus traversal](https://github.com/torvalds/linux/blob/v7.2/drivers/pci/bus.c#L408-L465).

### 2026-09-19 17:17 UTC — root port is the first D3cold veto

Added a run-unique kretprobe on `__pci_host_common_d3cold_possible()` and ran one more 10-second direct-deep cycle (`20260919T171557Z-316581cdd833`). The callback produced exactly one return, `-95` (`-EOPNOTSUPP`), immediately before the PCI host noirq callback returned `err=0`. `pci_walk_bus()` traverses the root bus's device list depth-first and stops on the first nonzero callback result; this device has only the root port `0000:00:00.0` followed by its subordinate Wi-Fi endpoint `0000:01:00.0`. The first veto is therefore the root port, and traversal never reaches the endpoint. All system suspend callbacks still returned 0. This is stronger than the outer boolean probe and localizes the D3cold veto to a specific PCI function.

The cycle observed 8.168 seconds asleep and resumed on the same boot. AOSD/CXSD/DDR stayed zero; ADSP count advanced by 242. The probe and trace instance were removed (`kprobe_cleanup_success=true`). Artifacts: `../sm8550-suspend-lab-runs/20260919T171557Z-316581cdd833/`.

The exact field/reason remains open: the helper returns `-EOPNOTSUPP` when an active function is not in `PCI_D3hot`, or when a wake-enabled function lacks PME-from-D3cold. The root port's pre/post snapshots show it enabled and `power/wakeup=disabled`, strongly suggesting `current_state != PCI_D3hot`, but neither post-resume state nor callback `err=0` proves the state at the check. Next, read the kernel BTF layout and add a bounded trace of the root port's `current_state` at the callback entry (or find an existing debug interface exposing it). Do not infer or modify the power state from the callback return alone.

### 2026-09-19 17:28 UTC — Root-port veto is specifically `PCI_UNKNOWN`

Decoded `struct pci_dev::current_state` from the running kernel's BTF and guarded the diagnostic against any other kernel release or BTF hash. The read-only kretprobe on `__pci_host_common_d3cold_possible()` captured `pdev_state=5 retval=-95` during the same callback that previously gave only `-EOPNOTSUPP`. Linux v7.2 defines `PCI_UNKNOWN` as numeric 5 and `PCI_D3hot` as 3 ([enum values](https://github.com/torvalds/linux/blob/v7.2/include/linux/pci.h#L2477-L2497)); the helper's first state check rejects any active function whose current state is not D3hot ([predicate](https://github.com/torvalds/linux/blob/v7.2/drivers/pci/controller/pci-host-common.c#L286-L343)). Therefore the observed veto is the root port's unknown software power state, not the PME-from-D3cold condition.

The guarded 10-second deep cycle (`20260919T172715Z-383542dc7c16`) completed on the same boot, measured 8.6534 seconds of suspend, matched the RTC wake, and cleaned up the temporary kprobe/trace instance. AOSD/CXSD/DDR stayed zero; ADSP advanced by 233 counts and APSS by 1. Exact trace line: `d3cold_device_ret: ... pdev_state=5 retval=-95`, immediately before the host noirq callback returned `err=0`. Artifacts: `../sm8550-suspend-lab-runs/20260919T172715Z-383542dc7c16/`.

Next determine why the root port's `current_state` remains unknown: inspect its read-only PCI PM capability/configuration and sysfs power-state/runtime-PM attributes, then compare the PM transition sequence with the root-port driver/bus PM path. Do not write PCI config or force D-states. This identifies one blocker to D3cold eligibility; it does not by itself explain why AOSD/CXSD/DDR counters remain zero.

### 2026-09-19 17:31 UTC — Generic PCI bus PM intentionally marks the unbound root port unknown

The pre-suspend snapshot shows root port `0000:00:00.0` in D0, runtime-active, enabled, with `d3cold_allowed=1`; the sysfs `driver` link is absent. Kernel logs identify it as Qualcomm `17cb:0113`, a PCIe Root Port with PME support from D0/D3hot/D3cold. Its suspend trace is the PCI bus callback `pci_pm_suspend_noirq`, followed 1 ms later by the Qualcomm host callback and the observed `current_state=PCI_UNKNOWN`.

Linux v7.2 source explains the transition: when the PCI device has no PM ops, `pci_pm_suspend_noirq()` saves config and jumps to `set_unknown`; `pci_pm_set_unknown_state()` deliberately changes D0 to PCI_UNKNOWN because firmware may alter state during system suspend ([no-PM-ops path](https://github.com/torvalds/linux/blob/v7.2/drivers/pci/pci-driver.c#L3620-L3640), [D0 to unknown](https://github.com/torvalds/linux/blob/v7.2/drivers/pci/pci-driver.c#L3230-L3245), [set_unknown label](https://github.com/torvalds/linux/blob/v7.2/drivers/pci/pci-driver.c#L3723-L3725)). This exactly matches the D0 pre-snapshot and `pdev_state=5` at the D3cold check. Since the helper walks the root bus and rejects active devices not in D3hot, the unbound root port is the concrete reason `pci_host_common_d3cold_possible()` returns false on this device.

This confirms a PCIe host D3cold eligibility blocker, not the full cause of zero AOSD/CXSD/DDR counters. Next inspect the upstream/vendor Qualcomm host suspend path and the root-port representation to decide whether the correct fix is to exclude this integrated root port from the endpoint eligibility walk or give it an explicit, truthful PM state contract. Do not simply force `current_state` to D3hot; no hardware transition has been established.

### 2026-09-19 17:45 UTC — Armada disables the PCIe port driver with pcie_ports=compat

The live kernel command line contains `pcie_ports=compat`. Armada's bootc kernel-argument source is `../armada/system_files/usr/lib/bootc/kargs.d/10-armada.toml`; git blame shows this argument has been present since the initial file commit `adbd224`, with no accompanying rationale. The running kernel has `CONFIG_PCIEPORTBUS=y` and `CONFIG_PCIEAER=y`, but `/sys/bus/pci/drivers/pcieport` is absent. The Qualcomm root port `0000:00:00.0` is unbound, PCI enabled (`enable=1`), D0/runtime-active before suspend, and wakeup-disabled.

Upstream Linux v7.2 `pcie_ports=compat` sets `pcie_ports_disabled=true`; `pcie_portdrv_init()` then returns `-EACCES` before registering the PCIe port driver. This explains why the root port has no driver/PM callbacks. With no driver PM ops, generic `pci_pm_suspend_noirq()` saves config and marks the root port's D0 state unknown; the already-recorded `pdev_state=5` is exactly that path. Sources: [pcie_ports parser and driver init](https://github.com/torvalds/linux/blob/v7.2/drivers/pci/pcie/portdrv.c#L2882-L2926), [generic noirq PM path](https://github.com/torvalds/linux/blob/v7.2/drivers/pci/pci-driver.c#L3620-L3725).

The initial Qualcomm D3cold helper patch did filter out root ports and switches, but the PCI review explicitly rejected ignoring all intermediate/root-port devices: a bound bridge/RCiEP/RC-EC driver can need D0 and must prevent the host from sending PME_Turn_Off. The author removed the device-type filter in response. Therefore, patching the common helper to skip this root port would contradict the reviewed safety model. Source: [v5 helper patch and maintainer review](https://patchew.org/linux/20260429-d3cold-v5-0-89e9735b9df6%40oss.qualcomm.com/20260429-d3cold-v5-1-89e9735b9df6%40oss.qualcomm.com/#146).

This yields a concrete, reversible experiment to consider: use a one-shot boot with `pcie_ports=native`, then verify that the root-port driver binds, record its `current_state` at the D3cold predicate, and compare the predicate, PCIe ICC/OPP teardown, RPMh SLEEP words, and qcom_stats. Native mode may enable Linux PCIe port services (including PME/AER/hotplug where supported), so do not make this the permanent Armada default based on the current evidence. First establish a one-shot boot/rollback path. Even if the port then reaches D3hot and the PCIe vote drops, that would identify one D3cold/ICC blocker; it would not by itself prove why the AOSD/CXSD/DDR counters were zero.

### 2026-09-19 18:12 UTC — staged pcie_ports A/B is ready, but not yet rebooted

Staged a kernel-argument-only deployment on the live Nova with `rpm-ostree kargs --delete=pcie_ports=compat`. The staged deployment (OSTree serial 2, index 0) no longer has the argument; the still-booted serial 1 retains it. No kernel build or image rebuild was used. This tests the minimal change: allow `pcieport` to register without explicitly forcing `pcie_ports=native`.

Preflight initially showed the staged deployment's `/etc` missing the current SSH host keys, Wi-Fi profile, enabled `sshd` link, and local lab configuration. This is expected for an unfinished staged deployment, not evidence those settings will be lost: `ostree-finalize-staged.service` is active and its shutdown `ExecStop` runs `ostree admin finalize-staged`, which performs the delayed `/etc` merge. Armada then runs `armada-bootimg-finalize` after that merge to regenerate `/boot/efi/KERNEL` from the new default BLS entry. The staged deployment has `finalization-locked=false`. Do not test by writing directly into the staged deployment's `/etc`; let the supported finalization path merge the live config. See the [OSTree staged-deployment documentation](https://ostreedev.github.io/ostree/deployment/).

The first 10-minute rollback timer was stopped before reboot when its deployment scope was unclear. It remains enabled but inactive in the live `/etc`; `systemctl stop` did not remove its enablement symlink. I verified on-device that `bootc rollback --apply` always reboots and discards an unapplied staged deployment. Updated the guard service to run only when the kernel command line lacks `pcie_ports=compat`, create the shared `/var/lib/sm8550-pcie-test-rollback-fired` marker, then invoke that rollback. This lets the test boot self-rollback if SSH does not return, prevents the previous normal deployment from firing the test guard, and prevents a second rollback after recovery. `systemd-analyze verify` passed; the timer is enabled but inactive on the current boot, the marker is absent, and no reboot has occurred.

The boot-image preflight is clear: `/boot/efi` has 368 MiB free and the current `/boot/efi/KERNEL` is 75,522,048 bytes, leaving room for the known-good snapshot plus the regenerated kernel image.

Before the A/B, confirm the staged deployment still omits `pcie_ports=compat`, the rollback timer is enabled/inactive, the marker is absent, and the bootimg finalizer has sufficient space and current inputs. After boot, check that SSH returned, immediately stop/disable the rollback timer, and collect `pcieport` binding, PCI D3cold predicate state/return, PCIe ICC/OPP, RPMh SLEEP TCS, and AOSD/CXSD/DDR deltas during the same guarded 10-second direct-deep trace. This remains a targeted PCIe eligibility experiment; even a changed D3cold result would not alone prove the cause of the zero firmware residency counters.

### 2026-09-19 18:20 UTC — removing pcie_ports=compat binds pcieport but does not clear the D3cold veto

The staged kargs booted on a new boot ID (`7549cc82-5dbf-40a5-9b6f-42b737e45393`); `/proc/cmdline` no longer contains `pcie_ports=compat`, and `/sys/bus/pci/devices/0000:00:00.0/driver` resolves to `pcieport`. The guard timer was immediately disabled after SSH returned; its `/var` marker was not created. The deployed image and kernel remain `20260915.feca679` / `7.2.3`; this was a boot-argument-only test.

The matched Wi-Fi-off, 10-second direct-deep run `20260919T181557Z-cb567ba69946` completed successfully on the same boot and measured 8.4586 seconds of clock-separated sleep. Both the `pcieport 0000:00:00.0` and `ath12k_wifi7_pci 0000:01:00.0` late/noirq PM callbacks returned `err=0`. However, `qcom-pcie 1c00000.pcie` still received `pci_host_common_d3cold_possible() == false`; its one recorded per-device callback returned `pdev_state=5` (`PCI_UNKNOWN`), `retval=-95` (`-EOPNOTSUPP`). The current probe records the state and return but not the PCI function identity. Thus removing `pcie_ports=compat` restores port-driver binding, but has not established that the root port was the state-5 device or cleared the host veto.

PCIe interconnect `icc_set_bw` events in the trace occur only during resume; the restored path retains `peak_bw=500000`. AOSD, CXSD, and scalar DDR records still have zero count/duration deltas; detailed DDR LPM IDs `0x11`, `0xd3`, and `0xd4` also remain zero. Separate ADSP/APSS subsystem records advance. Apps-RSC SLEEP TCS submits MC0/SH0 words `0x600003b8` in this run. The run requested Wi-Fi off and recorded a successful `nmcli radio wifi off`, but the earlier Wi-Fi-off experiment recorded `0x600001dc`; do not attribute the SLEEP word difference to the PCIe boot-argument change until the client/resource contribution is identified.

Next: extend only the temporary `pcie-d3cold` trace event to include a stable PCI identity (bus/device/function, vendor, and device ID) alongside `current_state`, using offsets verified against this running kernel's BTF. Repeat the short trace on the current boot, which already has `pcieport` bound. This will distinguish a still-unknown root-port state from an endpoint state and tell us whether the D3cold veto and retained PCIe floor share a concrete device cause. Do not change the generic D3cold predicate or leave the boot argument removed as a permanent fix based on this run. Artifacts: `../sm8550-suspend-lab-runs/20260919T181557Z-cb567ba69946/`.

### 2026-09-19 18:30 UTC — the PCI_UNKNOWN D3cold veto is the Qualcomm root port

Extended the temporary kretprobe with BTF-verified `pci_dev` and nested `pci_bus` fields. The short run `20260919T182725Z-0615b49b6039` captured the first and only D3cold callback veto as `pdev_state=5`, `pdev_busnum=0`, `pdev_domain=0`, `pdev_devfn=0`, `pdev_vendor=6091 (0x17cb)`, `pdev_device=275 (0x0113)`, `pdev_class=394240 (0x060400)`, `retval=-95`. Those values match PCI function `0000:00:00.0`, the Qualcomm PCIe Root Port. Therefore the PCI_UNKNOWN veto remains the root port even with the `pcieport` driver bound; the endpoint is not the first failing function.

The run completed a real direct-deep interval of 8.7097 seconds, returned on the same boot, and cleaned up its private trace instance and kretprobe. AOSD/CXSD/scalar DDR remain zero; ADSP/APSS subsystem records advance separately. This confirms the root-port eligibility blocker, but still does not show that removing the retained PCIe floor would make AOP record AOSD/CXSD/DDR residency. No D3hot state was forced and no MMIO was read.

Next inspect the exact v7.2.3 PCI core and `pcieport` PM callback path to explain why binding the port driver still leaves `current_state=PCI_UNKNOWN`, then inspect the Qualcomm host driver's use of the D3cold predicate and ICC/OPP teardown. Keep the boot argument change temporary and restore the original `pcie_ports=compat` setting after this diagnostic; do not claim that root-port D3cold eligibility is the cause of the zero firmware counters without a safe, separate A/B that changes the vote and observes those counters. Artifacts: `../sm8550-suspend-lab-runs/20260919T182725Z-0615b49b6039/`.

### 2026-09-19 18:45 UTC — the root-port veto leaves the DesignWare host unsuspended

The Linux v7.2.3 call path explains why the port-driver A/B did not clear the veto. `dw_pcie_suspend_noirq()` returns success immediately when `pci_host_common_d3cold_possible()` is false, before it stops the link, deinitializes the host, or sets `pci->suspended = true`. The Qualcomm callback therefore takes its “not suspended” branch even though system suspend continues. The PCIe port driver has a regular `.suspend` callback and `.resume_noirq`, but no `.suspend_noirq`; binding it does not establish a D3hot state for the root port. Sources: [DesignWare noirq suspend](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-designware-host.c#L1223-L1293), [PCIe port-driver PM ops](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pcie/portdrv.c#L2960-L2984), [generic PCI noirq state handling](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci-driver.c#L3620-L3725).

Armada's package patch `0513` changes the Qualcomm callback's OPP handling. In the fallback branch, deep mode (`PM_SUSPEND_MEM`) skips the suspend-OPP selection, so an active OPP can remain when the root-port veto prevents `pci->suspended` from becoming true. The corresponding non-S2RAM fallback selects the 1000 kB/s suspend OPP. This makes the retained 500000 kB/s PCIe OPP a plausible contributor to deep-mode SLEEP votes, while still not proving it explains the opaque AOSD/CXSD/DDR counters. The live `/usr/lib/modules/7.2.3/.armada-source` confirms Linux 7.2.3 with 144 Armada patches, but does not enumerate patch hashes, so exact patch-to-image provenance remains open. Patch and table: [0513 Qualcomm OPP handling](../../../armada-packages/kernel/patches/0513-PCI-qcom-honour-an-opp-suspend-opp-as-the-non-s2ram-memory-floor.patch), [0520 SM8550 suspend OPP](../../../armada-packages/kernel/patches/0520-arm64-dts-qcom-sm8550-add-a-pcie-suspend-opp.patch).

The raw A/B receipts show a remaining attribution problem. Both runs were on the same boot with `pcieport` bound and Wi-Fi requested off. Run `20260919T181557Z-cb567ba69946` submitted MC0/SH0 SLEEP words `0x600003b8` (952); run `20260919T182725Z-0615b49b6039` submitted `0x600001dc` (476). The latter captures the root port `0000:00:00.0` as the sole D3cold veto and has no host-filtered `icc_set_bw` update before its SLEEP batch. Its 476 value matches the known 500000 kB/s-to-BCM scaling, but the other run's extra 476 shows that the whole SLEEP word cannot be assigned to PCIe from this evidence. AOSD/CXSD/scalar DDR deltas remain zero in both.

Next capture all ICC clients (remove only the `dev=1c00000.pcie` filter) during one matched short direct-deep run, and record the SLEEP batch and qcom_stats together. This should identify the extra 476 and show which requests remain when the host callback returns unsuspended. Then restore the original `pcie_ports=compat` boot argument; removing it did not change the root-port veto or qcom_stats.

### 2026-09-19 18:53 UTC — full ICC trace preserves the 476 request but not its earlier client state

The all-client direct-deep run `20260919T184853Z-e2c0a82feb60` completed successfully on the same boot, slept for 8.2747 seconds, woke from the expected RTC alarm, restored Wi-Fi, and removed its trace instance and kprobe. The 945 kB trace had no per-CPU overruns or dropped events, and both ICC tracepoint filters were `none`.

At the PCI host's noirq suspend callback, the helper again vetoed on root port `0000:00:00.0` with `current_state=PCI_UNKNOWN`; the host callback returned 0. There was no `icc_set_bw` event for `1c00000.pcie` anywhere in this all-client trace. Between that callback and the final SLEEP batch, recorded ICC updates were QUP I2C client paths dropping to small suspend requests. MC0/SH0 still received `0x600001dc` (476). This is consistent with the retained active 500000 kB/s PCIe OPP, but does not identify every contributor.

The tracepoint records request changes, not a snapshot of active client requests at trace start. The earlier matched run `20260919T181557Z-cb567ba69946` had `0x600003b8` (952), while the next two had 476; this capture does not explain the extra 476 because it may have been active before tracing began. AOSD/CXSD/scalar DDR count and duration remain unchanged; ADSP advances by 13 and APSS by 1. The PSCI idle trace is still unavailable.

The useful result is a firm negative: binding `pcieport` and removing the boot argument did not resolve the AOP counters, and no PCIe ICC update was issued during the observed deep-suspend transition. Restore `pcie_ports=compat` now. If further vote attribution is needed, first inspect whether the device's interconnect debugfs exposes per-client requests; otherwise start tracing before the state changes that create the extra vote. No kernel build or vote change is justified yet.

### 2026-09-19 18:59 UTC — original boot restored; per-client ICC snapshots explain the variable 476 component

The device rebooted successfully onto boot ID `4508b1ed-cfbd-43a1-a37e-ccee2a163a20`. `/proc/cmdline` again contains `pcie_ports=compat`; the PCI root port has no `driver` symlink, as expected in compat mode. `rpm-ostree status --json` reports deployment serial 3 booted, serial 2 as rollback, and no staged deployment. The test rollback timer unit is absent and its marker is absent. SSH and the Wi-Fi route returned. `rpm-ostree status` in human-readable mode aborts on a missing `timestamp` assertion on this image; the JSON query works and was used to check staged state. No further persistent device changes remain from the PCIe A/B.

Captured the read-only live `/sys/kernel/debug/interconnect/interconnect_summary` and `interconnect_graph` after the restored boot; both exist and are readable. The summary is 343 lines / 23,669 bytes and includes 214 per-consumer entries, not just provider aggregates. Its current PCIe memory-path request is `avg_bw=0`, `peak_bw=1,000,000` kB/s on `llcc_mc@interconnect-1` and `ebi@interconnect-1`. Raw files and restore-state receipt are in `../sm8550-suspend-lab-runs/20260919T185748Z-restore-inspection/`.

This makes the earlier SLEEP-word variation more specific. Before run `20260919T181557Z-cb567ba69946`, the per-consumer PCIe request was 1,000,000 kB/s and the Apps-RSC MC0/SH0 SLEEP payload was `0x600003b8` (952). Before runs `20260919T182725Z-0615b49b6039` and `20260919T184853Z-e2c0a82feb60`, the PCIe request was 500,000 kB/s and the payload was `0x600001dc` (476). The payload scales exactly at 0.000952 per requested kB/s across these observations. In the 1,000,000 run, the PCIe `icc_set_bw` transition to 500,000 is only observed during resume, after the SLEEP batch; in the 500,000 runs there is no PCIe update before SLEEP. This strongly associates the variable 476 with the PCIe client's pre-suspend request and explains why the all-client change trace alone did not identify it: the relevant request was already active when tracing began.

This is not yet a unique attribution of every bit of the SLEEP payload. Other CPU, GPU, and PMU ICC requests also differ between the 1,000,000 and 500,000 snapshots, and the summary is an awake point-in-time request view rather than an in-suspend firmware-residency report. Keep the interpretation as a strong correlation, not proof that PCIe alone causes the payload or the zero AOSD/CXSD/DDR counters. The harness already captures ICC client rows in its pre/post summary JSON. Next take one matched 10-second direct-deep run on the restored `pcie_ports=compat` boot, with radios preserved, and correlate the immediate pre-run per-client request with the submitted MC0/SH0 SLEEP words and qcom_stats deltas. This adds no kernel build and changes no power or ICC policy.

### 2026-09-19 19:04 UTC — restored-boot deep repeat confirms the 1,000,000-to-952 mapping

Run `20260919T190341Z-5a7c0e91bb3a` completed on the restored boot ID `4508b1ed-cfbd-43a1-a37e-ccee2a163a20`, image `20260915.feca679`, kernel `7.2.3`, with `pcie_ports=compat` and both radios preserved. Direct `deep` was requested and observed; the same-boot clock separation was `7.696697` seconds, the expected RTC alarm fired, and Wi-Fi SSH returned. The runner removed its trace instance and run-specific kretprobe.

The immediately pre-run `interconnect_summary` again showed the PCIe consumer at `avg_bw=0`, `peak_bw=1,000,000` kB/s on the LLCC/EBI memory path. The final Apps-RSC SLEEP TCS then submitted `0x600003b8` (952) to both MC0 (`0x50000`) and SH0 (`0x50004`). Only after wake did the PCIe callback issue `icc_set_bw` requests at `peak_bw=500,000`. This reproduces the earlier 1,000,000 kB/s -> 952 observation on the original compat boot and supports treating the final SLEEP payload as tied to the pre-suspend PCIe request. It still does not prove that PCIe is its sole contributor.

The same cycle again left the scalar AOP/RPM AOSD, CXSD, and DDR records unchanged at zero. Separate ADSP/APSS subsystem SMEM records advanced (`adsp` +15, `apss` +1); DDR raw LPM ID `0xd0` duration advanced by `201,647,727` ticks while `0x11`, `0xd3`, and `0xd4` stayed at zero. The D3cold check still vetoed on Qualcomm root port `0000:00:00.0` (`vendor=0x17cb`, `device=0x0113`, `PCI_UNKNOWN=5`, return `-EOPNOTSUPP`). Thus the cycle confirms observed deep-mode entry, successful wake, and a nonzero SLEEP request, but it does not prove AOP accepted a particular physical residency state. Artifact: `../sm8550-suspend-lab-runs/20260919T190341Z-5a7c0e91bb3a/`.

The smallest next source-level check is to establish what the standard `rpmh_tx_done` trace covers for asynchronous SLEEP TCS writes and whether this 7.2.3 image exposes any successful-path TCS state readback. The prior inventory says `rpmh:rpmh_rsc_snapshot` is absent on this image and the four `qcom_aoss` debugfs endpoints are mode-0200 write-only controls, not readable blocker counters. Do not write them. If source confirms the existing trace cannot establish SLEEP TCS application/acknowledgment, the remaining exact no-kernel-build boundary is firmware residency visibility; the next implementation-quality experiment would need an observation-only RSC snapshot on a matching 7.2.3 kernel or equivalent vendor firmware telemetry, not another ICC policy change.

### 2026-09-19 19:16 UTC — upstream RSC traces cannot acknowledge SLEEP TCS application

Checked the exact Linux stable `v7.2.3` implementation. `rpmh_send_msg`'s printed `complete` field is assigned from `tcs_cmd.wait`, so `complete=0` on the observed SLEEP records means no response wait was requested; it does not mean a command was unfinished or rejected. The `tcs_tx_done()` interrupt handler and `rpmh_tx_done` trace are for `ACTIVE_ONLY` transfers. The source also states the AP triggers active-only transfers but does not trigger sleep/wake TCS values; `__tcs_buffer_write()` programs the command slots and enables them for the RSC/firmware low-power path. References: [trace field assignment](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/trace-rpmh.h#L26-L34), [active-only TX-done handler](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L402-L445), [sleep/wake trigger and TCS programming](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L342-L357) and [buffer write](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L450-L486).

A current-boot bounded read-only inventory confirms there is no `rpmh:rpmh_rsc_snapshot` event in the running `7.2.3` kernel. Available relevant events are `rpmh_send_msg`, `rpmh_tx_done`, `qcom_aoss:aoss_send{,_done}`, and PSCI domain idle entry/exit. `/sys/kernel/debug` has `qcom_stats` records and only four `qcom_aoss` controls; those controls are mode `0200` write-only files and reject reads with `EINVAL`. No `qcom_sleep_stats`, CXPC dump, or PM-violator interface was found in the bounded path inventory. No control file was written. The full debugfs path listing and event inventory are under `../sm8550-suspend-lab-runs/20260919T190341Z-5a7c0e91bb3a/device/post-readonly/`.

This means the present trace establishes that Linux staged the nonzero MC0/SH0 SLEEP request, but its send/done tracepoints cannot establish whether firmware actually triggered or accepted that SLEEP TCS. The earlier observation-only `7.2.0` RSC snapshot already showed configured/enabled sleep TCS commands with clear command status, yet it still did not expose AOP-selected AOSD/CXSD/DDR residency; the earlier source comparison found no RPMh or qcom_stats implementation changes between `v7.2` and `v7.2.3`. Rebuilding only to restore that register snapshot on `7.2.3` is therefore unlikely to answer the central question. We need a read-only AOP/firmware residency diagnostic or vendor telemetry to distinguish firmware selection from stats-record behavior; do not infer the missing state from the BCM word, and do not write AOSS/QMP or guessed MMIO.

The USB cable does not currently provide an Android ADB path: `adb devices -l` is empty on the Mac, and macOS reports no connected Nova USB device. The post-run device remains on the same Linux boot with `pcie_ports=compat`, Wi-Fi returned, the root port unbound, and the run's trace/kprobe cleanup complete. The 2.8 MB `rpm-ostree status` crash dump created by this inspection was removed; the older unrelated rpm-ostree coredump was left untouched.

### 2026-09-19 19:24 UTC — live RPMh resource and decoded records confirm Linux is reading the expected layout

On the restored Armada Linux boot (`4508b1ed-cfbd-43a1-a37e-ccee2a163a20`, kernel `7.2.3`), the live platform device `c3f0000.sram` has compatible `qcom,rpmh-stats` and is bound to `/sys/bus/platform/drivers/qcom_stats`. Its Device Tree `reg` bytes decode as resource start `0x0c3f0000`, size `0x400` (end `0x0c3f03ff`). Thus the mainline fixed record locations are `0x0c3f0048` for the three SoC records and `0x0c3f00b8` for DDR detail, both inside the declared resource.

A privileged read of the driver's existing debugfs output returned `aosd`, `cxsd`, and scalar `ddr` records, each with count, timestamps, and accumulated duration all zero. The separate `ddr_stats` file is present and has a nonzero raw `0xd0` LPM duration (`count=1`, `36582912306` ticks at this snapshot); `0xd4`, `0xd3`, and `0x11` remain zero. Upstream qcom_stats creates SoC files from the type words at its configured fixed offset and only creates `ddr_stats` after validating the DDR magic key at its configured DDR offset ([stable v7.2.3 qcom_stats.c](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L152-L183), [RPMh offsets](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L361-L368)). This is strong live evidence that Linux's `+0x48` / `+0xb8` mapping lands on the expected record formats; the zero SoC counters are not explained by a globally wrong qcom_stats resource or missing DDR record. The kernel source documents the numeric DDR LPM IDs but does not define what `0xd0` means, so the nonzero detail must not be treated as proof of a particular residency state.

This Linux snapshot did not itself read Android's pointer words, but the live Android probe had already captured them earlier on 2026-09-19 (00:07 UTC), and the 01:34 UTC Android refresh revalidated them. The values are `0x000f0048` and `0x000f00b8`; after `resource_start | raw_value`, they resolve to the same `+0x48` and `+0xb8` locations used by Armada. The Android evidence is recorded below at 00:07 and 01:34 UTC; the Linux readout is independent confirmation of the Linux-side mapping, not a still-open Android offset question.

Readout receipt: `../sm8550-suspend-lab-runs/20260919T1924Z-live-qcom-stats-readout/device/readout.txt`. Reading `ddr_stats` follows the driver's ordinary read path, which sends its built-in DDR frequency-sync request to AOP; no AOSS control, guessed MMIO, or explicit QMP command was issued. No persistent device security or kernel change was made.

The Mac still enumerates no ADB device (`adb devices -l` is empty), and `system_profiler SPUSBDataType` currently lists no USB device. This rules out using this cable as a present ADB transport; it does not establish why USB is not enumerating.

Next: compare the Android and Armada PM request paths and firmware-facing votes. The shared effective offsets and record layout rule out an address/layout mismatch; do not change Armada's stats offsets based on the zero counters.

### 2026-09-19 19:40 UTC — Android boot media identifies a matching diagnostic module without rebooting

Read-only inspection of the Android A/B partitions on UFS found identical boot payloads in both slots: `boot_a` and `boot_b` SHA-256 `3e143173f3112984b012f4bf69f9d5172ffdc913550723e3056ffc9de367d26c`; `vendor_boot_a` and `vendor_boot_b` SHA-256 `89a73c967f6305932fac5e397628e07b4c81c24bf08723f72538c48be054eec4`. The Android boot image is v4 and its embedded ARM64 kernel identifies as `5.15.123-android13-8-g697b78910a71-dirty`, built with Android clang 14.0.7 on `Mon Jul 20 10:48:54 UTC 2026`. Its embedded config has `CONFIG_MODULES=y`, `CONFIG_MODVERSIONS=y`, `CONFIG_MODULE_SIG=y`, and does not set `CONFIG_MODULE_SIG_FORCE`.

The v4 `vendor_boot` ramdisk is LZ4-compressed and packages `lib/modules/subsystem_sleep_stats.ko` (32,960 bytes), `soc_sleep_stats.ko` (35,400 bytes), `qcom_cpuss_sleep_stats.ko` (27,880 bytes), and `smem.ko`. The extracted subsystem module reports vermagic `5.15.123-g697b78910a71-dirty SMP preempt mod_unload modversions aarch64`, has the `qcom,subsystem-sleep-stats` / `qcom,subsystem-sleep-stats-v2` compatible strings, and depends on `soc_sleep_stats.ko` and `smem.ko`. It is therefore a loadable driver packaged with the Android image, not the 5.15 built-in image. The first-stage `modules.load` list does not name it, while `modules.dep` lists it as a dependency of `sys_pm_vx.ko`; packaging alone does not prove that Android loaded or bound it at runtime.

The `vendor_boot` DTB payload contains ten concatenated FDTs. Every one includes `/soc/subsystem-sleep-stats@c3f0000` (`qcom,subsystem-sleep-stats`) and `/soc/soc-sleep-stats@c3f0000` (`qcom,rpmh-sleep-stats`), both with `reg = <0xc3f0000 0x400>`. That is the same 0xc3f0000/0x400 SRAM resource exposed by Armada Linux, and every Android DTB variant carries the downstream driver node. The current Android DTB variant is not distinguished here, but all ten share this resource and compatible pair.

Artifacts are under `../sm8550-suspend-lab-runs/20260919T1924Z-live-qcom-stats-readout/android/` (boot headers, extracted DTB, selected vendor modules, and `modules.load`/`modules.dep`). No Android partition was written and the device was not rebooted for this offline image inspection. Its statements that runtime pointer values and module binding remained uncollected were superseded by the earlier live Android captures at 00:07 and 01:34 UTC.

Next: locate the exact source revision for `g697b78910a71`, inspect the vendor module load path, and determine whether this exact config plus available symbol-version metadata supports a small standalone module rebuild. Do not replace/load a diagnostic module until vermagic, modversions, module signature policy, dependent modules, and recovery are checked. If static proof is insufficient, the remaining required step is a short Android boot with a compatible diagnostic capture that logs the two already-read pointer words and their computed bases; Linux's fixed-offset results do not substitute for that runtime readout.

### 2026-09-19 19:45 UTC — Android debugfs driver also resolves the firmware pointer words

Correction to the preceding Android entry: `soc_sleep_stats.ko` is the more direct counterpart to Armada's `qcom_stats` debugfs interface, and it uses the same downstream pointer scheme. In the public source snapshot at `93c5cc6ad1d0b807510cfa0fb1d06f47407881f9`, `soc_sleep_stats_probe()` reads the word at `res->start + config->offset_addr`, computes `stats_base = res->start | raw`, maps that base, then repeats the operation for DDR; the RPMh config uses `offset_addr=0x4` and `ddr_offset_addr=0x1c` ([probe and mapping](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/soc_sleep_stats.c#L514-L579), [RPMh config and compatible](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/soc_sleep_stats.c#L655-L689)). It builds Android's `qcom_sleep_stats` debugfs records (not Armada's `qcom_stats` path). `subsystem_sleep_stats.ko` separately reads those same pointer words for its `/dev/stats` ioctl interface ([Android subsystem probe](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/subsystem_sleep_stats.c#L458-L527)). Therefore, if the earlier Android counters were read from `/sys/kernel/debug/qcom_sleep_stats`, `soc_sleep_stats` is the driver whose existing probe should be instrumented; the exact provenance of the earlier Android readout is not recorded, so this remains the likely path rather than a confirmed runtime binding.

The extracted `soc_sleep_stats.ko` has the same Android kernel vermagic as `subsystem_sleep_stats.ko`, is listed in `modules.dep` with `smem.ko` as a dependency, and exposes the RPMh compatible. Neither sleep-stats module appears in the vendor ramdisk's first-stage `modules.load`; `sys_pm_vx.ko` depends on both in `modules.dep`. This proves packaging and dependency metadata, not that the drivers were loaded on the prior Android boot. Android `/proc/modules` and the bound platform-driver symlinks are still needed to confirm runtime state.

The image's embedded kernel release hash `g697b78910a71` does not resolve as a public commit in `Ayn8550Dev/android_kernel_ayn_qcs8550`; that repository does contain the earlier public source snapshot `93c5cc6...`, but it is not proven to be the exact source revision for this dirty image. Consequently we have enough static evidence to target the right probe, but not yet enough to build or substitute a module safely. The updated smallest diagnostic target is `soc_sleep_stats_probe()`: log each resource range, the two values it already reads, and their computed bases immediately after those reads, without adding new MMIO accesses. Do this only against a source/config/toolchain/Module.symvers combination validated for the extracted image.

### 2026-09-19 19:51 UTC — correct Android debugfs path and interface distinction

The `soc_sleep_stats` source creates its debugfs root as `/sys/kernel/debug/qcom_sleep_stats`; it reads each SoC record's type word from the computed bases to name the `aosd`, `cxsd`, and `ddr` files, and only creates `ddr_stats` if the computed DDR base contains magic `0xA1157A75` ([Android debugfs creation](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/soc_sleep_stats.c#L457-L507)). The companion `subsystem_sleep_stats` driver creates `/dev/stats` for its ioctl interface. Armada's mainline driver creates `/sys/kernel/debug/qcom_stats` and uses fixed offsets. I corrected the preceding notebook entry's path label accordingly.

The earlier Android kprobe receipt preserves the path: it captured the stock `soc_sleep_stats` probe's own `readl_relaxed()` return values, then observed the normal record signatures and DDR magic at the computed bases. The 01:34 UTC refresh also confirmed `soc_sleep_stats` was loaded and bound. Therefore the raw words, computed bases, and runtime driver path are established; the remaining gap is why Linux and Android firmware counters differ during low-power operation.

### 2026-09-19 20:08 UTC — direct trace of the stats copy is blocked by `notrace`

Confirmed the branch is clean and synced through `20784cb` before continuing. On the live Linux boot, a private tracefs instance and temporary kprobe event targeting `memcpy_fromio` were attempted while reading only `/sys/kernel/debug/qcom_stats/aosd`. Registration returned `EINVAL`; the kernel log identifies the cause exactly: `trace_kprobe: Could not probe notrace function memcpy_fromio`. The event and instance were removed by the cleanup trap, and a privileged follow-up confirmed `/sys/kernel/tracing/kprobe_events` is empty and the instance is absent. No suspend, MMIO read, device setting, or boot state changed. The Mac still sees no USB/ADB device.

The running kernel exposes local kallsyms entries for `qcom_soc_sleep_stats_show` and `qcom_stats_probe`, and has `/sys/kernel/btf/vmlinux`. Upstream v7.2.3 `qcom_soc_sleep_stats_show()` obtains the pre-mapped `stats_data` from `seq_file->private`, then passes `stats_data->base` to the notrace copy helper ([reader](https://raw.githubusercontent.com/gregkh/linux/v7.2.3/drivers/soc/qcom/qcom_stats.c#L120-L136)). This leaves a possible no-build path: probe the non-`notrace` show function and use bounded structure-field fetches to capture its existing `private->base` pointer during a normal file read. It must be tested on Linux first and must not add MMIO reads. If that works, apply the same technique to Android's `soc_sleep_stats_show()` after Android is reachable; the low page offset of its existing ioremap pointer can identify the resolved record offset. This remains a proposed technique until the exact running-kernel field offsets and trace output are validated.

### 2026-09-19 20:13 UTC — caller probe recovers the mapped Linux stats offset without a build

Used the running Armada kernel's BTF to get exact field offsets (`seq_file.private` at byte 104; `stats_data.base` at byte 8), then added a temporary kprobe event on the non-`notrace` `qcom_soc_sleep_stats_show()` function. Reading `/sys/kernel/debug/qcom_stats/aosd` produced one event with `base=0xffff8000800e5048`; the low-page offset is `0x48`, matching the bound driver's fixed SoC-stat offset from resource `0x0c3f0000`. The kprobe only dereferenced the existing `seq_file->private->base` kernel pointers; the debugfs reader's normal `memcpy_fromio()` remained the only MMIO access. This validates a no-build trace technique for recovering the effective mapped offset on the running kernel. Raw output and recipe: [caller-probe receipt](receipts/2026-09-19-live-qcom-stats-show-probe.txt).

The probe and private trace instance were removed; a privileged follow-up verified the global kprobe event list empty and the instance absent. No suspend or device setting changed. This Linux result confirms its effective base is `+0x48`, consistent with the already-recorded Android values from 00:07/01:34 UTC. The offset question is closed; the remaining work is to compare the actual firmware-facing PM requests and interpret the mode counters. USB currently enumerates no ADB device, but no Android reboot is needed to answer the offset question.

### 2026-09-19 20:23 UTC — correction: Android pointer words were already captured

The compact handoff omitted the live Android result at 00:07 UTC and its 01:34 UTC refresh. Those entries and `receipts/2026-09-19-soc-sleep-kprobe-values.txt` already contain the stock module's raw reads: `0x000f0048` from `resource+0x4` and `0x000f00b8` from `resource+0x1c`. With the Android resource `0x0c3f0000`, the downstream `resource_start | raw` expression resolves to `0x0c3f0048` and `0x0c3f00b8`, exactly matching Armada/mainline `+0x48` and `+0xb8`. The stock path also read `aosd`, `cxsd`, and `ddr` signatures plus DDR magic. This decisively rules out an offset mismatch; no offset patch or Android module build is needed.

The 19:24, 19:40, 19:45, and 19:51 notes above incorrectly described these Android runtime values or the probe provenance as unknown. The 20:08/20:13 continuation initially repeated that mistake because the handoff summary omitted the earlier entries. Treat those uncertainty statements as superseded by the 00:07/01:34 receipts and this correction. The 19:24 Linux resource address also had a missing leading zero; it is now corrected to `0x0c3f0000` (the prior text `0xc3f00000` was numerically wrong). The current Linux caller-probe receipt is likewise corrected.

Remaining task: explain why Android's successful low-power path advances AOSD/CXSD/DDR while Armada's matched reader reports zeros during its suspend paths. Existing paired evidence and the Android-versus-Armada RPMh/PSCI request differences are journaled earlier at 13:11–13:17 UTC; continue from those records instead of repeating the pointer-word experiment. The Mac still sees no USB ADB device, so do not reboot away from the working Linux SSH session without a demonstrated recovery path.

### 2026-09-19 20:32 UTC — live regulator and interconnect snapshot matches the staged-request hypotheses

On the current Linux boot (`4508b1ed-cfbd-43a1-a37e-ccee2a163a20`, kernel `7.2.3`, `[s2idle] deep`, `pcie_ports=compat`), a privileged read-only snapshot still reports zero count, timestamps, and accumulated duration for `qcom_stats/{aosd,cxsd,ddr}`. The complete raw `interconnect_summary` and `regulator_summary` are saved in `receipts/2026-09-19-live-pm-readout.txt`.

The awake interconnect summary reports the PCIe consumer (`1c00000.pcie`) at `avg=0`, `peak=500000` kB/s on both `llcc_mc@interconnect-1` and `ebi@interconnect-1`; the same peak appears on its PCIe/LLCC memory paths. This matches the 500000-kB/s snapshot associated in the earlier matched deep runs with MC0/SH0 SLEEP payload `0x600001dc` (476). It strengthens the correlation between the active PCIe OPP request and the staged BCM floor, but the awake snapshot does not prove that PCIe is the only vote contributor or that the floor is the cause of zero AOSD/CXSD/DDR counts.

The current regulator summary shows Armada's single `vreg_l1e_0p88` at `normal` / 880 mV and `vreg_l3e_1p2` at `idle` / 1200 mV. Android's separately captured SLEEP TCS instead sets LDOE1 low-power mode and disables LDOE1/LDOE3, with WAKE restoring them. The Linux regulator summary is an awake active-state view; it cannot establish what firmware applied during a later low-power interval. Together with the source audit showing mainline RPMh regulators submit ACTIVE_ONLY requests, this confirms a concrete request-policy mismatch worth addressing in a controlled experiment, but not a proven cause.

No suspend was triggered and no kernel, boot, regulator, ICC, or power policy was changed. The least risky next step is to identify whether the live PCIe ICC request can be naturally removed by an already-supported system state transition without breaking Wi-Fi/resume, then capture the resulting SLEEP payload and counters. Do not manually lower the vote or disable LDOE rails: that would alter power policy without knowing its hardware safety requirements. If no reversible supported transition exposes a clean A/B, the smallest decisive implementation experiment is a temporary diagnostic kernel change that adds read-only visibility into SLEEP/Wake TCS buffer contents at the pre-suspend boundary; it still cannot prove AOP acceptance, so vendor AOP telemetry remains necessary for that final distinction.
### 2026-09-19 20:45 UTC — canonical checklist and Android PCIe source lead

The user reset the active investigation scope: do not repeat the closed stats-offset experiment; compare Android/vendor and Armada PCIe suspend paths first, then attribute the MC0/SH0 floor, then audit LDOE1/LDOE3 sleep contexts. Do not deploy a behavioral patch until source comparison supports a safe one-variable A/B. The new canonical checklist is [investigation-status.md](investigation-status.md); this notebook remains chronological so prior evidence and corrections are retained.

Current Git branch is `feat/sm8550-suspend-lab` at pushed commit `334ef072b33b2392b75e03cb9594266163d825da`, later than the user's earlier `054766d5...` anchor.

Initial comparison of the nearby public Android source snapshot (`Ayn8550Dev/android_kernel_ayn_qcs8550`, commit `93c5cc6ad1d0b807510cfa0fb1d06f47407881f9`) found `drivers/pci/controller/pci-msm.c::msm_pcie_pm_suspend_noirq()`. If its DT boolean `qcom,apss-based-l1ss-sleep` is enabled and PARF reports the link in L1SS, this path sets the host's internal suspended/power-off state, disables controller clocks and GDSC, removes the PCIe ICC request with `qcom_pcie_icc_bw_update(..., 0, 0)` (`icc_set_bw(..., 0, 0)`), and powers down analog rails. It does not call Linux's `pci_host_common_d3cold_possible()` in this function. If the L1SS property is absent/false, it instead calls the vendor PME_TURNOFF/L23 suspend helper. Source locations: `pci-msm.c` lines 3853–3891, 7598–7600, 8574–8720, 9419 onward.

This makes the Android vendor path a plausible explanation for how its host can remove the ICC request despite Armada's root-port `PCI_UNKNOWN` D3cold veto. It is not yet a confirmed Nova runtime path: Android's available kernel is only a nearby public match, the running kernel hash `g697b78910a71-dirty` is not matched to it, and Nova's active DT property/driver binding and endpoint power-state ordering remain unknown. Android logs from an earlier run show WLAN suspend/WoW activity, but do not establish endpoint D3 state or that this specific host branch ran.

No device setting, kernel, vote, regulator, or boot state changed during this source review. The source audit must now verify Android DT/property selection and resume flow, then compare mainline v7.2.3 and patches 0513/0520 before selecting any A/B. Keep the established constraints in the checklist: no manual ICC changes, forced D-state, `pcie_ports` changes, shared-rail shutdown, AOSS/QMP writes, or guessed MMIO. USB/ADB was absent in the last host check; the working Linux SSH route is Wi-Fi.
### 2026-09-19 21:06 UTC — D3cold veto explains why patch 0513 leaves the deep OPP active

Read the upstream v7.2.3 `qcom_pcie_suspend_noirq()` fallback together with Armada patches 0513/0520 and OPP-core semantics. The generic DesignWare callback returns success without setting `pci->suspended` when `pci_host_common_d3cold_possible()` is false. The Qualcomm driver then takes its fallback: in direct deep (`PM_SUSPEND_MEM`), it deliberately does not disable its CPU ICC path or alter the OPP, because late DBI accesses during S2RAM may require that path. Armada patch 0513's suspend-OPP helper call remains nested in the non-`PM_SUSPEND_MEM` branch for this fallback, so patch 0520's 1,000 kB/s suspend OPP is not selected in direct deep. Thus, if the running device is using the OPP path, its active PCIe OPP remains while the host is unsuspended. This resolves the apparent 0513 contradiction and is consistent with, but does not prove sole attribution of, the observed 500,000/1,000,000 kB/s pre-suspend PCIe request and 476/952 MC0/SH0 SLEEP values.

The OPP core confirms that `dev_pm_opp_set_opp(dev, NULL)` would set every attached interconnect path to `avg=0, peak=0`; that operation is not reached in the D3cold-vetoed deep fallback. The 0513 change therefore does not itself force an unsafe floor or misrepresent PCI state. The branch choice is inherited from the upstream fallback safety model. Sources: [v7.2.3 qcom noirq callback](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-qcom.c#L2026-L2078), [DesignWare D3cold early return](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-designware-host.c#L1143-L1208), [OPP null bandwidth handling](https://github.com/gregkh/linux/blob/v7.2.3/drivers/opp/core.c#L1080-L1104), [Armada 0513](../../../armada-packages/kernel/patches/0513-PCI-qcom-honour-an-opp-suspend-opp-as-the-non-s2ram-memory-floor.patch), [Armada 0520](../../../armada-packages/kernel/patches/0520-arm64-dts-qcom-sm8550-add-a-pcie-suspend-opp.patch).

Source comparison also found a public LineageOS Android DT overlay repository at commit `b2b4a398c40bde8642925eb475e3ebe66d9fe505`, including RP6/Nova Android overlay files. The RP6 overlay marks `hardware = "rp6"` and board ID but does not declare `qcom,apss-based-l1ss-sleep` itself. It includes a board base overlay outside that small repo, so this does not establish the merged Android DT property. A separate AYN vendor DT release sets the property in generic Kalama HDK files for AYN products; that is a nearby source, not evidence about Retroid's boot DT. Android kernel source remains a nearby match (`93c5cc6...`), not the observed `5.15.123-android13-8-g697b78910a71-dirty` build.

The Armada RP6 DT rail map is now explicit: LDOE1 supplies PCIe PHY, DSI0 PHY, and USB HS PHY. LDOE3 supplies DSI0, PCIe PHY PLL, UFS PHY PLL, USB HS PHY, and USB/DP QMP PHY. RP6 disables DSI1. This explains why a sleep-only PMIC request may be safe only after each consumer's suspend/wake contract is accounted for; the current TCS capture does not identify those contracts. Mainline `qcom-rpmh-regulator` sends state changes as ACTIVE_ONLY and exposes no suspend callbacks. A proper mainline route would model a generic regulator suspend constraint and issue SLEEP-state RPMh commands through regulator ops, with request ownership and wake behavior validated, not copy downstream proxy flags wholesale.

No source change or device behavior test occurred in this review. The existing harness already stores all awake per-client interconnect rows and `icc_set_bw` events; the kernel summary does not expose final per-client SLEEP-bucket contributions. Therefore we have not added an attribution calculator that would overstate what the data means. Next priority is to resolve the Android RP6 merged-DT/property/build source and inspect the exact RSC/bcm-voter aggregation and path-client mapping. Until then there is no safe behavioral A/B: dropping the deep OPP while the host stays unsuspended conflicts with the source's explicit late-DBI safety branch, while a vendor-style L1SS host-off path requires endpoint/WoW wake validation.

### 2026-09-19 21:22 UTC — awake ICC rows do not explain the final SLEEP word

Applied the Linux v7.2.3 interconnect and BCM-voter arithmetic to the saved
19:03 awake `interconnect_summary` receipt (`20260919T190341Z-5a7c0e91bb3a`).
If those requests were unchanged and tagged for SLEEP, MC0/SH0 would produce
`vote_x=525`, `vote_y=2034`. The same run's staged SLEEP TCS is instead
`0x600003b8` for both MC0 and SH0: `vote_x=0`, `vote_y=952`. Before the TCS,
the trace shows GPU, UFS, and display request changes; the PCIe request has no
matching update. Thus the awake calculation is a counterfactual, not exact
SLEEP attribution. The PCIe request remains a strong candidate for the 952
peak floor, but the TCS word alone does not prove it is the only contributor.

The tracepoint exposes `icc_set_bw` values but not each request's tag/enabled
state at final aggregation. Tiny QUP requests appear near staging, but their
tag membership is not captured; the zero `vote_x` is evidence that the awake
average set was not simply retained. Do not add a final-vote calculator based
only on the awake summary. A useful read-only harness extension needs an exact
observation of request tag/enabled state after suspend callbacks and before
BCM aggregation.

### 2026-09-19 21:57 UTC — Android DTBO candidates found [header interpretation superseded]

The previous Android preflight captured `ro.boot.slot_suffix=_a` and the
Retroid Pocket Nova/Kalama build fingerprint in
`receipts/2026-09-19-android-deep-rpmh/android-root-live-preflight.txt`. While
the device remained booted into Linux, I copied the 24 MiB Android
`/dev/disk/by-partlabel/dtbo_a` partition over SSH using a read-only `dd` and
saved its SHA-256 as
`1bd16dd02a532121fa1b1b3f5d3aa23c7916e880b40ae43678574c381fd3b1a5`. The
initial header interpretation in this note reversed `dt_entry_size` and
`dt_entry_count`, incorrectly calling the image a 32-entry, 56-byte table.
The corrected standard-table parse is recorded below. A bounded FDT-structure
scan found seven actual zero-length `qcom,apss-based-l1ss-sleep` properties,
at blob offsets
`0xab90d9`, `0xb14610`, `0xb71079`, `0xbcd704`, `0xbde786`, `0xbf2d89`, and
`0xc185b9`; they appear under `fragment@28`, `fragment@30`, or `fragment@42`
overlay nodes. The raw summary is in
`receipts/2026-09-19-android-dtbo-a-scan.txt`.

This proves those candidate overlays exist in the Android A-slot image, not
that ABL selected them for the Nova or that the APSS/L1SS callback ran. The
available public RP6 overlay source does not declare this property. I also
found a separate `DECLARE_PCI_FIXUP_SUSPEND_LATE` in the nearby Android
`pci-msm.c`; that root-bus fixup invokes `msm_pcie_pm_suspend()` for the
PME_TURNOFF/L23 route, independently of the platform `suspend_noirq` hook.
We need the exact PM-core ordering and actual selected property before saying
which host power-down branch produced Android's residency.

No device boot, PCIe state, ICC vote, regulator state, or Wi-Fi state changed.
Linux remains reachable through SSH; USB ADB is still absent on the Mac.

### 2026-09-19 22:08 UTC — correction: standard DTBO table; entry 51 matches RP6 IDs

I reversed two adjacent DTBO header fields in the 21:57 parse. The AOSP order
is `dt_entry_size` followed by `dt_entry_count`; the image says 32-byte entries
and 56 entries, not 56-byte entries and 32 entries. I re-parsed the same
read-only image `/tmp/nova-dtbo-a.img` (SHA-256 unchanged at
`1bd16dd02a532121fa1b1b3f5d3aa23c7916e880b40ae43678574c381fd3b1a5`) using
those standard 32-byte records and checked the property in each FDT structure.
The corrected raw table and candidate metadata are in
`receipts/2026-09-19-android-dtbo-a-scan.txt`.

Entry 51 at offset `0xb71079` (378,507 bytes) has
`qcom,msm-id=<0x25b 0x20000>`, `qcom,board-id=<0x1001f 0>`, and model
`KalamaP HDK`. Those IDs match the public RP6 Android DT source (`603` decimal
is `0x25b`). Its `fragment@30/__overlay__` contains both
`qcom,apss-based-l1ss-sleep` and `qcom,no-client-based-bw-voting`. This is a
strong candidate match, not proof of runtime selection: `fragment@30/target`
is a fixup placeholder, and we have not established ABL's selected overlay or
inspected the merged Android runtime tree. The earlier “56-byte vendor table”
wording is superseded, not an additional firmware difference.

No device state changed. Next resolve the entry's `__fixups__` target and look
for a safe way to establish the selected/merged DT without rebooting away from
the current Linux access path. Do not repeat the closed stats-offset probe.

### 2026-09-19 22:23 UTC — Android PCIe noirq ordering separates two suspend paths

Resolved entry 51's overlay target fixup: `__fixups__.pcie1` patches
`/fragment@30:target:0`, whose `target` word is otherwise `0xffffffff`. The
base-DT symbol path for `pcie1` is not present in the available device-tree
checkout. The overlay also has a second pcie1 target fixup at `fragment@32`;
the L1SS and `qcom,no-client-based-bw-voting` additions are specifically in
`fragment@30/__overlay__`. The bounded parse is in
`receipts/2026-09-19-android-dtbo-a-scan.txt`.

The nearby public Android kernel at `Ayn8550Dev/android_kernel_ayn_qcs8550`
commit `93c5cc6ad1d0b807510cfa0fb1d06f47407881f9` makes the two possible host
power-down routes and their ordering explicit:

1. `msm_pcie_pm_suspend_noirq()` is attached to the `pci-msm` platform
   controller driver. If the host is enumerated and `power_on`, the property
   path polls PARF L1SS bit 8; on success it disables config access, clocks,
   GDSC, and analog rails, and `qcom_pcie_icc_bw_update(..., 0, 0)` clears the
   PCIe ICC request. This branch does not assert endpoint PERST or set the PCI
   function to D3. If link L1SS is not confirmed, it returns without shutting
   the host down.
2. The driver separately registers `DECLARE_PCI_FIXUP_SUSPEND_LATE` for
   Qualcomm PCI devices. For a root-bus PCI device with the link enabled, the
   fixup calls `msm_pcie_pm_suspend()`: it saves/loads config state, sends
   PME_TURNOFF, polls L23, selects sleep pins, then calls
   `msm_pcie_disable()`. Disable sets `power_on=false`, asserts endpoint reset,
   and disables controller resources. Its `msm_pcie_clk_deinit()` clears the
   ICC request with `icc_set_bw(..., 0, 0)`.

In this tree, the controller calls `devm_pci_alloc_host_bridge(&pdev->dev)`,
so the PCI host bridge is a child of the platform device. The root PCI device
is below that bridge. DPM's noirq parent callback waits for subordinate
children; `pci_pm_suspend_noirq()` invokes the PCI `SUSPEND_LATE` fixup at its
end. Therefore, **if the root PCI device is not skipped and its fixup runs**,
that fixup powers the controller down before the platform noirq callback. The
latter then sees `power_on=false` and skips its `enumerated && power_on`
body, so the APSS/L1SS property branch did not produce that cycle. If the root
PCI device is skipped, the platform callback can still take the APSS/L1SS
route. This conditional ordering is source-proven; which branch the Android
run actually took is not.

This revises the earlier shorthand that the APSS/L1SS route was the likely
Android explanation. The existing Android capture shows the WCN driver
successfully armed firmware WoW and completed bus suspend, but has no PCIe
fixup/host callback log. It does not establish which root-port suspend
callback ran, what D-state the WCN endpoint reported, or whether PME_TURNOFF
and PERST were used. Do not conflate successful WCN bus suspend with root-port
or endpoint D3 state.

Relevant public-source line ranges (nearby source only; image kernel
`5.15.123-android13-8-g697b78910a71-dirty` is not matched to this commit):

- [Android PCIe ICC helper and L1SS property parse](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L3853-L3905), [property read](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L7598-L7602)
- [Android host noirq route](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L8574-L8728), [resume route](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L8730-L8876)
- [Controller platform driver and host bridge allocation](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L8920-L8933), [root-bus fixup](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L9420-L9558), [clock teardown removes ICC](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L4031-L4054)
- [PCI noirq runs the late fixup](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/pci-driver.c#L812-L897), [DPM parent waits for child callbacks](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/base/power/main.c#L1203-L1253), [host bridge parent and root bus hierarchy](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/probe.c#L623-L635)

### 2026-09-20 00:18 UTC — read-only ICC attribution profile prepared; device remains unreachable

The v7.2.3 interconnect source supports a direct read-only attribution method.
`icc_summary_show()` and `aggregate_requests()` traverse each node's `req_list`
in the same hlist order. While `aggregate_requests()` visits those rows, the
Qualcomm RPMh provider callback receives each request's `tag`, `avg_bw`, and
`peak_bw`; the ordinary `icc_set_bw` tracepoint then reports the node's generic
sum/max. This makes a live callback trace mappable to a fresh
`interconnect_summary`, provided the request list and tags do not change and
the callback rows reproduce the generic aggregate. Sources: [summary list
traversal](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L48-L69),
[aggregation traversal](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L255-L283),
[ICC update and tracepoint](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L673-L720),
[Qualcomm RPMh aggregation](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/icc-rpmh.c#L69-L104),
[SLEEP tag bits](https://github.com/gregkh/linux/blob/v7.2.3/include/dt-bindings/interconnect/qcom,icc.h#L7-L21).

I added the local-only `icc-attribution` harness profile. It probes the
Qualcomm aggregation callback for EBI/LLCC nodes, plus ICC path creation,
release, and tag changes; it uses the pinned Linux 7.2.3 release and BTF hash
before dereferencing `icc_node.name` at offset `0x8`. The report labels client
rows only when the fresh summary matches, no list/tag mutation occurs before
the last observed Apps-RSC SLEEP group, trace buffers are lossless, callback
count/tag order matches the summary, and callback sum/max matches
`icc_set_bw`. A mismatch now explicitly fails closed and leaves client names
unassigned. It captures the observed SLEEP messages and checks per-TCS command
indexes for continuity; it does not establish AOP acceptance or physical
residency.

Local verification passed: `py_compile`, `tests/sm8550-suspend-lab-test.sh`,
and `git diff --check`. A synthetic negative case confirms mismatched generic
aggregates do not receive client labels. This profile has not yet run on the
Nova. A fresh read-only access check at 00:18 UTC timed out on SSH to
`192.168.0.20:22`; `adb devices -l` showed no device. No device state or
behavior was changed, and no behavioral A/B is selected. The exact Android
kernel source/build and merged runtime DT remain unverified; a web search for
the reported build suffix did not identify an exact matching vendor tree, so
the nearby public `Ayn8550Dev` source remains explicitly provisional.

The working tree is on `feat/sm8550-suspend-lab`, still at pushed tip
`7ccf2b52bdcebe32f5bc145f937238f5b4449a99`; the harness and status-page edits
are local and not yet committed or pushed. When Linux SSH returns, the next
test is one 10-second direct-deep run with Wi-Fi/Bluetooth preserved and
`--trace-profile icc-attribution`. The full command is in
[investigation-status.md](investigation-status.md). If the profile fails any
guard, keep the floor attribution unresolved; do not infer a client from the
awake snapshot or change a vote.

### 2026-09-20 00:26 UTC — Android PCIe DT bandwidth property is handled; both host-off routes clear ICC

Correction to the quick web-page source inspection: GitHub's rendered code
search did not expose the `qcom,no-client-based-bw-voting` handler. I checked
the actual sparse checkout of the exact nearby public commit
`93c5cc6ad1d0b807510cfa0fb1d06f47407881f9` and found the property read in
`pci-msm.c`. It is not ignored in that source. With the property set,
`qcom_pcie_icc_bw_update()` converts the link-speed table times link width into
an average vote and sets peak to zero; otherwise it uses fixed average/peak
constants. At suspend, `speed == 0` clears either form with `icc_set_bw(0,0)`.

More significantly, each source-visible Android host-off route clears the
PCIe request: the APSS/L1SS noirq path calls the zero vote directly, and the
root-bus suspend-late fixup disables the controller through
`msm_pcie_clk_deinit()`, which also clears the vote. This makes a retained
Armada PCIe request a stronger request-generation explanation: Linux's
D3cold eligibility veto returns before host teardown, and Armada 0513 leaves
the active deep OPP in that path. The observed 500,000/1,000,000 kB/s to
476/952 MC0/SH0 association remains correlation until the new live callback
profile attributes the final SLEEP inputs; even exact attribution would not
alone prove that the vote blocks AOSD/CXSD/DDR residency.

Source links (nearby public Android source, not matched to the running
`g697b78910a71-dirty` kernel): [ICC vote helper](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L3853-L3905),
[DT property parsing](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L7598-L7603),
[L1SS host path clears ICC](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L8645-L8665),
[controller teardown clears ICC](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L4031-L4050).

No runtime path selection, device test, kernel build, or behavior change
occurred. The source result refines the leading hypothesis but does not justify
forcing D3hot/D3cold, dropping the active vote manually, or changing shared
regulators. Need the device back on Armada for the read-only attribution run;
the exact Android source/build and selected DT overlay are still open.

### 2026-09-20 00:32 UTC — Android awake PCIe vote matches the fixed-vote branch, not the candidate property branch

The saved Android `interconnect_summary` provides an additional check on the
candidate DTBO property. Under `llcc_mc` and `ebi`, the PCIe request is exactly
`tag=0, avg=500, peak=800`; the same row is visible on `qnm_pcie`. In the
nearby public `pci-msm.c`, those are the exact `ICC_AVG_BW=500` and
`ICC_PEAK_BW=800` constants used when `no_client_based_bw_voting` is false.
When the property is true, the helper instead calls `icc_set_bw(width * bw,
0)`, using a speed-indexed 250000/500000/1000000/... average and zero peak.
The stored 500/800 row therefore suggests the public driver's
`no-client-based-bw-voting` flag was false for this request at capture time.
This is an inference, because the captured Android kernel/build and runtime
merged DT have not been matched to that public commit, and the DTBO target
symbol `pcie1` has not been resolved to the `1c00000` request path.

This means the DTBO's `qcom,no-client-based-bw-voting` entry is not evidence
that the observed Wi-Fi PCIe request used the dynamic average-only branch.
It also does not affect the stronger suspend-path finding: in either
source-visible Android host-off route, the PCIe driver clears its request
with `icc_set_bw(0,0)`. Receipts: [Android interconnect summary](../../receipts/2026-09-19-android-deep-rpmh/android-interconnect-summary.txt);
[rooted Android build identity](../../receipts/2026-09-19-android-deep-rpmh/android-root-live-preflight.txt).
Source: [fixed constants and bandwidth helper](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L248-L249),
[property-selected vote form](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L3853-L3905).

### 2026-09-20 00:39 UTC — Separate the Android aborted attempt from its RTC-resumed deep entry

Cross-checking the Android run wrapper against the kernel excerpt shows two
events, not one ambiguous wake: log sequence 45500 reports `Wakeup pending,
aborting suspend` with `timerfd` active after the Wi-Fi driver logs an IRQ and
WLAN-triggered wake; sequence 45536 then starts another explicit deep entry.
That second entry takes CPUs offline, and sequence 45581 reports
`pm8xxx_rtc_alarm` as `pm_system_irq_wakeup`. The wrapper records the RTC alarm
was armed and captures the kernel log after the ten-second test window. This
supports RTC as the recorded wake IRQ for the deeper retry; it does not show
that Wi-Fi/PCIe cannot wake that state, nor that the first aborted attempt
reached the same residency. Updated the status row to preserve that distinction.

Receipt: [Android run wrapper](../../receipts/2026-09-19-android-deep-rpmh/android-icc-suspend-run.log)
and [kernel excerpt](../../receipts/2026-09-19-android-deep-rpmh/android-icc-suspend-excerpt.txt).


### 2026-09-20 01:54 UTC — Live ICC trace completed but client attribution failed closed

The corrected tracefs control writes allowed one 10-second direct-deep profile to
complete on the Nova (`20260920T015417Z-a3b217e2e4c0`). Linux 7.2.3 entered
`PM: suspend entry (deep)`, returned successfully in the same boot, and the
boottime-minus-monotonic interval measured 8.568 seconds; resume latency was
1.998 seconds. The observed wake was the armed RTC alarm (IRQ 199). Wi-Fi was
connected again after resume and both rfkill entries remained unblocked. No
radio or power policy was changed. AOSD, CXSD, scalar DDR, and the detailed DDR
LPM IDs showed no residency increment in this short interval; that still does
not prove whether the firmware accepted any particular staged request.

The run captured six contiguous Apps-RSC SLEEP commands. CMD_DB maps `0x50000`
to MC0 and `0x50004` to SH0; both final words were `0x600001dc` (476 in the
encoded vote field). Trace stats showed zero overruns or dropped events on all
eight CPUs. However, no client was attributed: the qcom callback's node names
were rendered as replacement characters, and the parser correctly refused to
assign clients. The full receipt is
`../../sm8550-suspend-lab-runs/20260920T015417Z-a3b217e2e4c0/`.

The trace exposed two instrumentation defects, not a device failure. First,
`icc_node.name` is a `char *`; the kprobe fetch used `:string`, which read the
member location as string storage and emitted garbage. Kernel kprobe docs say
`string[1]` fetches a `char *` array and is equivalent to the required nested
pointer dereference ([kprobetrace docs](https://cdn.kernel.org/doc/html/latest/trace/kprobetrace.html)).
Second, `path_init` was counted globally: this trace contained 19,468 such
initializations, most unrelated to the three EBI/LLCC targets, so treating any
one as a target-node list mutation made the guard overly broad. The local
harness now fetches the node pointer plus its `string[1]` name and captures the
`path_init` destination pointer, so the parser can scope additions to actual
target nodes. Its local py_compile, harness self-test, shell test, and
`git diff --check` pass. This corrected instrumentation has not yet been
validated on-device; rerun only if the next trace can either map all target
clients cleanly or name a specific remaining guard failure.


### 2026-09-20 02:03 UTC — PCIe is the only nonzero sleep-tagged EBI/LLCC client in Linux

The second read-only `icc-attribution` run (`20260920T020326Z-96e366a5fe0a`)
returned from direct deep suspend successfully: 8.783 seconds of observed sleep,
1.918 seconds resume latency, same boot ID, and the armed RTC wake. Wi-Fi was
connected after resume; both radios remained unblocked. The original run status
is `failed` only because the harness cleanup validator rejected its own
run-owned `icc_path_init` definition against a stale expected definition. The
device resumed successfully. A later root-only check found that this one event
was still in the global kprobe registry even though the trace instance was
gone. I removed that exact unique run-owned event with a non-truncating
tracefs write and verified the registry has zero entries and no matching
trace instance. Future profile setup no longer installs the unnecessary global
`path_init` probe, and cleanup metadata now matches that older definition.

The raw 6.5 MB trace had zero lost events on every CPU. It recorded all 18
requests at each of `qns_llcc@24100000.interconnect`,
`llcc_mc@interconnect-1`, and `ebi@interconnect-1`; request count and tag order
match the fresh interconnect summary, the `icc_set_bw` aggregate matches the
provider callback sum/max, and no callback or target update was unmatched. The
original host parser did not recognize tracefs's brace-wrapped `string[1]`
node-name form. Reprocessing the unchanged trace with that rendering handled
now passes all checks; the full corrected result is saved separately at
`../../sm8550-suspend-lab-runs/20260920T020326Z-96e366a5fe0a/host-analysis/icc-aggregate-attribution-reparsed.json`.
The original device-derived JSON and raw receipt remain untouched.

For each of the three target nodes, the only nonzero request whose tag includes
the SLEEP bucket is `1c00000.pcie`: `tag=7`, `avg_bw=0`, `peak_bw=500000`.
Every other SLEEP-tagged request at those nodes is zero. Thus this capture
attributes the retained Linux SLEEP-bucket floor to the PCIe client, rather
than merely correlating an awake request with a later BCM value. The final
Apps-RSC SLEEP words for MC0 (`0x50000`) and SH0 (`0x50004`) were both
`0x600001dc` (encoded vote 476); six commands were captured with contiguous
indexes. This establishes the source of the staged floor and its matching
value in this run. It does not prove the 476 floor is what prevents firmware
from recording AOSD/CXSD/DDR residency: all three sleep-stat deltas remained
zero, and staged RPMh commands are not a readback of AOP acceptance or rail
state.

The small harness cleanup is local. Local py_compile/self-tests/shell test and
`git diff --check` pass after adding brace-wrapped trace-field parsing and
removing system-wide `path_init` as a false mutation signal. The existing
receipt itself provides the live data to validate the parser; no third suspend
run is needed for this attribution result.

### 2026-09-20 02:15 UTC — Verify and remove the prior run's leftover kprobe

The read-only root inspection showed one stale event owned by the 02:03
profile: `s2lab_20260920T020326Z_96e366a5fe0a/icc_path_init`. The cleanup
validator had refused it because its expected definition did not include the
captured arguments. I removed only that exact event by writing its
`-:group/event` command with `O_WRONLY` and no truncation. A privileged
readback then showed zero entries in `/sys/kernel/tracing/kprobe_events` and
no matching private trace instance. The boot ID and Wi-Fi connection remained
unchanged. No suspend, PCI config, ICC vote, or power policy was touched during
cleanup.

### 2026-09-20 02:34 UTC — The candidate Android L1SS property targets a different PCIe host

Read-only SSH confirms the Nova is awake on Armada Linux 7.2.3 with Wi-Fi up
and boot ID `45137c86-bb9a-4021-9973-4bc6200fc9e6`. The active WLAN endpoint
`0000:01:00.0` (`17cb:1107`) is below root port `0000:00:00.0` (`17cb:0113`)
under `/sys/devices/platform/soc@0/1c00000.pcie`; the live FDT says
`soc@0/pcie@1c00000` is `okay` and `soc@0/pcie@1c08000` is `disabled`.
Both PCI devices currently report `power/wakeup=disabled`; this awake-state
setting is not evidence of their suspend-time wake configuration.

The public LineageOS QCS8550 devicetree at commit
`a345661c01d7e18b7dfa04dd27690655ff36bd5d` maps `pcie0` to `0x1c00000`
(domain 0) and `pcie1` to `0x1c08000` (domain 1). Its generic KalamaP HDK
overlay adds `qcom,apss-based-l1ss-sleep` and
`qcom,no-client-based-bw-voting` to `&pcie1`, not `&pcie0`. The public
Retroid Pocket 6 device overlay includes the Moorechip common DTSI, which
disables `&pcie1`. The Android DTBO partition's matching `KalamaP HDK` entry
therefore proves only that a matching candidate overlay carrying the property
exists; it does not prove the property applies to the active Wi-Fi host or
that the bootloader selected/merged that candidate. The public tree is a
nearby source match, not the exact source for the captured Android build.

This narrows the likely Android comparison. The public Android PCIe driver
also registers a separate root-device `SUSPEND_LATE` fixup, independent of
`apss-based-l1ss-sleep`. For an enabled root-bus link it saves PCI state,
disables config access, sends PME_TURNOFF, polls for L23, then calls
`msm_pcie_disable()`, which asserts endpoint PERST and deinitializes the host;
that deinit clears the PCIe ICC vote. If that fixup ran on pcie0, it could
explain the staged request difference without the special L1SS property. It
would also power down the WCN link rather than establish Wi-Fi wake from the
deep state. Android's captured suspend log records WCN WoW/bus-suspend success
before entry and an RTC alarm as the wake on the successful deep retry; it
does not show whether the root fixup ran or prove WCN wake from the deep state.

Sources: [public Kalama PCIe nodes](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalama-pcie.dtsi#L5-L18),
[pcie1 node](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalama-pcie.dtsi#L299-L312),
[HDK sleep properties](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalamap-hdk.dtsi#L36-L40),
[RP6 disables pcie1](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/moorechip/kalamap-moorechip-common.dtsi#L44-L46),
[RP6 overlay identity](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/moorechip/kalamap-retroid-pocket-6-overlay.dts#L4-L11),
[nearby Android root suspend fixup](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L9419-L9559).

No device state, suspend policy, or PCI configuration was changed. Exact
Android source/build, selected overlays, and runtime suspend branch remain
unknown.

### 2026-09-20 02:52 UTC — Linux host mapping cross-check and LDOE consumer map

The Nova is still on the same Armada Linux boot and was checked read-only over
SSH: kernel 7.2.3, boot ID `45137c86-bb9a-4021-9973-4bc6200fc9e6`, WLAN up.
Root `0000:00:00.0` and WCN7850 `0000:01:00.0` are both awake in D0 at Gen2 x1;
the root port is unbound and the endpoint is bound to `ath12k_wifi7_pci`; the
endpoint's parent is `soc@0/1c00000.pcie`. The live FDT says
`pcie@1c00000` is `qcom,pcie-sm8550` and `pcie@1c08000` is disabled. Both
devices currently report `power/wakeup=disabled`; that is only an awake-state
policy read, not evidence about the suspend wake path. `lspci` is absent, so
no further config-space capability decoding was attempted. No suspend or
power-control change was made. Raw snapshot:
`../../receipts/2026-09-20-live-pcie-cross-check.txt`.

The nearby public LineageOS Kalama/RP6 device-tree source maps `pcie0` to
`0x1c00000` and `pcie1` to `0x1c08000`; the RP6 common DTSI disables `pcie1`.
DTBO entry 51's `qcom,apss-based-l1ss-sleep` and
`qcom,no-client-based-bw-voting` properties target `pcie1`. This means that
candidate property is not evidence that Android used its APSS/L1SS host path
for the active WLAN controller. The exact Android base DT, selected overlay,
and runtime path are still unavailable; this public tree remains a nearby
source match only. A separate public root-device `SUSPEND_LATE` fixup can
shut down the host/link and clear its ICC request, but the existing Android
receipt contains staged RPMh commands and an RTC wake, not proof that this
fixup ran.

The nearby Android RP6 DT wires LDOE1/LDOE3 across shared interfaces:
LDOE1 supplies PCIe's 0.9-V PHY, UFS QREF, USB EUSB2, DSI PHY, and DP PHY
analog; LDOE3 supplies PCIe 1.2-V PHY/PLL, UFS PLL, USB EUSB2, USB3/DP QMP
core, and DSI 1.2-V PHY. RP6's display overlay selects its DSI0 panel, while
the board common DTSI disables DSI1. Thermal I-sense reference inputs use
separate active-only L1E/L3E proxy regulators. These are device-tree supply
edges, not evidence those blocks remain active in sleep.

The Android capture stages LDOE1 into LPM then disables it for SLEEP, disables
LDOE3 for SLEEP, and restores both on WAKE. The successful deep retry woke by
RTC. It demonstrates one suspend/resume with those staged requests; it does
not validate Wi-Fi/PCIe or USB wake, or prove that the rail requests were the
cause of AOSD/CXSD/DDR residency. This keeps the regulator A/B unsafe to infer
from the trace alone.

No device files, PCI state, votes, suspend policy, or kernel behavior were
changed. The current source conclusion remains that Android host shutdown is
the strongest explanation for why its PCIe ICC request disappears, while the
retained PCIe request itself has not been shown to prevent residency.

### 2026-09-20 02:54 UTC — Saved Android logs do not identify the PCIe suspend hook

Searched the saved Android suspend wrapper, kernel excerpt, root preflight, and
awake/hook receipt for the public driver's distinctive `RC0`/`RC1`, PME_TURNOFF,
L23, L1SS, endpoint-reset, ICC-clear, and `suspend_noirq` messages. The only
match was the generic kernel `pm_suspend` stack frame; the receipts contain no
PCIe-driver trace that establishes whether the active pcie0 root-device
`SUSPEND_LATE` fixup or the APSS/L1SS host path ran. This is absence from the
preserved receipts, not evidence that either path did not run. Exact runtime
branch identification needs a new Android log with suitable PCIe driver
logging or a direct branch marker. No device state was changed.

### 2026-09-20 03:08 UTC — Android's default ICC tag includes SLEEP; endpoint API adds another PCIe path

Fetched the nearby public Android source at pinned commit
`93c5cc6ad1d0b807510cfa0fb1d06f47407881f9` and checked its RPMh ICC
aggregator against the exact Linux v7.2.3 source. In both, `qcom_icc_aggregate()`
normalizes `tag=0` to `QCOM_ICC_TAG_ALWAYS`; the binding defines that as
AMC, WAKE, and SLEEP. Therefore Android's saved PCIe request (`tag=0`,
`avg=500`, `peak=800`) would be included in the SLEEP bucket if that request
remained unchanged. Given the final Android MC0/SH0 SLEEP TCS words are zero,
the request was likely cleared or changed before the final aggregation. This
is a source-based inference conditional on the nearby public implementation
matching the captured vendor build; it does not identify the code path. Sources:
[Android aggregator](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/interconnect/qcom/icc-rpmh.c#L66-L95),
[Android tag definitions](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/include/dt-bindings/interconnect/qcom,icc.h#L14-L24),
[Linux aggregator](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/icc-rpmh.c#L84-L105),
[Linux tag definitions](https://github.com/gregkh/linux/blob/v7.2.3/include/dt-bindings/interconnect/qcom,icc.h#L14-L24).

The Android PCIe driver exposes a third relevant route through its client
control API. `MSM_PCIE_DRV_SUSPEND` sends an RPMsg to the client, changes
`link_status` to `MSM_PCIE_LINK_DRV`, restricts config/MSI access, disables
unsuppressible clocks, and clears the PCIe ICC vote with
`qcom_pcie_icc_bw_update(..., 0, 0)`. It can then request L1SS sleep. The
separate `MSM_PCIE_SUSPEND` mode coordinates a full link suspend. If a client
driver calls `MSM_PCIE_DRV_SUSPEND` before the root-device `SUSPEND_LATE`
fixup, the fixup's `link_status == ENABLED` guard will return early. This
provides another plausible explanation for removal of the saved default-tag
vote, and the Android log's successful WCN bus-suspend message makes it worth
checking. The public kernel tree does not contain the proprietary WCN/CNSS
call site, and preserved Android receipts do not show either API being called;
this remains an unverified path, not a runtime finding. Sources:
[driver suspend](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L9877-L9944),
[PM control API](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L9951-L10073),
[root fixup guard](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L9524-L9558).

The user confirmed the Nova is currently on Armada Linux. A fresh read-only
SSH check at 03:08 UTC used the same boot ID (`45137c86-bb9a-4021-9973-4bc6200fc9e6`):
`wlp1s0` had carrier, and both the Qualcomm root port and WCN7850 were
D0/runtime-active with `power/control=on`, `power/wakeup=disabled`, and
`d3cold_allowed=1`. Unprivileged sysfs exposed only the first 64 bytes of each
PCI config space; both capability lists start at `0x40`, so this did not reveal
their PCI PM capability. The `d3cold_allowed` flag alone does not establish
that D3 is supported or wake-safe. Full output: `../../receipts/2026-09-20-live-pcie-pm-readout.txt`.

After the privileged capability read, a separate read-only check confirmed
the live `/proc/cmdline` still has `pcie_ports=compat`, the root port is
enabled but unbound, and WCN7850 is enabled and bound to `ath12k_wifi7_pci`.

No device state changed. The source audit now establishes that an untagged
Android request would ordinarily belong to SLEEP and that multiple source-
visible PCIe paths can clear it. The exact Android path is still unknown, and
the staged-request difference still does not prove the Linux 476 floor blocks
firmware residency. No behavioral A/B is justified yet.

### 2026-09-20 03:25 UTC — PCI PM capability exists; current compat-mode root veto is software state

The user had authorized device admin access. A one-shot privileged, read-only
`od` of the two PCI config spaces read 256 bytes each; no configuration was
written and no service or policy changed. Both root `0000:00:00.0` (`17cb:0113`)
and WCN7850 `0000:01:00.0` (`17cb:1107`) have a PM capability at `0x40` with
bytes `01 50 03 c8 08 00`: capability ID `0x01`, next capability `0x50`,
PMC `0xc803`, PMCSR `0x0008`. Linux v7.2.3's `pci_regs.h` definitions decode
this as PME supported from D0, D3hot, and D3cold (not D1/D2); PMCSR reports
D0 and PME enable clear. Both devices' sysfs `power/wakeup` is disabled in
the current awake state. Raw values: `../../receipts/2026-09-20-live-pcie-pm-capabilities.txt`.

The v7.2.3 PCI core explains the previously observed root-port veto on the
current boot. `pcie_ports=compat` leaves the root port unbound. In
`pci_pm_suspend_noirq()`, a device with no PM ops has config saved and jumps
to `set_unknown`; `pci_pm_set_unknown_state()` changes D0 to `PCI_UNKNOWN`
because firmware may alter it during suspend. The D3cold walker skips an
unbound device only if it is also disabled; the root is enabled, so the next
state check rejects it because it is not D3hot. This matches the captured
`pdev_state=5` veto and means missing PME/D3 hardware support is not the
current compat-mode failure. Sources: [PCI noirq fallback](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci-driver.c#L883-L950),
[D0-to-unknown fallback](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci-driver.c#L624-L636),
[D3cold per-device predicate](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/pci-host-common.c#L286-L310),
[PM capability bits](https://github.com/gregkh/linux/blob/v7.2.3/include/uapi/linux/pci_regs.h#L247-L263).

Important boundary: the earlier one-shot pcieport-binding test also observed
`PCI_UNKNOWN`. The unbound-device path explains the current `pcie_ports=compat`
boot but not that bound-port result. A bound bridge can also be required to
remain in D0 when a child stays in D0; we do not have the contemporaneous
`skip_bus_pm`/endpoint state needed to confirm that explanation. Do not infer
that PME support alone makes host shutdown safe. Previous Wi-Fi-off testing
lowered MC0/SH0 from 952 to 476 but left AOSD/CXSD/DDR at zero, so the PCIe
request difference remains a request-generation explanation, not a complete
residency cause. No behavioral change or suspend run was made during this
read.

### 2026-09-20 03:29 UTC — Android boot and super partitions are available from Linux

Read-only `lsblk` shows the installed Android `super` partition and A/B
`boot`, `dtbo`, and `vendor_boot` partitions alongside Armada's separate boot
and root volumes. Android's dynamic `super` partition is not mounted. This
creates a possible offline route to identify the installed Android build and
inspect its vendor/WCN modules while keeping the device on Linux. No Android
partition has been read, mounted, or modified yet. Concise inventory:
`../../receipts/2026-09-20-linux-visible-android-partitions.txt`.

### 2026-09-20 03:34 UTC — validated the exact A-slot vendor_dlkm extent

Read only the first 256 KiB of `super` and parsed the AOSP v10.2 logical-
partition metadata. Geometry checksums, all four metadata header checksums,
and all four table checksums validate. The slot-0 map includes one read-only
linear `vendor_dlkm_a` extent of 128,798,720 bytes at super sector 10,979,328;
this is consistent with the Android boot previously reporting slot `_a`. This
gives a bounded way to inspect the installed CNSS/WCN module without mounting
or copying the 12 GiB `super` partition. No vendor extent has been read yet.
Details: `../../receipts/2026-09-20-android-super-layout.txt`.

### 2026-09-20 03:49 UTC — exact installed Android PCIe/WCN modules expose the suspend call chain

While the Nova remained on Armada Linux, I extracted only the previously
validated A-slot `vendor_dlkm_a` extent from the Android `super` partition.
Its installed `qca_cld3_kiwi_v2.ko`, `cnss2.ko`, and `pci-msm-drv.ko` all
carry vermagic `5.15.123-g697b78910a71-dirty`, matching the Android kernel
captured in the earlier rooted run. Build IDs, hashes, and read-only
disassembly evidence are in
`../../receipts/2026-09-20-android-exact-pcie-modules.txt`.

This closed an important source-availability gap: the exact installed WLAN
binary contains `wlan_hdd_pld_suspend()` calling
`wlan_hdd_bus_suspend()`, and the saved `kiwi_v2` bus-suspend-success line
comes from that path. A first-pass read suggested the CNSS bus path always
requested PCI state 3 (D3hot); that interpretation was too broad and is
corrected in the 05:20 entry below. The exact CNSS2 binary contains both host
suspend modes, and the exact host module contains APSS/L1SS noirq and
ICC-clear code. No device state changed and no new suspend was run.

### 2026-09-20 05:20 UTC — manual binary reconstruction narrows the Android branch

I disassembled the exact installed A-slot `qca_cld3_kiwi_v2.ko`, `cnss2.ko`,
and `pci-msm-drv.ko` from the read-only extraction. The crucial correction is
that the explicit endpoint D3hot calls in `cnss_pci_suspend_bus()` run only
when the saved DRV-connected byte is zero. A nonzero byte jumps over
`pci_clear_master()`, `pci_disable_device()`, and
`pci_set_power_state(..., 3)` before host link-down.

The CNSS suspend guard returns `-EAGAIN` when DRV support is enabled, the
disable-DRV quirk is clear, and the connection flag is false. Thus, if the
effective pcie0 DT enables DRV support and the quirk is clear, successful
CNSS suspend requires the connected path, which skips explicit endpoint
D3hot. The inspected base-DT variants contain `qcom,drv-name = "lpass"` on
pcie0, but the exact merged runtime DT, controller association, and quirk
state are not known.

`cnss_set_pci_link()` selects host mode 0 (DRV suspend) when the saved
connected flag is true; with it false, switch type 1 also chooses mode 0,
otherwise it chooses normal mode 1. The exact binary reads
`qcom,pcie-switch-type` into private offset `+0x1f08` and stores zero when
the property read fails. Scanned Android base DTs and DTBOs lack that
property, so those inputs default to zero.

The exact host module has three independent PCIe ICC-clear routes: DRV
`msm_pcie_drv_suspend()`, normal `msm_pcie_clk_deinit()` reached by
`msm_pcie_pm_suspend()` and the root-device late fixup, and the gated
APSS/L1SS `suspend_noirq` path. Each calls the helper that submits zero
average and peak bandwidth. The final SLEEP TCS cannot distinguish which
route ran. The candidate APSS/L1SS property is on pcie1 in the nearby public
RP6 tree, which disables pcie1 and places WCN under pcie0; exact overlay
selection remains unknown.

The saved Android log proves only that the WLAN bus-suspend callback
reported success. It has no `Use PCIe DRV suspend` marker, recorded
`drv_connected_last` value, or host-mode/root-fixup/noirq marker. Neither a
conditional PCI state request nor the final TCS proves actual endpoint state,
host power collapse, or Wi-Fi wake behavior. Detailed pseudo-C, symbol
offsets, evidence limits, and reproduction method are in
`../../receipts/2026-09-20-android-pcie-binary-decomp.md`. No device state
changed and no new suspend was run.

Next useful evidence is an Android log window from one successful suspend
containing CNSS DRV-connected state and `msm_pcie_pm_control()` mode, plus
root-fixup/noirq markers and merged-DT APSS/L1SS property state. No behavioral
A/B is justified until those facts distinguish the actual host route.

### 2026-09-20 06:16 UTC — Android boot reported, but current ADB transport is unavailable

The user reported switching the Nova to Android. The host checked the last
documented Wi-Fi ADB endpoint, `192.168.0.163:5555`: the peer answered ICMP,
but repeated ADB and TCP connection attempts to port 5555 were refused. ADB
mDNS advertised no services, and the Mac's USB registry showed only the
SanDisk Ultra external drive, not the handheld. Ports 22, 8022, 5556, and
37099 also refused. The peer's current identity is not authenticated by ADB.

The prior rooted Android capture documents `service.adb.tcp.port=5555` as
boot-scoped and `persist.adb.tcp.port` as empty, so the service may simply not
have been enabled for this boot. No runtime Android logs, module state, or
merged DT were collected in this attempt. No device setting, service,
security policy, boot mode, or partition was changed. Receipt:
`../../receipts/2026-09-20-android-access-check.txt`.

### 2026-09-20 06:27 UTC — Wireless ADB restored; merged Android DT narrows the PCIe route

After the user enabled Android Wireless debugging, ADB discovered the Nova at
`192.168.0.163:42265` over TLS; `su` is root. The running image is the same
Android fingerprint and 5.15.123 build previously inspected, slot `_a`.

The live merged DT identifies `KalamaP HDK`, MSM ID `<0x25b 0x200>`, and
board ID `<0x1001f 0>`, matching the public Nova DTBO candidate previously
identified as entry 51. It confirms that the active WCN host is
`soc/qcom,pcie@1c00000`, with `qcom,drv-name = "lpass"`; `qcom,drv-supported`
is absent. The exact installed CNSS binary falls back from the absent
`qcom,drv-supported` to `qcom,drv-name`, so DRV support is likely enabled on
pcie0. The disable-DRV quirk and live connected flag are still unknown.

The candidate `qcom,apss-based-l1ss-sleep` and
`qcom,no-client-based-bw-voting` properties are present only under
`pcie@1c08000`, which the runtime DT marks disabled. They are absent from
active pcie0, where WCN sits. This closes the merged-DT/overlay uncertainty:
the public L1SS overlay is not configuring the active WCN host.

One early suspend attempt in this Android boot logged WLAN bus-suspend
callback success, then aborted with `NETLINK` pending. `suspend_stats` shows
success 0 / fail 1 (`failed_suspend=1`, late/noirq failures zero), and AOSD,
CXSD, scalar DDR, and APSS stats remain zero. This boot therefore has no
successful suspend sample yet. The log does not prove whether PCIe noirq ran;
it contains no selected `msm_pcie_pm_control()` mode or DRV flag. The abort
occurred seconds after `adbd`/`mdnsd` startup, a timing correlation only.

Receipt: `../../receipts/2026-09-20-android-live-runtime.md`. No kernel,
module, PCI state, regulator, interconnect, DT, or power policy was modified.

### 2026-09-20 06:34 UTC — corrected Android suspend test path and cleaned RTC alarm

I attempted one direct `rtcwake -u -m mem -s 15 -d /dev/rtc0`, which returned
`xwrite: Device or resource busy`. The existing 2026-09-19 01:21 entry had
already established that Android's `system_suspend` service owns the
`wakeup_count`/`state` protocol and that direct `rtcwake -m mem` competes with
it; I should not have repeated this test. The RTC command left the wake alarm
at `153393`; I cleared it with the correctly quoted Magisk-root command and
verified the alarm file empty, `alarm_IRQ=no`, and `alrm_pending=no`.

The post-call kernel log contains another short s2idle entry/exit interval
(~38 ms), and suspend counters changed from `success=0, fail=1` to
`success=0, fail=2` (`failed_suspend=1`, late/noirq failures zero). AOSD,
CXSD, scalar DDR, and APSS records remain zero. This interval occurred while
the RTC alarm was armed, so I cannot attribute it to `rtcwake`; it is not a
successful suspend sample. No alarm remains armed.

The command form `adb shell su -c 'multi word command'` also did not preserve
quoting across ADB for some prior reads: audit entries show some `cat`
commands ran in `u:r:shell:s0`. Readable DT/debugfs values were obtained, but
all privileged commands will use the verified form
`adb shell "su -c '...'"` from here on.

Do not use direct `rtcwake -m mem` again. The next controlled Android run
should use the already-proven `service call suspend_control_internal 2`
(`forceSuspend()`) path with a short RTC wake, temporarily select deep, and
restore the original `mem_sleep`, debug flag, and alarm state after resume.
The previous successful Android run and exact cleanup sequence are in
`receipts/2026-09-19-android-deep-rpmh/` and
`receipts/2026-09-19-deep-stats/`.

### 2026-09-20 06:39 UTC — verified recovery after an unarmed force-suspend probe

I inadvertently invoked `service call suspend_control_internal 2` while
checking that the service was available, before arming a wake alarm. It
returned `false`. Read-only post-checks show the same boot ID
`d927cfaa-54f1-428d-9f3b-1298aa1982fc`, unchanged `[s2idle] deep` selection,
empty RTC alarm, and all-zero APSS/AOSD/CXSD/DDR records. `suspend_stats` is
success 0 / fail 3 (`failed_suspend=1`, `failed_suspend_noirq=0`). Dmesg has
an 84 ms s2idle entry/exit at uptime 1520.553879–1520.638005; its cause is
unknown. The service's read-only `--suspend_controls` snapshot shows one
failed attempt / zero total suspend time, and `--wakeups` lists one NETLINK
abort. I cannot attribute the short interval to the force call.

No RTC alarm or temporary sleep selection remains. The next service call will
only follow the notebook's already successful order: enable the downstream
read-only `/sys/kernel/debug/interconnect/debug_suspend` hook, select deep,
arm an 8-second PMIC RTC wake, then call `forceSuspend()`; restore the original
sleep selection, hook `0`, and clear any remaining alarm after return. This is
the smallest safe way to get the Android suspend-boundary ICC client snapshot.

### 2026-09-20 ~06:47 UTC — Android deep capture advances AOSD/CXSD/DDR

Wireless ADB was active on the same rooted Android boot. Preflight verified
boot ID `d927cfaa-54f1-428d-9f3b-1298aa1982fc`,
`mem_sleep=[s2idle] deep`, `debug_suspend=0`, empty `rtc0/wakealarm`, RTC
`alarm_IRQ=no`, and `suspend_stats` success 0 / fail 3. APSS, AOSD, CXSD, and
DDR counters were all zero.

Ran only the previously validated bounded path: enabled the read-only
`/sys/kernel/debug/interconnect/debug_suspend` hook, temporarily selected
`deep`, armed `rtc0` with `rtcwake -u -m no -s 8 -d /dev/rtc0`, verified the
nonempty alarm and `alarm_IRQ=yes`, then invoked
`service call suspend_control_internal 2`. It returned `true`. The kernel
logged `PM: suspend entry (deep)`, WLAN bus-suspend success, wake IRQ
`pm8xxx_rtc_alarm`, and `PM: suspend exit`. Suspend stats changed to success
1 / fail 3 (`failed_suspend=1`, `failed_suspend_noirq=0`).

The records, zero at baseline, then reported APSS `Count=1`, accumulated raw
duration `119285904`; AOSD `Count=165`, `111831600`; CXSD `Count=17`,
`112746986`; and DDR `Count=17`, `113022361`. Their raw last-enter/exit values
are preserved in `../../receipts/2026-09-20-android-deep-icc-followup.md`.
This confirms firmware-backed AOSD/CXSD/DDR records advanced during this
successful Android deep run. Do not treat their raw accumulated values as
wall-clock residency without checking the ABI units.

At `machine_suspend`, the hook printed two enabled ICC clients: DCVS DDR tag
3 with average `1593832`, peak `2188000` on `llcc_mc`/`ebi`; and DCVS LLCC tag
3 with average `2589968`, peak `4800000` on `chm_apps`/`qns_llcc`. No PCIe
client appeared. Tag 3 is ACTIVE_ONLY, excluding SLEEP. The snapshot is
consistent with Android clearing the PCIe request before the suspend
boundary, but it is not the final Apps-RSC TCS and does not reveal whether
connected-DRV, the root-device late fixup, or APSS/L1SS host suspend ran.

After resume, Wi-Fi reported connected, `wlan0` was `UP/LOWER_UP`, and
Wireless ADB remained available. The original `[s2idle] deep` selection was
restored, `debug_suspend=0`, the wakealarm was cleared (`alarm_IRQ=no`), and
the boot ID was unchanged. No permanent device change was made. Receipt:
`../../receipts/2026-09-20-android-deep-icc-followup.md`.

This supersedes the 06:39 statement that this Android boot had no successful
suspend. Do not repeat this identical capture. Next, inspect whether Android
exposes safe runtime tracing for the exact CNSS/PCIe module branch and
suspend-time PCI state; no behavioral A/B is justified from this capture
alone.

### 2026-09-20 ~07:10 UTC — exact Android CNSS branch and TCS captured

The read-only runtime-tracing audit found `CONFIG_KPROBE_EVENTS=y`, exact
loaded module symbols, and tracepoint formats for RPMh messages and BCM voter
commits. A temporary tracefs instance was created; global `tracing_on` stayed
0. The bounded instrumented capture used entry/return probes for the CNSS
suspend callbacks, PM-control mode, DRV/noirq/clock paths, and PCIe ICC helper,
plus Apps-RSC RPMh, BCM-voter, and PM-phase events.

At the actual successful system-suspend bracket, `cnss_pci_suspend()` and
`cnss_pci_suspend_bus()` returned 0. CNSS selected
`msm_pcie_pm_control(mode=0)`, entered `msm_pcie_drv_suspend()`, and called
`qcom_pcie_icc_bw_update(avg=0, peak=0)`. The resume path used mode 2. Given
the active pcie0 DT has no `qcom,pcie-switch-type` and the installed CNSS
binary defaults that field to 0, mode 0 identifies the connected-DRV path.
This resolves the successful Android host branch that was previously
unknown. The exact branch skips CNSS's explicit PCI D3hot calls; no probe read
the endpoint's actual PCI config state.

The host `msm_pcie_pm_suspend_noirq()` callback entry was observed, but
active WCN pcie0 lacks `qcom,apss-based-l1ss-sleep`. There were no hits for
`msm_pcie_pm_suspend()` or `msm_pcie_clk_deinit()` in the capture, consistent
with the root-device late-fixup clock-deinit route not running after the
link entered DRV state. The callback entry alone does not show that the
APSS/L1SS body ran.

The same bracket captured all 14 Apps-RSC TCS3 SLEEP and all 14 TCS5 WAKE
commands. MC0 (`0x50000`) was `0x40000000` and SH0 (`0x50004`) was `0` in
SLEEP; both are off/zero while the successful Android run advances APSS,
AOSD, CXSD, and DDR counters. LDOE1/LDOE3 sleep/wake words were present, and
the SLEEP set also includes SH1, QUP0/1/2, ACV, MC4, and SH5. The complete
payload table and trace are in
`../../receipts/2026-09-20-android-exact-pcie-branch.md` and
`../../receipts/2026-09-20-android-pcie-branch-trace.txt`. RPMh tracepoint
writes prove TCS staging, not AOP acceptance; counter advancement is the
independent firmware-recorded result.

The ADB shell lost transport during this run, then returned on the same
device/boot after the RTC wake. The kernel recorded `deep` success and
`pm8xxx_rtc_alarm`; sleep counters advanced again. I stopped tracing, removed
the instance and every kprobe, restored `[s2idle]`, verified `debug_suspend=0`
and an empty alarm (`alarm_IRQ=no`), and confirmed global tracing remained
off. No permanent device state changed.

This supersedes the 06:47 note that the Android PCIe branch remained unknown.
The strongest remaining causal hypothesis is now specific: Android's
connected-DRV route clears its PCIe ICC request and stages MC0/SH0 off,
while Armada's Linux path retains a SLEEP-tagged PCIe bandwidth request when
the D3cold eligibility check prevents host teardown. Correlation is strong,
but the regulator and request-set differences mean causation still requires
a source-validated, one-variable Linux test. Do not force PCI D3hot or bypass
the generic D3cold check. Next inspect whether the mainline ICC API can
exclude only the PCIe path's SLEEP bucket while retaining active/wake votes.

### 2026-09-20 ~07:34 UTC — Android PCI PM callbacks succeed without observed D-state setters

Wireless ADB was available on the same rooted Android boot. A bounded,
10-second RTC-woken `deep` capture used a temporary tracefs instance for
generic PM callbacks and kprobes for PCI suspend and power-state setter
functions. It did not repeat the CNSS-branch/TCS capture. The 4 MiB trace
buffer recorded 11,803 events without loss.

The Qualcomm host's normal `pci-msm` suspend callback returned `err=0`; the
generic root-port `0000:00:00.0` callback returned `err=0`; the WCN endpoint
`cnss_pci 0000:01:00.0` callback and its power-domain callback returned
`err=0`; the host and endpoint noirq suspend callbacks also returned `err=0`.
Matching noirq resume callbacks succeeded. No hits were recorded for
`pci_set_power_state()`, `pci_raw_set_power_state()`, or the generic PCI
suspend kprobes. This means no OS-issued D-state setter was observed in this
run; it does not reveal the endpoint's physical state while asleep.

After the RTC wake, the same boot remained available, both PCI functions read
D0, and `wlan0` was up. These are post-resume health checks only. I restored
`[s2idle]`, cleared the RTC alarm, stopped tracing, removed the trace instance
and probes, and checked `tracing_on=0`, empty `kprobe_events`, and
`debug_suspend=0`. The current read-only recheck confirms the same boot ID,
empty alarm, those controls restored, and Wi-Fi up. Receipt:
`../../receipts/2026-09-20-android-live-pcie-validation.md`.

### 2026-09-20 ~07:40 UTC — source audit rules out a simple ICC retag test

The v7.2.3 QCOM PCIe probe uses OPP-managed ICC whenever the DT has an OPP
table; on this SM8550 node it does, so `use_pm_opp=true` and the driver does
not retain direct `icc_mem`/`icc_cpu` path handles. At the live 5 GT/s x1 OPP,
the DT asks for 500,000 kB/s on the SLEEP-capable `pcie-mem` path and 1 kB/s
on ACTIVE_ONLY `cpu-pcie`, with `rpmhpd_opp_low_svs` as the required power
domain OPP. This matches the live Linux ICC attribution trace.

When `pci_host_common_d3cold_possible()` vetoes the controller, DesignWare
returns success before stopping the link or setting `pci->suspended`. The QCOM
driver takes its host-active fallback. Its direct-ICC variant lowers
`pcie-mem` to 1 kB/s, but the OPP-backed variant makes no OPP change for
`PM_SUSPEND_MEM`: Armada patch 0513 only calls its suspend-OPP helper in the
non-MEM branch of that fallback. Thus the active 500,000 kB/s OPP remains in
direct deep when the host is not suspended. This gives a concrete source path
for the observed retained floor without bypassing the PCI core.

The proposed tag-only test is not a small change here. `icc_set_tag()` only
updates path request metadata; `icc_set_bw()` performs aggregation and applies
the constraints. The OPP framework owns the ICC paths, and QCOM PCIe has no
handle to retag them. A static `ACTIVE_ONLY` DT tag would also remove the
1,000 kB/s SLEEP OPP floor used by patch 0520 for s2idle, risking the prior
hard-reset regression.

Selected next A/B, still only a design: for direct `PM_SUSPEND_MEM` with the
host unsuspended, set a test-only OPP with `required-opps` unchanged at
`rpmhpd_opp_low_svs`, memory-path peak reduced from 500,000 to 1,000 kB/s, and
CPU-path peak left at 1 kB/s. Use a unique synthetic 64-bit `opp-hz` without
`opp-level`, selected only by an explicit diagnostic helper. This isolates
bandwidth magnitude; it does not alter PCI state, regulator requests, or the
existing s2idle `opp-suspend` behavior. Do not deploy it on Android. The
experiment still needs a test-kernel build and a Linux boot, so no build or
device behavior change was started. Source receipts and links are in
`../../receipts/2026-09-20-android-live-pcie-validation.md`.

### 2026-09-20 07:42 UTC — wireless ADB validates the exact installed modules

The user enabled Wireless debugging. ADB connected to the same Android boot
and reported the already-known Kalama fingerprint, slot `_a`, and kernel
`5.15.123-android13-8-g697b78910a71-dirty`. `/proc/modules` shows `cnss2`,
`pci_msm_drv`, and `kiwi_v2` loaded. I pulled their installed
`/vendor_dlkm/lib/modules/*.ko` files read-only and recomputed SHA-256. All
three hashes exactly match the previously decompiled A-slot files. This
closes the concern that the earlier disassembly came from a different module
copy; it still cannot identify the exact vendor source commit.

The current post-run read-only check confirms same boot, both PCI functions
back in D0, `wlan0=up`, `[s2idle] deep`, no RTC alarm, global tracing off,
empty kprobes, and `debug_suspend=0`. No Android image, module, or persistent
configuration was modified. Receipt:
`../../receipts/2026-09-20-android-live-pcie-validation.md`.

### 2026-09-20 08:06 UTC — live BTF closes the Android noirq-body ambiguity

Wireless ADB is still on the same Android boot. I pulled the live split-BTF
for `vmlinux` and `pci_msm_drv` read-only and mapped the exact installed
`struct msm_pcie_dev_t` fields. This does not repeat the sleep-stats offset
experiment. The new facts are specific to the PCIe suspend control flow:

- `link_status` is at byte `0x480`; `apss_based_l1ss_sleep` is at `0x409`;
  `enumerated` is at `0x535`; `power_on` is at `0x6a4`.
- Exact `msm_pcie_drv_suspend()` disassembly writes `3` to `link_status`, the
  BTF-described `MSM_PCIE_LINK_DRV` enum value.
- The exact registered root-port `SUSPEND_LATE` CFI function reads the same
  field and continues to its teardown only when it equals `1`
  (`MSM_PCIE_LINK_ENABLED`). The earlier successful mode-0 trace shows the
  DRV suspend function ran, while its `msm_pcie_pm_suspend()` and
  `msm_pcie_clk_deinit()` callees had no hits. This is consistent with the
  fixup teardown being gated out; the fixup entry itself was not separately
  probed, so do not report its callback invocation as directly observed.
- The exact noirq function checks `enumerated`, `power_on`, and
  `apss_based_l1ss_sleep` and jumps to unlock/return if any is false. The
  active merged pcie0 DT has no `qcom,apss-based-l1ss-sleep`, the input for the
  last flag. Therefore this callback's APSS/L1SS teardown body was not
  selected in the captured build, despite seeing its callback entry. It could
  not be the route that cleared ICC or shut down its host clocks/regulators.

This narrows Android's observed PCIe request removal to the connected-DRV
route's explicit `0/0` ICC call for this run. It still does not prove physical
PCI/link state during sleep, AOP acceptance of each staged command, or
PCIe/WCN wake safety. Exact Android source remains unavailable; this is an
exact installed-binary reconstruction based on matching module hashes, live
BTF, relocations, and disassembly. Hashes and instruction addresses are in
`../../receipts/2026-09-20-android-live-pcie-validation.md`.

No further Android suspend was needed. Post-check remained on the same boot
with `wlan0=up`, `[s2idle] deep`, empty alarm, global tracing off, empty
kprobes, and `debug_suspend=0`.

### 2026-09-20 09:02 UTC — Nova-only PCIe bandwidth A/B prepared

- Wireless ADB is connected to the same rooted Android boot; all actions in
  this pass were read-only. The live regulator debugfs excerpt shows active
  `pm_v6e_l1`/`pm_v6e_l3` proxies and separate `*_so` sleep-only proxy rows.
  Awake-state consumers include PCIe 0.9 V (80 mA) and 1.2 V (18 mA), plus
  DSI0; UFS, USB, and DP consumers in the excerpt are inactive. This confirms
  runtime registration/accounting, not suspend-time physical rail state or
  whether PCIe/Wi-Fi wake remains powered. Receipt:
  `receipts/2026-09-20-android-regulator-summary-awake.txt`.
- The first proposed test OPP had been placed in the common SM8550 DTSI. I
  replaced that scope before any package/device change: the new synthetic OPP
  and a boolean opt-in now live only in the Nova-specific DTS proposal. The
  kernel branch invokes it only for the OPP-backed host-active
  `PM_SUSPEND_MEM` fallback. Its `required-opps` remains `low_svs`, and the CPU
  interconnect peak remains 1 kB/s; only the PCIe memory path changes from
  500,000 to 1,000 kB/s. The test never sets PCI state or alters the regular
  s2idle suspend OPP. Proposal files are under `proposals/`.
- Both proposal diffs pass patch checks. I copied the package kernel inputs to
  `/Volumes/NovaKernelBuild/armada-packages-partial`, inserted the candidate
  patch after 0513, and applied the full 145-patch package series against
  Linux 7.2.3. Every patch and Nova DTS edit applied; there were zero failures.
  A targeted build is now running for `drivers/pci/controller/dwc/pcie-qcom.o`
  and `qcom/qcs8550-retroidpocket-rpnova.dtb`; no Image, modules, or full
  kernel is being built. The work tree is isolated on the external volume.
- A first source extraction inside Docker failed with directory-rename errors
  on its external-volume mount. The incomplete generated tree was removed; the
  preserved archive was extracted successfully with host `bsdtar`. No source
  checkout or device files were modified. The current scratch target build is
  what matters; do not repeat the failed Docker extraction.
- Next: finish the two targets, check the object and DTB, then inspect the
  live Linux deployment/rollback preflight before asking for a device switch.
  Do not deploy this test to Android.

### 2026-09-20 09:09 UTC — targeted build passed; resume restore gap caught

- The first targeted scratch build completed successfully on the external
  volume: `drivers/pci/controller/dwc/pcie-qcom.o` and the Nova DTB were
  produced for Linux 7.2.3. The ARM64 object is 584 KiB with debug info and
  contains the diagnostic property/error strings. The 143,771-byte DTB
  contains both `armada,diag-pcie-mem-suspend-opp` and
  `opp-test-sleep-bw`. SHA-256: object
  `d9f774015ad7d1d06b7bbe1ed85d5a0978b0375bbc997940d6776f5b9474a5f2`, DTB
  `72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422`.
- Before any device deployment, I traced the corresponding resume callback.
  My first read missed the common tail call to
  `qcom_pcie_icc_opp_update()`. The callback does recalculate OPP from the
  negotiated link when `PCI_EXP_LNKSTA_DLLLA` is set. It does nothing if the
  link-status bit is clear, so the diagnostic OPP could persist in that edge.
  No device or package checkout was modified.
- Next inspect how this driver represents the live PCIe OPP and add a
  diagnostic-only restore that cannot leave the low OPP selected if the link
  is not up. Rebuild only the object and Nova DTB. Android remains on the same
  rooted boot with Wi-Fi ADB healthy, and no Android setting or file was
  changed.

### 2026-09-20 09:11 UTC — resume callback correction

The common tail of `qcom_pcie_resume_noirq()` calls
`qcom_pcie_icc_opp_update(pcie)`. That helper reads the live PCIe Link Status
register and selects an OPP from the negotiated width and speed when
`PCI_EXP_LNKSTA_DLLLA` is set. Thus the original candidate normally restores
the link's actual OPP on the expected host-active, link-up path. The residual
case is a down link: the helper returns early and leaves the selected OPP
unchanged. The earlier statement that the OPP always persists was too broad.
The test patch still needs a tracked fallback restore for that no-link edge;
no runtime deployment has occurred.

### 2026-09-20 09:22 UTC — revised Nova OPP candidate builds

- Added a private `diag_opp_active` flag set only after the diagnostic OPP
  transition succeeds. The resume callback restores the maximum OPP if that
  flag is set, then the existing link-state updater selects the actual
  negotiated OPP if DLLLA is present. A down link is left at the maximum
  bandwidth OPP, never at the reduced test OPP. The initial candidate is
  superseded; only the revised diff in `proposals/` should be considered.
- Applied and reversed the revised patch against the isolated tree to confirm
  its hunk boundaries. Built only `pcie-qcom.o` and the Nova DTB with the
  pinned Fedora 44 AArch64 builder. DTC decomp confirms the opt-in is present
  in the Nova pcie0 node and the 2 Hz OPP requests `low_svs`, 1,000 kB/s on
  PCIe memory, and 1 kB/s on CPU path. DTC reports duplicate unit addresses
  only in unrelated QUP nodes.
- Object SHA-256 is
  `bca7e626ae96c0ed7003b42eadc969f358db54ce433436743b6077ea243239d0`; DTB
  SHA-256 is
  `72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422`.
  Full kernel/modules, package artifact, bootc layer, and a device suspend
  test remain undone. Full command, artifact sizes, and checks are in
  `receipts/2026-09-20-nova-opp-target-build.md`.
- Wireless ADB still reports the same Android boot ID and `wlan0=UP`; no
  Android settings, modules, files, PCI state, ICC requests, regulators, or
  suspend policy were changed. Next verify the current Linux deployment and
  rollback path, then decide whether a full kernel artifact is warranted.

### 2026-09-20 09:24 UTC — live Android PCIe DT refresh

Wireless ADB still reaches the same Android boot and the live PCIe host's
`of_node` resolves to `/sys/firmware/devicetree/base/soc/qcom,pcie@1c00000`.
It contains `qcom,drv-name="lpass"`; `qcom,drv-supported`,
`qcom,pcie-switch-type`, and `qcom,apss-based-l1ss-sleep` are absent. Both
root port and WCN endpoint are awake at 5.0 GT/s x1 and D0. The CNSS module's
visible `*drv*` parameter lookup and filtered dmesg showed no runtime branch
marker; the previously captured kprobe/branch trace remains the evidence for
the successful connected-DRV run. This refreshed tree/state receipt is
`receipts/2026-09-20-android-live-dt-refresh.txt`. It was read-only; no
suspend was run and no device state changed.

### 2026-09-20 09:29 UTC — exact CNSS DRV-support fallback confirmed

Pulled `/vendor_dlkm/lib/modules/cnss2.ko` read-only over Wireless ADB; its
SHA-256 `7c23fc2fdf9a19b3ea2797eea377325c83cc5263df79c040b257908eb549c1b2`
matches the previously disassembled installed module. At
`cnss_pci_update_drv_supported()` (`.text+0x37870`), the exact AArch64 binary
calls `of_find_property()` for `qcom,drv-supported`, then, if absent, for
`qcom,drv-name`, and stores whether that property exists in its CNSS state at
offset `0x2f1`. It does not compare the driver-name string. The refreshed live
pcie0 node has no `qcom,drv-supported` and does have `qcom,drv-name="lpass"`,
so the exact binary marks DRV as supported for this host. Together with the
previous successful `msm_pcie_pm_control(mode=0)`/`msm_pcie_drv_suspend()`
trace and absent switch-type property (default 0), this establishes the
connected-DRV path for that run. The current awake read still cannot expose
the saved flag during sleep or physical PCI state. Receipt:
`receipts/2026-09-20-android-live-dt-refresh.txt`. No suspend or device change
was made.

### 2026-09-20 09:36 UTC — candidate PCIe driver is built into the kernel

Checked the exact Linux 7.2.3 scratch configuration used for the revised
targeted candidate build. It has `CONFIG_MODULES=y` and `CONFIG_PCIE_QCOM=y`;
the DWC Makefile maps the latter to `pcie-qcom.o`. The object exists, but
`pcie-qcom.ko` does not. Therefore the candidate cannot be deployed as a
module-only replacement: functional testing requires a linked kernel `Image`
plus the Nova DTB. This is a direct finding about the scratch target config,
not a new read of the installed Linux config. Exact values, hashes, and scope
are in `receipts/2026-09-20-pcie-qcom-linkage-check.txt`.

Wireless ADB is currently connected to rooted Android
`5.15.123-android13-8-g697b78910a71-dirty`, with `wlan0` up. No suspend or
device mutation was performed during this check. Next verify that the scratch
config is reproduced by the package's actual kernel build path, then finish
the Linux rollback audit before deciding whether a full linked-kernel A/B is
worth building.

### 2026-09-20 09:39 UTC — exact Android source commit remains unavailable

Read-only Wireless ADB reports kernel
`5.15.123-android13-8-g697b78910a71-dirty`, Clang 14.0.7 based on Android
toolchain `r450784e`, build time 2026-07-20, and fingerprint
`qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys`.
The nearby public `lineage-23.2` checkout is at
`93c5cc6ad1d0b807510cfa0fb1d06f47407881f9`; it has no object for
`697b78910a71`. GitHub's commit lookup returns HTTP 422 “No commit found,” and
commit search returns no result. This does not prove the source is private or
does not exist, but the currently available public tree is not the identified
build revision. Continue labeling source comparisons provisional and base
exact runtime-branch conclusions on the hash-matched installed-module
disassembly. Full output is in
`receipts/2026-09-20-android-kernel-build-identity.txt`.

The device remains on the same Android boot with Wi-Fi up. This was an
identity-only read; no suspend or device modification occurred.

### 2026-09-20 09:44 UTC — package build confirms a linked-kernel test

Compared the targeted-build config path with the checked-out Armada package
(`armada-packages` `ffc331f`, kernel 7.2.3). The real package script starts
from ARM64 `defconfig`, merges `config/armada-kernel.config.overrides`, and
builds `Image dtbs modules`. The patched source's ARM64 defconfig sets
`CONFIG_PCIE_QCOM=y`; the Armada override does not set that symbol. The
targeted-build helper uses the same config steps and only narrows its build
targets to `pcie-qcom.o` and the Nova DTB. This confirms the candidate follows
the package's built-in driver configuration: a module swap is not possible,
and a functional trial needs at least a linked Image plus the Nova DTB. No
full build has started. Docker 28.2.2 is available on the aarch64 builder;
the normal wrapper invokes Podman, which is absent, so an isolated Docker run
would be needed unless Podman is otherwise supplied. Package/script details
are in `receipts/2026-09-20-pcie-qcom-linkage-check.txt`.

Expanded the public-source lookup: global commit search returned no result,
and the nearby public repository exposes four branch heads without the
reported Android suffix. This strengthens “not in the available public
checkout/refs” but still does not prove the OEM source does not exist. The
installed-module disassembly remains the exact runtime evidence.

### 2026-09-20 10:00 UTC — low-bandwidth A/B interpretation and diff cleanup

The selected Nova test OPP keeps `rpmhpd_opp_low_svs` and the CPU path at
1 kB/s while lowering only the PCIe memory request from 500,000 to
1,000 kB/s. This matches the active 5 GT/s x1 OPP's power-domain requirement
and CPU floor; the separate `opp-suspend-1` (`min_svs`) remains untouched.
Linux v7.2.3 `bcm_div()` returns at least one for every positive input, so the
low OPP is expected to leave a minimum nonzero MC0/SH0 SLEEP vote, not zero.
If residency advances with that minimum vote, the larger 476 floor is
strongly implicated. If it does not, the result is inconclusive about a
requirement for an exactly zero vote or about the other Android/Linux request
differences. Do not report a negative run as falsifying the PCIe hypothesis.
Sources: [BCM minimum-positive division](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/bcm-voter.c#L50-L59),
[BCM aggregation](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/bcm-voter.c#L91-L116),
[SM8550 PCIe OPP table](https://github.com/gregkh/linux/blob/v7.2.3/arch/arm64/boot/dts/qcom/sm8550.dtsi#L2386-L2460),
[existing Armada suspend OPP](../../../armada-packages/kernel/patches/0520-arm64-dts-qcom-sm8550-add-a-pcie-suspend-opp.patch).

Cleaned the proposal's unified diff using minimal alignment so it shows only
the added diagnostic helper, opt-in call, and resume restore. I first
mistakenly read repeated-looking hunk lines as an unrelated OPP-reference
fix; patch 0513 already contains that code. Exact forward application of the
clean diff to the pre-candidate file reproduces the existing built scratch
source byte-for-byte. No C behavior changed, so the previously built object
hash remains applicable; the clearer proposal is still not in the package
series.

Android remains on its existing boot with Wi-Fi/ADB up. No suspend, kernel
build, package change, or device write occurred in this analysis step. The
next useful device check is Linux-only: preflight the live base deployment and
rollback path before creating or staging any test image.

### 2026-09-20 10:22 UTC — live Android PCIe binaries rechecked

Wireless ADB is connected to the rooted Android boot. I pulled the currently
installed host, CNSS, endpoint, and MHI modules read-only. All four report
`vermagic=5.15.123-g697b78910a71-dirty`; the host and CNSS SHA-256 values
match the earlier exact disassembly. The host module retains its ELF symbols
and BTF but has no DWARF source lines. Exact hashes and sizes are in
`receipts/2026-09-20-android-live-pcie-binary-repull.txt`.

The fresh binary review confirms an important boundary: `cnss_pci_suspend_bus()`
contains an ordinary endpoint path that calls `pci_disable_device()` and
`pci_set_power_state(pdev, 3)`, but the connected-DRV branch uses its saved
nonzero flag to jump around those calls and continue to `cnss_set_pci_link()`.
The prior successful trace's mode-0 host call and the host's `0/0` ICC update
match that connected branch. Android therefore does not need to issue an
explicit endpoint D3hot transition on the observed DRV path. This still does
not reveal the PCI function's physical state during sleep or prove a wake
path. The separate callback run with no `pci_set_power_state()` kprobe hits is
consistent, but is not the same capture as the final-TCS run.

No Android suspend, module operation, setting change, or kernel write was
performed. The device remains awake on Android with Wireless ADB available.

### 2026-09-20 10:54 UTC — exact Android RPMh/ICC modules recovered and checked

Wireless ADB is live on Android slot `_a`, with `wlan0` up. The loaded core
RPMh/ICC/NoC modules were missing from the mounted `vendor_dlkm` file list; I
read `vendor_boot_a` without writing to the device and unpacked its v4 LZ4
vendor ramdisk with the official AOSP `unpack_bootimg.py`. The ramdisk contains
the exact loaded `icc-rpmh`, `icc-bcm-voter`, `rpmh-regulator`, `qnoc-kalama`,
and `qnoc-crow` modules. Their `.modinfo` vermagic and live sysfs scmversion
match `5.15.123-g697b78910a71-dirty` / `g697b78910a71-dirty`. The image, ten
selected modules, byte sizes, and SHA-256 hashes are retained outside Git on
`/Volumes/NovaKernelBuild/android-binaries/`; see the
[module receipt](../../receipts/2026-09-20-android-live-rpmh-module-decomp.md).

Exact AArch64 disassembly of `icc-bcm-voter.ko`'s
`qcom_icc_bcm_voter_commit()` shows `rpmh_write_batch()` called with state
values 2, 1, and 0 (ACTIVE_ONLY, WAKE_ONLY, SLEEP). This matches the call
sequence in mainline v7.2.3 `bcm-voter.c`; the common BCM-voter state pipeline
is not the observed distinction. The exact `rpmh-regulator.ko`'s
`rpmh_regulator_send_aggregate_requests()` instead confirms active, sleep, and
wake-only regulator aggregates. Mainline v7.2.3's regulator send helper uses
only ACTIVE_ONLY. This verifies a real capability gap, but it is not causal
proof and does not justify changing shared-rail behavior without wake-path
analysis.

The exact Kalama NoC module contains static BCM objects for MC0, SH0, SH1, and
ACV plus QUP2; mainline `sm8550.c` defines those same resources. Thus their
presence in the Android TCS is not itself evidence of a vendor-only voter
feature. The producer of the TCS `MC4`/`SH5` commands at `0x50060`/`0x50064`
remains unidentified; neither named object was found in the exact Kalama/Crow
module symbol tables or mainline `sm8550.c`. Keep the prepared PCIe low-bandwidth
OPP A/B as the narrow first test after Linux boot/rollback preflight. The
regulator-context difference stays a separate, higher-risk hypothesis.

No Android suspend, module operation, setting change, or kernel write was
performed. The linked Linux Image+Nova DTB build is still running off-device.

### 2026-09-20 11:27 UTC — active Android boot image and failed trace attempt

Wireless ADB is live as root on slot `_a`, kernel
`5.15.123-android13-8-g697b78910a71-dirty`. I pulled the active 96 MiB
`boot_a` partition read-only and unpacked its v4 header. The kernel image
contains source paths under `/home/liuwen/q9ex/VENDOR.13.2.6/kernel_platform/common`,
but this is only a build-tree label; it does not identify the exact vendor
source revision. The full image and extracted-kernel hashes are in the
[boot-image/trace receipt](../../receipts/2026-09-20-android-boot-image-and-trace-failure.md).

The live CMD-DB again maps `0x50060` to `MC4` and `0x50064` to `SH5`. Searches
of the exact `vendor_boot` RPMh/ICC modules and the mounted module tree found
no printable resource-name references that identify their producer. The
active kernel image scan also provided no meaningful paired references. This
does not prove the names are absent from indirect/generated tables.

I attempted one bounded Android `deep` capture with temporary,
per-instance `interconnect_qcom:bcm_voter_commit` and `rpmh:rpmh_send_msg`
tracepoints. The vendor tracefs rejected the address filter, so the attempt
was unfiltered. The first setup attempt and the run using the wrong
`/sys/power/suspend_stats` path both stopped before arming RTC or requesting
suspend. After correcting the stats path, the service returned false and
`suspend_stats` success remained 3 while fail advanced 3→4 and
`failed_prepare` 0→1. Kernel log identifies `3da0000.kgsl-smmu` returning
`-115` (`EINPROGRESS`); the built-in display was ON. Thus this run did not
reach the low-power path and its awake RPMh traffic cannot attribute the
`MC4`/`SH5` sleep commands. Tool output was truncated, so the full 180-event
trace was not retained as a raw receipt.

Cleanup verified the original boot ID, `[s2idle] deep`, empty RTC alarm and
`alarm_IRQ=no`, no tracefs instance, global tracing off, `debug_suspend=0`,
and `wlan0=UP/LOWER_UP`. No bandwidth vote, regulator, PCI state, Android
image, or module was changed. A retry should wait until display/GPU idle and
capture unfiltered to a host file; if KGSL SMMU still rejects prepare, stop
and treat Android-side event attribution as blocked by that suspend-preparation
path. This is separate from the Linux low-bandwidth PCIe OPP A/B.

### 2026-09-20 11:38 UTC — screen-off Android retry still aborted; device restored

Wireless ADB reconnected to rooted Android (`kalama`, build
`qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys`,
kernel `5.15.123-android13-8-g697b78910a71-dirty`). At reconnect the screen was
OFF and `mWakefulness=Asleep`; I woke it and verified `mWakefulness=Awake`,
screen ON, `wlan0=up`, `[s2idle] deep`, empty RTC wakealarm, global tracing
off, and no temporary tracefs instance. Boot ID is unchanged.

The saved screen-off trace from the prior bounded attempt is 107,372 bytes,
SHA-256
`ad0e367a94a98f309b7bed8e633e3160b55d362e3f558027634dbf259242d49b`. Its
force-suspend Binder result was false; success stayed 99, fail rose 6→8, and
`failed_freeze` rose 2→3. The latest failure was `alarmtimer.0.auto` (`-16`),
not a successful deep entry. The 679 trace entries include 283
`bcm_voter_commit` and 396 `rpmh_send_msg` events. There were no `0x50060`
(`MC4`) or `0x50064` (`SH5`) writes in the trace; because this attempt never
completed deep and tracing began after boot, that is only a negative result
for this awake/aborted interval, not proof about pre-staged TCS contents or
their producer. Exact address counts and limitations are in the
[Android trace receipt](../../receipts/2026-09-20-android-boot-image-and-trace-failure.md).

Further Android retries are paused pending read-only identification of the
freeze/prepare blockers. No module, image, sleep policy, regulator, vote, or
PCI state was changed.

### 2026-09-20 11:50 UTC — exact Android DCVS-FP binary owns MC4/SH5 staging

I extracted the active A-slot `dcvs_fp.ko` from the already-pulled vendor-boot
ramdisk and confirmed its `vermagic` is
`5.15.123-g697b78910a71-dirty`; live `/sys/module/dcvs_fp/scmversion` is the
same suffix. The module is loaded and its platform driver is bound to the
live DT node `/soc/apps_rsc@17a00000/drv@2/qcom,dcvs-fp`.

The live node has `qcom,ddr-bcm-name=MC4` and
`qcom,llcc-bcm-name=SH5`, matching the earlier CMD-DB resource map
(`MC4=0x50060`, `SH5=0x50064`). Exact AArch64 disassembly shows the probe calls
`populate_bcm_data()` for those two property names; that function uses
`cmd_db_read_addr()` and `cmd_db_read_aux_data()`. Probe then initializes the
RPMh fast path and calls `rpmh_write_async()` for both commands with
`RPMH_SLEEP_STATE` and `RPMH_WAKE_ONLY_STATE`. Later fast-path updates use the
ACTIVE_ONLY context. Module hash, ELF offsets, disassembly facts, and live DT
bytes are in the [DCVS-FP receipt](../../receipts/2026-09-20-android-dcvs-fp-binary-and-dt.md).

This is strong software attribution for Android's two extra BCM commands;
it is not evidence that they alone enable AOSD/CXSD/DDR residency. Next compare
the `dcvs_fp` source/DT and runtime role against Armada's kernel/device tree,
then determine how much of the Android staging can be represented upstream.
No code or device behavior changed during this inspection.

### 2026-09-20 12:11 UTC — Wireless ADB restored; Android state rechecked

Wireless ADB now sees rooted Android as `192.168.0.163:42265`. The live build
is `qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys`
with kernel `5.15.123-android13-8-g697b78910a71-dirty`, the same boot ID
`d927cfaa-54f1-428d-9f3b-1298aa1982fc`, and `wlan0` at `192.168.0.163`. The
system is awake. The PCIe host module remains bound to `1c00000.qcom,pcie`; the
root port and WCN endpoint both report D0 in this awake snapshot. `dcvs_fp`,
`qcom_rpmh`, `icc_rpmh`, `icc_bcm_voter`, and `rpmh_regulator` are loaded.

This confirms Android transport and build identity only; it adds no sleep-time
state evidence. No module, image, suspend setting, vote, regulator, or PCI
state was changed. An SSH attempt to the Armada alias timed out while Android
was active. The user confirms `adb reboot` returns to the default Linux boot;
that transition is the next read-only baseline check.

### 2026-09-20 12:35 UTC — Linux baseline restored; module-only A/B found

After the user confirmed the Nova's default OS, I rebooted Android with
Wireless ADB. Android went offline and Armada SSH at `192.168.0.20` returned.
The live system is Fedora 44, kernel `7.2.3`, Armada image version
`20260915.feca679`, boot ID `09a76af5-4e8f-454a-858e-dedb4ebb1d4d`, with
`wlp1s0` up at `192.168.0.20`. PCI root `0000:00:00.0` is D0/unbound and WCN
`0000:01:00.0` is D0/bound to `ath12k_wifi7_pci`. No systemd units have failed.

`bootc status` and `ostree admin status` both show current and rollback
Deployments on the same image digest/checksum; nothing is staged. The current
image version is `20260915.feca679` (`sha256:5fe995d5...`), deploy serial 3;
rollback is the same image at serial 2. `rpm-ostree status` currently aborts
with a missing-`timestamp` assertion, so bootc/OSTree status are the usable
read-only deployment receipts. No image or kernel layer was changed.

I fetched `/proc/config.gz` read-only. It is byte-for-byte identical to the
local Linux 7.2.3 Kbuild `.config` (SHA-256
`2219546e268f72bb2bcbac96943202e9e50731b6e531e3193cc73b1976d2fbef`). The
running config has `CONFIG_MODULES=y`, `CONFIG_MODULE_UNLOAD=y`,
`CONFIG_OF_DYNAMIC=y`, `CONFIG_OF_OVERLAY=y`, `CONFIG_QCOM_COMMAND_DB=y`, and
`CONFIG_QCOM_RPMH=y`; `Module.symvers` is absent and the device has no
kernel-devel package or compiler. The local Kbuild tree has generated headers
and `modpost`. This is enough to try an out-of-tree module build without a full
kernel build; module-load ABI still must be checked.

The live Apps RSC is `/sys/devices/platform/soc@0/17a00000.rsc`, driver `rpmh`,
compatible `qcom,rpmh-rsc`, with `qcom,drv-id=<2>`. The bound child
`17a00000.rsc:regulators-0` uses `qcom-rpmh-regulator` and has the RSC as its
direct parent. `cmd_db_read_addr` and `rpmh_write_async` are present in live
`/proc/kallsyms`. Configfs is mounted but has no OF-configfs overlay directory;
none is needed if a test module reuses this existing RPMh child device as its
client. That removes the proposed overlay and makes the diagnostic smaller.

Fresh post-boot counters are APSS=1 and AOSD/CXSD/scalar DDR=0; suspend stats
are success=0/fail=0. The awake interconnect summary still shows the PCIe
client at a 1,000,000 kB/s peak, which is not a suspend request. No module was
built or loaded, no overlay or vote was changed, and no suspend was attempted.
The next action is to build a module-only MC4/SH5 SLEEP/WAKE probe in the local
Kbuild tree, verify its vermagic and exports, then decide whether it is safe to
load for one RTC-bounded A/B. A reboot to the unchanged current image will clear
the RPMh request cache afterward.

### 2026-09-20 13:01 UTC — MC4/SH5 probe builds; live ABI checks narrow the risk

The module source now targets the already-bound Nova platform device
`17a00000.rsc:regulators-0` by exact device name. On insertion it resolves
`MC4` and `SH5` through CMD-DB and queues the Android-matched SLEEP=0 and
WAKE_ONLY=1 pair using `rpmh_write_async()`. It does not alter ACTIVE votes,
PCI state, regulators, or the boot deployment. The request cache persists until
reboot; if the WAKE_ONLY queue fails after SLEEP was accepted, do not suspend
and reboot before further testing.

The out-of-tree module is an AArch64 ELF with vermagic
`7.2.3 SMP preempt mod_unload aarch64`, matching both `uname -r` and a shipped
device module. Its SHA-256 is
`ec0194e7ae8a6dc91c74449718948c941095c3f55c0ff90c55a03aa02e11e330`.
`KBUILD_EXTRA_SYMBOLS` pointed modpost at the local 7.2.3 `vmlinux.symvers`;
all imported symbols are listed there as exported, and the same symbol names
are present in live `/proc/kallsyms`. The local build tree has no top-level
`Module.symvers`, and live `CONFIG_MODVERSIONS` is disabled, so there is no
symbol-CRC comparison. The device's live BTF confirms `struct tcs_cmd` is three
u32 fields at offsets 0/4/8 (12 bytes total) and that
`RPMH_SLEEP_STATE=0` / `RPMH_WAKE_ONLY_STATE=1`, matching the module source.

One build caveat: before build preparation,
`/proc/config.gz` and the local `.config` matched at SHA-256
`2219546e268f72bb2bcbac96943202e9e50731b6e531e3193cc73b1976d2fbef`.
`make modules_prepare` normalized entries unknown to that source tree and
disabled BTF plus several scheduler/tracing options; the module/RPMh/CMD-DB,
ARM64, SMP, PREEMPT, stack-protector, and module-unload settings remain enabled
in both. Thus the release, required API symbols, key structure layout, and
relevant config gates are verified, while the exact full vendor patch/config
identity is not. The exact live config and BTF were saved outside the repo at
`/Volumes/NovaKernelBuild/armada-rpmh-dcvs-pair/` for comparison.

The device is still on the same Linux boot ID, Wi-Fi and SSH are healthy, and
the probe has not been copied to or loaded on it. No suspend test has run. The
next gate is to insert the module, verify its one-line `SLEEP_AB` success log,
and only then run the harness's 10-second minimum RTC-woken direct-deep test
with the available `rpmh-aoss` trace profile. After the trial, reboot the unchanged
deployment to clear the cached RPMh pair.

### 2026-09-20 13:15 UTC — use available RPMh tracepoints for the A/B

The root-only preflight passed again on the same Linux boot
`09a76af5-4e8f-454a-858e-dedb4ebb1d4d`: kernel `7.2.3`, Wi-Fi link up, no
failed systemd units, no RTC wake alarm, suspend success/fail `0/0`, and
AOSD/CXSD/scalar DDR `0/0/0`. The module is present in `/tmp` with the expected
hash and vermagic but is not loaded. No behavior or suspend setting changed.

This kernel does not expose `rpmh:rpmh_rsc_snapshot`; therefore the harness's
`rsc-success` profile would stop before suspend. It does expose
`rpmh:rpmh_send_msg`, `rpmh:rpmh_tx_done`, and both `qcom_aoss` send/done events,
so use the existing `rpmh-aoss` profile instead. The RPMh send-message event
captures the command payloads written into TCS during flush; there is no
separate RSC-snapshot event on this kernel. Tracefs has zero private instances
and global `tracing_on=1` at baseline; the harness will use its own private
instance and leave the global setting alone. This narrows the trace evidence
but does not change the A/B variable.

### 2026-09-20 13:27 UTC — first module insertion rejected by struct-size ABI gate

I copied the prepared MC4/SH5 probe to `/tmp` on the awake Nova Linux system and
attempted one `insmod`. The loader rejected it before init with:

```text
module armada_rpmh_dcvs_pair: .gnu.linkonce.this_module section size must match the kernel's built struct module size at run time
```

The module never loaded, its init routine never ran, and it queued no RPMh
requests. No suspend was run. The device remained on the same Linux boot with
Wi-Fi/SSH up; no reboot is needed to clear anything because no request was
staged. The failed artifact must not be retried.

The rejection is now explained by the build config: the rejected object has a
1216-byte `struct module`/`this_module` section, while live
`/sys/kernel/btf/vmlinux` reports 1280 bytes. Its DWARF lacks the four fields
gated by `CONFIG_DEBUG_INFO_BTF_MODULES`; the live kernel has that option
enabled, but `make modules_prepare` normalized it off before the module build.
The 24-byte field shift rounds to a 64-byte total size difference. The existing
local `vmlinux` has the same 1280-byte layout as live BTF, but its build ID
differs, so it is not evidence of an identical running image. This accounts for
the loader error and supersedes the earlier assumption that the vermagic and
`tcs_cmd` match were enough. Exact values and safe rebuild gates are in the
[insertion failure receipt](../../receipts/2026-09-20-rpmh-dcvs-pair-insertion-failure.md).

Next: restore BTF-module configuration for an out-of-tree rebuild, then compare
the compiled `struct module` size/member offsets and the probe's relevant
kernel API type layouts against live BTF. Do not reload anything until those
checks pass; `CONFIG_MODVERSIONS` is off, so vermagic cannot protect against
remaining ABI mismatch.

### 2026-09-20 13:45 UTC — rebuilt probe matches the live module layout

I re-enabled `CONFIG_DEBUG_INFO_BTF` and
`CONFIG_DEBUG_INFO_BTF_MODULES`, regenerated the module-preparation headers,
cleaned the out-of-tree module, and rebuilt only the probe. The corrected
artifact SHA-256 is
`548d9244a327cc16ba04d2ad644a0b87b08660dfd37e8db5144e07a0065eda2f`; its
`.gnu.linkonce.this_module` size is `0x500` (1280 bytes), exactly equal to a
stock device `crypto_engine.ko` and live `struct module` BTF.

Live BTF and the new module agree on `struct module`, `struct device`,
`struct bus_type`, and `struct tcs_cmd` sizes/member offsets; the RPMh state
values also match. Canonical live-versus-build-tree BTF signatures match for
`bus_find_device`, `device_match_name`, `put_device`, `cmd_db_read_addr`, and
`rpmh_write_async`. The module BTF is built with `.BTF.base`; the 7.2.3 source
loader relocates module base BTF against live vmlinux BTF and rejects a
mismatch unless the allow-mismatch option is enabled, which is disabled on the
device. `CONFIG_MODVERSIONS` remains off, and the local vmlinux build ID differs
from the running image, so this is a guarded ABI match rather than proof of
identical source/image identity. The device reports 144 package patches and
the package `patches/series` has 144 entries; the local build also has the
separate PCIe OPP diagnostic C/DT edits, which do not affect the probe's API
types.

The corrected module has not been copied to or loaded on Linux. The failed
older artifact is still unloaded in `/tmp`; the attempted insertion queued no
RPMh requests and no suspend ran. The device remains on the same healthy boot.
Next I will copy the corrected hash, verify it on-device, and try one
insertion. I will only start the RTC-bounded deep test if init confirms both
CMD-DB lookups and the SLEEP/WAKE_ONLY requests succeeded. See the [BTF rebuild
receipt](../../receipts/2026-09-20-rpmh-dcvs-pair-btf-rebuild.md).

### 2026-09-20 13:51 UTC — MC4/SH5 sleep-pair A/B did not restore residency

The corrected test module was copied to `/tmp` on Linux and loaded
successfully. Its init log resolved MC4/SH5 to `0x50060`/`0x50064` and
reported the SLEEP=0, WAKE_ONLY=1 pair queued. I ran one RTC-woken direct
`deep` suspend using the harness's `rpmh-aoss` profile. The device returned
on the same boot, with Wi-Fi/SSH healthy; kernel suspend success advanced by
one and the clock bracket measured 9.319121 seconds of actual sleep.

The Apps-RSC send trace contained the six normal Linux resources plus the
injected MC4/SH5 commands in both SLEEP and WAKE contexts. MC0 and SH0 retained
their nonzero `0x600003b8` SLEEP words. AOSD, CXSD, and scalar DDR count and
duration deltas all remained zero; APSS advanced once. Detailed DDR LPM ID
`0xd0` gained 227,760,477 ticks without a count change, and remains opaque.
The run's ICC attribution was unavailable, and the trace profile has no RSC
snapshot event, so do not claim the AOP accepted the complete staged set.

This rules out the MC4/SH5 pair as a sufficient standalone fix in this run.
It does not establish that the pair is irrelevant, nor prove the retained
PCIe-correlated MC0/SH0 floor is causal. Harness cleanup restored the RTC,
trace instance, debug settings, and suspend selection. The module's request
cache persists until reboot; the next cleanup is a reboot to the unchanged
Linux deployment, then verify Wi-Fi/SSH and that the temporary module is gone.
Full request set, deltas, and hashes are recorded in the [A/B
receipt](receipts/2026-09-20-rpmh-dcvs-pair-ab.md).

### 2026-09-20 14:06 UTC — reboot cleared the test RPMh cache

After recording the MC4/SH5 result, I rebooted the unchanged Linux deployment
to clear the test module and its cached RPMh SLEEP/WAKE requests. SSH returned
on new boot ID `cd02fc51-33c5-4b1a-96a7-75a17eb98b30`; the device reports
kernel `7.2.3`, Armada version `20260915.feca679`, `mem_sleep=[s2idle] deep`,
suspend success/fail `0/0`, Wi-Fi interface `wlp1s0` up,
`systemctl is-system-running=running`, and no failed units. The test module
is absent. No boot layer or persistent device file was installed.

The harness receipt shows the private trace instance was removed before the
reboot. Direct post-boot tracefs inventory is denied to the unprivileged SSH
account, so I do not claim an independent post-boot tracefs listing. The
device is back in its normal Linux state and is ready for further read-only
source work.

### 2026-09-20 14:24 UTC — linked PCIe OPP image found; scheduler config blocks deployment

The earlier status text saying there was no linked OPP image was stale. The
external `linux-7.2.3` scratch tree already contains the test OPP in its linked
`vmlinux`/`Image` and Nova DTB. Their hashes and the source/DTB markers are in
the [config-gate receipt](receipts/2026-09-20-pcie-opp-image-config-gate.md).

The linked image is not safe to deploy. Its `.config` turned off
`CONFIG_SCHED_CLASS_EXT` and omitted `CONFIG_GROUP_SCHED_BANDWIDTH`,
`CONFIG_EXT_GROUP_SCHED`, and `CONFIG_EXT_SUB_SCHED`, all enabled in the live
device config. The Armada kernel package fragment explicitly requires
`SCHED_CLASS_EXT=y` for `scx_lavd`. This is a concrete config mismatch, not a
theoretical warning. The target package checkout is on the unrelated
`fix-steam-charging-eta` branch and was not modified.

Source inspection also sharpened the test variable. The live link is Gen2 x1,
whose 5 GT/s x1 OPP requests `low_svs` and PCIe-MEM/CPU-PCIe peak bandwidths
`500000/1` kB/s. The diagnostic OPP uses the same `low_svs` corner and
`1000/1` kB/s, so the intended change is the PCIe-MEM request while retaining
the same RPMh power-domain performance state. It runs only when the normal
host suspend path leaves PCIe unsuspended during direct suspend-to-RAM. It
does not force PCI state, bypass the D3cold check, or manually write an ICC
vote. This is a source-justified A/B candidate, not causal proof.

An isolated `O=` Kconfig attempt stopped because the existing scratch source
tree has an in-tree build; `mrproper` would destroy cached outputs, so it was
not run. The `armada-kmod-build` container is native AArch64 and mounts the
scratch tree, making an incremental rebuild possible. Next, preserve the
current `.config`, restore the four live scheduler settings through Kconfig,
verify the full diff, and rebuild only if the configuration gate passes. Do
not install the currently linked image or stage a boot layer yet. No device
state changed in this audit.

### 2026-09-20 14:32 UTC — scheduler config restored exactly

I backed up the scratch `.config`, enabled `CONFIG_SCHED_CLASS_EXT`, and ran
`olddefconfig` in the already configured AArch64 build tree. Kconfig restored
`CONFIG_GROUP_SCHED_BANDWIDTH`, `CONFIG_EXT_GROUP_SCHED`, and
`CONFIG_EXT_SUB_SCHED`; the new config hash exactly matches the live Nova's
saved `/proc/config.gz` copy (`2219546e268f72bb2bcbac96943202e9e50731b6e531e3193cc73b1976d2fbef`).
The previous scratch config is backed up with hash
`ffeef3364ee62e1e819c9a3f9c37406822483c61104a8a13785e652b917dd755`.

This passes the scheduler config gate, but the linked Image/DTB are still from
the old config and remain unusable. `CONFIG_PCIE_QCOM=y`, so the experiment is
built into the kernel Image rather than packaged as a module. No rebuild or
device deployment has happened yet; next is an incremental `Image dtbs`
build, followed by artifact inspection and a reversible bootc-layer review.
Hashes and exact commands are in the
[config reconcile receipt](receipts/2026-09-20-pcie-opp-config-reconcile.md).

### 2026-09-20 14:47 UTC — current bootc base found; old layer recipe is stale

The booted and rollback Armada deployments both use version
`20260915.feca679` and OSTree checksum
`ec096ad2fdb64e35dd9b2ac691690d80f6e62d80c2617704d2a5788c7b95294b`; neither
is staged. Their image reference is
`ghcr.io/armada-os/armada:beta`, pinned by manifest digest
`sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88`.
The BLS entries use the installed kernel `7.2.3`. This lets the test layer
preserve the exact current root image and kernel-module tree.

The old local layer recipe is for `localhost/armada-rsc:20260901` and kernel
7.2.0, so it cannot be reused. Rootful Podman has only its Fedora builder
image; the Armada base is not cached. `/var` has 37 GB free, and the pinned
base's compressed OCI layers total about 5.65 GiB before extraction or bootc
staging. I have not pulled it; first budget the unpacked storage so the build
does not crowd the live device. No deployment changed. Details are in the
[bootc base/space receipt](receipts/2026-09-20-bootc-base-and-space.md).

### 2026-09-20 14:52 UTC — Linux SSH is available; matching-config rebuild is active

The user confirmed Armada Linux is Nova's default boot; if the device is on
Android with ADB available, an ADB reboot returns to Linux. At this check,
`adb devices -l` had no Android target, while SSH alias `armada` returned the
Nova on kernel `7.2.3`, boot ID
`cd02fc51-33c5-4b1a-96a7-75a17eb98b30`. The device remains on its unchanged
Linux deployment. The diagnostic `Image dtbs` rebuild is active in the
external AArch64 build container (274% CPU at the check); the Image and Nova
DTB timestamps are still from the prior build, so they must not be deployed
yet. No device reboot, overlay, RPMh change, or test module was applied.

### 2026-09-20 15:06 UTC — bootc apply and Nova boot-image rollback path verified

Read-only inspection confirmed that bootc switch --download-only can stage
the local image without rebooting, while --from-downloaded --apply reboots
immediately. Armada's shutdown unit rebuilds the next deployment's ABL
/KERNEL from its kernel, initramfs, and supported DTBs. Before boot, its
startup path snapshots the currently stamped /KERNEL to KERNEL.BAK. The
current /KERNEL and KERNEL.BAK are identical at SHA-256
0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000, so a
known-good image is present now.

That startup snapshot would replace the old backup with the candidate after a
successful candidate boot. The temporary image must therefore include a
systemd drop-in that clears only the --snapshot-prev argument while keeping
the updater check and shutdown updater. The existing armada-bootimg-finalize
rollback only covers failure to regenerate /KERNEL; neither it nor the
initramfs remapper proves automatic recovery from a kernel hang. The backup is
a manual recovery path if SSH does not return. No deployment or ESP file was
changed. Full facts and source references are in the
[bootimg-recovery-path.md](receipts/2026-09-20-bootimg-recovery-path.md).

### 2026-09-20 15:20:50 UTC — pinned Nova PCIe test-layer recipe added

Added a test-only Containerfile pinned to the installed Armada base digest.
It accepts and verifies the final kernel and Nova DTB hashes, replaces only
the 7.2.3 kernel image and Nova DTB, labels the deployment distinctly, and
adds the boot-service drop-in that preserves the known-good KERNEL.BAK while
keeping the startup freshness check and shutdown updater. It does not replace
modules or regenerate the unchanged initramfs. The recipe and drop-in are
tracked on the branch; no image has been built, pulled, staged, or applied.

### 2026-09-20 15:28 UTC — matching-config kernel build reached final link

The full kernel objects and built-in archives compiled successfully. The first
vmlinux link and BTF generation completed; Kbuild is on the second/final link
pass. No build error has appeared, but the final vmlinux, boot Image, and DTB
are not yet verified, so the older artifacts remain unusable. The Nova remains
on its unchanged Linux deployment and no test image is staged.

### 2026-09-20 15:59 UTC — matching-config build verified; Android source remains unavailable

`make -j8 ARCH=arm64 Image dtbs` completed with exit status 0 from the external
Linux 7.2.3 build tree. The generated Image embeds the exact captured Nova
config hash. The Nova DTB contains the opt-in diagnostic property and the
synthetic 2 Hz OPP at 1000/1 kB/s with the existing `low_svs` required OPP. The
artifact hashes and validation are recorded in
[`2026-09-20-matching-config-pcie-opp-build.md`](../../receipts/2026-09-20-matching-config-pcie-opp-build.md).
No OCI image was built or staged, and the device has not booted this candidate.

The installed Android kernel suffix `g697b78910a71-dirty` does not resolve
through the public GitHub commit API. The available `lineage-23.2` checkout is
grafted at `93c5cc6`; the checked public `lineage-24.0` head is `dc79bb3`. This
does not change the binary-grounded PCIe/RPMh findings, but it means the exact
vendor source is not available through those public refs.

The user reports Android is awake with Wireless debugging enabled, but this
Mac still sees no ADB device or mDNS endpoint. The prior address
`192.168.0.163:42265` does not respond. I requested the current pairing or
connect endpoint; no ADB command, reboot, or Android modification was made.

### 2026-09-20 16:34 UTC — current Linux state and ESP recovery copy verified

The Nova is on Linux, not Android. Fresh SSH reports Fedora 44/kernel `7.2.3`,
boot ID `55fdad18-019d-4c92-8ebd-8a558574c1d3`, Wi-Fi connected, and systemd
running. ADB discovery is empty as expected. The booted and rollback bootc
deployments still use the same pinned Armada beta digest and OSTree checksum;
no deployment is staged. `/var` has 37 GB free, and rootful Podman contains
only its 199 MB Fedora builder.

The root-owned ESP's active `/KERNEL` and `/KERNEL.BAK` are both 75,522,048
bytes and match SHA-256
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`. I copied
both into an external-drive tar and verified each extracted member against the
device hash. The archive hash and path are in the [preflight
receipt](receipts/2026-09-20-live-linux-preflight-and-boot-backup.md). No
device setting, image, ESP file, or sudo/SSH policy changed. Device sudo is
limited to the already-authorized test runner, Podman, and bootc without a
prompt; other root commands still require the supplied device password.

The 15:59 notebook paragraph and status sentence treating Android as the live
OS were stale; the current SSH boot ID and Linux checks establish that the
Nova remained on Linux. The Android source/binary investigation is already
captured; this next experiment is Linux-only. The candidate OCI image has not
yet been built or staged.

### 2026-09-20 16:37 UTC — pinned base pulled; first image build hit Netavark

Transferred the verified build context to the Nova; remote Image and DTB
SHA-256 values match the build receipt. Rootful Podman fetched the exact base
manifest pinned in the Containerfile, and reports it as digest
`sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88`.
The first build reached its final validation `RUN` step, but Podman failed to
start that step because Netavark's isolated network setup could not apply its
nftables ruleset. The validation step only checks local hashes and writes the
Armada version marker, so a retry with `--network=host` does not change the
build inputs or expose the command to a network requirement.

The failed build did not complete or tag the candidate and did not stage or
apply bootc. `/var` currently has 30 GB free; rootful Podman reports 12.8 GB
of images. Continue monitoring free space during retry and bootc staging. Exact
failure: `netavark: nftables error: "nft" did not return successfully while
applying ruleset`. No device firewall or network configuration was changed.

### 2026-09-20 16:59 UTC — diagnostic layer staged; candidate PCI BTF verified

The same on-device build context succeeded when Podman used `--network=host`;
the hash-check step passed for the matching-config kernel Image and Nova DTB.
The candidate OCI image has manifest digest
`sha256:d7eb055720a28bddc8f6a3e7267d6e56c54c53de719963ed06c1228f851e101b`,
and inspection confirms its 128 lower rootfs layers exactly match the pinned
base, with four diagnostic layers on top. It carries the backup-preserving
boot-image sync override and test version marker. Full recipe, digest, and
stage data are in the [layer receipt](receipts/2026-09-20-pcie-opp-layer-stage.md).

Bootc staged it download-only as OSTree checksum
`7eb51de69c15c669d35900ff93b279c8b8a21ffec8f415e7da00d14dd2d55cbf`; status
shows `downloadOnly=true`, `rollbackQueued=false`, and both active and rollback
deployments still on the original base. The active ESP and `KERNEL.BAK` hashes
remain unchanged and `/var` has 30 GB free. The candidate is not queued for
boot, and no reboot or suspend run has occurred.

Before applying it, I extracted and inspected the candidate's exact `.BTF`
section. Its global hash differs from stock because the patch adds
`qcom_pcie.diag_opp_active`; `pci_dev`/`pci_bus` offsets used by the trace
probe remain identical. The harness's strict gate now allows only those two
known BTF hashes and writes the observed hash into its trace metadata. The
candidate offsets and harness check are recorded in the
[BTF receipt](receipts/2026-09-20-candidate-pcie-btf.md); `host self-test`,
`py_compile`, and `git diff --check` pass.

### 2026-09-20 17:05 UTC — pre-boot PCIe/RPMh trace prerequisites pass

Ran a fresh harness preflight after pushing the updated runner. Its SHA-256
matches the local source at `b790120`, and it confirms the original Linux boot
is still active with the candidate download-only staged, no rollback queued,
Wi-Fi enabled, and `[s2idle] deep` selected. All nine `pcie-d3cold` profile
tracepoints are present. Both `psci_system_suspend_enter` and
`__pci_host_common_d3cold_possible` are available and unblacklisted. The full
preflight is retained outside Git with its hash and exact gates in the
[pre-boot receipt](receipts/2026-09-20-pcie-opp-preboot-harness-preflight.md).

This closes the remaining instrumentation preflight. The next operation is to
apply the already-staged candidate, confirm boot/SSH/Wi-Fi and candidate BTF,
then run one short RTC-woken direct-deep A/B with the `pcie-d3cold` profile.

### 2026-09-20 17:16 UTC — candidate apply requested; device unreachable

After the preflight, `sudo -n bootc switch --from-downloaded --apply` returned
`Staged deployment will now be applied on reboot` and the SSH session closed.
The candidate boot is not confirmed. A fresh SSH connection, two pings, and a
TCP/22 probe to `192.168.0.20` timed out. ADB listed no devices, USB inventory
was empty, and mDNS discovery returned only this Mac. The existing ARP entry
for `.20` is stale and is not evidence of a live device. No further reboot or
suspend was issued. The mode-0600 ESP archive on `/Volumes/NovaKernelBuild`
was rehashed and still matches its recorded SHA-256. See the
[post-apply reachability receipt](receipts/2026-09-20-post-apply-device-reachability.md).

The A/B is still pending. First regain access and establish whether the
candidate or the stock deployment booted; verify bootc rollback state, Wi-Fi,
ESP image hashes, and candidate BTF before considering a suspend run.

At 17:19 UTC, another SSH attempt returned `No route to host` on the default
Ethernet route. An interface-scoped route lookup selected Wi-Fi (`en1`), where
`ping -b en1` and SSH `BindInterface=en1` both reported the host down. The old
`.20` neighbor record remained stale. This confirms the device did not respond
over either tested interface, but it does not distinguish a failed boot from
Wi-Fi/network startup failure. No reboot was issued.

A 17:22 UTC retry still found no SSH, ADB, or USB device. Source review found
no remote or automatic kernel-hang recovery: `armada-bootimg-finalize` rolls
back only when boot-image regeneration fails, and the Select boot hotkey only
changes session mode after Linux userspace starts. The official Armada recovery
guide documents entering ABL with VOL- while powering on, then choosing
**Switch Boot Mode → Android**. This gives a concrete way to regain ADB if ABL
is reachable; it does not repair or verify the Linux deployment. No physical
action was taken. Details are in the
[post-apply reachability receipt](receipts/2026-09-20-post-apply-device-reachability.md).

### 2026-09-20 18:21 UTC — Android ADB recovered; stock boot image restored

The user entered Android through ABL after reporting that the Linux boot had
stalled at “Preparing Armada.” Rooted Android 13 is reachable through
authenticated Wireless ADB. Read-only inspection identified the actual ESP as
`/dev/block/sda18` (`ARMADA`, vfat); `/dev/block/sda19` is the ext4 boot
partition and `/dev/block/sda20` is Btrfs, which this Android kernel cannot
mount. No Btrfs or boot partition writes were attempted.

The ESP contained the diagnostic `KERNEL` image from the candidate and the
known-good stock image in `KERNEL.BAK`. Both were copied off-device and
hash-verified. I restored `KERNEL` by copying the stock backup to a temporary
ESP filename, syncing, and renaming it over `KERNEL`. A fresh read-only mount
then verified both active `KERNEL` and `KERNEL.BAK` have stock SHA-256
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`; the
candidate is preserved externally. BLS files and image-ID stamps were not
changed. See the [Android ESP rollback receipt](receipts/2026-09-20-android-esp-rollback.md).

Android's global `adb_wifi_enabled` and persistent
`persist.adb.tls_server.enable` values both read `1`; I reasserted them through
the native settings/property interfaces. `persist.adb.tcp.port` remains empty.
This confirms Wireless ADB is currently on over TLS, but its behavior after a
future Android reboot is not yet tested; no boot script or insecure TCP mode
was added.

The Android restart to Linux has not yet been issued. The next check is a
single reboot, then verify the booted Linux deployment, bootc rollback state,
Wi-Fi/SSH, and whether the system gets past “Preparing Armada” before doing
any suspend experiment.

### 2026-09-20 18:36 UTC — stock Linux and Steam UI recovered; candidate remains queued

The Android restart returned to SSH on `armada`. The new Linux boot ID is
`aa40c55e-d558-46a9-a710-3a7d926b9e9e`; kernel `7.2.3` is running with the
old base's `ostree=.../fe4d16bd.../0` command line. `bootc status --json`
reports the original Armada beta digest booted, candidate
`armada-pcie-opp-test:20260920-01` in `rollback`, no staged deployment,
`spec.bootOrder=rollback`, and `rollbackQueued=true`. The live CLI help says
the rollback-slot deployment is queued for the next boot. The sudo audit has
no explicit `bootc rollback` command; it records the earlier
`bootc switch --from-downloaded --apply`. The queue's origin/intent remains
unresolved, so do not reboot again until the selected next boot is clear.

Systemd is `running` with no failed units; Wi-Fi and SSH are up. The user
Gamescope service is active, and Steam's local CEF endpoint lists
`Steam Big Picture Mode`, `MainMenu_uid2`, and `QuickAccess_uid2`. This
confirms Steam UI components loaded, though the physical screen was not
captured.

The current-boot `armada-bootimg-sync` log says it copied the current image to
`KERNEL.BAK` as a known-good image, then skipped rebuilding `/KERNEL` as
“already current (vmlinuz-7.2.3).” The updater trusts `.armada-bootimg.id`, not
the actual `/KERNEL` bytes. That stamp still describes the candidate's BLS
content although the pre-reboot stock image was restored. The running stock
cmdline confirms which image booted, but post-boot ESP hashing requires root
and was not available with the current noninteractive sudo rules. No BLS,
image stamp, or bootc state was changed after boot. The full evidence is in
the [Android rollback receipt](receipts/2026-09-20-android-esp-rollback.md).

The PCIe-MEM OPP A/B has not run. Keep the current stock Linux/Game Mode boot
available while resolving the bootc queue and stamp mismatch. The Android
Wireless ADB settings were reasserted before the restart from Android to Linux
(`adb_wifi_enabled=1`,
`persist.adb.tls_server.enable=1`, legacy TCP port unset); persistence after a
future Android reboot is still unverified.

### 2026-09-20 18:44 UTC — queued test deployment removed; stock image normalized

The first `rpm-ostree cleanup --rollback` was a no-op (`Deployments unchanged`).
Read-only `ostree admin status` showed the candidate as the pending deployment
and the old Armada base as the only booted deployment. The exact candidate OCI
image was still present in rootful Podman storage.

`rpm-ostree cleanup --pending` then removed one pending deployment (count
change `-1`, 64.1 MiB freed). `bootc status` now reports the stock beta image
booted, default boot order, no rollback, no queued rollback, and no staged
deployment. OSTree reports only the stock booted deployment. The candidate OCI
tag and digest remain in local Podman storage, so the test can be staged later
without recompilation.

The remaining BLS entry is the stock base. I ran Armada's own
`armada-bootimg-update`; it regenerated `/boot/efi/KERNEL` for vmlinuz-7.2.3,
without rebooting or touching `KERNEL.BAK`. Root-level hashes of both boot
images match the preserved pre-test stock hash
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`. The
active stamp is restored to stock ID
`d7755f13ac5a1224fef222e2d104192045fd01d61924f9b1ae31e941b73f049b`; the
previous-image stamp records candidate ID
`2fde9022665b5aef44d538eb1d4930548627519b16d1a6fe49ca033d3c2a91fe`.

Linux remains healthy after cleanup: systemd is running with no failed units,
Steam's user session is active, and the local Steam CEF target list includes
Big Picture, Main Menu, and Quick Access. The panel was not captured. The
candidate boot still has no SSH or journal evidence from its failed attempt;
the user's “Preparing Armada” observation is the only runtime indication, so
the exact failure point is unknown. The PCIe-MEM OPP suspend A/B has not run.

Wireless debugging's native Android controls were reasserted before the
Android-to-Linux restart (`adb_wifi_enabled=1`,
`persist.adb.tls_server.enable=1`, legacy TCP port unset). Whether the setting
survives another Android boot remains unverified. Full device output and
recovery hashes are in the
[Android rollback receipt](receipts/2026-09-20-android-esp-rollback.md).

### 2026-09-20 18:52 UTC — Android Wireless ADB persistence needs Android access

The recovered Linux boot remains reachable over SSH at `armada`; its boot ID
and kernel are unchanged. `adb devices -l` is empty, and reconnecting to the
previous Android TLS endpoint (`192.168.0.163:45935`) timed out. Linux has no
`adbd` process or listener on the checked ADB ports. The Android `userdata`
partition is `/dev/sda17`; it is unmounted and Linux reports no filesystem
type. I did not attempt to mount or modify it offline.

Before the Android-to-Linux restart, the native Android controls had both been
set to `1` (`adb_wifi_enabled` and `persist.adb.tls_server.enable`), while the
legacy TCP ADB port remained unset. This did not verify persistence through an
Android reboot because the restart selected Linux. To satisfy the user's
request for boot-persistent Wireless debugging, the remaining step is to
install a small Magisk late-start helper once Android is reachable again, then
verify its setting and TLS listener. Keep legacy TCP ADB disabled. No further
device change or reboot was made from this check.

### 2026-09-20 19:23 UTC — Android module transplant is not viable; Linux evidence checked

The user asked whether Android's working sleep path could be reused by
mounting Android or loading its `.ko` files while Armada Linux is running.
The answer is: reuse the request semantics by porting them to Linux, but do not
load the Android binaries. Android runs
`5.15.123-android13-8-g697b78910a71-dirty`; Armada runs `7.2.3`. The exact
Android `dcvs_fp.ko` is built for 5.15.123 with module-versioning enabled,
depends on `cmd-db,qcom_rpmh`, and imports vendor-only
`rpmh_init_fast_path()`/`rpmh_update_fast_path()`. The live Linux symbol table
has `rpmh_write_async()` but neither fast-path symbol, and Linux's captured
config does not enable `CONFIG_MODVERSIONS`. Forcing vermagic could not add
the missing functions or make the kernel ABI compatible.

The current Linux config has `CONFIG_QCOM_RPMH=y`,
`CONFIG_INTERCONNECT_QCOM=y`, `CONFIG_REGULATOR_QCOM_RPMH=y`,
`CONFIG_PCIE_QCOM=y`, and `CONFIG_PCIE_DW=y`; these drivers are built into the
running kernel. The awake read-only snapshot shows the Qualcomm host
`0000:00:00.0` and WLAN endpoint `0000:01:00.0` both in D0, with
`d3cold_allowed=1`. The existing rollback timer is disabled. No module was
loaded, no suspend request or vote was changed, and no reboot or sleep test
was run. The direct module compatibility check and port alternatives are in
[Android module reuse analysis](android-module-reuse.md).

The exact Android MC4/SH5 SLEEP/WAKE_ONLY pair has already been reproduced by
a Linux-native 7.2.3 test module. Its commands appeared in the Apps-RSC trace,
but AOSD/CXSD/scalar DDR did not advance. That tested subset is insufficient
alone in the observed run; it does not exclude regulator-context or coordinated
PCIe/WCN behavior. See the
[DCVS-pair A/B receipt](receipts/2026-09-20-rpmh-dcvs-pair-ab.md).

I checked retained diagnostics after the candidate boot did not return SSH:
the persistent journal index has only the pre-candidate boot and the recovered
stock boot; it has no separate candidate boot ID. Root-read pstore and
`/var/lib/systemd/pstore` contain no crash record. The user's “Preparing
Armada” observation therefore remains the only candidate-boot symptom; the
failure point is still unknown.

The candidate boot image's `ostree=` identifier differs from its staged
container/OSTree checksum, but that is not evidence of a bad path by itself.
On the current stock system, `/ostree/boot.0/default/fe4d.../0` is a symlink to
the actual deployment `ec096...3`, demonstrating that the BLS boot-path key
and deployment checksum are distinct. The candidate link target was removed
by rollback and cannot now be checked. The two saved Android boot images have
the same reported load addresses and page geometry. No source-level boot-image
defect has been established.

No further live Linux suspend A/B is justified while the diagnostic candidate
has an unexplained boot failure and its rollback timer is disabled. Keep the
working stock boot; next resolve boot observability/recovery before staging a
candidate again. Full findings are in
[Android module reuse analysis](android-module-reuse.md).

### 2026-09-20 19:58 UTC — Linux OPP test narrowed; current rollback guard is mismatched

Read-only SSH recheck confirms the Nova remains on stock Armada 7.2.3, boot ID
`aa40c55e-d558-46a9-a710-3a7d926b9e9e`, with `systemd` reporting `running`.
`bootc status --json` shows the original beta digest booted, default boot
order, and no staged or rollback deployment. `/var` has 30 GB free; the
previous OPP candidate image remains in rootful Podman storage. The Qualcomm
root port `0000:00:00.0` is bound to `qcom-pcie`, and WCN endpoint
`0000:01:00.0` is bound to `ath12k_wifi7_pci`; both report D0 and
`d3cold_allowed=1`. The PCIe platform-device sysfs tree has no exposed OPP or
devfreq control. No suspend, reboot, module insertion, vote change, or power
configuration change was made.

Source recheck of the exact Linux 7.2.3 test tree and Armada patches 0513/0520
clarifies the A/B scope. `qcom_pcie_suspend_noirq()` first calls the
DesignWare suspend path. If the host is suspended, deep mode drops the OPP.
If the host stays active after the D3cold veto, the ordinary direct-deep
fallback does not select an OPP for an OPP-managed controller, so the active
500,000/1,000,000 kB/s memory request can remain. The existing non-S2RAM
`opp-suspend` route (including s2idle) already selects the 1,000 kB/s OPP
from patch 0520, with its `min_svs` required corner. The test-only deep-mode
OPP uses `low_svs` like the active 5 GT/s x1 link and changes only the
PCIe-MEM peak to 1,000 kB/s; it intentionally leaves the regular s2idle OPP
and CPU path unchanged. This remains the cleanest available A/B for the
observed direct-deep floor, but it is not proof that bandwidth alone explains
the zero AOSD/CXSD/DDR records.

There is no clean stock-runtime OPP switch exposed to userspace. In the
matching 7.2.3 OPP API, the dynamic `dev_pm_opp_data` contains frequency,
voltage, level, and turbo fields, but no interconnect bandwidth. A temporary
module could select an existing table entry, but the only existing 1,000
kB/s entry requires `min_svs`, so using it would change both bandwidth and
power-domain corner. It would not reproduce the isolated `low_svs` diagnostic
entry. The kernel/DT candidate remains necessary for that single-variable
test.

The existing on-device rollback unit is not a guard for this candidate:
`sm8550-pcie-test-rollback.timer` is disabled, and its service condition only
runs when `pcie_ports=compat` is absent. Both the restored stock boot and OPP
candidate use `pcie_ports=compat`. The earlier candidate failure still has no
separate boot ID or pstore trace; "Preparing Armada" and missing SSH remain
the only observed symptoms. A candidate-specific, image-marked timer could
roll back if systemd starts, but cannot recover a kernel/initramfs failure
before systemd. Do not stage or reboot the OPP image while that early-boot
recovery gap remains. Next prepare and syntax-check the candidate-only guard,
then find an independent observation/recovery path for a pre-systemd stall.

### 2026-09-20 20:05 UTC — candidate-only rollback guard prepared

Added a candidate image marker, a systemd oneshot service that runs
`/usr/bin/bootc rollback --apply`, and an enabled timer scheduled five minutes
after boot. Both units check for the marker, which exists only in the
diagnostic candidate. The candidate Containerfile installs these files and
enables the timer under `timers.target`; the production Armada image and
currently booted system were not changed.

Copied only the two unit files to `/tmp` on the live Nova, ran
`systemd-analyze verify` against them, observed exit status 0, and removed the
temporary copies. No image layer was built or staged. The guard can recover a
candidate that reaches systemd but does not return SSH; it cannot help if the
kernel or initramfs hangs before systemd. The existing disabled
`sm8550-pcie-test-rollback.timer` has a `!pcie_ports=compat` condition and is
not a fallback for this OPP test. Keep the candidate unapplied until the
pre-systemd recovery gap is addressed; if a systemd-only guard is accepted as
partial coverage later, keep it armed through the short A/B and disarm it only
after the evidence is collected.

### 2026-09-20 20:10 UTC — guarded OPP image built and verified, not staged

Built `localhost/armada-pcie-opp-test-guarded:20260920-01` on the Nova from
the pinned Armada beta base using the already-built candidate kernel and Nova
DTB. The kernel and DTB SHA-256 checks passed. Manifest digest is
`sha256:e2ea9a924bd82606036d9f9b0938ba51be850b1633d0895e8a6960b50b21b302`
(reported image size 12.6 GB). The candidate rollback timer is enabled in the
image and gated by a marker file that exists only in that image.

The first `podman run` inspections failed before launching their commands
because the device's Netavark/nftables setup rejects isolated networking.
Retrying with `--network=host` succeeded: `systemd-analyze verify` returned 0,
the marker exists, the `timers.target.wants` symlink points to the timer, and
the image version marker is `20260920.pcie-opp-test-01`. This follows the
already-used build workaround; it did not change device networking policy.

Post-build `bootc status --json` still shows the stock beta deployment booted,
default boot order, and no staged or rollback image. Boot ID remains
`aa40c55e-d558-46a9-a710-3a7d926b9e9e`; `/var` still reports 30 GB free. No
kernel, DTB, boot partition, or active systemd unit changed. The only device
changes are the copied scratch context and local rootful OCI image. Full
artifact and command details are in the
[guarded-candidate receipt](receipts/2026-09-20-pcie-opp-guarded-candidate.md).

The five-minute guard is useful only if the candidate reaches systemd. It does
not solve the unknown pre-systemd boot failure, so the guarded image remains
unstaged and no suspend A/B was run. The next gate is an independent way to
observe/recover a pre-systemd stall or an attended recovery window; then the
guarded candidate can be used for the single-variable PCIe-MEM OPP test.

### 2026-09-20 20:14 UTC — guarded image has a unique boot version

The first guarded image reused the unguarded candidate's
`/usr/lib/armada/version` string, which would make boot identification
ambiguous. Updated the image recipe and built a fresh unique tag:
`localhost/armada-pcie-opp-test-guarded:20260920-02`, version
`20260920.pcie-opp-test-guarded-01`, manifest digest
`sha256:b4560e90b4dfba8631a47c69de91bdcde7f491fa3fb47299b73d828de8e076e0`.
The two guarded image tags remain local; `20260920-01` is superseded and is
not the one to stage. The final image's kernel/DTB hash checks passed,
`systemd-analyze verify` returned 0 inside the image, its candidate marker and
enabled timer link are present, and the pinned stock base has neither marker
nor timer link.

Post-build checks still show the same stock boot ID, bootc default order, and
no staged/rollback deployment. No reboot or suspend was run. The timer is
recovery for a boot that reaches systemd; it does not address the unknown
early-boot gap.

### 2026-09-20 20:18 UTC — rollback semantics and remote recovery rechecked

The Nova is still reachable over SSH on the same stock Linux 7.2.3 boot
(`aa40c55e-d558-46a9-a710-3a7d926b9e9e`). `bootc rollback --help` confirms
that `--apply` reboots into the deployment queued as rollback. The
`bootc-fetch-apply-updates.timer` is masked and inactive, so Armada's automatic
update agent will not race the diagnostic rollback. The guard is therefore
valid for a candidate that reaches systemd and can persistently request the
previous deployment.

The host sees no ADB or fastboot device from the USB connection. On Linux, an
UDC is present, but configfs has no USB gadget configuration; this does not
provide an out-of-band console. A 464-GB SD card is mounted at
`/run/media/armada/sd`, which could hold captured logs but cannot recover an
early boot. The failure boundary remains: a kernel/initramfs hang before
systemd can start the five-minute timer, and no independent reset/boot control
is currently available remotely. The guarded OPP image remains unstaged.

No suspend, reboot, update, storage write, or boot-order change was performed.

### 2026-09-20 20:22 UTC — Linux exposes no remote early-boot rescue control

Checked the currently running Linux boot's command line and recovery-facing
interfaces. `bootctl status` reports “Not booted with EFI”; no EFI variables
were visible, `/dev/watchdog*` is absent, and `/sys/class/watchdog` is empty.
The host's `adb devices -l` and `fastboot devices` lists are empty. This
confirms that the present Linux userspace does not expose an independent
remote boot selector or watchdog device that can be relied on for a failed
pre-systemd candidate boot.

The SSH user cannot read the ESP and passwordless sudo is unavailable, so this
check did not inspect ABL/ESP boot policy. No attempt was made to change
bootloader settings. Current boot ID, kernel, deployment, and boot order remain
stock and unchanged; the diagnostic image remains unstaged. The rollback
timer only closes the post-systemd/network failure case.

### 2026-09-20 20:26 UTC — “Preparing Armada” does not locate the boot stall

Found the exact label in the adjacent `armada-packages/armada-splash` source.
The initramfs unit is
`system/usr/lib/dracut/modules.d/91armada-splash/armada-splash-initrd.service`:
it is ordered after `dracut-pre-mount.service`, writes
`/run/armada/splash/status` as “Preparing Armada,” and starts the splash
launcher from `initrd.target`. Its `KillMode=none` comment says the launcher
intentionally survives switch-root. The installed real-root
`armada-splash-early.service` also writes the same “Preparing Armada” status
from `sysinit.target`.

Therefore the user's unchanged splash screen proves neither that the
candidate remained in initramfs nor that it reached the real-root systemd
timer: the status string is identical across both phases, and the initramfs
display process persists across root switch. This explains why the earlier
screen observation could not localize the failed boot. The guarded image's
five-minute rollback is only effective after real-root systemd starts; do not
count the splash screen as evidence that it will fire. No device state or
boot files changed during this source trace.

### 2026-09-20 20:29 UTC — current boot timing and ABL layout verified read-only

Used one-off sudo authentication for read-only inspection only; no sudoers,
SSH, boot, or device configuration was changed. The current stock boot's
persistent journal shows: systemd running in initrd at 0.898 s;
`armada-splash-initrd.service` starting at 3.545 s; `initrd-switch-root.service`
starting at 4.109 s; real-root `armada-splash-early` logging the same
“Preparing Armada” label at 6.134 s; and the splash advancing to “Starting
Steam” at 16.162 s. This confirms the normal stage order and proves that the
same visible text can persist on both sides of switch-root. It does not show
which stage the prior candidate reached, because that boot has no retained
candidate journal/boot ID.

The mounted ESP contains only `KERNEL`, `KERNEL.BAK`, and Armada's
`.armada-bootimg.id` / `.armada-bootimg.prev.id`. `/sys/firmware/efi/efivars`
is absent, and no EFI loader configuration is present there. Thus no standard
EFI BootNext entry is available from Linux; the known recovery still requires
the device's ABL boot-mode selection. This resolves the read-permission gap
from the prior check but does not provide unattended recovery for a failed
candidate.

The next candidate can gain better phase evidence by adding tiny initrd and
real-root checkpoint records to the mounted external SD, which persists
across boots. That would identify whether switch-root and root-systemd were
reached, but it would not itself recover a failure; do not treat observability
as a substitute for recovery. No candidate was staged and no reboot/suspend
was run.

### 2026-09-20 20:33 UTC — initramfs checkpointing is image-only work

The exact Armada build step is `build_files/55-generate-initramfs.sh`: it
regenerates `/usr/lib/modules/<kver>/initramfs.img` using dracut with the
`ostree`, `armada-splash`, and `armada-ostree-fallback` modules and verifies
the resulting archive with `lsinitrd`. This makes candidate-only initrd phase
instrumentation feasible without compiling the kernel. The current guarded
OPP Containerfile does not regenerate the initramfs, so adding a dracut module
requires an explicit generation/verification step before rebuilding that
candidate.

The package source also shows `KERNEL.BAK` is maintained as a spare for manual
replacement from another system; `armada-bootimg-update` does not configure
an ABL attempt counter or automatic fallback. The `armada-splash-stall`
service is pulled in only with `graphical.target`, so its visible “Waiting
for …” diagnostics cannot help distinguish a failure before graphical boot.
No boot chain or initramfs files were changed.

### 2026-09-20 20:40 UTC — the candidate preserves the stock ESP backup

The guarded PCIe OPP Containerfile includes
`preserve-kernel-backup.conf`. Its systemd drop-in clears only the startup
`--snapshot-prev` option and leaves the boot-image updater command active;
the existing shutdown updater remains. This means the candidate's normal
root-systemd startup will not replace `KERNEL.BAK` with the candidate image.
The stock KERNEL hash previously verified for this base is
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`.

The stock initramfs is 49 MB and was generated with `ostree`,
`armada-splash`, and `armada-ostree-fallback`; it contains no suspend-lab
recovery service. The ESP is `/dev/sda18`, vfat label `ARMADA`, UUID
`81DC-CB41`. The existing `armada-ostree-fallback` only remaps a missing
OSTree boot path to a surviving deployment with the same boot checksum; it
does not choose `KERNEL.BAK` or roll back a boot that hangs.

This gives a concrete but unimplemented guard design: a candidate-only initrd
timer can, if it is still running after a generous startup timeout, mount the
ESP, require `KERNEL.BAK` to match the known-good hash, atomically restore it
to `KERNEL`, set the active image stamp to the known stock ID, and reboot.
The real-root five-minute timer remains responsible after switch-root. The
initrd guard must fail closed on any missing/mismatched file and be validated
inside a rebuilt initramfs before it can justify a device test. It is not yet
implemented, built, or deployed; no device state changed in this inspection.

### 2026-09-20 20:45 UTC — backup stamp is stale; verify by bytes instead

Fresh read-only inspection confirms the Nova is still on stock kernel 7.2.3,
boot ID `aa40c55e-d558-46a9-a710-3a7d926b9e9e`, with no bootc staged or
rollback deployment. Both `/boot/efi/KERNEL` and `KERNEL.BAK` hash to
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`; active
image ID is stock `d7755f13ac5a1224fef222e2d104192045fd01d61924f9b1ae31e941b73f049b`.
The separate `.armada-bootimg.prev.id` still says candidate
`2fde9022665b5aef44d538eb1d4930548627519b16d1a6fe49ca033d3c2a91fe`. This
stale stamp is a leftover from earlier manual recovery and must not be trusted
to identify the backup; the content hash is authoritative.

`CONFIG_FAT_FS=y` and `CONFIG_VFAT_FS=y`, so the initrd kernel can mount the
ESP without loading a filesystem module. The current initrd already contains
`mount`, `umount`, `blkid`, and `systemctl`; it does not show `sha256sum`, so a
candidate dracut module must explicitly include that tool. The pinned candidate
image contains `dracut-108-8.fc44.aarch64`, so initramfs regeneration can be
done in the OCI build without a kernel compile.

The candidate recovery design is updated accordingly: verify the saved
`KERNEL.BAK` bytes against the known stock SHA-256, restore atomically, and
write the known stock active image ID directly. Do not copy the stale
`.armada-bootimg.prev.id`. This was read-only; the active image, ESP, and bootc
state were not changed.

### 2026-09-20 21:19 UTC — Android modules are not mountable Linux sleep hooks

The current goal already covers this question: a mounted Android partition
would only expose its files. Android's `dcvs_fp.ko` is built for
`5.15.123-g697b78910a71-dirty`, while Armada runs `7.2.3`; the module imports
vendor-only `rpmh_init_fast_path()` and `rpmh_update_fast_path()` symbols that
Armada does not export. The Android RPMh regulator module likewise cannot
replace Armada's already-bound built-in mainline driver. The transferable
piece is the firmware request contract, implemented with Linux 7.2.3 APIs.
The previously tested MC4/SH5 request pair is already known insufficient on
its own. No Android partition was mounted and no module was loaded.

To close part of the candidate boot-recovery gap, added a candidate-only
dracut module. Its 120-second initrd-systemd timer is wanted by
`dracut-pre-mount.service` and conflicts with `initrd-switch-root.target`;
when it fires, the helper requires the ESP backup to match the exact known
stock SHA-256, copies it through `KERNEL.TMP`, syncs and verifies the copy,
replaces `KERNEL`, writes the known stock image ID (not the stale previous-ID
stamp), then requests reboot. It fails closed on a missing marker/device,
non-vfat or read-only ESP, missing backup, hash mismatch, or write failure.
The existing five-minute real-root rollback timer remains in the image.

Local `bash -n`, `git diff --check`, and mocked success/failure tests pass. The
tests cover successful restore, wrong backup hash, missing marker, mount
failure, and an already-mounted read-only ESP. The pinned-base OCI build
regenerated the initramfs without compiling the kernel. Its archive contains
the marker, both units, the `dracut-pre-mount` drop-in, helper, and required
utilities; `systemd-analyze verify` passed for both recovery layers. Dracut
printed a nonfatal missing-logger message in the build container but exited
successfully and passed every archive assertion. See the
[initrd recovery receipt](receipts/2026-09-20-pcie-opp-initrd-recovery.md).

The new image is `localhost/armada-pcie-opp-test-initrd-guard:20260920-03`
with digest
`sha256:eaee50deeee62e1135e8b56c57557ce17a19f6c94dc498634e88faea9d310a0a`.
It is not staged or booted. The device remained on stock kernel `7.2.3` with
boot ID `aa40c55e-d558-46a9-a710-3a7d926b9e9e`; no live ESP or bootc state was
changed. This guard starts only after initrd systemd reaches its pre-mount
unit. It cannot recover a kernel hang or an initrd systemd/pre-mount failure,
and the old candidate's precise stall phase is still unknown. ABL remains the
only known recovery for that early failure case, so the PCIe OPP A/B is still
not safe to launch unattended.

### 2026-09-20 21:29 UTC — corrected initrd timer ordering before use

Reviewing the first built guard image (`20260920-03`) exposed an ordering
weakness: its timer was ordered after `dracut-pre-mount.service`, so a hang
inside that service could prevent the timer from starting. That image was never
staged. The corrected version removes the recovery service's dependency on
pre-mount completion and orders the timer before the pre-mount unit. The
existing drop-in wants the timer from that unit, so it starts its countdown as
pre-mount is queued and can recover while that work is stuck. It still cannot
run if the kernel or initrd systemd fails before that unit is queued.

Rebuilt as `localhost/armada-pcie-opp-test-initrd-guard:20260920-04`, version
`20260920.pcie-opp-test-initrd-guard-02`, digest
`sha256:f2aa1e6b6dea32ac27a8324c6215685d0121bfee4ac7e5430e7ddcf179325682`,
image ID `2c67bc32cabdbc2147a02280069414a41bf883ea6a57788be77e31a81de4cc81`.
The regenerated initramfs is 50,081,314 bytes, SHA-256
`c5d3275ea48c03c5f2ee5b64e4bf3b7afba07fc01db9f06998f6643d09ec2369`.
`systemd-analyze verify` passed for both recovery layers, and `lsinitrd -f`
confirmed the timer's `Before=dracut-pre-mount.service` ordering plus the
pre-mount `Wants=` drop-in. The image remains un-staged and un-booted. A fresh
SSH check still reports stock kernel `7.2.3` and boot ID
`aa40c55e-d558-46a9-a710-3a7d926b9e9e`. The corrected guard narrows but does
not close the remaining kernel/initrd-systemd recovery gap.

### 2026-09-20 21:48 UTC — run the generated recovery helper on scratch VFAT

To check the real file operations before considering a candidate boot, ran
the helper extracted from `20260920-04`'s generated initramfs against a
256 MiB loop-backed FAT32 image on the Nova. The extracted script SHA-256
matched the tracked helper. A success case restored a fixture `KERNEL` from
`KERNEL.BAK`, wrote the configured active image ID, preserved the previous
image ID, and reached `systemctl reboot --force`; `systemctl` was a stub, so
the device did not reboot. A second run with an intentionally wrong expected
backup hash returned failure and left the candidate kernel, active ID, and
reboot count unchanged. The backup fixture SHA-256 was
`93140f66a789cdabf4cba3bc6b7dbdd4b162e8b23dbf5af38e74c30ba998e497`.

The Podman container saw only the temporary directory and `/dev/loop-control`
plus `/dev/loop2`; it did not receive `/boot/efi`. The loop was detached and
the scratch directory removed. `bootc status` afterward still showed the
stock beta digest, with no candidate staged. Receipt:
[`2026-09-20-pcie-opp-vfat-helper-test.md`](receipts/2026-09-20-pcie-opp-vfat-helper-test.md).

This closes the helper's scratch-VFAT integration gap, not the boot-recovery
gap. It does not prove the initrd timer starts on the previously failing
candidate path, and it cannot recover a kernel hang or failure before initrd
systemd activates the timer. The OPP candidate remains un-staged; early ABL
recovery is still needed before a test that can fail before this guard starts.

### 2026-09-20 21:55 UTC — persistent journal narrows the previous apply boundary

Read-only inspection of `journalctl -b -1` found the shutdown sequence from the
candidate apply. At 13:07:41 EDT sudo ran
`bootc switch --from-downloaded --apply`; systemd-logind recorded a reboot
initiated by bootc, then OSTree finalized the staged deployment and reported a
bootconfig swap. At 13:08:02 EDT `armada-bootimg-finalize` wrote
`/boot/efi/KERNEL` for `vmlinuz-7.2.3`, and the shutdown sync immediately
reported the kernel as current. The old boot journal ends at 13:08:02.703.

The current persistent boot list contains the old Linux boot ID
`55fdad18019d4c928ebd8a558574c1d3` and current stock boot ID
`aa40c55ed55846a9a7103a7d926b9e9e`; there is no separate candidate Linux
root journal between them. This proves the staged deployment was finalized
and the boot image was rewritten before restart. It does not hash-identify the
rewritten bytes (both images report `vmlinuz-7.2.3`) or establish whether the
candidate reached initrd systemd. The on-screen “Preparing Armada” label still
cannot distinguish initrd from real root. The missing SSH phase remains
unresolved; the previous clean shutdown is not evidence of a successful
candidate boot. See the
[`previous-candidate-reboot-boundary` receipt](receipts/2026-09-20-previous-candidate-reboot-boundary.md).

At 21:58 UTC, checked for a retained kernel trace. `CONFIG_PSTORE=y` and
`CONFIG_PSTORE_RAM=m`, but the root-readable `/sys/fs/pstore` directory was
empty, `/sys/module/ramoops` and `/dev/pmsg0` were absent, and no live
reserved-memory compatible named `ramoops` or `pstore` was found. This leaves
no captured panic/console trace for the candidate boot. Loading ramoops would
require a valid firmware-reserved buffer; do not guess a RAM address.

At 22:00 UTC, checked the attached-USB path from the Mac. `adb devices` and
`fastboot devices` were empty, no Retroid/Android USB product was visible, and
no USB serial node appeared; only macOS `debug-console` and `wlan-debug`
serial nodes were present. The visible USB product was `Ultra`. This adds no
host-side recovery channel if the Nova fails before Linux userspace.

### 2026-09-20 22:06 UTC — fresh stock direct-deep PCIe/RPMh control

Ran a 15-second, RTC-woken direct `deep` control on the unchanged stock image
with the `pcie-d3cold` trace profile. It entered and exited `deep`, returned
success, showed 13.612693 seconds of suspend-clock separation, and woke on the
expected PMIC RTC interrupt. The boot ID remained the same; Wi-Fi returned UP,
and Steam/Gamescope stayed alive. The one-shot RTC alarm and private trace
instance were cleaned. No driver, DT, request, or radio policy was changed.

The root port again vetoed `pci_host_common_d3cold_possible()` in
`PCI_UNKNOWN` (`17cb:0113`, `retval=-95`). Apps-RSC submitted the same six
SLEEP/six WAKE commands, including MC0/SH0 SLEEP `0x600003b8`. AOSD, CXSD,
and scalar DDR stayed zero; APSS SMEM advanced once, separate ADSP/CDSP
records advanced, and detailed DDR ID `0xd0` advanced by 310695345 ticks.
This run did not enable the PSCI system-suspend return probe, so its direct
PSCI return is not newly established by this receipt. The earlier dedicated
PSCI runs remain the evidence for that point. Raw run and hashes:
[`stock deep PCIe/RPMh receipt`](receipts/2026-09-20-stock-deep-pcie-control.md).

This strengthens the repeatability of the observed Linux baseline and keeps
the staged-request versus firmware-acceptance distinction open. It does not
make the PCIe floor causal evidence for zero AOSD/CXSD/DDR residency, so the
candidate OPP remains unbooted until the early-boot recovery gap is covered.

### 2026-09-20 22:43 UTC — Android kernel reuse boundary and earlier initrd guard

The Android-kernel idea is now bounded. A mount, bind mount, chroot, or
container cannot attach Android's sleep `.ko` files to the running Armada
kernel: modules execute only inside the kernel that loads them, and this
device's Android modules target downstream `5.15.123` while Armada runs `7.2.3`.
The exact `dcvs_fp.ko` also imports fast-path RPMh symbols absent from Armada;
the Android RPMh regulator module would conflict with Armada's already-bound
built-in driver. The viable reuse is still to translate request behavior to
Linux 7.2.3 APIs. The completed MC4/SH5 request-only test was insufficient by
itself.

Running Armada user space on the Android kernel is theoretically possible as a
separate hybrid boot, but not by mounting Android while Armada is running. It
would require a repacked Android boot image, a matching initramfs/DTB and
5.15-matched module set, then validation of the OSTree boot flow and Armada's
display/GPU/Wi-Fi stack on that kernel. This is substantially riskier than a
native Linux driver change and would not fix the Linux 7.2.3 path. The exact
Android source remains unavailable and the earlier candidate's pre-systemd
failure recovery is unresolved, so this is not the next experiment. The
expanded analysis is in [`android-module-reuse.md`](android-module-reuse.md).

The candidate-only initrd rollback timer was moved from the pre-mount unit's
drop-in to `basic.target.wants`, with ordering before `basic.target`. This
starts the 120-second timer earlier in initrd boot and still before
`dracut-pre-mount.service`; it does not cover a kernel failure or an initrd
systemd failure before the basic-target transaction starts. The first build
of tag `20260920-05` regenerated the initramfs but its final assertion failed:
the `lsinitrd` symlink row ends with the link target, so the generic `$NF`
matcher did not recognize the link path. The assertion now checks that path
explicitly. Rebuild passed, confirmed the symlink and timer ordering, and
`systemd-analyze verify` passed for both initrd recovery units and the existing
real-root rollback units. Local shell syntax, mocked recovery tests, and
`git diff --check` also pass. The successful image is version
`20260920.pcie-opp-test-initrd-guard-03`, manifest digest
`sha256:ee083828400828329df59ad7ca9084a8a745894d95831efeb8e77a1f1d5688cc`,
image ID `a0455586b6be5aa5770e0afcd69523cd07ca6e849bfe45efc6af7acb3676b0b2`,
and initramfs SHA-256
`9d71e262d0190f220c3cf685b656986fc6001b3cc775ee795460c793aa91379d`.
Dracut emitted its known nonfatal missing-logger warning; the build exited
successfully.

A fresh post-build SSH check still reports stock kernel `7.2.3`, boot ID
`aa40c55e-d558-46a9-a710-3a7d926b9e9e`, Armada image
`20260915.feca679`, default boot order, `staged=null`, and no queued rollback.
Only a local Podman image was added; no bootc deployment, ESP file, reboot, or
suspend state was changed. This guard improves early timer coverage but does
not close the recovery gap, so the PCIe OPP candidate remains un-staged. Full
build and verification details are in the
[`early-target guard receipt`](receipts/2026-09-20-initrd-guard-early-target-build.md).
