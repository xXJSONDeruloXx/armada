# SM8550 suspend lab

This directory contains the Phase 1 experiment harness for a Retroid Pocket
Nova running Armada. It is intentionally a userspace observation tool. It does
not modify a kernel, firmware, ABL, boot image, storage controller, or radio
binding.

## Current upstream inspection

The repository fingerprints and the source comparison used to start this lab
are recorded in [upstream-state.md](upstream-state.md). The important current
state is:

- Armada's Nova profile is SM8550, inherits the global fake-suspend default,
  and its real path is Armada's shipped
  `/usr/libexec/armada/suspend-dispatch`, which selects `mem_sleep` and then
  invokes `systemd-sleep`.
- The current Armada kernel package is Linux 7.2 with Armada's PCIe
  suspend-OPP floor patches. Userspace already has the SM8550 CPU0
  suspend-window hook and USB autosuspend rule.
- Thorch carries a separate RPMh regulator suspend-state pair and a matching
  regulator-core s2idle mapping. These are not silently treated as safe for
  Nova; they remain later A/B candidates.

The chronological device observations are maintained in
[lab-notebook.md](lab-notebook.md). It records every attempted run, including
harness failures and interpretation corrections, with exact run IDs and raw
evidence paths.

The post-update A/B read-only analysis is recorded in
[current-image-forensic-differential.md](current-image-forensic-differential.md).
It is the current evidence boundary for choosing the next single-variable
experiment; the ten-cycle objective is exceeded by 11 clean current-image
cycles, and remaining blind repetitions are deferred pending the read-only
root-cause/instrumentation review.

The first functional kernel opportunity A/B is recorded in
[dwc3-skip-phy-ab.md](dwc3-skip-phy-ab.md). The reviewed Qualcomm DWC3
skip-PHY-init candidate booted and suspended cleanly but produced no observable
USB/PHY or relevant power/residency improvement in the matched cable-free
deep run, so it was rolled back. Its device-local recipe is preserved in
`device-kernel-layer-dwc3.Containerfile`; the unresolved RPMh/AOP question is
independent of this negative result.

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
6. For `s2idle` or `deep`, uses a run-local `suspend_mode` file and child
   environment for `suspend-dispatch` so `/etc/armada/sleep.conf` is not
   edited.
7. Records `CLOCK_BOOTTIME`, `CLOCK_MONOTONIC`, and `CLOCK_REALTIME`, then the
   autonomous root-owned agent invokes Armada's shipped
   `/usr/libexec/armada/suspend-dispatch` directly. The agent remains on the
   device and writes the post snapshot only after that dispatcher returns, so
   SSH timing is not the suspend boundary and no direct
   `systemd-suspend.service` start is needed. This is not `rtcwake -m freeze`.
8. For short diagnostic reproductions, `--trace-profile ufs-irq`,
   `--trace-profile rpmh-aoss`, or `--trace-profile rsc-success` creates a
   private tracefs instance, records its exact event inventory/configuration,
   enables only the requested existing tracepoints, archives the bounded buffer
   after the dispatcher returns, and removes the instance. `rsc-success` also
   requires the isolated observation-only kernel package's successful-path
   `rpmh_rsc_snapshot` tracepoint. The profiles never send firmware commands or
   change runtime-PM, regulator, interconnect, or device power controls.
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
  `s2idle`/`deep` modes are transient experiment requests, not persisted policy
  changes.
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

The `ufs-irq` trace profile resolves the live `ufshcd` IRQ from
`/proc/interrupts` at run time. It never assumes a board IRQ number, which is
important because the Nova's current mapping uses UFS IRQ 170 and `mmc0` IRQ
169. The resolved number and the exact trace controls are retained in each
run's `meta/trace.json` and `raw/trace/` archive.
