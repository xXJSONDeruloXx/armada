# Android PCIe suspend callbacks and live module validation

Captured 2026-09-20 over Wireless ADB on the rooted Nova. This is a bounded
read-only follow-up; no Android partition, module, PCI state, interconnect
request, regulator, or suspend policy was changed.

## Running build and exact module identity

The live device reported:

```text
fingerprint: qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys
slot:        _a
kernel:      5.15.123-android13-8-g697b78910a71-dirty
boot_id:     d927cfaa-54f1-428d-9f3b-1298aa1982fc
```

`/proc/modules` lists `cnss2`, `pci_msm_drv`, and `kiwi_v2` as loaded. The
three files were pulled read-only from `/vendor_dlkm/lib/modules/` and their
hashes exactly match the binaries previously extracted from the validated
A-slot partition:

| File | Bytes | SHA-256 |
|---|---:|---|
| `cnss2.ko` | 1,169,264 | `7c23fc2fdf9a19b3ea2797eea377325c83cc5263df79c040b257908eb549c1b2` |
| `pci-msm-drv.ko` | 511,664 | `675761030ef72886097cabe87e6c2191e30a4e8d2b7a7d412abd564416ac3a2c` |
| `qca_cld3_kiwi_v2.ko` | 25,728,248 | `fd7587579716167898cd6ee0b23eeab9d14a1033fac5b04db7b0d4890888b64b` |

Their `vermagic` is `5.15.123-g697b78910a71-dirty`. This validates that the
previous manual disassembly is of the same module files installed on the
currently running image. It does not recover the exact vendor source revision;
no source tree or DWARF debug information was found in these modules. The
reconstruction remains disassembly plus relocations, not source decompilation.
See [`2026-09-20-android-pcie-binary-decomp.md`](2026-09-20-android-pcie-binary-decomp.md)
for the control-flow reconstruction.

## Bounded Android PCI PM callback trace

A temporary tracefs instance recorded generic PM callback start/end events
and kprobes for PCI suspend and PCI power-state setter functions. The global
tracing switch remained off. A verified RTC wake caused one short `deep`
suspend and the kernel logged entry, RTC wake, and exit. The trace buffer held
11,803 events without loss.

Observed callback results:

| Device/callback | Result |
|---|---|
| Android Qualcomm host `pci-msm 1c00000.qcom,pcie` normal suspend | `err=0` |
| PCI root port `0000:00:00.0` suspend | `err=0` |
| WCN endpoint `cnss_pci 0000:01:00.0` suspend | `err=0` |
| WCN endpoint power-domain suspend | `err=0` |
| Qualcomm host and endpoint noirq suspend | `err=0` |
| Matching noirq resume callbacks | `err=0` |

No hits were recorded for `pci_set_power_state()`,
`pci_raw_set_power_state()`, or the generic PCI suspend probes. Thus this run
shows no OS-issued PCI D-state transition; it does **not** prove the physical
endpoint or link state while the SoC was asleep. Both PCI functions report
D0 after resume, which is only an awake-state read. Wi-Fi returned `up` and
Wireless ADB stayed on the same boot.

Post-run read-only checks confirmed `[s2idle] deep`, empty RTC wakealarm,
`tracing_on=0`, empty `kprobe_events`, `debug_suspend=0`, unchanged boot ID,
both PCI functions back in D0, and `wlan0=up`. The full selected trace remains
outside Git at `/tmp/armada-android-pci-pm-trace.txt`; no Wi-Fi identity or
address is recorded here.

## Linux source comparison and selected A/B

Stable Linux v7.2.3 source confirms the observed Linux path:

1. SM8550 declares `pcie-mem` as `QCOM_ICC_TAG_ALWAYS` and `cpu-pcie` as
   `QCOM_ICC_TAG_ACTIVE_ONLY`. Its 5 GT/s x1 OPP requests 500,000 kB/s on
   `pcie-mem` and 1 kB/s on `cpu-pcie`, with `rpmhpd_opp_low_svs` as its
   required OPP. This matches the live Linux attribution trace.
2. Because this controller has an OPP table, `pcie->use_pm_opp` is set and
   the direct `pcie->icc_mem`/`icc_cpu` handles are not initialized. The OPP
   core owns the ICC paths and applies each OPP's bandwidth values.
3. `dw_pcie_suspend_noirq()` returns success immediately if
   `pci_host_common_d3cold_possible()` is false. On that early return it does
   not stop the link or set `pci->suspended`; the Qualcomm driver then takes
   its host-active fallback.
4. The direct-ICC fallback explicitly lowers `pcie-mem` to 1 kB/s. In the
   OPP-backed branch, however, Armada patch 0513 selects `opp-suspend` only
   inside the non-`PM_SUSPEND_MEM` branch. For direct `deep`/`PM_SUSPEND_MEM`
   with the host still unsuspended, it makes no OPP update and retains the
   active 500,000 kB/s OPP. Patch 0520's existing `opp-suspend` requires
   `rpmhpd_opp_min_svs`, so using it for this test would change the power
   corner as well as bandwidth.

The generic `icc_set_tag()` only changes request tags; it does not reaggregate
or apply constraints. The OPP-owned ICC paths are private to the OPP core, so
the Qualcomm PCIe caller cannot retag its request directly. Statically making
`pcie-mem` ACTIVE_ONLY would also remove the existing 1,000 kB/s SLEEP floor
used by patch 0520 for s2idle, risking the already-fixed hard-reset-on-wake
regression.

