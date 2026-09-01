# SM8550 suspend lab notebook

This is the running observation log for the Retroid Pocket Nova at
`192.168.0.20` (`node=fedora`, user `armada`). Every device experiment gets a
dated entry here before the next experiment starts. Raw receipts remain in the
host output directory `/Users/kurt/Developer/sm8550-suspend-lab-runs/`; the
paths below are intentionally exact so an observation can be audited back to
the device archive.

## 2026-09-01 correction addendum

The device image used for all historical entries through the supported update
boundary is Armada `20260817.8b49045` with kernel `7.2.0-rc7`. The source checkout used to build the harness is newer,
currently at Armada `main` commit
`71e45aa956ad53834ebaaefd6070f28f43d4462d`. Therefore every run through
that boundary is a historical pre-current-fixes control, not the current
Armada baseline. The archives and their original result documents are
retained unchanged. A fresh read-only preflight and a supported Armada update
must complete before a new current-image baseline is named; current-image
experiments will be appended after the boundary.

The clock interpretation is also corrected here without rewriting old run
archives: every new run records the signed separation
`delta(CLOCK_BOOTTIME) - delta(CLOCK_MONOTONIC)` and labels zero/negative
separation as unexpected or negative. Kernel suspend markers and
`suspend_stats` remain independent evidence; a missing clock separation is not
silently treated as normal for either s2idle or deep.

The fresh corrected preflight at `2026-09-01T15:10:21Z` again identified the
historical booted image as Armada `20260817.8b49045` / kernel `7.2.0-rc7`,
bootc image digest
`sha256:275a67b09e6c60fcd3148e09a2b954bbae3b6105725273caeff880247fa0441d`,
with no staged deployment. The supported beta update check at
`2026-09-01T15:12:39Z` returned exit 7 with no output because the beta remote
digest was identical to the booted digest. The complete receipts are
`/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T151021Z-6af837b23e98.json`
and
`/Users/kurt/Developer/sm8550-suspend-lab-runs/supported-update-20260901T151238Z-e96c61cf6e7f.json`.

At `2026-09-01T15:14:40Z`, the shipped selector was used to select the
`main` token, which Armada maps to the `testing` channel. The selector exited
zero and changed only `/var/lib/armada/update-channel`; it did not reboot or
write kernel/boot files. Receipt:
`/Users/kurt/Developer/sm8550-suspend-lab-runs/supported-channel-20260901T151440Z-5d805e252e76.json`.

After that supported channel selection, the shipped update hook was checked at
`2026-09-01T15:15:19Z`. `/usr/bin/steamos-update check` exited zero and
reported target version `20260830.71e45aa`; the receipt is
`/Users/kurt/Developer/sm8550-suspend-lab-runs/supported-update-20260901T151519Z-649e292716e7.json`.

At `2026-09-01T15:26:31Z`, `/usr/bin/steamos-update` staged the selected
testing deployment successfully. The hook imported 128 missing layers
(`6.1 GB`), queued signed image digest
`sha256:cae66b751f6376c7a2da84e7bca7fa81293e9689f7cc9b6bd682ebe83d852c25`
with version `20260830.71e45aa`, and exited zero. It did not reboot; the
receipt is
`/Users/kurt/Developer/sm8550-suspend-lab-runs/supported-update-20260901T152631Z-6bbdb6ec7311.json`.

The pre-apply read-only inventory at `2026-09-01T15:27:44Z` captured the
booted beta image (`20260817.8b49045`, digest
`sha256:275a67b09e6c60fcd3148e09a2b954bbae3b6105725273caeff880247fa0441d`)
and the queued testing image (`20260830.71e45aa`, digest
`sha256:cae66b751f6376c7a2da84e7bca7fa81293e9689f7cc9b6bd682ebe83d852c25`)
together. Receipt:
`/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T152744Z-bc2684c2a174.json`.

At `2026-09-01T15:28:05Z`, the staged deployment was applied through an
autonomous root-owned unit running bootc's supported
`upgrade --apply --from-downloaded` operation. This was the normal apply step
after Armada's `steamos-update` hook staged the image; no kernel or boot file
was manually replaced. Receipt:
`/Users/kurt/Developer/sm8550-suspend-lab-runs/supported-update-20260901T152804Z-36e09b5bac57.json`.

## Device and scope

- Device identity: `Retroid Pocket Nova`; device-tree compatible values
  `retroidpocket,rpnova`, `qcom,qcs8550`, `qcom,sm8550`.
- Historical completed runs before the update boundary used kernel
  `7.2.0-rc7`, Armada `20260817.8b49045`. The post-update current-image
  provenance is recorded below; no current-image suspend run has yet been
  counted as a baseline.
- Host source anchor: Armada `main` at
  `71e45aa956ad53834ebaaefd6070f28f43d4462d` when the lab started.
- Physical condition requested for the sleep baselines: no USB/charger/dock or
  hub attached, no touch or button input during the timed window, device awake
  at the desktop before launch, and microSD left mounted. The harness disabled
  Wi-Fi and Bluetooth only inside the run and restored both afterward.
- No kernel, firmware, ABL, boot-image, storage-controller, device-binding, or
  persistent suspend-policy change has been made by this lab.

## How to read the results

The autonomous root-owned agent invokes Armada's shipped
`/usr/libexec/armada/suspend-dispatch` and writes the post snapshot only after
that command returns. Each run records the signed clock separation
`delta(CLOCK_BOOTTIME) - delta(CLOCK_MONOTONIC)` without clamping it. A
zero/negative separation is reported as unexpected/negative for both modes;
kernel entry/exit markers and `suspend_stats` remain separate evidence.
`suspend_success` is not a claim that every subsystem functionally recovered;
the health and gamepad/display/audio/USB/Steam gates are separate.

The first four current-image receipts (A-D) were generated while the derived
summary still used the legacy basis labels
`kernel-s2idle-markers-plus-waited-systemd-job` and
`kernel-markers-plus-waited-systemd-job`. This was a text-label defect only:
their immutable raw command receipts and `meta/suspend-dispatch.json` files
show the direct Armada dispatcher path, and no existing run archive or ID is
being rewritten. New receipts use `...-waited-dispatcher-job`.

## Experiments

### 2026-09-01 — harness preflight and target identity

Before a suspend attempt, the target was verified by SSH and non-destructive
inventory. It reported the Nova model/compatible strings above, kernel
`7.2.0-rc7`, `[s2idle] deep`, `/etc/armada/sleep.conf=suspend_mode=s2idle`,
internal root on `/dev/sda20`, and a mounted microSD at `/run/media/armada/sd`.
CPU0 `cpu-sleep-0-0` was disabled while awake; the corresponding SM8550 sleep
hook is expected to enable it only inside a real suspend window. Wi-Fi and
Bluetooth were initially enabled/unblocked. No physical change was required
after this inventory beyond keeping the requested no-cable/no-input state.

### 2026-09-01 14:28 UTC — preflight failure, no suspend

- Run: `20260901T142834Z-7123ecd62ba8`
- Request: explicit `s2idle`, Wi-Fi off, Bluetooth off, RTC wake in 45 seconds.
- Observation: the run stopped before arming/suspending because the first
  harness version passed `disabled` to `nmcli radio wifi` instead of its
  accepted `off` value. The exact remote error was `invalid 'wifi' argument:
  'disabled' (use on/off)`.
- Device effect: no suspend was attempted and no physical device action was
  needed. The run archive is retained, including the partial retrieval
  quarantine, as failure provenance.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T142834Z-7123ecd62ba8`.
- Follow-up: fixed the command mapping and verified the host/device archive
  path with the narrow sudo rule.

### 2026-09-01 14:31 UTC — first actual s2idle, boundary bug discovered

- Run: `20260901T143106Z-2221133205fa`
- Request: explicit `s2idle`, Wi-Fi off, Bluetooth off, 45-second RTC wake.
- Observation: raw kernel evidence shows the Nova entered
  `PM: suspend entry (s2idle)` and exited about 45 seconds later, with the
  boot ID unchanged and the kernel success counter incremented. However,
  `systemctl suspend` returned immediately to the lab process; its post
  snapshot and clock receipt were captured before the actual suspend completed.
  The old derived receipt consequently showed only `0.000001` clock-proven
  seconds and incorrectly called the run successful.
- Wake evidence: the first receipt saw an unchanged/stale `pm_wakeup_irq=21`
  (`pmic_pwrkey`) while the RTC IRQ and RTC wakeup-source counters also
  changed. The old broad text match was not trustworthy.
- Device health: `armada-powerd` watchdog timeout/core dump was present in the
  later journal, along with RCU-stall/journal-loss evidence.
- Device effect: the device resumed without reboot; radio state was restored.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T143106Z-2221133205fa`.
- Follow-up: changed the harness to wait on the actual oneshot service and to
  report IRQ, interrupt, and wakeup-source evidence separately.

### 2026-09-01 14:40 UTC — waited s2idle, mode-semantics bug discovered

- Run: `20260901T144034Z-836df46368b1`
- Request: same explicit `s2idle`/off-radio/45-second baseline, now using
  `systemctl start --wait systemd-suspend.service`.
- Observation: the waited systemd job took `46.293496` seconds; the device
  entered/exited s2idle, boot ID stayed unchanged, the success counter rose by
  one, and RTC IRQ 199 plus the RTC wakeup source changed. Both clocks
  advanced by about 46.3 seconds, which is expected for s2idle—not evidence
  that no suspend occurred.
- Device health: the same `armada-powerd` watchdog failure reproduced.
- Device effect: resumed without reboot; radio state was restored.
- Harness effect: the new deep-style clock-only gate marked this valid s2idle
  run failed. No device defect was inferred from that harness result.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T144034Z-836df46368b1`.
- Follow-up: made the verdict mode-aware and added explicit kernel-marker and
  waited-job metrics.

### 2026-09-01 14:43 UTC — baseline A, valid s2idle

- Run: `20260901T144353Z-5bec2b5d5aa1`
- Request: explicit `s2idle`, Wi-Fi off, Bluetooth off, no external cable,
  no user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `s2idle`; waited job
  `46.671013` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`; RTC IRQ 199 (`pm8xxx_rtc_alarm`) delta `+1`; RTC wakeup source
  `c400000.spmi:pmic@0:rtc@6100` active/event deltas `+1/+1`.
- Power/depth: AOSD, CXSD, and DDR counters remained at zero; ADSP count
  delta was `+225`. CPU1-7 s2idle state counters advanced for roughly 44.47
  seconds, while CPU0 `cpu-sleep-0-0` remained disabled/unused in the awake
  snapshot model.
