# Android DCVS-FP module and live DT attribution

Captured 2026-09-20 over Wireless ADB while the Nova was awake on Android.
The inspection was read-only on the device. It identifies the software
producer of the Android `MC4`/`SH5` RPMh commands; it does not claim those
requests are individually necessary for deep residency.

## Binary provenance

The active slot is `_a`; the running kernel is
`5.15.123-android13-8-g697b78910a71-dirty`. The `dcvs_fp` module is loaded,
bound through the platform driver `qcom-dcvs-fp`, and reports live
`/sys/module/dcvs_fp/scmversion=g697b78910a71-dirty`.

I extracted its 18,904-byte ELF from the active A-slot `vendor_boot` ramdisk.
The CPIO entry payload is at offset `0x50f5f8` and ends at `0x514058`, within
the retained archive. The module SHA-256 is
`0c28f99c4695fe674bc1a20fd3b76d396bfebe144c68900554ffb73299add0d0`; ELF
Build ID is `a9325dd906341d7441ada68225f516c1ecacdc37`; `.modinfo` vermagic is
`5.15.123-g697b78910a71-dirty SMP preempt mod_unload modversions aarch64`.
The extracted binary is retained outside Git at
`/Volumes/NovaKernelBuild/android-binaries/vendor_boot_modules/modules/dcvs_fp.ko`.

The nearest public source checkout is still a single grafted commit
`93c5cc6ad1d0b807510cfa0fb1d06f47407881f9` (`lineage-23.2`); it does not
contain the installed `g697b78910a71` commit. The claims below therefore use
the exact loaded module binary and runtime device tree, not a claim that the
nearby source is the exact vendor source.

## Live device-tree binding

The live platform device resolves to:

```text
/sys/firmware/devicetree/base/soc/apps_rsc@17a00000/drv@2/qcom,dcvs-fp
compatible            qcom,dcvs-fp
qcom,ddr-bcm-name      MC4\0
qcom,llcc-bcm-name     SH5\0
```

These are the same names as the earlier live CMD-DB entries:

```text
MC4 -> RPMh command address 0x50060
SH5 -> RPMh command address 0x50064
```

The driver is bound to this OF node in sysfs, so these are active runtime
properties, not an unselected DTBO fragment.

## Disassembly evidence

The exact AArch64 ELF retains local symbols and relocation records. Key
functions and offsets:

- `qcom_dcvs_fp_probe()` at `.text+0x2bc` calls `populate_bcm_data()` twice,
  once for each BCM-name property.
- `populate_bcm_data()` at `.text+0x47c` calls
  `of_property_read_string()` (`.text+0x4c0`), then `cmd_db_read_addr()`
  (`.text+0x4cc`) and `cmd_db_read_aux_data()` (`.text+0x4e4`). It validates
  the 8-byte auxiliary record before copying the returned address and
  converted BCM data into the fast-path structure.
- Probe initializes the fast path at `.text+0x36c`, then submits two
  commands using `rpmh_write_async()` with state argument `0` at
  `.text+0x384` (`RPMH_SLEEP_STATE`) and state argument `1` at
  `.text+0x3ac` (`RPMH_WAKE_ONLY_STATE`). The command count passed is two.
- `ddrllcc_fp_commit()` at `.text+0x1dc` recalculates the BCM payloads and
  calls `rpmh_update_fast_path()` with state argument `2` at `.text+0x258`
  (`RPMH_ACTIVE_ONLY_STATE`).

The property strings are at `.rodata+0x60` (`qcom,llcc-bcm-name`) and
`.rodata+0xc9` (`qcom,ddr-bcm-name`). The module's strings identify itself as
`QCOM DCVS FP Driver` and depend on `cmd-db,qcom_rpmh`.

Together, the live node, CMD-DB map, and exact probe call sequence identify
`dcvs_fp` as the software producer of Android's MC4/SH5 SLEEP and WAKE_ONLY
requests. A separate successful Android capture already observed those
addresses in the final staged TCS and advancing AOSD/CXSD/DDR records. This
does not prove the firmware accepted those requests or that they are the
causal difference from Armada. The most recent Android retry did not enter
deep and its trace had no MC4/SH5 writes; that aborted trace is not contrary
evidence because probe-time staging occurred before trace enable and the
attempt never completed the low-power path.
