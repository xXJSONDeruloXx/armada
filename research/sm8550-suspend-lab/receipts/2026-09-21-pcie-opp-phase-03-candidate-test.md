# Phase-03 candidate test: PCIe floor changed, residency did not

Captured 2026-09-21 02:43 UTC on feat/sm8550-suspend-lab. The test used a
single 15-second RTC-woken direct-deep run on the matching-module candidate.
It did not change firmware, regulators, PCIe link policy, or radios. The raw
run is retained outside Git at:

/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T023438Z-9d42e275c2f9/

## Candidate boot

- Image tag: localhost/armada-pcie-opp-test-phase:20260921-03.
- Podman image ID: 12212bf145929dc7b7e56f7234cc8b043f9bc9b17e74267ad0d900abe0fd49cc.
- Manifest digest: sha256:6c178cb71381532160e9b5e08f3a38033de9496d0cfcc6e7fc10b71ab42fbf49.
- Candidate version: 20260921.pcie-opp-test-phase-03; kernel 7.2.3.
- Kernel SHA-256: 15b46efc40d15200523b5c7ec623f54d4ac03bddfe798f1d8842ebf1fa2824d9.
- Nova DTB SHA-256: 72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422.
- All 96 stripped modules matched the manifest and candidate vermagic. The
  generated initramfs included Btrfs, dm-mod, raid6_pq, xor, and libblake2b.
  The candidate root marker was recorded on boot
  6660e4d7-3e96-4cf3-900f-9ba32710b494; Btrfs and dm-mod were loaded.
  This fixes the phase-02 initrd BTF/module packaging failure.

## Direct-deep run

Run ID: 20260921T023438Z-9d42e275c2f9, started at 02:34:41 UTC with trace
profile rpmh-aoss. It selected deep, logged both suspend entry and exit,
returned from systemd-sleep suspend with code 0, and the RTC IRQ/wakeup source
fired. BOOTTIME minus MONOTONIC was 14.286997 seconds. The boot ID was the
same before and after the suspend call, so the suspend itself returned
without a reset.

The trace directly observed the candidate PCIe memory-path request being
reduced during suspend preparation. For path
xm_pcie3_0@16c0000.interconnect-ebi@interconnect-1 from device
1c00000.pcie, icc_set_bw set peak bandwidth to 1,000 kB/s on the
PCIe/LLCC/EBI route. The Apps-RSC SLEEP TCS submissions then contained:

| Address | Candidate SLEEP data | Stock control data |
| --- | ---: | ---: |
| 0x50000 (MC0) | 0x60000001 (1) | 0x600003b8 (952) |
| 0x50004 (SH0) | 0x60000001 (1) | 0x600003b8 (952) |
| 0x50010 | 0x40000000 | 0x40000000 |
| 0x50038 | 0x40000000 | 0x40000000 |
| 0x50048 | 0x00000000 | 0x00000000 |
| 0x50044 | 0x40000000 | 0x40000000 |

The WAKE payloads matched the stock control. This is strong evidence that the
PCIe OPP change lowers the submitted MC0/SH0 SLEEP floor. It is not proof that
AOP/RPM firmware accepted/applied the TCS: rpmh_rsc_snapshot was unavailable
on the image, so the derived snapshot is available=false.

Despite the request change, the before/after firmware records were:

- AOSD: count delta 0, duration delta 0.
- CXSD: count delta 0, duration delta 0.
- Scalar DDR: count delta 0, duration delta 0.
- APSS SMEM: count delta +1, duration delta 274,249,880 raw ticks.
- Detailed DDR LPM: 0xd0 duration +318,614,909 raw ticks; 0x11,
  0xd3, and 0xd4 unchanged. The ID and units remain undocumented.

The run did not collect the PCIe D3cold eligibility probe or the
psci_system_suspend_enter return probe. Its rpmh-aoss profile did capture the
submitted Apps-RSC SLEEP/WAKE commands and optional ICC tracepoints. It shows
the PCIe floor is not sufficient by itself to produce named AOSD/CXSD/DDR
residency; additional Android-versus-Armada request/context differences
remain to be isolated.

## Automatic rollback and current device state

The root guard began bootc rollback --apply at 02:35:14 UTC and logged
"Next boot: rollback deployment" at 02:35:20. The next Linux boot is stock
Armada 20260915.feca679, boot ID
3656b0e7-5671-4b7e-9368-67965daa251a. At 02:42 UTC Wi-Fi was connected,
systemd had zero failed units, and bootc showed stock booted, phase-03 in the
rollback slot, staged=null, and rollbackQueued=false. The device recovered
itself; no manual ABL reset was needed. During the candidate run's immediate
post-resume health snapshot, wlp1s0 was temporarily DOWN/NO-CARRIER; Wi-Fi
was connected after the automatic stock rollback boot.

## Evidence hashes

- Result: 441264c078e7f3630d456a56349f586e834b95f43cd4a600d5fd9c9f571cb2b9.
- Raw trace: 516158fef73bc31f876006d80f06dc907192ae10d024986d9c2b7aa3e38ded29.
- Derived summary: 633e7e01434f9e5b9972934772cdd94524d3f8b9e6593b7bcafebd31540e196a.
- Host manifest: 10ca52c1f6d94ab93fe5b14218bbcd19cca7c5fecd04d62e6184594931ffbfc5.
- Pre/post interconnect summaries and the run-scoped trace are in the raw run
  directory above.

## Decision

Keep the OPP code diagnostic-only. The test verifies it changes the firmware
request floor from the stock 952 down to 1 but falsifies the claim that this
change alone enables AOSD/CXSD/scalar-DDR residency. The next experiment should
come only after the source audit identifies a separate, narrowly scoped
Android-versus-Armada request difference that can be changed independently.