- Resume health: the journal recorded an `armada-powerd.service` watchdog
  timeout and failure, two `rsinput serial1-0: Checksum mismatch` lines, and
  kernel-message loss around resume. The harness still found all 10 input
  devices present, the internal DSI display connected/enabled, no failed
  systemd units at health capture, and no reboot. Functional gamepad,
  display/touch, audio, USB, Wi-Fi, Bluetooth, Steam, and gamescope tests were
  not run.
- Device effect: Wi-Fi and Bluetooth were restored to their pre-run enabled /
  unblocked / powered-on state by cleanup.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T144353Z-5bec2b5d5aa1`;
  summary is under `device/derived/summary.json` and raw evidence under
  `device/raw/`.
- Interpretation: current Armada can complete a timer-woken s2idle cycle, but
  it does not reach the observed AOSD/CXSD/DDR counters and has a repeatable
  powerd/watchdog resume-health problem during this 45-second s2idle setup.

### 2026-09-01 14:47 UTC — baseline B, valid deep

- Run: `20260901T144700Z-fb2eea03ed31`
- Request: explicit `deep`, Wi-Fi off, Bluetooth off, same no-cable/no-input
  condition, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `deep`; waited systemd job
  `2.343243` seconds; clock-separated suspended interval
  `44.314054` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`. The short job duration is expected because the monotonic clock
  does not advance through deep suspend.
- Wake evidence: RTC IRQ 199 delta `+1` and RTC wakeup-source active/event
  deltas `+1/+1`; `pm_wakeup_irq` remained 199 before/after, so the receipt
  labels the primary sysfs value as unchanged rather than treating it as a
  fresh IRQ transition.
- Power/depth: AOSD, CXSD, and DDR counters remained at zero; ADSP count
  delta was `+188`. No reboot was observed.
- Resume health: this run did not produce the powerd/watchdog or rsinput
  errors found in the s2idle baselines; the harness still did not perform
  functional subsystem tests.
- Device effect: Wi-Fi and Bluetooth were restored by cleanup.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T144700Z-fb2eea03ed31`.
- Interpretation: the current image completes an RTC-woken deep suspend and
  resumes cleanly at the coarse health gate, but the available Qualcomm stats
  still show no AOSD/CXSD/DDR residency. This is an observation, not yet a
  reason to import Thor/PockNix patches.

The first deep receipt's battery-rate derivation used the short post-resume
systemd-job duration and therefore overstated current. The harness now uses
the boottime wall interval for battery-rate derivation; no battery-rate number
from that first deep receipt will be used for comparison.

### 2026-09-01 14:51 UTC — baseline C, Bluetooth on s2idle

- Run: `20260901T145153Z-8e6d1986f36c`
- Request: explicit `s2idle`, Bluetooth on, Wi-Fi off, no external cable,
  no user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `s2idle`; waited job
  `46.566521` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`; RTC IRQ 199 delta `+1`; RTC wakeup-source active/event deltas
  `+1/+1`.
- Radio observation: Bluetooth was still powered and unblocked at the post
  health capture; Wi-Fi was disabled as requested. Cleanup restored the
  original Wi-Fi state.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+188`. The same CPU s2idle pattern and no observed CPU0 `cpu-sleep-0-0`
  residency remained.
- Resume health: `armada-powerd.service` again hit its 15-second watchdog;
  gamescope also logged a touchscreen event-processing lag of about 46.1
  seconds. The input inventory still contained all 10 devices, but this is a
  functional-health warning requiring a later direct touch/gamepad check.
- Device effect: no reboot; Wi-Fi/Bluetooth state was restored by cleanup.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T145153Z-8e6d1986f36c`.
- Interpretation: keeping Bluetooth powered did not prevent this short s2idle
  cycle, but it did not alter the missing AOSD/CXSD/DDR counters or the
  repeatable s2idle resume-health warnings.

### 2026-09-01 14:53 UTC — baseline D, Wi-Fi on s2idle

- Run: `20260901T145347Z-5bd093b36a95`
- Request: explicit `s2idle`, Wi-Fi on, Bluetooth off, no external cable,
  no user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `s2idle`; waited job
  `46.764753` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`; RTC IRQ 199 delta `+1`; RTC wakeup-source active/event deltas
  `+2/+2`.
- Radio observation: Wi-Fi was enabled and the `wlp1s0` link was up at the
  post health capture. Bluetooth was intentionally blocked. Cleanup left the
  original enabled/unblocked radio state intact.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+209`; the same lack of observed CPU0 deep s2idle residency remained.
- Resume health: `armada-powerd.service` again hit its 15-second watchdog.
  All 10 input devices remained present and the internal DSI display was
  connected/enabled. This run did not reproduce C's gamescope touchscreen-lag
  line, but the functional input gate is still pending.
- Device effect: no reboot; Wi-Fi and Bluetooth were restored/left in their
  original state by cleanup.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T145347Z-5bd093b36a95`.
- Interpretation: Wi-Fi being enabled at suspend entry did not prevent the
  s2idle cycle or change the missing Qualcomm low-power-domain counters; the
  powerd watchdog behavior remains s2idle-associated.

### 2026-09-01 14:55 UTC — baseline E, normal Armada policy

- Run: `20260901T145520Z-7f85d0048651`
- Request: `--mode policy`, both radios preserved, no external cable, no user
  input, 45-second RTC wake.
- Result: `suspend_success=true`; the installed policy resolved to observed
  `s2idle`; waited job `46.408543` seconds; boot ID unchanged; suspend success
  delta `+1`, failure delta `0`; RTC IRQ 199 delta `+1`; RTC wakeup-source
  active/event deltas `+1/+1`.
- Radio observation: Wi-Fi was enabled with `wlp1s0` up, and Bluetooth was
  powered/unblocked at post capture. This confirms the explicit s2idle mode
  was not required to make the current user-facing policy enter real s2idle.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+210`; CPU1-7 s2idle residency continued while CPU0's deep state remained
  unused in the captured window.
- Resume health: `armada-powerd.service` again hit its 15-second watchdog;
  input count remained 10 and the internal DSI display remained connected and
  enabled. No reboot occurred and no additional functional gate was run.
- Device effect: no persistent policy or radio change; cleanup preserved the
  pre-run radio state.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T145520Z-7f85d0048651`.
- Interpretation: the normal Armada policy on this install is currently a
  working timer-woken s2idle path, but the same missing low-power-domain
  counters and powerd watchdog behavior remain.

### 2026-09-01 14:56 UTC — repeat F, s2idle/off-radio

- Run: `20260901T145657Z-ab63c6967007`
- Request: explicit `s2idle`, Wi-Fi off, Bluetooth off, no external cable,
  no user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `s2idle`; waited job
  `46.510413` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`; RTC IRQ 199 delta `+1`; RTC wakeup-source active/event deltas
  `+1/+1`.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+206`; CPU1-7 s2idle residency continued while CPU0's deep state remained
  unused in the captured window.
- Resume health: `armada-powerd.service` again hit its 15-second watchdog.
  The 10-device input inventory and internal DSI display inventory remained
  present; no reboot occurred and no functional gate was run.
- Device effect: Wi-Fi and Bluetooth were restored by cleanup.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T145657Z-ab63c6967007`.
- Interpretation: this repeat reinforces that the explicit off-radio s2idle
  path is reliable at the coarse suspend gate but does not reach the observed
  Qualcomm AOSD/CXSD/DDR counters and continues to trigger the powerd
  watchdog-health issue.

### 2026-09-01 14:58 UTC — repeat G, deep/off-radio

- Run: `20260901T145840Z-89aefa2cd598`
- Request: explicit `deep`, Wi-Fi off, Bluetooth off, no external cable, no
  user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `deep`; waited job
  `2.252502` seconds; clock-separated suspended interval `44.382355` seconds;
  boot ID unchanged; suspend success delta `+1`, failure delta `0`; RTC IRQ
  199 delta `+1`; RTC wakeup-source active/event deltas `+1/+1`.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+191`. The corrected charge-counter estimate used the `46.654073` second
  boottime interval and was approximately `244 mA`.
- Resume health: no watchdog, rsinput, failed-unit, or inventory-loss error
  was reported by the coarse health capture; the functional gates remain
  pending. No reboot occurred.
- Device effect: Wi-Fi and Bluetooth were restored by cleanup.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T145840Z-89aefa2cd598`.
- Interpretation: deep suspend remains reproducible and cleaner than the
  45-second s2idle path at the coarse health gate, but the available Qualcomm
  low-power-domain counters still do not show AOSD/CXSD/DDR residency.

### 2026-09-01 15:00 UTC — repeat H, Bluetooth-on s2idle

- Run: `20260901T150031Z-abf77a9a349b`
- Request: explicit `s2idle`, Bluetooth on, Wi-Fi off, no external cable, no
  user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `s2idle`; waited job
  `46.423561` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`; RTC IRQ 199 delta `+1`; RTC wakeup-source active/event deltas
  `+1/+1`.
- Radio observation: Bluetooth was powered/unblocked at post capture; Wi-Fi
  was intentionally disabled. Cleanup restored the original radio state.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+215`; CPU1-7 s2idle residency continued and CPU0 deep state remained
  unused in the captured awake/suspend model.
- Resume health: the powerd 15-second watchdog failure reproduced. The input
  and display inventories remained present; no reboot occurred and no
  functional gate was run.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T150031Z-abf77a9a349b`.
- Interpretation: the Bluetooth-on variant is repeatable and does not explain
  the missing Qualcomm low-power-domain counters; the s2idle powerd watchdog
  remains independent of this radio variant.

### 2026-09-01 15:02 UTC — repeat I, Wi-Fi-on s2idle

- Run: `20260901T150249Z-2b9c27538a3e`
- Request: explicit `s2idle`, Wi-Fi on, Bluetooth off, no external cable, no
  user input, 45-second RTC wake.
- Result: `suspend_success=true`; observed mode `s2idle`; waited job
  `46.081041` seconds; boot ID unchanged; suspend success delta `+1`, failure
  delta `0`; RTC IRQ 199 delta `+1`; RTC wakeup-source active/event deltas
  `+1/+1`.
- Radio observation: Wi-Fi was enabled and `wlp1s0` was up at post capture;
  Bluetooth was intentionally blocked. Cleanup restored the original state.
- Power/depth: AOSD, CXSD, and DDR remained at zero; ADSP count delta was
  `+220`; the CPU s2idle/CPU0 pattern remained unchanged.
- Resume health: the powerd 15-second watchdog failure reproduced. All 10
  input devices and the internal DSI display remained present; no touchscreen
  lag line or reboot was observed, and no functional gate was run.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T150249Z-2b9c27538a3e`.
