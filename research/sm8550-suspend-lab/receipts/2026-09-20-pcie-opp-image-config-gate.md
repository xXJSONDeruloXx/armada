# PCIe OPP candidate image config gate

Captured 2026-09-20 14:24 UTC. This is a read-only audit of the Linux device
and an existing scratch build; no kernel, boot layer, or device setting was
changed during this check.

## Device and branch

- Research branch: `feat/sm8550-suspend-lab`, then at `58b3d8d` and matching
  `origin/feat/sm8550-suspend-lab`.
- Nova is awake on Armada Linux, kernel `7.2.3`, boot ID
  `cd02fc51-33c5-4b1a-96a7-75a17eb98b30`; SSH and Wi-Fi are up and there are no
  failed systemd units.
- Live `/proc/config.gz` copy:
  `/Volumes/NovaKernelBuild/device-linux-config-7.2.3`, SHA-256
  `2219546e268f72bb2bcbac96943202e9e50731b6e531e3193cc73b1976d2fbef`.

## Candidate artifacts

The external tree `/Volumes/NovaKernelBuild/work/linux-7.2.3` already contains
the test-only PCIe OPP change and linked artifacts:

| Artifact | SHA-256 |
|---|---|
| `drivers/pci/controller/dwc/pcie-qcom.o` | `bca7e626ae96c0ed7003b42eadc969f358db54ce433436743b6077ea243239d0` |
| `vmlinux` | `49b98897c007f185c5a781314cbecc812c013187d9d5278807589f5c813b24d8` |
| `arch/arm64/boot/Image` | `9d84d8b7f3b75ea7ecd51aa4f5d93d4587a73ac8901f12bc5d1bf58c1a9743a3` |
| Nova DTB | `72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422` |

The linked Image and DTB contain `armada,diag-pcie-mem-suspend-opp`; this
proves the earlier statement that no linked image existed was stale. It does
not make this image safe to deploy.

## Config mismatch: deployment veto

The scratch `.config` SHA-256 is
`ffeef3364ee62e1e819c9a3f9c37406822483c61104a8a13785e652b917dd755`. Its
diff against the saved live config contains four scheduler options:

| Symbol | Running device | Candidate `.config` |
|---|---:|---:|
| `CONFIG_SCHED_CLASS_EXT` | `y` | not set |
| `CONFIG_GROUP_SCHED_BANDWIDTH` | `y` | not set |
| `CONFIG_EXT_GROUP_SCHED` | `y` | not set |
| `CONFIG_EXT_SUB_SCHED` | `y` | not set |

Both configs retain `CONFIG_BPF_SYSCALL=y`, `CONFIG_BPF_JIT=y`,
`CONFIG_DEBUG_INFO_BTF=y`, `CONFIG_CGROUPS=y`, and `CONFIG_CGROUP_SCHED=y`.
The package build fragment explicitly sets `CONFIG_SCHED_CLASS_EXT=y` because
`scx_lavd` requires sched-ext. The candidate image could therefore change
runtime scheduler capability; do not deploy it. The additional three symbols
are selected/defaulted by the matching Kconfig when `SCHED_CLASS_EXT` and
cgroup scheduling are enabled.

## OPP A/B source check

The active Linux snapshot reports PCIe Gen2 x1. In the SM8550 OPP table, that
maps to the 5 GT/s x1 entry: `required-opps = <&rpmhpd_opp_low_svs>` and
`opp-peak-kBps = <500000 1>` for PCIe-MEM and CPU-PCIe. The proposed Nova-only
test entry also requires `rpmhpd_opp_low_svs`, but sets the paths to
`<1000 1>`. OPP core applies bandwidth through its normal interconnect path;
the unchanged `low_svs` requirement means the intended firmware-facing change
is the PCIe-MEM bandwidth request, not a lower RPMh power-domain corner. The
test runs only in the existing host-unsuspended `PM_SUSPEND_MEM` branch, after
the standard DesignWare suspend/D3cold decision. It makes no PCI D-state claim
and does not call `icc_set_bw()` directly.

This is a narrowly scoped candidate, not proof that bandwidth causes the
missing firmware residency or that every wake path is safe. The existing
patch and design are in `proposals/pcie-qcom-diagnostic-opp.patch`,
`proposals/rpnova-diagnostic-opp.diff`, and `proposals/README.md`.

## Build path and next gate

The local `armada-kmod-build` container is AArch64 and already mounts the
scratch tree at `/kernel`; it has native `make`, GCC, and `pahole`. This makes
an incremental rebuild feasible. An attempted separate `O=` Kconfig check
stopped because the source tree already contains an in-tree build; do not run
`mrproper`, which would delete the useful cached build. Instead, back up the
scratch `.config`, enable `CONFIG_SCHED_CLASS_EXT=y`, run `olddefconfig` in the
existing tree, and compare all options with the saved live config before
building. Preserve the original config backup and do not deploy until the
resulting Image/DTB/config and the bootc rollback procedure are verified.

No bootc layer, deployment, or runtime setting has been changed. The current
Linux boot is unchanged and healthy.
