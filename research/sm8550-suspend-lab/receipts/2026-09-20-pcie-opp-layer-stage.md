# PCIe OPP diagnostic layer built and staged

Captured 2026-09-20 16:59 UTC. The candidate is staged in bootc's
download-only slot and is **not queued for the next boot**. No reboot or
suspend run has happened with this candidate yet.

## Build inputs and result

- Exact base: `ghcr.io/armada-os/armada@sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88`.
- Build context: `/var/home/armada/sm8550-suspend-lab/pcie-opp-20260920-01`.
- Build tag: `localhost/armada-pcie-opp-test:20260920-01`.
- Candidate manifest digest:
  `sha256:d7eb055720a28bddc8f6a3e7267d6e56c54c53de719963ed06c1228f851e101b`.
- Candidate image size reported by Podman: 12,583,663,553 bytes.
- Candidate OSTree checksum staged by bootc:
  `7eb51de69c15c669d35900ff93b279c8b8a21ffec8f415e7da00d14dd2d55cbf`.
- The candidate OCI rootfs has all 128 pinned-base layers as an identical
  prefix, plus four image layers for labels, the kernel, Nova DTB, backup
  preservation drop-in, and version/hash-validation changes.
- Build-time and disposable-container hash checks report:
  - `vmlinuz`: `15b46efc40d15200523b5c7ec623f54d4ac03bddfe798f1d8842ebf1fa2824d9`
  - `qcs8550-retroidpocket-rpnova.dtb`:
    `72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422`
  - `/usr/lib/armada/version` is `20260920.pcie-opp-test-01`.
- The image contains the intended boot-image sync override, which removes only
  the startup `--snapshot-prev` argument and leaves the updater command active.

## Build failure and retry

The first build reached the final hash-validation `RUN` step but failed while
Netavark tried to configure an isolated build network:

```text
netavark: nftables error: "nft" did not return successfully while applying ruleset
```

No device firewall or networking change was made. The validation step performs
only local hash checks and writes the image version marker. Retrying the same
inputs with Podman's `--network=host` passed; no network access was used by the
build step.

## Stage and rollback gate

`sudo bootc switch --transport containers-storage --download-only
localhost/armada-pcie-opp-test:20260920-01` completed successfully. Status
reports staged `downloadOnly=true`, candidate image digest and OSTree checksum
above, and `rollbackQueued=false`. The booted and rollback deployments are
still the original base digest and OSTree checksum
`ec096ad2fdb64e35dd9b2ac691690d80f6e62d80c2617704d2a5788c7b95294b`.

Before staging, both `/boot/efi/KERNEL` and `KERNEL.BAK` matched SHA-256
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`. They
were independently copied and verified off-device; see
[`2026-09-20-live-linux-preflight-and-boot-backup.md`](2026-09-20-live-linux-preflight-and-boot-backup.md).
After staging, the device hashes remain unchanged. `/var` has 30 GB free.

The post-boot validation must still confirm kernel/version, the candidate BTF
hash, the preserved ESP backup, Wi-Fi/SSH health, and the test OPP. Only then
run one RTC-bounded `deep` test with the PCIe/RPMh trace profile. The retained
backup is a manual recovery aid; automatic recovery from a kernel hang is not
claimed.
