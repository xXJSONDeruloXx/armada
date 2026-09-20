# SM8550 suspend investigation status

**Read this first.** This is the current checklist and evidence boundary for
the Nova suspend investigation. The [lab notebook](lab-notebook.md) remains
the chronological record, including failed runs and superseded interpretations.
Update this page when a checklist item changes; put raw output in a dated
receipt and explain the result in the notebook.

Status as of 2026-09-20 12:11 UTC. Repository branch
`feat/sm8550-suspend-lab`. Wireless ADB verified that the installed Android
PCIe module matches the disassembled copy. Live split-BTF maps the connected-
DRV `link_status` and the late-fixup/noirq gates; the successful Android
callback/TCS trace confirms PCIe ICC clears while physical PCI state during
sleep remains unknown. Linux source explains why its OPP-backed PCIe client
keeps the active 500,000 kB/s request in direct deep when D3cold eligibility
prevents the host from suspending. A new exact-binary/live-DT comparison
identifies Android's `dcvs_fp` driver as the producer of the additional
`MC4`/`SH5` SLEEP and WAKE_ONLY requests. Its source-matched binary and live DT
show the two baseline requests queued at probe; the earlier successful trace
contains the same addresses and data. This resolves request ownership, not
whether those votes cause deeper residency. Mainline's standard SLEEP/WAKE API
can stage the pair without importing Android's missing active fast-path code.
The preferred first A/B is to stage just this pair through a test-only RPMh
consumer; it leaves PCIe state, active WCN bandwidth, and regulators
unchanged. The reviewed low-bandwidth OPP remains an alternate experiment, not
the selected first test. Only its targeted PCIe object and Nova DTB were built;
no linked image containing that proposal, package archive, or bootc layer has
been verified. The separate scratch `Image`/`vmlinux` files are not evidence
that they contain the proposed change. Resume
restores a maximum OPP and then reapplies the negotiated link OPP when the
link is up. Android's awake regulator summary distinguishes active and
sleep-only LDOE proxy instances but does not show sleep-time rail state. The
latest live DT still shows `qcom,drv-name="lpass"` and no pcie0 APSS/L1SS
property. The active Android `boot_a` was pulled read-only; its embedded
source paths name `VENDOR.13.2.6/kernel_platform/common`, but the exact source
revision remains unidentified. A recent isolated RPMh trace attempt did not
reach deep: Android aborted in prepare at `3da0000.kgsl-smmu` with `-115` while
the display was ON. Its trace instance, RTC alarm, and temporary `deep`
selection were cleaned up; global tracing is off, Wi-Fi/ADB remain healthy.
Earlier direct `rtcwake -m mem` and unarmed-forceSuspend mistakes
remain documented; do not repeat them. The user-supplied anchor
`054766d5...` predates the current branch tip. The candidate Linux 7.2.3
config has `CONFIG_PCIE_QCOM=y` (even though `CONFIG_MODULES=y`), so Kbuild
links `pcie-qcom.o` into the kernel and emits no `.ko`. This is also the
package's normal configuration: ARM64 defconfig sets the symbol to `y`, the
package override does not change it, and the standard build targets
`Image dtbs modules`. The current device is Android, so this is not a live read
of its installed Linux config. A functional A/B needs a linked kernel Image
plus the Nova DTB, not a driver-module swap. Receipt:
`receipts/2026-09-20-pcie-qcom-linkage-check.txt`. Wireless ADB now reports
the Android kernel suffix `g697b78910a71-dirty` and RPN engineering build
fingerprint. That commit is absent from the nearby public checkout and GitHub
returns no commit for it; use exact installed-binary evidence and keep the
public source labeled as a match, not the exact vendor tree. Receipt:
`receipts/2026-09-20-android-kernel-build-identity.txt`. The exact Android
RPMh/ICC binaries are now recovered read-only from the active A-slot
`vendor_boot` ramdisk and match the running kernel's `vermagic`/`scmversion`.
The vendor BCM voter follows the same ACTIVE/WAKE/SLEEP pipeline as mainline;
the Android regulator binary does have separate SLEEP/WAKE request support,
unlike mainline's current ACTIVE_ONLY-only regulator helper. This confirms a
capability difference, not a residency cause. Receipt:
`receipts/2026-09-20-android-live-rpmh-module-decomp.md`.

## Most recent Android probe

