# Manual reconstruction of the installed Android PCIe/WCN suspend path

Captured 2026-09-20 from the A-slot Android modules extracted read-only while
the Nova was running Armada Linux. Module hashes, build IDs, partition
provenance, and Android fingerprint are in
[`2026-09-20-android-exact-pcie-modules.txt`](2026-09-20-android-exact-pcie-modules.txt).
The binaries carry the recorded Android kernel vermagic
`5.15.123-android13-8-g697b78910a71-dirty`.

This is a manual control-flow reconstruction from AArch64 disassembly and ELF
relocations, not recovered source. The text addresses below are `.text`
offsets in those exact `.ko` files. Reproduction used Xcode's
`llvm-nm -S -n` and `llvm-objdump -dr --start-address=... --stop-address=...`.
Static code proves what the installed binary can do; it does not identify the
branch taken during the saved Android suspend.

## CNSS2 and WLAN control flow

| Installed module symbol | `.text` offset | Recovered behavior |
|---|---:|---|
| `wlan_hdd_pld_suspend` (`qca_cld3_kiwi_v2.ko`) | `0x437f8` | validates context, starts the synchronized operation, calls `wlan_hdd_bus_suspend` at `0x43894`, and returns its result |
| `wlan_hdd_bus_suspend` (`qca_cld3_kiwi_v2.ko`) | `0x4136c` | requests WLAN firmware bus suspend through the registered callback; the saved `kiwi_v2` success log is emitted by this path |
| `cnss_pci_suspend` (`cnss2.ko`) | `0x21648` | checks DRV support/connection, dispatches the upper WLAN suspend callback, then serializes and calls `cnss_pci_suspend_bus` |
| `cnss_pci_suspend_bus` (`cnss2.ko`) | `0x14b70` | requests firmware bus suspend, conditionally quiesces the PCI function, then calls `cnss_set_pci_link(..., false)` |
| `cnss_set_pci_link` (`cnss2.ko`) | `0x38270` | maps link-up/down and DRV/switch state to host `msm_pcie_pm_control` modes |
| `cnss_pci_update_drv_supported` (`cnss2.ko`) | `0x37870` | checks the PCIe node for `qcom,drv-supported`, falling back to `qcom,drv-name`, and records the result in CNSS private state |
| `cnss_pci_of_switch_type_init` (`cnss2.ko`) | `0x1fcfc` | reads `qcom,pcie-switch-type` into private offset `+0x1f08`; on property-read failure explicitly stores zero |

All inspected Android base DTs and DTBO structures lack
`qcom,pcie-switch-type`, so that field defaults to zero for those inputs. The
extracted base-DT variants put `qcom,drv-name = "lpass"` on pcie0, but the
exact merged runtime DT and CNSS-to-controller association during the saved
run are not captured.

The critical guard recovered from `cnss_pci_suspend()` is:

```c
if (drv_supported && !disable_drv_quirk) {
        drv_connected_last = atomic_read(&drv_connected);
        if (!drv_connected_last)
                return -EAGAIN;
}

ret = upper_wlan_suspend_callback(...);
if (!ret)
        ret = cnss_pci_suspend_bus(data);
```

The field names are matched to nearby public CNSS source; exact binary
evidence is the guard at `0x2167c–0x2169c`, atomic read at private offset
`+0xe4`, and saved-state byte at `+0xe8`. The module contains the diagnostic
string `Firmware does not support non-DRV suspend, reject`. Thus, if the
effective pcie0 node enabled DRV support and the disable-DRV quirk was clear,
a successful CNSS suspend requires the connected flag to be true.

`cnss_pci_suspend_bus()` then behaves differently based on that saved flag.
When the byte at `data + 0xe8` is zero, it clears bus mastering,
conditionally saves PCI state, disables the function, and calls
`pci_set_power_state(pdev, 3)` (D3hot) before link-down. When it is nonzero,
the branch at `0x14ba4–0x14ba8`
jumps past those PCI calls directly to `cnss_set_pci_link()`. The earlier
summary that Android always requests endpoint D3hot was wrong: the successful
DRV-connected path skips the explicit D3hot request.

For link-down, `cnss_set_pci_link()` selects the host mode as follows (mode
numbers are the actual first argument passed to the exact host module):

```c
if (link_up)
        msm_pcie_pm_control(2, ...);       /* resume */
else if (drv_connected_last || pcie_switch_type == 1)
        msm_pcie_pm_control(0, ...);       /* DRV suspend */
else
        msm_pcie_pm_control(1, ...);       /* normal PCIe suspend */
```

