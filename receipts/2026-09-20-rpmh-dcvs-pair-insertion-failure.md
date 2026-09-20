# MC4/SH5 probe insertion failure

Date: 2026-09-20 13:27 UTC
Branch: `feat/sm8550-suspend-lab`

## Outcome

The test-only `armada_rpmh_dcvs_pair.ko` was copied to `/tmp` on Armada Linux
and passed to `insmod`. The kernel rejected it before module initialization:

```text
module armada_rpmh_dcvs_pair: .gnu.linkonce.this_module section size must match the kernel's built struct module size at run time
```

This is a module ABI/layout mismatch, not an RPMh API or CMD-DB failure. The
probe's init function did not run, so it queued no SLEEP or WAKE_ONLY requests.
No suspend was attempted. The running deployment, boot ID, and Wi-Fi state were
unchanged. The rejected artifact is not loaded or installed persistently; do
not retry it.

## Exact mismatch

- Running kernel `/sys/kernel/btf/vmlinux`: `struct module` size 1280 bytes,
  65 members.
- Rejected module's DWARF and `.gnu.linkonce.this_module`: 1216 bytes,
  61 members; ELF section size `0x4c0`.
- The rejected build lacks the four live BTF-module fields
  `btf_data_size`, `btf_base_data_size`, `btf_data`, and `btf_base_data`.
  Later `struct module` members shift by 24 bytes; cacheline alignment makes
  the final object 64 bytes smaller.
- The live kernel config has `CONFIG_DEBUG_INFO_BTF=y` and
  `CONFIG_DEBUG_INFO_BTF_MODULES=y`. `make modules_prepare` normalized the
  local config and disabled both options before the probe was compiled. This
  explains the loader's exact size rejection.
- The existing local `vmlinux` reports the same 1280-byte `struct module`
  layout as live BTF, but its build ID (`cee09cd96435caa0e27230f6636eb5026302e8ee`)
  differs from the running kernel's (`c6fa94a80791299f41d4a780f6fb0e6b6f489203`).
  Treat it as corroborating type evidence, not proof that the local image is
  the exact running binary.

## Next safe gate

Rebuild the probe with the live BTF-module configuration restored. Before any
new insertion, require all of the following:

1. `.gnu.linkonce.this_module` size and all `struct module` member offsets
   match live BTF.
2. The probe's relevant DWARF layouts and API prototypes match live BTF,
   including `struct device`, `struct platform_device`, `struct tcs_cmd`, and
   the RPMh calls used by the probe.
3. The patched source/release and generated symbol exports used for the build
   are identified well enough to explain any remaining ABI assumptions.

`CONFIG_MODVERSIONS` is disabled on the device, so the kernel cannot provide a
symbol-CRC guard. Matching `vermagic` alone is insufficient, as this failure
demonstrated. If the exact ABI cannot be established from the available tree,
stop before another insertion and use a matching kernel build environment or
move to offline/source-only instrumentation.
