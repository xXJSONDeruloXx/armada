# QUP2 suspend trace correction and next observation

Captured 2026-09-21. This is a source/receipt review plus read-only checks of
the current stock boot. No suspend run, kernel change, vote change, or device
configuration change was made in this update.

## Correction to the 04:42 notebook interpretation

The phase-03 trace uses the `boot` trace clock. The final Apps-RSC WAKE and
SLEEP submissions occur at 289.167 seconds. The first clear post-resume PMU
activity is at 303.483 seconds. Therefore the QUP2 `icc_set_bw` event for
`89c000.serial` at 304.104 seconds is a resume-side event, not a suspend-side
vote update. The associated active TCS write to address `0x5004c` is also
post-resume. It cannot show whether the UART dropped its SLEEP vote.

At 289.129 seconds, the trace instead shows `systemd-sleep` updating the
QUP2-core path for `890000.i2c`, followed by an active write to
`0x5004c`. The final SLEEP and WAKE batches contain no command to `0x5004c`.
The awake pre- and post-snapshots both show `89c000.serial` as the only
persistent nonzero QUP2 core client (tag 7, 1/1); `890000.i2c` is 0/0 in those
snapshots. The trace does not record the ICC request `enabled` bit, so the
289.129 event alone cannot attribute the aggregate to one client. It does
show that the sibling I2C update leaves aggregate QUP2 bandwidth at 1.

Linux's QUP2 BCM has `keepalive=true`. The BCM voter sets AMC and WAKE minimums
to 1 when the active vote is empty, but does not set the SLEEP bucket. The
voter only emits WAKE/SLEEP commands when those bucket values differ. Thus, if
the gamepad UART's tag-7 1/1 request remains enabled, WAKE and SLEEP both
contain 1 and the voter omits QUP2. If its ICC path is disabled, the expected
keepalive result is WAKE=1 and SLEEP=0, which should create a distinct QUP2
request. This is the Linux-side contract to verify; omitted TCS data does not
prove what AOP ultimately applied.

## Source path and remaining uncertainty

The matching Linux 7.2.3 source used for the phase-03 module build has this
path:

1. Non-console `qcom_geni_serial_suspend()` calls
   `uart_suspend_port()` but does not retag its ICC requests. Only the console
   path is changed to `QCOM_ICC_TAG_ACTIVE_ONLY`.
2. `uart_suspend_port()` ends by changing the UART PM state to OFF. The serial
   core invokes the driver's PM callback only when that state changes.
3. `qcom_geni_serial_pm()` calls `pm_runtime_put_sync()` only for ON→OFF.
4. The runtime-suspend path calls `geni_serial_resources_off()`, which calls
   `geni_icc_disable()` after the GENI resources turn off successfully.
5. ICC aggregation excludes disabled requests. The BCM keepalive then leaves
   WAKE at 1 and SLEEP at 0, so a QUP2 sleep command should be generated.

Source references: [GENI UART resource shutdown](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serial/qcom_geni_serial.c#L1656-L1668), [GENI PM transition](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serial/qcom_geni_serial.c#L1727-L1739), [GENI suspend callback](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serial/qcom_geni_serial.c#L1993-L2004), [serial-core PM transition](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serial/serial_core.c#L2269-L2278), [serial-core suspend path](https://github.com/gregkh/linux/blob/v7.2.3/drivers/tty/serial/serial_core.c#L2296-L2369), [ICC disable aggregation](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L271-L296), [ICC enable/disable](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L767-L798), [SM8550 QUP2 keepalive](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/sm8550.c#L1407-L1413), and [BCM sleep/wake generation](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/bcm-voter.c#L91-L125).

The saved phase-03 trace did not enable `power:device_pm_callback_start/end`
for the UART or serdev child. It therefore cannot tell whether the GENI
system-suspend callback ran, whether serial-core PM state was already OFF,
whether the wakeup early return applied, or whether runtime resource shutdown
failed before `geni_icc_disable()`. No causal conclusion about residency is
supported yet.

## Current live device check

Read-only SSH reports stock Linux 7.2.3, boot ID
`3656b0e7-5671-4b7e-9368-67965daa251a`, `[s2idle] deep`, and systemd `running`.
While awake, platform device `89c000.serial` is `power/control=auto` and
`runtime_status=active`; `runtime_suspended_time=0`. These runtime-PM counters
do not reveal its system-suspend state. No root-only tracefs read or device
mutation was made.

## Next diagnostic

The existing `rpmh-aoss` trace profile now also selects filtered device-PM
callback start/end events for `89c000.serial`, its `serial1-0` serdev child,
and sibling `890000.i2c`. An unchanged-stock 15-second direct-deep observation
can correlate those callbacks with existing ICC and RPMh events without
changing a vote or driver behavior. If the GENI callback succeeds but no
QUP2 ICC disable occurs, the next source-level probe should distinguish the
serial PM-state transition from runtime-resource shutdown, rather than trying
another residency A/B.

## Evidence locations

- Raw phase-03 trace:
  `/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T023438Z-9d42e275c2f9/device/raw/trace/trace.txt`
- Phase-03 interconnect snapshots:
  `.../device/{pre,post}/files/sys/kernel/debug/interconnect/interconnect_summary`
- Relevant trace events: 289.129 (I2C path/active QUP2 write), 289.167
  (final WAKE/SLEEP batches), 303.483 (post-resume activity), and 304.104
  (UART ICC restore/active QUP2 write).
- Candidate source tree: `/Volumes/NovaKernelBuild/work/linux-7.2.3`.
