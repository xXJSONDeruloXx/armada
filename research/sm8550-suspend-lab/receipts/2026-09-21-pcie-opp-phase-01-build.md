# Phase-marker PCIe OPP candidate built, not staged

Captured 2026-09-21 00:53 UTC on `feat/sm8550-suspend-lab`. This continues
from the guarded apply that returned to stock without identifying its boot
phase. The phase-marker follow-up has been built and verified, but has not
been staged, applied, or used for a suspend test.

## Candidate image

- Tag: `localhost/armada-pcie-opp-test-phase:20260921-01`
- Manifest digest: `sha256:54ab4a31d2669ed6fe4d48f782396f6a44464c239d86ee69b3dabc74424089d5`
- Image ID: `aee66458720bc40482586cb9a55fbf3ea49ad0b609d8d9acf0467a089c16c969`
- Base: Armada beta digest `sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88`
- Kernel SHA-256: `15b46efc40d15200523b5c7ec623f54d4ac03bddfe798f1d8842ebf1fa2824d9`
- Nova DTB SHA-256: `72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422`

The kernel and DTB are the same pinned artifacts used by the earlier guarded
candidate. This image retains the single PCIe diagnostic OPP change and adds
boot-phase observability only:

1. The initrd recovery helper writes `event=initrd_recovery_started` to ESP
   `SUSDIAG.LOG` before checking the stock backup. After a successful stock
   kernel restore it replaces that line with
   `event=stock_kernel_restored`, including the current boot ID.
2. A candidate-root `ExecStartPre` appends the boot ID and Armada image version
   to `/var/lib/sm8550-pcie-opp-test/boot-phases.log` before the normal Armada
   boot-image sync service runs.

The initrd recovery timer still uses the exact stock `KERNEL.BAK` SHA-256
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000` before
it will replace `KERNEL`. The existing five-minute real-root bootc rollback
timer is also included. Neither marker changes PCIe or sleep policy.

## Build and validation

Synced the lab-only recipe, initrd guard, and root marker into the device
scratch context `/var/home/armada/sm8550-suspend-lab/pcie-opp-20260921-phase-01`.
Built with rootful Podman against the pinned local base and no network pull or
kernel compile:

```sh
sudo -n podman build --pull=never --network=host \
  --file /var/home/armada/sm8550-suspend-lab/pcie-opp-20260921-phase-01/device-kernel-layer-pcie-opp.Containerfile \
  --tag localhost/armada-pcie-opp-test-phase:20260921-01 \
  --build-arg ARMADA_TEST_KERNEL_SHA256=15b46efc40d15200523b5c7ec623f54d4ac03bddfe798f1d8842ebf1fa2824d9 \
  --build-arg ARMADA_TEST_DTB_SHA256=72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422 \
  /var/home/armada/sm8550-suspend-lab/pcie-opp-20260921-phase-01
```

Build assertions verified both artifact hashes, the root marker executable
and its boot-sync drop-in, the initrd recovery service/timer/helper/marker,
and the timer link under `sysinit.target.wants`. `systemd-analyze verify`
returned 0 for the candidate rollback service/timer and Armada boot-image
sync service. Local `bash -n`, `tests/test-initrd-recovery.sh`, and
`git diff --check` passed. Dracut printed its previously observed nonfatal
container warning that `/dev/log` or `logger` is not included; the build and
all final assertions exited successfully.

## Device preflight after build

At 00:53 UTC, the device remained on stock image `20260915.feca679`, kernel
`7.2.3`, boot ID `ef966ac2-4fb6-4222-b573-fb84d474e295`. Systemd was running
with zero failed units; Wi-Fi was connected; RTC wakealarm was empty. Root
`bootc status --json` showed stock beta booted with `bootOrder=default`,
`rollback=null`, `rollbackQueued=false`, and `staged=null`. Read-only hashes
of both ESP kernel files matched the stock hash listed above. The candidate
image exists only in rootful Podman; no boot, deployment, or suspend state
had changed at capture time.

## Next action and interpretation

With the owner present for ABL recovery, stage this exact local digest using
bootc's `containers-storage --download-only` path, verify the staged digest
and default rollback state, then apply it. On SSH return, check the candidate
version and DTB, `SUSDIAG.LOG`, and the root phase log before doing anything
that suspends the device. If it returns to stock, preserve the phase file and
clean the pending deployment/ESP with the documented Armada recovery path;
do not count that as an OPP A/B. Run the 15-second RTC-woken direct-deep test
only if candidate root is positively confirmed.
