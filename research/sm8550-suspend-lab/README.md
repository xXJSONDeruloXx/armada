# SM8550 suspend lab

This directory contains the Phase 1 experiment harness for a Retroid Pocket
Nova running Armada. It is intentionally a userspace observation tool. It does
not modify a kernel, firmware, ABL, boot image, storage controller, or radio
binding.

## Current upstream inspection

The repository fingerprints and the source comparison used to start this lab
are recorded in [upstream-state.md](upstream-state.md). The important current
state is:

- Armada main now defaults Nova to native `s2idle` (merged PR #370). The
  current Nova image also selects `s2idle`; its shipped
  `/usr/libexec/armada/device-env` and `suspend-dispatch` accept `fake` and
  `s2idle`, not `deep`, even though the kernel lists both modes in
  `/sys/power/mem_sleep`.
- A live refresh on 2026-09-17 found Armada `20260915.feca679`, kernel
  `7.2.3`, and the SM8550 IRQ routing / CPU0 cpuidle fix from `e2d9802`.
- Two short current-image timer-wake cycles completed in `s2idle`. Qualcomm
  AOSD, CXSD, and scalar DDR counters remained at zero while ADSP counters
  advanced. A request for `deep` fell back to `s2idle`; it is retained as a
  fallback observation, not a deep-mode result. A later direct-kernel run
  selected `deep` through `/sys/power/mem_sleep` and entered a real suspend
  interval, but the same named-state counters stayed at zero. The harness now
  supports `deep` as a test-only mode that bypasses Armada's dispatcher, and
  marks any requested/observed mode mismatch as a failed run.
- Thorch carries a separate RPMh regulator suspend-state pair and a matching
  regulator-core s2idle mapping. These are not silently treated as safe for
  Nova; they remain later A/B candidates.

The latest live observations, temporary test cleanup, and next low-cost steps
are recorded at the top of [lab-notebook.md](lab-notebook.md). No kernel build
or image deployment was needed for this refresh.

The chronological device observations are maintained in
[lab-notebook.md](lab-notebook.md). It records every attempted run, including
harness failures and interpretation corrections, with exact run IDs and raw
evidence paths.

The larger post-update A/B read-only analysis is recorded in
[current-image-forensic-differential.md](current-image-forensic-differential.md).
It documents the earlier ten-cycle comparison; the short September 17 cycles
are a separate current-image refresh and do not replace that historical
analysis.

The first functional kernel opportunity A/B is recorded in
[dwc3-skip-phy-ab.md](dwc3-skip-phy-ab.md). The reviewed Qualcomm DWC3
skip-PHY-init candidate booted and suspended cleanly but produced no observable
USB/PHY or relevant power/residency improvement in the matched cable-free
deep run, so it was rolled back. Its device-local recipe is preserved in
`device-kernel-layer-dwc3.Containerfile`; the unresolved RPMh/AOP question is
independent of this negative result.

## Current sleep-depth evidence boundary

For the Nova, `/sys/kernel/debug/qcom_stats/{aosd,cxsd,ddr}` are records
maintained by AOP/RPM firmware. An unchanged zero `count` means firmware
recorded no entry into that named SoC low-power mode in the capture window;
these counters report firmware state, not direct rail voltage. The detailed
`ddr_stats` table is separate from scalar `ddr`. Its `0xd0` row advances while
the device is awake and nearly matches the sum of DDR frequency-duration rows,
so it is not independent proof of self-refresh or collapse. The other DDR LPM
IDs remain undocumented in public source.

The `adsp` file shares the debugfs directory but is a different data source:
Linux reads that subsystem counter from SMEM item 606 / host 2, while AOSD,
CXSD, and DDR are read from the mapped SoC stats SRAM. The runner now samples
all named subsystem SMEM files at the same suspend boundaries and reports
their deltas separately. This can show which subsystem records change across
the suspend window; it cannot validate the separate SoC stats block or prove
physical residency.

The live Nova FDT maps PSCI argument `0x4100c344` to
`cpus/domain-idle-states/cluster-sleep-1`; that node has no `idle-state-name`,
which explains why genpd prints `N/A`. CPU-local states map `0x40000004` to
the separately named silver, gold, and goldplus rail-collapse nodes. The
runner now captures this live mapping and reports it beside PSCI events. A
requested DT node and a successful PSCI return do not prove the physical
domain or SoC rails reached their target. Qualcomm's downstream Kalama DTS
maps this argument to an `llcc-off` entry, but the live Nova FDT name is only
`cluster-sleep-1`.
The same before/after boundary now includes the cluster genpd idle-state table,
so Usage/Rejected/S2idle callback counters can be correlated to each firmware
snapshot rather than inferred from broad run snapshots. The `S2idle` column is
not a selected-mode detector: Linux increments it when a genpd system-power-
down callback exists, and the callback path itself does not check whether the
run selected `deep` or `s2idle` ([genpd accounting](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pmdomain/core.c#L1391-L1445)).
These counters remain Linux callback evidence, not physical residency.

A current-image direct `deep` run also reached `psci_system_suspend_enter` and
its run-scoped return probe recorded `retval=0` after the RTC wake, while the
exact AOSD/CXSD/scalar-DDR firmware records again remained zero. Thus the
platform SYSTEM_SUSPEND callback is reached and returns successfully; merely
adding a Linux system genpd is not enough to explain these zero records. The
RPMh trace resolves suspend-set addresses to BCM names (MC0, SH0, SN0, CN0,
QUP0, QUP1), but the writes are staged asynchronously and do not prove firmware
triggered them. No AOSS QMP messages were emitted in that window.

Paired exact-boundary s2idle and direct-`deep` runs each recorded one APSS
SMEM sleep entry whose duration closely matched the ~29-second
suspend-clock interval. Both had genpd cluster S1 Usage +1 / Rejected +0 /
S2idle +1; Linux source shows the `S2idle` column is callback-tagged accounting
and can also increment during direct `deep`, so it cannot distinguish modes.
S2idle traced one `0x4100c344` `cluster-sleep-1` enter/exit pair returning 0;
direct `deep` traced one successful PSCI SYSTEM_SUSPEND callback return. In
both runs AOSD, CXSD, scalar DDR, and the recognized detailed DDR LPM IDs
`0xd4`, `0xd3`, and `0x11` recorded no entry. ADSP/CDSP subsystem counters also
advanced, but they are separate SMEM records. This proves the kernel and
firmware subsystem paths recorded suspend activity; it does not identify the
APSS rail state or prove DDR self-refresh/collapse. Linux's v7.2.3 reader
confirms subsystem entries use SMEM and adjusts duration for a subsystem
currently asleep, while SoC-mode records are read from mapped stats SRAM
([qcom_stats.c](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/qcom_stats.c#L1123-L1267)).

The running kernel exposes no read-only AOP acknowledgement query. Its
`qcom_aoss` debugfs nodes are write-only controls, the DTBO slots have no
Nova-specific CXPC sink mapping, and the live QMP resource does not validate
the public decoder's buffer address. Do not read that guessed buffer or send
the experimental monitor QMP message without a Nova-validated resource/layout.
The live PSCI feature list also omits `STAT_RESIDENCY`, `STAT_COUNT`, and
`NODE_HW_STATE`, so firmware does not expose the standard PSCI residency query
through its debugfs interface.
Static disassembly of the exact AOP image found `0x0c320000` among unlabeled
address constants but no sink bounds or CXPC record schema; this is not enough
to make a read safe. The remaining gap is an authoritative Nova AOP buffer
mapping plus documented residency fields, matching firmware source/release
documentation, or a PMIC/hardware state trace. A CXPC blocker report alone
would explain why collapse may be prevented, not prove which state was entered.

The earlier workload validation used a diagnostic image and was rolled back
through Armada's supported update path. The live refresh now reports a newer
testing image (`20260915.feca679`); historical image and cleanup receipts are
kept in the notebook and run archives.

The pre-update image used for the historical control runs was older than this
checkout. Run a fresh read-only preflight before any future update, then use
Armada's shipped update hook to check and stage the configured channel; the
helper never writes a kernel or boot file directly:

```console
python3 research/sm8550-suspend-lab/sm8550_suspend_lab.py host preflight \
  --target retroid-nova
python3 research/sm8550-suspend-lab/sm8550_suspend_lab.py host supported-update \
  --target retroid-nova --action check
python3 research/sm8550-suspend-lab/sm8550_suspend_lab.py host supported-update \
  --target retroid-nova --action stage
python3 research/sm8550-suspend-lab/sm8550_suspend_lab.py host supported-update \
  --target retroid-nova --action apply
```

`apply` invokes bootc's supported `--from-downloaded --apply` operation in a
root-owned on-device unit. It reboots into the staged deployment and lets the
normal Armada shutdown hooks synchronize the boot image; it does not manually
replace any kernel or boot file.

If the configured channel has no newer image, select a different channel only
as an explicit experiment through Armada's shipped selector. For example,
the `main` token maps to Armada's `testing` channel:

```console
python3 research/sm8550-suspend-lab/sm8550_suspend_lab.py host supported-channel \
  --target retroid-nova --channel main
```

## Host setup

The control host needs an SSH key-based target and non-interactive root access
on the Nova. The runner uses `BatchMode=yes` and `sudo -n`; it never stores or
passes a password. Set the target explicitly or export
`SM8550_SSH_TARGET`:

```console
python3 research/sm8550-suspend-lab/sm8550_suspend_lab.py host self-test
python3 research/sm8550-suspend-lab/sm8550_suspend_lab.py host run \
  --target nova-ssh-alias \
  --mode s2idle \
  --wifi-state off \
  --bluetooth-state off \
  --sleep-seconds 45
```

The default host output directory is the sibling
`../sm8550-suspend-lab-runs/`, so raw captures do not pollute the checkout.
Use `host start` when the Mac process should return immediately:

```console
python3 research/sm8550-suspend-lab/sm8550_suspend_lab.py host start \
  --target nova-ssh-alias --mode s2idle --sleep-seconds 45
python3 research/sm8550-suspend-lab/sm8550_suspend_lab.py host status \
  --target nova-ssh-alias RUN_ID
python3 research/sm8550-suspend-lab/sm8550_suspend_lab.py host retrieve \
  --target nova-ssh-alias RUN_ID
```

If the Nova reboots or the detached unit is lost, wait for SSH to return and
run `host recover RUN_ID` before retrieving the run. The run ID is generated
with UTC time plus random bytes, and both host and device refuse to reuse an
existing run directory.

## What a run does

On the device, one detached systemd unit performs this sequence:

1. Creates `/var/lib/sm8550-suspend-lab/runs/RUN_ID/` with mode 0700.
2. Captures OS, kernel, package, boot, DT, Armada policy, cpuidle, IRQ,
   wakeup-source, runtime-PM, power-supply, audio, regulator/clock, thermal,
   RTC, journal, and dmesg evidence into `pre/` and `raw/`.
3. Runs Armada's `armada-sleep-debug prepare` into the run directory and
   retains its exact output.
4. Arms a writable RTC `wakealarm` without asking `rtcwake` to suspend.
   Existing nonzero alarms are refused unless the explicit
   `--allow-existing-rtc-wakealarm` flag is supplied.
5. Applies the requested `--wifi-state` and `--bluetooth-state` inside the
   detached run, if they are not `preserve`, and records/restores their prior
   state after resume. This is why SSH can disappear during the Wi-Fi-off
   baseline without turning radio state into an untracked manual variable.
6. For explicit `s2idle`, uses a run-local `suspend_mode` file and child
   environment so `/etc/armada/sleep.conf` is not edited. `policy` leaves the
   configured mode alone. Explicit `deep` temporarily selects the kernel mode
   directly and bypasses the dispatcher in step 7.
7. Records `CLOCK_BOOTTIME`, `CLOCK_MONOTONIC`, and `CLOCK_REALTIME`, then the
   autonomous root-owned agent invokes Armada's shipped
   `/usr/libexec/armada/suspend-dispatch` for `policy` and `s2idle`, or invokes
   `systemd-sleep suspend` directly for test-only `deep`. The agent remains on
   the device and writes the post snapshot only after suspend returns, so SSH
   timing is not the suspend boundary and no direct
   `systemd-suspend.service` start is needed. This is not `rtcwake -m freeze`.
8. For short diagnostic reproductions, `--trace-profile ufs-irq`,
   `--trace-profile rpmh-aoss`, `--trace-profile rsc-success`, or
   `--trace-profile psci-kretprobe` creates a
   private tracefs instance, records its exact event inventory/configuration,
   selects the suspend-inclusive `boot` clock, enables only the requested
   existing tracepoints, archives the bounded buffer after the dispatcher
   returns, and removes the instance. `rsc-success` also
   requires the isolated observation-only kernel package's successful-path
   `rpmh_rsc_snapshot` tracepoint. `psci-kretprobe` temporarily registers a
   run-unique return probe for `psci_cpu_suspend_enter` on s2idle, or
   `psci_system_suspend_enter` on direct deep suspend. It enables the probe
   only in its private trace instance and removes only that registration
   immediately after trace capture, before post-resume collection.
   The profiles never send firmware commands or change runtime-PM, regulator,
   interconnect, or device power controls.
9. After resume, captures the matching post snapshot, Armada's exact
   `armada-sleep-debug collect` output, bounded logs, and read-only health
   observations.
10. Computes `derived/summary.json`, writes `result.md`, and restores only the
   RTC alarm, RTC wake control, child mode environment, mem-sleep
   selection, radio state, PM debug switches, and TSENS dynamic-debug flag that
   this run changed. If an outside process changes an owned control during the
   run, the cleanup leaves that conflicting value untouched and records the
   conflict.

The automatic optional charger-firmware subcollector inside
`armada-sleep-debug collect` is suppressed. Armada documents that loading its
`pmic_pdcharger_ulog` module leaves it loaded because unloading can wedge the
GLINK teardown. Power-supply uevents and all available battery counters are
still collected. Charging-specific firmware logging can be added as a later,
explicitly scoped experiment.

## Evidence layout and interpretation

Each retrieved host run has this shape:

```text
RUN_ID/
  host-manifest.json
  result.md
  device/
    config.json status.json
    pre/ post/          # structured before/after snapshots and copied files
    raw/                # command receipts, raw logs, and sleep-debug state
    meta/               # RTC, mutation, transient-env, and clock receipts
    derived/summary.json post-resume-health.json
    cleanup/            # restoration receipts and conflicts
    checksums.sha256    # device-side SHA-256 receipt for every other run file
```

`suspend_clock_separation_seconds` (also retained as
`real_suspended_seconds`) is derived for every mode as the
`CLOCK_BOOTTIME` delta minus the `CLOCK_MONOTONIC` delta. The signed value is
preserved. A zero or negative result is reported as
`suspend_clock_separation_status=unexpectedly_absent` or `negative`; it is
never normalized into a claim that the clocks behaved as expected. Kernel
entry/exit markers and `suspend_stats` remain independent evidence. A
`PM: suspend exit` line alone never makes a run successful. The success verdict
also requires the observed kernel mode markers, the unchanged boot ID, a
comparable suspend-stat success increment, and a zero-return dispatcher
command. A reboot is reported as a recovery/failure boundary rather than
being folded into a successful sleep.

Inventory and process-presence checks are not functional gamepad, display,
audio, Wi-Fi, Bluetooth, USB, Steam, or gamescope acceptance tests. Those
remain explicit validation gates after short idle cycles are reliable.

## Safety boundaries

- Disconnect USB physically for ordinary no-USB baselines. A USB cable is an
  experiment variable and cannot be inferred reliably from SSH state.
- Keep the Nova awake at the desktop for the initial setup, with Wi-Fi
  available for SSH. The first `--wifi-state off --bluetooth-state off` run
  will intentionally drop SSH until the RTC wake and cleanup restore Wi-Fi;
  no cable should be connected during that run.
- The runner never unbinds, resets, power-gates, or changes a storage
  controller. In particular, it does not touch an SDHCI controller hosting the
  root filesystem.
- Do not run long unattended cycles until short RTC-controlled cycles have
  established reliability. Do not flash ABL or modify AOP, TZ, or vendor
  firmware as part of this lab.
- `--mode policy` measures Armada's current user-facing policy. Explicit
  `s2idle` is a transient experiment request, not a persisted policy change.
  `deep` is an explicit kernel-only experiment: the harness temporarily selects
  `deep` in `/sys/power/mem_sleep`, invokes `systemd-sleep` directly, bypasses
  Armada's dispatcher, and restores the original kernel selection after resume.
  It does not change `/etc/armada/sleep.conf` or the installed image. The run
  fails if the observed kernel mode differs from the request.
- The harness does not claim a power improvement from capacity alone. It uses
  charge/energy counters when available and labels gauge-derived values as
  indicative.

The test matrix and functional kernel A/B work belong to later phases. The
observation-only RSC/TCS package is maintained separately in the Armada
packages checkout and must reach the Nova through a supported signed Armada
image/update path; this harness never installs a raw kernel tarball or writes a
boot file. For explicitly authorized kernel-only lab iteration, the checked-in
`device-kernel-layer.Containerfile` wraps a checksum-verified Armada kernel
tarball into a uniquely tagged on-device OCI layer, regenerates the initramfs,
and applies it with bootc's containers-storage/downloaded-image flow. This
keeps each iteration quick while preserving image provenance and rollback; it
does not weaken the production signed update boundary.

The DWC3 candidate used the same fast path with the candidate-specific
`device-kernel-layer-dwc3.Containerfile`; it was not retained after the A/B.

The `ufs-irq` trace profile resolves the live `ufshcd`, `apps_rsc`, and
`arch_timer` IRQs from `/proc/interrupts` at run time. It never assumes board
IRQ numbers. The resolved numbers and exact trace controls are retained in
each run's `meta/trace.json` and `raw/trace/` archive.
