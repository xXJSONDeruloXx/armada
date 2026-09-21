# QUP2 GENI runtime-PM usage trace confirmation

Captured 2026-09-21 on unchanged stock Armada Linux 7.2.3. The run used only
the existing filtered runtime-PM tracepoints and run-scoped probes. No kernel,
ICC request, suspend policy, boot artifact, or device setting changed.

## Direct observation

At trace time `12042.760006`, `qcom_geni_serial_pm()` records the gamepad UART
`89c000.serial` transitioning `new_state=3 old_state=0` (ON to OFF). One
microsecond later, `rpm_usage` reports:

```text
rpm_usage: 89c000.serial flags-4 cnt-1 dep-0 auto-1 p-0 irq-0 child-1
```

The GENI system-suspend callback then returns `err=0`. No `rpm_idle` or
`rpm_suspend` event for this UART occurs before the final Apps-RSC SLEEP/WAKE
submission. The separate runtime-suspend probe has zero UART hits; therefore
its `geni_serial_resources_off()` / `geni_icc_disable()` path did not run and
the QUP2 request stayed enabled. On resume, the same UART receives an ICC
update restoring 1/1.

This confirms the runtime-PM accounting mechanism seen in source: the PM core
holds a runtime-PM reference across the system transition, and the UART's
ordinary `pm_runtime_put_sync()` cannot idle the device while the usage count
is still positive. The active child (`child-1`) is also visible, so the
forced-suspend path must be reviewed against the complete serdev lifecycle;
the event alone does not establish QUP2 as an AOSD/CXSD/DDR gate.

## Existing upstream implementation

Linux upstream added the matching GENI system-sleep force-suspend/resume path
in commit `d0cd9c8d0fd5`:

- Suspend first calls `uart_suspend_port()`, propagates errors, preserves an
  active console when `no_console_suspend` is set, then calls
  `pm_runtime_force_suspend(dev)`.
- Resume calls `pm_runtime_force_resume(dev)` before `uart_resume_port()`.

The current master source contains this implementation. The v7.2.3 Armada
source does not. The upstream change is directly applicable to the observed
non-console gamepad UART and uses the driver's existing runtime-suspend
callback, which is responsible for power/resource shutdown and ICC removal.
Do not backport just the two calls without the console matching logic: the
upstream review identified an unbalanced force-resume when a console was
intentionally left active. For the Nova's non-console UART that branch should
not be taken, but the driver is shared by console instances.

This is a plausible small Linux-side correction for the missing QUP2 sleep
request. It is not evidence that QUP2 alone is the missing firmware contract,
and it is not authorization to run another behavioral A/B before the other
request-source and WCN/PCIe questions are narrowed.

Sources:

- Exact runtime trace and before/after state: run
  `20260921T055601Z-62202a34c194`, raw trace
  `/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T055601Z-62202a34c194/device/raw/trace/trace.txt`.
- Matched Linux v7.2.3 PM-core and GENI sources are linked in the preceding
  `lab-notebook.md` entries.
- [Upstream GENI driver](https://github.com/torvalds/linux/blob/master/drivers/tty/serial/qcom_geni_serial.c#L1928-L1971)
  and [upstream patch discussion](https://lists.openwall.net/linux-kernel/2026/07/02/1310).
- [Upstream follow-up for no_console_suspend force-resume balancing](https://lists.openwall.net/linux-kernel/2026/08/28/1355).

## Run outcome and recovery

The RTC woke the Nova on the same boot. AOSD/CXSD/scalar DDR deltas were
zero; detailed DDR row `0xd0` advanced but remains undecoded. Wi-Fi returned
with carrier, the Steam session remained available, and the private trace
instance and dynamic probes were removed successfully. Full run summary and
raw data are under
`/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T055601Z-62202a34c194/`.