**Selected candidate, not yet implemented or deployed:** in a test kernel only,
when direct `PM_SUSPEND_MEM` has returned from the D3cold check with
`pci->suspended == false`, apply a dedicated diagnostic OPP with the same
`required-opps = <&rpmhpd_opp_low_svs>` as the active 5 GT/s x1 OPP, but with
`opp-peak-kBps = <1000 1>`. Give it a synthetic `opp-hz = /bits/ 64 <2>` and no
`opp-level`, so normal link-speed selection cannot choose it. This changes the
PCIe memory-path request magnitude while preserving the active power-domain
corner and CPU-path floor; it does not fake PCI state, bypass the D3cold
check, or alter LDOE requests. It is a narrow test, not a production fix.

Expected discriminating result: if the suspend TCS changes only the MC0/SH0
request magnitude and AOSD/CXSD/DDR counters begin advancing, the retained
500,000 kB/s request is a strong causal contributor. If the counters remain
zero, bandwidth magnitude alone is insufficient and the regulator/BCM request
differences remain viable causes. Either result must include the unchanged
PCIe callback result, complete SLEEP/WAKE TCS, PSCI result, detailed DDR IDs,
and Wi-Fi/PCIe resume health.

Source references:

- [Qualcomm PCIe OPP setup/update and suspend path, v7.2.3](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-qcom.c#L1622-L1718)
- [Qualcomm PCIe suspend fallback, v7.2.3](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-qcom.c#L2159-L2215)
- [DesignWare D3cold check and early return, v7.2.3](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-designware-host.c#L1223-L1291)
- [OPP core applies bandwidth from private paths, v7.2.3](https://github.com/gregkh/linux/blob/v7.2.3/drivers/opp/core.c#L1150-L1176)
- [ICC tag and bandwidth APIs, v7.2.3](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L570-L675)
- [SM8550 PCIe path tags and link OPPs, v7.2.3](https://github.com/gregkh/linux/blob/v7.2.3/arch/arm64/boot/dts/qcom/sm8550.dtsi#L2377-L2425)
- Armada patch sources: `../../armada-packages/kernel/patches/0513-PCI-qcom-honour-an-opp-suspend-opp-as-the-non-s2ram-memory-floor.patch` and `../../armada-packages/kernel/patches/0520-arm64-dts-qcom-sm8550-add-a-pcie-suspend-opp.patch`.

No kernel build or device behavior change was attempted in this pass.

## Exact PCIe branch gates recovered from live BTF

To map the installed module's offsets without guessing, I pulled
`/sys/kernel/btf/vmlinux` and `/sys/kernel/btf/pci_msm_drv` read-only from
this same boot and parsed the module's split BTF against the base BTF. Their
SHA-256 values are:

```text
vmlinux BTF:    18a62ea65c248c2107100eb71f009ee3494779e502c0ec4a5447c203ae2d7c1e
pci_msm_drv BTF: ea0a647ff27cda68bb01eef546faf39a2b5628e0351d6372cda6e936f518bb3d
```

The module BTF defines `struct msm_pcie_dev_t` with these byte offsets:

| Field | Offset | Relevant exact-binary use |
|---|---:|---|
| `apss_based_l1ss_sleep` | `0x409` | Noirq APSS/L1SS body gate |
| `link_status` | `0x480` | `ENABLED=1` versus `DRV=3` suspend-fixup gate |
| `enumerated` | `0x535` | Noirq body gate |
| `power_on` | `0x6a4` | Noirq body gate |

This is live build-specific type metadata, not an inferred structure layout.
The same BTF provides the function prototypes for
`msm_pcie_drv_suspend(struct msm_pcie_dev_t *, u32)` and
`msm_pcie_pm_suspend_noirq(struct device *)`.

The exact `pci-msm-drv.ko` disassembly then shows:

1. `msm_pcie_drv_suspend()` stores integer `3` at `pcie + 0x480`, which BTF
   identifies as `link_status`. The enum is `MSM_PCIE_LINK_DRV`.
2. The registered root-port `SUSPEND_LATE` CFI body
   `__UNIQUE_ID_msm_pcie_fixup_suspend494.cfi` reads that same field, compares
   it with `1` (`MSM_PCIE_LINK_ENABLED`), and branches around its teardown
   path for any other value. This statically explains why the connected-DRV
   path does not call `msm_pcie_pm_suspend()`/`msm_pcie_clk_deinit()` in the
   captured trace. The fixup-entry callback itself was not separately
   probed, so its invocation is not claimed as observed.
3. `msm_pcie_pm_suspend_noirq()` checks `enumerated`, `power_on`, then
   `apss_based_l1ss_sleep` at those BTF-backed offsets. A zero in any gate
   branches directly to unlock/return before the PARF poll, ICC clear, clock,
   regulator, or analog-rail teardown block. The live merged pcie0 DT lacks
   `qcom,apss-based-l1ss-sleep`; that property is the probe input for this
   flag. Therefore the APSS/L1SS body was not selected for the active WLAN
   host in this build, even though its noirq callback entry occurred.

This closes the specific APSS/L1SS-body question for the captured Android
configuration and makes the connected-DRV ICC clear the only observed
PCIe-host request-removal route in that run. It does not prove the physical
PCIe link/endpoint state during sleep, AOP acceptance of individual TCS
words, or whether Wi-Fi/PCIe can wake from that state. The module remains
without source/DWARF; this is a symbol-, relocation-, BTF-, and disassembly-
based reconstruction of the exact installed binary.
