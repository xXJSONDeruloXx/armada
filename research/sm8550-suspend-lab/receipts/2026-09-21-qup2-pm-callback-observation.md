# QUP2 UART PM callback observation

Captured 2026-09-21 on unchanged stock Armada Linux 7.2.3. This was a
15-second direct-deep observation with run-scoped trace events only. No kernel,
vote, radio policy, or boot configuration was changed.

## Result

The filtered trace records successful system-suspend callbacks for the gamepad
GENI UART `89c000.serial` and its `serial1-0` rsinput child. It does **not**
show the UART's QUP2 ICC request being updated before the final Apps-RSC
SLEEP/WAKE submissions:

- UART callback: `9679.281178`, `qcom_geni_serial 89c000.serial [suspend]`,
  returned `err=0`; its bus suspend callback at `9679.351507` also returned
  `err=0`.
- The `serial1-0` rsinput callbacks at `9679.281423` and `9679.323701`
  returned `err=0`.
- The only QUP2-core `icc_set_bw` events before the final SLEEP set are for
  sibling `890000.i2c` (`9679.325149` and `9679.492689`). It writes active
  address `0x5004c`; no suspend-window `icc_set_bw` event names
  `89c000.serial`.
- The final WAKE and SLEEP submissions at `9679.5426` contain no command for
  QUP2 address `0x5004c`.
- The first captured QUP2 ICC update naming `89c000.serial` is after wake, at
  `9693.971511`; it reports the UART's 1/1 request and is followed by an
  active write to `0x5004c`.

This supports the narrow conclusion that the UART ICC request was not removed
before BCM SLEEP/WAKE batching. A successful device-PM callback only proves
that its callback returned success; it does not prove that serial-core changed
the UART PM state or that GENI runtime resource shutdown ran. The trace does
not identify which of those steps was skipped. The awake interconnect summary
records `89c000.serial` with QUP2 tag 7 and a 1/1 request both before and after
the run; it does not expose the request's enabled bit.

## Sleep outcome and recovery

The RTC woke the device after about 16 seconds of BOOTTIME. AOSD, CXSD, and
scalar DDR count/duration deltas were zero; detailed DDR ID `0xd0` advanced
307,070,525 raw ticks. The trace records 337 PSCI domain idle enter/exit events
for state `0x40000004`; it did not record a `psci_system_suspend_enter`
kretprobe. These observations do not prove that RPMh/AOP applied the submitted
SLEEP commands.

The immediate post-run network snapshot showed Wi-Fi `NO-CARRIER`; a direct
read-only check at 05:21 UTC found `wlp1s0` UP with carrier, kernel 7.2.3, and
no reported failed systemd units. No reset or manual recovery was needed.

## Next diagnostic

Before any behavioral A/B, instrument the internal UART PM handoff in a
private trace instance: record `qcom_geni_serial_pm()` old/new states, whether
`qcom_geni_serial_runtime_suspend()` runs and returns, and whether
`geni_serial_resources_off()` / `geni_icc_disable()` are reached. First verify
those symbols are probeable and not blacklisted on this exact running kernel.
This should distinguish a serial-core OFF-state transition issue from runtime
resource shutdown without changing the request.

Relevant source path in Linux v7.2.3:

