# Observation-only diagnostic kernel: build and deployment preparation

Status at 2026-09-02 00:30 UTC: the diagnostic kernel artifact is built,
wrapped in an ephemeral OCI/bootc layer, and booted successfully on the Nova.
The image is observation-only: no functional kernel change, firmware change,
ABL change, loose boot-file replacement, QMP/AOSS operation, forced vote, or
device power-control change is part of it.

## Artifact and provenance

- Package checkout: `/Users/kurt/Developer/armada-packages-suspend-lab`
- Package source commit: `f595f0f` (`fix(kernel): register RPMh post-resume
  diagnostic notifier`), on branch `feat/sm8550-rsc-observation`
- Package working branch: `feat/sm8550-rsc-observation`
- Kernel source: kernel.org stable `linux-7.2`, as selected by
  `kernel/BASE.env` and `kernel/scripts/build-kernel.sh`
- Armada patch series includes
  `0900-soc-qcom-rpmh-read-only-diagnostics.patch` last
- Diagnostic config: `CONFIG_QCOM_RPMH_SUCCESS_DEBUG=y`; `CONFIG_DEBUG_INFO_BTF=y`
  remains enabled because Linux 7.2's scheduler configuration depends on it
- Build container: Fedora arm64 image
  `registry.fedoraproject.org/fedora@sha256:0c6072366ebf8ea1c8c0f3a118aad3e9a9247d3065d499e54d62968f69351966`
- Output: `kernel/out/armada-kernel-7.2.0.tar.zst`
- Artifact SHA-256:
  `6ad795b7a50318d1af7e75ccc7e9576edefea6700b4cea6a38e14374935c56c3`
- Embedded `vmlinuz` SHA-256:
  `197d096d16642cebff417ed181df856ac621a172b642ef9b2189ef74d44d8b7b`
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

## Fast kernel-only iteration path

The full Armada image build was attempted once and failed during standard
Proton extraction with Docker VM/ext4 storage I/O errors (`metadata_v2.db:
input/output error`, failed unwritten extents). The source build was not the
cause. Docker was restarted, build cache was pruned, and the generated ccache
was removed; source checkouts and the verified kernel artifact were retained.
The full signed-image path remains the production boundary, but rebuilding the
whole image for each kernel-only observation is unnecessarily slow.

For this explicitly authorized test device, the repeatable fast path is the
small device-local image layer in
`research/sm8550-suspend-lab/device-kernel-layer.Containerfile`:

1. Copy the verified kernel archive, checksum, and recipe to the device-local
   staging directory `/var/home/armada/sm8550-rsc-pmcb`.
2. Build a new uniquely tagged OCI layer from the already-installed diagnostic
   base `localhost/armada-rsc:20260901`. The recipe verifies the checksum,
   installs the complete packaged module tree, regenerates the Armada-style
   initramfs, and records both the image version label and
   `/usr/lib/armada/version`.
3. Apply only that local image through
   `bootc switch --transport containers-storage --download-only` followed by
   `bootc switch --from-downloaded --apply`.

This is still an OCI/bootc deployment, not a loose `/boot`, initramfs, or
`/usr/lib/modules` replacement. Every changed layer must use a new tag; tag
reuse can leave bootc staging on an older image digest. The successful layer
was `localhost/armada-rsc:20260901-pmcb4`, version
`20260901.rsc-f595f0f-pmcb`, image digest
`sha256:c31703b2c4d6f8273a10f017cd3951580458fc946afa6ca98a131c747bf77d76`,
and OSTree commit
`bc8bb4139fe20ab1f7270ba991c84266caad65d9c644ba86584e1a13cd3ee14f`.

The temporary device authorization was narrow: a sudoers drop-in permits only
the lab runner, the staged podman command, and bootc. No containers policy file
was edited. Remove that drop-in during final stock rollback and verify generic
passwordless sudo is no longer available.

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

The Nova at `192.168.0.20` is booted into the corrected diagnostic layer,
version `20260901.rsc-f595f0f-pmcb`, kernel `7.2.0`, image
`localhost/armada-rsc:20260901-pmcb4`, image digest
`sha256:c31703b2c4d6f8273a10f017cd3951580458fc946afa6ca98a131c747bf77d76`,
and OSTree commit
`bc8bb4139fe20ab1f7270ba991c84266caad65d9c644ba86584e1a13cd3ee14f`.
The successful boot required both an explicit `ostree.linux=7.2.0` label and a
regenerated initramfs with the Armada `ostree`, splash, and fallback modules.
Earlier uniquely tagged `pmcb`/`pmcb2`/`pmcb3` attempts are preserved as failed
boot receipts: inherited metadata caused rollback, then missing initramfs and
an overlong generated BLS entry caused rollback. No history was overwritten.

Root preflight
`/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260902T001225Z-bfa21e4b672a.json`
confirmed the diagnostic config, root-readable complete trace-event inventory,
and unchanged Nova identity. The successful RSC cycle and valid UFS cycle are
recorded in the lab notebook and their raw archives. No deployment through
loose kernel or boot-file copying was used.

For every further layer, record a fresh preflight and retain its exact receipt.
After reboot, require the expected Armada version/origin, kernel `7.2.0`,
unchanged Nova DT identity, diagnostic config and root-readable trace-event
inventory, unchanged boot ID, and a clean post-boot health check. A failed or
ambiguous boot is a recovery boundary, not a suspend result.

## Physical instructions for the deployment and first diagnostic run

For further testing, leave the Nova on a stable surface with no USB cable,
charger, dock, hub, or controller attached. Keep the microSD mounted. No
manual action is needed during a normal fast-path deployment or RTC-controlled
suspend; SSH will be unavailable while it reboots and during the suspend.
Reconnect only after the agent reports the boot and health checks complete.
The lab will continue to use Armada's
`/usr/libexec/armada/suspend-dispatch` after independently arming RTC wake.

The corrected RSC run
`20260902T001240Z-f80f54f6b742` and valid UFS run
`20260902T002708Z-4e8666167435` are complete. The UFS evidence does not justify
a storage patch; the next experiment must target the remaining RPMh/AOP or
counter-semantics boundary rather than guess at a Linux device workaround.

## Functional candidate boundary: DWC3 skip-PHY-init

The reviewed Qualcomm DWC3 candidate was built separately from the diagnostic
artifact as package commit `5aa8e4c` on branch
`feat/sm8550-dwc3-skip-phy`, with exactly one additional kernel patch,
`0910-usb-dwc3-qcom-skip-phy-init.patch`. The clean arm64 package workflow
`33580043873` passed with the same Linux 7.2 source, pinned Fedora builder,
diagnostic RSC patch, and config. The carrier and archive hashes, device layer
digest, and full A/B evidence are in
[`dwc3-skip-phy-ab.md`](dwc3-skip-phy-ab.md).

The candidate was deployed only through the fast OCI/bootc path, tested once
in a matched cable-free/off-radio deep cycle, and rolled back after no
observable USB/PHY mechanism or relevant power/residency improvement was
found. Candidate s2idle was intentionally not run under the predeclared gate;
the unresolved RSC/AOP question remains separate.
