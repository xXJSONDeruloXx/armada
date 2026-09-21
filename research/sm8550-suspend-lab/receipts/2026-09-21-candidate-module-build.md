# Matching candidate modules built without rebuilding the kernel image

Captured 2026-09-21 02:04 UTC. This is a host-side module build and package
preparation step. The candidate image has not yet been built or deployed.

## Build result

- Used the existing `/Volumes/NovaKernelBuild/work/linux-7.2.3` tree in the
  active native AArch64 `armada-kmod-build` container. Its GCC `16.2.1`,
  `pahole v1.30`, kernel release `7.2.3`, and config match the candidate
  kernel build; the `.config`, `vmlinux`, and `Image` hashes remained
  unchanged.
- Built only the 96 `.ko` targets corresponding to modules loaded on the
  stock Nova, including the root module closure. The target list was derived
  from `/proc/modules` and `modinfo -F filename`; no warning suppression was
  used. Command form:

  ```sh
  cd /kernel
  make -j8 ARCH=arm64 <96 selected .ko targets>
  ```

- Kbuild exited successfully after compiling 579 module objects, linking 96
  modules, and generating BTF for all 96. The log contains no modpost,
  unresolved-symbol, compiler, or BTF errors. `Module.symvers` was generated
  from this selected set and the existing candidate `vmlinux.o`.
- A follow-up check confirmed all 96 `.ko` files exist, each has vermagic
  `7.2.3 SMP preempt mod_unload aarch64`, and each has a `.BTF` section.
- Copied and stripped only debug sections from the 96 module files. Their
  BTF sections and vermagic remain present; the resulting overlay is 17 MB.
  Btrfs shrank from 44,734,592 bytes to 3,214,128 bytes while retaining `.BTF`.
- The exact 96 destination paths and SHA-256 values are in
  [`2026-09-21-candidate-module-manifest.sha256`](2026-09-21-candidate-module-manifest.sha256),
  SHA-256
  `8ae27c4a1f9990adcdc0592de50b9622a4eebd8a4bb4ed4c8e376492e9914521`.

## Boot-image plan

The Nova's stock initramfs already contains Btrfs, `dm_mod`, `raid6_pq`,
`xor`, and `libblake2b` at the expected `/usr/lib/modules/7.2.3/kernel/...`
paths. The diagnostic Containerfile now copies the matching 96-module
overlay over those same paths, checks all file hashes, runs `depmod`, then
regenerates the guarded initramfs. It also asserts the five root-critical
modules appear in the new initramfs. This lets the image build fail before
staging if a module is missing or differs from the validated payload.

No module was loaded into the stock kernel. No boot setting or deployment
changed. The Nova remains on stock `20260915.feca679` / kernel `7.2.3`; the
next step is build and inspect the phase-03 candidate image, then stage/apply
it with the 120-second recovery guard and ABL recovery available. Do not run
the PCIe OPP suspend A/B until its candidate-root marker and post-boot health
checks pass.
