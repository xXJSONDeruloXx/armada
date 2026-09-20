# PCIe OPP scratch config reconciled to live Nova

Captured 2026-09-20 14:32 UTC. The only mutation was to the external scratch
kernel build configuration. No kernel artifact was rebuilt or deployed, and
the Nova runtime was not changed.

## Result

The saved live config and the reconciled scratch config are byte-identical:

```text
SHA-256 2219546e268f72bb2bcbac96943202e9e50731b6e531e3193cc73b1976d2fbef
```

In `/Volumes/NovaKernelBuild/work/linux-7.2.3`, I backed up the prior scratch
config to
`/Volumes/NovaKernelBuild/armada-rpmh-dcvs-pair/pci-opp-config.before-schedext-20260920`
(SHA-256 `ffeef3364ee62e1e819c9a3f9c37406822483c61104a8a13785e652b917dd755`).
Then I enabled `CONFIG_SCHED_CLASS_EXT` using `scripts/config` and ran
`make ARCH=arm64 olddefconfig` in the existing in-tree build. Kconfig restored
all required values:

```text
CONFIG_SCHED_CLASS_EXT=y
CONFIG_GROUP_SCHED_BANDWIDTH=y
CONFIG_EXT_GROUP_SCHED=y
CONFIG_EXT_SUB_SCHED=y
CONFIG_PCIE_QCOM=y
```

The resulting `.config` hash exactly matches the config copied from the
running Nova. `CONFIG_PCIE_QCOM=y` means the diagnostic change belongs in the
built-in kernel Image, not a replaceable module.

## Build state and next gate

The existing linked `vmlinux`, `Image`, and Nova DTB were built before this
config correction; their hashes in the preceding
[config-gate receipt](2026-09-20-pcie-opp-image-config-gate.md) are stale for
deployment and must not be installed. Rebuild `Image dtbs` incrementally with
the exact live config, record new hashes, and verify the embedded config and
DTB marker. Then inspect the bootc staging/rollback route before installing.

The local AArch64 build container is `armada-kmod-build`, with the source tree
mounted at `/kernel` and build tools available. The earlier separate `O=`
Kconfig attempt failed because this source tree already contains an in-tree
build; no `mrproper` was run, preserving the cache.
