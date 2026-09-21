# Candidate module-only build path

Captured 2026-09-21 01:51 UTC. This is host/build-tree inspection only; no
module has been built or deployed in this step.

## Exact candidate build context

- Existing source/build tree:
  `/Volumes/NovaKernelBuild/work/linux-7.2.3`.
- `make -s kernelrelease` returns `7.2.3`; `pcie-qcom.c` contains the
  diagnostic `diag_opp_active` change used by the candidate image.
- The tree's `.config` SHA-256 is
  `2219546e268f72bb2bcbac96943202e9e50731b6e531e3193cc73b1976d2fbef`,
  matching the saved live-device config. It has modules and module BTF
  enabled; Btrfs and device mapper are modules; `CONFIG_MODVERSIONS` is unset.
- `vmlinux`, `Image`, and `vmlinux.o` already exist. Their hashes match the
  candidate receipts; `vmlinux.o` is 1.5 GB. `Module.symvers` and the
  candidate `.ko` files are absent because the candidate image build stopped
  after producing the kernel and DTB.
- The active container `armada-kmod-build` is native AArch64, based on the
  pinned Fedora 44 builder image, and mounts this exact tree read/write at
  `/kernel`. Its GCC is `16.2.1`, exactly matching the generated kernel
  compiler metadata; `pahole` is `v1.30`. The generated compile metadata
  names the same container hostname, `d56d368ba840`.
- Armada's package build script builds `Image dtbs modules` and then runs
  `modules_install` with `INSTALL_MOD_STRIP=1`. Here, the existing `Image` and
  Nova DTB are already verified, so only module targets and installation are
  needed; a kernel image rebuild is not the first choice.

## Bounded module set

The stock Nova currently has 96 modules loaded. This set includes the
root-critical `btrfs`, `dm_mod`, `raid6_pq`, `xor`, and `libblake2b` modules,
as well as the active Wi-Fi (`ath12k_wifi7`, `ath12k`, `mac80211`, `cfg80211`)
and the device's currently active sound, input, power, and remote-processor
modules. Loaded module dependencies are also loaded in this snapshot.

The candidate config has 1,458 symbols set to `=m`. Building only the
currently loaded modules and their dependencies, plus the initrd root closure,
is a smaller first step. Kbuild's single-`.ko` target path temporarily lists
the requested modules and runs `modpost`; because this tree has `vmlinux.o`
and module versioning is disabled, it should be possible to validate this
subset without compiling all 1,458 module configs. This has not yet been
executed; the next step is to run the selected targets, inspect modpost/BTF
results, and stage only those matching `.ko` files while retaining the base
module index files.

If targeted Kbuild cannot resolve the symbols or emits unusable module BTF,
stop and correct the build method before packaging. Do not hide modpost errors
or deploy unvalidated modules. The candidate kernel and device remain on
stock Armada; no boot setting has changed.
