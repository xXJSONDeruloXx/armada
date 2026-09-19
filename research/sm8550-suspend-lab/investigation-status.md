# SM8550 suspend investigation status

**Read this first.** This is the current checklist and evidence boundary for
the Nova suspend investigation. The [lab notebook](lab-notebook.md) remains
the chronological record, including failed runs and superseded interpretations.
Update this page when a checklist item changes; put raw output in a dated
receipt and explain the result in the notebook.

Status as of 2026-09-19 22:08 UTC. Repository branch
`feat/sm8550-suspend-lab`; see Git history for the current pushed tip.
The user supplied anchor `054766d5...` is an earlier commit; work continues from
the newer pushed tip.

## Current objective

Find the smallest defensible causal A/B explaining why Android's successful
deep-suspend path submits a different RPMh request set from Armada. Do source
comparison first. Do not change live behavior until the source audit identifies
a safe, single-variable test.

## Closed question: sleep-stat offsets

**Do not repeat this experiment.** Android resource `0x0c3f0000`, size `0x400`;
the stock Android driver read pointer words `0x000f0048` and `0x000f00b8`,
resolving to `0x0c3f0048` and `0x0c3f00b8`. Its normal reads found the expected
AOSD/CXSD/DDR signatures and DDR magic. Armada's Linux caller probe independently
resolved `+0x48`; mainline uses `+0x48` and `+0xb8`. The zero Armada records are
not explained by a stats-address, stride, or obvious record-layout mismatch.

No Android diagnostic module, pointer-word probe, qcom_stats offset change, or
new arbitrary MMIO read is warranted.

## Evidence ledger

Labels matter: **observed** means captured directly; **source** means found in
the inspected tree; **correlation** is not causal proof; **unknown** must stay
open until measured.

