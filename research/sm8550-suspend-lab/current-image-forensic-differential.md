# Current-image SM8550 A/B forensic differential

Date: 2026-09-01. Device: Retroid Pocket Nova at `192.168.0.20`, compatible
with `retroidpocket,rpnova`, `qcom,qcs8550`, and `qcom,sm8550`. Image:
Armada `20260830.71e45aa`; kernel `7.2.0`; boot ID
`be074ba4-8dc3-43e0-ac75-77257f38a7fe`.

This is a read-only forensic analysis of existing archives. It did not rerun
either comparison cycle and did not change SDHCI, USB, runtime-PM, clock,
regulator, interconnect, kernel, package, or firmware state. The completed
in-flight repeat G was preserved separately as
`20260901T155052Z-87c9c373b27c`; later clean stock samples brought the
current-image total to 11, exceeding the ten-cycle objective. Remaining blind
repetitions are deferred while the read-only root-cause pass continues.

## Compared runs and method

| Label | Run ID | Requested/observed mode | Signed clock separation | Archive verification |
|---|---|---|---:|---|
| A | `20260901T153527Z-a7399e37863d` | `s2idle` / `s2idle` | 44.414845 s | 4,241 files, no checksum mismatches |
| B | `20260901T153837Z-528c7ba0975a` | `deep` / `deep` | 44.354371 s | 4,241 files, no checksum mismatches |

Both runs had the same no-USB/charger/dock/hub, no-input, microSD-mounted
physical condition. The run agent applied the off-radio policy after its
ordinary `pre/` snapshot and before `armada-sleep-debug prepare`; therefore
radio-specific `pre/` values are the pre-policy values and `post/` values are
before cleanup. The kernel suspend interval itself was off-radio. This timing
limitation is called out wherever it affects interpretation.

The harness calculated separation as
`delta(CLOCK_BOOTTIME) - delta(CLOCK_MONOTONIC)` without clamping. A recorded
`PM: suspend entry`/`PM: suspend exit` pair, same boot ID, zero-return Armada
dispatcher, and `suspend_stats` success increment independently validate both
cycles.

## Executive result

- A and B both entered the requested real kernel mode, woke on the expected
  RTC source, survived without a reset, and had signed clock separation.
- The Qualcomm `aosd`, `cxsd`, and `ddr` records were present, readable, and
  unchanged at absolute zero in both modes. The qcom-stats interface was not
  generally frozen: ADSP, APSS, CDSP, and the separate DDR statistics export
  changed. The evidence therefore supports “no recorded entry into these
  three named SoC low-power states,” not “the parser is reading the wrong
  file” or “all firmware statistics are nonfunctional.”
- The historical SDHCI symptom is absent. `mmc0` advanced only 50 and 52
  interrupts, or 1.126 and 1.172 per measured suspended second.
- The largest unexplained Linux-visible activity is UFS IRQ 169
  (`ufshcd`): 12,766 events in A and 10,653 in B, normalized to 287.426 and
  240.179 per measured suspended second. The UFS controller, host, target,
  boot/root LUN, and UFS clocks are runtime-active in the snapshots. No UFS
  error, timeout, fatal, abort, or reset line was recorded, so this is a lead,
  not yet a causal diagnosis.
- The USB DWC3 root is runtime-suspended before the run and active after
  resume; no xHCI device or attached USB device exists. The Qualcomm combo
  PHY `88e8000.phy` is active with `power/control=on` in both snapshots, and
  its USB clocks/regulators appear enabled in the post-resume snapshot. This
  is a secondary USB/PHY lead, not proof that it blocked the low-power state.
- ADSP is not supported as the primary explanation. The exact kernel mapping
  makes it a firmware subsystem sleep statistic; both runs had zero open PCM
  devices, DAPM was off apart from HDMI codec standby, and Armada's own
  diagnostic reported about 99% ADSP sleep over its coarse collection window.

## 1. Qualcomm stats validity

### Raw inventory and parser scope

Both A and B captured the same 17 files in both `pre/` and `post/` under
`/sys/kernel/debug/qcom_stats`:

```text
adsp  adsp_island  aosd  apss  cdsp  cdsp1  cxsd  ddr  ddr_stats
display  gpdsp0  gpdsp1  gpu  modem  slpi  slpi_island  wpss
```

The complete raw files are retained at, for example:

```text
/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T153527Z-a7399e37863d/device/pre/files/sys/kernel/debug/qcom_stats/
/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T153527Z-a7399e37863d/device/post/files/sys/kernel/debug/qcom_stats/
/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T153837Z-528c7ba0975a/device/pre/files/sys/kernel/debug/qcom_stats/
/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T153837Z-528c7ba0975a/device/post/files/sys/kernel/debug/qcom_stats/
```

The corresponding `qcom_stats.json` files retain every raw text read. The
second possible harness directory, `/sys/kernel/debug/qcom_sleep_stats`, did
not appear in either archive. The files `cdsp1`, `display`, `gpdsp0`,
`gpdsp1`, `gpu`, `modem`, `slpi`, `slpi_island`, and `wpss` were present but
returned empty raw text in the four captures; that is an empty export/no
payload observation, not a claim about why firmware supplied no record.

For the scalar `Count` records, the absolute raw fields are shown below as
`count / last_entered_at / last_exited_at / accumulated_duration`. `empty`
means the exact raw file had no parsed fields.

| File | A pre | A post | B pre | B post |
|---|---|---|---|---|
| `adsp` | `1564 / 7614706052 / 7614546762 / 7123369308` | `1854 / 8794603124 / 8794592845 / 8132812353` | `2153 / 11099852090 / 11099841453 / 10751847383` | `2335 / 12421731005 / 12421721253 / 11753368234` |
| `adsp_island` | `60 / 319421103 / 320285767 / 71795050` | unchanged | `60 / 319421103 / 320285767 / 71795050` | unchanged |
| `aosd` | `0 / 0 / 0 / 0` | unchanged | `0 / 0 / 0 / 0` | unchanged |
| `apss` | `empty` | `2 / 8050194994 / 8764317850 / 852393523` | `2 / 8050194994 / 8764317850 / 852393523` | `3 / 11541532442 / 12393084174 / 1703945255` |
| `cdsp` | `4 / 790410454 / 789964463 / 7581336178` | `4 / 790410454 / 789964463 / 8594398086` | `4 / 790410454 / 789964463 / 11218308800` | `4 / 790410454 / 789964463 / 12222695321` |
| `cxsd` | `0 / 0 / 0 / 0` | unchanged | `0 / 0 / 0 / 0` | unchanged |
| `ddr` | `0 / 0 / 0 / 0` | unchanged | `0 / 0 / 0 / 0` | unchanged |

Thus the named scalar deltas are:

| Statistic | A delta | B delta |
|---|---:|---:|
| `adsp` count | +290 | +182 |
| `adsp` accumulated duration | +1,009,443,045 | +1,001,520,851 |
| `adsp_island` count/duration | 0 / 0 | 0 / 0 |
| `aosd` count/duration | 0 / 0 | 0 / 0 |
| `apss` count/duration | +2 / +852,393,523 | +1 / +851,551,732 |
| `cdsp` count/duration | 0 / +1,013,061,908 | 0 / +1,004,386,521 |
| `cxsd` count/duration | 0 / 0 | 0 / 0 |
| `ddr` count/duration | 0 / 0 | 0 / 0 |

