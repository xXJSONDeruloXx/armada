# Stock direct-deep control before PCIe-only DTB test

Run ID: `20260921T152415Z-d9d4375f7b23`.
Raw run: `/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T152415Z-d9d4375f7b23/`.

The fresh preflight and 15-second matched control ran on stock Armada
`20260915.feca679`, Linux `7.2.3`, boot ID
`dcb129c5-a531-4e8b-899c-9bc0ff1ee29a`. The only network interface and route
was Wi-Fi `wlp1s0`; its PCIe/WCN dependency means a PCIe-disabled boot will
have no remote SSH. Before suspend, the interconnect summary showed PCIe
`1c00000.pcie` at 500000 kB/s peak on LLCC/EBI. UART `89c000.serial` retained
QUP2 avg/peak 1 and CNOC avg/peak 115.

The harness selected kernel `mem_sleep=deep`, armed RTC0 for 15 seconds, and
invoked `/usr/lib/systemd/systemd-sleep suspend` directly. The device returned
with the same boot ID, expected RTC IRQ 200, and 13.381 seconds of
boottime/monotonic separation. The suspend command returned 0. AOSD, CXSD,
and scalar DDR count/duration deltas were all zero. APSS advanced by one
entry; detailed DDR ID `0xd0` advanced by 301125714 raw ticks. These agree
with prior stock direct-deep results.

The raw `device/raw/commands/suspend-command.json` and
`device/pre/sleep-configuration.json` are authoritative for the selected path.
The host-generated top-level `result.md` still contains a stale generic claim
that the Armada dispatcher ran. The device-side result and command receipts
show direct `systemd-sleep`; no raw data was edited.

Candidate 03 build and rollback details:

- Image: `localhost/armada-sm8550-pcie-only-test:20260921-03`.
- OCI image ID: `34d660ae6cb51f36a62e95e263dc09a40963551250cf6d8ad49384448f31fed7`.
- OCI manifest: `sha256:cdf6959b7d8a1072915206b09615473f9376b62557d535efa80470085f6dec08`.
- Base: the locally retained phase-03 candidate, image digest
  `sha256:6c178cb71381532160e9b5e08f3a38033de9496d0cfcc6e7fc10b71ab42fbf49`.
- Nova DTB hash:
  `522e15cc530964db5d6527a271e5c0d50c330017b9fdc4381aa0bdae008796b6`.
- Build-time `fdtget` confirmed only
  `/soc@0/pcie@1c00000/status = "disabled"`; `89c000.serial` remains enabled.
- The candidate has a local runner which performs one 15-second direct-deep
  cycle, saves results under `/var/home/armada`, and requests bootc rollback.
  A six-minute root timer is the fallback; the inherited initrd recovery is
  present. `systemd-analyze verify` passed for the new units.
- The first local build was never staged. Pre-deploy validation caught an
  invalid run ID before reboot; tag `20260921-03` has the corrected
  `20260921T154600Z-1ee9acefc15a` ID. The embedded runner hash matches source.

Immediately before staging, root readback confirmed `/boot/efi/KERNEL` and
`KERNEL.BAK` both hash to the guard's expected
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`,
`.armada-bootimg.id` is the expected stock ID
`d7755f13ac5a1224fef222e2d104192045fd01d61924f9b1ae31e941b73f049b`, and
the ESP UUID `81DC-CB41` matches the initrd recovery script. Bootc still showed
stock booted and no staged deployment.

Candidate tag `20260921-03` was applied once. Its local service reached
userspace, then aborted before reading the DTB status or starting the harness:
the script required the Python agent to be executable, while the image copied
it as a readable non-executable file. The service immediately invoked
`bootc rollback --apply`. No candidate suspend, QCOM counter, or DTB-status
observation was produced. The recovered device is stock
`20260915.feca679`, boot ID `a601457c-4b80-469b-8c1b-afd08edbd71a`, Wi-Fi is
back, and bootc reports no staged image with tag `20260921-03` in the rollback
slot.

The failure receipt is outside Git at
`/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T1553Z-pcie-only-runner-fail/`.
The controller log SHA-256 is
`1aa33cd1961a899f4155194b0b33ee1221b86280cc687abab51a2fae09ca8d85`.
The corrected wrapper was built and run as candidate `20260921-04`; it calls
the agent through `/usr/bin/python3` and uses a fresh run ID and marker. Its
completed negative residency result, successful RTC wake, evidence archive,
and automatic rollback are documented in the
[candidate test receipt](2026-09-21-pcie-only-dtb-candidate-test.md).