| Status | Finding |
|---|---|
| Observed | Armada s2idle and direct PSCI SYSTEM_SUSPEND suspend/resume successfully. AOSD/CXSD/scalar DDR and recognized detailed DDR LPM rows remain zero; APSS/other subsystem evidence advances. |
| Observed | Android's captured Apps-RSC SLEEP/WAKE set has 11 BCM plus 3 PMIC regulator commands. It includes SH1, QUP2, ACV, MC4, SH5; MC0/SH0 SLEEP requests are zero/off; LDOE1/LDOE3 have explicit sleep requests. See `receipts/2026-09-19-android-deep-rpmh/`. |
| Observed | Armada stages six BCM sleep commands (MC0, SH0, SN0, CN0, QUP1, QUP0); MC0/SH0 are nonzero. The trace proves Linux staged these commands, not that AOP accepted/applied them. |
| Observed | The PCIe host's D3cold eligibility check fails on Qualcomm root port `0000:00:00.0` (`17cb:0113`) in `PCI_UNKNOWN`. Binding `pcieport` after a temporary boot-argument test did not change that result or clear the zero counters. Original `pcie_ports=compat` was restored. |
| Correlation | PCIe consumer pre-suspend peak requests of 500,000 and 1,000,000 kB/s coincide with MC0/SH0 SLEEP words encoding 476 and 952. Wi-Fi-off removed one 476 component in a prior matched run, but other clients also differ. Do not assign the whole floor to PCIe yet. |
| Source, public match only | Available Android source `Ayn8550Dev/android_kernel_ayn_qcs8550` at `93c5cc6...` has a Qualcomm `pci-msm.c` noirq path gated by `qcom,apss-based-l1ss-sleep`. When selected and L1SS is confirmed, it disables config access, host clocks/GDSC/analog rails, and clears its ICC request; it does not set root-port or endpoint D3 state in that branch. Android logs confirm WCN/WoW bus-suspend success, not the endpoint's PCI power state. Running Android reported `g697b78910a71-dirty`, not matched to this public commit. |
| Observed, read-only Android DTBO | `dtbo_a` is a standard table with `dt_entry_size=32`, `dt_entry_count=56`. Seven entries contain the zero-length L1SS property. Entry 51 (`0xb71079`, size 378,507) has root IDs `<0x25b 0x20000>` and `<0x1001f 0>`, matching the public RP6 DT source IDs; its model label is KalamaP HDK. Its `fragment@30` adds both `qcom,apss-based-l1ss-sleep` and `qcom,no-client-based-bw-voting`; `__fixups__.pcie1` points that fragment's `target` at base-DT symbol `pcie1`. The base symbol path and runtime selection remain unproven. See `receipts/2026-09-19-android-dtbo-a-scan.txt`. The earlier 32-by-56 interpretation was a field-order mistake and is superseded. |
| Source, Android DT selection unresolved | Entry 51 is the strongest RP6 candidate by matching public SoC/board IDs, but matching IDs do not prove ABL selected it for the observed run. Its `fragment@30` target fixup, exact ABL overlay-selection behavior, and merged runtime DT remain to be verified. The public RP6 overlay source does not itself declare the L1SS property. |
| Source, two Android PCIe suspend hooks | The nearby public driver has both a host-platform `suspend_noirq` path gated by `qcom,apss-based-l1ss-sleep` and a root-PCI-device `SUSPEND_LATE` fixup. Source ordering puts the root PCI device's noirq fixup before its parent host-platform callback: the host bridge is allocated as a child of the PCIe platform device, and DPM makes a parent wait for children. If the fixup runs, it calls PME_TURNOFF/L23, then `msm_pcie_disable()`; `msm_pcie_clk_deinit()` clears the ICC vote and `msm_pcie_disable()` sets `power_on=false`, so the later host callback skips its `enumerated && power_on` body, including APSS/L1SS logic. If the root PCI device is skipped, the host callback may take the APSS/L1SS path instead. The public source proves the ordering and conditions, not which runtime branch executed on this build. |
| Source | Armada uses upstream DesignWare/Qualcomm PCIe PM plus patches 0513/0520. If the generic D3cold check fails, `dw_pcie_suspend_noirq()` returns before host teardown and leaves `pci->suspended` false. In the qcom fallback branch, direct deep (`PM_SUSPEND_MEM`) skips the OPP update; with the OPP-based path this leaves the active OPP request. The `opp-suspend` floor from 0520 is selected only in the non-S2RAM branch. |
| Source, 0513/0520 nuance | Patch 0513 does call its OPP helper when the host really suspended; for `PM_SUSPEND_MEM` that helper passes `NULL`, which drops associated OPP bandwidth. But when D3cold is vetoed, the helper call is nested inside the non-`PM_SUSPEND_MEM` fallback, so deep suspend skips it. The patch therefore does not bypass the PCI safety check; it preserves the active request when the host remains running. |
| Observed, source mapping | Mainline SM8550 maps BCM MC0 to EBI and SH0 to LLCC. Replaying the exact v7.2.3 aggregation formula against the 19:03 awake snapshot predicts MC0/SH0 `vote_x=525, vote_y=2034`; the captured SLEEP TCS instead has `vote_x=0, vote_y=952` (`0x600003b8`). GPU, UFS, and display requests change before that TCS; PCIe has no corresponding update. The awake summary is therefore not the final SLEEP-bucket input and cannot prove the exact client contribution. |
| Observed/source | `interconnect_summary` includes each request's current tag and bandwidth, while `icc_set_bw` tracepoints omit request tags and enabled state. The suspend trace records several client bandwidth changes before SLEEP staging. Exact final per-request SLEEP membership is still unknown; a pre-suspend-only attribution calculator would be misleading. |
| Observed/source | Android SLEEP TCS contains LDOE1/LDOE3 sleep-context commands. Mainline qcom-rpmh-regulator currently submits ACTIVE_ONLY requests and does not provide an equivalent sleep-context API. The awake regulator summary does not show what firmware applies in suspend. |
| Source, Armada DT | For Nova, LDOE1 (`vreg_l1e_0p88`) supplies PCIe PHY, DSI0 PHY, and USB HS PHY. LDOE3 (`vreg_l3e_1p2`) supplies DSI0, PCIe PHY PLL, UFS PHY PLL, USB HS PHY, and USB/DP QMP PHY. RP6 disables DSI1. These consumers make a blanket rail-off change unsafe to infer from the TCS alone. |
| Unknown | Which of the seven Android DTBO candidate overlays were selected and whether the observed run used the APSS/L1SS branch; ordering of the host noirq callback versus the PCI suspend-late fixup; which root-port/endpoint power states and wake path it reached; exact matching Android source/build and merged runtime DT; final sleep-bucket per-client contributions to each BCM value; which LDOE consumers may be changed safely at sleep; whether any one request difference causes the counter difference. |

## Work checklist

### 1. Android versus Armada PCIe suspend path — do first

- [x] Inspect the public `pci-msm.c` implementation and the RP6 Android DT
  overlay; mark their applicability provisional where the actual vendor base
  DT/build is missing.
- [x] Read the Android slot `_a` DTBO partition without changing device state;
  parse its standard 32-byte entries and identify the seven property-bearing
  overlays. Entry 51 matches the public RP6 SoC/board IDs.
- [x] Resolve entry 51's `fragment@30` target fixup to the base-DT symbol
  `pcie1`.