A later screen-off attempt still did not complete deep suspend. The
`suspend_control_internal` service returned false; `suspend_stats` success
stayed at 99, fail advanced 6→8, and `failed_freeze` advanced 2→3, with the
last recorded failure at `alarmtimer.0.auto` (`-16`). A 107,372-byte trace is
retained outside Git. It contains 283 BCM commits and 396 RPMh sends, but no
write to `0x50060` or `0x50064`. The `dcvs_fp` probe staged those SLEEP/WAKE
requests earlier in boot, before tracing began; this failed attempt does not
contradict the exact successful-run attribution. The device has since been
woken; live checks show Android awake, `wlan0` up, `[s2idle] deep` restored,
empty RTC wakealarm, global tracing off, and no tracefs instance. The earlier
screen-on attempt separately aborted at `3da0000.kgsl-smmu` with `-115`.
Repeated Android attempts are low-value until the freeze/preparation blocker
is isolated. Details and trace hash are in
`../../receipts/2026-09-20-android-boot-image-and-trace-failure.md`.

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
| Observed, exact Android binary + live DT | The exact A-slot `dcvs_fp.ko` (`vermagic` `5.15.123-g697b78910a71-dirty`, live `scmversion` matches) is bound to `/soc/apps_rsc@17a00000/drv@2/qcom,dcvs-fp`. Its live properties select `qcom,ddr-bcm-name=MC4` and `qcom,llcc-bcm-name=SH5`; the module disassembly reads the names through CMD-DB, then submits two RPMh commands in SLEEP and WAKE_ONLY contexts during probe. This identifies the software producer of the MC4/SH5 commands in Android's successful TCS capture. It does not show firmware acceptance by itself or establish that these two votes cause residency. Receipt: `../../receipts/2026-09-20-android-dcvs-fp-binary-and-dt.md`. |
| Source, mainline v7.2.3 RPMh interface | Mainline has no `dcvs_fp` driver or `rpmh_init_fast_path()`/`rpmh_update_fast_path()` API. It does export `cmd_db_read_addr()` and `rpmh_write_async()`; SLEEP/WAKE requests are cached, then `rpmh-rsc` flushes them to TCS before low-power entry. `rpmh_rsc_probe()` populates child devices, so a test-only child under Apps-RSC `drv@2` can bind to the correct controller. The prepared v7.2.3 config enables modules, RPMh, CMD-DB, OF overlays, and configfs; `CONFIG_MODVERSIONS` is off. `Module.symvers` is not present yet, so standalone-module build feasibility remains to verify. |
| Observed, live Android merged DT | Runtime model is KalamaP HDK with IDs matching the public Nova DTBO candidate. Active WCN is under `pcie@1c00000`, has `qcom,drv-name=lpass`, and lacks `qcom,apss-based-l1ss-sleep`, `qcom,no-client-based-bw-voting`, and `qcom,pcie-switch-type`; pcie1 is disabled. The exact successful mode-0 trace, combined with the absent switch-type property/default 0, establishes the connected-DRV branch and connected flag for that run. The `qcom,drv-supported` fallback and exact runtime DT are in `../../receipts/2026-09-20-android-live-runtime.md`; callback and module identity evidence is in `../../receipts/2026-09-20-android-live-pcie-validation.md`. |
| Observed, earlier Android suspend attempts | Before the successful capture below, this boot had `success=0`, `fail=3`. One natural attempt logged WLAN bus-suspend success then a `NETLINK` abort. Direct `rtcwake -m mem` returned `EBUSY`; its alarm was cleared. A later unarmed `forceSuspend()` returned false. The short s2idle intervals around those attempts remain unattributed. Do not repeat direct `rtcwake -m mem` or call forceSuspend before a verified RTC alarm. Receipt: `../../receipts/2026-09-20-android-live-runtime.md`. |
| Observed, controlled Android deep capture | On the same Android boot, `service call suspend_control_internal 2` returned true with temporary `deep` selected and a verified `+8s` rtc0 alarm. The kernel logged `PM: suspend entry (deep)` and `pm8xxx_rtc_alarm` wake; `suspend_stats` success advanced 0→1. Baseline-zero APSS/AOSD/CXSD/DDR records advanced to counts 1/165/17/17. The suspend-boundary ICC hook showed two tag-3 ACTIVE_ONLY DCVS clients and no PCIe client. Wi-Fi/ADB recovered; `mem_sleep`, hook, and alarm were restored. This proves Android deep reaches these firmware-recorded states in this run, but does not identify the exact PCIe suspend branch, final TCS, or a single causal difference. Receipt: `../../receipts/2026-09-20-android-deep-icc-followup.md`. |
| Observed, exact Android PCIe branch and final staged TCS | A bounded `deep` run traced `cnss_pci_suspend()`/`cnss_pci_suspend_bus()` success, `msm_pcie_pm_control(mode=0)`, `msm_pcie_drv_suspend()`, and `qcom_pcie_icc_bw_update(0, 0)`. The exact binary stores `link_status=DRV(3)`; its root-port `SUSPEND_LATE` body requires `ENABLED(1)`, matching the absence of `msm_pcie_pm_suspend()`/`msm_pcie_clk_deinit()` hits. The noirq callback checks `enumerated`, `power_on`, and `apss_based_l1ss_sleep`; live pcie0 lacks the DT property setting the last flag, so the APSS/L1SS teardown body is skipped. The run stages 14 SLEEP/14 WAKE commands; MC0/SH0 SLEEP words are zero, LDOE1/LDOE3 requests are present, and APSS/AOSD/CXSD/DDR advance. Neither no OS-issued D-state setter calls nor post-resume D0 establishes physical PCI state during sleep. Receipt: `../../receipts/2026-09-20-android-exact-pcie-branch.md` and `../../receipts/2026-09-20-android-live-pcie-validation.md`. |
| Observed, Android PCI PM callbacks | A separate short Android `deep` run saw successful normal/noirq suspend and resume callbacks for Qualcomm host, root port, and WCN endpoint. Kprobes for `pci_set_power_state()` and `pci_raw_set_power_state()` recorded no hits. This establishes no software D-state setter was observed, not the physical sleep-time state. Post-resume root and endpoint were D0 and WLAN was up. Trace settings/probes were cleaned and verified. Receipt: `../../receipts/2026-09-20-android-live-pcie-validation.md`. |
| Observed, exact live Android modules/BTF | Wireless ADB reported the same fingerprint, slot `_a`, and kernel as the prior capture. The three installed modules match prior A-slot SHA-256 values; live split-BTF gives exact `msm_pcie_dev_t` offsets for `link_status=0x480`, `apss_based_l1ss_sleep=0x409`, `enumerated=0x535`, and `power_on=0x6a4`. These offsets anchor the exact binary branch reconstruction. This does not identify the missing vendor source revision or physical PCI state during sleep. Receipt: `../../receipts/2026-09-20-android-live-pcie-validation.md`. |
| Observed, Android source identity check | Live `uname`/`/proc/version` report `5.15.123-android13-8-g697b78910a71-dirty`, Clang 14.0.7, and build time 2026-07-20; fingerprint is `qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys`. The nearby public checkout is `93c5cc6ad1d0b807510cfa0fb1d06f47407881f9` on `lineage-23.2`; it does not contain the reported suffix, and GitHub's commit endpoint/search returns no matching commit. Exact vendor source is still unlocated; disassembly is from hash-matched installed modules. Receipt: `receipts/2026-09-20-android-kernel-build-identity.txt`. |
| Observed, fresh Android PCIe module re-pull | While Android was running, Wireless ADB pulled `pci-msm-drv.ko`, `cnss2.ko`, `ep_pcie_drv.ko`, and `mhi_cntrl_qcom.ko` read-only. Each `vermagic` matches `5.15.123-g697b78910a71-dirty`; the host and CNSS hashes match the previously disassembled files. The host binary retains symbols and BTF. Disassembly confirms the connected-DRV branch skips the conditional endpoint D3hot calls, then calls the host mode-0 path which clears ICC to `0/0`. This confirms the prior static reconstruction against files on the live boot; no suspend was run and physical PCI state remains unknown. Receipt: `receipts/2026-09-20-android-live-pcie-binary-repull.txt`. |
| Observed, exact CNSS property fallback | The live pcie0 DT has `qcom,drv-name="lpass"` but no `qcom,drv-supported`. Disassembly of the hash-matched installed `cnss2.ko` shows `cnss_pci_update_drv_supported()` checks for the first property, then uses presence of `qcom,drv-name` as its fallback and stores the boolean. Thus the exact module enables its DRV-supported path for this host. Combined with the saved mode-0 trace and absent/default-zero switch type, the connected-DRV branch is established for that successful run. This does not prove physical PCI state while asleep. Receipt: [live DT and binary fallback](receipts/2026-09-20-android-live-dt-refresh.txt). |
| Observed, live Android awake regulator summary | Read-only root access over Wireless ADB shows `pm_v6e_l1` active (`use=1`, `open=14`, 880 mV), including PCIe 0.9-V consumer `1c00000.qcom,pcie-vreg-0p9` at 80 mA and DSI0 PHY. `pm_v6e_l3` is active (`use=2`, `open=15`, 1200 mV), including PCIe 1.2-V consumer at 18 mA and DSI0. The `pm_v6e_l1_so` and `pm_v6e_l3_so` sleep-only proxy rows are idle with zero users while awake; UFS/USB/DP consumers shown in the excerpt are inactive. These are awake regulator-core accounting values, not proof of which loads or physical rails are active during suspend. Receipt: [Android awake regulator excerpt](receipts/2026-09-20-android-regulator-summary-awake.txt). |
| Observed, host-side transport check | At 06:16 UTC the previously documented Android peer at `192.168.0.163` answered ping, but TCP/5555 and tested alternate access ports refused, ADB device/mDNS discovery was empty, and USB enumeration showed only the SanDisk drive. Current peer identity was not authenticated. No Android runtime state was collected or changed. Receipt: `../../receipts/2026-09-20-android-access-check.txt`. A later Wireless ADB session has since authenticated the same Android build and boot; see the 12:11 notebook entry. |
| Observed | Armada s2idle and direct PSCI SYSTEM_SUSPEND suspend/resume successfully. AOSD/CXSD/scalar DDR and recognized detailed DDR LPM rows remain zero; APSS/other subsystem evidence advances. |
| Observed | Android's captured Apps-RSC SLEEP/WAKE set has 11 BCM plus 3 PMIC regulator commands. It includes SH1, QUP2, ACV, MC4, SH5; MC0/SH0 SLEEP requests are zero/off; LDOE1/LDOE3 have explicit sleep requests. See `receipts/2026-09-19-android-deep-rpmh/`. |
| Observed | Armada stages six BCM sleep commands (MC0, SH0, SN0, CN0, QUP1, QUP0); MC0/SH0 are nonzero. The trace proves Linux staged these commands, not that AOP accepted/applied them. |
| Observed | The PCIe host's D3cold eligibility check fails on Qualcomm root port `0000:00:00.0` (`17cb:0113`) in `PCI_UNKNOWN`. Binding `pcieport` after a temporary boot-argument test did not change that result or clear the zero counters. Original `pcie_ports=compat` was restored. |
| Observed, live Linux cross-check | On the current 7.2.3 boot (`45137c86-bb9a-4021-9973-4bc6200fc9e6`), WCN7850 (`17cb:1107`) is under enabled `pcie@1c00000`; root `0000:00:00.0` is unbound, endpoint `0000:01:00.0` is bound to `ath12k_wifi7_pci`, both are awake in D0, link is Gen2 x1, and WLAN is up. Live FDT marks `pcie@1c08000` disabled. Both devices currently show `power/wakeup=disabled`; this awake-state value does not establish suspend-time wake behavior. Raw snapshot: `../../receipts/2026-09-20-live-pcie-cross-check.txt`. |
| Observed, exact ICC attribution | Reprocessing the lossless 2026-09-20 02:03 trace with the correct brace-wrapped `string[1]` parser mapped all 18 callbacks at each EBI/LLCC node to the fresh request list. Count, tag order, and callback sum/max match; no unmatched callbacks or trace loss. The only nonzero request carrying the SLEEP tag is `1c00000.pcie` with `tag=7`, `avg=0`, `peak=500000` kB/s, at EBI, `llcc_mc`, and `qns_llcc`. Full reanalysis is in `../../sm8550-suspend-lab-runs/20260920T020326Z-96e366a5fe0a/host-analysis/icc-aggregate-attribution-reparsed.json`. |
| Source, public match only | Available Android source `Ayn8550Dev/android_kernel_ayn_qcs8550` at `93c5cc6...` has a Qualcomm `pci-msm.c` noirq path gated by `qcom,apss-based-l1ss-sleep`. When selected and L1SS is confirmed, it disables config access, host clocks/GDSC/analog rails, and clears its ICC request; it does not set root-port or endpoint D3 state in that branch. Android logs confirm WCN/WoW bus-suspend success, not the endpoint's PCI power state. Running Android reported `g697b78910a71-dirty`, not matched to this public commit. |
| Source, public match only | The same `pci-msm.c` parses `qcom,no-client-based-bw-voting`; this changes the steady-state vote shape. The live merged pcie0 DT lacks that property, and the captured exact CNSS branch clears the PCIe request via `MSM_PCIE_DRV_SUSPEND`. Public code remains a nearby source match, not the exact Android tree. [Property/helper](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L3853-L3905), [property read](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L7598-L7603), [ICC clear](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L8645-L8665). |
| Observed + source inference | Android's saved interconnect summary reports the pre-suspend PCIe request as `tag=0, avg=500, peak=800` under `llcc_mc`, `ebi`, and `qnm_pcie`, matching the nearby source's fixed-vote constants. The active merged pcie0 lacks `qcom,no-client-based-bw-voting`; the exact Android source/build remains unmatched. The later suspend trace directly records the connected-DRV ICC clear and final zero MC0/SH0 SLEEP words. See [request snapshot](../../receipts/2026-09-19-android-deep-rpmh/android-interconnect-summary.txt), [PCIe branch/TCS receipt](../../receipts/2026-09-20-android-exact-pcie-branch.md), and [public helper](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L248-L249). |
| Observed, read-only Android DTBO | `dtbo_a` is a standard table with `dt_entry_size=32`, `dt_entry_count=56`. Seven entries contain the zero-length L1SS property. Entry 51 (`0xb71079`, size 378,507) has root IDs `<0x25b 0x20000>` and `<0x1001f 0>`, matching the public RP6 DT source IDs; its model label is KalamaP HDK. Its `fragment@30` adds both `qcom,apss-based-l1ss-sleep` and `qcom,no-client-based-bw-voting`; `__fixups__.pcie1` points that fragment's `target` at base-DT symbol `pcie1`. The base symbol path and runtime selection remain unproven. See `receipts/2026-09-19-android-dtbo-a-scan.txt`. The earlier 32-by-56 interpretation was a field-order mistake and is superseded. |
| Observed merged DT + public source match | The live Android runtime DT places active WCN under pcie0 at `0x1c00000`; pcie1 at `0x1c08000` is disabled and does not own WCN. The public RP6 DTBO's L1SS/no-client properties target pcie1, so they do not configure the active WLAN host in this boot. Exact base-DT source and ABL overlay provenance remain unknown. [PCIe node map](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalama-pcie.dtsi#L5-L18), [RP6 disables pcie1](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/moorechip/kalamap-moorechip-common.dtsi#L44-L46), [candidate property](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalamap-hdk.dtsi#L36-L40). |
| Source plus exact-binary reconstruction, root and host suspend hooks | The exact CFI root-port fixup compares BTF-mapped `link_status` to `ENABLED(1)` before its teardown call; `msm_pcie_drv_suspend()` writes `DRV(3)`, and its called teardown helpers were absent in the trace. Exact noirq disassembly checks BTF-mapped `enumerated`, `power_on`, and `apss_based_l1ss_sleep` fields, then returns before teardown if any is false. Active pcie0 lacks the selecting DT property, so the APSS/L1SS body was not selected. The fixup entry itself was not separately probed; physical PCI/link state remains unknown. Exact vendor source is unavailable. |
| Observed, exact Android endpoint/host path | Exact CNSS binary plus trace show the connected-DRV caller invokes host PM-control mode 0; the host enters `msm_pcie_drv_suspend()` and clears its ICC request to `0/0`. That branch skips explicit endpoint D3hot calls. The exact physical PCI state and the required wake behavior are still unknown. Nearby source references: [DRV path](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L9877-L9944), [PM-control API](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L9951-L10073), [root-fixup guard](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L9524-L9558). |
| Observed, exact installed Android modules | The A-slot `qca_cld3_kiwi_v2.ko`, `cnss2.ko`, and `pci-msm-drv.ko` were extracted read-only from the validated `vendor_dlkm_a` extent. All carry vermagic matching the recorded Android kernel `5.15.123-g697b78910a71-dirty`; identities and hashes are in `../../receipts/2026-09-20-android-exact-pcie-modules.txt`. Exact QCA code calls `wlan_hdd_bus_suspend()`, matching the saved `kiwi_v2` success log. Exact CNSS code requests D3hot only if its saved DRV-connected byte is zero; the connected branch skips the PCI D3hot calls. See the manual reconstruction in `../../receipts/2026-09-20-android-pcie-binary-decomp.md`. |
| Observed, exact Android binary call routes | `cnss_pci_suspend()` rejects a disconnected client with `-EAGAIN` when DRV support is enabled and the disable-DRV quirk is clear. `cnss_set_pci_link()` maps connected DRV to host mode 0, switch type 1 to mode 0, and default switch type 0 to normal mode 1. Exact `pci-msm-drv.ko` clears ICC in DRV suspend, normal clock teardown, and the gated APSS/L1SS noirq route. The captured mode 0 plus active-DT absence of switch type establishes the connected-DRV branch; the trace observes its `0/0` ICC update. No endpoint PCI config-state probe was installed. |
| Source inference, default ICC tag | In both the nearby Android and v7.2.3 mainline `qcom_icc_aggregate()`, `tag=0` is normalized to `QCOM_ICC_TAG_ALWAYS`; the binding defines this as AMC + WAKE + SLEEP. Thus Android's saved PCIe request (`tag=0`) would normally participate in the SLEEP bucket if left unchanged. Its final MC0/SH0 SLEEP TCS words are zero, which strongly implies the request was cleared or otherwise changed before final aggregation. This does not identify which Android suspend hook did it, and the Android kernel is a public source match rather than the exact running build. [Android aggregator](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/interconnect/qcom/icc-rpmh.c#L66-L95), [Android tag definitions](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/include/dt-bindings/interconnect/qcom,icc.h#L14-L24), [mainline aggregator](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/icc-rpmh.c#L84-L105), [mainline tag definitions](https://github.com/gregkh/linux/blob/v7.2.3/include/dt-bindings/interconnect/qcom,icc.h#L14-L24). |
| Observed, live Linux PM/capability read | At 03:08 UTC the same Linux boot was reachable by SSH over `wlp1s0` (`carrier=1`). Root `0000:00:00.0` and WCN7850 `0000:01:00.0` are D0/runtime-active with `power/control=on`, wake disabled, and `d3cold_allowed=1`; link is 5.0 GT/s x1. A bounded privileged read then found the same PM capability bytes (`01 50 03 c8 08 00`) on both functions: PME from D0, D3hot, and D3cold is supported; PMCSR reports D0 with PME enable clear. Thus missing PCI PM/PME capability is not the observed veto. This remains an awake snapshot. Receipts: `../../receipts/2026-09-20-live-pcie-pm-readout.txt` and `../../receipts/2026-09-20-live-pcie-pm-capabilities.txt`. |
| Source, current Linux root-port veto | On the current `pcie_ports=compat` boot the Qualcomm root port is unbound. In v7.2.3, PCI noirq suspend with no driver PM ops saves config and marks a D0 device `PCI_UNKNOWN`; the common D3cold helper skips only devices that are both unbound and disabled, then rejects any active device not in D3hot. This matches the previously captured root-port `PCI_UNKNOWN` veto. Its advertised PME capability is not reached because the state check fails first. The earlier one-shot pcieport-binding test still saw `PCI_UNKNOWN`, so this explains the current compat-mode path but does not fully explain the bound-port result. [PCI noirq fallback](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci-driver.c#L883-L950), [D0-to-unknown fallback](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci-driver.c#L624-L636), [D3cold per-device predicate](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/pci-host-common.c#L286-L310). |
| Source | Armada uses upstream DesignWare/Qualcomm PCIe PM plus patches 0513/0520. If the generic D3cold check fails, `dw_pcie_suspend_noirq()` returns before host teardown and leaves `pci->suspended` false. In the qcom fallback branch, direct deep (`PM_SUSPEND_MEM`) skips the OPP update; with the OPP-based path this leaves the active OPP request. The `opp-suspend` floor from 0520 is selected only in the non-S2RAM branch. |
| Source, 0513/0520 nuance | Patch 0513 does call its OPP helper when the host really suspended; for `PM_SUSPEND_MEM` that helper passes `NULL`, which drops associated OPP bandwidth. But when D3cold is vetoed, the helper call is nested inside the non-`PM_SUSPEND_MEM` fallback, so deep suspend skips it. The patch therefore does not bypass the PCI safety check; it preserves the active request when the host remains running. |
| Source, OPP path and tag feasibility | SM8550 has an OPP table, so QCOM PCIe uses OPP-managed paths rather than retaining direct ICC handles. At 5 GT/s x1 the OPP sets `pcie-mem=500000` and `cpu-pcie=1` kB/s, with `low_svs`. If D3cold is vetoed, DesignWare returns 0 before stopping the link or setting `pci->suspended`; the direct-ICC fallback would lower memory bandwidth to 1, but the OPP branch leaves the active OPP for `PM_SUSPEND_MEM`. `icc_set_tag()` only updates metadata; `icc_set_bw()` triggers aggregation/application, and the OPP paths are not exposed to QCOM PCIe. Static ACTIVE_ONLY tagging would also remove the existing s2idle sleep floor. Detailed source links and proposed A/B: `../../receipts/2026-09-20-android-live-pcie-validation.md`. |
| Observed, source mapping | Mainline SM8550 maps BCM MC0 to EBI and SH0 to LLCC. In the 02:03 run, the final Apps-RSC SLEEP words for MC0 (`0x50000`) and SH0 (`0x50004`) were both `0x600001dc`, encoding 476. The exact live callback trace shows the sole nonzero SLEEP-tagged client at those nodes is PCIe's 500,000 kB/s peak request. This establishes the origin of the staged floor; it does not prove the floor prevents AOSD/CXSD/DDR residency or that firmware accepted it. |
| Observed/source | `interconnect_summary` omits request enabled state, while `icc_set_bw` tracepoints omit tags. The live provider-callback capture resolves both: fresh-list order and tag values matched at all three nodes, and callback sum/max matched generic `icc_set_bw` aggregates. A system-wide `path_init` probe created false mutation noise, so it has been removed from future profiles; request-count/tag-order validation catches target-list changes, with path removal and retag probes retained as fail-closed checks. |
| Source, Linux v7.2.3 | `icc_summary_show()` and `aggregate_requests()` both traverse the node's `req_list` using the same hlist iteration order. The qcom RPMh provider callback receives each request's tag/avg/peak before the core `icc_set_bw` tracepoint reports the node aggregate. This provides a source-grounded way to attach callback inputs to the fresh request list, with the generic aggregate tracepoint as a cross-check. Sources: [summary traversal](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L48-L69), [aggregate traversal](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L255-L283), [ICC update tracepoints](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L673-L720), [qcom RPMh aggregate](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/icc-rpmh.c#L69-L104). |
| Harness, live validation and local fix pending | The 02:03 on-device run entered/resumed deep successfully (8.783 s observed sleep, same boot, RTC wake) but its wrapper marked the run failed because cleanup metadata expected an old `path_init` definition. The trace instance/probes were removed and Wi-Fi recovered. The unchanged trace has zero loss; a corrected offline parse validates exact attribution. The local harness now handles the kernel's brace-wrapped `string[1]` names, no longer installs the noisy `path_init` probe, and updates legacy cleanup matching. Local tests pass. The original device-derived report remains preserved beside the separate host reanalysis. |
| Observed/source | Android SLEEP TCS contains LDOE1/LDOE3 sleep-context commands. Mainline qcom-rpmh-regulator currently submits ACTIVE_ONLY requests and does not provide an equivalent sleep-context API. The awake regulator summary does not show what firmware applies in suspend. |
| Source, nearby Android match only | Downstream `rpmh-regulator.c` parses each proxy's `qcom,set` into independent active/sleep participation, aggregates separate requests, stages a `RPMH_SLEEP_STATE` update, and stages the restored active values in `RPMH_WAKE_ONLY_STATE` when they differ. Android's LDOE1/LDOE3 `-so` proxies are sleep-only while `-ao` proxies are active-only; the captured TCS disables them for SLEEP and re-enables them for WAKE. This explains the state-specific mechanism, but not whether every physical consumer is safe to depower for its wake source. In the captured run, an initial suspend attempt was interrupted by a Wi-Fi event and aborted with `timerfd` pending; a subsequent deep entry reached CPU shutdown and reported `pm8xxx_rtc_alarm` as its wake IRQ. This does not demonstrate Wi-Fi/PCIe-initiated wake from the deeper path. [Run receipt](../../receipts/2026-09-19-android-deep-rpmh/android-icc-suspend-run.log), [kernel excerpt](../../receipts/2026-09-19-android-deep-rpmh/android-icc-suspend-excerpt.txt), [aggregation](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/regulator/rpmh-regulator.c#L665-L707), [SLEEP and WAKE_ONLY submissions](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/regulator/rpmh-regulator.c#L800-L855), [active restore](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/regulator/rpmh-regulator.c#L876-L904), [`qcom,set` parsing](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/regulator/rpmh-regulator.c#L1910-L1920). |

| Source, upstream-quality design direction | In v7.2.3 the mainline RPMh send helper hardcodes `RPMH_ACTIVE_ONLY_STATE`, and its regulator op tables expose no suspend enable/disable/mode hooks. An upstream design should use the regulator core's standard suspend-state constraints and implement the RPMh provider support to stage per-regulator SLEEP commands plus appropriate WAKE_ONLY restoration from the active state. This is preferable to copying downstream `qcom,set` proxy nodes, but must account for shared-rail constraints and should be enabled only after board owners establish that consumers are quiesced or their wake paths remain powered. [Mainline send helper and ops](https://github.com/gregkh/linux/blob/v7.2.3/drivers/regulator/qcom-rpmh-regulator.c#L197-L209), [regulator ops](https://github.com/gregkh/linux/blob/v7.2.3/drivers/regulator/qcom-rpmh-regulator.c#L393-L433). |
| Source, regulator consumers | In the nearby Android Kalama/RP6 DT, LDOE1 supplies PCIe 0.9-V PHY, UFS QREF, USB EUSB2, DSI PHY, and DisplayPort PHY analog; LDOE3 supplies PCIe 1.2-V PHY/PLL, UFS PLL, USB EUSB2, USB3/DP QMP core, and DSI 1.2-V PHY. RP6 uses the public DSI0 panel overlay; DSI1 is disabled in its board common DTSI. Thermal I-sense references use separate active-only L1E/L3E proxies. Armada's Nova DT has the same broad PHY consumers, and no `regulator-state-mem` descriptions for these rails. The list establishes wiring, not which links remain wake-capable during Android's captured sleep. [Regulator proxies](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalama-regulators.dtsi#L690-L787), [UFS PHY](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalama-qrd.dtsi#L148-L166), [USB PHYs](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalama-usb.dtsi#L112-L145), [DSI/DP rails](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/display/display/kalama-sde.dtsi#L249-L291), [thermal active-only refs](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalama-thermal.dtsi#L213-L219). |
| Unknown | The exact Android source revision corresponding to the installed build beyond the exact inspected A-slot module binaries and nearby public source; root/endpoint PCI config state during sleep; whether PCIe/WCN, UFS, USB, display, or thermal paths must remain powered for each wake source; whether reducing only Armada's PCIe SLEEP request allows residency; whether any LDOE consumer must remain powered for a required wake path. The Android noirq APSS/L1SS body is resolved as skipped for active pcie0; the root-fixup entry itself remains unprobed, though its teardown branch is gated out by the observed DRV state and has no inner-function hits. |

## Exact Android module evidence

The active A-slot `vendor_boot` ramdisk confirms the loaded Android modules use
the same `g697b78910a71-dirty` build suffix. The exact `icc-bcm-voter.ko`
disassembly sends state arguments 2/1/0 to ACTIVE_ONLY/WAKE_ONLY/SLEEP, matching
the mainline BCM-voter implementation. The exact `rpmh-regulator.ko`
disassembly sends per-proxy aggregates in those three contexts, confirming the
sleep-context mechanism previously inferred from nearby public source. This
does not establish firmware acceptance or physical rail state. Android's
`ACV`, `QUP2`, and `SH1` resources also exist in the mainline SM8550 provider.
The earlier conclusion that MC4/SH5 ownership was unknown is superseded by
the exact `dcvs_fp` binary/live-DT attribution below. Keep these as separate
request-generation facts, not proof of why residency advances.
Detailed extraction, hashes, and ELF offsets: [module receipt](../../receipts/2026-09-20-android-live-rpmh-module-decomp.md).

## Current hypothesis ranking and decision

1. **The retained PCIe request is the strongest directly observed Linux-side
   correlate.** PCIe is the only nonzero SLEEP-tagged EBI/LLCC client and
   contributes the staged 476/952 MC0/SH0 words. Armada's root port fails
   D3cold eligibility in `PCI_UNKNOWN`; the DesignWare host returns before
   teardown and the active request remains. Android's connected-DRV path
   clears its ICC request to 0/0 before final TCS staging, while the residency
   counters advance. This is strong correlation, not causal proof.
2. **The missing Android DCVS-FP sleep/wake pair is the safest first A/B.**
   The exact binary, live DT, and successful Android TCS capture establish
   that Android queues SLEEP=0 and WAKE_ONLY=1 for MC4/SH5. Mainline can stage
   those requests with `rpmh_write_async()` without importing the vendor active
   fast path. Whether the pair enables residency is unknown. A temporary test
   consumer changes only those sleep/wake requests and preserves the live
   PCIe/WCN vote. Design and rollback caveats:
   [`dcvs-fp-ab-design.md`](../../receipts/2026-09-20-dcvs-fp-ab-design.md).
3. **LDOE1/LDOE3 sleep-context requests may affect shared PHY or wake paths.**
   Android stages them and mainline's RPMh regulator path does not. Several
   active consumers share these rails, so this remains the highest-risk
   hypothesis and is not the next experiment.

The Wi-Fi-off A/B reduced the MC0/SH0 word from 952 to 476 without advancing
AOSD/CXSD/DDR; binding `pcieport` also left the root veto and counters
unchanged. A reviewed Nova-only low-bandwidth OPP proposal remains available
as a later A/B, but is not first: if the host remains active it lowers the
PCIe memory path used by WCN. It preserves `low_svs` and `cpu-pcie=1` while
reducing `pcie-mem` from 500,000 to 1,000 kB/s; BCM quantization leaves a
minimum nonzero vote, not zero. Do not bypass the generic D3cold check, force a
PCI D-state, or infer safe D3 support from `d3cold_allowed=1` alone.

## Work checklist

### 1. Android versus Armada PCIe suspend path — do first

- [x] Inspect the public `pci-msm.c` implementation and the RP6 Android DT
  overlay; mark their applicability provisional where the actual vendor base
  DT/build is missing.
- [x] Resolve the nearby public driver's `qcom,no-client-based-bw-voting`
  behavior: it changes the steady-state vote form. The source has separate
  host and endpoint-client suspend paths that can clear ICC; this property
  does not prove which runtime path ran.
- [x] Read the Android slot `_a` DTBO partition without changing device state;
  parse its standard 32-byte entries and identify the seven property-bearing
  overlays. Entry 51 matches the public RP6 SoC/board IDs.
- [x] Resolve entry 51's `fragment@30` target fixup to the base-DT symbol
  `pcie1`.
- [x] Resolve the public base symbol: `pcie0` is at `0x1c00000`, `pcie1` at
  `0x1c08000`; the nearby public RP6 common DTSI disables `pcie1`. Cross-check
  the current Armada live FDT and WCN parent: active WLAN is under `pcie0` at
  `0x1c00000`. This weakens the overlay-property explanation for active WLAN.
- [x] Inspect the merged Android runtime DT: active WCN pcie0 lacks the L1SS
  and no-client-vote properties, while pcie1 is disabled and carries them.
  This closes their applicability to the active host; exact ABL overlay
  provenance remains unproven.
- [x] Capture the exact running Android build identity and check the nearby
  public checkout/GitHub for its kernel suffix. The suffix is not present; the
  nearby source remains a public match, while exact installed-module
  disassembly anchors runtime conclusions.
- [ ] Obtain the matching vendor source tree or build source if it becomes
  available; the public checks did not locate it.
- [x] Identify the current Armada runtime PCIe compatible, bound endpoint,
  and live DT status. Root port is unbound, WCN is bound to ath12k, both are
  awake in D0; WCN is under pcie0. This is not a suspend-time snapshot.
- [x] Compare nearby Android root-fixup, APSS/L1SS host, and endpoint-driver
  suspend routes. The public `MSM_PCIE_DRV_SUSPEND` API independently clears
  ICC and can suppress the later root fixup by changing link status. Exact
  A-slot module disassembly plus the instrumented run now confirm the CNSS
  connected-DRV caller, host mode 0, and the `0/0` ICC clear.
- [x] Run one bounded Android `deep` capture through `forceSuspend()` with an
  armed RTC wake. The call succeeded, firmware sleep records advanced, and
  Wi-Fi/ADB recovered. The suspend-boundary hook saw only ACTIVE_ONLY DCVS
  votes, not a PCIe request. This does not identify the PCIe callback route.
- [x] From Linux, inspect and manually reconstruct the exact A-slot
  `qca_cld3_kiwi_v2.ko`, `cnss2.ko`, and `pci-msm-drv.ko` without mounting or
  changing Android partitions. The connected-DRV versus D3hot branch, host
  mode selection, and all identified ICC-clear routes are recorded in the
  binary-decomp receipt.
- [x] Pull live split-BTF and map exact PCIe host private-field offsets to the
  installed module. Decode `msm_pcie_drv_suspend()` setting `link_status=DRV`
  and the root late-fixup requiring `ENABLED`; its teardown branch is skipped
  for the captured mode-0 route, matching the absent inner-call hits. The
  fixup entry itself was not separately probed.
- [x] Decode exact noirq gates. Active pcie0 lacks
  `qcom,apss-based-l1ss-sleep`, so the `apss_based_l1ss_sleep` flag is not set
  and the noirq callback returns before APSS/L1SS clock, regulator, analog,
  and ICC teardown. This resolves the previous callback-entry ambiguity.
- [x] Compare default ICC-tag semantics: both inspected aggregators map
  `tag=0` to AMC + WAKE + SLEEP, so Android's pre-suspend PCIe request cannot
  explain a zero SLEEP command merely by being untagged.
- [x] Capture the actual successful Android CNSS/host branch and final staged
  TCS. Mode 0 reaches connected-DRV suspend and clears PCIe ICC to 0/0; MC0/
  SH0 SLEEP words are zero while firmware counters advance. The endpoint's
  PCI config state remains unknown; the host noirq callback entry does not
  prove APSS/L1SS shutdown.
- [x] Capture a separate Android generic PCI PM callback trace. Host, root
  port, endpoint and noirq callbacks return success; no PCI state setter hits
  are recorded. Physical sleep-time PCI state remains unknown.
- [x] Pull the installed Android modules through Wireless ADB and verify all
  three SHA-256 values match the previously decompiled A-slot files. Exact
  module identity is established; exact vendor source revision is not.
- [x] Re-pull the host, CNSS, endpoint, and MHI modules from the running
  Android boot and verify their `vermagic`; exact host/CNSS hashes match the
  prior disassembly. This was read-only and did not repeat a suspend.
- [ ] Directly sample root/endpoint PCI state during sleep or otherwise prove
  the physical link state, and validate PCIe/WCN wake. The connected-DRV
  branch makes no explicit endpoint D3hot request. The exact APSS/L1SS body is
  skipped; the root-fixup teardown is gated out by `link_status=DRV`, but the
  callback entry was not separately probed.
- [x] Trace source ordering between the PCI `SUSPEND_LATE` fixup and host
  platform `suspend_noirq`; the captured trace has no `msm_pcie_clk_deinit()`
  hit, consistent with the late-fixup teardown route not running after CNSS
  entered DRV mode. Treat this as a traced absence, not proof of physical
  PCIe power state.
- [x] Compare that call path with Linux v7.2.3 `pcie-qcom.c`, DesignWare host
  PM, generic D3cold eligibility, Armada patches 0513/0520, and the PCI core's
  no-driver `PCI_UNKNOWN` suspend fallback.
- [x] Separate source from runtime evidence: the nearby source explains the
  paths, while exact installed-binary probes establish the connected-DRV
  branch and ICC clear; actual PCI state during sleep remains unobserved.

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
- [x] Run one 10-second profile on the Nova; the suspend/resume succeeded. The
  first host parse failed closed because kprobe string-array names were
  brace-wrapped and the run wrapper had stale cleanup metadata.
- [x] Reparse the unchanged, lossless trace. Exact order/count and aggregate
  checks pass for EBI, LLCC, and qns_llcc. PCIe is the sole nonzero
  SLEEP-tagged client (`500000` peak); MC0/SH0 each stage encoded `476`.
- [ ] Determine whether this request is a cause of zero AOSD/CXSD/DDR residency;
  this requires a source-justified safe A/B, not an awake-snapshot calculation.

### 3. Compare regulator sleep contexts

- [x] Map Nova's Armada-DT consumers of LDOE1/LDOE3: PCIe PHY, UFS PHY,
  USB HS/DP PHY, and DSI0. Android merged-DT mapping remains open.
- [x] Inspect the nearby Android regulator driver: it represents active and
  sleep votes separately and queues restored active values in WAKE_ONLY state.
- [x] Verify mainline qcom-rpmh-regulator does not emit the corresponding
  SLEEP/WAKE_ONLY requests; standard suspend-state DT alone is not enough.
- [x] Map principal LDOE1/LDOE3 consumers in the nearby Android RP6 DT: PCIe,
  UFS PHY, USB2 and USB3/DP PHY, DSI0; note thermal active-only proxies.
- [x] Capture the live Android awake regulator summary read-only. It confirms
  active PCIe/DSI consumers and separate idle sleep-only proxy rows; it does
  not establish suspend-time rail state or wake safety.
- [ ] Establish which of these consumers Android quiesced and which wake
  sources it retained. The captured run woke by RTC, so it does not validate
  PCIe/Wi-Fi or USB wake after the LDO sleep requests.
- [ ] Describe an upstream-quality regulator API/DT model that can emit sleep
  RPMh requests; do not blindly copy proxy properties or assume
  `regulator-state-mem` works in the current mainline driver.

### 4. Choose one A/B after the source gate

- [x] Rank the retained PCIe bandwidth request as the strongest directly
  observed Linux-side correlate; preserve other differences as alternatives,
  not proven causes.
- [x] Identify the exact Android baseline MC4/SH5 SLEEP and WAKE_ONLY pair.
- [x] Select that pair as the preferred first test-only A/B because it leaves
  active PCIe/WCN bandwidth, PCI state, and shared regulators unchanged. This
  is a design selection only; no module or overlay has been built or deployed.
- [x] Keep the Nova-only 1,000 kB/s OPP proposal as a reviewed alternate. Its
  targeted object and DTB passed isolated checks; the full linked image and
  bootc layer were not built. See the
  [build receipt](receipts/2026-09-20-nova-opp-target-build.md).
- [ ] Build the temporary module against the prepared Linux 7.2.3 tree and
  validate a runtime OF-overlay child reaches the Apps-RSC `drv@2` RPMh
  controller. `Module.symvers` is absent; compile feasibility is not yet
  established.
- [ ] Verify the live Linux base deployment, test-layer installation path,
  rollback deployment, and reboot health before staging either A/B.
- [ ] Run one bounded pair A/B only after those gates pass. If the pair is
  staged but the counters remain zero, retain the PCIe OPP proposal as the
  next candidate rather than combining variables.
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

- The Nova is currently on rooted Android, reachable over Wireless ADB at the
  discovered TLS endpoint (it may change after reconnect). The last bounded
  run stayed on boot ID `d927cfaa-54f1-428d-9f3b-1298aa1982fc`; `wlan0` is
  connected. `mem_sleep=[s2idle] deep`, `debug_suspend=0`, and RTC wakealarm
  empty were verified after cleanup. Preserve Android Wi-Fi/ADB access during
  further runtime tracing.
- Do not force PCI D3hot, bypass `pci_host_common_d3cold_possible()`, change
  `pcie_ports` again, manually alter ICC votes, blindly disable shared rails,
  send AOSS/QMP commands, or access guessed MMIO/AOP memory.
- Do not repeat the closed sleep-stats offset experiment or change `qcom_stats`
  offsets. Do not stage the selected RPMh A/B until its module/overlay build,
  runtime binding, and Linux rollback checks pass.
- Any device trial must use the existing reversible kernel-layer/bootc test
  path with a verified rollback. Record preflight, exact diff, run receipt,
  rollback, and post-resume function checks.

## Next action

The user confirms the Nova's default boot is Armada Linux and authorizes using
`adb reboot` from Android to return to it. First switch to Linux, then capture a
fresh read-only baseline: active bootc deployment, kernel/config, prior
rollback deployment, PCIe/WLAN state, and kernel-layer install support. The
`armada` SSH alias timed out while Android was active, so reconnect only after
Linux has booted. Then compile the small MC4/SH5 RPMh consumer and verify that a
runtime OF overlay can bind it under Apps-RSC `drv@2`. Do not stage a behavioral
change until the compile/bind path and rollback checks pass.

The archived Linux trace and host reanalysis remain under
`.external-research/sm8550-suspend-lab-runs/`; do not edit their raw data.

## Working files

- Chronology, corrections, and test receipts: [lab-notebook.md](lab-notebook.md)
- Latest read-only Linux PM snapshot: [live PM receipt](../../receipts/2026-09-19-live-pm-readout.txt)
- Android SLEEP/WAKE TCS and ICC excerpts: `../../receipts/2026-09-19-android-deep-rpmh/`
- Latest Android PCIe callback, module-hash, and Linux OPP source audit:
  [validation receipt](../../receipts/2026-09-20-android-live-pcie-validation.md)
- Existing harness: [sm8550_suspend_lab.py](sm8550_suspend_lab.py)
- Kernel/package patch stack: sibling checkout
  `../../../armada-packages/kernel/patches/`
