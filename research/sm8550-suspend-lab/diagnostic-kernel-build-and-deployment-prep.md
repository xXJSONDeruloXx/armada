# Observation-only diagnostic kernel: build and deployment preparation

Status at 2026-09-01 21:03 UTC: the diagnostic kernel artifact is built and
verified. It has not been installed on the Nova. No functional kernel change,
firmware change, ABL change, boot-file replacement, QMP/AOSS operation, forced
vote, or device power-control change is part of this artifact.

## Artifact and provenance

- Package checkout: `/Users/kurt/Developer/armada-packages-suspend-lab`
- Package base: `armada-os/armada-packages` commit
  `2c93e73cbe1bcf4d443495e94fbaa5e7a8cf7141`
- Package working branch: `feat/sm8550-rsc-observation`
- Kernel source: kernel.org stable `linux-7.2`, as selected by
  `kernel/BASE.env` and `kernel/scripts/build-kernel.sh`
- Armada patch series: 136 patches applied, with
  `0900-soc-qcom-rpmh-read-only-diagnostics.patch` last
- Diagnostic config: `CONFIG_QCOM_RPMH_SUCCESS_DEBUG=y`; `CONFIG_DEBUG_INFO_BTF=y`
  remains enabled because Linux 7.2's scheduler configuration depends on it
- Build container: Fedora arm64 image
  `registry.fedoraproject.org/fedora@sha256:0c6072366ebf8ea1c8c0f3a118aad3e9a9247d3065d499e54d62968f69351966`
- Output: `kernel/out/armada-kernel-7.2.0.tar.zst`
- Artifact SHA-256:
  `3fc078ffc04e59471538269abe442fab907f3c792a0b42c048d816715af72cc1`
- Embedded `vmlinuz` SHA-256:
  `5d7348afe15a71ef5918c47eea9d3d995f88d3e157bd65b6907eed352e71d867`
- Embedded source metadata reports `Built: armada-builder on aarch64`, 20
  DTBs, and `Repackaged for: armada`.

The archive passed `zstd -t`, checksum verification, extraction to a temporary
directory, and tar-entry checks for the Nova DTB, `vmlinuz`, and the complete
module payload. The build completed with exit status 0 after a prior storage
failure during module BTF finalization was isolated to the Docker build store;
the final build used no ccache mount and retained BTF configuration.

The patch carries the reviewed Qualcomm CMD-DB name/type helpers and merged
RSC timeout diagnostics, plus an Armada-specific successful-path observation.
The Armada portion uses `readl` through the driver's version-selected offsets
to snapshot configured active/sleep/wake TCS state after Linux programs the
sleep set and again from the PM post-suspend notifier. It does not trigger a
TCS, clear an IRQ, write a TCS/AOSS/QMP register, or force a vote. The source
references and differences are recorded in `kernel/PATCHES.md` in the package
checkout and in `upstream-state.md` here.

## Supported delivery boundary

The raw package tarball is a build artifact, not a device-install input. The
Armada delivery path is:

1. Build the package carrier image from the package checkout using its normal
   staging/build recipe.
2. Assemble an Armada bootc image with the carrier selected as the local
   `kernel` package, using the main checkout's `Containerfile` and `Justfile`.
3. Publish/sign the resulting image through the Armada image workflow, or use a
   separately approved equivalent that satisfies the device's container policy.
4. On the Nova, use Armada's shipped `steamos-update`/`armada-update` path to
   check, stage, and apply the signed image. The update is staged by bootc and
   the normal Armada boot-image synchronization hook regenerates the boot image
   for the next boot.

Do not copy the tarball into `/boot` or `/usr/lib/modules`, invoke a raw
`bootc switch` to bypass Armada policy, edit `/KERNEL`, flash ABL, or use a
different suspend entry path. If the custom image cannot be signed and accepted
by the device's policy, deployment stops at this document rather than weakening
the update boundary.

## Current device gate

The Nova at `192.168.0.20` is still booted into Armada `20260830.71e45aa`,
kernel `7.2.0`, with the existing `testing` origin. A read-only live check
confirmed the Fedora 44 base, `/usr/libexec/armada/armada-update`,
`/usr/bin/steamos-update`, and the expected Armada boot-image helpers. The
unprivileged account can inspect the system but root authorization is required
for bootc status, package staging, and lab collection. No deployment has been
attempted.

Before the eventual update, record a fresh lab preflight and retain its exact
receipt. After reboot, require all of the following before the diagnostic
suspend run: the expected Armada version/origin, kernel `7.2.0`, unchanged Nova
DT identity, the diagnostic config/tracepoint, unchanged boot ID after the
update boot, and a clean post-boot health check. A failed or ambiguous boot is a
recovery boundary, not a suspend result.

## Physical instructions for the deployment and first diagnostic run

At the moment deployment is started, leave the Nova on a stable surface with
no USB cable, charger, dock, hub, or controller attached. Keep the microSD
mounted. Do not press buttons or touch the device during the reboot/update;
SSH will be unavailable while it reboots and during the later RTC-controlled
suspend. Reconnect only after the agent reports the boot and health checks
complete. The lab will continue to use Armada's
`/usr/libexec/armada/suspend-dispatch` after independently arming RTC wake.

The next observation remains exactly one `rsc-success` deep cycle, followed by
classification of the four outstanding branches. No functional fix is selected
until that evidence exists.
