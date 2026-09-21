# Root-port D3cold eligibility audit

**Captured:** 2026-09-21 10:14 UTC  
**Device:** stock Armada 20260915.feca679, Linux 7.2.3  
**Boot ID:** 3656b0e7-5671-4b7e-9368-67965daa251a  
**Changed behavior:** none; source review and read-only SSH/sysfs inspection

## Live default-boot state

The current boot command line contains **pcie_ports=compat**. Read-only sysfs
inspection showed:

| PCI function | Driver | Enabled | Tracked state | Wake | D3cold allowed |
|---|---|---:|---|---|---:|
| 0000:00:00.0, Qualcomm 17cb:0113 root port | unbound; pcieport driver directory absent | 1 | D0 while awake | disabled | 1 |
| 0000:01:00.0, WCN7850 17cb:1107 | ath12k_wifi7_pci | 1 | D0 while awake | disabled | 1 |

The kernel's pcie_ports parser sets pcie_ports_disabled when the value is
compat. With no PCI driver PM operations, pci_pm_suspend_noirq() saves the
function's state and follows its unknown-state path. The running helper then
visits the root port: it ignores a function only when both its driver is
unbound and PCI is disabled. This root port is unbound but enabled=1, so it is
still an active participant. Its PCI_UNKNOWN state is sufficient to veto the
host's D3cold transition.

This source explanation matches the 09:15 capture, which observed the enabled,
unbound root port at PCI_UNKNOWN and the host D3cold check returning
-EOPNOTSUPP. The endpoint's tracked D3hot state does not override the root
port's failure. The live read is not a new suspend run and says nothing about
electrical state.

## Why not filter out bridges generically

The common helper's comment describes downstream endpoints, but its current
implementation does not filter by PCIe type: it walks the host bus and checks
each active PCI function's tracked D-state and wake capability. During review
of the Qualcomm D3cold series, the maintainers explicitly rejected an
endpoint-only filter because a switch, bridge, root port, RC-integrated
endpoint, or conventional device with a bound driver may need to remain in
D0. The merged helper therefore intentionally checks all active functions.

Consequently, changing the generic helper to ignore every bridge or root port
would be broader than this Armada case and could let a host power off a
component whose driver still needs it. A Qualcomm-host-specific exception
could be considered only if source and a run-scoped trace prove that this
integrated root port is controlled by the host suspend sequence, every
downstream active function is quiesced, and wake is preserved or intentionally
disabled.

## Bound-root-port gap

The September 19 run with pcieport bound still saw 17cb:0113 at PCI_UNKNOWN.
Its trace did not record the root port's state_saved, skip_bus_pm, or
bridge_d3 values, nor whether pci_prepare_to_sleep() was entered and what it
returned. The PCI core only attempts that transition when state is not already
saved, skip_bus_pm is clear, and pci_power_manageable() is true; for a bridge,
the latter means bridge_d3. Those missing fields prevent us from choosing
between a skipped transition, an ineligible bridge, or a failed transition.

The current normal boot cannot reproduce the bound case: pcie_ports=compat is
present and the pcieport driver is absent. The previous experiment that
changed that policy must not be repeated. Until a naturally available,
approved configuration presents the bound path, there is no safe live read
that can recover those historical callback values.

## Decision and next diagnostic

No behavioral A/B is justified. The current default-path veto is explained,
but the bound-path reason and wake contract are not. Do not edit
pci_host_common_d3cold_possible() to ignore the root port, force its software
state, bypass the check, or zero PCIe ICC.

If a future diagnostic run can observe the bound configuration without
repeating the prohibited boot-policy change, extend the existing PCI PM trace
to capture, for 17cb:0113 at pci_pm_suspend_noirq() entry, current_state,
state_saved, skip_bus_pm, bridge_d3, and driver presence; pair it with
pci_prepare_to_sleep() entry/return, the endpoint's state/wakeup/PME
capability, the D3cold-walk result, and dw_pcie_suspend_noirq()'s
pci->suspended result. The existing PCI PM profile already captures endpoint
D3hot and the D3cold walk; only the root noirq decision fields are missing.

If the trace shows a host-owned root-port state that is not a real active
downstream dependency, a narrow Qualcomm host contract could be evaluated.
If it instead shows skip_bus_pm, bridge_d3=false, or a failed
pci_prepare_to_sleep(), each outcome points to a different fix and must not
be guessed in advance.

Relevant source:

- Linux v7.2.3 [pcie_ports=compat parser](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pcie/portdrv.c#L606-L633)
- Linux v7.2.3 [PCI noirq fallback](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci-driver.c#L883-L950)
- Linux v7.2.3 [common D3cold walk](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/pci-host-common.c#L286-L343)
- Linux v7.2.3 [bridge power-manageable test](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci.h#L321-L328)
- Qualcomm D3cold series [maintainer discussion on checking bridges and root ports](https://patchew.org/linux/20260429-d3cold-v5-0-89e9735b9df6%40oss.qualcomm.com/20260429-d3cold-v5-1-89e9735b9df6%40oss.qualcomm.com/#414)
- September 2026 [fix for early bus-walk exit](https://lists.openwall.net/linux-kernel/2026/09/05/59); it preserves continued PME-capability discovery but does not make an active PCI_UNKNOWN root port eligible.
