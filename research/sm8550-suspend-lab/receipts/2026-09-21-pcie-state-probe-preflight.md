# PCI state probe preflight

**Captured:** 2026-09-21 07:56 UTC\
**Device:** Retroid Nova, stock Armada Linux `20260915.feca679`, kernel `7.2.3`\
**Boot ID:** `3656b0e7-5671-4b7e-9368-67965daa251a`

This read-only preflight was taken before extending the existing `pcie-d3cold`
trace profile. It confirmed the device was still on the stock deployment with
no staged image or queued rollback. The preflight JSON is
`/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/preflight-20260921T075649Z-840908d5eed9.json`, SHA-256
`4274e4189b8a34a8d0790ebe785406c3174cf4864aa040e5308e1577f35bacdb`.

The kernel exposes `pci_set_power_state` through
`/sys/kernel/tracing/available_filter_functions`, and it is not listed in the
kprobe blacklist. `pci_pm_set_unknown_state` is absent from the available
function list, so the harness must not depend on probing it. The profile now
records only `pci_set_power_state()` entry arguments for Qualcomm vendor
`0x17cb`, domain 0, buses 0 and 1. It captures `pci_dev.current_state`, device
identity, and the requested D-state using the existing BTF-validated field
offsets. The `pcie-d3cold` profile already records the PCI device-PM callback
tracepoints and the later per-device state/result from the host D3cold walk.

That combination answers the software contract without probing the optimized
helper: Linux v7.2.3's `pci_pm_suspend_noirq()` saves state and takes its
`set_unknown` path when the PCI device has no PM driver, and
`pci_pm_set_unknown_state()` changes a D0 software state to `PCI_UNKNOWN`
([source](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci-driver.c#L894-L950)).
The host's D3cold walk rejects active devices that are not in D3hot
([source](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/pci-host-common.c#L286-L310)).
DesignWare returns before link stop/deinit when that check fails
([source](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-designware-host.c#L1223-L1233));
Qualcomm then retains the minimum memory bandwidth needed by the unsuspended
host ([source](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-qcom.c#L2211-L2245)).

The upcoming run is an unchanged-stock, RTC-woken, short direct-deep
observation. It will not alter PCI state, ICC, RPMh, regulators, boot state, or
device policy. It can establish which software D-state requests are made and
which state the host eligibility check sees; it cannot prove the physical
link's electrical state while the SoC is asleep.