### Separate `ddr_stats` export

`ddr_stats` is not the scalar `ddr` record. Its complete raw text contains
four DDR LPM mode codes and ten frequency rows. The three non-`0xd0` LPM
codes remained zero in both runs. The `0xd0` LPM row retained count 1 but its
duration changed:

| Raw row | A pre -> post | A duration delta | B pre -> post | B duration delta |
|---|---|---:|---|---:|
| `DDR LPM Stat Name:0xd4` | `0/0 -> 0/0` | 0 | `0/0 -> 0/0` | 0 |
| `DDR LPM Stat Name:0xd3` | `0/0 -> 0/0` | 0 | `0/0 -> 0/0` | 0 |
| `DDR LPM Stat Name:0x11` | `0/0 -> 0/0` | 0 | `0/0 -> 0/0` | 0 |
| `DDR LPM Stat Name:0xd0` | `1/7796395275 -> 1/8809458327` | +1,013,063,052 | `1/11433371820 -> 1/12437751837` | +1,004,380,017 |

The notation in this table is `count/duration_ticks`. Nonzero frequency
duration changes were:

- A: 1555 MHz `+913,887,232`, 1708 MHz `+34,103,808`, 2736 MHz
  `+45,894,656`, 3187 MHz `+1,307,136`, and 3686 MHz `+17,869,824` raw
  ticks; all other frequency rows were unchanged.
- B: 3686 MHz `+1,004,380,160` raw ticks; all other frequency rows were
  unchanged.

The raw DDR frequency/LPM numbers are deliberately not converted to seconds:
the Linux driver prints them as firmware “ticks,” and the source does not
define a universal conversion for these DDR rows.

### Exact kernel semantics and classification

