# Proposed Armada A/B: stage Android's DCVS-FP sleep/wake pair

Status as of 2026-09-20 13:01 UTC: the test-only module is built but has not
been loaded. No module, DT, or behavior has been applied to the Nova. Captured
after inspecting the exact Android `dcvs_fp` module and after the read-only
Linux baseline and module ABI preflight.

## What is established

The active Android `dcvs_fp.ko` (`5.15.123-g697b78910a71-dirty`) is bound to
`/soc/apps_rsc@17a00000/drv@2/qcom,dcvs-fp`. Its live DT names `MC4` as the
DDR BCM and `SH5` as the LLCC BCM. CMD-DB maps these to `0x50060` and
`0x50064`.

The exact module's probe reads those names through CMD-DB, then queues
`BCM_TCS_CMD(1, 1, 0, 0)` in `RPMH_SLEEP_STATE` and
`BCM_TCS_CMD(1, 1, 0, 1)` in `RPMH_WAKE_ONLY_STATE`, for both addresses. These
evaluate to `0x60000000` and `0x60000001`. The successful Android Apps-RSC
trace contains the same addresses and data. The matching public source is
[`dcvs_fp.c` at `93c5cc6`](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/soc/qcom/dcvs/dcvs_fp.c#L57-L243);
the exact installed source revision remains unidentified. Exact binary hash,
live DT bytes, and ELF offsets are in
[`android-dcvs-fp-binary-and-dt.md`](2026-09-20-android-dcvs-fp-binary-and-dt.md).

Mainline v7.2.3 has no `dcvs_fp` driver or the vendor-only
`rpmh_init_fast_path()` / `rpmh_update_fast_path()` APIs. It does provide
`cmd_db_read_addr()` and GPL-exported `rpmh_write_async()`. For SLEEP and
WAKE_ONLY states, `rpmh_write_async()` caches the request in the controller;
the `rpmh-rsc` driver flushes the cached pair into TCS before low-power entry.
Its `devm_of_platform_populate()` creates child devices under a driver node,
so a test-only consumer placed below Apps-RSC `drv@2` gets the correct RPMh
controller through its parent. Sources: [RPMh async writer](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh.c#L159-L241),
[RSC suspend flush](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L883-L945),
[child-device population](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L1118-L1127),
[BCM command encoding](https://github.com/gregkh/linux/blob/v7.2.3/include/soc/qcom/tcs.h#L66-L75).

## One-variable A/B

**A:** current Armada Linux image and DT.

**B:** load the temporary test-only module from
`research/sm8550-suspend-lab/probes/rpmh-dcvs-pair/` on the live Nova. It finds
the existing, already-bound `17a00000.rsc:regulators-0` RPMh client by its
verified platform device name, resolves both addresses with CMD-DB, and queues
only these requests:

| Resource | SLEEP | WAKE_ONLY |
|---|---:|---:|
| MC4 (`0x50060`) | `0x60000000` | `0x60000001` |
| SH5 (`0x50064`) | `0x60000000` | `0x60000001` |

This reproduces the Android baseline SLEEP/WAKE pair. It deliberately omits
Android's active DCVS fast path and does not change the PCIe OPP, PCI state,
active bandwidth, regulators, or LDOE rails. It is a better first test than
the prepared 500,000→1 kB/s PCIe OPP change because the root port may remain
active when the D3cold check is vetoed; lowering that OPP could also constrain
live WCN traffic. The pair A/B directly tests one missing firmware-facing
request group while leaving the known MC0/SH0 floor as-is.

The probe is 58 C lines plus a one-line Makefile. It needs no overlay, image
rebuild, active fast path, or DT change. This is a disposable diagnostic, not a
production DCVS-FP port. A full port would also need the vendor active fast-path
and DCVS integration, which mainline does not provide.

## Test observations

Capture A and B with the same controlled direct-deep procedure, no battery
drain interval. Before and after the B attempt record:

1. Whether the PCIe host suspended; preserve the current D3cold eligibility
   result and do not force a PCI D-state.
2. PCIe ICC/OPP request before entry; it should be unchanged by this test.
3. MC0/SH0 SLEEP words; they should remain at the current Linux values.
4. Full Apps-RSC SLEEP/WAKE TCS words; B must add MC4/SH5 with the exact
   Android values above.
5. LDOE1/LDOE3 command presence; these should stay unchanged.
6. PSCI SYSTEM_SUSPEND result and suspend/resume timestamps.
7. AOSD/CXSD/scalar DDR counter deltas.
8. Detailed DDR LPM ID counter deltas.
9. Resume health, WLAN state, and SSH/Wi-Fi recovery.

**Positive result:** the pair is present in both TCS sets and AOSD/CXSD/DDR
residency advances while the PCIe state, OPP, LDOE commands, and MC0/SH0
request remain unchanged. This would strongly support the pair as a missing
sleep handshake, not prove it is the only missing difference.

**Negative result:** the pair is present, deep suspend/resume succeeds, but
the target counters remain zero. That makes the pair insufficient by itself;
the PCIe SLEEP floor remains the next bounded hypothesis. If the pair is not
present in TCS, the test did not exercise the intended variable and gives no
causal result. Any PCIe/WLAN resume regression ends the experiment and triggers
rollback.

## Build and rollback gate

The module now builds as an AArch64 ELF against the local 7.2.3 Kbuild tree;
its vermagic exactly matches the Nova and a shipped module. The local tree has
no top-level `Module.symvers`, but its `vmlinux.symvers` lists every imported
symbol as exported. All import names are present in live `/proc/kallsyms`, and
the live BTF confirms the `tcs_cmd` field offsets/size and RPMh state enum
values. Live `CONFIG_MODVERSIONS` is disabled, so no symbol-CRC comparison is
available. The exact build, ABI evidence, and caveat are recorded in the
[module receipt](2026-09-20-rpmh-dcvs-pair-module-build.md).

One caveat remains: `make modules_prepare` normalized options not recognized
by the local Kconfig. Required module, RPMh, CMD-DB, architecture, SMP,
PREEMPT, stack-protector, and module-unload settings match, but the complete
source/config identity does not. The module has not yet been inserted, so
runtime symbol resolution and the device log remain the final pre-suspend gate.

The RPMh SLEEP/WAKE cache is owned by the RSC controller, not the temporary
module. Unloading it does not clear the cached requests. If both requests queue,
rollback is to reboot into the unchanged bootc deployment; the active and
rollback deployments were verified to use the same image digest. Do not suspend
if device lookup, CMD-DB, SLEEP, or WAKE_ONLY fails. If SLEEP queues but
WAKE_ONLY fails, reboot before further testing.
