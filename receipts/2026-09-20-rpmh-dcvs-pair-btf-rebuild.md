# MC4/SH5 probe BTF-compatible rebuild

Date: 2026-09-20 13:45 UTC
Branch: `feat/sm8550-suspend-lab`

## Rebuild

The first module failed because `make modules_prepare` had disabled BTF module
support. In the isolated ARM64 build container, I re-enabled
`CONFIG_DEBUG_INFO_BTF=y` and `CONFIG_DEBUG_INFO_BTF_MODULES=y`, ran
`olddefconfig` and `modules_prepare`, cleaned the module output, and rebuilt
only the out-of-tree probe with the existing `vmlinux.symvers`. No kernel image
or device file was rebuilt.

The new artifact is
`/Volumes/NovaKernelBuild/armada-rpmh-dcvs-pair/armada_rpmh_dcvs_pair.ko`:

- SHA-256: `548d9244a327cc16ba04d2ad644a0b87b08660dfd37e8db5144e07a0065eda2f`
- Vermagic: `7.2.3 SMP preempt mod_unload aarch64`
- `.gnu.linkonce.this_module`: `0x500` (1280 bytes), equal to the same section
  in the shipped device module `crypto_engine.ko`.
- Module DWARF `struct module`: 1280 bytes, 65 members, matching live BTF.

## ABI comparisons

The rebuilt module's `struct device` (800 bytes/43 members), `struct bus_type`
(168 bytes/22 members), and `struct tcs_cmd` (12 bytes/3 members) have matching
live-BTF sizes and member offsets. `rpmh_state` values match live BTF:
SLEEP=0, WAKE_ONLY=1, ACTIVE_ONLY=2. A field-by-field `pahole` comparison
showed only compiler alignment annotations, not layout differences.

Canonical signatures extracted from live BTF and the local kernel tree's BTF
match for `bus_find_device`, `device_match_name`, `put_device`,
`cmd_db_read_addr`, and `rpmh_write_async`. In particular,
`rpmh_write_async` is `int(const struct device *, enum rpmh_state,
const struct tcs_cmd *, u32)` and `cmd_db_read_addr` is `u32(const char *)`.
The local `vmlinux.symvers` marks the six kernel API symbols
(`bus_find_device`, `device_match_name`, `put_device`, `platform_bus_type`,
`cmd_db_read_addr`, and `rpmh_write_async`) as GPL exports, and the symbol
names are present in the live kernel's kallsyms.

The live config has BTF module support enabled, `CONFIG_MODVERSIONS` disabled,
and `CONFIG_MODULE_ALLOW_BTF_MISMATCH` disabled. The corresponding 7.2.3 module
loader reads `.BTF`/`.BTF.base`, relocates a module base BTF against the live
vmlinux BTF, and rejects BTF mismatch unless the allow-mismatch option is set.
This provides a load-time type check for the new artifact; it is not a
replacement for symbol CRCs or proof of identical source revision.

## Source identity and scope

The device's `/usr/lib/modules/7.2.3/.armada-source` says 144 patches from
`patches/series`; the current Armada package series has 144 entries and was
last changed before the device's September 13 kernel build. The local scratch
kernel tree also contains the separate Nova diagnostic PCIe OPP C/DT edits
used in the earlier targeted-build experiment, so its vmlinux build ID and
build date differ from the device's. Those edits do not change the module/API
types checked here. Exact running-image source identity remains unproven.

The rebuilt artifact has not been copied to or loaded on the Nova. The rejected
old artifact remains unloaded in `/tmp`; there are no cached RPMh requests and
no reboot is required. Next gate: copy this exact hash, verify it on-device,
and attempt one insertion. Do not suspend unless init logs successful CMD-DB
lookups and both RPMh contexts. If BTF validation rejects it, do not bypass the
loader check or retry with BTF mismatch allowed.
