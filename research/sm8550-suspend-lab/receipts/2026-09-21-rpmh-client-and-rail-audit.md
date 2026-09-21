# Remaining RPMh request and shared-rail audit

**Date:** 2026-09-21\
**Scope:** source and saved Android/Linux receipts only; no device state or power policy changed

## What is attributable now

| Difference | Producer/client evidence | Linux equivalent and boundary | Residency relevance / risk |
|---|---|---|---|
| **QUP2** | Mainline's `bcm_qup2` aggregates `qup2_core_slave`. The saved Android awake interconnect summary shows the only nonzero QUP2 client is `89c000.qcom,qup_uart` (590000 on `qhs_qup2`, plus QUP2 core votes). The final Android TCS proves a QUP2 SLEEP request exists, but the awake summary does not prove which client's SLEEP-tag vote contributed. | Linux's corresponding device is Qualcomm GENI UART `89c000.serial`. Its system-sleep callback changes the UART state, but the PM core's held runtime-PM usage reference prevents GENI runtime suspend, leaving its request active; Linux's final SLEEP batch has no QUP2 command. Console balancing and the active serdev child constrain a force-suspend backport. | A plausible request-set difference, but there is no evidence QUP2 gates AOSD/CXSD/DDR. Fixing the GENI PM path is separable from the primary PCIe host veto and should not be A/B-tested as a residency fix without stronger evidence. |
| **SH1** | Linux `bcm_sh1` aggregates 13 nodes, including `qnm_pcie` and `qns_pcie`, plus GPU, CPU/app, modem DSP, multimedia, compute and other NoC nodes. Android's SH1 TCS command is the result of an aggregate BCM vote, not a single named client. | The BCM definition exists in Armada's mainline SM8550 ICC driver; this is not an absent-resource-definition issue. The saved Android evidence does not include a SLEEP-tagged per-client vote list. | Could reflect PCIe or unrelated NoC clients. No leaf client or causal gate is established. Changing SH1 globally would have broad memory/NoC effects. |
| **ACV** | Linux `bcm_acv` is a boolean enable-mask (`0x8`) over the EBI node. It summarizes memory-path demand; the TCS word cannot be assigned to a single interconnect client. | The `bcm_acv` provider exists in Armada. Android's SLEEP ACV value is known from the final TCS, but no saved per-client SLEEP aggregation receipt identifies who kept or cleared it. | It is plausibly tied to aggregate memory demand, but no evidence shows it is the missing gate. Avoid an isolated ACV override. |
| **LDOE1 / LDOE3** | Exact installed Android regulator binaries implement separate active/sleep proxy contexts and emitted explicit LDOE1/LDOE3 SLEEP and WAKE requests. The exact vendor source tree remains unavailable; disassembly is from hash-matched installed modules. | Armada's `qcom-rpmh-regulator.c` routes normal requests through `RPMH_ACTIVE_ONLY_STATE`; its registered `regulator_ops` do not implement `set_suspend_voltage`, `set_suspend_enable`, `set_suspend_disable`, or `set_suspend_mode`. Adding only `regulator-state-mem` DTS properties would therefore not make this driver emit RPMh SLEEP requests. | Shared consumers make an experimental disable unsafe. Consumer supply mappings identify possible wake-path dependencies, not whether each block is active during suspend. |

## Shared regulator consumers in the Nova board source

The local Linux build input is
`/Volumes/NovaKernelBuild/work/linux-7.2.3/arch/arm64/boot/dts/qcom/qcs8550-ayn-common.dtsi`;
the Nova DTS includes the RP6/common board description.

- **LDOE1 / `vreg_l1e_0p88`:** DSI1 PHY `vdds`, PCIe0 PHY `vdda-phy`, and USB HS PHY `vdd`.
- **LDOE3 / `vreg_l3e_1p2`:** DSI1 `vdda`, PCIe0 PHY `vdda-pll`, UFS PHY `vdda-pll`, USB HS PHY `vdda12`, and USB/DP QMP PHY `vdda-phy`.

The source establishes consumers, not runtime load or wake guarantees. The
Android sleep test's RTC wake does not validate PCIe/WCN, UFS, USB, DSI, or
DisplayPort wake with either rail changed.

## What a correct regulator implementation would require

Use standard regulator suspend constraints as the policy input, and add
driver callbacks that translate them into RPMh SLEEP context commands. Resume
must restore/clear the temporary SLEEP policy through the supported RPMh
WAKE_ONLY/ACTIVE request model. The RPMh driver must keep active votes and
sleep votes separate, handle unsupported combinations and request ordering,
and preserve consumer constraints for shared rails. Android's `qcom,set`
proxy-node semantics should not be copied into the upstream binding, and
standard regulator-state DTS alone is insufficient while the driver only
submits ACTIVE_ONLY requests. This needs regulator-core and hardware-owner
review before any LDOE experiment.

## Remaining exact-attribution gap

The saved Android TCS is a final aggregate. The available Android
`interconnect_summary` is an awake snapshot, so it identifies the awake QUP2
UART client and PCIe clients but does not expose each client's SLEEP-tagged
contribution to SH1, ACV, or QUP2. Exact leaf ownership requires a
context-specific per-client vote capture from the matching Android build, or
matching vendor source that exposes the aggregation inputs. Do not infer the
owner from one final BCM command.

Before any regulator A/B, also establish which wake paths must function and
whether those consumers are truly idle or held by Linux during the target
sleep. The current evidence is not enough to choose a safe one-variable rail
change.

## Source pointers

- Linux v7.2.3 SM8550 BCM mappings: [`bcm_acv`, `bcm_qup2`, `bcm_sh1`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/sm8550.c#L1302-L1433)
- Linux v7.2.3 RPMh regulator ACTIVE_ONLY submission and ops: [`rpmh_regulator_send_request()` and VRM ops](https://github.com/gregkh/linux/blob/v7.2.3/drivers/regulator/qcom-rpmh-regulator.c#L188-L209), [registered regulator ops](https://github.com/gregkh/linux/blob/v7.2.3/drivers/regulator/qcom-rpmh-regulator.c#L393-L433)
- Standard regulator suspend callback contract: [`struct regulator_ops`](https://github.com/gregkh/linux/blob/v7.2.3/include/linux/regulator/driver.h#L228-L243)
- Local board supply mappings: `/Volumes/NovaKernelBuild/work/linux-7.2.3/arch/arm64/boot/dts/qcom/qcs8550-ayn-common.dtsi:792-800,1065-1088,1117-1121,1727-1753`
- Saved Android awake request summary: `../../receipts/2026-09-19-android-deep-rpmh/android-interconnect-summary.txt`
- Exact Android PCIe and regulator context evidence: [`android-exact-pcie-branch.md`](2026-09-20-android-exact-pcie-branch.md) and [`android-live-rpmh-module-decomp.md`](2026-09-20-android-live-rpmh-module-decomp.md)
- Linux QUP2 runtime-PM trace: [`2026-09-21-qup2-rpm-trace-confirmation.md`](2026-09-21-qup2-rpm-trace-confirmation.md)
