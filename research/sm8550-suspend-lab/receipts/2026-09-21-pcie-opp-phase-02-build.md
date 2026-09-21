# Bounded initrd journal capture built, not staged

Captured 2026-09-21 01:15 UTC on `feat/sm8550-suspend-lab`. This follows the
phase-01 candidate, whose recovery timer restored the stock kernel after
120 seconds but whose initrd journal was not retained. The phase-02 candidate
is built and validated but has not been staged or applied.

## Diagnostic change

The recovery helper now attempts to write the last 500 initrd journal lines
to ESP `SUSDIAG.JRN` using a temporary file, `sync`, and atomic rename before
restoring `KERNEL.BAK`. Capture failure is logged but does not stop the
fail-closed kernel restore. The existing 120-second recovery timer and PCIe
OPP behavior are unchanged. The candidate image build now asserts that
`journalctl` is present in the generated initramfs; direct inspection of the
phase-01 initramfs confirmed it already contains `journalctl` and
`systemd-journald`.

Local validation passed:

- `bash -n` for the recovery helper and test script.
- `tests/test-initrd-recovery.sh`, including persisted-log success and
  journal-command failure without blocking stock restore.
- `git diff --check`.

## Candidate image

- Tag: `localhost/armada-pcie-opp-test-phase:20260921-02`
- Manifest digest: `sha256:b8be5e46ca08c9d03aa7992bd24b9861befd95af5d360a122504cb8685d0e8bd`
- Image ID: `0cd625c73f4ec17726d32692a729df34a72c74e62be646d951a9280bfea3743c`
- Base: Armada beta digest `sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88`
- Kernel SHA-256: `15b46efc40d15200523b5c7ec623f54d4ac03bddfe798f1d8842ebf1fa2824d9`
- Nova DTB SHA-256: `72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422`

Built on-device with rootful Podman, using the cached base and no kernel
compile:

```sh
sudo -n podman build --pull=never --network=host \
  --file /var/home/armada/sm8550-suspend-lab/pcie-opp-20260921-phase-02/device-kernel-layer-pcie-opp.Containerfile \
  --tag localhost/armada-pcie-opp-test-phase:20260921-02 \
  --build-arg ARMADA_TEST_KERNEL_SHA256=15b46efc40d15200523b5c7ec623f54d4ac03bddfe798f1d8842ebf1fa2824d9 \
  --build-arg ARMADA_TEST_DTB_SHA256=72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422 \
  /var/home/armada/sm8550-suspend-lab/pcie-opp-20260921-phase-02
```

The build checked the kernel and DTB hashes, root marker/drop-in, initrd
recovery helper and units, sysinit timer link, and `journalctl` presence in
the initramfs. `systemd-analyze verify` returned 0 for the recovery service,
rollback service/timer, and boot-image sync service. Dracut printed its known
nonfatal `/dev/log` or `logger` warning; the build and final assertions
completed successfully.

## Device state before staging

At 01:15 UTC the Nova remained on stock image `20260915.feca679`, kernel
`7.2.3`, boot ID `5263e173-9323-426b-aee2-6fe6f3dc4bfd`. Systemd was
`running` with zero failed units, Wi-Fi was connected, and RTC wakealarm was
empty. Bootc and OSTree showed only stock, with no staged or rollback
deployment. Both ESP kernel files matched stock SHA-256
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`.
The phase-02 candidate exists only in rootful Podman; no boot or suspend state
had changed at capture time.

## Next step

With ABL recovery available, stage this exact digest from
`containers-storage`, verify it is the sole staged deployment, then apply.
On return, read `SUSDIAG.LOG`, `SUSDIAG.JRN`, and the root phase log before
changing the timer or running a suspend test. If the root phase marker is
still absent, use the journal to locate the initrd stall; do not count that
boot as a PCIe OPP A/B.
