# Stock direct-deep PSCI return control

Date: 2026-09-20. Device: Nova, Armada `20260915.feca679`, Linux `7.2.3`,
boot ID `aa40c55e-d558-46a9-a710-3a7d926b9e9e`.

Run ID: `20260920T234417Z-1ec58a1619be`. This was one 15-second,
RTC-woken direct-`deep` control on the unchanged stock image. The only
run-scoped changes were selecting `deep` and programming/restoring the RTC
wake alarm. No kernel, DT, firmware, bandwidth, or radio policy changed.

## Result

- Kernel entry and exit logs both say `deep`; the suspend command returned 0.
- `CLOCK_BOOTTIME - CLOCK_MONOTONIC` was `13.530067` seconds. The expected
  PMIC RTC alarm fired and the boot ID stayed unchanged.
- The run-scoped kretprobe observed one
  `psci_system_suspend_enter` return with `retval=0`. PSCI CPU/domain trace
  events recorded 797 enter and 797 exit callbacks for state `0x40000004`
  with `s2idle=no`.
- AOSD, CXSD, and scalar DDR firmware-record deltas were all zero. APSS SMEM
  advanced by one count and `259694622` ticks; ADSP advanced by 15 counts and
  `312719398` ticks; CDSP duration advanced by `313041401` ticks without a
  count change. These SMEM values are separate from the three zero SoC
  residency records.
- Detailed DDR LPM ID `0xd0` duration advanced by `313042917` raw ticks,
  with no count change. IDs `0x11`, `0xd3`, and `0xd4` did not change. The
  `0xd0` meaning and tick unit remain undecoded.
- The immediate post-resume network snapshot at 23:44:52 UTC showed
  `wlp1s0` administratively UP but `NO-CARRIER`. A later live check found it
  UP with carrier; SSH was available, systemd was `running`, and no failed
  units were reported. The transient link recovery is recorded rather than
  treating the first snapshot as final health.
- Cleanup restored the original empty RTC alarm, disabled both PSCI trace
  events, removed the private trace instance and run-specific kretprobe, and
  restored the debug settings. A follow-up read found no alarm and the
  original `[s2idle] deep` selection.

## Interpretation

This weakens the hypothesis that Linux simply fails to invoke PSCI
`SYSTEM_SUSPEND`: the Linux wrapper returned success once and the system
resumed from the RTC. It does not prove that firmware accepted or physically
entered the intended system-level power state. The PSCI callbacks describe
requested states and return codes, not rail residency; the AOSD/CXSD/scalar
DDR records still show no entries in this window.

## Evidence and integrity

Raw run directory (outside Git):
`/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260920T234417Z-1ec58a1619be/`.
The captured trace contains the return event at line 1282. Host checksum
verification checked 4,594 files with zero mismatches (`ok=true`).

SHA-256:

- Trace: `2d017e337cc368d9abb5b8b4955eba2ce1a12aad2659f4965328cdc9294e3be9`
- Derived summary: `4ed90864aa4727bd669ad8a0580c2a75557edde386e0bfd7109f560df1fc3abd`
- Host manifest: `2651309314cdab36f1cb28149a3266c67d9edc0a754c5e05670a1dacdb0ae6e4`
- Device status: `935857f708ff7025fd881fc4136158b667ab64b63ad4ab04a491f028e6d3167f`
