# Linux PCIe suspend state capture and upstream comparison

**Captured:** 2026-09-21 09:15 UTC\
**Device:** stock Armada `20260915.feca679`, Linux `7.2.3`\
**Boot ID:** `3656b0e7-5671-4b7e-9368-67965daa251a` before and after\
**Run:** `20260921T091515Z-5d4b010ecf94`\
**Mode:** direct `deep`, RTC wake; observed suspend-clock separation 12.195 s\
**Changed behavior:** none; this run added scoped trace probes only

Raw archive: `/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T091515Z-5d4b010ecf94/device/`.

## New observation

The trace directly observes Linux's generic PCI core preparing WCN7850
`0000:01:00.0` (`17cb:1107`) for sleep:

```text
pci_prepare_to_sleep_entry  pdev_state=0 bus=1 vendor=6091 device=4359 class=163840
pci_prepare_to_sleep_return pdev_state=3 bus=1 vendor=6091 device=4359 class=163840 retval=0
```

The BTF-validated `current_state` changed from `PCI_D0` to `PCI_D3hot`, and
`pci_prepare_to_sleep()` returned success. This closes the Linux software-state
question for the endpoint. It does **not** read PMCSR during sleep and does not
prove the WCN silicon or link electrically powered down.

Immediately afterward, the Qualcomm host's common D3cold walk rejected root
port `0000:00:00.0` (`17cb:0113`) in software `PCI_UNKNOWN` (state 5), with
`-EOPNOTSUPP` (`-95`). On this stock `pcie_ports=compat` boot, the root port is
unbound. The PCI core's no-driver `pci_pm_suspend_noirq()` path saves config
and marks a D0 device unknown. The common eligibility helper ignores only an
unbound *and disabled* function; this enabled root port is rejected because
its state is not D3hot.

The Qualcomm DesignWare host then returns before PME Turn Off, LTSSM/L2
handling, link stop, and host deinitialization. Consequently
`pci->suspended` remains false and the ordinary host-suspended ICC/OPP removal
does not run. The final staged MC0/SH0 SLEEP words in this capture remain
`0x600001dc` (476), consistent with the retained active PCIe request. The
named AOSD/CXSD/scalar-DDR counters remain unchanged. This is a stronger
software-path diagnosis than the earlier zero-hit `pci_set_power_state()`
probe, but still not proof that host teardown alone would enable residency.

There were two earlier experiments with `pcie_ports=compat` removed and
`pcieport` bound. The first run (`20260919T181557Z-cb567ba69946`) recorded
`-EOPNOTSUPP` without device identity/state. The follow-up
(`20260919T182725Z-0615b49b6039`) added BTF-validated identity and did capture
the bound root port `17cb:0113` at `PCI_UNKNOWN` (state 5), also returning
`-EOPNOTSUPP`. Both runs left the named counters at zero. Thus binding the
driver did not clear the root-port veto.

The follow-up did not trace why the bound port ended the generic PCI noirq
path at `PCI_UNKNOWN`. `pcie_portdrv_pm_ops` has a regular `.suspend` callback
and `.resume_noirq`, but no `.suspend_noirq`; the PCI bus callback handles the
state. It calls `pci_prepare_to_sleep()` only when state was not already saved,
`skip_bus_pm` is clear, and `pci_power_manageable()` is true. For a bridge the
last condition is `bridge_d3`. The generic fallback changes a still-D0 device
to `PCI_UNKNOWN`; a successfully transitioned D3hot port would remain D3hot.
The 18:27 run did not record the root's `bridge_d3`/`skip_bus_pm`, endpoint
state at that point, or root-port `pci_prepare_to_sleep()` entry/return, so the
exact branch remains unresolved. Do not repeat the boot-argument test; the
09:15 capture establishes the unbound-path veto on the normal compat boot.

## Linux and Android contract comparison

The current Linux sequence is now evidenced at the software layer:

1. ath12k requests its suspend-specific PCI/MHI power-down; `mhi_power_down_keep_dev(graceful=1)` is observed.
2. Generic PCI PM calls `pci_prepare_to_sleep()` for the WCN endpoint and tracks it in D3hot.
3. The host's all-device D3cold eligibility walk is vetoed by the enabled root port's unknown state.
4. DesignWare skips its host/link shutdown path; Qualcomm preserves the live PCIe request needed for the unsuspended host.

