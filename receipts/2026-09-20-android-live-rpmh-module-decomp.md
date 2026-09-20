# Android live RPMh and ICC module analysis

Captured 2026-09-20 over Wireless ADB while the Nova was awake on Android.
This was a read-only inspection; no suspend, module operation, setting change,
or device write was performed.

## Exact image and module provenance

The active slot is `_a`. I read `/dev/block/by-name/vendor_boot_a` to the
external scratch volume; the image is 100,663,296 bytes with SHA-256
`89a73c967f6305932fac5e397628e07b4c81c24bf08723f72538c48be054eec4`. Its
vendor-boot v4 header has a 4096-byte page size and one vendor ramdisk of
9,698,659 bytes. The ramdisk is LZ4-compressed newc CPIO. I unpacked it with
the [AOSP `unpack_bootimg.py`](https://android.googlesource.com/platform/system/tools/mkbootimg/+/refs/heads/main/unpack_bootimg.py),
following the [AOSP vendor-boot v4 layout](https://android.googlesource.com/platform/system/tools/mkbootimg/+/refs/heads/main/include/bootimg/bootimg.h).

The mounted `vendor_dlkm`/`system_dlkm` module directories do not contain the
loaded RPMh regulator, ICC RPMh, BCM voter, or Kalama/Crow NoC binaries. Those
modules are in the active vendor-boot ramdisk. Their `.modinfo` `vermagic`
matches the running kernel,
`5.15.123-g697b78910a71-dirty SMP preempt mod_unload modversions aarch64`;
the live `/sys/module/*/scmversion` for `rpmh_regulator`, `icc_rpmh`,
`icc_bcm_voter`, `qnoc_kalama`, and `qnoc_crow` is
`g697b78910a71-dirty`.

Extracted module files and the image remain outside Git at
`/Volumes/NovaKernelBuild/android-binaries/`. SHA-256 and byte sizes:

| Module | Bytes | SHA-256 |
|---|---:|---|
| `icc-rpmh.ko` | 32,544 | `b09a7bec2e27f6120068180395d9e70f6f1d5fb74f3304ca60980afee0043e5d` |
| `icc-bcm-voter.ko` | 35,784 | `a1d70d3c34b372bed3080cc890aa5fc0ce7833da1a52f89b0dd396e044369b66` |
| `qnoc-kalama.ko` | 304,544 | `b82252eb30ab27ef1edca090e9eaed5a4e60158c6c376ba810f03a7d61ca6bb9` |
| `qnoc-crow.ko` | 189,920 | `b695d5497b01670720c58f50d30b37a16b79215749eef1372bc3dc3c96b67ffa` |
| `rpmh-regulator.ko` | 51,632 | `52107f26c4c1e5565dc48c311173ab2d3691aec9e3bd2384f827dd210d95bcec` |
| `qcom_rpmh.ko` | 110,112 | `35497824202c42f8962147716633a37d86a7f728d7511ed1684c63a6c9a37acc` |
| `qcom_aoss.ko` | 51,472 | `bc29920249cb7b9f4cc9014575de44ee7d649d1e21d5d3c714c1535089a2f015` |
| `clk-rpmh.ko` | 114,480 | `3347ed9e6ca8c3d11b19067c02f9f5cb8e40c8162910baa0cd6b0bf92029667f` |
| `cmd-db.ko` | 21,352 | `ffcd55c46d120bc221d007d61d16c9264f26a8da1e76b35b7bdadd5ed41d807a` |
| `proxy-consumer.ko` | 23,136 | `aa3c46701bc5be00acc4088b227000c6a5176905494d3902f066fb481e2e239c` |

## Findings

### The Android BCM voter has the same state pipeline as mainline

In the exact `icc-bcm-voter.ko`, `qcom_icc_bcm_voter_commit()` at ELF
`.text+0x638` calls `rpmh_write_batch()` with state argument 2 at `.text+0x948`,
1 at `.text+0x9cc`, and 0 at `.text+0xa0c`. The v7.2.3 RPMh enum maps these to
ACTIVE_ONLY, WAKE_ONLY, and SLEEP respectively. The mainline
[`bcm-voter.c`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/bcm-voter.c#L309-L357)
does the same: AMC/ACTIVE_ONLY first, then WAKE_ONLY and SLEEP when the two
requirements differ. The core BCM-voter state mechanism is therefore not the
explaining difference; focus on which requests and BCM data reach it.

The exact `qnoc-kalama.ko` symbol table contains `bcm_mc0`, `bcm_sh0`,
`bcm_sh1`, `bcm_acv`, and QUP2 nodes. Mainline v7.2.3
[`sm8550.c`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/sm8550.c#L1302-L1425)
also defines ACV, MC0, SH0, SH1, and QUP2. Their appearance in Android's TCS
does not by itself demonstrate a vendor-only feature. No named `bcm_mc4` or
`bcm_sh5` object was found in the exact Kalama/Crow module symbol tables or
mainline `sm8550.c`; the producer of Android CMD-DB resources `MC4` (`0x50060`)
and `SH5` (`0x50064`) remains unidentified. Do not attribute these commands to
the ICC provider without tracing their caller.

### The Android regulator binary does support separate SLEEP/WAKE contexts

The exact `rpmh-regulator.ko` contains `qcom,set`, `active`, `sleep`, and
`RPMH_SLEEP_STATE`/`RPMH_WAKE_ONLY_STATE`/`RPMH_ACTIVE_ONLY_STATE` strings.
`rpmh_regulator_send_aggregate_requests()` at `.text+0x1830` sends its sleep
aggregate using `rpmh_write_async()` with state 0, the wake-only aggregate with
state 1, and the active aggregate with state 2 (synchronous `rpmh_write()` or
asynchronous depending on its wait flag). This binary evidence matches the
LDOE1/LDOE3 SLEEP/WAKE TCS words already captured in
[`tcs-sequence.txt`](2026-09-19-android-deep-rpmh/tcs-sequence.txt).

Mainline v7.2.3 [`qcom-rpmh-regulator.c`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/regulator/qcom-rpmh-regulator.c#L197-L209)
hardcodes `RPMH_ACTIVE_ONLY_STATE` in its send helper and has no equivalent
proxy aggregation path. This confirms a driver capability difference, but
does not prove which shared rails are physically changed during sleep or that
this difference causes the zero Linux residency counters. The shared LDOE1/
LDOE3 consumers still make a blind regulator A/B unjustified.

## Consequence for the experiment

Keep the prepared Nova-only PCIe low-bandwidth OPP as the first narrow Linux
A/B after the device is back on Linux and the bootc rollback preflight passes.
The exact Android modules strengthen the case for comparing request contents,
but do not prove that lowering the PCIe SLEEP floor enables AOSD/CXSD/DDR.
Treat the regulator-context gap as a separate, higher-risk hypothesis. Keep
`MC4`/`SH5` ownership open for source/caller tracing.

The device remained awake on Android with `wlan0` up and Wireless ADB connected.
No Android suspend or mutation was performed.
