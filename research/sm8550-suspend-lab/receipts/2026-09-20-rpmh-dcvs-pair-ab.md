# MC4/SH5 RPMh sleep-pair A/B

## Setup

- Run: `20260920T135031Z-2e899212c506`, captured 2026-09-20 13:50–13:51 UTC.
- Armada branch/host source: `feat/sm8550-suspend-lab`, HEAD
  `5e08ca028bd332b47278d82926bf67d7d3969e91`.
- Device: Nova, Fedora/Armada Linux `7.2.3`, image `20260915.feca679`,
  boot ID `09a76af5-4e8f-454a-858e-dedb4ebb1d4d`.
- Test module SHA-256:
  `548d9244a327cc16ba04d2ad644a0b87b08660dfd37e8db5144e07a0065eda2f`.
  It was copied to `/tmp`, loaded once, and was not installed in an image.
- Module init logged
  `SLEEP_AB: MC4=0x50060 SH5=0x50064 SLEEP=0 WAKE_ONLY=1`.
  It did not change ACTIVE votes, PCI state, regulators, or the boot deployment.
- The harness ran a 10-second-minimum RTC-woken direct `deep` suspend. The
  kernel reported `PM: suspend entry (deep)`, suspend success advanced by 1,
  failure stayed unchanged, RTC0 woke the device, and boottime-minus-monotonic
  showed 9.319121 seconds of sleep. The same boot survived and Wi-Fi/SSH
  recovered.

## Captured Apps-RSC TCS commands

The `rpmh:rpmh_send_msg` trace at 5139.5058–5139.5059 seconds contained this
complete Apps-RSC WAKE/SLEEP set. Data words are the exact trace values.

| Context | CMD-DB resource | Address | Data |
|---|---|---:|---:|
| WAKE | MC0 | `0x50000` | `0x60000823` |
| WAKE | SH0 | `0x50004` | `0x600011db` |
| WAKE | SN0 | `0x50010` | `0x60004001` |
| WAKE | CN0 | `0x50038` | `0x60004001` |
| WAKE | QUP1 | `0x50048` | `0x20004001` |
| WAKE | QUP0 | `0x50044` | `0x60004001` |
| WAKE | MC4 | `0x50060` | `0x60000001` |
| WAKE | SH5 | `0x50064` | `0x60000001` |
| SLEEP | MC0 | `0x50000` | `0x600003b8` |
| SLEEP | SH0 | `0x50004` | `0x600003b8` |
| SLEEP | SN0 | `0x50010` | `0x40000000` |
| SLEEP | CN0 | `0x50038` | `0x40000000` |
| SLEEP | QUP1 | `0x50048` | `0x0` |
| SLEEP | QUP0 | `0x50044` | `0x40000000` |
| SLEEP | MC4 | `0x50060` | `0x60000000` |
| SLEEP | SH5 | `0x50064` | `0x60000000` |

The MC4/SH5 pair therefore appeared in the traced Apps-RSC SLEEP/WAKE messages.
The shared MC0/SH0 SLEEP data remained at `0x600003b8` (the previously
observed 952 floor). This trace profile has no `rpmh_rsc_snapshot` event, so
the messages establish the staged TCS payloads, not independent proof of AOP
acceptance. The run's ICC client attribution field is unavailable; do not
assign this specific floor to a client from this run alone.

## Outcome

- AOSD, CXSD, and scalar DDR count/duration deltas: all zero.
- APSS count delta: +1.
- Detailed DDR LPM ID `0xd0` duration delta: +227,760,477 ticks, with no count
  delta. The ID and tick units remain opaque and this is not evidence of a
  named AOSD/CXSD/DDR residency transition.
- PSCI trace recorded CPU/domain state `0x40000004` enter/exit events; the
  event semantics do not prove physical SoC or rail residency.
- Harness cleanup restored the previous `mem_sleep`, debug settings, RTC
  alarm, and private trace instance. Wi-Fi remained enabled and Bluetooth
  remained off as before the run.

**Conclusion:** staging MC4/SH5 alone did not restore the named firmware
residency counters in this bounded run, while the existing MC0/SH0 floor
remained. This rejects the pair as a sufficient standalone fix in the tested
condition; it does not show that the pair has no effect or that AOP applied
each command. The stronger next lead remains the retained PCIe/MC0/SH0 floor,
but a new A/B requires a source-supported, safe way to change one variable.

## Raw evidence

The complete immutable harness artifact is outside the repository at:

`/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260920T135031Z-2e899212c506`

Key SHA-256 values:

- `device/raw/trace/trace.txt`:
  `272630efa3d5c25d6d8871837b6aabf1e4f5bd94cc92ca6955db56d8e2abe7df`
- `device/derived/summary.json`:
  `adcd567bf3d9aec509955d33da50f74a02c2b4b76696d07c684ab6e22da70afa`
- `device/pre/qcom_stats.json`:
  `f4d5eff91d5485ca05da6b7deee2ecc9e771762ed4ae956f33437a3932862551`
- `device/post/qcom_stats.json`:
  `6b1cb3da16ce20a66495aeff3ebce8a4a130ea3244319116dff91c03f02e440a`

At test completion the module remained loaded and its RPMh request cache was
pending a reboot. A subsequent normal reboot returned the Nova to Linux on new
boot ID `cd02fc51-33c5-4b1a-96a7-75a17eb98b30`. Post-reboot SSH checks reported
kernel `7.2.3`, Armada version `20260915.feca679`, `mem_sleep=[s2idle] deep`,
suspend success/fail `0/0`, `wlp1s0` up, system state `running`, zero failed
units, and the test module absent. No kernel layer or deployment was installed.
The harness had already removed its private trace instance before reboot;
post-boot tracefs inventory was denied to the non-root SSH account.
