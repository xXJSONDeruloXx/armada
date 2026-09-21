# PCIe-only disabled-DTB suspend test

Candidate image `localhost/armada-sm8550-pcie-only-test:20260921-04` booted
with `/soc@0/pcie@1c00000/status = "disabled"`; its local runner verified
that live DT value before starting the harness. QUP2 and the rest of the
candidate base were unchanged. This was a host-absent-from-boot positive
control, not a test of PCIe/WCN suspend or resume.

## Build and recovery

- Version: `20260921.pcie-only-dtb-1556`.
- Base: `localhost/armada-pcie-opp-test-phase:20260921-03`, manifest
  `sha256:6c178cb71381532160e9b5e08f3a38033de9496d0cfcc6e7fc10b71ab42fbf49`.
- OCI image ID: `8b2d24e8f313a59f19e39f3f938c2d88baa0711516bc27ff1432c73da19e7140`.
- OCI manifest digest: `sha256:1d0e7f5e46e9c33b84b5b402f426e1ffde93eb53038e92923a340589d0111c05`.
- DTB SHA-256: `522e15cc530964db5d6527a271e5c0d50c330017b9fdc4381aa0bdae008796b6`.
- The previous `20260921-03` deployment aborted before suspend because its
  wrapper invoked a readable, non-executable Python agent directly. Candidate
  04 invokes the agent with `/usr/bin/python3`, uses a fresh marker and run ID,
  passed `py_compile` and `systemd-analyze verify`, and retained the local
  six-minute rollback timer plus initrd recovery guard.
- Applied at 2026-09-21 16:06 UTC. The candidate completed its local run,
  called `bootc rollback --apply`, and returned to stock
  `20260915.feca679`; Wi-Fi/SSH returned. Bootc reports stock booted, no staged
  deployment, and the test image only in the rollback slot.

## Run

- Run ID: `20260921T155600Z-b9511ca007d6`.
- Candidate boot ID stayed `2c7798de-aa34-4d61-bd29-814fb8bbeed7` across
  suspend; systemd observed kernel mode `deep`, and direct
  `/usr/lib/systemd/systemd-sleep suspend` returned 0.
- `CLOCK_BOOTTIME - CLOCK_MONOTONIC` measured 14.166 seconds of suspend.
  RTC0 woke the system through IRQ 209 (`pm8xxx_rtc_alarm`); there was no reset.
- AOSD, CXSD, and scalar DDR count/duration deltas were all zero. APSS
  advanced by one entry (271,917,554 raw ticks). Detailed DDR LPM record
  `0xd0` advanced by 302,609,056 raw ticks; `0x11`, `0xd3`, and `0xd4`
  stayed unchanged.
- The harness runtime-PM inventory contained no PCIe host/root/endpoint
  entries. The candidate had no Wi-Fi during the test; normal PCIe/WCN resume
  was not tested. Its rollback restored stock and Wi-Fi.
- `rpmh_rsc_snapshots.available` was false. This run does not establish that
  firmware applied or acknowledged a particular SLEEP TCS command set.

## Interpretation

Removing the PCIe host from the candidate device tree did not make the named
AOSD/CXSD/scalar-DDR residency counters advance. Combined with phase 03, where
reducing the PCIe memory-path request from 500000 to 1 kB/s lowered the MC0/SH0
SLEEP floors but left those counters at zero, this makes PCIe host presence or
its large vote an insufficient standalone explanation. The run did not capture
the final MC0/SH0 SLEEP words or a complete Apps-RSC acknowledgment, so it does
not prove that the resulting floor was zero or that firmware applied a
particular request set. It also does not identify whether QUP2, ACV, regulator
context, or another power-domain request is the remaining blocker. The APSS
and DDR `0xd0` movement confirms this was a real RTC-woken deep suspend, not a
failed or no-op attempt.

The complete device archive is outside Git at
`/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T155600Z-b9511ca007d6/device/`.
The archive checksum verification covered 3,739 files with zero mismatches.
The candidate controller log, bootc status, and result summary are alongside
that run. No additional test was run after this candidate.
