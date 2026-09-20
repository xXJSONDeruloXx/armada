# Guarded PCIe OPP diagnostic image built, not staged

Captured 2026-09-20 20:14 UTC. The running Nova remains on the stock Armada
Linux boot. No bootc deployment was staged or applied, and no suspend test or
reboot was run.

## Build

Reused the existing device-local kernel/DTB candidate context at
`/var/home/armada/sm8550-suspend-lab/pcie-opp-20260920-01`. Copied in the
candidate rollback service, timer, marker, and updated Containerfile. Built
with Podman's local pinned base image and `--pull=never --network=host`:

```sh
sudo podman build --pull=never --network=host \
  --file /var/home/armada/sm8550-suspend-lab/pcie-opp-20260920-01/device-kernel-layer-pcie-opp.Containerfile \
  --tag localhost/armada-pcie-opp-test-guarded:20260920-02 \
  --build-arg ARMADA_TEST_KERNEL_SHA256=15b46efc40d15200523b5c7ec623f54d4ac03bddfe798f1d8842ebf1fa2824d9 \
  --build-arg ARMADA_TEST_DTB_SHA256=72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422 \
  /var/home/armada/sm8550-suspend-lab/pcie-opp-20260920-01
```

All kernel and DTB hash checks passed. The final image is
`localhost/armada-pcie-opp-test-guarded:20260920-02`, manifest digest
`sha256:b4560e90b4dfba8631a47c69de91bdcde7f491fa3fb47299b73d828de8e076e0`,
reported size 12.6 GB. It layers on the pinned Armada beta base and uses the
existing kernel and DTB artifacts; no kernel compile was run. An initial
guarded tag `20260920-01` was superseded after its version marker matched the
unguarded candidate. The final tag reports the distinct version
`20260920.pcie-opp-test-guarded-01`; both prior image tags remain local and
unstaged.

## Verification

- Ran `systemd-analyze verify` inside the guarded image for both units; exit 0.
- Verified the image contains the candidate marker, the enabled timer symlink
  `timers.target.wants/sm8550-pcie-opp-test-rollback.timer ->
  ../sm8550-pcie-opp-test-rollback.timer`, and version marker
  `20260920.pcie-opp-test-guarded-01`.
- Verified the marker and timer symlink are absent from the pinned stock base.
- `bootc status --json` still reports the stock beta digest booted, default
  boot order, and no staged or rollback deployment. Boot ID remains
  `aa40c55e-d558-46a9-a710-3a7d926b9e9e`.
- `/var` reports 30 GB free. Only the device-local scratch context and rootful
  Podman image store changed; the active OS, ESP, and boot selection did not.

The timer fires five minutes after systemd starts in the candidate and calls
`bootc rollback --apply`; the candidate marker prevents accidental execution
on the stock image. This covers a userspace/network startup failure only. It
cannot recover a kernel or initramfs hang before systemd, so keep this image
unstaged until there is an independent early-boot observation/recovery path or
the device is physically attended.