- [`qcom_geni_serial_suspend()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serial/qcom_geni_serial.c#L1988-L2012)
- [`uart_suspend_port()` / `uart_change_pm()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serial/serial_core.c#L2269-L2369)
- [`qcom_geni_serial_pm()` and runtime suspend](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serial/qcom_geni_serial.c#L1727-L1739)
- [`geni_serial_resources_off()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serial/qcom_geni_serial.c#L1656-L1668)
- [`geni_icc_disable()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom-geni-se.c#L1018-L1033)
- [`icc_disable()` calls `icc_set_bw()`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L767-L797)

## Evidence

- Run: `20260921T051638Z-20b8f71b702c`, label
  `stock-qup2-pm-callback-observation`.
- Summary: `/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T051638Z-20b8f71b702c/result.md`
- Raw trace: `/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T051638Z-20b8f71b702c/device/raw/trace/trace.txt`
- Trace event filters and selected events:
  `/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T051638Z-20b8f71b702c/device/meta/trace.json`

## Follow-up internal PM probes

A second unchanged-stock direct-deep observation added run-scoped probes for
the serial PM callback, GENI runtime suspend, GENI SE resource shutdown, and
GENI ICC disable. The trace now identifies the break:

- At `10882.208776`, inside the `89c000.serial` bus suspend callback, the
  `qcom_geni_serial_pm()` probe records `new_state=3` and `old_state=0`.
  Linux defines these as UART PM OFF and ON, respectively. The serial-core
  state transition therefore did occur.
- The `qcom_geni_serial_runtime_suspend()` return probe had zero hits.
- All six `geni_se_resources_off()` and `geni_icc_disable()` hits were from
  `geni_i2c_runtime_suspend()` callers; none was from the UART path.
- The UART's QUP2 ICC update remains resume-side. The final SLEEP batch again
  contains no command for QUP2 address `0x5004c`.

This proves that serial-core requested ON-to-OFF, but the corresponding UART
runtime-suspend callback did not execute before the firmware SLEEP batch. It
does not yet explain why. Candidates to separate in source and runtime state
are a remaining runtime-PM usage reference, runtime PM being disabled during
system sleep, or a device-specific runtime-PM constraint. The UART PM callback
is `void` and ignores the return from `pm_runtime_put_sync()`, so its successful
system-suspend callback cannot report that distinction.

All four dynamic kprobes and the private trace instance were removed by the
harness. The RTC wake returned on the same boot; a direct SSH check found Wi-Fi
UP with carrier. No vote, radio, kernel, or boot behavior was changed.

Evidence run: `20260921T053640Z-9f9e6fb592c9`, label
`stock-geni-pm-path-observation`. Its summary and raw trace are under
`/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T053640Z-9f9e6fb592c9/`.

## Source audit: system-sleep PM reference

Inspection of the exact Linux v7.2.3 source identifies a concrete reason that
the runtime-suspend callback is absent. `device_prepare()` takes a no-resume
runtime-PM reference on each device to prevent its parent from runtime
suspending during the system transition. That reference is retained until
`device_complete()` after resume. The GENI suspend path calls
`uart_suspend_port()`; serial-core then transitions the UART ON-to-OFF, and
`qcom_geni_serial_pm()` calls only `pm_runtime_put_sync(uport->dev)`. The
callback is void and discards the put result.

For `RPM_GET_PUT`, `__pm_runtime_idle()` drops one usage count. If the count
remains positive, it emits the `rpm_usage` tracepoint and returns 0 before
calling `rpm_idle()`. Therefore a successful qcom GENI system-suspend callback
can leave its hardware resources and ICC request untouched: the system-PM
reference masks the driver's runtime put. This is consistent with the probe
result, but the next trace should capture the actual post-put counter and
confirm the runtime-PM path on the target.

The serial/serdev stack is a separate possible contributor. The tty-backed
serdev controller is registered under the serial port device. Opening its
serdev child calls `pm_runtime_get_sync(&ctrl->dev)`; closing drops that
reference. The controller ignores its own children for runtime PM, but this
does not release the qcom UART's system-PM reference. Capture the named
runtime-PM events for the whole device chain to keep these counts distinct.

The platform's power sysfs directory lacks `runtime_usage` and
`runtime_active_kids`, because its config has
`CONFIG_PM_ADVANCED_DEBUG=n`. Read-only SSH showed the UART, serial-core
controller/port, and serdev controller nodes runtime-active with zero
runtime-suspended time.

Source references for the matched tree:

- [PM core prepare reference](https://github.com/gregkh/linux/blob/v7.2.3/drivers/base/power/main.c#L2188-L2198)
- [PM core completion release](https://github.com/gregkh/linux/blob/v7.2.3/drivers/base/power/main.c#L1295-L1305)
- [runtime idle early return on a remaining reference](https://github.com/gregkh/linux/blob/v7.2.3/drivers/base/power/runtime.c#L1111-L1133)
- [GENI system-suspend handoff](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serial/qcom_geni_serial.c#L1993-L2004)
- [serial-core OFF transition](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serial/serial_core.c#L2296-L2369)
- [GENI runtime put and runtime-suspend callback](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serial/qcom_geni_serial.c#L1727-L1739)
- [serdev runtime reference](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serdev/core.c#L149-L186)
- [tty-backed serdev controller parent](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serdev/serdev-ttyport.c#L275-L296)

No behavior-changing test has been run. The next step is a single unchanged
stock deep-sleep observation with filtered `rpm:rpm_usage`,
`rpm:rpm_idle`, `rpm:rpm_suspend`, `rpm:rpm_resume`,
`rpm:rpm_status`, and `rpm:rpm_return_int` tracepoints. Expected evidence:
the GENI put returns via `rpm_usage` with a positive count, while no
`rpm_idle`/`rpm_suspend` event occurs for the qcom UART before the Apps-RSC
SLEEP batch. All trace state will be run-scoped and cleaned up by the existing
harness.
