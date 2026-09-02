# Qualcomm DWC3 skip-PHY-init A/B

Status: completed and rolled back at 2026-09-02 02:32 UTC.

This was an independent functional opportunity test. It does not resolve the
separate RPMh/AOP question behind the zero AOSD/CXSD/scalar-DDR records.

## Scope and provenance

The control was the existing current-image deep run
`20260902T004312Z-8ddc7114e866`. The candidate was
`20260902T022513Z-59a89502b494`. Both were cable-free, off-radio, RTC-woken
45-second deep cycles through `/usr/libexec/armada/suspend-dispatch` with the
`rsc-success` trace profile and the microSD mounted.

The candidate changed one kernel variable only:
`0910-usb-dwc3-qcom-skip-phy-init.patch`. It is the reviewed Qualcomm change
that creates the managed software property
`xhci-skip-phy-init-quirk` for the xHCI platform driver. The Qualcomm proposal
describes the problem as an extra USB-core PHY initialization reference that
can leave the PHY init count nonzero; Linux 7.2's xHCI platform driver already
consumes this property. The source proposal is
[the Qualcomm DWC3 skip-PHY-init patch](https://lkml.iu.edu/2607.2/15543.html),
and the base xHCI consumer is [Linux v7.2 `xhci-plat.c`](https://raw.githubusercontent.com/torvalds/linux/v7.2/drivers/usb/host/xhci-plat.c).

The candidate package was built from Linux 7.2, package commit
`5aa8e4cfb7c6faf3cb22db77fc93519aadff5e92`, Armada's existing 136-patch base
plus this patch (137 applied), the unchanged diagnostic RSC instrumentation,
unchanged config, and the pinned Fedora arm64 builder
`registry.fedoraproject.org/fedora@sha256:0c6072366ebf8ea1c8c0f3a118aad3e9a9247d3065d499e54d62968f69351966`.
The clean package workflow was run as `33580043873`; its published carrier
digest was
`sha256:80d2ae7b5664c723cffcd477db784ea3a939f209bb9c1d0bdad2f1dc643a525e`.
The extracted kernel archive SHA-256 was
`dbe3f05b967374d5c4a7386ebfc22362fa107fa7b58f7653cc314a70a3fd5fe3`; the
embedded source metadata says Linux 7.2, 137 patches, 20 DTBs, and an arm64
Armada build. The archive checksum and zstd integrity checks passed.

On the Nova, the archive was installed only through a uniquely tagged local
OCI/bootc layer:
`localhost/armada-dwc3:20260902-5aa8e4c`, image digest
`sha256:32e8f1f3b8c89443c5201258136ab4d0a45afaf53af7e091d72a2e4ad8184054`,
and version `20260902.dwc3-5aa8e4c`. The candidate booted successfully, with
kernel `7.2.0`, the expected Nova DT identity, and the diagnostic inventory
intact. It was rolled back with `bootc rollback --apply`; preflight
`20260902T023217Z-1381e03a5c7d` confirms the known diagnostic baseline
`localhost/armada-rsc:20260901-pmcb4` is booted again.

## Suspend and wake gates

| Measure | Current diagnostic control | DWC3 candidate |
| --- | ---: | ---: |
| Requested/observed mode | deep / deep | deep / deep |
| `CLOCK_BOOTTIME` delta | 45.595271 s | 46.669971 s |
| `CLOCK_MONOTONIC` delta | 2.545525 s | 2.579147 s |
| signed separation | 43.049745 s, observed | 44.090824 s, observed |
| boot ID | unchanged | unchanged |
| kernel suspend markers | deep entry/exit | deep entry/exit |
| suspend stats | success +1, failures 0 | success +1, failures 0 |
| wake | expected RTC IRQ/source | expected RTC IRQ/source |
| systemd failed units | none | none |

The candidate therefore preserved suspend/resume correctness. The short-run
battery metrics were unavailable: the battery power-supply entry exposed no
usable counters, and the harness recorded `battery_metrics={}`. No power
improvement is claimed from this run.

## Intended USB/PHY mechanism

The comparison uses pre/post deltas because runtime PM time counters reset at
boot. The complete raw snapshots are retained in both run archives.

| Device/evidence | Control pre -> post | Candidate pre -> post |
| --- | --- | --- |
| `a600000.usb` runtime PM | suspended -> active; active time `33153 -> 37210`, suspended time `1767754 -> 1771847` | suspended -> active; active time `13552 -> 17208`, suspended time `45913 -> 50008` |
| `88e8000.phy` runtime PM | active, `control=on`; active time `1800965 -> 1809160` | active, `control=on`; active time `59376 -> 67139` |
| `usb3_phy_gdsc` / `88e8000.phy` genpd | on / active / usage 0 | on / active / usage 0 |
| `usb30_prim_gdsc` / `a600000.usb` genpd | on / suspended pre, active post / usage 0 | identical |
| USB regulators | `88e8000.phy-vdda-phy`, `88e8000.phy-vdda-pll`, EUSB2 rails: same pre/post consumer states | byte-for-byte same filtered pre/post lines |
| USB clocks | USB3 pipe, aux, ref, sleep, UTMI, and AXI clocks 0 pre and 1 post in the same pattern | identical |
| DWC3 ICC | all USB path votes zero pre; same post-resume `1,000,000` average / `2,500,000` peak votes on the DDR/LLCC-side path | identical |

The post-resume ICC and clock snapshots are not in-suspend proof; they are
only evidence that the candidate did not alter the observable post-resume
ownership. The raw `clk_summary`, `regulator_summary`,
`interconnect_summary`, `interconnect_graph`, and `pm_genpd_summary` files are
under each run's `device/{pre,post}/files/` tree.

The PM callback sequence was also unchanged. Both runs showed successful
`genpd_suspend_noirq` for DWC3 and the combo PHY, successful matching resume
callbacks, and `dwc3_qcom_pm_resume` returning 0. The control/candidate
`dwc3_qcom_pm_resume` durations were 64825/62815 usecs, respectively; the
small difference is not a demonstrated improvement. There was no candidate
error, timeout, or changed callback ordering.

No attached USB device was present: the DWC3 gadget child reported
`state=not attached` in both runs. The combo PHY remained active because its
observable consumers include the display-port/aux path as well as the DWC3
link. It is therefore plausible, but not proven, that this cable-free test is
dominated by the display-side PHY reference rather than the extra xHCI init
reference targeted by the patch.

## Residency and RSC evidence

AOSD, CXSD, and scalar DDR remained zero before and after in both runs. This
does not by itself reject a DWC3 benefit. However, no USB/PHY mechanism or
repeatable power/residency improvement was observed. The independent DDR
`0xd0` statistic changed by `986707923` ticks in the control and `995380207`
ticks in the candidate; this is comparable and is not a deep-residency claim.
The complete raw qcom_stats files remain in both archives. The candidate's
RPMh sleep/wake TCS contents and status fields were normal, with no command,
response, or RSC error evidence attributable to this patch.

## Disposition

This is a negative result for retaining the DWC3 candidate on the matched
cable-free workload. Suspend still succeeding is not treated as improvement,
and unchanged AOSD/CXSD/DDR is not treated as proof of no benefit; the deciding
fact is that the intended USB/PHY behavior and relevant post-resume ownership
did not change. Candidate s2idle was not run because the deep gate produced no
observable mechanism or power signal. The device is back on the known
diagnostic baseline. No USB, regulator, PCIe, RPMh, SDHCI, UFS, DT,
runtime-PM, autosuspend, firmware, or AOP change was layered onto this test.

The unresolved RSC/AOP/counter-semantics investigation remains independent.
