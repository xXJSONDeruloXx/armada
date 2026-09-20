# Stock direct-deep PCIe/RPMh control

Captured 2026-09-20 22:06:53 UTC with the suspend-lab runner on the Nova's
unchanged stock Armada deployment. This was a 15-second RTC-woken direct
`deep` control; no kernel, DT, PCIe, Wi-Fi, Bluetooth, or RPMh policy was
changed. The only temporary device change was the run-scoped RTC alarm and
trace instance, both cleaned by the harness.

## Identity and run

- Run ID: `20260920T220653Z-2d370a752c35`.
- Branch/host HEAD: `feat/sm8550-suspend-lab` at
  `ab327730025fa9a5d49d41f714f98063916fd738`.
- Kernel/image: Linux `7.2.3`, Armada `20260915.feca679`, stock beta image
  digest `sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88`.
- Boot ID before and after: `aa40c55e-d558-46a9-a710-3a7d926b9e9e`.
- Requested and observed mode: `deep`; `/sys/power/mem_sleep` remained
  `[s2idle] deep`.
- RTC alarm woke the run through IRQ 199 (`pm8xxx_rtc_alarm`) and the PMIC RTC
  wakeup source. The systemd suspend command returned 0; BOOTTIME minus
  MONOTONIC showed 13.612693 seconds of suspend-clock separation.
- Wi-Fi remained enabled and `wlp1s0` returned UP; the Steam/Gamescope session
  remained alive. Bluetooth was off before and after and was preserved.

## PCIe and RPMh observations

The `pcie-d3cold` run-scoped trace captured
`__pci_host_common_d3cold_possible()` rejecting Qualcomm root port
`0000:00:00.0` (`17cb:0113`): `current_state=5` (`PCI_UNKNOWN`) and return
`-95` (`-EOPNOTSUPP`). The trace does not show the host completing its normal
DesignWare link/host shutdown.

Immediately before `machine_suspend`, the Apps-RSC trace recorded six SLEEP
commands and six WAKE commands. The raw message values were:

| Context | Address | Data |
|---|---:|---:|
| SLEEP | `0x50000` | `0x600003b8` |
| SLEEP | `0x50004` | `0x600003b8` |
| SLEEP | `0x50010` | `0x40000000` |
| SLEEP | `0x50038` | `0x40000000` |
| SLEEP | `0x50048` | `0x00000000` |
| SLEEP | `0x50044` | `0x40000000` |
| WAKE | `0x50000` | `0x600028b6` |
| WAKE | `0x50004` | `0x60002ff9` |
| WAKE | `0x50010` | `0x60004001` |
| WAKE | `0x50038` | `0x60004001` |
| WAKE | `0x50048` | `0x20004001` |
| WAKE | `0x50044` | `0x60004001` |

The MC0/SH0 SLEEP payloads remain `0x600003b8` (952). The exact live ICC
attribution was established by the earlier dedicated profile; this run's
`pcie-d3cold` profile did not independently recapture per-client votes. The
RSC snapshot event is unavailable on this image, so these trace records prove
Linux submitted the commands, not that firmware acknowledged or applied each
one.

## Suspend and residency boundary

- The kernel logged `PM: suspend entry (deep)` and `PM: suspend exit`; the
  systemd suspend operation succeeded and RTC wake evidence matched.
- AOSD, CXSD, and scalar DDR count/duration deltas were all zero.
- APSS SMEM advanced by one count and `261302731` duration ticks. ADSP/CDSP
  SMEM records also advanced; these are separate subsystem records.
- Detailed DDR LPM ID `0xd0` advanced by `310695345` ticks; IDs `0x11`,
  `0xd3`, and `0xd4` did not. The `0xd0` meaning and tick units are still
  undocumented here.
- This run did **not** register the `psci_system_suspend_enter` kretprobe:
  `psci_idle_trace.available=false`. Earlier matched direct-deep runs did
  record a successful PSCI system-suspend return; do not attribute that
  kretprobe result to this particular run.

This repeats the stock result: direct deep suspends and resumes, while the
named AOP/RPM firmware records report no AOSD/CXSD/scalar-DDR entry. It does
not prove that the staged PCIe floor causes the missing residency or that the
firmware applied the SLEEP TCS.

## Raw evidence

The full run is retained outside Git at:
`/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260920T220653Z-2d370a752c35/`.

- Derived host `result.md` SHA-256:
  `ca0551c4e511be1999c283f1304990f160cfe6dc3084fbe57e00005e589c90d2`.
- Raw trace `device/raw/trace/trace.txt` SHA-256:
  `f190af4f417b1c049dd88b3888e6a2c308dcdd64f623e1dc68bfc5e46d8a058d`.
- Host manifest SHA-256:
  `f2bd2de00383391635b0ff9d84f67269faa2b8d7ce7c3873095a611d11ef28b1`.
- Device status SHA-256:
  `a6d0d94b0da2b79eaf804440cbdca2d4ad75f2e9f449ccbe1eea26250ef92c0c`.

The candidate PCIe-MEM OPP comparison remains unrun. The existing initrd
recovery helper passed a scratch-VFAT test, but it cannot recover a failure
before initrd systemd queues its timer; do not stage the candidate without a
known early-boot recovery path.