The current Armada kernel package is configured with `CONFIG_QCOM_STATS=y`
and `CONFIG_QCOM_AOSS_QMP=y` in its current 7.2 package configuration. The
package build script fetches Linux `7.2`, and the device reports kernel
`7.2.0`. The exact upstream driver inspected is
[Linux v7.2 `drivers/soc/qcom/qcom_stats.c`](https://github.com/torvalds/linux/blob/v7.2/drivers/soc/qcom/qcom_stats.c);
the format and meaning are also described by the
[Linux qcom-stats binding](https://github.com/torvalds/linux/blob/v7.2/Documentation/devicetree/bindings/soc/qcom/qcom-stats.yaml).

For the `qcom,rpmh-stats` configuration used by this driver, Linux creates
three mapped SoC sleep records and names them from their firmware stat types;
the source configuration has three records at the RPMh stats area and also
exports subsystem records from SMEM. The source prints `Count`, last entry,
last exit, and accumulated duration. It adjusts the accumulated value when a
subsystem is still asleep at read time. The separate DDR reader sends the
SM8450-and-newer QMP `freqsync` request before reading the DDR LPM/frequency
table.

The local harness parser is intentionally simpler but is reading the correct
interface: it enumerates `/sys/kernel/debug/qcom_stats`, parses only the
colon-delimited scalar fields, and retains the exact raw text beside them.
It does not use `ddr_stats` as the scalar `ddr` value. The raw interface and
the independent changes in ADSP/APSS/CDSP/DDR frequency data rule out the
parser simply reading a permanently stale or unrelated statistic.

**Classification:** (a), with a precise scope: the exposed scalar `aosd`,
`cxsd`, and `ddr` records are live, valid-looking RPMh sleep records and show
no recorded entry into those three named states in either A or B. This does
not claim that every DDR low-power mode was absent, because `ddr_stats` is a
different export and changed. There is no evidence here for (b) “firmware
nonfunctional” and no evidence for (c) “wrong parser statistic.”

## 2. Full interrupt differential

The harness parsed all 126 IRQ IDs present in each A/B before/after pair. A
had 34 IRQs with nonzero total deltas and 44,150 positive events; B had 33
with 40,886 positive events. There were no negative deltas. The table lists
every nonzero row in either pair. The rate is total delta divided by the
measured signed suspended interval, not by the short dispatcher job time.

The complete unmodified before/after raw captures are:

```text
/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T153527Z-a7399e37863d/device/pre/files/proc/interrupts
/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T153527Z-a7399e37863d/device/post/files/proc/interrupts
/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T153837Z-528c7ba0975a/device/pre/files/proc/interrupts
/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T153837Z-528c7ba0975a/device/post/files/proc/interrupts
```

| IRQ | Details | A delta / s | B delta / s |
|---:|---|---:|---:|
| 11 | GICv3 27 Level arch_timer | +19677 / 443.028 | +19367 / 436.642 |
| 169 | GICv3 297 Level ufshcd | +12766 / 287.426 | +10653 / 240.179 |
| 14 | GICv3 37 Level apps_rsc | +8163 / 183.790 | +7751 / 174.752 |
| 187 | GICv3 494 Level qcom_geni_serial_uart2 | +770 / 17.337 | +734 / 16.549 |
| 198 | msmgpio 13 Edge pwm-fan | +764 / 17.201 | +720 / 16.233 |
| 232 | ipcc 196608 Edge glink-smem | +461 / 10.379 | +268 / 6.042 |
| 13 | GICv3 261 Level ipcc_0 | +350 / 7.880 | +189 / 4.261 |
| 185 | GICv3 618 Level 890000.i2c | +226 / 5.088 | +226 / 5.095 |
| 188 | GICv3 385 Level a80000.i2c | +226 / 5.088 | +226 / 5.095 |
| 167 | GICv3 499 Level 98c000.i2c | +197 / 4.435 | +197 / 4.442 |
| 221 | ITS-PCI-MSI-0000:01:00.0 5 Edge ce2 | +136 / 3.062 | +110 / 2.480 |
| 33 | GICv3 38 Level arch_mem_timer | +93 / 2.094 | +98 / 2.209 |
| 170 | GICv3 239 Level mmc0 | +50 / 1.126 | +52 / 1.172 |
| 218 | ITS-PCI-MSI-0000:01:00.0 2 Edge mhi | +37 / 0.833 | +36 / 0.812 |
| 201 | GICv3 332 Level gpu-irq | +36 / 0.811 | +36 / 0.812 |
| 162 | msm_mdss 0 Edge msm | +35 / 0.788 | +37 / 0.834 |
| 222 | ITS-PCI-MSI-0000:01:00.0 6 Edge ce3 | +31 / 0.698 | +29 / 0.654 |
| 36 | GICv3 113 Level 24091000.pmu | +25 / 0.563 | +27 / 0.609 |
| 37 | GICv3 613 Level 240b6400.pmu | +23 / 0.518 | +29 / 0.654 |
| 191 | msm_mdss 4 Edge dsi_isr | +21 / 0.473 | +21 / 0.473 |
| 186 | GICv3 493 Level qcom_geni_serial_uart1 | +14 / 0.315 | +15 / 0.338 |
| 15 | ipcc 0 Edge aoss-qmp | +8 / 0.180 | +8 / 0.180 |
| 217 | ITS-PCI-MSI-0000:01:00.0 1 Edge mhi | +8 / 0.180 | +8 / 0.180 |
| 224 | ITS-PCI-MSI-0000:01:00.0 8 Edge DP_EXT_IRQ | +6 / 0.135 | +8 / 0.180 |
| 227 | ITS-PCI-MSI-0000:01:00.0 11 Edge DP_EXT_IRQ | +6 / 0.135 | +12 / 0.271 |
| 216 | ITS-PCI-MSI-0000:01:00.0 0 Edge bhi | +5 / 0.113 | +5 / 0.113 |
| 171 | GICv3 255 Level 8804000.mmc | +3 / 0.068 | +3 / 0.068 |
| 219 | ITS-PCI-MSI-0000:01:00.0 3 Edge ce0 | +3 / 0.068 | +3 / 0.068 |
| 220 | ITS-PCI-MSI-0000:01:00.0 4 Edge ce1 | +3 / 0.068 | +3 / 0.068 |
| 226 | ITS-PCI-MSI-0000:01:00.0 10 Edge DP_EXT_IRQ | +3 / 0.068 | 0 / 0.000 |
| 168 | msmgpio 15 Edge ft5426 | +1 / 0.023 | +1 / 0.023 |
| 200 | pmic_arb 6431283 Edge pm8xxx_rtc_alarm | +1 / 0.023 | +1 / 0.023 |
| 228 | ITS-PCI-MSI-0000:01:00.0 12 Edge DP_EXT_IRQ | +1 / 0.023 | +6 / 0.135 |
| 229 | ITS-PCI-MSI-0000:01:00.0 13 Edge DP_EXT_IRQ | +1 / 0.023 | +7 / 0.158 |

The repeated high rows are arch timer, UFS host controller, and apps RSC.
The UFS rate is the main unexplained storage-related signal. The `mmc0` row
is not a tens-per-second storm, and the companion `8804000.mmc` IRQ is only
three events in each pair. The microSD remained mounted and no SDHCI device
was unbound or altered.

This differential cannot prove that every UFS event occurred during the
lowest-power subinterval: the snapshots bracket suspend plus the small
resume/capture interval. The kernel PM trace nevertheless shows UFS noirq
suspend/resume callbacks completing successfully in both modes, so the IRQ
counter is a concrete attribution target for the next experiment.

## 3. Runtime-PM and device differential

The A and B archives each contain 389 device records and 15 class records.
Neither archive exposed a readable `power/runtime_usage` field for any record
(0 fields in both device and class captures), so an active runtime usage count
cannot be claimed from these files. `runtime_status`, `runtime_active_time`,
and `runtime_suspended_time` are reported below where available. A post value
is an after-resume snapshot, not an in-suspend state.

| Subsystem | A pre -> post | B pre -> post | Suspend evidence and interpretation |
|---|---|---|---|
| DWC3 Qualcomm controller `a600000.usb` | `suspended -> active`; active time `15433 -> 19307`; `control=auto` | `suspended -> active`; `22181 -> 26049`; `control=auto` | `genpd_suspend_noirq` returned 0 in 18 us (A) / 15 us (B); resume noirq returned 0. `dwc3_qcom_pm_resume` returned 0 after 42.698 ms / 36.398 ms. The post-active state is after resume. |
| xHCI and attached USB | No xHCI record; DWC3 UDC `state=not attached` | Same | No attached USB device was captured. `lsusb` is not installed, so enumeration was not independently probed. |
| Qualcomm USB PHYs | `88e8000.phy` active/on -> active/on; active `404084 -> 412314`; EUSB2/QMP UFS status unsupported | `88e8000.phy` active/on -> active/on; `548926 -> 556753`; EUSB2/QMP UFS status unsupported | Combo PHY, EUSB2 HS PHY, EUSB2 repeater, and UFS/PCIe PHY noirq callbacks returned 0. The combo PHY remains a concrete always-on snapshot lead. |
| SDHCI/MMC | `8804000.mmc` suspended -> suspended; `mmc0:59b4` suspended -> active | Same; active-time root `3698 -> 4084`; card `64929 -> 67690` | `pm_runtime_force_suspend`, genpd noirq, and `mmc_bus_resume` returned 0. The active card post-state follows resume; no IRQ storm. |
| UFS | controller active -> active; host/target active; LUNs 49488 and 0 active, data LUNs mostly suspended | controller active -> active; same topology | Controller runtime suspended time stayed unchanged within each pair (`226086` A, `307401` B) while active time rose `+8230` / `+7839`. Genpd noirq and `ufshcd_system_resume` returned 0. IRQ 169 was +12766 / +10653. Rootfs is under UFS LUN 0; no unmount/unbind was attempted. |
| PCIe root and endpoint | root active; endpoint `0000:01:00.0` active, `control=on`, ath12k driver | same | qcom-pcie and ath12k late/noirq/resume callbacks returned 0. Endpoint active status is after resume and pre-radio policy timing must be considered. |
| ath12k/WLAN | `wlp1s0` up in pre, down/blocked in post; PCIe endpoint active | same | Off-radio policy was applied after `pre/`; ath12k suspend-late/noirq and resume completed without error. |
| Bluetooth transport | hci0 class runtime unsupported | same | `qcom_geni_serial 898000.serial` and `hci_uart_qca serial0-0` suspend/resume callbacks returned 0. No runtime usage count was available. |
| Remoteprocs / ADSP | remoteproc0/1 `state=running`, runtime unsupported; genpd proxies suspended | same | q6v5/smp2p suspend/resume callbacks returned 0. “running” is Linux remoteproc state, not proof that firmware stayed out of low power. |
| Display/GPU | primary DSI PHY active; secondary DSI PHY suspended; DSI connected/enabled | same | MDSS/DPU/DSI noirq callbacks and GPU resume completed without error. No display functional test was run. |

The most important runtime facts are therefore UFS active, PCIe/WCN endpoint
active, and combo PHY active/on. The DWC3 root is not evidence of an attached
USB workload, and every system-PM callback named above returned success.

## 4. Clocks, regulators, and interconnects

Complete `clk_summary` and `regulator_summary` outputs were captured in every
A/B pre/post archive:

| Interface | Availability | Raw content |
|---|---|---:|
| `/sys/kernel/debug/clk/clk_summary` | present in A/B pre/post | 119,055 payload bytes each |
| `/sys/kernel/debug/regulator/regulator_summary` | present in A/B pre/post | 7,987 payload bytes each |
| `/sys/kernel/debug/interconnect/*` | no file in either archive; current live debugfs probe also found no interconnect summary path | unavailable |

The exact clock and regulator files are under each run's
`device/{pre,post}/files/sys/kernel/debug/` directory. Because these are
before/after-resume snapshots rather than an in-suspend sample, a post-only
enable does not prove a clock remained enabled for the whole sleep interval.

### Nonzero consumers and changes

- UFS has multiple nonzero clock references before and after the run, with
  consumers `ufshc@1d84000`/`1d84000.ufshc`: UFS PHY symbol, AHB, AXI,
  UNIPRO, pad-reference, and core clocks. Representative enable-count
  changes were 36 -> 37 in A and 49 -> 50 in B for the UFS clock consumers.
  UFS regulators have nonzero consumers including `1d84000.ufshc-vccq`,
  `1d84000.ufshc-vdd-hba`, and `1d84000.ufshc-vcc`.
- PCIe has nonzero `pcie0_pipe_clk`, PCIe auxiliary/AXI/config clocks, and
  `gcc_ddrss_pcie_sf_qtb_clk` consumers rooted at `pcie@1c00000`.
- USB3 clocks were mostly disabled in the A/B pre snapshots but appeared
  enabled after resume: the USB3 master, mock-UTMI, sleep, reference, aux,
  and pipe clocks gained consumers at `usb@a600000`/`88e8000.phy`. This
  matches the combo PHY's active/on runtime state and is worth attributing,
  but it is not an in-suspend measurement.
- Audio clock output has nonzero LPASS hardware dcodec/macro references and
  MCLK/fsgen references. The same archives show no open PCM and DAPM bias
  `Off` for the audio paths, with only the HDMI codec at `Standby`; clock
  references alone do not establish an active audio stream.
- SDHCI regulators `8804000.mmc-vqmmc` and `8804000.mmc-vmmc` have nonzero
  consumers. The post snapshot changes the vqmmc current reading, but not its
  consumer count. No SDHCI control was changed.
- Regulator post snapshots show combo/EUSB2 PHY consumer references being
  restored after resume (`88e8000.phy-vdda-phy`, `88e8000.phy-vdda-pll`, and
  related EUSB2 supplies). These are resume-state observations, not proof of
  a persistent suspend vote.
- The available archives contain no direct CX, DDR, LLCC, or interconnect
  vote/value table. Kernel PM logs do show qnoc, LLCC, RPMh regulator, and
  RPMh power-controller suspend/resume callbacks completing successfully.

## 5. Armada diagnostics and current interpretation

The device-side `/usr/bin/armada-sleep-debug` hash was
`a1e7d2e4a1866032098e52887851e12520d6e8bef070a50825a43b361b03d899`, matching
the current checkout's
[Armada `armada-sleep-debug`](../../system_files/usr/bin/armada-sleep-debug).
The implementation was inspected directly.

Its relevant semantics are explicit:

- It labels `aosd` as chip-wide AOSS deep sleep, `cxsd` as CX rail collapse,
  and `ddr` as DDR self-refresh.
- It saves a qcom baseline only for files containing the exact scalar
  `Count:` and `Accumulated Duration:` lines. The separate `ddr_stats` table
  has no top-level `Count:` line, so Armada's stock report omits it. The lab
  harness retains it and therefore has strictly more raw evidence than the
  stock summary.
- It prints the interpretation
  `reading=aosd/cxsd/ddr deltas of 0 across a real suspend mean the SoC rails
  never powered down` when those named deltas are zero.
- It computes ADSP sleep percentage from accumulated ADSP ticks using a
  19.2 MHz assumption and a coarse `prepare -> collect` wall window. A near
  zero percentage is its warning for an open audio path; it separately counts
  open PCMs at prepare.

The A report showed `window_seconds=52`, `real_sleep_this_boot=44s across 24
timekeeping cycles`, `adsp_sleep_pct_of_window=99.2%`, and
`open_pcms_at_prepare=0`. The B report showed the same 52-second collection
window, `real_sleep_this_boot=89s across 25 timekeeping cycles`,
`adsp_sleep_pct_of_window=98.9%`, and `open_pcms_at_prepare=0`. The B
“89 seconds” is cumulative current-boot diagnostic output, not a per-run
measurement; the harness's signed clock separation is the per-run evidence.

The stock diagnostic and the harness agree on the named scalar conclusion,
but the harness preserves the raw file set, separates `ddr_stats`, and keeps
the independent clock and kernel-marker evidence visible.

## 6. ADSP determination

Linux v7.2's qcom-stats source maps the `adsp` record to SMEM item 606, PID 2,
and the generic stats binding defines the count as low-power-mode entries with
last entry/exit and accumulated sleep duration. Therefore the ADSP count is
not an audio PCM period count, IRQ count, or proof that an audio stream is
open.

The A/B facts are:

- ADSP count rose by +290 in A and +182 in B. Under Armada's 19.2 MHz
  diagnostic conversion, the raw duration deltas are about 52.575 s and
  52.163 s, respectively; they exceed the precise 44.415/44.354-second
  clock separations because the Qualcomm driver adjusts an in-progress sleep
  statistic at read time and the stock tool uses a coarse collection window.
  These values must not be treated as a direct energy or wall-time meter.
- All three captured PCM status files were `closed` before and after each
  run. `audio.json` reported `open_pcm=[]` in all four phases.
- DAPM bias was `Off` for the ASoC paths in both runs; only the HDMI audio
  codec was `Standby`. No audio playback or capture functional test was run.
- ADSP and CDSP Linux remoteproc devices remained `state=running`, while
  their genpd proxy records were `runtime_status=suspended`. The q6v5/smp2p
  system-PM callbacks returned 0.
- Armada's own ADSP sleep percentage was 99.2%/98.9%, not near its open-audio
  warning condition.

**Conclusion:** the high ADSP count represents repeated ADSP firmware
low-power entries during these captures. Existing evidence does not make an
open PCM/audio path a plausible primary reason for the zero AOSD/CXSD/DDR
records. The ADSP behavior remains an observation to retain in later runs,
not a fix target.

## Ranked hypotheses

1. **UFS host/IRQ activity — strongest current lead, not proven causal.**
   IRQ 169 is 240–287/s by the requested normalization; the UFS controller,
   host, target, boot LUN, rootfs LUN, UFS clocks, and regulators are active
   in the available snapshots. No error line explains the activity. The
   snapshot boundary means a timestamped IRQ attribution is still required.
2. **PCIe/WCN and the always-on combo PHY — credible secondary lead.** The
   ath12k endpoint and PCIe root are runtime-active with `control=on`, and
   `88e8000.phy` is runtime-active/on. USB3 PHY clocks/regulators appear in
   the post-resume state despite no attached USB device. All suspend callbacks
   succeed, so ownership and timing—not a guessed USB patch—must be proved.
3. **RPMh/RSC or firmware low-power-state policy — unresolved platform-level
   possibility.** `apps_rsc` is the third-largest IRQ row and qnoc/RPMh/LLCC
   callbacks run, but the archives have no interconnect vote dump and no
   direct firmware trace. The valid changing qcom records argue against
   declaring qcom-stats firmware dead.
4. **Audio/ADSP — low support.** The ADSP counter is valid and active, but
   the open-PCM, DAPM, and stock ADSP-sleep evidence do not show a live audio
   stream blocking system sleep.
5. **SDHCI/microSD IRQ storm — not supported by this A/B pair.** `mmc0` is
   about 1.1/s, the SDHCI controller is runtime-suspended, and system-PM
   callbacks succeed. Do not unbind or patch SDHCI on this evidence.

## Unknowns

- `/proc/interrupts` before/after snapshots cannot timestamp every event
  inside the pure low-power subinterval; UFS IRQ 169 must be traced around the
  suspend boundary before causality is assigned.
- Runtime usage-count files were absent/unreadable in all 808 captured
  records. Runtime-active status and regulator/clock consumer references are
  not interchangeable with a numeric usage count.
- No interconnect summary or equivalent vote-value debugfs file was available
  in the archives or the current live debugfs probe.
- The qcom DDR LPM code `0xd0` is printed as an opaque firmware code by the
  Linux driver; its raw duration changes, but this pass does not assign it a
  higher-level state name.
- Empty SMEM-backed qcom files are present but contain no text; the archives
  cannot distinguish absent firmware payload from a deliberately unused
  record.
- No functional gamepad, touch, audio, USB, Steam UI, or game test was run in
  A or B. Display/input inventory survived, but that is not end-user
  acceptance.

## Exactly one recommended next experiment

Run one current-stock, off-radio, 45-second **deep** cycle with a run-scoped,
reversible trace capture focused only on UFS IRQ 169 and the UFS host's
runtime/system-PM activity. Capture IRQ handler timestamps, UFS PM/request
events, the existing `/proc/interrupts` and `runtime_*` snapshots, and the
same qcom-stats/clock evidence. Restore trace settings automatically after
resume.

Keep the microSD inserted and mounted, keep the internal UFS rootfs mounted,
and do not unbind, reset, or change power/control values for UFS, SDHCI, USB,
PCIe, or PHY devices. Use the same no-cable/no-input condition. This one
experiment also supplies the next reliability sample. If IRQ 169 is active
through the actual low-power interval or UFS remains active in the relevant
PM phase, pursue UFS ownership/PM tracing; if it is only pre/post capture
traffic, the next investigation target becomes the combo PHY/PCIe path. No
kernel or package patch is recommended or authorized by this result.

## Recommended experiment execution record

The recommended trace experiment was executed as current-stock run
`20260901T162647Z-5c6d44f7dcf7` and its complete archive is retained at
`/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T162647Z-5c6d44f7dcf7`.
It completed deep suspend/resume successfully with signed clock separation of
`43.485335` seconds, an RTC wake, an unchanged boot ID, and no new health
errors. Its private trace instance had zero per-CPU overruns or dropped
events. IRQ 169 and UFS command activity were present around the transition,
but no IRQ-169 handler event occurred across the no-IRQ suspend boundary; the
raw `/proc/interrupts` delta therefore cannot be treated as a proven
in-suspend rate because post-resume collection contributes to it. The UFS
controller and PHY completed system and no-IRQ suspend/resume callbacks with
`err=0`. The archive and notebook retain the full event counts and the
`[local]` trace-clock limitation.

This execution did not identify a causal UFS blocker. The ten uninstrumented
current-image stock reliability cycles were then completed separately, all
passing the harness success gates. No kernel or package patch was made.

The final archive reconciliation found one additional clean current-image
policy sample, `20260901T154437Z-64317bfc6a02`, which was indexed in the lab
notebook after this document's initial count. The completed total is therefore
11 uninstrumented current-image clean cycles; the ten-cycle reliability target
is exceeded. No original run ID or receipt was rewritten.

## Read-only live debugfs follow-up

The earlier A/B archive facts above are preserved: neither A nor B contains an
in-suspend interconnect vote dump, and their archive-time live probe did not
find one. A later read-only root preflight on the same current image found that
the interfaces are available now. This supersedes only the availability
statement; it does not add suspend-window data to A or B.

Receipt:
`/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T170713Z-4aa81059d0be.json`.
It captured Armada `20260830.71e45aa`, image digest
`sha256:cae66b751f6376c7a2da84e7bca7fa81293e9689f7cc9b6bd682ebe83d852c25`,
Linux `7.2.0`, model `Retroid Pocket Nova`, and the complete output of the
root-only diagnostic inventory.

- The four `qcom_aoss` nodes
  `prevent_ddr_collapse`, `prevent_cx_collapse`, `prevent_aoss_sleep`, and
  `ddr_frequency_mhz` all rejected a read with `EINVAL`/`Invalid argument`.
  No write was attempted. They are not usable as read-only scalar state
  evidence on this build.
- `interconnect_summary` and `interconnect_graph` were readable. Their full
  344-line and 565-line outputs are in the receipt. Awake-state summary rows
  include nonzero LLCC/EBI and display activity, a PCIe peak of `500000`, and
  `qns_llcc` average/peak of `1471610/9600000`; UFS and USB endpoint rows are
  present but zero in this awake snapshot.
- `pm_genpd_summary` was readable in full. The awake snapshot reports `cx`
  and `mmcx` on with usage `64`, UFS and PCIe GDSC/domain references on with
  usage `64`, USB PHY/GDSCs on while the DWC3 device is suspended, and the
  display domain active. The RSC device `17a00000.rsc` is runtime-suspended.
  These are genpd statuses/usages, not proof of state during the 45-second
  low-power interval.
- `cmd-db` is mode `-r-------- root root` with debugfs-reported size zero, but
  `cat` returns the complete 162-line/5,893-byte dump. It names the relevant
  ARC resources (`cx.lvl`, `ebi.lvl`, `ddr.lvl`, `mmcx.lvl`), BCM resources
  (`MC0`, `SH0`, `SN0`, `CN0`, `QUP0/1`, `ACV`), and VRM resources (`vrm.aoss`,
  `vrm.wlan`, `vrm.cx`, `vrm.ebi`). The dump is a CMD-DB descriptor map, not
  a live vote readback. Its SHA-256 is
  `3859059d49db26681cafdac268b6abed10c3003d23370e0dd85c419de4756e0d`.

The current package provenance remains `armada-os/armada-packages` main at
`2c93e73cbe1bcf4d443495e94fbaa5e7a8cf7141`: its Linux 7.2 manifest carries
Armada's `0513`/`0520` SM8550 PCIe suspend-OPP pair and the existing `0122`
SM8550 interconnect QoS change, but no RSC/AOP diagnostic patch. The current
Armada checkout is `71e45aa956ad53834ebaaefd6070f28f43d4462d`; it ships
`armada-sleep-debug` and `suspend-dispatch`, but no AOP debug executable. The
external `jaewun/qcom-aop-debug` tree is documentation/experimental tooling,
not proof of a firmware-compatible Nova monitor interface, and its raw-QMP
warning is why no sender or monitor command was invoked.

Disposition: no additional device experiment is selected from this awake-only
inventory. The evidence boundary is now a source-level review/design of
observation-only RSC/CMD-DB/AOP instrumentation that can be built through the
supported Armada package path; no kernel/package change has been made.

## RPMh address reverse mapping and sleep-set contents

This section uses only the completed RPMh trace
`/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T164522Z-62f40512d811/device/raw/trace/trace.txt`
and the complete current-device CMD-DB dump in the final read-only preflight
`/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T172752Z-d0cace201f60.json`.
No device state was changed.

Linux v7.2 defines the RPMh command address as a slave/accelerator ID plus a
resource offset. Its CMD-DB implementation compares ARC and BCM addresses
exactly; for VRM it ignores the low sub-address bits so the voltage, enable,
mode, and related four-byte commands resolve to one resource. That is the
same matching rule used by the reviewed upstream reverse-lookup proposal.
The current dump has ARC v16.0, BCM v16.0, and VRM v1.0 sections. All 38
unique addresses seen across `rpmh_send_msg` and `rpmh_tx_done` were mapped;
the grouped VRM rows below show the CMD-DB base and sub-address explicitly.
The last column is `rpmh_send_msg` / `rpmh_tx_done` count.

| Accelerator | Trace address or addresses | Current CMD-DB resource | Send / done |
|---|---|---|---:|
| ARC | `0x30000` | `cx.lvl` | 5 / 5 |
| ARC | `0x30010` | `mx.lvl` | 3 / 3 |
| ARC | `0x30030` | `lcx.lvl` | 2 / 2 |
| ARC | `0x30040` | `lmx.lvl` | 2 / 2 |
| ARC | `0x30080` | `mmcx.lvl` | 2 / 2 |
| ARC | `0x30090` | `nsp.lvl` | 2 / 2 |
| ARC | `0x300a0` | `mxc.lvl` | 3 / 3 |
| VRM | `0x41204` (`0x41200 + 0x04`) | `ldob5` | 1 / 1 |
| VRM | `0x41500`, `0x41504`, `0x41508` | `ldob8` base `0x41500` plus offsets `0x00/0x04/0x08` | 1 / 1, 2 / 2, 2 / 2 |
| VRM | `0x41600`, `0x41604`, `0x41608` | `ldob9` base `0x41600` plus offsets `0x00/0x04/0x08` | 1 / 1, 2 / 2, 2 / 2 |
| VRM | `0x41e04`, `0x41e08` | `ldog1` base `0x41e00` plus offsets `0x04/0x08` | 2 / 2, 2 / 2 |
| VRM | `0x42004` (`0x42000 + 0x04`) | `ldog3` | 6 / 6 |
| VRM | `0x42604`, `0x42608` | `ldob17` base `0x42600` plus offsets `0x04/0x08` | 2 / 2, 2 / 2 |
| VRM | `0x42d04`, `0x42d08` | `ldod1` base `0x42d00` plus offsets `0x04/0x08` | 8 / 8, 8 / 8 |
| VRM | `0x43204`, `0x43208` | `ldof3` base `0x43200` plus offsets `0x04/0x08` | 1 / 1, 1 / 1 |
| VRM | `0x43908` (`0x43900 + 0x08`) | `ldoe1` | 2 / 2 |
| VRM | `0x43a08` (`0x43a00 + 0x08`) | `ldoe3` | 6 / 6 |
| BCM | `0x50000` | `MC0` | 291 / 289 |
| BCM | `0x50004` | `SH0` | 290 / 0 |
| BCM | `0x50008` | `SH1` | 313 / 286 |
| BCM | `0x50010` | `SN0` | 20 / 0 |
| BCM | `0x50018` | `SN2` | 14 / 0 |
| BCM | `0x5001c` | `SN3` | 4 / 0 |
| BCM | `0x50020` | `CN1` | 2 / 0 |
| BCM | `0x50030` | `MM0` | 10 / 0 |
| BCM | `0x50038` | `CN0` | 27 / 0 |
| BCM | `0x50044` | `QUP0` | 6 / 4 |
| BCM | `0x50048` | `QUP1` | 6 / 4 |
| BCM | `0x5004c` | `QUP2` | 5 / 5 |
| BCM | `0x50068` | `ACV` | 289 / 0 |

The exact six-command transition recorded at trace timestamp approximately
`4078.0271` is below. The `msgid` and `complete` columns reproduce the trace
fields; they are not inferred values. For BCM data, the v7.2 `BCM_TCS_CMD`
layout decodes `commit = bit 30`, `valid = bit 29`, `vote_x = bits 27:14`,
and `vote_y = bits 13:0`.

| TCS command | Address -> CMD-DB resource | Linux interconnect owner from SM8550 source | WAKE raw / decoded | SLEEP raw / decoded |
|---:|---|---|---|---|
| 0 | `0x50000` -> BCM `MC0` | `ebi` memory path; `MC0` is the `ebi` BCM | `0x60000823`, `msgid=0x10108`, `complete=1`; commit=1 valid=1 x=0 y=2083 | `0x600001dc`, `msgid=0x10008`, `complete=0`; commit=1 valid=1 x=0 y=476 |
| 1 | `0x50004` -> BCM `SH0` | `qns_llcc`; `SH0` is the LLCC BCM | `0x600011db`, `msgid=0x10108`, `complete=1`; commit=1 valid=1 x=0 y=4571 | `0x600001dc`, `msgid=0x10008`, `complete=0`; commit=1 valid=1 x=0 y=476 |
| 2 | `0x50010` -> BCM `SN0` | `qns_gemnoc_sf`; system-NoC SF path | `0x60004001`, `msgid=0x10108`, `complete=1`; commit=1 valid=1 x=1 y=1 | `0x40000000`, `msgid=0x10008`, `complete=0`; commit=1 valid=0 x=0 y=0 |
| 3 | `0x50038` -> BCM `CN0` | `qsm_cfg` and its configuration-NoC nodes | `0x60004001`, `msgid=0x10108`, `complete=1`; commit=1 valid=1 x=1 y=1 | `0x40000000`, `msgid=0x10008`, `complete=0`; commit=1 valid=0 x=0 y=0 |
| 4 | `0x50048` -> BCM `QUP1` | `qup1_core_slave` virtual QUP path | `0x20004001`, `msgid=0x10008`, `complete=0`; commit=0 valid=1 x=1 y=1 | `0x00000000`, `msgid=0x10008`, `complete=0`; commit=0 valid=0 x=0 y=0 |
| 5 | `0x50044` -> BCM `QUP0` | `qup0_core_slave` virtual QUP path | `0x60004001`, `msgid=0x10108`, `complete=1`; commit=1 valid=1 x=1 y=1 | `0x40000000`, `msgid=0x10008`, `complete=0`; commit=1 valid=0 x=0 y=0 |

This decoding makes two points precise. First, `0x50004` is exactly the
CMD-DB `SH0` entry, not an `MC0` sub-address; exact BCM matching matters.
Second, MC0 and SH0 retain a valid nonzero sleep vote (`vote_y=476`), while
SN0, CN0, QUP0, and QUP1 carry no valid sleep vote in this set. A valid
nonzero memory/LLCC low-power request is not by itself evidence of a blocker;
it may be the floor needed to keep memory accessible. Conversely, the raw
words do not reveal whether the AOP accepted those requests or whether the
selected vote policy is sufficient for AOSD/CXSD entry.

## Interconnect and genpd ownership correlation

The current Linux source defines the BCM ownership used above: `MC0` owns
`ebi`, `SH0` owns `qns_llcc`, `SN0` owns `qns_gemnoc_sf`, `CN0` covers the
configuration-NoC node set, and `QUP0`/`QUP1` own the corresponding virtual QUP
core slave nodes. Armada's current `0122` package change adds QoS register
configuration to SM8550 nodes; it does not change these BCM names or the
ownership mapping.

The existing trace shows the immediate pre-set consumers, without claiming
that any of them persisted during the hardware-suspend interval:

- At `4077.965246`, `a80000.i2c` raised the QUP1 core path to `1/1`, and the
  trace sent active `QUP1` data `0x60004001`. The path then traversed
  `qns_gemnoc_sf`, `qns_llcc`, `llcc_mc`, and `ebi`; corresponding active
  `MC0` and `SH0` traffic was logged at `4077.969663`–`4077.969667`.
- At `4077.973405`, `890000.i2c` raised QUP2 and sent active `QUP2`; its
  path also traversed `qns_gemnoc_sf`, `qns_llcc`, `llcc_mc`, and `ebi`, with
  active `MC0` at `4077.974496`–`4077.974505`.
- At `4077.976592`, `98c000.i2c` raised QUP0 and sent active `QUP0`; its
  configuration path was followed by the active `QUP0` request. The last
  active ARC requests before the transition were `mmcx.lvl=0` at `4077.979226`
  and `cx.lvl=0` at `4077.979240`.
- The six WAKE and six SLEEP commands followed at `4078.027083`–`4078.027116`.
  There were no trace events in the actual timekeeping gap that would show
  Linux issuing a new request during hardware suspend.

The final read-only preflight captured the live aggregate views and the
complete topology. `interconnect_summary` reported awake-state `llcc_mc` and
`ebi` average/peak `1471610/6832000`, `qns_llcc` `1471610/9600000`,
`qsm_cfg` `3315/57000`, `qhs_qup2` `3315/3200`, and PCIe memory-path peak
`500000` at `xm_pcie3_0`/`qns_pcie_mem_noc`. The graph retained the same
logical paths; its values are independently sampled and can differ because
the summaries are live and the commands run sequentially. UFS and USB
endpoint rows were present but zero in this awake capture. These values
identify current Linux consumers and topology, not an in-suspend vote dump.

The same preflight's `pm_genpd_summary` showed awake `cx` and `mmcx` domains
on with usage `64`, UFS and PCIe GDSC/domain references on with usage `64`,
USB PHY/GDSCs on while `a600000.usb` was suspended, and the display domain
active. GPU GDSCs, EBI, MX/LCX/LMX, and GFX were off; `17a00000.rsc` was
runtime-suspended. These statuses are useful ownership context but are not
readings from the 45-second low-power interval.

The lab harness now preserves each of these four views as both raw files and
parsed structures in future phase snapshots: `cmd_db`,
`interconnect_summary`, `interconnect_graph`, and `pm_genpd_summary` in
`regulator-clock-summaries.json`. The additive schema is version 2 and was
validated against the exact current preflight: 152 CMD-DB resources, 127
interconnect aggregates, 214 interconnect consumers, 127 graph nodes, 135
graph edges, 48 genpd domains, and 50 genpd device rows.

## RSC/CMD-DB diagnostic boundary

The reviewed Qualcomm [`[PATCH v3 0/3] Output debug information from RSC`](https://lkml.iu.edu/2608.1/07181.html)
series adds three relevant capabilities: accelerator-type decoding
(ARC/VRM/BCM), reverse CMD-DB address-to-name lookup, and an RSC diagnostic
routine that reads TCS controller/command registers plus GIC pending state.
The three commits were merged into Qualcomm's `qualcomm-linux/kernel`
`qcom-6.18.y` branch on 2026-08-20 (RSC commit
`403d2a6ac9213a7454fa31744f8ad6089d368cd8`, with CMD-DB commits
`946390ea27648ac0e76ecd1950405f1ce3ed5640` and
`b98e95ae006480d4d6c384725beede55ed3092d7`). This is a stronger reviewed
starting point than an unreviewed custom decoder. The merged Qualcomm PR is
also visible at [qualcomm-linux/kernel#907](https://github.com/qualcomm-linux/kernel/pull/907).
The code is not in the
inspected Torvalds Linux master or Armada's kernel 7.2 package.

The reverse lookup intentionally folds VRM sub-addresses back to the base
resource. The RSC routine is wired into `rpmh_write()`, `rpmh_write_batch()`,
and `rpmh_read()` **timeout paths**. It can therefore explain a stuck TCS or
missing completion, but it does not log a successful `rpmh_flush()` sleep/wake
set, expose a persistent read-only TCS debugfs view, or report the AOP's
decision to enter AOSD/CXSD/DDR states. The Nova trace had no RPMh timeout,
so this merged reviewed work would have emitted no additional evidence for
the completed clean cycle.

Current upstream Linux still has no `cmd_db_read_name()`,
`cmd_db_hw_type_str()`, or `rpmh_rsc_debug()` implementation in the inspected
master source. Armada's current kernel package likewise has no RSC/CMD-DB/AOP
diagnostic patch. Its `0122` change is QoS configuration only. The current
Armada AOSS driver exposes the four `qcom_aoss` files as write-only debugfs
controls, which explains their read-side `EINVAL`; they are not a hidden
read-only firmware-status interface.

The completed trace archive's available-event inventory contains only
`rpmh_send_msg`, `rpmh_tx_done`, `aoss_send`, `aoss_send_done`,
`icc_set_bw`, and `icc_set_bw_end` for these subsystems. There is no existing
RSC/TCS-register or firmware-acceptance tracepoint to enable on the current
image. The exact Armada package build anchor is `VERSION=7.2`; its build script
uses a pinned Fedora builder image and applies the package's recorded patch
manifest. The manifest's relevant current entries are `0513`/`0520` for the
SM8550 PCIe suspend-OPP pair, `0121` for the scoped RPMh power-domain behavior,
and `0122` for SM8550 interconnect QoS; none supplies successful-path RSC
readback. The Qualcomm `qcom-6.18.y` integration is source prior art only;
it is not part of the Armada package provenance and is not being copied or
deployed in this phase.

Armada's package build path independently fetches the `linux-7.2` kernel.org
stable tarball and applies only the local `kernel/patches/series`; it cannot
consume Qualcomm's `qcom-6.18.y` branch as a substitute source. A line-level
comparison of the merged Qualcomm `rpmh-rsc.c`, `rpmh.c`, and
`rpmh-internal.h` against Linux v7.2 found the expected diagnostic insertion
contexts (the v7.2 `rpmh.c` also has unrelated allocator changes), so the
three commits are a plausible reviewed porting base. This was not a patch
application or build, and no commit was added to Armada's series.

The Linux v7.2 control flow identifies the smallest future instrumentation
point. `rpmh_rsc_write_ctrl_data()` is explicitly the non-triggering
sleep/wake path: it allocates a slot and calls `__tcs_buffer_write()`, which
writes the TCS command registers and emits the existing send tracepoint. The
sleep/wake TCS is then left for firmware to trigger when the execution
environment reaches its deepest low-power mode. The current trace already
captures the message state, TCS number, command number, address, data, and
message ID at that point, but it does not read back `CMD_ENABLE`, controller
control/status, per-command status, response data, or the TCS IRQ status. The
RSC busy check is for active transfers before the final flush, not a successful
sleep-set acceptance result. This makes a post-buffer-write, read-only
TCS-register snapshot the minimal evidence addition; it must not trigger or
rewrite the TCS.

The live RSC topology makes the target slots unambiguous. Linux's RSC binding
defines `SLEEP_TCS=0`, `WAKE_TCS=1`, `ACTIVE_TCS=2`, and `CONTROL_TCS=3`.
The device-tree cells decode as `(ACTIVE_TCS,3), (SLEEP_TCS,2),
(WAKE_TCS,2), (CONTROL_TCS,0)`, so the sleep slots are global TCS 3--4 and
the wake slots are global TCS 5--6. The completed trace's final sleep TCS 3
and wake TCS 5 therefore match the running device-tree allocation. The
merged Qualcomm diagnostic is not sufficient to reuse verbatim for this
purpose: it iterates `drv->tcs_in_use`, which tracks active transfer
bookkeeping, while the successful sleep/wake path uses `tcs->slots` and does
not mark those control TCSes as in-use. A successful-path snapshot must
explicitly enumerate the sleep/wake group masks or the observed TCS IDs.

The diagnostic must use the driver's selected `drv->regs` table because the
v7.2 RSC driver has different command-register offsets for RSC v2.7 and v3.0.
For each selected TCS it should read only `CMD_ENABLE`, `CONTROL`, `STATUS`,
global `IRQ_STATUS`, and enabled-command `MSGID`, `ADDR`, `DATA`, `STATUS`,
and `RESP_DATA` fields, plus the driver's decoded hardware version. It should
take the pre-suspend snapshot after the final `rpmh_flush()` buffer writes and
the post-resume snapshot at the corresponding CPU-PM exit point. No
`CMD_ENABLE` clear, trigger, IRQ clear, TCS write, QMP message, or vote change
belongs in this diagnostic path.

The current device identifies `QCS_KAILUA`, and the running OS reports ADSP,
CDSP, boot, and TZ firmware identities, but the AOP-specific identity is
blank/unreported. The device tree only exposes reserved-memory paths
`aop-cmd-db-region@81c60000` and `aop-config-merged-region@81c80000`, and no
AOP/RPMh firmware file is present under `/usr/lib/firmware`. The external
`qcom-aop-debug` material therefore cannot be matched to this AOP build, and
no sender or monitor operation was used.

A fresh live read-only sysfs/device-tree check, retained in preflight receipt
`/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T174854Z-45d0702ef09c.json`,
narrows the register boundary:
the RSC is labeled `apps_rsc`, compatible with `qcom,rpmh-rsc`, at
`/soc@0/rsc@17a00000`, with four named `drv-0` through `drv-3` register
windows at `0x17a00000`, `0x17a10000`, `0x17a20000`, and `0x17a30000`, each
`0x100` bytes. Its device-tree `qcom,drv-id` is `2`, `qcom,tcs-offset` is
`0xd0000`, and `qcom,tcs-config` decodes to rows `2,3,0,2` and `1,2,3,0`.
The live sysfs device has no readable `resource`, register, status, or TCS
debug file; it exposes only the `rpmh`, `bcm_voter`, `clk-rpmh`,
`qcom-rpmhpd`, and `qcom-rpmh-regulator` child-driver identities. Therefore
there is no unpatched read-only path to the RSC registers on this image, and
the proposed in-driver `readl` snapshot remains the smallest observation-only
instrumentation boundary.

The archived kernel journal contains no AOP firmware version, AOP acceptance,
or low-power-decision record. It does show the RSC, RPMh regulator, RPMh power
controller, BCM voter, AOSS-QMP, and CMD-DB suspend/resume callbacks returning
zero. Those records establish that Linux completed its PM callbacks; they do
not establish that firmware honored the programmed low-power set.

## Branch assessment and smallest distinguishing observation

1. **Insufficient or wrong sleep-set contents:** not demonstrated. Every
   traced address is known, the six transition commands are structurally valid
   BCM words, and MC0/SH0 carry explicit valid sleep values. The set could
   still be policy-insufficient, but there is no malformed/unknown-address
   evidence.
2. **Surviving Linux-visible vote:** plausible but not demonstrated. The
   immediate pre-set trace contains transient QUP/I2C paths and LLCC/EBI
   activity, and the awake genpd view has active CX/MMCX/UFS/PCIe references.
   No observation timestamps a persistent request through the hardware-sleep
   gap, so post-resume or awake values cannot be promoted to this cause.
3. **AOP/RPMh firmware declines the deeper state:** remains the strongest
   unresolved boundary. Linux programs the set and sees no transfer error, but
   no current interface reports firmware acceptance or the low-power decision.
4. **Platform-specific qcom residency semantics:** reduced but not eliminated.
   The v7.2 qcom-stats implementation and Armada interpretation identify the
   scalar records correctly, the files are readable, and other changing
   records prove the interface is not simply an inert parser target. The exact
   firmware meaning of the opaque DDR LPM code and zero deep-state result is
   still an unknown.

The single smallest future observation capable of separating these branches is
one observation-only successful-path RSC snapshot, taken after Linux programs
the sleep and wake sets and immediately before the real suspend trigger, with
the corresponding post-resume snapshot. It should read and archive only the
RSC TCS command/control/status registers for the involved sleep/wake TCSes
(including address, data, message ID, command status, TCS status, AMC mode,
and IRQ status), and use the reviewed CMD-DB type/name helpers for decoding.
It must not send a command, force a vote, or alter AOSS controls. This would
show whether the words are still present/valid (branch 1), whether a Linux
request remains active at the handoff (branch 2), or whether Linux hands off a
valid quiet set with no firmware acceptance/residency result (branch 3); the
already source-checked counter definitions cover branch 4 better than another
blind stock repeat. The merged Qualcomm RSC v3 series is the preferred
reviewed starting point for the decoding helpers, but its timeout-only hook is
not sufficient by itself. Do not build or deploy this diagnostic patch yet.

## Post-instrumentation correction: UFS is not the in-suspend blocker

The observation-only RSC package was subsequently built and deployed through
the device-local OCI layer described in the deployment preparation receipt.
Corrected deep run
`/Users/kurt/Developer/sm8550-suspend-lab-runs/20260902T001240Z-f80f54f6b742`
captured 35 RSC snapshots: 17 before suspend and 18 from the post-resume
notifier. Sleep TCS 3 and wake TCS 5 retained the six decoded BCM resources
and their programmed words, with `cmd_enable=0x3f`, `tcs_status=1`,
`tcs_in_use=0`, `irq_status=0`, `cmd_status=0`, and zero response data. The
post-resume active TCS activity was ordinary concurrent RPMh traffic; it is
not evidence of sleep-set rejection.

The first UFS trace receipt
`20260902T002021Z-a66419f43ef9` remains preserved but is invalid for its stated
IRQ question: its hard-coded filter selected `mmc0` IRQ 169 while the live UFS
IRQ was 170. The harness was corrected to resolve `ufshcd` dynamically before
configuring the trace.

The corrected run
`/Users/kurt/Developer/sm8550-suspend-lab-runs/20260902T002708Z-4e8666167435`
resolved `ufshcd` IRQ 170 and captured 501 matching IRQ entries/exits, 1,122
UFS command events, 126 UIC events, and 7 hibern8 events. The IRQ delta was
11,814 and `mmc0` increased by only 47; dividing those raw deltas by the
43.368549 seconds of boottime-minus-monotonic separation would yield
272.4/s and 1.08/s respectively, but those quotients are not in-suspend rates.
The trace places the UFS events around suspend preparation and after
timekeeping resumes. No UFS event was recorded during the actual 43.368-second
deep-sleep interval, and the kernel completed UFS suspend/noirq and resume
callbacks without an error. The historical microSD/SDHCI interrupt storm is
therefore not reproduced on this Nova, and no UFS or SDHCI functional change is
justified by this evidence.

The branch assessment is now: the Linux sleep set is demonstrably programmed
and structurally decoded; no persistent Linux-visible UFS or SDHCI blocker is
shown; and the remaining uncertainty is between firmware policy/acceptance and
platform-specific meaning of the named Qualcomm residency files. The next
single experiment should be one read-only RPMh/AOP or equivalent firmware-state
observation matched to this exact build, not a guessed device patch. Until that
exists, retain the current diagnostic layer and do not force votes or write
qcom_aoss/QMP controls.
