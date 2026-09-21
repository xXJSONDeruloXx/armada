# Guarded PCIe OPP image apply returned to stock before the A/B

Captured 2026-09-21 00:23 UTC on branch `feat/sm8550-suspend-lab`, starting
from `32a6aec2dea3813b7e835acec8f375c2366c156a`. The Nova's owner was
available to recover from ABL. This was one guarded deployment attempt; no
suspend or bandwidth A/B ran.

## Preflight and candidate

- The device was healthy on the stock beta deployment, kernel `7.2.3`, boot
  ID `aa40c55e-d558-46a9-a710-3a7d926b9e9e`, with Wi-Fi connected and no
  staged/rollback deployment.
- Both ESP files matched the known stock SHA-256
  `0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`.
  The active stock image-ID stamp was
  `d7755f13ac5a1224fef222e2d104192045fd01d61924f9b1ae31e941b73f049b`.
- The guarded test image was present in rootful Podman:
  `localhost/armada-pcie-opp-test-initrd-guard:20260920-06`, manifest digest
  `sha256:21ba7a30b3585f3f438b32a1dbd8e4d4c2435d7ab968e9b91ed39acfa4a3cad6`,
  image ID
  `9bdbc4f0c2f57eb07f0a46b663dcc1561b46dddab73b3094257c3ac6bf187f55`.
- `/var` had 29 GB free. The candidate was staged download-only, then bootc
  confirmed the exact manifest digest and `rollbackQueued=false` before apply.

## Apply and return

At 2026-09-21 00:12:24 UTC, `sudo bootc switch --from-downloaded --apply`
started an orderly reboot. The persistent journal records the old boot's
`armada-bootimg-finalize` writing `/boot/efi/KERNEL` for `vmlinuz-7.2.3` at
00:12:39 UTC. SSH was unavailable for roughly two minutes, then returned on
boot ID `ef966ac2-4fb6-4222-b573-fb84d474e295`.

The returned system was the stock root, not the candidate:

- `/usr/lib/armada/version` was `20260915.feca679`.
- `/proc/cmdline` pointed to stock OSTree checksum
  `ec096ad2fdb64e35dd9b2ac691690d80f6e62d80c2617704d2a5788c7b95294b`.
- `bootc status` showed stock as booted, the test image in `rollback`,
  `rollbackQueued=true`, and `spec.bootOrder=rollback`.
- `ostree admin status` showed the test deployment pending and stock booted.
- No candidate version/DTB marker was observed over SSH; there is no
  persistent candidate boot ID or candidate-root journal, and pstore is empty.

The stock boot journal records `initrd-switch-root.target` at 00:14:55 UTC.
Its stock `armada-bootimg-sync` then logged “saved known-good
`/boot/efi/KERNEL.BAK`” at 00:14:59 and wrote `/boot/efi/KERNEL` at 00:15:02.
At the time, the candidate BLS deployment was still pending. This explains
how a stock root could rewrite the next-boot image as the candidate while
leaving the stock backup intact. Before cleanup, `/KERNEL` had SHA-256
`a503892dbd4b6fd82242f00b527dac89cecacb6a78adde9f9e8f21cd123a4a8e` and
`KERNEL.BAK` still had the stock hash.

The surviving evidence does not distinguish whether the initrd recovery timer
restored the stock image, ABL/firmware selected the backup, or a manual ABL
reset caused the return. The owner was asked whether they intervened. Do not
claim that the candidate reached switch-root or that the guard fired.

## Restoring the known-good state

Without another reboot, `rpm-ostree cleanup --pending` removed one pending
deployment (136 layers; 114.2 MB freed). Armada's own
`/usr/libexec/armada/armada-bootimg-update` then wrote `/KERNEL` from the
active stock BLS entry.

Post-cleanup verification at 00:22 UTC:

- `bootc status`: stock beta booted, `bootOrder=default`,
  `rollback=null`, `rollbackQueued=false`, `staged=null`.
- `ostree admin status`: only the stock deployment remained.
- Both `/boot/efi/KERNEL` and `KERNEL.BAK` again matched the stock SHA-256
  above; both image-ID stamps read the stock ID.
- Systemd was `running` with zero failed units, Wi-Fi was connected, RTC
  wakealarm was empty, and the boot ID had not changed during cleanup.
- The candidate OCI image remains in Podman storage at the digest above.

## Result and next diagnostic

The deployment was not available as a confirmed candidate Linux userspace,
so this run provides no evidence about the PCIe suspend OPP, Apps-RSC requests,
PSCI result, or sleep counters. Do not report it as an A/B result.

Before another candidate boot, determine whether the owner manually reset in
ABL and add a small durable boot-phase receipt for the candidate initrd and
recovery helper. The current experiment's root journal cannot show whether the
120-second initrd timer fired, and the stock startup hook can rewrite the
pending candidate into `/KERNEL` after a fallback. Keep the device on the
verified stock boot until that return path is understood or observable.