Android's exact installed-binary trace instead shows CNSS's connected-DRV
path calling `msm_pcie_pm_control(mode=0)` and the Qualcomm host clearing its
PCIe ICC request to 0/0. That path skips OS-issued endpoint D3hot setters.
Android's logs and callbacks do not establish the physical endpoint state
while asleep, so the two implementations are not yet proven equivalent at the
hardware level. See
[`android-exact-pcie-branch.md`](2026-09-20-android-exact-pcie-branch.md).

The correct Linux direction remains a truthful, ordered host/WCN suspend
contract: quiesce the endpoint, honor its wake configuration, establish the
host/link shutdown condition, and only then remove host bandwidth/OPP demand.
Marking `current_state` manually, bypassing the common safety check, or
zeroing ICC while the host is still live would not implement that contract.
No behavioral A/B is justified by this capture alone.

## Comparison against current upstream

Compared function bodies from the local Armada build input (`v7.2.3`) against
Linus's `master` at `93f51579e7df248780214094418f205253383cc5` on 2026-09-21:

| Function | Result | Relevant meaning |
|---|---|---|
| `pci_pm_suspend_noirq()` | identical | Generic endpoint D-state transition and unknown-state fallback are unchanged. |
| `__pci_host_common_d3cold_possible()` and wrapper | identical | Active functions must be D3hot; an unbound disabled function alone is skipped. |
| `dw_pcie_suspend_noirq()` | identical | The failed eligibility check still returns before PME/link/host teardown. |
| `ath12k_pci_power_down()` and `ath12k_core_suspend_late()` | identical | Upstream ath12k's late MHI/device suspend path has not become Qualcomm host-controller suspend. |
| `qcom_pcie_suspend_noirq()` / resume | different OPP plumbing only | Current upstream uses `dev_pm_opp_set_opp(..., NULL)` where this Armada tree uses its suspend-OPP helper; the D3cold test, ICC disable after host suspend, and live-host fallback remain the same. Armada also has its scoped diagnostic OPP branch. |

The upstream WCN7850 suspend series implements ath12k/MHI firmware suspend
and resume. Its early RFC explicitly notes that MHI could not fully shut down
the device and used firmware WoW as a workaround; the merged series later
enabled WCN7850 suspend support. This is relevant endpoint behavior, not a
replacement for `pcie-qcom.c` host/link shutdown.

## Run health and boundaries

The device returned on the same boot, Wi-Fi is `UP/LOWER_UP`, and a fresh SSH
check at 09:21 UTC still reports kernel 7.2.3 and both PCI functions awake in
D0. The run-scoped kprobes and trace instance were cleaned successfully.
`rpm-ostree-countme.service` is failed because its Fedora repository requests
failed; the logged failures are userspace network errors and are not PCI PM or
suspend callback failures. The short test did not run a Wi-Fi functional test
beyond interface recovery.

## Source references

- Linux v7.2.3 [`pci_pm_suspend_noirq()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci-driver.c#L883-L977) and [`pci_prepare_to_sleep()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci.c#L2611-L2690)
- Linux v7.2.3 [`pcie_portdrv_pm_ops`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pcie/portdrv.c#L656-L668) and bridge [`pci_power_manageable()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci.h#L316-L328)
- Linux v7.2.3 [`pci_host_common_d3cold_possible()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/pci-host-common.c#L286-L367)
- Linux v7.2.3 [`dw_pcie_suspend_noirq()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-designware-host.c#L1223-L1292)
- Linux v7.2.3 [`qcom_pcie_suspend_noirq()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-qcom.c#L2211-L2281)
- Current upstream at [`93f51579`](https://github.com/torvalds/linux/tree/93f51579e7df248780214094418f205253383cc5): [PCI noirq](https://github.com/torvalds/linux/blob/93f51579e7df248780214094418f205253383cc5/drivers/pci/pci-driver.c#L906-L1000), [host D3cold predicate](https://github.com/torvalds/linux/blob/93f51579e7df248780214094418f205253383cc5/drivers/pci/controller/pci-host-common.c#L269-L350), [DesignWare suspend](https://github.com/torvalds/linux/blob/93f51579e7df248780214094418f205253383cc5/drivers/pci/controller/dwc/pcie-designware-host.c#L1225-L1294), [Qualcomm suspend](https://github.com/torvalds/linux/blob/93f51579e7df248780214094418f205253383cc5/drivers/pci/controller/dwc/pcie-qcom.c#L2340-L2396)
- Upstream [WCN7850 suspend RFC](https://lists.infradead.org/pipermail/ath12k/2023-July/000460.html) and [merged ath12k suspend/resume series](https://lists.infradead.org/pipermail/ath12k/2024-April/002079.html)
