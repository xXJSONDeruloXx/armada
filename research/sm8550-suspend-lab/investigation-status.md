# SM8550 suspend investigation status

**Read this first.** This is the current checklist and evidence boundary for
the Nova suspend investigation. The [lab notebook](lab-notebook.md) remains
the chronological record, including failed runs and superseded interpretations.
Update this page when a checklist item changes; put raw output in a dated
receipt and explain the result in the notebook.

Status as of 2026-09-20 00:39 UTC. Repository branch
`feat/sm8550-suspend-lab`. The read-only ICC attribution profile and tests are
committed on this branch; the latest public Android PCIe-source review is
recorded below and in the chronological notebook. The user supplied anchor
`054766d5...` is an earlier commit; work continues from the newer branch tip.

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
| Source, public match only | The same `pci-msm.c` parses `qcom,no-client-based-bw-voting`. When true, its PCIe helper votes average bandwidth as `link_speed_bandwidth * link_width` with no peak vote; otherwise it uses fixed average/peak constants. This is a different vote shape from Armada's observed `avg=0, peak=500000`, even if a link-speed calculation yields the same scalar. Both known host-off paths clear the request: the APSS/L1SS noirq path calls `icc_set_bw(..., 0, 0)`, and the root-bus suspend-late route reaches `msm_pcie_clk_deinit()`, which also clears it. Thus Android's overlay property changes the steady-state vote form but does not imply the vote is kept in suspend. Actual runtime DT/path remain unknown. [Property and helper](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L3853-L3905), [property read](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L7598-L7603), [L1SS vote clear](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L8645-L8665), [root teardown vote clear](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L4031-L4050). |
| Observed + source inference | Android's saved interconnect summary reports the PCIe request as `tag=0, avg=500, peak=800` under `llcc_mc`, `ebi`, and `qnm_pcie`, exactly matching the nearby source's fixed-vote constants. Its property-enabled branch would instead send a speed/width-derived average and `peak=0`. This suggests `qcom,no-client-based-bw-voting` was false for that request at capture time, but the exact Android source/build and merged DT are not matched, and the overlay target `pcie1` is not mapped to the `1c00000` request. See [Android request snapshot](../../receipts/2026-09-19-android-deep-rpmh/android-interconnect-summary.txt) and [source helper](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L248-L249). |
| Observed, read-only Android DTBO | `dtbo_a` is a standard table with `dt_entry_size=32`, `dt_entry_count=56`. Seven entries contain the zero-length L1SS property. Entry 51 (`0xb71079`, size 378,507) has root IDs `<0x25b 0x20000>` and `<0x1001f 0>`, matching the public RP6 DT source IDs; its model label is KalamaP HDK. Its `fragment@30` adds both `qcom,apss-based-l1ss-sleep` and `qcom,no-client-based-bw-voting`; `__fixups__.pcie1` points that fragment's `target` at base-DT symbol `pcie1`. The base symbol path and runtime selection remain unproven. See `receipts/2026-09-19-android-dtbo-a-scan.txt`. The earlier 32-by-56 interpretation was a field-order mistake and is superseded. |
| Source, Android DT selection unresolved | Entry 51 is the strongest RP6 candidate by matching public SoC/board IDs, but matching IDs do not prove ABL selected it for the observed run. Its `fragment@30` target fixup, exact ABL overlay-selection behavior, and merged runtime DT remain to be verified. The public RP6 overlay source does not itself declare the L1SS property. |
| Source, two Android PCIe suspend hooks | The nearby public driver has both a host-platform `suspend_noirq` path gated by `qcom,apss-based-l1ss-sleep` and a root-PCI-device `SUSPEND_LATE` fixup. Source ordering puts the root PCI device's noirq fixup before its parent host-platform callback: the host bridge is allocated as a child of the PCIe platform device, and DPM makes a parent wait for children. If the fixup runs, it calls PME_TURNOFF/L23, then `msm_pcie_disable()`; `msm_pcie_clk_deinit()` clears the ICC vote and `msm_pcie_disable()` sets `power_on=false`, so the later host callback skips its `enumerated && power_on` body, including APSS/L1SS logic. If the root PCI device is skipped, the host callback may take the APSS/L1SS path instead. The public source proves the ordering and conditions, not which runtime branch executed on this build. |
| Source | Armada uses upstream DesignWare/Qualcomm PCIe PM plus patches 0513/0520. If the generic D3cold check fails, `dw_pcie_suspend_noirq()` returns before host teardown and leaves `pci->suspended` false. In the qcom fallback branch, direct deep (`PM_SUSPEND_MEM`) skips the OPP update; with the OPP-based path this leaves the active OPP request. The `opp-suspend` floor from 0520 is selected only in the non-S2RAM branch. |
| Source, 0513/0520 nuance | Patch 0513 does call its OPP helper when the host really suspended; for `PM_SUSPEND_MEM` that helper passes `NULL`, which drops associated OPP bandwidth. But when D3cold is vetoed, the helper call is nested inside the non-`PM_SUSPEND_MEM` fallback, so deep suspend skips it. The patch therefore does not bypass the PCI safety check; it preserves the active request when the host remains running. |
| Observed, source mapping | Mainline SM8550 maps BCM MC0 to EBI and SH0 to LLCC. Replaying the exact v7.2.3 aggregation formula against the 19:03 awake snapshot predicts MC0/SH0 `vote_x=525, vote_y=2034`; the captured SLEEP TCS instead has `vote_x=0, vote_y=952` (`0x600003b8`). GPU, UFS, and display requests change before that TCS; PCIe has no corresponding update. The awake summary is therefore not the final SLEEP-bucket input and cannot prove the exact client contribution. |
| Observed/source | `interconnect_summary` includes each request's current tag and bandwidth, while `icc_set_bw` tracepoints omit request tags and enabled state. The suspend trace records several client bandwidth changes before SLEEP staging. Exact final per-request SLEEP membership is still unknown; a pre-suspend-only attribution calculator would be misleading. |
| Source, Linux v7.2.3 | `icc_summary_show()` and `aggregate_requests()` both traverse the node's `req_list` using the same hlist iteration order. The qcom RPMh provider callback receives each request's tag/avg/peak before the core `icc_set_bw` tracepoint reports the node aggregate. This provides a source-grounded way to attach callback inputs to the fresh request list, with the generic aggregate tracepoint as a cross-check. Sources: [summary traversal](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L48-L69), [aggregate traversal](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L255-L283), [ICC update tracepoints](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L673-L720), [qcom RPMh aggregate](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/icc-rpmh.c#L69-L104). |
| Harness, pushed / live unverified | Commit `ff1a541` adds `icc-attribution`: it captures per-request qcom aggregation inputs for EBI/LLCC, checks request-list/tag order and trace loss, verifies sums/maxima against `icc_set_bw`, and records the observed Apps-RSC SLEEP command group. It checks command-index continuity but cannot prove firmware acceptance. It is guarded by the inspected 7.2.3 release/BTF hash and reports unresolved instead of assigning clients when checks fail. Unit/smoke tests pass; it has not run on the device. No votes, kernel behavior, or power policy changed. |
| Observed/source | Android SLEEP TCS contains LDOE1/LDOE3 sleep-context commands. Mainline qcom-rpmh-regulator currently submits ACTIVE_ONLY requests and does not provide an equivalent sleep-context API. The awake regulator summary does not show what firmware applies in suspend. |
| Source, nearby Android match only | Downstream `rpmh-regulator.c` parses each proxy's `qcom,set` into independent active/sleep participation, aggregates separate requests, stages a `RPMH_SLEEP_STATE` update, and stages the restored active values in `RPMH_WAKE_ONLY_STATE` when they differ. Android's LDOE1/LDOE3 `-so` proxies are sleep-only while `-ao` proxies are active-only; the captured TCS disables them for SLEEP and re-enables them for WAKE. This explains the state-specific mechanism, but not whether every physical consumer is safe to depower for its wake source. In the captured run, an initial suspend attempt was interrupted by a Wi-Fi event and aborted with `timerfd` pending; a subsequent deep entry reached CPU shutdown and reported `pm8xxx_rtc_alarm` as its wake IRQ. This does not demonstrate Wi-Fi/PCIe-initiated wake from the deeper path. [Run receipt](../../receipts/2026-09-19-android-deep-rpmh/android-icc-suspend-run.log), [kernel excerpt](../../receipts/2026-09-19-android-deep-rpmh/android-icc-suspend-excerpt.txt), [aggregation](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/regulator/rpmh-regulator.c#L665-L707), [SLEEP and WAKE_ONLY submissions](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/regulator/rpmh-regulator.c#L800-L855), [active restore](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/regulator/rpmh-regulator.c#L876-L904), [`qcom,set` parsing](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/regulator/rpmh-regulator.c#L1910-L1920). |
| Source, Armada DT | For Nova, LDOE1 (`vreg_l1e_0p88`) supplies PCIe PHY, DSI0 PHY, and USB HS PHY. LDOE3 (`vreg_l3e_1p2`) supplies DSI0, PCIe PHY PLL, UFS PHY PLL, USB HS PHY, and USB/DP QMP PHY. RP6 disables DSI1. These consumers make a blanket rail-off change unsafe to infer from the TCS alone. |
| Unknown | Which of the seven Android DTBO candidate overlays were selected and whether the observed run used the APSS/L1SS branch; ordering of the host noirq callback versus the PCI suspend-late fixup; which root-port/endpoint power states and wake path it reached; exact matching Android source/build and merged runtime DT; final sleep-bucket per-client contributions to each BCM value; which LDOE consumers may be changed safely at sleep; whether any one request difference causes the counter difference. |

## Current hypothesis ranking and decision

1. **PCIe/other ICC sleep requests remain active.** This has the strongest
   direct support: the nearby Android driver clears its PCIe ICC request in
   both source-visible host-off routes, while Armada's D3cold veto returns
   before equivalent host teardown and its bandwidth request correlates with
   the MC0/SH0 floors. Android's awake request matches the public driver's
   fixed-vote branch rather than the candidate property-enabled branch. The
   exact Android route/build and final Armada SLEEP-bucket client list remain
   unverified, so this is not yet causal proof.
2. **Android's broader BCM request set changes shared fabric sleep state.** The
   captured Android and Armada TCS command sets differ substantially, but a
   staged request is not proof the AOP accepted it, and multiple resources
   change together.
3. **LDOE1/LDOE3 sleep-context requests alter a required PHY or wake path.**
   These are directly observed in Android and absent from the mainline
   regulator path; their safe per-consumer semantics and causal relation to
   residency remain unknown.

No behavioral A/B is justified yet. The next low-risk step is the read-only
`icc-attribution` profile below. If it shows the PCIe request is retained in
the final SLEEP input, that strengthens the PCIe hypothesis but still does not
justify bypassing PCI safety checks. If it does not, investigate the remaining
BCM/regulator request differences before choosing one variable.

## Work checklist

### 1. Android versus Armada PCIe suspend path — do first

- [x] Inspect the public `pci-msm.c` implementation and the RP6 Android DT
  overlay; mark their applicability provisional where the actual vendor base
  DT/build is missing.
- [x] Resolve the nearby public driver's `qcom,no-client-based-bw-voting`
  behavior: it changes the link-speed vote form, while both source-visible
  host-off routes clear the PCIe ICC request. Do not assume this property
  suppresses suspend bandwidth votes or proves the runtime route.
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

- [x] Inspect the Linux v7.2.3 summary and aggregation paths, qcom RPMh
  aggregation, and tag-bit definitions. Both summary and aggregation traverse
  `req_list` in the same order; the core aggregate tracepoint can validate
  callback input sums/maxima.
- [x] Add a read-only `icc-attribution` harness profile. It captures each
  request passed to the EBI/LLCC qcom aggregate callback, maps by fresh
  `interconnect_summary` order, invalidates the mapping on path/tag changes,
  checks trace loss and generic aggregate totals, and records final staged
  Apps-RSC SLEEP commands. It does not modify votes.
- [x] Run local syntax, parser, and harness smoke tests. They pass.
- [ ] Run the profile on the Nova. The device did not answer SSH and was absent
  from ADB at the latest access check, so no live attribution is available yet.
- [ ] Determine from live callback rows whether PCIe accounts for all or only
  part of MC0/SH0's SLEEP input. The awake-snapshot calculation is not a valid
  final attribution because suspend callbacks change requests before staging.

### 3. Compare regulator sleep contexts

- [x] Map Nova's Armada-DT consumers of LDOE1/LDOE3: PCIe PHY, UFS PHY,
  USB HS/DP PHY, and DSI0. Android merged-DT mapping remains open.
- [x] Inspect the nearby Android regulator driver: it represents active and
  sleep votes separately and queues restored active values in WAKE_ONLY state.
- [x] Verify mainline qcom-rpmh-regulator does not emit the corresponding
  SLEEP/WAKE_ONLY requests; standard suspend-state DT alone is not enough.
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

- Device control is currently SSH over Wi-Fi only; at 2026-09-20 00:33 UTC the
  SSH connection to `192.168.0.20:22` timed out and `adb devices -l` was empty.
  Preserve Wi-Fi and the current Linux boot while
  source work is possible. Do not test a Wi-Fi/PCIe change remotely without a
  verified independent recovery route.
- Do not force PCI D3hot, bypass `pci_host_common_d3cold_possible()`, change
  `pcie_ports` again, manually alter ICC votes, blindly disable shared rails,
  send AOSS/QMP commands, or access guessed MMIO/AOP memory.
- Do not patch offsets or kernel behavior before completing the source audit.
- Any device trial must use the existing reversible kernel-layer/bootc test
  path with a verified rollback. Record preflight, exact diff, run receipt,
  rollback, and post-resume function checks.

## Next device run

When the Nova is reachable over SSH, run one 10-second deep suspend with Wi-Fi
and Bluetooth preserved. The `icc-attribution` profile is read-only and
fail-closed; its kernel release/BTF guard aborts before suspend if this is not
the inspected 7.2.3 build. Command:

```sh
python3 research/sm8550-suspend-lab/sm8550_suspend_lab.py host run \
  --target armada --mode deep --sleep-seconds 10 \
  --wifi-state preserve --bluetooth-state preserve \
  --trace-profile icc-attribution \
  --hypothesis "Identify EBI/LLCC clients contributing to the final Apps-RSC SLEEP request" \
  --changed-variable "Read-only ICC/RPMh tracing; no votes or power policy changed" \
  --recommendation "Accept client attribution only if loss, list/tag stability, callback order, and aggregate cross-checks pass" \
  --confidence "Linux staged TCS only; does not prove firmware acceptance or physical residency"
```

## Working files

- Chronology, corrections, and test receipts: [lab-notebook.md](lab-notebook.md)
- Latest read-only Linux PM snapshot: [live PM receipt](../../receipts/2026-09-19-live-pm-readout.txt)
- Android SLEEP/WAKE TCS and ICC excerpts: `../../receipts/2026-09-19-android-deep-rpmh/`
- Existing harness: [sm8550_suspend_lab.py](sm8550_suspend_lab.py)
- Kernel/package patch stack: sibling checkout
  `../../../armada-packages/kernel/patches/`