- Interpretation: the Wi-Fi-on repeat remains a reliable s2idle cycle and
  does not explain the missing Qualcomm low-power-domain counters; the
  s2idle watchdog finding persists.

## 2026-09-01 supported update boundary

The historical-control phase ended before the update. The selected Armada
channel was changed only through the shipped `steamos-select-branch` hook and
the image was staged only through `steamos-update`; the deployment was applied
through bootc's supported `--from-downloaded --apply` operation. No kernel,
boot image, ABL, or partition was manually replaced.

The post-update preflight at
`/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T152929Z-35f46c0021d0.json`
shows the booted signed image as Armada `20260830.71e45aa`, digest
`sha256:cae66b751f6376c7a2da84e7bca7fa81293e9689f7cc9b6bd682ebe83d852c25`,
with rollback retained as the historical beta image
`20260817.8b49045` / digest
`sha256:275a67b09e6c60fcd3148e09a2b954bbae3b6105725273caeff880247fa0441d`.
The boot ID changed from the historical control's
`cb38c234-b832-48f7-8519-9c73dbc930ef` to
`be074ba4-8dc3-43e0-ac75-77257f38a7fe`; no deployment remained staged.

The current image reports kernel `7.2.0` (`Linux fedora 7.2.0 #1 SMP PREEMPT
Sun Aug 30 15:09:15 UTC 2026 aarch64`), still identifies the same Nova/SM8550
DT compatibles, and still reports `[s2idle] deep` with
`suspend_mode=s2idle`. Relevant package changes include bootc `1.16.10`,
Terra gamescope `137.13e1dd19`, updated gamescope-session packages, and the
new `armada-rgb` package. The current device-env now has empty primary display
connector fields and explicit RGB targets, so those values must be treated as
current-image baseline facts rather than inherited from the old image.

The preflight had no command failures. This is the point at which the new
current-image Phase 2 baseline begins; none of the earlier suspend receipts
are counted as current-image baseline data.

### 2026-09-01 15:35 UTC — current-image baseline A, direct-dispatch s2idle/off-radio

- Run: `20260901T153527Z-a7399e37863d`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `s2idle`, Wi-Fi off, Bluetooth off, 45-second RTC wake. The pre/post boot ID
  was unchanged at `be074ba4-8dc3-43e0-ac75-77257f38a7fe`; current mem-sleep
  remained `[s2idle] deep` and the Nova/SM8550 DT identity was unchanged.
- Physical condition: no USB/charger/dock/hub, no user input, microSD left
  mounted, device awake before launch. The device had been moved closer to the
  router; no other manual action was taken. SSH loss occurred while radios
  were disabled and was expected.
- Exact suspend path: the autonomous root-owned unit invoked
  `/usr/libexec/armada/suspend-dispatch` with run-local
  `ARMADA_SUSPEND_MODE=s2idle` and `ARMADA_SLEEP_CONFIG`; the command returned
  zero after `2.371608` seconds. The raw stderr says systemd froze the user
  slice, performed the suspend operation, returned, and thawed the slice.
  No direct `systemd-suspend.service` start was used.
- Clock evidence: `CLOCK_BOOTTIME` delta `46.796019` seconds minus
  `CLOCK_MONOTONIC` delta `2.381174` seconds gives signed separation
  `44.414845` seconds, status `observed`. This is independent of the kernel
  markers: `PM: suspend entry (s2idle)` and `PM: suspend exit` were both
  present. `suspend_stats` independently changed from success `0`, fail `0`
  to success `1`, fail `0`.