The branch and calls are at `0x3847c–0x385e0`; `qcom,pcie-switch-type` is
loaded from private offset `+0x1f08` at `0x38544`. Because inspected DT
inputs default it to zero, the disconnected case selects normal mode 1.
However, if DRV support is enabled and the disable-DRV quirk is clear,
`cnss_pci_suspend()` rejects that disconnected case before it gets here.

The saved Android kernel log proves the WLAN bus-suspend operation logged
success; it does not say whether `drv_connected_last` was set, whether CNSS's
function returned success, or which PCIe host mode completed. Searches of
preserved receipts did not find the module's `Use PCIe DRV suspend` marker or
a branch-specific host log.

## Exact host module routes and ICC removal

`pci-msm-drv.ko` contains three independent request-clear routes:

1. `msm_pcie_drv_suspend()` at `.text+0x34d0` sends its DRV RPMsg, marks host
   state, disables eligible clocks, then calls `qcom_pcie_icc_bw_update`
   as `(pcie, 0, 0)` at `0x3680–0x368c`.
2. Normal `msm_pcie_pm_suspend()` at `.text+0x3778` reaches
   `msm_pcie_clk_deinit()` at `0x7c24`; after clock teardown,
   `msm_pcie_clk_deinit()` calls the same helper as `(pcie, 0, 0)` at
   `0x7ccc–0x7cd8`.
3. `msm_pcie_pm_suspend_noirq()` at `.text+0x13c44`, when its host-state and
   APSS/L1SS gates pass and the PARF status poll succeeds, calls the helper
   as `(pcie, 0, 0)` at `0x13ecc–0x13ed8` before regulator/analog-rail
   teardown.

The helper at `.text+0x1684` maps selector 0 to average=0 and peak=0, then
calls `icc_set_bw()`. Therefore any of these host routes can explain removal
of the PCIe request before Android's final SLEEP TCS is assembled. The final
zero words cannot distinguish which route ran.

The APSS/L1SS noirq path parses `qcom,apss-based-l1ss-sleep` in the platform
probe and requires additional host-state gates plus PARF bit 8. The inspected
DTBO candidate with that property points to `pcie1`; public RP6 DTS disables
pcie1 and places WCN below pcie0. Exact Android overlay selection is unknown.
The root PCI `SUSPEND_LATE` fixup is also present in the installed host
module: its CFI body is at `0xddb8` (thunk `0x1b4d0`), and its eligible path
calls `msm_pcie_pm_suspend()`, which reaches the same clock-deinit ICC clear.

The public nearby source gives names and high-level context for these binary
paths, but does not match the exact installed build:
[PCIe suspend and PM-control code](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L9877-L10073),
[root-device suspend fixup](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L9524-L9558),
[clock teardown and ICC clear](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L4031-L4054).

## What this changes

- Android's PCIe request disappearing is now explained by exact installed
  code routes, but the final TCS does not identify which route ran.
- A D3hot transition is not required by every successful CNSS path. If DRV
  was connected, CNSS skips `pci_disable_device()` and
  `pci_set_power_state(..., 3)` and instead asks the host for DRV suspend.
- If the effective pcie0 DT enabled DRV support and the disable-DRV quirk was
  clear, the guard makes a connected-DRV path the likely successful route;
  that remains an inference until the runtime flag or branch log is captured.
- No AOP residency consequence follows from ICC clearing alone. Neither a
  PCI state request nor a host-control call proves final hardware state or
  Wi-Fi wake behavior.

## Next evidence needed

For the next Android comparison, preserve a kernel-log window covering one
successful suspend and collect the CNSS DRV-connected status/branch marker,
`msm_pcie_pm_control()` mode, root-fixup marker, and APSS/L1SS property state.
The highest-value fact is whether the run reaches mode 0 with
`drv_connected_last=1`; that would establish the branch which clears ICC
without an explicit endpoint D3hot request. Do not infer this from TCS values.

No module was replaced or reloaded. No Android partition, PCI configuration,
device power policy, ICC request, regulator state, or sleep state was changed
during this static analysis.

## Follow-up: live BTF branch mapping

Wireless ADB later confirmed the pulled PCIe module is byte-identical to the
installed module and exposed its split-BTF. The exact `link_status` and
`apss_based_l1ss_sleep` field offsets now map the mode-0 trace to the
root-fixup and noirq branch gates. This resolves that the active pcie0
APSS/L1SS noirq body was skipped, while the root-fixup teardown gate requires
`link_status=ENABLED` and the connected-DRV route sets `DRV`. The callback
entry itself, physical PCI state during sleep, and PCIe/WCN wake behavior
remain unobserved. Details and exact BTF hashes are in
[`2026-09-20-android-live-pcie-validation.md`](2026-09-20-android-live-pcie-validation.md).
