# Reusing Android's sleep contract from Armada Linux

Captured 2026-09-20 19:23 UTC. This is a source/runtime compatibility check;
no kernel module was inserted, no sleep request was queued, and no reboot or
suspend was performed.

## Direct answer

The Android sleep behavior can be reused as a **behavioral reference**, but
the Android `.ko` files cannot be used as plug-ins in the running Armada
kernel. A mount only exposes the file. A `.ko` executes inside the kernel that
loads it; it is not a userspace service that can be copied into Linux or
invoked at suspend time.

Android is running kernel
`5.15.123-android13-8-g697b78910a71-dirty`; Armada is running `7.2.3`. The
exact Android `dcvs_fp.ko` has vermagic
`5.15.123-g697b78910a71-dirty SMP preempt mod_unload modversions aarch64`,
depends on `cmd-db,qcom_rpmh`, and imports vendor-only
`rpmh_init_fast_path()` and `rpmh_update_fast_path()`. The running Linux
kernel's symbol table has `rpmh_write_async()` but neither of those fast-path
symbols. Its captured config also does not enable `CONFIG_MODVERSIONS`, unlike
the Android module's build. Forcing vermagic would not supply missing symbols
or make the kernel data structures and callbacks ABI-compatible.

The exact Android `rpmh-regulator.ko` is also a 5.15.123 module. Armada has
`CONFIG_REGULATOR_QCOM_RPMH=y` and the mainline qcom-rpmh-regulator driver
already bound as built-in kernel code. The Android module is not a safe way to
replace it; the missing behavior is a Linux driver feature, not a missing
file. The same direct-load objection applies even more strongly to Android's
downstream PCIe/WCN modules, which would compete with Armada's already bound
Qualcomm PCIe host driver and its Linux device tree.

Exact Android module hashes, bindings, and disassembly are in the
[DCVS-FP binary/DT receipt](../../receipts/2026-09-20-android-dcvs-fp-binary-and-dt.md)
and the [RPMh/ICC module receipt](../../receipts/2026-09-20-android-live-rpmh-module-decomp.md).

## What Linux already has, and what was tested

The live Armada config has `CONFIG_QCOM_RPMH=y`,
`CONFIG_INTERCONNECT_QCOM=y`, `CONFIG_REGULATOR_QCOM_RPMH=y`,
`CONFIG_PCIE_QCOM=y`, and `CONFIG_PCIE_DW=y`. The relevant RPMh, regulator,
interconnect, and PCIe drivers are built into the running kernel. Linux's
`rpmh-rsc` already caches SLEEP/WAKE_ONLY requests and flushes them for suspend
through its own mainline API; the Android BCM voter uses the same core state
pipeline.

We already reproduced the narrow static part of Android `dcvs_fp` in a
7.2.3-native test module: the MC4/SH5 SLEEP and WAKE_ONLY requests appeared in
the Apps-RSC trace, but AOSD/CXSD/scalar-DDR counters remained zero after the
deep run. That exact A/B is recorded in the
[DCVS-pair receipt](receipts/2026-09-20-rpmh-dcvs-pair-ab.md). It means
copying only those two request pairs is insufficient in the tested run; it
does not rule out other Android behavior.

## Portable behavior versus Android-only implementation

The useful unit to port is the **suspend contract and sequencing**, using
Armada's own 7.2.3 drivers and firmware interfaces:

1. Android `dcvs_fp` stages MC4/SH5 requests and also has a vendor fast path.
   The static pair has already failed as a sufficient Linux fix. A complete
   port would need a Linux-supported way to model its active and suspend
   bandwidth requests, not those Android function calls.
2. Android `rpmh-regulator` has separate ACTIVE, SLEEP, and WAKE_ONLY
   aggregates; mainline 7.2.3 `qcom-rpmh-regulator` sends ACTIVE_ONLY requests.
   A Linux implementation could add proper regulator-core suspend-state
   handling, but it must first map shared LDOE consumers and wake requirements.
   Do not load the vendor regulator module or blindly disable rails.
3. Android coordinates WCN/PCIe quiescence and drops its bandwidth request.
   Armada's Qualcomm root port is still D0 in the current awake snapshot, and
   the prior D3cold eligibility check vetoed the Linux host shutdown. The
   production-quality route is a Linux PCIe/WCN PM sequence that actually
   quiesces the hardware and releases its ICC/OPP vote, not a fake PCI state.

Mainline's relevant primitives are the
[`rpmh_write_async()` API](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh.c#L159-L241),
[RPMh-RSC suspend flush](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L883-L945),
and [qcom PCIe suspend path](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/dwc/pcie-qcom.c#L2238-L2360).

## Linux-side checks and limits

- Armada is still on stock Linux 7.2.3. The live suspend modes are
  `[s2idle] deep`; both Qualcomm PCI functions are awake in D0. The
  `sm8550-pcie-test-rollback.timer` is disabled.
- No `rpmh_init_fast_path` or `rpmh_update_fast_path` symbol exists in the
  live Linux symbol table. `rpmh_write_async` is present.
- The saved Linux journal index contains the pre-candidate stock boot and the
  recovered stock boot, with no separate candidate boot ID. The pstore and
  systemd-pstore directories contain no crash record. This cannot locate the
  candidate's stall more precisely than “no retained Linux journal/pstore
  evidence.”
- The candidate `KERNEL` and stock backup have the same Android boot-image
  geometry reported by `file` (kernel address `0x10008000`, ramdisk address
  `0x16000000`, 2048-byte page). Its embedded `ostree=` path uses a different
  identifier from the staged image checksum, but this is not by itself a
  mismatch: on the live stock image, `/ostree/boot.0/default/fe4d.../0` is a
  symlink to deployment `ec096...3`. The candidate link target was removed
  during rollback, so its mapping cannot now be checked. Do not blame the
  candidate boot failure on those different identifiers alone.

The candidate's new OPP setter is reached in the suspend callback; the added
DT OPP is read at PCIe probe. The candidate did not produce a persistent
journal or pstore record, so the actual boot failure stage remains unknown.
The PCIe-MEM A/B has not run. Do not re-stage it while the user is away without
first adding an observation/recovery plan that covers the early boot gap.

## Conclusion

Mounting Android partitions or copying their modules cannot make Android's
sleep contract active under Linux. The reusable part is source-level behavior
implemented against Linux 7.2.3 APIs. The first narrow port (MC4/SH5 static
SLEEP/WAKE requests) is already tested and insufficient alone. The best
remaining production paths are a real PCIe/WCN quiesce-and-vote-release path
or carefully designed RPMh regulator sleep-context support, with the PCIe
path having the stronger direct correlation to the retained MC0/SH0 floor.