- Wake/depth: the expected RTC source fired: IRQ 200
  (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta `+1`, and
  `c400000.spmi:pmic@0:rtc@6100` wakeup-source active/event deltas `+1/+1`.
  AOSD, CXSD, and DDR count deltas were all `0`; ADSP count delta was `+290`.
  CPU0's `cpu-sleep-0-0` s2idle counters became visible in this current image
  run (`usage +24`, `time +933` in the captured counter units), while the
  other CPU sleep-state counters also advanced.
- Resume health: `suspend_success=true`, boot survived without reset, no
  systemd failed units, and no new error-like log lines. Ten input devices
  remained present and internal `DSI-1` remained connected/enabled. Steam and
  gamescope processes were present, but no functional gamepad, touch, audio,
  Steam UI, or game test was run. `lsusb` is not installed on the device, so
  USB enumeration was not assessed by this receipt.
- Cleanup: Wi-Fi and Bluetooth rfkill state were restored. The first
  `bluetoothctl power on` cleanup attempt returned `org.bluez.Error.Busy`, but
  the subsequent read-only check confirmed Wi-Fi enabled/up, Bluetooth
  unblocked and powered on. This cleanup transient is retained as evidence;
  no persistent radio change remains.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T153527Z-a7399e37863d`;
  checksum verification covered `4241` files with no mismatches.
- Interpretation: this is the first valid current-image s2idle baseline
  receipt. It demonstrates real RTC-woken s2idle through Armada's supported
  dispatcher with clock separation and kernel/stat evidence, while the zero
  AOSD/CXSD/DDR counters and elevated ADSP delta remain observations, not a
  causal diagnosis. No kernel patch has been made.

### 2026-09-01 15:38 UTC — current-image baseline B, direct-dispatch deep/off-radio

- Run: `20260901T153837Z-528c7ba0975a`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `deep`, Wi-Fi off, Bluetooth off, 45-second RTC wake. The pre/post boot ID
  remained `be074ba4-8dc3-43e0-ac75-77257f38a7fe`; the Nova/SM8550 DT identity
  and `[s2idle] deep` availability were unchanged.
- Physical condition: same no-USB/charger/dock/hub, no-input, microSD-mounted
  condition as baseline A. No manual device action was taken between runs;
  Wi-Fi and Bluetooth were controlled only inside the autonomous run.
- Exact suspend path: the root-owned agent invoked
  `/usr/libexec/armada/suspend-dispatch` with run-local
  `ARMADA_SUSPEND_MODE=deep` and `ARMADA_SLEEP_CONFIG`; it returned zero after
  `2.245466` seconds. The dispatcher stderr again records the freeze,
  suspend, return, and thaw sequence. No direct `systemd-suspend.service`
  start was used.
- Clock evidence: `CLOCK_BOOTTIME` delta `46.618300` seconds minus
  `CLOCK_MONOTONIC` delta `2.263929` seconds gives signed separation
  `44.354371` seconds, status `observed`. Independent kernel evidence shows
  `PM: suspend entry (deep)` and `PM: suspend exit`. Independent
  `suspend_stats` changed from success `1`, fail `0` to success `2`, fail `0`.
- Wake/depth: the expected RTC fired through IRQ 200
  (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta `+1`, and the RTC
  wakeup-source active/event deltas were `+1/+1`. AOSD, CXSD, and DDR count
  deltas were all `0`; ADSP count delta was `+182`. The deep run's s2idle
  residency fields were zero for the CPU sleep states, while generic cpuidle
  usage counters advanced.
- Resume health: `suspend_success=true`, no reset, no systemd failed units,
  and no new error-like log lines. Ten input devices remained present and
  internal `DSI-1` remained connected/enabled. Steam and gamescope processes
  were present, but no functional gamepad, touch, audio, Steam UI, or game
  test was run. `lsusb` remains unavailable on-device, so USB enumeration was
  not assessed by this receipt.
- Cleanup: the recorded BlueZ power-on action again returned
  `org.bluez.Error.Busy` while restoring the per-run off state, but the
  subsequent read-only check confirmed Wi-Fi enabled/up and Bluetooth
  unblocked/powered on. The transient cleanup result is retained; no
  persistent radio change remains.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T153837Z-528c7ba0975a`.
- Interpretation: this is a valid current-image deep baseline paired with A.
  Both modes reach the requested kernel path and wake from the expected RTC,
  but neither produces nonzero AOSD/CXSD/DDR counters. The ADSP deltas differ
  between the two single cycles, so they are not yet a diagnosis. No kernel
  patch has been made.

### 2026-09-01 15:40 UTC — current-image baseline C, Bluetooth-on s2idle/off-Wi-Fi

- Run: `20260901T154048Z-4f8b83e02e0f`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `s2idle`, Bluetooth on, Wi-Fi off, 45-second RTC wake. The boot ID remained
  `be074ba4-8dc3-43e0-ac75-77257f38a7fe`; mem-sleep stayed `[s2idle] deep`.
- Physical condition: unchanged no-cable/no-input/microSD-mounted condition;
  no manual device action. Wi-Fi was disabled only inside the run, so SSH
  loss was expected. Bluetooth was left powered by the experiment policy.
- Exact suspend path: the autonomous root-owned agent invoked
  `/usr/libexec/armada/suspend-dispatch` with run-local s2idle environment;
  it returned zero after `2.087467` seconds. No direct
  `systemd-suspend.service` start was used.
- Clock evidence: `CLOCK_BOOTTIME` delta `46.190723` seconds minus
  `CLOCK_MONOTONIC` delta `2.115305` seconds gives signed separation
  `44.075419` seconds, status `observed`. Kernel markers independently show
  `PM: suspend entry (s2idle)` and `PM: suspend exit`. `suspend_stats`
  independently changed from success `2`, fail `0` to success `3`, fail `0`.
- Wake/depth: RTC IRQ 200 (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta
  `+1` and RTC wakeup-source active/event deltas `+1/+1`; the PM wakeup IRQ
  remained 200 and no competing wake source was recorded. AOSD, CXSD, and
  DDR count deltas remained `0`; ADSP count delta was `+181`.
- Resume health: `suspend_success=true`, no reset, no failed systemd units,
  and no new error-like log lines. Bluetooth was powered/on in the post
  snapshot, Wi-Fi was disabled as requested, ten input devices remained
  present, and internal `DSI-1` remained connected/enabled. Steam/gamescope
  processes were present; no functional gamepad, touch, audio, Steam UI, or
  game test was run. `lsusb` is unavailable, so USB enumeration was not
  assessed.
- Cleanup: Wi-Fi was restored successfully; Bluetooth was not changed because
  it was already on. A subsequent read-only check confirmed both radios
  enabled/unblocked/on.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T154048Z-4f8b83e02e0f`.
- Interpretation: Bluetooth-on did not prevent a valid current-image s2idle
  cycle or alter the RTC wake classification in this single run. The
  low-power-domain counters remain zero, and the modest ADSP delta is only an
  observation pending repeated samples. No kernel patch has been made.

### 2026-09-01 15:42 UTC — current-image baseline D, Wi-Fi-on s2idle/off-Bluetooth

- Run: `20260901T154249Z-b22ef7622799`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `s2idle`, Wi-Fi on, Bluetooth off, 45-second RTC wake. The boot ID remained
  `be074ba4-8dc3-43e0-ac75-77257f38a7fe`; the requested and observed modes
  matched.
- Physical condition: unchanged no-cable/no-input/microSD-mounted condition;
  no manual action. Wi-Fi remained available as the requested radio variable,
  although SSH still timed out during the suspend interval. Bluetooth was
  blocked only inside the run.
- Exact suspend path: the autonomous root-owned agent invoked
  `/usr/libexec/armada/suspend-dispatch` with run-local s2idle environment;
  it returned zero after `2.231535` seconds. No direct
  `systemd-suspend.service` start was used.
- Clock evidence: `CLOCK_BOOTTIME` delta `45.873797` seconds minus
  `CLOCK_MONOTONIC` delta `2.237828` seconds gives signed separation
  `43.635969` seconds, status `observed`. Kernel markers independently show
  `PM: suspend entry (s2idle)` and `PM: suspend exit`. `suspend_stats`
  independently advanced by success `+1` with failure delta `0`.
- Wake/depth: RTC IRQ 200 (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta
  `+1` and RTC wakeup-source active/event deltas `+1/+1`; PM wakeup IRQ stayed
  200 with no competing wake source recorded. AOSD, CXSD, and DDR count
  deltas were all `0`; ADSP count delta was `+182`.
- Resume health: `suspend_success=true`, no reset, no failed systemd units,
  and no new error-like log lines. Wi-Fi was enabled/up in the post snapshot;
  Bluetooth was off/blocked as requested. Ten input devices remained present
  and internal `DSI-1` remained connected/enabled. Steam/gamescope processes
  were present, but no functional gamepad, touch, audio, Steam UI, or game
  test was run. `lsusb` is unavailable, so USB enumeration was not assessed.
- Cleanup: Wi-Fi restoration succeeded and Bluetooth rfkill/power state was
  restored; a read-only follow-up confirmed Wi-Fi enabled/up and Bluetooth
  enabled, unblocked, and powered on.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T154249Z-b22ef7622799`.
- Interpretation: Wi-Fi-on/Bluetooth-off did not prevent a valid current-image
  s2idle cycle or change the expected RTC wake classification in this sample.
  The zero low-power-domain counters persist. No kernel patch has been made.

### 2026-09-01 15:44 UTC — current-image policy sample retained from prior run

- Run: `20260901T154437Z-64317bfc6a02`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, Armada
  `policy`, radios preserved, 45-second RTC wake. Policy selected and
  observed `s2idle`; the boot ID remained unchanged. This completed sample was
  present in the archive before the later notebook reconciliation and is
  documented here without rewriting its receipt.
- Physical condition: no cable, charger, dock, hub, or user input; microSD
  remained inserted and mounted. No manual device action was recorded.
- Exact path: the root-owned agent invoked
  `/usr/libexec/armada/suspend-dispatch` and received return code `0` after
  `2.342269` seconds.
- Clock/evidence: signed clock separation was `43.911823` seconds and status
  `observed`; kernel policy/s2idle entry and exit markers were present.
  `suspend_stats` advanced from success `4`, fail `0` to success `5`, fail
  `0`. RTC IRQ 200 advanced by one and the matching wakeup source advanced
  active/event by `+1/+1`.
- Qualcomm/depth: AOSD, CXSD, and scalar DDR count/duration deltas were zero;
  ADSP count delta was `+197`. No new error-like log lines or failed systemd
  units were observed; ten inputs remained present and `DSI-1` remained
  connected/enabled.
- Aggregate IRQ observation: IRQ 169 (`ufshcd`) increased by `10,509` and
  mmc0 by `47` between the pre/post snapshots. As established by the later
  trace, these are aggregate pre/post-window values rather than proven
  in-suspend rates; the low mmc0 delta does not support the historical SDHCI
  storm.
- Cleanup: no radio state needed restoration because policy preserved it; the
  RTC and temporary diagnostic controls were restored. The archive checksum
  verification covered `4,226` files with no mismatches.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T154437Z-64317bfc6a02`.
- Interpretation: this is an additional clean current-image policy sample,
  not a new candidate-fix experiment. It contributes to the reliability
  evidence and preserves the same zero AOSD/CXSD/DDR result; no kernel patch
  was made.

### 2026-09-01 15:46 UTC — current-image baseline E, Armada policy/preserve-radio

- Run: `20260901T154633Z-016dc93da017`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, Armada
  `policy`, both radios preserved, 45-second RTC wake. Policy selected and
  observed `s2idle`; the boot ID remained
  `be074ba4-8dc3-43e0-ac75-77257f38a7fe` and mem-sleep remained
  `[s2idle] deep`.
- Physical condition: unchanged no-cable/no-input/microSD-mounted condition;
  no manual action was taken. Both Wi-Fi and Bluetooth were enabled/up/on
  before and after the run, and SSH loss during the suspend interval was
  expected.
- Exact suspend path: with no transient mode environment override, the
  autonomous root-owned agent invoked the shipped
  `/usr/libexec/armada/suspend-dispatch`; it returned zero after `2.318356`
  seconds. No direct `systemd-suspend.service` start was used.
- Clock evidence: `CLOCK_BOOTTIME` delta `46.539722` seconds minus
  `CLOCK_MONOTONIC` delta `2.345078` seconds gives signed separation
  `44.194644` seconds, status `observed`. Kernel markers independently show
  `PM: suspend entry (s2idle)` and `PM: suspend exit`. `suspend_stats`
  independently advanced from success `5`, fail `0` to success `6`, fail `0`.
- Wake/depth: RTC IRQ 200 (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta
  `+1` and RTC wakeup-source active/event deltas `+1/+1`; PM wakeup IRQ stayed
  200 with no competing wake source recorded. AOSD, CXSD, and DDR count
  deltas were all `0`; ADSP count delta was `+184`.
- Resume health: `suspend_success=true`, no reset, no failed systemd units,
  and no new error-like log lines. Wi-Fi was enabled/up and Bluetooth was
  powered/on; ten input devices remained present and internal `DSI-1` remained
  connected/enabled. Steam/gamescope processes were present, but no
  functional gamepad, touch, audio, Steam UI, or game test was run. `lsusb`
  is unavailable, so USB enumeration was not assessed.
- Cleanup: no radio cleanup was necessary because policy preserved the
  existing state. A follow-up read-only check confirmed both radios remained
  enabled, unblocked, and powered on.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T154633Z-016dc93da017`.
- Interpretation: Armada's normal policy currently resolves to the same
  real s2idle path measured by the explicit runs. This fifth current-image
  cycle is valid and reinforces RTC-woken s2idle, but the zero low-power-domain
  counters remain unexplained. No kernel patch has been made.

### 2026-09-01 15:48 UTC — current-image repeat F, s2idle/off-radio

- Run: `20260901T154832Z-8a5193ddaeb5`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `s2idle`, Wi-Fi off, Bluetooth off, 45-second RTC wake. The boot ID was
  unchanged and the dispatcher observed the requested mode.
- Physical condition: unchanged no-cable/no-input/microSD-mounted condition;
  no manual device action. SSH loss was expected while both radios were off.
- Exact path: the autonomous root-owned agent invoked
  `/usr/libexec/armada/suspend-dispatch` with run-local s2idle environment and
  received return code zero after `2.219483` seconds.
- Clock evidence: `CLOCK_BOOTTIME` delta `46.493743` seconds minus
  `CLOCK_MONOTONIC` delta `2.244774` seconds gives signed separation
  `44.248969` seconds, status `observed`. Kernel entry/exit markers were
  present. `suspend_stats` advanced independently from success `6`, fail `0`
  to success `7`, fail `0`.
- Wake/depth: RTC IRQ 200 (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta
  `+1` and RTC wakeup-source active/event deltas `+1/+1`; PM wakeup IRQ stayed
  200 with no competing wake source. AOSD, CXSD, and DDR count deltas were
  `0`; ADSP count delta was `+182`.
- Resume health: `suspend_success=true`, no reset, no new error-like log
  lines, ten inputs present, and internal `DSI-1` connected/enabled. Steam and
  gamescope processes were present; no functional gamepad, touch, audio,
  Steam UI, game, or USB test was run (`lsusb` is unavailable). The post
  snapshot correctly showed Wi-Fi disabled and Bluetooth off/blocked.
- Cleanup: Wi-Fi and Bluetooth were restored. The recorded BlueZ power-on
  action returned `org.bluez.Error.Busy` transiently, but the follow-up
  read-only check confirmed Wi-Fi enabled/up and Bluetooth enabled,
  unblocked, and powered on.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T154832Z-8a5193ddaeb5`.
- Interpretation: the first independent repeat of current baseline A
  reproduces real s2idle, expected RTC wake, and zero low-power-domain
  counters. The repeated ADSP delta is an observation only; no kernel patch
  has been made.

### 2026-09-01 15:50 UTC — current-image repeat G, deep/off-radio

- Run: `20260901T155052Z-87c9c373b27c`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `deep`, Wi-Fi off, Bluetooth off, 45-second RTC wake. The boot ID remained
  `be074ba4-8dc3-43e0-ac75-77257f38a7fe`; requested and observed modes
  matched.
- Physical condition: unchanged no-cable/no-input/microSD-mounted condition;
  no manual device action. SSH loss was expected while both radios were off.
- Exact path: the autonomous root-owned agent invoked
  `/usr/libexec/armada/suspend-dispatch` with run-local deep environment and
  received return code zero after `2.457125` seconds.
- Clock evidence: `CLOCK_BOOTTIME` delta `45.846394` seconds minus
  `CLOCK_MONOTONIC` delta `2.477252` seconds gives signed separation
  `43.369142` seconds, status `observed`. Kernel deep entry/exit markers were
  present. `suspend_stats` advanced independently from success `7`, fail `0`
  to success `8`, fail `0`.
- Wake/depth: RTC IRQ 200 (`pmic_arb 6431283 Edge pm8xxx_rtc_alarm`) delta
  `+1`; the matching RTC wakeup source reported active/event deltas `+2/+2`
  in this archive. PM wakeup IRQ stayed 200 and no competing source was
  recorded. AOSD, CXSD, and DDR count deltas were `0`; ADSP count delta was
  `+180`.
- Resume health: `suspend_success=true`, no reset, no new error-like log
  lines, ten inputs present, and internal `DSI-1` connected/enabled. Steam and
  gamescope processes were present; no functional gamepad, touch, audio,
  Steam UI, game, or USB test was run (`lsusb` is unavailable). The post
  snapshot showed both radios disabled/blocked during the requested window.
- Cleanup: Wi-Fi and Bluetooth were restored; a follow-up read-only check
  confirmed Wi-Fi enabled/up and Bluetooth enabled, unblocked, and powered on.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T155052Z-87c9c373b27c`;
  checksum verification covered `4241` files with no mismatches.
- Interpretation: this independent deep repeat is valid and preserves the
  qualitative result already established by A/B: real deep sleep, RTC wake,
  clock separation, and zero AOSD/CXSD/DDR delta. The ten-cycle reliability
  objective remains open; blind repeats are paused here for the requested
  forensic differential. No kernel patch has been made.

## 2026-09-01 16:10 UTC — read-only A/B forensic differential

- Scope: completed without rerunning A or B and without changing device state.
  Compared current-image off-radio s2idle A
  (`20260901T153527Z-a7399e37863d`) with paired off-radio deep B
  (`20260901T153837Z-528c7ba0975a`). Run G
  (`20260901T155052Z-87c9c373b27c`) had already completed normally and remains
  preserved; blind repeats are paused at seven clean current-image cycles.
- Qualcomm stats: both archives contain all 17 `/sys/kernel/debug/qcom_stats`
  filenames in pre/post captures, with exact raw files retained. `aosd`,
  `cxsd`, and scalar `ddr` remained absolute zero in both modes, while ADSP,
  APSS, CDSP, and separate `ddr_stats` data changed. The Linux 7.2
  implementation and current Armada sleep-debug semantics classify this as
  valid named-state zero evidence, not a wrong parser or presumed dead
  firmware. `ddr_stats` is a separate export and was not collapsed into the
  scalar `ddr` result.
- Interrupts: all 126 IRQ IDs were compared. A had 34 nonzero rows / 44,150
  positive events; B had 33 / 40,886. UFS IRQ 169 (`ufshcd`) measured
  287.426/s in A and 240.179/s in B after normalization by signed suspended
  seconds. `mmc0` measured only 1.126/s and 1.172/s, so the historical
  tens-per-second SDHCI symptom was not present.
- Runtime-PM: UFS controller/host/target and root LUN remained active in the
  snapshots; PCIe and ath12k endpoint were active with `control=on`; combo PHY
  `88e8000.phy` was active/on. DWC3 was suspended pre and active post, with no
  attached UDC/xHCI device. No runtime usage-count field was available in any
  captured record. Kernel PM callbacks for UFS, DWC3/PHY, SDHCI, PCIe/WLAN,
  remoteproc, and display returned zero.
- Clocks/regulators: complete clk/regulator summaries were present in A/B
  pre/post; no interconnect summary was available in the archives or live
  debugfs. UFS and PCIe consumers were referenced; USB3 combo-PHY clocks and
  regulators appeared in post-resume state. No in-suspend vote value was
  captured.
- ADSP/audio: ADSP count is a firmware subsystem low-power-entry statistic,
  not an audio PCM count. All captured PCM status files were `closed`, DAPM
  was Off except HDMI codec Standby, and Armada reported approximately 99%
  ADSP sleep over its coarse diagnostic window. Audio is not a supported
  primary blocker from this evidence.
- Result: the complete forensic analysis, ranked hypotheses, unknowns, raw
  archive paths, and exactly one recommended next experiment are in
  `research/sm8550-suspend-lab/current-image-forensic-differential.md`.
  No kernel or package patch was made, and no SDHCI/USB/runtime-PM/control
  value was changed.

## 2026-09-01 16:28 UTC — current-stock deep UFS IRQ/PM trace experiment

- Run: `20260901T162647Z-5c6d44f7dcf7`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `deep`, Wi-Fi off, Bluetooth off, 45-second RTC wake, microSD left inserted
  and mounted. The boot ID stayed unchanged. No kernel, package, firmware,
  SDHCI, runtime-PM control, or power-policy value was changed.
- Physical condition: no cable, dock, hub, charger, or user input; no manual
  device action was required. SSH loss during the sleep interval was expected.
- Exact path: the root-owned detached agent armed the RTC, created a private
  tracefs instance, invoked `/usr/libexec/armada/suspend-dispatch`, stopped
  tracing after the dispatcher returned, archived the post-resume snapshot,
  and removed the private instance. Dispatcher return code was `0` and the
  run is `suspend_success=true`.
- Clock/evidence: `CLOCK_BOOTTIME` delta `45.871318` seconds minus
  `CLOCK_MONOTONIC` delta `2.385984` seconds gives signed separation
  `43.485335` seconds, status `observed`. Kernel deep entry/exit markers were
  present. `suspend_stats` advanced independently from success `8`, fail `0`
  to success `9`, fail `0`. RTC IRQ 200 and its matching wakeup source each
  advanced by one.
- Trace configuration: the archive preserves all 2,812 available-event lines,
  event formats, filter/enable receipts, control snapshots, the 1,229,227-byte
  trace buffer, and per-CPU statistics. Twelve events were selected: IRQ 169
  entry/exit, both device-PM callback events, and eight `ufs:` tracepoints.
  The run used the then-current helper, so the PM tracepoint filter remained
  `none` because this kernel exposes the field as `device`, not `dev_name`;
  UFS PM lines were selected by exact device text during analysis. The trace
  used the kernel's `[local]` trace clock; its timestamps therefore cover the
  awake suspend/resume portions, while the signed clock pair proves the
  43.485-second suspended interval.
- IRQ/UFS result: the trace contains `1,069` IRQ-169 handler entries and
  `1,029` exits, with `0` per-CPU overruns and `0` dropped events. There were
  `1,758` `ufshcd_command` records (`879` sends and `879` completions), `126`
  UIC commands, and `7` hibern8 profile records; runtime suspend/resume and
  exception UFS tracepoints were absent. The UFS IRQ trace events were before
  the no-IRQ suspend boundary or after the no-IRQ resume boundary; none fell
  in the boundary gap. This demonstrates UFS activity around the transition,
  but not a Linux UFS interrupt handler executing during hardware suspend.
- PM result: `ufshcd-qcom 1d84000.ufshc`, `qcom-qmp-ufs-phy 1d80000.phy`, the
  SCSI host, UFS WLUN, devfreq, and UFS BSG paths all emitted suspend/resume
  callbacks with `err=0`, including the no-IRQ power-domain callbacks. The
  raw trace also records PCIe, ath12k, DWC3, SDHCI, display, and RPMh no-IRQ
  callbacks completing with `err=0`.
- Qualification of A/B: A/B `/proc/interrupts` deltas span pre-snapshot
  through post-snapshot collection, not only the hardware-suspended interval.
  This trace run's post-snapshot UFS total was `255,923 - 237,861 = 18,062`,
  but only `1,069` IRQ-169 entries were captured in the traced suspend/resume
  window. Therefore the earlier normalized UFS rates (`287.426/s` and
  `240.179/s`) are useful as aggregate pre/post-window rates, not proven
  in-suspend rates. The historical mmc0 storm remains unsupported by the
  observed trace and earlier low `mmc0` deltas.
- Qualcomm depth/result: AOSD, CXSD, and scalar DDR remained zero; ADSP was
  `+183`. Resume health had no new error-like lines, no failed systemd units,
  ten inputs remained present, and `DSI-1` remained connected/enabled.
- Cleanup: all selected events were disabled, the private trace instance was
  removed, Wi-Fi and Bluetooth were restored, and checksum verification
  covered `4,330` files with no mismatches. The trace run remains a distinct
  instrumented sample and is not counted as an uninstrumented stock repeat.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T162647Z-5c6d44f7dcf7`.
- Interpretation: UFS is active and busy around suspend entry/resume and has a
  strong Linux-visible association with the earlier aggregate IRQ deltas, but
  this experiment does not prove that UFS prevents AOSD/CXSD/DDR entry. The
  zero hardware counters remain unresolved; no kernel patch has been made.

## 2026-09-01 16:36 UTC — current-image stock repeat 8, s2idle/off-radio

- Run: `20260901T163453Z-c55f8534886a`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `s2idle`, Wi-Fi off, Bluetooth off, 45-second RTC wake, with no trace
  profile. The boot ID stayed unchanged. This is uninstrumented stock repeat
  8 of the ten-cycle current-image reliability target.
- Physical condition: no cable, charger, dock, hub, or user input; microSD
  remained inserted and mounted. No manual device action was required. SSH
  loss during the sleep interval was expected.
- Exact path: the root-owned detached agent invoked Armada's shipped
  `/usr/libexec/armada/suspend-dispatch` with the run-local s2idle request and
  received return code `0` after `2.120831` seconds.
- Clock/evidence: `CLOCK_BOOTTIME` delta `45.755710` seconds minus
  `CLOCK_MONOTONIC` delta `2.146865` seconds gives signed separation
  `43.608845` seconds, status `observed`. Kernel s2idle entry/exit markers
  were present. `suspend_stats` advanced independently from success `9`, fail
  `0` to success `10`, fail `0`. RTC IRQ 200 advanced by one and its matching
  wakeup source advanced active/event by `+2/+2`.
- Qualcomm/depth: AOSD, CXSD, and scalar DDR count/duration deltas were all
  zero; ADSP count delta was `+186`. The post snapshot had no new error-like
  lines and no failed systemd units. Ten input devices remained present and
  internal `DSI-1` remained connected/enabled.
- Aggregate IRQ observation: IRQ 169 (`ufshcd`) increased by `16,065` and
  mmc0 by `54` between the harness pre/post snapshots. As established by the
  traced run, these counters span post-resume collection and are not claimed
  as in-suspend rates; mmc0 still does not show the historical tens-per-second
  storm in this stock sample.
- Cleanup: the private trace profile was disabled (`none`), the RTC and
  temporary controls were restored, and a post-cleanup read-only SSH check
  confirmed Wi-Fi enabled/up, Bluetooth unblocked/powered on, and no hard
  radio block. The Bluetooth power-on command returned a transient failure in
  the cleanup receipt, but the subsequent check showed the desired restored
  state. Checksum verification covered `4,243` files with no mismatches.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T163453Z-c55f8534886a`.
- Interpretation: repeat 8 is a clean current-image s2idle reliability sample
  and reproduces the zero AOSD/CXSD/DDR result. The ten-cycle objective is
  still open; no kernel patch has been made.

## 2026-09-01 16:39 UTC — current-image stock repeat 9, deep/off-radio

- Run: `20260901T163731Z-e91f1b27bc6e`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `deep`, Wi-Fi off, Bluetooth off, 45-second RTC wake, with no trace
  profile. The boot ID stayed unchanged. This is uninstrumented stock repeat
  9 of the ten-cycle current-image reliability target.
- Physical condition: no cable, charger, dock, hub, or user input; microSD
  remained inserted and mounted. No manual device action was required. SSH
  loss during the sleep interval was expected.
- Exact path: the root-owned detached agent invoked Armada's shipped
  `/usr/libexec/armada/suspend-dispatch` with the run-local deep request and
  received return code `0` after `2.322498` seconds.
- Clock/evidence: `CLOCK_BOOTTIME` delta `46.097678` seconds minus
  `CLOCK_MONOTONIC` delta `2.346724` seconds gives signed separation
  `43.750954` seconds, status `observed`. Kernel deep entry/exit markers were
  present. `suspend_stats` advanced independently from success `10`, fail `0`
  to success `11`, fail `0`. RTC IRQ 200 advanced by one and its matching
  wakeup source advanced active/event by `+1/+1`.
- Qualcomm/depth: AOSD, CXSD, and scalar DDR count/duration deltas were all
  zero; ADSP count delta was `+182`. The post snapshot had no new error-like
  lines and no failed systemd units. Ten input devices remained present and
  internal `DSI-1` remained connected/enabled.
- Aggregate IRQ observation: IRQ 169 (`ufshcd`) increased by `16,879` and
  mmc0 by `53` between the harness pre/post snapshots. As established by the
  traced run, these counters span post-resume collection and are not claimed
  as in-suspend rates; mmc0 still does not show the historical tens-per-second
  storm in this stock sample.
- Cleanup: the RTC and temporary controls were restored. The Bluetooth
  power-on command again returned a transient failure in the cleanup receipt,
  but a subsequent read-only SSH check confirmed Wi-Fi enabled/up, Bluetooth
  unblocked/powered on, and no hard radio block. Checksum verification covered
  `4,243` files with no mismatches.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T163731Z-e91f1b27bc6e`.
- Interpretation: repeat 9 is a clean current-image deep reliability sample
  and reproduces the zero AOSD/CXSD/DDR result. One uninstrumented sample
  remains; no kernel patch has been made.

## 2026-09-01 16:41 UTC — current-image stock repeat 10, s2idle/off-radio

- Run: `20260901T163944Z-dab05e4ee675`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `s2idle`, Wi-Fi off, Bluetooth off, 45-second RTC wake, with no trace
  profile. The boot ID stayed unchanged. This is uninstrumented stock repeat
  10 of 10 for the current-image short-cycle reliability target.
- Physical condition: no cable, charger, dock, hub, or user input; microSD
  remained inserted and mounted. No manual device action was required. SSH
  loss during the sleep interval was expected.
- Exact path: the root-owned detached agent invoked Armada's shipped
  `/usr/libexec/armada/suspend-dispatch` with the run-local s2idle request and
  received return code `0` after `2.250809` seconds.
- Clock/evidence: `CLOCK_BOOTTIME` delta `46.526572` seconds minus
  `CLOCK_MONOTONIC` delta `2.278667` seconds gives signed separation
  `44.247905` seconds, status `observed`. Kernel s2idle entry/exit markers
  were present. `suspend_stats` advanced independently from success `11`, fail
  `0` to success `12`, fail `0`. RTC IRQ 200 advanced by one and its matching
  wakeup source advanced active/event by `+1/+1`.
- Qualcomm/depth: AOSD, CXSD, and scalar DDR count/duration deltas were all
  zero; ADSP count delta was `+180`. The post snapshot had no new error-like
  lines and no failed systemd units. Ten input devices remained present and
  internal `DSI-1` remained connected/enabled.
- Aggregate IRQ observation: IRQ 169 (`ufshcd`) increased by `16,141` and
  mmc0 by `53` between the harness pre/post snapshots. These are not claimed
  as in-suspend rates because the traced run established that the pre/post
  interval includes post-resume collection; mmc0 still does not show the
  historical tens-per-second storm.
- Cleanup: the RTC and temporary controls were restored. The Bluetooth
  power-on command returned a transient failure in the cleanup receipt, but a
  subsequent read-only SSH check confirmed Wi-Fi enabled/up, Bluetooth
  unblocked/powered on, and no hard radio block. Checksum verification covered
  `4,243` files with no mismatches.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T163944Z-dab05e4ee675`.
- Interpretation: repeat 10 is a clean current-image s2idle reliability
  sample. The ten uninstrumented current-image short cycles are complete and
  all ten meet the harness's suspend-success gates; no kernel patch has been
  made.

## 2026-09-01 16:47 UTC — current-stock deep RPMh/AOSS/ICC trace experiment

- Run: `20260901T164522Z-62f40512d811`
- Scope: current signed Armada `20260830.71e45aa`, kernel `7.2.0`, explicit
  `deep`, Wi-Fi off, Bluetooth off, 45-second RTC wake, with the new
  observation-only `rpmh-aoss` private trace profile. The boot ID stayed
  unchanged. No kernel, package, firmware, SDHCI, USB, runtime-PM,
  regulator, interconnect, or power-control value was changed.
- Physical condition: no cable, charger, dock, hub, or user input; microSD
  remained inserted and mounted. No manual device action was required. SSH
  loss during the sleep interval was expected.
- Exact path: the root-owned detached agent armed the RTC, created a private
  tracefs instance, held it stopped during setup, invoked
  `/usr/libexec/armada/suspend-dispatch`, stopped tracing after return, saved
  the post-resume snapshot, and removed the instance. Dispatcher return code
  was `0` and `suspend_success=true`.
- Clock/evidence: `CLOCK_BOOTTIME` delta `45.579892` seconds minus
  `CLOCK_MONOTONIC` delta `2.567737` seconds gives signed separation
  `43.012155` seconds, status `observed`. Kernel deep entry/exit markers were
  present. `suspend_stats` advanced independently from success `12`, fail `0`
  to success `13`, fail `0`. RTC IRQ 200 and its matching wakeup source each
  advanced by one.
- Trace configuration: all four required existing events were available and
  selected: `rpmh:rpmh_send_msg`, `rpmh:rpmh_tx_done`,
  `qcom_aoss:aoss_send`, and `qcom_aoss:aoss_send_done`. Both existing
  interconnect events, `interconnect:icc_set_bw` and
  `interconnect:icc_set_bw_end`, were also selected. The archive preserves
  all `2,812` available-event lines, exact formats and control receipts, a
  `861,385`-byte trace buffer, and per-CPU statistics. The trace instance was
  verified stopped after collection and removed; every selected event was
  disabled during cleanup.
- RPMh/AOSS result: the trace contains `1,347` `rpmh_send_msg` records and
  `658` `rpmh_tx_done` records, with no per-CPU overrun or dropped-event
  indication. RPMh send states were `1,335` `[active]`, `6` `[wake]`, and
  `6` `[sleep]`. At one suspend-transition point, `systemd-sleep` programmed
  an RPMh wake set on `apps_rsc` TCS 5 and a sleep set on TCS 3. The six wake
  writes were addresses `0x50000`, `0x50004`, `0x50010`, `0x50038`, `0x50048`,
  and `0x50044`; the six sleep writes targeted the same addresses with raw
  data retained in `raw/trace/trace.txt`. There were no traced RPMh error
  records. The sleep/wake sequence is evidence that Linux issued the
  firmware-facing set programming; it is not proof that firmware accepted or
  entered the requested hardware states.
- AOSS result: `qcom_aoss:aoss_send` and `qcom_aoss:aoss_send_done` both had
  zero records. This means no AOSS QMP message was emitted during this traced
  window; it does not establish that AOSS firmware or the AOSD residency
  counter is nonfunctional.
- Interconnect result: there were `1,934` `icc_set_bw` and `844`
  `icc_set_bw_end` records. The dominant senders were CPU-frequency governor
  tasks (`sugov`) and suspend/resume worker paths. The raw trace includes
  UFS-specific paths such as `xm_ufs_mem` and `qhs_ufs_mem_cfg` with the UFS
  device `1d84000.ufshc`, plus LLCC/EBI aggregate values; those changes occur
  around the suspend/resume plumbing and are not an in-suspend vote dump.
- Timing qualification: the private instance used the kernel's `[local]`
  trace clock, so its timestamps cover the awake portions of the transition
  while the signed clock pair proves the `43.012155`-second hardware-suspend
  interval. The trace shows the one-time sleep/wake programming and active
  traffic around it, not a direct firmware residency decision log.
- Qualcomm/depth: AOSD, CXSD, and scalar DDR count/duration deltas were all
  zero; ADSP count delta was `+199`. Resume health had no new error-like
  lines or failed systemd units, ten inputs remained present, and `DSI-1`
  remained connected/enabled.
- Cleanup: the RTC and temporary controls were restored; Wi-Fi and Bluetooth
  were restored and a read-only check confirmed enabled/up and
  unblocked/powered-on state. Checksum verification covered `4,305` files
  with no mismatches.
- Evidence: `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T164522Z-62f40512d811`.
- Interpretation: this run rules out the narrow hypothesis that the current
  Linux path never programs an RPMh sleep set. It does not show a failed
  RPMh transaction, a persistent Linux-visible request stream during the
  actual hardware-suspend interval, or an AOSS message that explains the
  zero AOSD/CXSD/DDR counters. The strongest remaining boundary is the
  firmware-side RPMh/AOP low-power decision and residency reporting, not a
  justified UFS, SDHCI, or kernel patch. No kernel patch has been made.

## Counting correction

The archive contains one additional current-image uninstrumented policy run,
`20260901T154437Z-64317bfc6a02`, which is documented in chronological order
above. Therefore there were eight clean uninstrumented current-image cycles
before the later forensic pause, followed by the three newly labeled stock
samples `20260901T163453Z-c55f8534886a`,
`20260901T163731Z-e91f1b27bc6e`, and
`20260901T163944Z-dab05e4ee675`. The final total is 11 clean stock cycles;
the ten-cycle objective is exceeded. The original run IDs, receipts, and
labels are preserved; this note only corrects the aggregate count.

## 2026-09-01 — read-only supported RPMh/AOP diagnostic inventory

- Source-side inventory: Armada ships `armada-sleep-debug` and the
  `40-armada-wake-ledger` system-sleep hook. The checkout contains no
  Armada-shipped AOP debug executable or package; the external
  `jaewun/qcom-aop-debug` source recorded in `upstream-state.md` is not
  installed or invoked by this lab.
- Device-side inventory: `/usr/bin/armada-sleep-debug` is present and
  executable, `/usr/libexec/armada/suspend-dispatch` is present and
  executable, and `/var/lib/armada/wake-ledger.log` is present as a root-owned
  readable 923-byte file. Its retained entries for the current runs all
  identify RTC IRQ 200 (`pm8xxx_rtc_alarm`) as the wake source.
- Supported evidence already available: `armada-sleep-debug` reports
  qcom-stats, wake IRQs, wake ledger, IRQ deltas, cpuidle, audio, thermal, and
  power-supply state. The lab archives add complete qcom-stats files,
  clock-pair evidence, runtime-PM snapshots, clk/regulator summaries, and
  scoped ftrace buffers.
- Firmware-facing trace availability: the current kernel exposes
  `rpmh:rpmh_send_msg`, `rpmh:rpmh_tx_done`, `qcom_aoss:aoss_send`,
  `qcom_aoss:aoss_send_done`, and interconnect bandwidth tracepoints. The
  completed RPMh run used these existing tracepoints without issuing a
  command or changing a vote. A normal SSH user cannot enumerate the root-only
  debugfs tree; no AOP-specific interface was assumed from that denied view.
- Boundary: the existing supported diagnostics and traces show Linux RPMh
  sleep/wake-set programming but not the firmware's acceptance decision or
  hardware residency result. No undocumented AOP/QMP command, vote forcing,
  kernel patch, or package change is justified yet.

## 2026-09-01 17:07 UTC — read-only root debugfs preflight follow-up

- Scope: this was a read-only inventory after the completed stock and trace
  runs. It did not suspend the Nova, write a debugfs value, alter runtime-PM
  or power controls, unbind SDHCI, or modify the microSD state. No physical
  device action was required; the Nova stayed awake with the microSD mounted
  and no cable attached.
- Receipt: `/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T170713Z-4aa81059d0be.json`.
  The device agent was the current checkout copy with SHA-256
  `6435788de07b8c27b9eb4dd5dcc88b0a99e23c413455f4417ca01946b52d34fa`.
- Current provenance: Armada `20260830.71e45aa`, bootc image digest
  `sha256:cae66b751f6376c7a2da84e7bca7fa81293e9689f7cc9b6bd682ebe83d852c25`,
  ostree checksum
  `c799737eff3f3e4a4299701d5d4ee7099d6ce498941bf6655ae7e158f49de79f`,
  Linux `7.2.0` (`#1 SMP PREEMPT Sun Aug 30 15:09:15 UTC 2026`), model
  `Retroid Pocket Nova`, and `mem_sleep=[s2idle] deep` with
  `/etc/armada/sleep.conf` still `suspend_mode=s2idle`.
- Qualcomm/AOSS controls: reads of
  `qcom_aoss/{prevent_ddr_collapse,prevent_cx_collapse,prevent_aoss_sleep,ddr_frequency_mhz}`
  each returned exit 1 with `Invalid argument`. No write was attempted. They
  are not readable scalar-state files on this build; the error does not say
  whether a collapse-prevention value is set.
- Interconnect: both
  `/sys/kernel/debug/interconnect/interconnect_summary` and
  `interconnect_graph` were readable. Complete payloads were retained in the
  receipt (344 and 565 lines). The awake summary showed nonzero aggregate
  activity including `llcc_mc`/`ebi` average `1471610`, peak `6832000`,
  display-subsystem average `1471610` with peaks `800000` and `400000`, PCIe
  `1c00000.pcie` peak `500000`, `qns_llcc` average `1471610` and peak
  `9600000`, and `qhs_qup2` average `3315` and peak `3200`. UFS
  `1d84000.ufshc` and USB `a600000.usb` rows were present but zero in this
  awake snapshot. These are aggregate/debug views, not in-suspend votes.
- Generic PM domains: `pm_genpd_summary` was readable and retained in full
  (111 lines). Awake state showed `cx on` usage `64`, `mmcx on` usage `64`,
  `ufs_phy_gdsc on` usage `64` with `1d84000.ufshc active` usage `64`, and
  `pcie_0_gdsc on` usage `64` with `1c00000.pcie active` usage `64`.
  `usb3_phy_gdsc` and `usb30_prim_gdsc` were on while `a600000.usb` was
  suspended; `mdss_gdsc` and the display subsystem were on/active; GPU GDSCs,
  EBI, MX/LCX/LMX, and GFX were off. The `17a00000.rsc` device was
  runtime-suspended. These are genpd usage/status values while awake, not
  the missing per-device runtime-PM usage-count field from A/B.
- CMD-DB: `stat` reported `-r-------- root root 0`, but a read succeeded and
  returned the complete 162-line, 5,893-byte dump. It maps the low-power ARC
  resources (`cx.lvl`, `mx.lvl`, `ebi.lvl`, `ddr.lvl`, `mmcx.lvl`, and
  `gfx.lvl`), BCM resources such as `MC0`, `SH0`, `SN0`, `CN0`, `QUP0/1`, and
  `ACV`, and VRM resources including `vrm.aoss`, `vrm.wlan`, `vrm.cx`, and
  `vrm.ebi`. It is a resource descriptor map, not live RPMh vote readback.
  Payload SHA-256:
  `3859059d49db26681cafdac268b6abed10c3003d23370e0dd85c419de4756e0d`.
- Debugfs availability: the root-only inventory retained `qcom_stats`, all
  four `qcom_aoss` nodes, both interconnect views, `pm_genpd_summary`,
  `cmd-db`, `clk_summary`, and `regulator_summary`. The complete file and
  directory listings remain in the receipt; no AOP-specific userspace helper
  was found.
- Correction to the earlier A/B entry: the statement that no interconnect
  view was available was accurate for the A/B archives and their first live
  probe, but is superseded for the current device inventory by this later
  root-readable preflight. It does not retroactively add an in-suspend vote
  capture to A or B. No Linux-visible awake-state value alone explains why
  the named qcom residency counters stayed zero during the clean cycles.

## 2026-09-01 17:28 UTC — read-only CMD-DB/RSC differential and source review

- Scope: no new suspend cycle was run. The completed RPMh archive and current
  read-only preflight were analyzed on the host; no qcom_aoss/QMP control was
  written, no vote was forced, no kernel was built, and no device/package
  state was changed. No physical action was required; the Nova stayed awake
  with the microSD mounted and no cable attached.
- Receipts: RPMh trace
  `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T164522Z-62f40512d811`
  and final schema-2 preflight
  `/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T172752Z-d0cace201f60.json`.
- CMD-DB result: the current full 5,893-byte/162-line dump contains ARC
  v16.0, BCM v16.0, and VRM v1.0 entries. All 38 unique addresses seen in
  both RPMh trace event types mapped successfully. ARC/BCM addresses matched
  exact entries; VRM sub-addresses matched their base resource using the
  documented bits-19:4 rule. The complete mapping and counts are in
  `current-image-forensic-differential.md` under “RPMh address reverse
  mapping and sleep-set contents.”
- Six-set result: the wake/sleep TCS commands are BCM `MC0` (`0x50000`),
  `SH0` (`0x50004`), `SN0` (`0x50010`), `CN0` (`0x50038`), `QUP1`
  (`0x50048`), and `QUP0` (`0x50044`). MC0/SH0 carry valid nonzero sleep
  `vote_y=476`; SN0/CN0/QUP0 carry `commit=1, valid=0`; QUP1 carries
  `commit=0, valid=0` in the sleep word. Wake values decode to valid
  `vote_y=2083` for MC0, `4571` for SH0, and valid `x=y=1` for the four
  remaining BCM commands. This is not malformed-address evidence and is not
  proof that AOP honored the set.
- Immediate ownership: just before the set, the trace shows `a80000.i2c`
  using QUP1, `890000.i2c` using QUP2, and `98c000.i2c` using QUP0. Their
  paths traverse `qns_gemnoc_sf`, `qns_llcc`, `llcc_mc`, and `ebi`; the last
  active ARC writes were `mmcx.lvl=0` and `cx.lvl=0`. The final preflight's
  live summary independently shows LLCC/EBI, configuration, display, and
  PCIe aggregate values, but those values are awake samples and are not
  promoted to in-suspend votes.
- Firmware identity boundary: the preflight identifies `QCS_KAILUA` and
  reports ADSP/CDSP/boot/TZ strings, but AOP-specific identity is blank. The
  only AOP-related device-tree evidence is reserved memory at
  `aop-cmd-db-region@81c60000` and
  `aop-config-merged-region@81c80000`; no AOP/RPMh firmware file was found in
  `/usr/lib/firmware`. The external `qcom-aop-debug` monitor operations are
  therefore not firmware-matched and were not used.
- Upstream/RSC result: reviewed RSC v3 adds accelerator type/name decoding and
  TCS/GIC/status output on transfer timeout. Current Linux master and Armada's
  package do not carry it. It would not produce evidence for this clean run,
  because there was no timeout and it has no successful sleep-set readback or
  AOP acceptance report. The current Armada AOSS debugfs entries are
  write-only, consistent with the observed read-side `EINVAL`.
- Harness result: future phase snapshots now retain raw plus parsed
  `cmd_db`, `interconnect_summary`, `interconnect_graph`, and
  `pm_genpd_summary` structures under schema version 2. Local parser tests and
  validation against the exact preflight passed. No kernel/package patch has
  been built or deployed.
- Conclusion: branch 1 (malformed/unknown set) is not supported; branch 2
  (persistent Linux vote) remains unproven because the low-power interval has
  no direct vote snapshot; branch 3 (firmware-side decline) is the strongest
  unresolved boundary; branch 4 is reduced by the source-checked qcom-stats
  semantics but not fully eliminated. The next smallest observation is a
  successful-path, read-only RSC TCS snapshot around the sleep-set handoff,
  using reviewed CMD-DB helpers. It is a future diagnostic design, not a
  patch/build/deployment decision.
- Archived kernel/journal logs add no AOP firmware version, acceptance, or
  low-power-decision breadcrumb. They do show RSC, RPMh regulator, power
  controller, BCM voter, AOSS-QMP, and CMD-DB PM callbacks returning zero;
  this is Linux PM completion evidence, not proof of firmware state entry.

## 2026-09-01 — source-only successful-path RSC hook review

- The v7.2 RSC implementation makes `rpmh_rsc_write_ctrl_data()` the
  non-triggering sleep/wake path. It allocates a sleep/wake TCS slot and calls
  `__tcs_buffer_write()`, which writes the command registers and emits the
  existing `rpmh_send_msg` tracepoint. Firmware is responsible for triggering
  those sets when the execution environment reaches the deepest low-power
  mode.
- The completed trace already records state, TCS number, command number,
  address, data, message ID, and wait/complete flag. It does not record the
  selected TCS's post-write `CMD_ENABLE`, controller control/status, per-command
  status/response, or IRQ status. The active-transfer busy check is separate
  and cannot prove sleep-set acceptance.
- Source-only conclusion: the minimal future diagnostic is a read-only
  post-buffer-write TCS-register snapshot for the sleep/wake slots, decoded
  with the reviewed CMD-DB helpers. It must not trigger/rewrite the TCS or
  send any QMP/AOSS message. No patch was created, built, or deployed.

## 2026-09-01 17:45 UTC — live RSC boundary and host consistency check

- Scope: no suspend cycle was run and no device state was changed. The live
  check read only sysfs and device-tree metadata; the host check re-parsed the
  retained RPMh trace and CMD-DB receipt. No MMIO was read, no qcom_aoss/QMP
  control was written, no vote was forced, and no kernel/package patch was
  created, built, or deployed. No physical action was required; the Nova
  remained awake with the microSD mounted and no cable attached.
- Receipt: the fresh root preflight is
  `/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T174854Z-45d0702ef09c.json`;
  its device-agent SHA-256 is
  `7dd127a2e532764b039c1bd051a85a25a6b9d99407b760b78e8c55931fe52b1b`.
- Live RSC metadata: `apps_rsc` is compatible with `qcom,rpmh-rsc` at
  `/soc@0/rsc@17a00000`. The device tree exposes four `drv-0` through `drv-3`
  windows at `0x17a00000`, `0x17a10000`, `0x17a20000`, and `0x17a30000`, each
  `0x100` bytes; `qcom,drv-id=2`, `qcom,tcs-offset=0xd0000`, and
  `qcom,tcs-config` rows `2,3,0,2` and `1,2,3,0`. Sysfs exposes no readable
  RSC resource/register/status/TCS view, so an unpatched observation is not
  available.
- Host consistency result: re-parsing
  `/Users/kurt/Developer/sm8550-suspend-lab-runs/20260901T164522Z-62f40512d811/device/raw/trace/trace.txt`
  against the CMD-DB dump in
  `/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T172752Z-d0cace201f60.json`
  found 38 unique trace addresses and zero unresolved addresses. The six
  transition addresses and all VRM sub-addresses resolve exactly as recorded
  in the forensic result document.
- The same receipt now contains parsed structures, not only raw text: CMD-DB
  `152` resources, interconnect `127` aggregates and `214` consumers, graph
  `127` nodes and `135` edges, and genpd `48` domains and `50` device rows.
- Verification: `py_compile`, both harness self-tests, and `git diff --check`
  passed. This is a tooling/source verification, not new device evidence.
- Decision unchanged: the smallest next diagnostic remains a successful-path
  in-driver read-only RSC/TCS snapshot immediately after Linux programs the
  sleep/wake buffers and again after resume. It must use `readl` only and
  capture command/control/status, response, and IRQ state; no trigger, write,
  QMP, forced vote, or AOP monitor operation is allowed.

## 2026-09-01 17:50 UTC — upstream diagnostic freshness recheck

- The freshness check found no newer successful-path RSC diagnostic revision.
  The latest reviewed Qualcomm series remains v3, posted 2026-08-12; its RSC
  patch is explicitly timeout-triggered and the 2026-08-17 maintainer reply
  contained only minor review comments. Qualcomm's kernel PR #907 was in fact
  merged on 2026-08-20 into `qualcomm-linux/kernel:qcom-6.18.y`, with RSC
  commit `403d2a6ac9213a7454fa31744f8ad6089d368cd8` and CMD-DB commits
  `946390ea27648ac0e76ecd1950405f1ce3ed5640` and
  `b98e95ae006480d4d6c384725beede55ed3092d7`. The live Torvalds Linux master
  and Armada package still lack those helpers.
- A direct remote check recorded Qualcomm `qcom-6.18.y` at
  `681580d43f243496bce246326979dddabfb5d8bd`; its current raw
  `rpmh-rsc.c` and `cmd-db.c` contain `rpmh_rsc_debug()`,
  `cmd_db_read_name()`, and `cmd_db_hw_type_str()`. This confirms the patch is
  present in that vendor branch, while not making it part of the Nova image.
- Armada's current package script fetches the `linux-7.2` kernel.org stable
  tarball and applies only `kernel/patches/series`, so the Qualcomm vendor
  branch cannot be substituted as the Nova build source. A line-level source
  comparison found the merged diagnostic hunks' expected contexts in the
  Linux v7.2 RSC/RPMh files, with unrelated allocator differences in
  `rpmh.c`; this is porting evidence only, not a patch application check.
- The merged Qualcomm implementation remains timeout-only: it prints TCS
  command/control/status and GIC state only when a blocking RPMh operation
  times out. It does not provide a successful sleep-set snapshot or AOP
  acceptance result. This is source-status evidence only, not device evidence.
  No device command, control, suspend cycle, patch, build, or deployment was
  performed for this check.
- Decision unchanged: use the merged reviewed series as the decoding/reference
  starting point, and design a separate successful-path read-only snapshot for
  Nova if that experiment is later authorized.

## 2026-09-01 17:58 UTC — exact RSC TCS allocation for future observation

- Source inspection confirmed the running device-tree `qcom,tcs-config`
  sequence is `(ACTIVE_TCS,3), (SLEEP_TCS,2), (WAKE_TCS,2),
  (CONTROL_TCS,0)`, using the v7.2 binding constants. The resulting global
  slots are ACTIVE `0--2`, SLEEP `3--4`, and WAKE `5--6`; the completed RPMh
  trace's final sleep TCS `3` and wake TCS `5` match this allocation.
- The merged Qualcomm `rpmh_rsc_debug()` source iterates only
  `drv->tcs_in_use`, the active-transfer bookkeeping bitmap. Sleep/wake
  control writes instead reserve `tcs->slots`, so simply carrying that helper
  into Armada would not inspect the clean-run sleep TCS 3 or wake TCS 5.
- The future observation must enumerate the sleep/wake group slots explicitly,
  use the driver's version-selected register-offset table, and read only
  `CMD_ENABLE`, `CONTROL`, `STATUS`, global `IRQ_STATUS`, and enabled-command
  `MSGID`, `ADDR`, `DATA`, `STATUS`, and `RESP_DATA`. This refines the design;
  it does not authorize a patch, build, deployment, TCS trigger, IRQ clear,
  QMP/AOSS operation, or vote change.

## 2026-09-01 18:03 UTC — supported package compatibility audit

- The current Armada package source was inspected read-only. Its kernel build
  script fetches the kernel.org stable `linux-7.2` tarball and applies the
  package-local `kernel/patches/series`; the current series contains no RSC or
  CMD-DB diagnostic entry.
- The merged Qualcomm branch was compared line-by-line with the v7.2 RPMh
  source. The expected insertion contexts are present in `rpmh-rsc.c`,
  `rpmh-internal.h`, and `rpmh.c`; `rpmh.c` also has unrelated allocator
  differences. This establishes a plausible reviewed porting base, not a
  successful patch application or build.
- No source patch was created or applied, and no package, kernel, boot, device,
  QMP/AOSS, or vote state changed. No physical action was required. The next
  allowed implementation step remains gated by the explicit no-build/no-patch
  instruction.

## 2026-09-01 21:03 UTC — observation-only diagnostic package built

- The user-authorized diagnostic build completed through the Armada package
  checkout. Package base was `2c93e73cbe1bcf4d443495e94fbaa5e7a8cf7141` on
  branch `feat/sm8550-rsc-observation`; kernel source remained the package's
  kernel.org stable `linux-7.2` input. No kernel source, firmware, ABL, boot,
  device, QMP/AOSS, or power-control state was changed on the Nova.
- The final build used the arm64 Fedora container
  `registry.fedoraproject.org/fedora@sha256:0c6072366ebf8ea1c8c0f3a118aad3e9a9247d3065d499e54d62968f69351966`,
  applied all `136` series patches, passed config validation, linked Image,
  built DTBs/modules, and exited 0. `CONFIG_QCOM_RPMH_SUCCESS_DEBUG=y` and
  `CONFIG_DEBUG_INFO_BTF=y` were retained. A prior Docker-store I/O failure
  during module BTF finalization was preserved as a build observation; it was
  not treated as a source failure. The ccache mount was removed before the
  successful retry and its generated files were cleaned.
- Artifact: `/Users/kurt/Developer/armada-packages-suspend-lab/kernel/out/armada-kernel-7.2.0.tar.zst`;
  SHA-256 `3fc078ffc04e59471538269abe442fab907f3c792a0b42c048d816715af72cc1`.
  The embedded `vmlinuz` SHA-256 is
  `5d7348afe15a71ef5918c47eea9d3d995f88d3e157bd65b6907eed352e71d867`.
  `zstd -t`, checksum verification, extraction, tar listing, and required Nova
  DTB/module entry checks passed. Embedded metadata reports aarch64 build,
  136 applied patches, 20 DTBs, and Armada repackaging.
- The source package remains uncommitted and undeployed at this notebook point;
  the main checkout has the deployment-preparation document and the package
  checkout has the patch/config/series changes. Generated `kernel/out` is kept
  locally for delivery preparation and is not source history.

## 2026-09-01 21:03 UTC — live supported-update gate rechecked

- Read-only SSH inventory to `retroid-nova` (`192.168.0.20`) confirmed the
  expected Armada userspace: `/usr/lib/armada/version` is `20260830.71e45aa`,
  the running kernel is `7.2.0`, the booted origin is the signed Armada
  `testing` image, and the Nova DT/RSC identity remains unchanged. The OS
  identifies as Fedora 44, which is the Armada bootc base and is not evidence
  of a wrong host.
- The supported update entry points are `/usr/bin/steamos-update` and
  `/usr/libexec/armada/armada-update`; the latter is not on the normal user's
  `PATH`. Root is required for `bootc status` and update application. The
  current account's generic `sudo -n` check requires the installed default
  password, while Armada's narrow passwordless rules cover only selected
  management operations. No update, reboot, kernel/boot-file write, or lab run
  was started during this gate.
- The raw kernel tarball is therefore not yet a deployable device input. It
  must be wrapped into a signed Armada bootc image and applied through the
  shipped update workflow. If a custom image cannot satisfy the device's
  signature policy, deployment will stop rather than bypassing that policy.

## Next controlled step

The ten-cycle stock reliability objective is exceeded: 11 uninstrumented
current-image cycles completed cleanly, and the two scoped read-only trace
experiments are complete. The observation-only successful-path RSC/TCS kernel
is now built and source-ready but not deployed. First publish the source/docs
to the user's fork(s), then complete the supported signed-image assembly and
update gate. After boot verification, run exactly one `rsc-success` deep cycle
with RTC wake, parse the successful-path snapshots, and classify the four
outstanding branches before selecting any functional fix. Remaining blind
repetitions stay deferred, not cancelled.
