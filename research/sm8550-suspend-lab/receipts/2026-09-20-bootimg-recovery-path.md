# Current bootc deployment and boot-image recovery path

Read-only capture at 2026-09-20 15:06:04. No image was pulled, staged, or applied.

## Live state

- The Nova is awake on Armada Linux 7.2.3, base image
  ghcr.io/armada-os/armada:beta digest
  sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88.
  bootc status shows no staged image.
- Rootful Podman uses /var/lib/containers/storage; its only image is the
  199 MB Fedora builder. The rootless store is separate and empty. Device
  /var has 37 GB free.
- The current ESP /boot/efi/KERNEL and saved KERNEL.BAK are both
  75,522,048 bytes and have SHA-256
  0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000.
  Their 64-byte Armada image stamps also match. The known-good backup is
  therefore present before staging.
- /etc/containers/policy.json accepts containers-storage images under its
  existing local-storage policy. No signature policy change is needed.

## Bootc and Armada source behavior

- bootc switch --download-only stages an image without rebooting.
  bootc switch --from-downloaded --apply applies a staged target and
  reboots immediately. Do not use --apply until the candidate, boot-image
  synchronization, and recovery gates are checked.
- Armada's
  [boot-image sync service](../../../system_files/usr/lib/systemd/system/armada-bootimg-sync.service#L17-L24)
  runs armada-bootimg-update --snapshot-prev at startup and runs
  armada-bootimg-update again at shutdown, after deployment finalization.
- The [image updater](../../../system_files/usr/libexec/armada/armada-bootimg-update#L43-L65)
  snapshots the currently stamped /KERNEL to KERNEL.BAK on startup.
  It then reads the next-boot BLS entry, packs that deployment's kernel,
  initramfs, and all listed DTBs into an ABL boot image, and atomically
  replaces /boot/efi/KERNEL
  ([packing and replace](../../../system_files/usr/libexec/armada/armada-bootimg-update#L105-L164)).
- The Nova is in supported-dtbs; the updater gets the target deployment's
  list, so replacing only its
  /usr/lib/modules/7.2.3/dtb/qcom/qcs8550-retroidpocket-rpnova.dtb makes
  the generated image carry that test DTB with the full supported set.
- Important recovery limit: armada-bootimg-finalize calls bootc rollback
  if regenerating /KERNEL fails. That is an update failure fallback, not proof
  of automatic recovery from a kernel that boots and then hangs. The initramfs
  fallback only remaps a missing ostree= path to a surviving deployment with
  the same kernel; it does not select KERNEL.BAK.

## Required test-only safeguard

The stock startup command would overwrite KERNEL.BAK with the diagnostic
kernel at the first successful test boot, because the image stamp changes.
To retain the proven pre-test image for the entire A/B, the temporary test
image should include a vendor drop-in that clears only the snapshot option:

~~~ini
[Service]
ExecStart=
ExecStart=/usr/bin/ionice -c 2 -n 7 /usr/libexec/armada/armada-bootimg-update
~~~

This keeps the startup freshness check and leaves the existing shutdown
ExecStop updater intact. The drop-in disappears when bootc rolls back to
the original deployment. It changes no suspend behavior. If the diagnostic
kernel does not return SSH, the prior KERNEL.BAK remains the manual recovery
image; do not claim that this is an automatic boot-failure fallback.

No test image has been built or staged yet. The matching-config kernel rebuild
is still active on the Mac's external build volume.
