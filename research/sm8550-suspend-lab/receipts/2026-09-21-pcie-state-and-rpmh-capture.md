# Stock PCIe state and RPMh SLEEP/WAKE capture

**Captured:** 2026-09-21 08:00 UTC\
**Device:** Retroid Nova, stock Armada `20260915.feca679`, kernel `7.2.3`\
**Boot ID:** `3656b0e7-5671-4b7e-9368-67965daa251a` before and after\
**Run:** `20260921T080019Z-044f01e5858f`\
**Mode:** direct `deep`, RTC wake after 15 seconds\
**Changed behavior:** none; run-scoped trace probes only

The host run archive is
`/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T080019Z-044f01e5858f/device/`.

## Observations

- Deep suspend/resume completed without reset. The boot ID was unchanged;
  `CLOCK_BOOTTIME - CLOCK_MONOTONIC` was 13.278 seconds. The RTC interrupt
  and RTC wakeup-source counters each advanced once. Wi-Fi returned UP with
  carrier. This establishes resume for this short control, not long-term
  stability.
- The `pci_set_power_state()` probe was registered and filtered for Qualcomm
  PCI devices on buses 0 and 1; it recorded zero calls. The root-port D3cold
  walk then recorded device `17cb:0113`, bus 0, software `current_state=5`
  (`PCI_UNKNOWN`), and `-95` (`-EOPNOTSUPP`). In v7.2.3, the unbound-root-port
  branch in `pci_pm_suspend_noirq()` saves config and marks its state unknown;
  `pci_host_common_d3cold_possible()` rejects the active non-D3hot device.
  This is software state and does not reveal the physical link state while
  asleep.
- The PCI endpoint's actual driver is `ath12k_wifi7_pci`. The PM trace labels
  PCI callbacks `bus`, because `pci_pm_suspend_late()` calls
  `pm_generic_suspend_late()`, which dispatches to the bound driver's
  `suspend_late` operation. The endpoint's `late bus [suspend]` callback ran
  for about 102 ms and returned 0; the noirq PCI bus callback also returned
  0. Armada registers `ath12k_pci_pm_suspend_late()`, which calls
  `ath12k_core_suspend_late()`. That helper can return early unless system
  suspend is supported and the ath12k hardware state is OFF; only on the
  continuing path does it disable HIF interrupts and call
  `ath12k_hif_power_down(ab, true)`. The PM trace proves dispatch into the
  driver's late callback, but does not capture whether that guard passed or
  whether HIF power-down ran. The earlier interpretation that a missing
  literal `late driver` trace label meant the ath12k callback was skipped was
  wrong. The endpoint's MHI/WCN shutdown still needs a direct call/state
  observation, and this path does not itself perform the root-port D3cold
  transition or prove WCN physical power state.
- The root-port D3cold eligibility check still fails before DesignWare host
  link teardown. The root port has no bound PCI driver, which is why the PCI
  core takes its `PCI_UNKNOWN` fallback. No `pci_set_power_state()` request
  was observed for either filtered Qualcomm PCI device.
- The Apps-RSC `rpmh_send_msg` trace recorded six SLEEP commands on TCS 3 and
  six WAKE commands on TCS 5:

  | State | Address | Data |
  |---|---:|---:|
  | SLEEP | `0x50000` | `0x600001dc` |
  | SLEEP | `0x50004` | `0x600001dc` |
  | SLEEP | `0x50010` | `0x40000000` |
  | SLEEP | `0x50038` | `0x40000000` |
  | SLEEP | `0x50048` | `0x00000000` |
  | SLEEP | `0x50044` | `0x40000000` |
  | WAKE | `0x50000` | `0x60000823` |
  | WAKE | `0x50004` | `0x600011db` |
  | WAKE | `0x50010` | `0x60004001` |
  | WAKE | `0x50038` | `0x60004001` |
  | WAKE | `0x50048` | `0x20004001` |
  | WAKE | `0x50044` | `0x60004001` |

  In this run the retained MC0/SH0 SLEEP value was `0x600001dc` (476),
  not zero. These records show the command payloads generated while the RSC
  writes sleep/wake TCS slots. They are not a firmware completion or residency
  acknowledgment. `rpmh_send_msg` is emitted before the final command-enable
  register write; the Linux `tcs_tx_done()` IRQ path is documented and wired
  only for active-only TCSes. Linux does not trigger the SLEEP/WAKE TCSes;
  its source says firmware triggers them on entry to the deepest low-power
  mode. No separate RSC/AOP acceptance or application readback was captured.
