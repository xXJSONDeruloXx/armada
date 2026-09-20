# MC4/SH5 module build and ABI preflight

Date: 2026-09-20 13:01 UTC
Branch: `feat/sm8550-suspend-lab`
Purpose: prepare a single-variable, transient Linux A/B that stages Android's
MC4/SH5 sleep/wake request pair. No device module has been loaded yet.

## Probe behavior

`research/sm8550-suspend-lab/probes/rpmh-dcvs-pair/armada_rpmh_dcvs_pair.c`
finds the pre-verified Nova platform device `17a00000.rsc:regulators-0` on the
platform bus. That device is the bound `qcom-rpmh-regulator` child directly
under Apps RSC (`qcom,drv-id=2`).
The module resolves `MC4` and `SH5` through CMD-DB, then queues only:

- `RPMH_SLEEP_STATE`: `BCM_TCS_CMD(1, 1, 0, 0)` for both resources.
- `RPMH_WAKE_ONLY_STATE`: `BCM_TCS_CMD(1, 1, 0, 1)` for both resources.

This mirrors the exact Android `dcvs_fp` pair. `rpmh_write_async()` caches the
sleep/wake pair for RSC to flush during suspend; module unload does not clear
that controller cache. Rebooting the unchanged deployment clears it. The probe
does not write ACTIVE requests, alter the PCIe/WCN vote, change PCI state, or
touch regulators.

## Build result

Built out of tree in an ARM64 Fedora 44 container against
`/Volumes/NovaKernelBuild/work/linux-7.2.3`:

```sh
make ARCH=arm64 modules_prepare
make ARCH=arm64 M=/probe \
  KBUILD_EXTRA_SYMBOLS=/kernel/vmlinux.symvers modules
```

The first attempt lacked generated `scripts/module.lds`; `modules_prepare`
generated it after installing the missing container tools (`cmp`, `bc`, GCC,
Make, kmod, and libelf headers). No full kernel image build was run.

The resulting `/probe/armada_rpmh_dcvs_pair.ko` is an AArch64 ELF. Its
`modinfo` vermagic is:

```text
7.2.3 SMP preempt mod_unload aarch64
```

This exactly matches `uname -r` and the vermagic of a shipped Nova module. The
module SHA-256 is
`ec0194e7ae8a6dc91c74449718948c941095c3f55c0ff90c55a03aa02e11e330`; the C
source SHA-256 is
`49f4c0226820be76c21e23782396ff88fa35428d7f996272f2cdae9e3683a206`.

The kernel tree lacks top-level `Module.symvers`, so the first modpost pass
warned about every import. The tree does contain `vmlinux.symvers`; passing it
with `KBUILD_EXTRA_SYMBOLS` removed the unresolved-symbol warnings and linked
the module. Its imports are `_printk`, `_dev_err`, `_dev_info`,
`__stack_chk_fail`, `platform_bus_type`, `bus_find_device`,
`device_match_name`, `put_device`, `cmd_db_read_addr`, and
`rpmh_write_async`. The local `vmlinux.symvers` marks each as exported, and
live `/proc/kallsyms` contains every name. Live `CONFIG_MODVERSIONS` is unset,
so no symbol CRC comparison is available.

## Live type and configuration checks

On the running Nova, `/proc/config.gz` initially matched the local `.config`
byte-for-byte, SHA-256
`2219546e268f72bb2bcbac96943202e9e50731b6e531e3193cc73b1976d2fbef`.
However, the local source Kconfig does not recognize several options present in
the live config. `make modules_prepare` normalized those entries and disabled
local BTF/scheduler/tracing options. The module-related settings remain equal:
ARM64, SMP, PREEMPT, module loading/unloading, stack protector, CMD-DB, and
RPMh. The local source's exact relationship to the running image's 144-patch
stack is not proven by the shared release string.

To narrow that gap, the device's actual `/sys/kernel/btf/vmlinux` was copied
read-only. Live BTF shows `struct tcs_cmd` as `{ u32 addr; u32 data; u32 wait; }`
with offsets 0, 4, 8 and size 12, matching the module's header. It also reports
`RPMH_SLEEP_STATE=0`, `RPMH_WAKE_ONLY_STATE=1`, and
`RPMH_ACTIVE_ONLY_STATE=2`, matching the queued state choices. The APIs and
their expected prototypes are present in the running kernel symbol set.

The exact live config and BTF copies are in
`/Volumes/NovaKernelBuild/armada-rpmh-dcvs-pair/` outside Git. The local Kbuild
tree now has a normalized `.config`; its full config must not be described as
an exact match for the device. The kernel source and device have not been
changed.

## Device baseline and next gate

The device is awake on Armada `20260915.feca679`, kernel `7.2.3`, boot ID
`09a76af5-4e8f-454a-858e-dedb4ebb1d4d`. Wi-Fi/SSH are healthy, suspend success
and failure counts are both zero on this boot, and APSS/AOSD/CXSD/scalar DDR
are `1/0/0/0`. Current and rollback bootc deployments share the same image
digest; no deployment is staged. No module, overlay, request, or suspend
setting has been applied.

Next, copy the module to `/tmp`, load it once, and require the success log
showing both CMD-DB addresses and both contexts. If insertion, lookup, or either
RPMh request fails, do not suspend. If SLEEP succeeds but WAKE_ONLY fails,
reboot before another test. If both succeed, run the existing harness in direct
`deep` mode for its 10-second minimum, preserving Wi-Fi and using the
`rpmh-aoss` trace profile. This Nova kernel exposes `rpmh_send_msg`,
`rpmh_tx_done`, and both `qcom_aoss` events, but not `rpmh_rsc_snapshot`; the
selected profile therefore captures per-command RPMh payloads without a
separate RSC snapshot. Record PCIe host/request state, PSCI result,
AOSD/CXSD/DDR and detailed DDR deltas, and resume health. Reboot the unchanged
deployment after the A/B to clear the cached pair.
