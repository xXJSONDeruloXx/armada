# RPMh/AOP sleep-set observability boundary

Date: 2026-09-21

## Result

Linux 7.2.3 has no trustworthy host-visible completion or readback path for
the firmware-triggered RPMh SLEEP/WAKE TCSes used by this suspend path. The
existing trace and `rpmh_flush()` return prove that Linux staged and flushed
the command slots without a software error. They do not prove that AOP/RSC
triggered those slots, that the commands completed, or that the requested
resource states became effective.

The firmware-maintained AOSD/CXSD/DDR counters remain the nearest trustworthy
observable for the target residency. Their zero deltas show that the named
records did not count entry during the observed interval; they do not identify
whether the cause was a missing trigger, firmware policy/acceptance, another
subsystem's aggregate vote, or a state transition not represented by those
records.

## Source-backed layers

1. **Linux stages the request.** `rpmh_write()` caches Sleep/Wake values.
   `rpmh_flush()` invalidates and writes the cached batches/commands into the
   assigned TCS slots, then returns the slot-programming result. The target
   capture recorded six SLEEP and six WAKE `rpmh_send_msg` events and a zero
   return from `rpmh_flush()`.
2. **Firmware owns the trigger.** The RPMh RSC binding explicitly says the
   firmware triggers SLEEP and WAKE TCSes after CPUs power off. The RSC driver
   source says the AP triggers ACTIVE transfers only. `rpmh_rsc_write_ctrl_data()`
   writes the control data but does not trigger it.
3. **There is no Sleep/Wake completion IRQ contract in this driver.**
   `tcs_tx_done()` is documented and configured for ACTIVE_ONLY transfers.
   The SLEEP/WAKE path is fire-and-forget from Linux's perspective. Therefore
   `rpmh_flush()==0` is not an AOP acknowledgment.
4. **Effective firmware state is not read back.** The 7.2.3 source has no
   exposed per-command Sleep/Wake acknowledgment interface. The live Armada
   image has no RPMh/AOP debugfs status interface available to the lab. Do not
   add reads of guessed RSC/AOP registers or memory.

## Newer read support does not close this gap

Newer mainline `rpmh_read()` support uses `RPMH_ACTIVE_ONLY_STATE`, waits for
that active transaction's response, and returns the current resource value.
It is useful for active regulator/ICC readback, but does not retrieve the
cached SLEEP value or reconstruct the value that firmware applied during the
previous low-power interval. Running it after resume would observe the awake
state, not the historical SLEEP transaction. This API is not present in
Armada's Linux 7.2.3 target source.

The newer RSC timeout-diagnostic series reports TCS/CMD status bits and AOSS
response state when a transfer times out. It is timeout debugging, not a
success-path Sleep/Wake acknowledgment or a public readback interface. Even
`triggered/sent/response-received` command bits would describe transaction
progress, not by themselves prove the aggregate rail/memory state or AOSD
residency.

## What would justify deeper instrumentation

The closest source-backed next step would require a documented firmware
interface that can query the Sleep/WAKE transaction or effective resource
state after resume. No such interface is exposed in the target kernel source
or the current lab-visible device interfaces. A future driver diagnostic may
log only status fields that Qualcomm documents for this exact RSC generation
and whose lifetime/clear semantics are established. Until then, keep the
existing TCS submission trace and firmware residency records separate; do not
label submission as application.

## References

- Armada build-input Linux 7.2.3: `drivers/soc/qcom/rpmh.c`, especially
  `__rpmh_write()` and `rpmh_flush()` (source lines 160-190 and 421-480).
- Armada build-input Linux 7.2.3: `drivers/soc/qcom/rpmh-rsc.c`, especially
  `__tcs_set_trigger()`, `tcs_tx_done()`, and `rpmh_rsc_write_ctrl_data()`
  (source lines 367-481 and 727-755).
- Linux v7.2.3 RPMh RSC binding:
  <https://github.com/gregkh/linux/blob/v7.2.3/Documentation/devicetree/bindings/soc/qcom/qcom%2Crpmh-rsc.yaml#L20-L31>
- Linux v7.2.3 RSC source:
  <https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L2807-L2840>
  and <https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L3430-L3465>
- Linux current-master active-only `rpmh_read()`:
  <https://github.com/torvalds/linux/blob/master/drivers/soc/qcom/rpmh.c#L204-L235>
- Public discussion identifying active-only readback and the missing sleep
  bucket:
  <https://patchew.org/linux/20251106-topic-sm8x50-icc-read-rpmh-v1-1-d03a2e5ca5f7%40linaro.org/>
- Qualcomm's 2026 RSC timeout diagnostic series (not a Sleep/Wake success
  acknowledgment):
  <https://patchew.org/linux/20260812-rpmh-timeout-debug-v1-v3-0-68c0a40dce23%40oss.qualcomm.com/>