- AOSD, CXSD, and scalar DDR firmware-recorded count/duration deltas were all
  zero. Detailed DDR ID `0xd0` advanced 308,721,078 raw ticks with count
  delta zero; its meaning and units remain undecoded. The RPMh RSC snapshot
  artifact was unavailable. No PSCI kretprobe was part of this profile.
- The trace instance and both owned kprobes were removed successfully. The
  run did not change ICC, OPP, PCIe state, regulators, boot policy, or image.

## Interpretation and remaining boundary

This capture proves Linux reached the software stage that populates the RSC
SLEEP/WAKE TCS slots. It distinguishes that from any active-TCS transaction
completion: `rpmh_tx_done` acknowledgments seen elsewhere in the trace are for
active TCS IDs. The available Linux interface does not report that firmware
triggered these sleep requests or applied their resource values. The named
AOSD/CXSD/DDR counters remain the nearest trustworthy residency observables;
they remained unchanged in this window.

The next source-backed diagnostic improvement, if we need to distinguish
successful RSC slot programming from a failed flush, is a run-scoped return
probe on `rpmh_flush()`. That would report Linux's software flush result only;
it cannot supply the missing firmware acknowledgment. Do not use guessed
MMIO, `/dev/mem`, QMP commands, or infer physical PCI/WCN state from
`PCI_UNKNOWN`.

## Source references

- Linux v7.2.3 [`pci_pm_suspend_late()` and `pci_pm_suspend_noirq()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci-driver.c#L873-L955)
- Linux v7.2.3 [`pm_generic_suspend_late()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/base/power/generic_ops.c#L76-L84)
- Linux v7.2.3 [`__tcs_set_trigger()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L367-L406), [`tcs_tx_done()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L430-L479), [`__tcs_buffer_write()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L482-L522), [`rpmh_rsc_write_ctrl_data()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L727-L755), and [last-CPU sleep/wake flush comments](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L835-L913)

The `ath12k_wifi7_pci` implementation is from the exact local Armada-patched
Linux source tree; its source locations are `drivers/net/wireless/ath/ath12k/pci.c:1753-1835`,
`drivers/net/wireless/ath/ath12k/wifi7/pci.c:210-224`, and
`drivers/net/wireless/ath/ath12k/core.c:100-179` in
`/Volumes/NovaKernelBuild/work/linux-7.2.3`. The local source is the Armada
build input; its exact commit metadata has not yet been established.

## Artifact hashes

| Artifact | SHA-256 |
|---|---|
| `raw/trace/trace.txt` | `e1e569fef90ddf59e24a117a0ad13b99901a383a39c06e9abc01931066aea7ab` |
| `raw/trace/kprobe_profile.txt` | `7712ddb352b109fb9d9beea34fa3349c5198d29235a65609c9e50796cf00dfa3` |
| `derived/summary.json` | `4f965768c91b6957e0966779641ccd2d7f671a0145007427b95f0e41c4b716cc` |
| `result.md` | `d74c285fcb55e08f31f7c6952f2421d8f1e9ce3b345853ad8e8e283ff8807fc8` |
| `derived/rpmh-rsc-snapshots.json` | `dfac698216cae4a78f40cd71411e6af29a946845ec6e491277056435035a1774` |
| `cleanup/trace.json` | `1f86547e51a5126da81a0056e1b113cabaaebe5341200c4e9fcf9045004d873b` |