- [ ] Find the base symbol's node path and establish whether ABL selected
  entry 51 and whether the property is present in the merged runtime DT.
- [ ] Find the exact Android source/build revision if available; otherwise keep
  each nearby public-source conclusion explicitly provisional.
- [ ] Identify Nova's runtime PCIe compatible, bound driver, DT properties,
  and whether `qcom,apss-based-l1ss-sleep` is active; the DTBO candidate match
  alone is insufficient.
- [ ] Trace Android host and endpoint PM ordering: WCN7850 suspend/WoW, root
  port state, link L1SS/L23 behavior, host power-down, ICC/OPP calls, wake
  restoration. Do not infer D3hot/D3cold from host power loss.
- [x] Trace source ordering between the PCI `SUSPEND_LATE` fixup and host
  platform `suspend_noirq`; the runtime branch taken remains unknown.
- [ ] Compare that call path with Linux v7.2.3 `pcie-qcom.c`, DesignWare host
  PM, generic D3cold eligibility, and Armada patches 0513/0520.
- [ ] Separate what source proves from what needs Android runtime logs/DT.

### 2. Attribute the MC0/SH0 floor

- [ ] Inspect `interconnect_summary` parser/receipts, BCM voter aggregation,
  SM8550 BCM/interconnect definitions, PCIe ICC/OPP calls, and the Android
  Kalama definitions/TCS capture.
- [ ] Determine whether the PCIe request accounts for the full value or only
  the observed variable component; identify other client contributions. The
  harness already captures named client rows and ICC changes, but these do not
  currently expose final per-client SLEEP-bucket values. The awake-snapshot
  calculation has been compared with the staged TCS and is not a valid final
  attribution because suspend callbacks change requests before staging.
- [ ] Add a harness read-only attribution view only if existing debugfs/source
  data provides exact client aggregation. Do not invent an approximation or
  modify votes to identify them.

### 3. Compare regulator sleep contexts

- [x] Map Nova's Armada-DT consumers of LDOE1/LDOE3: PCIe PHY, UFS PHY,
  USB HS/DP PHY, and DSI0. Android merged-DT mapping remains open.
- [ ] Establish each consumer's wake requirement and why Android's sleep-only
  requests do not break its wake path.
- [ ] Describe an upstream-quality regulator API/DT model that can emit sleep
  RPMh requests; do not blindly copy proxy properties or assume
  `regulator-state-mem` works in the current mainline driver.

### 4. Choose at most one A/B after the source gate

- [ ] Rank hypotheses by direct evidence and select one device-scoped or
  narrowly driver-scoped variable only if it is reversible and safe.
- [ ] If no safe one-variable A/B exists, stop at source/instrumentation
  conclusions and identify the missing fact. Do not deploy a speculative fix.
- [ ] For any justified A/B, record all of the following at matched boundaries:
  1. PCIe host suspend result.
  2. PCIe ICC/OPP request before suspend.
  3. final MC0/SH0 SLEEP TCS words.
  4. complete Apps-RSC SLEEP/WAKE command set.
  5. LDOE1/LDOE3 request context, if relevant.
  6. PSCI SYSTEM_SUSPEND result.
  7. AOSD/CXSD/scalar DDR before and after.
  8. detailed DDR IDs before and after.
  9. Resume health and PCIe/Wi-Fi function.
- [ ] Do not use battery drain as the verdict for a short diagnostic run.

## Safety and continuity constraints

- Device control is currently SSH over Wi-Fi only; the Mac saw no USB/ADB data
  device in the latest check. Preserve Wi-Fi and the current Linux boot while
  source work is possible. Do not test a Wi-Fi/PCIe change remotely without a
  verified independent recovery route.
- Do not force PCI D3hot, bypass `pci_host_common_d3cold_possible()`, change
  `pcie_ports` again, manually alter ICC votes, blindly disable shared rails,
  send AOSS/QMP commands, or access guessed MMIO/AOP memory.
- Do not patch offsets or kernel behavior before completing the source audit.
- Any device trial must use the existing reversible kernel-layer/bootc test
  path with a verified rollback. Record preflight, exact diff, run receipt,
  rollback, and post-resume function checks.

## Working files

- Chronology, corrections, and test receipts: [lab-notebook.md](lab-notebook.md)
- Latest read-only Linux PM snapshot: [live PM receipt](receipts/2026-09-19-live-pm-readout.txt)
- Android SLEEP/WAKE TCS and ICC excerpts: `receipts/2026-09-19-android-deep-rpmh/`
- Existing harness: [sm8550_suspend_lab.py](sm8550_suspend_lab.py)
- Kernel/package patch stack: sibling checkout
  `../../../armada-packages/kernel/patches/`
