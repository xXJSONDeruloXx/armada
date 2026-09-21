# WCN7850, PCIe host, and wake contract audit

**Captured:** 2026-09-21 10:25 UTC  
**Source:** Armada Linux 7.2.3 build input and the Nova/QCS8550 board DTS  
**Changed behavior:** none; source review only

## The observed Linux ath12k path

Linux has two materially different ath12k suspend paths:

1. When ath12k's hardware state is OFF and suspend is supported,
   ath12k_core_suspend_late() disables HIF interrupts and requests HIF
   power-down. The PCI HIF path selects MHI POWER_OFF_KEEP_DEV, which calls
   mhi_power_down_keep_dev(..., true). The 2026-09-21 08:32 trace directly
   observed this path, including ath12k_pci_power_down(is_suspend=1) and
   graceful=1.
2. The cfg80211 WoW path configures wake triggers, protocol offloads and
   keepalive, enables firmware WoW, disables HIF interrupts, and calls HIF
   suspend. That selects MHI MHI_SUSPEND/M3; ath12k_wow_op_set_wakeup()
   separately toggles the device wakeup flag.

The capture proves that Linux requested the full ath12k/MHI shutdown path for
that run. It does not prove the WCN silicon or PCIe link was physically off.
It also does not show the WoW callbacks or the wake-enable value during sleep;
the WoW/M3 path must not be attributed to that run. After resume, the saved
evidence is only that the interface returned UP/LOWER_UP, not that Wi-Fi
reassociated or passed traffic.

## Host-owned shutdown and resume ordering

The Qualcomm DesignWare host calls the common D3cold eligibility check before
PME Turn Off, LTSSM/L2 handling, link stop, or host deinitialization. If the
check fails, the host returns early and remains unsuspended. Qualcomm disables
its CPU/PCIe and memory/PCIe ICC paths and selects the suspend OPP only after
pci->suspended becomes true; the live-host fallback preserves a minimum
request instead.

After a successful eligibility check, host deinit asserts PERST, powers off
the PCI power-control devices unless skip_pwrctrl_off is set, then powers
off the PHY/controller. On resume, Qualcomm restores the maximum OPP and ICC
paths before DesignWare resume. Host init asserts PERST, initializes the
controller and PHY, powers the WCN pwrseq if it was shut down, applies
post-init configuration, deasserts PERST, and configures the SID. This is the
ordered Linux mechanism that could make a host power-down truthful; it is not
reached on the default boot while the root port vetoes D3cold.

skip_pwrctrl_off is derived from a wakeup-enabled downstream function's
PME-from-D3cold capability. It preserves WCN power for a possible PME wake
path; it is not proof that this board has a functioning sideband wake route.

## WCN power sequencer and board wake GPIO

The generic PCI power-control wrapper matches WCN7850 compatible
pci17cb,1107, gets the QCOM WCN sequencer's wlan target, and delegates
power-on/off to that sequencer. Its WLAN disable step drives the
wlan-enable GPIO low. The QCOM WCN driver has an explicit source comment
that driving this GPIO low without coordinated controller link-down handling
causes PCIe link-down and makes the device unusable. Do not toggle this GPIO
directly or test it independently of the PCIe host suspend sequence.

Nova DTS declares wake-gpios = <&tlmm 96 GPIO_ACTIVE_HIGH> and
reset-gpios = <&tlmm 94 GPIO_ACTIVE_LOW> on pcieport0. The active Linux
Qualcomm host/DesignWare driver does not parse wake-gpios or configure a
wake IRQ from it. That property alone therefore cannot be counted as Linux's
working WCN wake contract. Standard endpoint PME/WoW may be a separate route,
but the existing trace did not prove its enablement or electrical behavior.
The current awake sysfs snapshot had power/wakeup=disabled for both root
port and WCN endpoint; this awake value does not prove their suspend-time
settings.

The same board file maps shared RPMh PMIC rails as follows:

| Rail | Board consumers relevant to suspend |
|---|---|
| LDOE1 / vreg_l1e_0p88 | DSI1 PHY, PCIe PHY, USB HS PHY |
| LDOE3 / vreg_l3e_1p2 | DSI1, PCIe PLL, UFS PHY PLL, USB HS PHY, USB/DP QMP PHY |

Android's explicit LDOE sleep requests therefore cannot be copied as blanket
disable operations without knowing which wake paths remain armed. Linux's
single awake regulator summary cannot establish the sleep-context value.

## Decision

This source review clarifies why the Qualcomm host must own any WCN power
sequencing and why endpoint MHI power-down is not equivalent to host/link
shutdown. It does not supply a safe single-variable A/B: the default root-port
state blocks host teardown, the earlier bound-root run lacks the noirq
eligibility fields, and Linux's declared root wake-gpios is not wired into
the active host driver. Do not force a PCI state, directly toggle the WCN
GPIO, clear ICC, or disable LDOE1/LDOE3.

Before a host-suspend A/B can be justified, the missing observations are:

- For any available bound-root path: root state_saved, skip_bus_pm,
  bridge_d3, driver presence and pci_prepare_to_sleep() return; downstream
  D-states; and the host's pci->suspended result.
- Whether this use case requires Wi-Fi wake. If it does, identify the actual
  wake signal/PME route and verify it is enabled through Linux's suspend and
  resume callbacks. The current awake power/wakeup read is insufficient.
- Whether Android's connected-DRV path preserves a physical WCN wake route or
  intentionally powers WLAN down; its installed-binary trace establishes the
  ICC clear, not the electrical endpoint state.

No suspend test or configuration change was made for this audit.

## Source references

- Linux v7.2.3 [ath12k OFF-state guard and full late power-down](https://github.com/gregkh/linux/blob/v7.2.3/drivers/net/wireless/ath/ath12k/core.c#L102-L179)
- Linux v7.2.3 [ath12k WoW suspend and wake enable](https://github.com/gregkh/linux/blob/v7.2.3/drivers/net/wireless/ath/ath12k/wow.c#L861-L959)
- Linux v7.2.3 [MHI full shutdown vs M3](https://github.com/gregkh/linux/blob/v7.2.3/drivers/net/wireless/ath/ath12k/mhi.c#L441-L523)
- Linux v7.2.3 [WCN7850 PCI pwrctrl match](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pwrctrl/pci-pwrctrl-pwrseq.c#L109-L130)
- Linux v7.2.3 [QCOM WCN WLAN GPIO sequence and link-down warning](https://github.com/gregkh/linux/blob/v7.2.3/drivers/power/sequencing/pwrseq-qcom-wcn.c#L200-L225) and [probe-time GPIO safety comment](https://github.com/gregkh/linux/blob/v7.2.3/drivers/power/sequencing/pwrseq-qcom-wcn.c#L515-L539)
- Linux v7.2.3 [DesignWare D3cold gate and link teardown](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-designware-host.c#L1223-L1293)
- Linux v7.2.3 [Qualcomm PCIe host init/deinit](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-qcom.c#L1362-L1467) and [suspend ICC/OPP handling](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-qcom.c#L2211-L2315)
- Nova DTS: /Users/danhimebauch/Developer/.external-research/armada-packages/kernel/dts/qcs8550-ayn-common.dtsi lines 793-820, 1066-1123, 1728-1754
- Upstream [WCN7850 suspend RFC](https://lists.infradead.org/pipermail/ath12k/2023-July/000460.html) and [merged ath12k suspend/resume series](https://lists.infradead.org/pipermail/ath12k/2024-April/002079.html)
