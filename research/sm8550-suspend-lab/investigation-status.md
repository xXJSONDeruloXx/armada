# SM8550 suspend investigation status

**Read this first.** This is the current checklist and evidence boundary for
the Nova suspend investigation. The [lab notebook](lab-notebook.md) remains
the chronological record, including failed runs and superseded interpretations.
Update this page when a checklist item changes; put raw output in a dated
receipt and explain the result in the notebook.

Status as of 2026-09-20 22:58 UTC. Branch `feat/sm8550-suspend-lab`.

## Current goal checklist

- [x] Treat Android's sleep behavior as a reference; do not mount Android
  expecting its kernel code to run or force-load Android `.ko` files into
  Linux.
- [x] Recheck live Linux: stock 7.2.3 is healthy, bootc is at the default
  image with no staged/rollback deployment, and both PCIe functions are in D0.
- [x] Narrow the PCIe test: s2idle selects the existing 1,000 kB/s
  `opp-suspend` OPP; the diagnostic changes only the memory-path peak for the
  direct-deep, host-unsuspended fallback, preserving `low_svs`.
- [x] Confirm there is no exposed PCIe OPP sysfs control and the public
  dynamic OPP API cannot define bandwidth for a new runtime OPP.
- [x] Prepare a candidate-specific systemd rollback guard, build its OCI
  image from cached artifacts, and verify the timer and marker in-container.
  The newest un-staged image starts its initrd timer in the `basic.target`
  transaction and orders it before that target. The image has not been staged
  or applied.
- [x] Evaluate whether Android's kernel modules can be mounted into Armada and
  whether Armada user space could run on Android's kernel. Direct module reuse
  is incompatible; a hybrid boot is theoretically possible but is a separate
  high-risk boot port, not the next minimal test.
- [x] Verify the rollback command reboots into the previous deployment and
  that the automatic bootc update timer is masked on the device.
- [x] Check Linux- and Mac-visible USB/ADB/fastboot/serial, EFI, and watchdog
  surfaces for remote early-boot recovery; none is currently exposed.
- [x] Trace the “Preparing Armada” splash label to its initramfs and real-root
  producers; the identical label cannot identify which boot phase stalled.
- [x] Read the current boot's initrd/switch-root journal and inspect the ESP
  read-only; confirm normal phase timings and no EFI BootNext control.
- [x] Confirm Armada's image build regenerates initramfs with dracut, so
  candidate-only phase instrumentation can be added without a kernel rebuild.
- [x] Verify the candidate image's existing boot-sync drop-in preserves the
  known-good `KERNEL.BAK` instead of snapshotting the test kernel over it.
- [x] Recheck the current ESP hashes and the actual FAT/VFAT kernel config;
  reject the stale `.armada-bootimg.prev.id` as a source of truth.
- [x] Add a candidate-only initrd recovery timer that checks the exact stock
  `KERNEL.BAK` hash before restoring it, and exercise fail-closed cases.
- [x] Build an un-staged candidate with the guard in its generated initramfs;
  verify required files/tools, systemd units, and the existing root rollback.
- [x] Exercise the exact generated initrd helper on a scratch loop-backed
  VFAT image, with reboot stubbed; success and wrong-hash fail-closed checks
  pass. The real ESP and bootc deployment were not touched.
- [x] Check persistent journal and pstore for the prior candidate boot. The
  clean apply/shutdown is recorded, but there is no candidate root journal or
  pstore kernel log to identify the failed phase.
- [x] Repeat a stock RTC-woken direct-deep control with the PCIe/RPMh trace.
  The root-port D3cold veto and MC0/SH0 SLEEP floor reproduced; AOSD/CXSD/
  scalar-DDR deltas remained zero. The run did not include a PSCI kretprobe.
  See the [stock control receipt](receipts/2026-09-20-stock-deep-pcie-control.md).
- [ ] Locate the previous candidate boot's SSH loss and cover failures before
  the initrd timer starts. The prior journal proves a clean bootc apply and
  boot-image rewrite, but there is no persistent journal for the subsequent
  candidate boot. The timer cannot recover a kernel/initrd-systemd hang; do
  not stage again until manual ABL recovery is available for that gap.

## Latest device recovery state

The Nova is running the original Armada beta image, kernel `7.2.3`, boot ID
`aa40c55e-d558-46a9-a710-3a7d926b9e9e`. Systemd is `running` with no failed
units; Wi-Fi/SSH and the Gamescope Steam session are active. Steam CEF reports
Big Picture, Main Menu, and Quick Access pages. The display itself was not
captured.

At 22:43 UTC a new candidate image was built and verified in rootful Podman:
`20260920-05`, version `20260920.pcie-opp-test-initrd-guard-03`, manifest
digest `sha256:ee083828400828329df59ad7ca9084a8a745894d95831efeb8e77a1f1d5688cc`.
Its generated initramfs contains the recovery timer under
`basic.target.wants`; the timer is ordered before `basic.target` and
`dracut-pre-mount.service`. Both initrd and real-root rollback units pass
`systemd-analyze verify`. The image is only in local Podman storage: bootc
still reports the original default deployment, `staged=null`, and no rollback.
The boot ID and running kernel did not change. This earlier timer still cannot
cover a kernel failure or initrd systemd failure before the `basic.target`
transaction starts; manual ABL recovery remains necessary for that gap. See
the [early-target guard receipt](receipts/2026-09-20-initrd-guard-early-target-build.md).

The test deployment has been removed from OSTree with
`rpm-ostree cleanup --pending`; `bootc status` is now `bootOrder=default`,
`rollback=null`, `rollbackQueued=false`, `staged=null`. Its candidate OCI image
remains in local Podman storage at the recorded digest for restaging. Armada's
boot-image updater has regenerated stock `/KERNEL`; root-level hashes for
`KERNEL` and `KERNEL.BAK` are both the pre-test stock hash, and the active
image-ID stamp is stock. The candidate's stale queue and stamp mismatch are
resolved. See the [Android rollback receipt](receipts/2026-09-20-android-esp-rollback.md).

A read-only SSH check at 19:45 UTC reconfirmed the same boot ID and bootc
default state. PCIe root port `0000:00:00.0` and WCN endpoint
`0000:01:00.0` are both D0; the host remains bound to `qcom-pcie` and the
endpoint to `ath12k_wifi7_pci`. The PCIe host's sysfs tree exposes no runtime
OPP/devfreq control. The original and guarded candidate OCI images and pinned
base remain in rootful Podman storage, with 30 GB free on `/var`; none is
staged. Use guarded tag `20260920-02`, manifest digest
`sha256:b4560e90b4dfba8631a47c69de91bdcde7f491fa3fb47299b73d828de8e076e0`
and version `20260920.pcie-opp-test-guarded-01`. The older guarded tag
`20260920-01` has an ambiguous version marker and is superseded. The final
image's units and marker pass in-container checks. See the
[guarded-candidate receipt](receipts/2026-09-20-pcie-opp-guarded-candidate.md).

A further read-only check at 20:18 UTC still finds the same stock boot ID and
kernel. `bootc rollback --apply` is documented on-device to reboot into the
previous deployment, and `bootc-fetch-apply-updates.timer` is masked/inactive,
so it will not automatically undo the rollback during a test. The attached
464-GB card is mounted at `/run/media/armada/sd`, but it is storage, not an
independent boot-control channel. The host reports no ADB or fastboot device;
the Linux UDC exists but no USB gadget configuration is mounted. This adds no
recovery path for a kernel/initramfs failure before systemd.

At 20:22 UTC, the Linux host still exposes no ADB/fastboot device, `bootctl`
reports “Not booted with EFI,” and both `/dev/watchdog*` and
`/sys/class/watchdog` are absent/empty. The ESP contents could not be inspected
as the SSH user lacks permission and passwordless sudo is unavailable; no
bootloader fallback control was changed or assumed. This does not establish a
pre-systemd rescue path.

The previously reported splash text is not a phase marker: both Armada's
initramfs service and its real-root early-boot service write “Preparing
Armada.” The initramfs splash launcher is deliberately left running across
switch-root. Thus the old observation does not show whether the candidate
reached the real-root timer; the pre-systemd recovery gap remains unresolved.

The current boot's journal shows initrd systemd starting at 0.898 s, the
initrd splash at 3.545 s, `initrd-switch-root.service` at 4.109 s, the
real-root splash at 6.134 s, and “Starting Steam” at 16.162 s. The ESP contains
only Armada's `KERNEL`, `KERNEL.BAK`, and boot-image ID stamps; no EFI loader
or EFI variables are present. This confirms ordinary Linux has no visible
EFI BootNext route; ABL/manual recovery remains the only known fallback.

Armada's build recipe regenerates `/usr/lib/modules/<kver>/initramfs.img`
with dracut modules `ostree`, `armada-splash`, and
`armada-ostree-fallback`, then verifies key files with `lsinitrd`. A
candidate-only dracut module can therefore add persistent boot-phase
checkpoints without rebuilding the kernel. That would improve failure
localization, but would not itself recover a hung boot.

The test image also contains `preserve-kernel-backup.conf`, which removes only
the startup `--snapshot-prev` argument and leaves the updater and shutdown
sync in place. This keeps the hash-verified stock `KERNEL.BAK` available
during a candidate boot. A candidate-only initrd timer is now built into a
separate OCI image; it verifies the stock backup hash, restores `KERNEL`
through a temporary file, repairs the active image ID from the known stock
value, and requests reboot. Its mocked success/failure cases, generated
initramfs contents, and systemd units pass. It has not been booted. The timer
is wanted by `dracut-pre-mount.service` but ordered before that service, so it
starts when pre-mount is queued. It still cannot recover kernel or initrd
systemd failures before that activation point; those need manual ABL recovery.

At 21:48 UTC, the helper extracted from this candidate's generated initramfs
was exercised on a 256 MiB loop-backed scratch VFAT filesystem inside the
candidate OCI image. The success path restored a fixture `KERNEL`, repaired
the active image stamp, preserved the previous-image stamp, and called a
stubbed `systemctl reboot`. A bad backup hash failed closed without changing
the fixture kernel/stamp or requesting reboot. The exact scratch directory
was removed and loop2 detached afterward. The real ESP was not mounted into
the container; this validates helper/VFAT behavior only, not initrd timer
activation or recovery before initrd systemd.

At 21:55 UTC, the previous persistent boot journal was found to contain the
apply/reboot boundary: bootc initiated shutdown at 13:07:41 EDT, OSTree
finalized the staged deployment and updated the boot config, and Armada's
finalizer wrote `/boot/efi/KERNEL` for `vmlinuz-7.2.3` by 13:08:02. The log
does not identify the written bytes beyond the shared kernel version string.
`journalctl --list-boots` has no separate persistent Linux root journal for
the candidate before the current stock boot. This narrows the sequence but
does not locate the failure within kernel/initrd or distinguish a bootloader
selection issue. See the [reboot-boundary receipt](receipts/2026-09-20-previous-candidate-reboot-boundary.md).

At 21:58 UTC, root-readable `/sys/fs/pstore` was empty. The running kernel has
`CONFIG_PSTORE=y` and `CONFIG_PSTORE_RAM=m`, but `ramoops` is not loaded, no
`/dev/pmsg0` exists, and no reserved-memory compatible in the live DT names
`ramoops` or `pstore`. There is no preserved panic/console trace from the
missing boot, and no RAM region should be guessed for a ramoops backend.

At 22:00 UTC, the Mac also showed no Nova/Android USB device, ADB device,
fastboot device, or USB serial node. The only serial nodes were macOS's own
`debug-console` and `wlan-debug`; the visible USB product was `Ultra`. This
does not provide a host-side recovery channel for an early boot failure.

At 22:06 UTC, a fresh stock `deep` run succeeded for 13.612693 seconds of
suspend-clock separation and woke through the RTC. The D3cold check again
returned `-EOPNOTSUPP` for root port `17cb:0113`; MC0/SH0 again received
`0x600003b8`; AOSD/CXSD/scalar DDR remained unchanged. Wi-Fi recovered and
Steam/Gamescope stayed alive. No PSCI return probe was enabled for this run.
The PCIe OPP candidate remains un-staged because the initrd timer still cannot
cover kernel/initrd-systemd failures before timer activation.

At 20:45 UTC both current ESP images again hash to the known stock image
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`, and the
active ID is stock `d7755f13…`. The previous-ID stamp still names the old
candidate `2fde9022…`; do not use that stamp to identify `KERNEL.BAK`. VFAT/FAT
are built into this kernel, and the existing initramfs already includes
mount/umount/systemctl/blkid. A fail-closed initrd recovery can instead verify
the exact backup hash and write the known stock ID directly. No device state
changed.

Before rebooting from Android to Linux, I reasserted `adb_wifi_enabled=1` and
`persist.adb.tls_server.enable=1`; legacy TCP ADB remained unset. This booted
into Linux, so persistence through another Android reboot is not yet tested.
At 18:52 UTC, `adb devices` was empty and reconnecting to the prior Android
TLS endpoint timed out. Linux has no `adbd` process/listener. Android's
`userdata` partition (`/dev/sda17`) is unmounted and has no filesystem type
reported by Linux; do not edit it offline. To make Wireless debugging
boot-persistent, the remaining safe route is a small Magisk late-start helper
after Android is reachable again. Keep Android's authenticated TLS mode and
leave legacy TCP ADB disabled.

The sleep-stats offset question is closed: Android and Armada both resolve the
SM8550 records at `+0x48` and `+0xb8`. Android's successful deep path advances
AOSD/CXSD/DDR; Armada's successful deep path does not. The exact Android
`dcvs_fp` binary and live DT identify the producer of the additional MC4/SH5
SLEEP=0 and WAKE_ONLY=1 requests.

The first Linux A/B is now complete. A BTF-compatible test module staged only
the MC4/SH5 pair, and the Apps-RSC trace showed both commands alongside the
usual six Linux SLEEP/WAKE commands. A 9.319-second RTC-woken `deep` entry
still left AOSD/CXSD/scalar DDR deltas at zero. MC0/SH0 retained the
`0x3b8` (952) SLEEP floor. This rejects the pair as a sufficient fix in this
run; it does not prove the pair has no effect or that firmware accepted every
command. The test left the stronger PCIe/floor correlation unresolved.
See the [A/B receipt](receipts/2026-09-20-rpmh-dcvs-pair-ab.md).

The module was loaded from a temporary file for the test only; it was not
installed into an image or deployment. The device has since rebooted to Linux,
clearing the module and its request cache. Post-reboot checks show kernel
`7.2.3`, Armada version `20260915.feca679`, a new boot ID,
`mem_sleep=[s2idle] deep`, suspend stats `0/0`, Wi-Fi/SSH up, zero failed
units, and no loaded test module. Harness cleanup recorded removal of its
private trace instance before reboot; direct post-boot tracefs inventory was
permission-denied to the non-root SSH account. The corrected module hash is
`548d9244a327cc16ba04d2ad644a0b87b08660dfd37e8db5144e07a0065eda2f`; live
BTF layout/prototype checks passed, though exact source/image identity is not
proven and `CONFIG_MODVERSIONS` is disabled.

The exact Android source commit remains unavailable. The running build suffix
`g697b78910a71-dirty` does not resolve through the public GitHub commit API;
the nearby public `lineage-23.2` tree is grafted at `93c5cc6`, and the advertised
`lineage-24.0` head is `dc79bb3`. Runtime claims are therefore anchored by
hash-matched binaries, live DT, and traces, with public source labeled only as
a match. The current candidate A/B is a Nova-only OPP
that keeps the active Gen2 x1 `low_svs` RPMh corner while lowering only the
PCIe-MEM peak request from 500000 to 1000 kB/s; the CPU path remains 1 kB/s.
It uses the normal OPP path and does not bypass PCI eligibility or directly
write an ICC vote. The matching-config `make -j8 ARCH=arm64 Image dtbs`
completed with exit 0. The embedded Image config hash matches the live config
at `2219546e268f72bb2bcbac96943202e9e50731b6e531e3193cc73b1976d2fbef`. Image
SHA-256 is `15b46efc40d15200523b5c7ec623f54d4ac03bddfe798f1d8842ebf1fa2824d9`;
Nova DTB SHA-256 is
`72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422`. The
DTB contains the opt-in property and 2 Hz diagnostic OPP with a 1000/1 kB/s
peak and `required-opps` pointing to phandle `0x26` (`opp-64`, level `0x40`,
the existing `low_svs` corner).
The artifact hashes and checks are in the
[matching-config build receipt](../../receipts/2026-09-20-matching-config-pcie-opp-build.md).
The original linked image was blocked because its config omitted scheduler-
extension options enabled on the device; the scratch `.config` was reconciled
through Kconfig before the successful build. See the
[config-reconcile receipt](receipts/2026-09-20-pcie-opp-config-reconcile.md).
The currently installed base is `ghcr.io/armada-os/armada:beta` at digest
`sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88`;
the old local-layer recipe points at a 2026-09-01 image and kernel 7.2.0, so it
cannot be reused verbatim. The candidate is built from that exact digest after
the first attempt hit a Netavark/nftables setup error; retrying with
`--network=host` passed the artifact hash checks. It is
`localhost/armada-pcie-opp-test:20260920-01`, manifest digest
`sha256:d7eb055720a28bddc8f6a3e7267d6e56c54c53de719963ed06c1228f851e101b`.
Bootc staged it as download-only at OSTree checksum
`7eb51de69c15c669d35900ff93b279c8b8a21ffec8f415e7da00d14dd2d55cbf`. A later
`bootc switch --from-downloaded --apply` request was accepted with the message
"Staged deployment will now be applied on reboot"; SSH then closed. The
candidate's boot and current bootc rollback state have not been confirmed. See
the [layer/stage receipt](receipts/2026-09-20-pcie-opp-layer-stage.md) and the
[post-apply reachability receipt](receipts/2026-09-20-post-apply-device-reachability.md).

The diagnostic patch changes the global BTF blob by adding its private
`qcom_pcie` state flag. Candidate BTF hash
`cd7334c576a197a39b0e5121d2b3fb9c38fef8af6b034beb039d1b04b4bbbb44` retains
the inspected `pci_dev`/`pci_bus` offsets used by the PCIe probe. The harness
accepts only the stock and this exact candidate hash and records the active
hash. See the
[candidate BTF receipt](receipts/2026-09-20-candidate-pcie-btf.md).
The 17:05 UTC preflight confirms all nine `pcie-d3cold` tracepoints and both
required kprobe targets were available and unblacklisted on the stock kernel.
The candidate must boot before its live BTF allowlist can be checked. See the
[pre-boot preflight receipt](receipts/2026-09-20-pcie-opp-preboot-harness-preflight.md).
Immediately before the apply request, SSH reported Linux kernel `7.2.3`, boot
ID `55fdad18-019d-4c92-8ebd-8a558574c1d3`, and connected Wi-Fi. At 17:16 UTC,
SSH, ping, and TCP/22 to `192.168.0.20` did not respond; explicit checks scoped
to the Mac's Wi-Fi interface also reported the host down. ADB listed no
devices, USB inventory was empty, and mDNS advertised only this Mac. The
running deployment and OS after apply are therefore unknown; do not assume the
candidate booted.
The Android binary/module analysis needed for this PCIe hypothesis is already
captured; the next test remains Linux-only.
The [boot-image recovery receipt](receipts/2026-09-20-bootimg-recovery-path.md)
confirms the existing KERNEL.BAK matches the current boot image and documents
a test-layer drop-in needed to keep that backup from being replaced at the
first diagnostic boot. At 16:34 UTC, both ESP files were freshly hashed on the
device and copied to
`/Volumes/NovaKernelBuild/backups/nova-esp-20260920T1634Z/boot-esp-kernel-pair.tar`;
the extracted active and backup images both match SHA-256
`0b0d7c03a88e77c480ad31d145a6718916638ba62287ff5a2b427c0f75475000`. The
archive SHA-256 is `0760f9acf1399a98186233800185b8a37a781247c0a10f12b98999da409eee16`.
The device-scoped layer recipe is tracked at
[`device-kernel-layer-pcie-opp.Containerfile`](device-kernel-layer-pcie-opp.Containerfile).
The off-device ESP archive was reverified at 17:16 UTC: it remains mode 0600
and has SHA-256
`0760f9acf1399a98186233800185b8a37a781247c0a10f12b98999da409eee16`. It
contains the previously hash-matched stock `KERNEL` and `KERNEL.BAK`; the
device's current ESP contents cannot be checked while it is unreachable.

## Latest Android suspend attempt (historical)

A later screen-off attempt still did not complete deep suspend. The
`suspend_control_internal` service returned false; `suspend_stats` success
stayed at 99, fail advanced 6→8, and `failed_freeze` advanced 2→3, with the
last recorded failure at `alarmtimer.0.auto` (`-16`). A 107,372-byte trace is
retained outside Git. It contains 283 BCM commits and 396 RPMh sends, but no
write to `0x50060` or `0x50064`. The `dcvs_fp` probe staged those SLEEP/WAKE
requests earlier in boot, before tracing began; this failed attempt does not
contradict the exact successful-run attribution. The device has since been
woken; live checks show Android awake, `wlan0` up, `[s2idle] deep` restored,
empty RTC wakealarm, global tracing off, and no tracefs instance. The earlier
screen-on attempt separately aborted at `3da0000.kgsl-smmu` with `-115`.
Repeated Android attempts are low-value until the freeze/preparation blocker
is isolated. Details and trace hash are in
`../../receipts/2026-09-20-android-boot-image-and-trace-failure.md`.

## Current objective and checklist

Find the smallest defensible cause for Linux's zero AOSD/CXSD/scalar DDR
records, and choose one safe next experiment without forcing PCI state or
manually changing shared bandwidth/regulator requests.

- [x] Close the Android/Linux stats address and record-layout comparison.
- [x] Attribute Android's extra MC4/SH5 SLEEP/WAKE_ONLY requests to its exact
  installed `dcvs_fp` module and live DT.
- [x] Build and load a one-variable Linux MC4/SH5 request-pair probe after
  matching its relevant live BTF ABI.
- [x] Run a short RTC-woken direct-`deep` test and capture the Apps-RSC request
  set plus before/after firmware records.
- [x] Reboot the unchanged Linux deployment and confirm SSH, kernel/image
  version, suspend selection/stats, and absence of the test module. Harness
  cleanup removed its trace instance before reboot; post-boot tracefs inventory
  requires root and was not independently read.
- [x] Attribute the retained MC0/SH0 floor to PCIe's only nonzero SLEEP-tagged
  request and check the PCIe OPP semantics against source and trace.
- [x] Prepare a device-scoped diagnostic OPP that retains the currently used
  `low_svs` corner and lowers only PCIe-MEM bandwidth; it does not bypass PCI
  D3cold eligibility or directly alter an ICC vote.
- [x] Restore the live scheduler config through Kconfig; the result matches
  the saved live config byte-for-byte.
- [x] Rebuild the matching-config candidate and inspect the Image/DTB; verify
  bootc rollback and the preserved `KERNEL.BAK` manual recovery path.
- [x] Identify the live bootc base digest and rollback deployment; confirm the
  old 7.2.0 local-layer recipe is stale. The pinned base and test layer fit;
  `/var` currently has 30 GB free after build and stage.
- [x] Read current bootc switch semantics and Armada's boot-image refresh path;
  verify the current ESP backup matches the active boot image.
- [x] Prepare a device-scoped image recipe and backup-preservation drop-in.
- [x] Build and stage the candidate in download-only mode; verify its base
  digest, artifact hashes, bootc stage, unchanged current/rollback deployments,
  and off-device KERNEL/KERNEL.BAK backup before reboot.
- [ ] Run one RTC-bounded deep A/B only if the artifact and rollback gates
  pass. Record the command set, residency counters, PSCI result, resume, and
  Wi-Fi state; do not use battery drain as the short-run verdict.

## Closed question: sleep-stat offsets

**Do not repeat this experiment.** Android resource `0x0c3f0000`, size `0x400`;
the stock Android driver read pointer words `0x000f0048` and `0x000f00b8`,
resolving to `0x0c3f0048` and `0x0c3f00b8`. Its normal reads found the expected
AOSD/CXSD/DDR signatures and DDR magic. Armada's Linux caller probe independently
resolved `+0x48`; mainline uses `+0x48` and `+0xb8`. The zero Armada records are
not explained by a stats-address, stride, or obvious record-layout mismatch.

No Android diagnostic module, pointer-word probe, qcom_stats offset change, or
new arbitrary MMIO read is warranted.

## Evidence ledger

Labels matter: **observed** means captured directly; **source** means found in
the inspected tree; **correlation** is not causal proof; **unknown** must stay
open until measured.

| Status | Finding |
|---|---|
| Observed, exact Android binary + live DT | The exact A-slot `dcvs_fp.ko` (`vermagic` `5.15.123-g697b78910a71-dirty`, live `scmversion` matches) is bound to `/soc/apps_rsc@17a00000/drv@2/qcom,dcvs-fp`. Its live properties select `qcom,ddr-bcm-name=MC4` and `qcom,llcc-bcm-name=SH5`; the module disassembly reads the names through CMD-DB, then submits two RPMh commands in SLEEP and WAKE_ONLY contexts during probe. This identifies the software producer of the MC4/SH5 commands in Android's successful TCS capture. It does not show firmware acceptance by itself or establish that these two votes cause residency. Receipt: `../../receipts/2026-09-20-android-dcvs-fp-binary-and-dt.md`. |
| Observed, live Linux module ABI gate | The probe's first `insmod` was rejected before init: `.gnu.linkonce.this_module` is 1216 bytes, while live BTF says `struct module` is 1280 bytes. The rejected object omits four fields gated by `CONFIG_DEBUG_INFO_BTF_MODULES`; this option is enabled live but was normalized off by local `make modules_prepare`. No RPMh requests were issued and no suspend was run. The module must be rebuilt and its relevant ABI checked before a retry. Receipt: `../../receipts/2026-09-20-rpmh-dcvs-pair-insertion-failure.md`. |
| Observed, corrected module static gate | Re-enabling `CONFIG_DEBUG_INFO_BTF_MODULES` and cleaning before rebuild produced `.gnu.linkonce.this_module=0x500` (1280 bytes), equal to a shipped module. Live BTF and module DWARF layouts match for `module`, `device`, `bus_type`, and `tcs_cmd`; canonical function signatures match for the RPMh/CMD-DB and device-bus APIs used. It was host-only at that checkpoint; it was later loaded for the bounded A/B below. Exact build identity is not proven and live `CONFIG_MODVERSIONS` is disabled. |
| Observed, Linux MC4/SH5 A/B | The BTF-checked module queued the MC4/SH5 pair; both commands appeared in the Apps-RSC SLEEP/WAKE send trace. One RTC-woken `deep` run lasted 9.319 s, but AOSD/CXSD/scalar DDR deltas remained zero and MC0/SH0 retained `0x600003b8`. This rejects the pair as a sufficient standalone fix in that run; it does not prove AOP acceptance or that the pair is irrelevant. Receipt: `receipts/2026-09-20-rpmh-dcvs-pair-ab.md`. |
| Source + live Linux, mainline v7.2.3 RPMh interface | Mainline lacks Android `dcvs_fp` and its active fast-path APIs, but exports `cmd_db_read_addr()` and `rpmh_write_async()`; SLEEP/WAKE requests are cached and flushed by `rpmh-rsc` before low-power entry. Live Nova Linux has `17a00000.rsc` (`qcom,rpmh-rsc`, `qcom,drv-id=<2>`) with bound child `17a00000.rsc:regulators-0` directly beneath it. A test module can reuse that existing child as the API client, so no DT overlay is needed. Live config has `CONFIG_DEBUG_INFO_BTF=y`, `CONFIG_DEBUG_INFO_BTF_MODULES=y`, and `CONFIG_MODVERSIONS` disabled. Matching vermagic and one API type were insufficient to load the first build. |
| Observed, live Android merged DT | Runtime model is KalamaP HDK with IDs matching the public Nova DTBO candidate. Active WCN is under `pcie@1c00000`, has `qcom,drv-name=lpass`, and lacks `qcom,apss-based-l1ss-sleep`, `qcom,no-client-based-bw-voting`, and `qcom,pcie-switch-type`; pcie1 is disabled. The exact successful mode-0 trace, combined with the absent switch-type property/default 0, establishes the connected-DRV branch and connected flag for that run. The `qcom,drv-supported` fallback and exact runtime DT are in `../../receipts/2026-09-20-android-live-runtime.md`; callback and module identity evidence is in `../../receipts/2026-09-20-android-live-pcie-validation.md`. |
| Observed, earlier Android suspend attempts | Before the successful capture below, this boot had `success=0`, `fail=3`. One natural attempt logged WLAN bus-suspend success then a `NETLINK` abort. Direct `rtcwake -m mem` returned `EBUSY`; its alarm was cleared. A later unarmed `forceSuspend()` returned false. The short s2idle intervals around those attempts remain unattributed. Do not repeat direct `rtcwake -m mem` or call forceSuspend before a verified RTC alarm. Receipt: `../../receipts/2026-09-20-android-live-runtime.md`. |
| Observed, controlled Android deep capture | On the same Android boot, `service call suspend_control_internal 2` returned true with temporary `deep` selected and a verified `+8s` rtc0 alarm. The kernel logged `PM: suspend entry (deep)` and `pm8xxx_rtc_alarm` wake; `suspend_stats` success advanced 0→1. Baseline-zero APSS/AOSD/CXSD/DDR records advanced to counts 1/165/17/17. The suspend-boundary ICC hook showed two tag-3 ACTIVE_ONLY DCVS clients and no PCIe client. Wi-Fi/ADB recovered; `mem_sleep`, hook, and alarm were restored. This proves Android deep reaches these firmware-recorded states in this run, but does not identify the exact PCIe suspend branch, final TCS, or a single causal difference. Receipt: `../../receipts/2026-09-20-android-deep-icc-followup.md`. |
| Observed, exact Android PCIe branch and final staged TCS | A bounded `deep` run traced `cnss_pci_suspend()`/`cnss_pci_suspend_bus()` success, `msm_pcie_pm_control(mode=0)`, `msm_pcie_drv_suspend()`, and `qcom_pcie_icc_bw_update(0, 0)`. The exact binary stores `link_status=DRV(3)`; its root-port `SUSPEND_LATE` body requires `ENABLED(1)`, matching the absence of `msm_pcie_pm_suspend()`/`msm_pcie_clk_deinit()` hits. The noirq callback checks `enumerated`, `power_on`, and `apss_based_l1ss_sleep`; live pcie0 lacks the DT property setting the last flag, so the APSS/L1SS teardown body is skipped. The run stages 14 SLEEP/14 WAKE commands; MC0/SH0 SLEEP words are zero, LDOE1/LDOE3 requests are present, and APSS/AOSD/CXSD/DDR advance. Neither no OS-issued D-state setter calls nor post-resume D0 establishes physical PCI state during sleep. Receipt: `../../receipts/2026-09-20-android-exact-pcie-branch.md` and `../../receipts/2026-09-20-android-live-pcie-validation.md`. |
| Observed, Android PCI PM callbacks | A separate short Android `deep` run saw successful normal/noirq suspend and resume callbacks for Qualcomm host, root port, and WCN endpoint. Kprobes for `pci_set_power_state()` and `pci_raw_set_power_state()` recorded no hits. This establishes no software D-state setter was observed, not the physical sleep-time state. Post-resume root and endpoint were D0 and WLAN was up. Trace settings/probes were cleaned and verified. Receipt: `../../receipts/2026-09-20-android-live-pcie-validation.md`. |
| Observed, exact live Android modules/BTF | Wireless ADB reported the same fingerprint, slot `_a`, and kernel as the prior capture. The three installed modules match prior A-slot SHA-256 values; live split-BTF gives exact `msm_pcie_dev_t` offsets for `link_status=0x480`, `apss_based_l1ss_sleep=0x409`, `enumerated=0x535`, and `power_on=0x6a4`. These offsets anchor the exact binary branch reconstruction. This does not identify the missing vendor source revision or physical PCI state during sleep. Receipt: `../../receipts/2026-09-20-android-live-pcie-validation.md`. |
| Observed, Android source identity check | Live `uname`/`/proc/version` report `5.15.123-android13-8-g697b78910a71-dirty`, Clang 14.0.7, and build time 2026-07-20; fingerprint is `qti/kalama/kalama:13/TKQ1.231222.001/eng.RPN.20260722.081626:user/release-keys`. The nearby public checkout is `93c5cc6ad1d0b807510cfa0fb1d06f47407881f9` on `lineage-23.2`; it does not contain the reported suffix, and GitHub's commit endpoint/search returns no matching commit. Exact vendor source is still unlocated; disassembly is from hash-matched installed modules. Receipt: `receipts/2026-09-20-android-kernel-build-identity.txt`. |
| Observed, fresh Android PCIe module re-pull | While Android was running, Wireless ADB pulled `pci-msm-drv.ko`, `cnss2.ko`, `ep_pcie_drv.ko`, and `mhi_cntrl_qcom.ko` read-only. Each `vermagic` matches `5.15.123-g697b78910a71-dirty`; the host and CNSS hashes match the previously disassembled files. The host binary retains symbols and BTF. Disassembly confirms the connected-DRV branch skips the conditional endpoint D3hot calls, then calls the host mode-0 path which clears ICC to `0/0`. This confirms the prior static reconstruction against files on the live boot; no suspend was run and physical PCI state remains unknown. Receipt: `receipts/2026-09-20-android-live-pcie-binary-repull.txt`. |
| Observed, exact CNSS property fallback | The live pcie0 DT has `qcom,drv-name="lpass"` but no `qcom,drv-supported`. Disassembly of the hash-matched installed `cnss2.ko` shows `cnss_pci_update_drv_supported()` checks for the first property, then uses presence of `qcom,drv-name` as its fallback and stores the boolean. Thus the exact module enables its DRV-supported path for this host. Combined with the saved mode-0 trace and absent/default-zero switch type, the connected-DRV branch is established for that successful run. This does not prove physical PCI state while asleep. Receipt: [live DT and binary fallback](receipts/2026-09-20-android-live-dt-refresh.txt). |
| Observed, live Android awake regulator summary | Read-only root access over Wireless ADB shows `pm_v6e_l1` active (`use=1`, `open=14`, 880 mV), including PCIe 0.9-V consumer `1c00000.qcom,pcie-vreg-0p9` at 80 mA and DSI0 PHY. `pm_v6e_l3` is active (`use=2`, `open=15`, 1200 mV), including PCIe 1.2-V consumer at 18 mA and DSI0. The `pm_v6e_l1_so` and `pm_v6e_l3_so` sleep-only proxy rows are idle with zero users while awake; UFS/USB/DP consumers shown in the excerpt are inactive. These are awake regulator-core accounting values, not proof of which loads or physical rails are active during suspend. Receipt: [Android awake regulator excerpt](receipts/2026-09-20-android-regulator-summary-awake.txt). |
| Observed, host-side transport check | At 06:16 UTC the previously documented Android peer at `192.168.0.163` answered ping, but TCP/5555 and tested alternate access ports refused, ADB device/mDNS discovery was empty, and USB enumeration showed only the SanDisk drive. Current peer identity was not authenticated. No Android runtime state was collected or changed. Receipt: `../../receipts/2026-09-20-android-access-check.txt`. A later Wireless ADB session has since authenticated the same Android build and boot; see the 12:11 notebook entry. |
| Observed | Armada s2idle and direct PSCI SYSTEM_SUSPEND suspend/resume successfully. AOSD/CXSD/scalar DDR and recognized detailed DDR LPM rows remain zero; APSS/other subsystem evidence advances. |
| Observed | Android's captured Apps-RSC SLEEP/WAKE set has 11 BCM plus 3 PMIC regulator commands. It includes SH1, QUP2, ACV, MC4, SH5; MC0/SH0 SLEEP requests are zero/off; LDOE1/LDOE3 have explicit sleep requests. See `receipts/2026-09-19-android-deep-rpmh/`. |
| Observed | Armada stages six BCM sleep commands (MC0, SH0, SN0, CN0, QUP1, QUP0); MC0/SH0 are nonzero. The trace proves Linux staged these commands, not that AOP accepted/applied them. |
| Observed | The PCIe host's D3cold eligibility check fails on Qualcomm root port `0000:00:00.0` (`17cb:0113`) in `PCI_UNKNOWN`. Binding `pcieport` after a temporary boot-argument test did not change that result or clear the zero counters. Original `pcie_ports=compat` was restored. |
| Observed, live Linux cross-check | On the current 7.2.3 boot (`45137c86-bb9a-4021-9973-4bc6200fc9e6`), WCN7850 (`17cb:1107`) is under enabled `pcie@1c00000`; root `0000:00:00.0` is unbound, endpoint `0000:01:00.0` is bound to `ath12k_wifi7_pci`, both are awake in D0, link is Gen2 x1, and WLAN is up. Live FDT marks `pcie@1c08000` disabled. Both devices currently show `power/wakeup=disabled`; this awake-state value does not establish suspend-time wake behavior. Raw snapshot: `../../receipts/2026-09-20-live-pcie-cross-check.txt`. |
| Observed, exact ICC attribution | Reprocessing the lossless 2026-09-20 02:03 trace with the correct brace-wrapped `string[1]` parser mapped all 18 callbacks at each EBI/LLCC node to the fresh request list. Count, tag order, and callback sum/max match; no unmatched callbacks or trace loss. The only nonzero request carrying the SLEEP tag is `1c00000.pcie` with `tag=7`, `avg=0`, `peak=500000` kB/s, at EBI, `llcc_mc`, and `qns_llcc`. Full reanalysis is in `../../sm8550-suspend-lab-runs/20260920T020326Z-96e366a5fe0a/host-analysis/icc-aggregate-attribution-reparsed.json`. |
| Source, public match only | Available Android source `Ayn8550Dev/android_kernel_ayn_qcs8550` at `93c5cc6...` has a Qualcomm `pci-msm.c` noirq path gated by `qcom,apss-based-l1ss-sleep`. When selected and L1SS is confirmed, it disables config access, host clocks/GDSC/analog rails, and clears its ICC request; it does not set root-port or endpoint D3 state in that branch. Android logs confirm WCN/WoW bus-suspend success, not the endpoint's PCI power state. Running Android reported `g697b78910a71-dirty`, not matched to this public commit. |
| Source, public match only | The same `pci-msm.c` parses `qcom,no-client-based-bw-voting`; this changes the steady-state vote shape. The live merged pcie0 DT lacks that property, and the captured exact CNSS branch clears the PCIe request via `MSM_PCIE_DRV_SUSPEND`. Public code remains a nearby source match, not the exact Android tree. [Property/helper](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L3853-L3905), [property read](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L7598-L7603), [ICC clear](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L8645-L8665). |
| Observed + source inference | Android's saved interconnect summary reports the pre-suspend PCIe request as `tag=0, avg=500, peak=800` under `llcc_mc`, `ebi`, and `qnm_pcie`, matching the nearby source's fixed-vote constants. The active merged pcie0 lacks `qcom,no-client-based-bw-voting`; the exact Android source/build remains unmatched. The later suspend trace directly records the connected-DRV ICC clear and final zero MC0/SH0 SLEEP words. See [request snapshot](../../receipts/2026-09-19-android-deep-rpmh/android-interconnect-summary.txt), [PCIe branch/TCS receipt](../../receipts/2026-09-20-android-exact-pcie-branch.md), and [public helper](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L248-L249). |
| Observed, read-only Android DTBO | `dtbo_a` is a standard table with `dt_entry_size=32`, `dt_entry_count=56`. Seven entries contain the zero-length L1SS property. Entry 51 (`0xb71079`, size 378,507) has root IDs `<0x25b 0x20000>` and `<0x1001f 0>`, matching the public RP6 DT source IDs; its model label is KalamaP HDK. Its `fragment@30` adds both `qcom,apss-based-l1ss-sleep` and `qcom,no-client-based-bw-voting`; `__fixups__.pcie1` points that fragment's `target` at base-DT symbol `pcie1`. The base symbol path and runtime selection remain unproven. See `receipts/2026-09-19-android-dtbo-a-scan.txt`. The earlier 32-by-56 interpretation was a field-order mistake and is superseded. |
| Observed merged DT + public source match | The live Android runtime DT places active WCN under pcie0 at `0x1c00000`; pcie1 at `0x1c08000` is disabled and does not own WCN. The public RP6 DTBO's L1SS/no-client properties target pcie1, so they do not configure the active WLAN host in this boot. Exact base-DT source and ABL overlay provenance remain unknown. [PCIe node map](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalama-pcie.dtsi#L5-L18), [RP6 disables pcie1](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/moorechip/kalamap-moorechip-common.dtsi#L44-L46), [candidate property](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalamap-hdk.dtsi#L36-L40). |
| Source plus exact-binary reconstruction, root and host suspend hooks | The exact CFI root-port fixup compares BTF-mapped `link_status` to `ENABLED(1)` before its teardown call; `msm_pcie_drv_suspend()` writes `DRV(3)`, and its called teardown helpers were absent in the trace. Exact noirq disassembly checks BTF-mapped `enumerated`, `power_on`, and `apss_based_l1ss_sleep` fields, then returns before teardown if any is false. Active pcie0 lacks the selecting DT property, so the APSS/L1SS body was not selected. The fixup entry itself was not separately probed; physical PCI/link state remains unknown. Exact vendor source is unavailable. |
| Observed, exact Android endpoint/host path | Exact CNSS binary plus trace show the connected-DRV caller invokes host PM-control mode 0; the host enters `msm_pcie_drv_suspend()` and clears its ICC request to `0/0`. That branch skips explicit endpoint D3hot calls. The exact physical PCI state and the required wake behavior are still unknown. Nearby source references: [DRV path](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L9877-L9944), [PM-control API](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L9951-L10073), [root-fixup guard](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/pci/controller/pci-msm.c#L9524-L9558). |
| Observed, exact installed Android modules | The A-slot `qca_cld3_kiwi_v2.ko`, `cnss2.ko`, and `pci-msm-drv.ko` were extracted read-only from the validated `vendor_dlkm_a` extent. All carry vermagic matching the recorded Android kernel `5.15.123-g697b78910a71-dirty`; identities and hashes are in `../../receipts/2026-09-20-android-exact-pcie-modules.txt`. Exact QCA code calls `wlan_hdd_bus_suspend()`, matching the saved `kiwi_v2` success log. Exact CNSS code requests D3hot only if its saved DRV-connected byte is zero; the connected branch skips the PCI D3hot calls. See the manual reconstruction in `../../receipts/2026-09-20-android-pcie-binary-decomp.md`. |
| Observed, exact Android binary call routes | `cnss_pci_suspend()` rejects a disconnected client with `-EAGAIN` when DRV support is enabled and the disable-DRV quirk is clear. `cnss_set_pci_link()` maps connected DRV to host mode 0, switch type 1 to mode 0, and default switch type 0 to normal mode 1. Exact `pci-msm-drv.ko` clears ICC in DRV suspend, normal clock teardown, and the gated APSS/L1SS noirq route. The captured mode 0 plus active-DT absence of switch type establishes the connected-DRV branch; the trace observes its `0/0` ICC update. No endpoint PCI config-state probe was installed. |
| Source inference, default ICC tag | In both the nearby Android and v7.2.3 mainline `qcom_icc_aggregate()`, `tag=0` is normalized to `QCOM_ICC_TAG_ALWAYS`; the binding defines this as AMC + WAKE + SLEEP. Thus Android's saved PCIe request (`tag=0`) would normally participate in the SLEEP bucket if left unchanged. Its final MC0/SH0 SLEEP TCS words are zero, which strongly implies the request was cleared or otherwise changed before final aggregation. This does not identify which Android suspend hook did it, and the Android kernel is a public source match rather than the exact running build. [Android aggregator](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/interconnect/qcom/icc-rpmh.c#L66-L95), [Android tag definitions](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/include/dt-bindings/interconnect/qcom,icc.h#L14-L24), [mainline aggregator](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/icc-rpmh.c#L84-L105), [mainline tag definitions](https://github.com/gregkh/linux/blob/v7.2.3/include/dt-bindings/interconnect/qcom,icc.h#L14-L24). |
| Observed, live Linux PM/capability read | At 03:08 UTC the same Linux boot was reachable by SSH over `wlp1s0` (`carrier=1`). Root `0000:00:00.0` and WCN7850 `0000:01:00.0` are D0/runtime-active with `power/control=on`, wake disabled, and `d3cold_allowed=1`; link is 5.0 GT/s x1. A bounded privileged read then found the same PM capability bytes (`01 50 03 c8 08 00`) on both functions: PME from D0, D3hot, and D3cold is supported; PMCSR reports D0 with PME enable clear. Thus missing PCI PM/PME capability is not the observed veto. This remains an awake snapshot. Receipts: `../../receipts/2026-09-20-live-pcie-pm-readout.txt` and `../../receipts/2026-09-20-live-pcie-pm-capabilities.txt`. |
| Source, current Linux root-port veto | On the current `pcie_ports=compat` boot the Qualcomm root port is unbound. In v7.2.3, PCI noirq suspend with no driver PM ops saves config and marks a D0 device `PCI_UNKNOWN`; the common D3cold helper skips only devices that are both unbound and disabled, then rejects any active device not in D3hot. This matches the previously captured root-port `PCI_UNKNOWN` veto. Its advertised PME capability is not reached because the state check fails first. The earlier one-shot pcieport-binding test still saw `PCI_UNKNOWN`, so this explains the current compat-mode path but does not fully explain the bound-port result. [PCI noirq fallback](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci-driver.c#L883-L950), [D0-to-unknown fallback](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/pci-driver.c#L624-L636), [D3cold per-device predicate](https://github.com/gregkh/linux/blob/v7.2.3/drivers/pci/controller/pci-host-common.c#L286-L310). |
| Source | Armada uses upstream DesignWare/Qualcomm PCIe PM plus patches 0513/0520. If the generic D3cold check fails, `dw_pcie_suspend_noirq()` returns before host teardown and leaves `pci->suspended` false. In the qcom fallback branch, direct deep (`PM_SUSPEND_MEM`) skips the OPP update; with the OPP-based path this leaves the active OPP request. The `opp-suspend` floor from 0520 is selected only in the non-S2RAM branch. |
| Source, 0513/0520 nuance | Patch 0513 does call its OPP helper when the host really suspended; for `PM_SUSPEND_MEM` that helper passes `NULL`, which drops associated OPP bandwidth. But when D3cold is vetoed, the helper call is nested inside the non-`PM_SUSPEND_MEM` fallback, so deep suspend skips it. The patch therefore does not bypass the PCI safety check; it preserves the active request when the host remains running. |
| Source, OPP path and tag feasibility | SM8550 has an OPP table, so QCOM PCIe uses OPP-managed paths rather than retaining direct ICC handles. At 5 GT/s x1 the OPP sets `pcie-mem=500000` and `cpu-pcie=1` kB/s, with `low_svs`. If D3cold is vetoed, DesignWare returns 0 before stopping the link or setting `pci->suspended`; the direct-ICC fallback would lower memory bandwidth to 1, but the OPP branch leaves the active OPP for `PM_SUSPEND_MEM`. `icc_set_tag()` only updates metadata; `icc_set_bw()` triggers aggregation/application, and the OPP paths are not exposed to QCOM PCIe. Static ACTIVE_ONLY tagging would also remove the existing s2idle sleep floor. Detailed source links and proposed A/B: `../../receipts/2026-09-20-android-live-pcie-validation.md`. |
| Observed, source mapping | Mainline SM8550 maps BCM MC0 to EBI and SH0 to LLCC. In the 02:03 run, the final Apps-RSC SLEEP words for MC0 (`0x50000`) and SH0 (`0x50004`) were both `0x600001dc`, encoding 476. The exact live callback trace shows the sole nonzero SLEEP-tagged client at those nodes is PCIe's 500,000 kB/s peak request. This establishes the origin of the staged floor; it does not prove the floor prevents AOSD/CXSD/DDR residency or that firmware accepted it. |
| Observed/source | `interconnect_summary` omits request enabled state, while `icc_set_bw` tracepoints omit tags. The live provider-callback capture resolves both: fresh-list order and tag values matched at all three nodes, and callback sum/max matched generic `icc_set_bw` aggregates. A system-wide `path_init` probe created false mutation noise, so it has been removed from future profiles; request-count/tag-order validation catches target-list changes, with path removal and retag probes retained as fail-closed checks. |
| Source, Linux v7.2.3 | `icc_summary_show()` and `aggregate_requests()` both traverse the node's `req_list` using the same hlist iteration order. The qcom RPMh provider callback receives each request's tag/avg/peak before the core `icc_set_bw` tracepoint reports the node aggregate. This provides a source-grounded way to attach callback inputs to the fresh request list, with the generic aggregate tracepoint as a cross-check. Sources: [summary traversal](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L48-L69), [aggregate traversal](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L255-L283), [ICC update tracepoints](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/core.c#L673-L720), [qcom RPMh aggregate](https://github.com/gregkh/linux/blob/v7.2.3/drivers/interconnect/qcom/icc-rpmh.c#L69-L104). |
| Harness, live validation and local fix pending | The 02:03 on-device run entered/resumed deep successfully (8.783 s observed sleep, same boot, RTC wake) but its wrapper marked the run failed because cleanup metadata expected an old `path_init` definition. The trace instance/probes were removed and Wi-Fi recovered. The unchanged trace has zero loss; a corrected offline parse validates exact attribution. The local harness now handles the kernel's brace-wrapped `string[1]` names, no longer installs the noisy `path_init` probe, and updates legacy cleanup matching. Local tests pass. The original device-derived report remains preserved beside the separate host reanalysis. |
| Observed/source | Android SLEEP TCS contains LDOE1/LDOE3 sleep-context commands. Mainline qcom-rpmh-regulator currently submits ACTIVE_ONLY requests and does not provide an equivalent sleep-context API. The awake regulator summary does not show what firmware applies in suspend. |
| Source, nearby Android match only | Downstream `rpmh-regulator.c` parses each proxy's `qcom,set` into independent active/sleep participation, aggregates separate requests, stages a `RPMH_SLEEP_STATE` update, and stages the restored active values in `RPMH_WAKE_ONLY_STATE` when they differ. Android's LDOE1/LDOE3 `-so` proxies are sleep-only while `-ao` proxies are active-only; the captured TCS disables them for SLEEP and re-enables them for WAKE. This explains the state-specific mechanism, but not whether every physical consumer is safe to depower for its wake source. In the saved capture, HIF IRQ 324 and a WLAN wake packet are logged in the first aborted attempt, while the kernel reports `[timerfd]` as pending. Earlier eventpoll analysis shows this label can name an EPOLLWAKEUP source associated with a watched timerfd; it does not prove timer expiry or identify the abort cause. The subsequent deep entry reached CPU shutdown and reported `pm8xxx_rtc_alarm` as its wake IRQ. This does not demonstrate Wi-Fi/PCIe-initiated wake from the deeper path. [Run receipt](../../receipts/2026-09-19-android-deep-rpmh/android-icc-suspend-run.log), [kernel excerpt](../../receipts/2026-09-19-android-deep-rpmh/android-icc-suspend-excerpt.txt), [aggregation](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/regulator/rpmh-regulator.c#L665-L707), [SLEEP and WAKE_ONLY submissions](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/regulator/rpmh-regulator.c#L800-L855), [active restore](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/regulator/rpmh-regulator.c#L876-L904), [`qcom,set` parsing](https://github.com/Ayn8550Dev/android_kernel_ayn_qcs8550/blob/93c5cc6ad1d0b807510cfa0fb1d06f47407881f9/drivers/regulator/rpmh-regulator.c#L1910-L1920). |

| Source, upstream-quality design direction | In v7.2.3 the mainline RPMh send helper hardcodes `RPMH_ACTIVE_ONLY_STATE`, and its regulator op tables expose no suspend enable/disable/mode hooks. An upstream design should use the regulator core's standard suspend-state constraints and implement the RPMh provider support to stage per-regulator SLEEP commands plus appropriate WAKE_ONLY restoration from the active state. This is preferable to copying downstream `qcom,set` proxy nodes, but must account for shared-rail constraints and should be enabled only after board owners establish that consumers are quiesced or their wake paths remain powered. [Mainline send helper and ops](https://github.com/gregkh/linux/blob/v7.2.3/drivers/regulator/qcom-rpmh-regulator.c#L197-L209), [regulator ops](https://github.com/gregkh/linux/blob/v7.2.3/drivers/regulator/qcom-rpmh-regulator.c#L393-L433). |
| Source, regulator consumers | In the nearby Android Kalama/RP6 DT, LDOE1 supplies PCIe 0.9-V PHY, UFS QREF, USB EUSB2, DSI PHY, and DisplayPort PHY analog; LDOE3 supplies PCIe 1.2-V PHY/PLL, UFS PLL, USB EUSB2, USB3/DP QMP core, and DSI 1.2-V PHY. RP6 uses the public DSI0 panel overlay; DSI1 is disabled in its board common DTSI. Thermal I-sense references use separate active-only L1E/L3E proxies. Armada's Nova DT has the same broad PHY consumers, and no `regulator-state-mem` descriptions for these rails. The list establishes wiring, not which links remain wake-capable during Android's captured sleep. [Regulator proxies](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalama-regulators.dtsi#L690-L787), [UFS PHY](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalama-qrd.dtsi#L148-L166), [USB PHYs](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalama-usb.dtsi#L112-L145), [DSI/DP rails](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/display/display/kalama-sde.dtsi#L249-L291), [thermal active-only refs](https://github.com/LineageOS/android_kernel_ayn_qcs8550-devicetrees/blob/a345661c01d7e18b7dfa04dd27690655ff36bd5d/qcom/kalama-thermal.dtsi#L213-L219). |
| Unknown | The exact Android source revision corresponding to the installed build beyond the exact inspected A-slot module binaries and nearby public source; root/endpoint PCI config state during sleep; whether PCIe/WCN, UFS, USB, display, or thermal paths must remain powered for each wake source; whether reducing only Armada's PCIe SLEEP request allows residency; whether any LDOE consumer must remain powered for a required wake path. The Android noirq APSS/L1SS body is resolved as skipped for active pcie0; the root-fixup entry itself remains unprobed, though its teardown branch is gated out by the observed DRV state and has no inner-function hits. |

## Exact Android module evidence

The active A-slot `vendor_boot` ramdisk confirms the loaded Android modules use
the same `g697b78910a71-dirty` build suffix. The exact `icc-bcm-voter.ko`
disassembly sends state arguments 2/1/0 to ACTIVE_ONLY/WAKE_ONLY/SLEEP, matching
the mainline BCM-voter implementation. The exact `rpmh-regulator.ko`
disassembly sends per-proxy aggregates in those three contexts, confirming the
sleep-context mechanism previously inferred from nearby public source. This
does not establish firmware acceptance or physical rail state. Android's
`ACV`, `QUP2`, and `SH1` resources also exist in the mainline SM8550 provider.
The earlier conclusion that MC4/SH5 ownership was unknown is superseded by
the exact `dcvs_fp` binary/live-DT attribution below. Keep these as separate
request-generation facts, not proof of why residency advances.
Detailed extraction, hashes, and ELF offsets: [module receipt](../../receipts/2026-09-20-android-live-rpmh-module-decomp.md).

The Android `.ko` files cannot be loaded into the running 7.2.3 kernel: the
exact `dcvs_fp.ko` is built for Android 5.15.123, expects `modversions`, and
imports `rpmh_init_fast_path()`/`rpmh_update_fast_path()`, which are absent
from Linux. Armada already has its RPMh, qcom regulator, interconnect, and
Qualcomm PCIe drivers built in. The useful route is to port specific behavior
to those Linux APIs, not mount or force-load Android modules. The static
MC4/SH5 subset was already tried with a native 7.2.3 module and was
insufficient in that run. Details: [Android module reuse analysis](android-module-reuse.md).

## Current hypothesis ranking and decision

1. **The retained PCIe request is the strongest directly observed Linux-side
   correlate.** PCIe is the only nonzero SLEEP-tagged EBI/LLCC client and
   contributes the staged 476/952 MC0/SH0 words. Armada's root port fails
   D3cold eligibility in `PCI_UNKNOWN`; the DesignWare host returns before
   teardown and the active request remains. Android's connected-DRV path
   clears its ICC request to 0/0 before final TCS staging, while the residency
   counters advance. This is strong correlation, not causal proof.
2. **MC4/SH5 SLEEP/WAKE_ONLY pair alone was insufficient in the tested run.**
   The temporary consumer queued the Android-matched pair; the Apps-RSC trace
   contained both commands. The existing MC0/SH0 floor remained
   `0x600003b8`, and AOSD/CXSD/scalar DDR did not advance during the observed
   9.319 seconds of direct deep suspend. This is one bounded run, not proof the
   pair is irrelevant or firmware-accepted. Full receipt:
   [MC4/SH5 A/B](receipts/2026-09-20-rpmh-dcvs-pair-ab.md).
3. **LDOE1/LDOE3 sleep-context requests may affect shared PHY or wake paths.**
   Android stages them and mainline's RPMh regulator path does not. Several
   active consumers share these rails, so this remains the highest-risk
   hypothesis and is not the next experiment.

The Wi-Fi-off A/B reduced the MC0/SH0 word from 952 to 476 without advancing
AOSD/CXSD/DDR; binding `pcieport` also left the root veto and counters
unchanged. The selected OPP A/B keeps the active link's `low_svs` power-domain
corner and reduces only PCIe-MEM from 500000 to 1000 kB/s. It remains
undeployed because the linked scratch image dropped scheduler-extension config
options required on the device. Do not bypass the generic D3cold check, force a
PCI D-state, manually change an ICC vote, or infer safe D3 support from
`d3cold_allowed=1` alone.

## Work checklist

### 1. Android versus Armada PCIe suspend path — do first

- [x] Inspect the public `pci-msm.c` implementation and the RP6 Android DT
  overlay; mark their applicability provisional where the actual vendor base
  DT/build is missing.
- [x] Resolve the nearby public driver's `qcom,no-client-based-bw-voting`
  behavior: it changes the steady-state vote form. The source has separate
  host and endpoint-client suspend paths that can clear ICC; this property
  does not prove which runtime path ran.
- [x] Read the Android slot `_a` DTBO partition without changing device state;
  parse its standard 32-byte entries and identify the seven property-bearing
  overlays. Entry 51 matches the public RP6 SoC/board IDs.
- [x] Resolve entry 51's `fragment@30` target fixup to the base-DT symbol
  `pcie1`.
- [x] Resolve the public base symbol: `pcie0` is at `0x1c00000`, `pcie1` at
  `0x1c08000`; the nearby public RP6 common DTSI disables `pcie1`. Cross-check
  the current Armada live FDT and WCN parent: active WLAN is under `pcie0` at
  `0x1c00000`. This weakens the overlay-property explanation for active WLAN.
- [x] Inspect the merged Android runtime DT: active WCN pcie0 lacks the L1SS
  and no-client-vote properties, while pcie1 is disabled and carries them.
  This closes their applicability to the active host; exact ABL overlay
  provenance remains unproven.
- [x] Capture the exact running Android build identity and check the nearby
  public checkout/GitHub for its kernel suffix. The suffix is not present; the
  nearby source remains a public match, while exact installed-module
  disassembly anchors runtime conclusions.
- [ ] Obtain the matching vendor source tree or build source if it becomes
  available; the public checks did not locate it.
- [x] Identify the current Armada runtime PCIe compatible, bound endpoint,
  and live DT status. Root port is unbound, WCN is bound to ath12k, both are
  awake in D0; WCN is under pcie0. This is not a suspend-time snapshot.
- [x] Compare nearby Android root-fixup, APSS/L1SS host, and endpoint-driver
  suspend routes. The public `MSM_PCIE_DRV_SUSPEND` API independently clears
  ICC and can suppress the later root fixup by changing link status. Exact
  A-slot module disassembly plus the instrumented run now confirm the CNSS
  connected-DRV caller, host mode 0, and the `0/0` ICC clear.
- [x] Run one bounded Android `deep` capture through `forceSuspend()` with an
  armed RTC wake. The call succeeded, firmware sleep records advanced, and
  Wi-Fi/ADB recovered. The suspend-boundary hook saw only ACTIVE_ONLY DCVS
  votes, not a PCIe request. This does not identify the PCIe callback route.
- [x] From Linux, inspect and manually reconstruct the exact A-slot
  `qca_cld3_kiwi_v2.ko`, `cnss2.ko`, and `pci-msm-drv.ko` without mounting or
  changing Android partitions. The connected-DRV versus D3hot branch, host
  mode selection, and all identified ICC-clear routes are recorded in the
  binary-decomp receipt.
- [x] Pull live split-BTF and map exact PCIe host private-field offsets to the
  installed module. Decode `msm_pcie_drv_suspend()` setting `link_status=DRV`
  and the root late-fixup requiring `ENABLED`; its teardown branch is skipped
  for the captured mode-0 route, matching the absent inner-call hits. The
  fixup entry itself was not separately probed.
- [x] Decode exact noirq gates. Active pcie0 lacks
  `qcom,apss-based-l1ss-sleep`, so the `apss_based_l1ss_sleep` flag is not set
  and the noirq callback returns before APSS/L1SS clock, regulator, analog,
  and ICC teardown. This resolves the previous callback-entry ambiguity.
- [x] Compare default ICC-tag semantics: both inspected aggregators map
  `tag=0` to AMC + WAKE + SLEEP, so Android's pre-suspend PCIe request cannot
  explain a zero SLEEP command merely by being untagged.
- [x] Capture the actual successful Android CNSS/host branch and final staged
  TCS. Mode 0 reaches connected-DRV suspend and clears PCIe ICC to 0/0; MC0/
  SH0 SLEEP words are zero while firmware counters advance. The endpoint's
  PCI config state remains unknown; the host noirq callback entry does not
  prove APSS/L1SS shutdown.
- [x] Capture a separate Android generic PCI PM callback trace. Host, root
  port, endpoint and noirq callbacks return success; no PCI state setter hits
  are recorded. Physical sleep-time PCI state remains unknown.
- [x] Pull the installed Android modules through Wireless ADB and verify all
  three SHA-256 values match the previously decompiled A-slot files. Exact
  module identity is established; exact vendor source revision is not.
- [x] Re-pull the host, CNSS, endpoint, and MHI modules from the running
  Android boot and verify their `vermagic`; exact host/CNSS hashes match the
  prior disassembly. This was read-only and did not repeat a suspend.
- [ ] Directly sample root/endpoint PCI state during sleep or otherwise prove
  the physical link state, and validate PCIe/WCN wake. The connected-DRV
  branch makes no explicit endpoint D3hot request. The exact APSS/L1SS body is
  skipped; the root-fixup teardown is gated out by `link_status=DRV`, but the
  callback entry was not separately probed.
- [x] Trace source ordering between the PCI `SUSPEND_LATE` fixup and host
  platform `suspend_noirq`; the captured trace has no `msm_pcie_clk_deinit()`
  hit, consistent with the late-fixup teardown route not running after CNSS
  entered DRV mode. Treat this as a traced absence, not proof of physical
  PCIe power state.
- [x] Compare that call path with Linux v7.2.3 `pcie-qcom.c`, DesignWare host
  PM, generic D3cold eligibility, Armada patches 0513/0520, and the PCI core's
  no-driver `PCI_UNKNOWN` suspend fallback.
- [x] Separate source from runtime evidence: the nearby source explains the
  paths, while exact installed-binary probes establish the connected-DRV
  branch and ICC clear; actual PCI state during sleep remains unobserved.

### 2. Attribute the MC0/SH0 floor

- [x] Inspect the Linux v7.2.3 summary and aggregation paths, qcom RPMh
  aggregation, and tag-bit definitions. Both summary and aggregation traverse
  `req_list` in the same order; the core aggregate tracepoint can validate
  callback input sums/maxima.
- [x] Add a read-only `icc-attribution` harness profile. It captures each
  request passed to the EBI/LLCC qcom aggregate callback, maps by fresh
  `interconnect_summary` order, invalidates the mapping on path/tag changes,
  checks trace loss and generic aggregate totals, and records final staged
  Apps-RSC SLEEP commands. It does not modify votes.
- [x] Run local syntax, parser, and harness smoke tests. They pass.
- [x] Run one 10-second profile on the Nova; the suspend/resume succeeded. The
  first host parse failed closed because kprobe string-array names were
  brace-wrapped and the run wrapper had stale cleanup metadata.
- [x] Reparse the unchanged, lossless trace. Exact order/count and aggregate
  checks pass for EBI, LLCC, and qns_llcc. PCIe is the sole nonzero
  SLEEP-tagged client (`500000` peak); MC0/SH0 each stage encoded `476`.
- [ ] Determine whether this request is a cause of zero AOSD/CXSD/DDR residency;
  this requires a source-justified safe A/B, not an awake-snapshot calculation.

### 3. Compare regulator sleep contexts

- [x] Map Nova's Armada-DT consumers of LDOE1/LDOE3: PCIe PHY, UFS PHY,
  USB HS/DP PHY, and DSI0. Android merged-DT mapping remains open.
- [x] Inspect the nearby Android regulator driver: it represents active and
  sleep votes separately and queues restored active values in WAKE_ONLY state.
- [x] Verify mainline qcom-rpmh-regulator does not emit the corresponding
  SLEEP/WAKE_ONLY requests; standard suspend-state DT alone is not enough.
- [x] Map principal LDOE1/LDOE3 consumers in the nearby Android RP6 DT: PCIe,
  UFS PHY, USB2 and USB3/DP PHY, DSI0; note thermal active-only proxies.
- [x] Capture the live Android awake regulator summary read-only. It confirms
  active PCIe/DSI consumers and separate idle sleep-only proxy rows; it does
  not establish suspend-time rail state or wake safety.
- [ ] Establish shared-rail wake safety. The saved Android log confirms WCN
  WoW setup and bus suspend. An HIF wake IRQ appears in an incomplete attempt,
  while the kernel reports `[timerfd]` as a pending wakeup-source label. The
  source audit says that label can come from an epoll-watched file and does not
  prove timer expiry or cause; the completed deep attempt wakes by RTC. There
  is no completed deep Wi-Fi/USB wake evidence or matching UFS/USB/DSI suspend
  record. See the [wake evidence boundary receipt](../../receipts/2026-09-20-android-wcn-wake-evidence-boundary.md).
- [x] Describe an upstream-quality regulator API/DT model that can emit sleep
  RPMh requests. Use regulator-core suspend constraints plus provider-side
  SLEEP requests and WAKE_ONLY restoration; `regulator-state-mem` alone is
  insufficient until the mainline provider implements these operations. See
  the source/design row in the evidence table above.

### 4. Selected A/B and deployment gate

- [x] Rank the retained PCIe bandwidth request as the strongest directly
  observed Linux-side correlate; preserve other differences as alternatives,
  not proven causes.
- [x] Identify the exact Android baseline MC4/SH5 SLEEP and WAKE_ONLY pair.
- [x] Run the MC4/SH5 pair as the first test-only A/B. It left active PCIe/WCN
  bandwidth, PCI state, and shared regulators unchanged, but it did not
  restore the observed AOSD/CXSD/scalar DDR counters.
- [x] Select the Nova-only 1,000 kB/s PCIe-MEM OPP reduction as the next
  diagnostic A/B. Its source/object/DTB are prepared; the old linked image
  was blocked by config mismatch. The scratch config now matches live, pending
  relink. See the [target-build receipt](receipts/2026-09-20-nova-opp-target-build.md),
  [config-gate receipt](receipts/2026-09-20-pcie-opp-image-config-gate.md),
  and [config-reconcile receipt](receipts/2026-09-20-pcie-opp-config-reconcile.md).
- [x] Reboot Android to the Nova's default Linux and verify bootc current and
  rollback deployments. Both use the same digest; no image layer was changed.
- [x] Verify the live RSC parent and child relationship and both required RPMh
  symbols. The existing `17a00000.rsc:regulators-0` child makes an OF overlay
  unnecessary; a module can use it as the RPMh API client.
- [x] Build the test module and check its AArch64 ELF, exact vermagic, imported
  exports, live kallsyms names, and live BTF layout/state values. The local
  `Module.symvers` is absent and live `CONFIG_MODVERSIONS` is disabled. Kconfig
  preparation normalized some unsupported entries; required module/RPMh/
  CMD-DB and architecture settings match, but full source/config identity
  remains open.
- [x] Attempt one insertion of the first module artifact. The kernel rejected
  it before init because its `this_module` section was 64 bytes smaller than
  live `struct module`; no RPMh request was staged and no suspend was run.
  See the [failure receipt](../../receipts/2026-09-20-rpmh-dcvs-pair-insertion-failure.md).
- [x] Rebuild with `CONFIG_DEBUG_INFO_BTF_MODULES=y`; verify `struct module`
  size/member offsets, the probe's relevant struct layouts, and its API
  prototypes against live BTF. Exact source/image identity remains unproven.
- [x] Load the module and verify its CMD-DB lookup and SLEEP/WAKE_ONLY success
  log; the trace then showed both contexts in the Apps-RSC TCS send set.
- [x] Run the RTC-bounded direct-`deep` test and compare the final SLEEP/WAKE
  words and before/after AOP/RPM sleep records. The MC4/SH5 pair alone did not
  advance AOSD/CXSD/scalar DDR.
- [x] Reboot the unchanged deployment to clear the module's cached RPMh pair.
  The new boot is healthy with the same kernel/image version and Wi-Fi/SSH up;
  the module is absent and suspend stats reset to 0/0. Tracefs instance cleanup
  was recorded by the harness before reboot.
- [x] Run one 10-second-minimum RTC-woken direct-deep A/B with
  `rpmh-aoss` tracing and capture the Apps-RSC command payloads plus residency
  counters. The kernel lacks `rpmh_rsc_snapshot`, so this proves staged
  messages, not a firmware acknowledgment. See the A/B receipt.
- [x] The MC4/SH5 pair was staged but AOSD/CXSD/scalar DDR remained zero.
- [x] Source-check the PCIe-MEM OPP reduction as the next A/B; keep it
  undeployed until the scheduler config and rollback gates pass.
- [ ] For any justified A/B, record all of the following at matched boundaries:
  1. PCIe host suspend result.
  2. PCIe ICC/OPP request before suspend.
  3. final MC0/SH0 SLEEP TCS words.
  4. complete Apps-RSC SLEEP/WAKE command set.
  5. LDOE1/LDOE3 request context, if relevant.
  6. PSCI SYSTEM_SUSPEND result.
  7. AOSD/CXSD/scalar DDR before and after.
  8. detailed DDR IDs before and after.
  9. Resume health and PCIe/Wi-Fi function.
- [ ] Do not use battery drain as the verdict for a short diagnostic run.

## Safety and continuity constraints

- The current OS is stock Armada Linux 7.2.3 with a clean bootc default order,
  no staged/pending deployment, and verified stock `KERNEL`/`KERNEL.BAK`.
  The candidate boot previously failed to return SSH and the user observed
  “Preparing Armada”; its precise failure phase is unknown. Do not rerun the
  candidate or suspend test until its boot failure is diagnosed and recovery
  remains available.
- Do not force PCI D3hot, bypass `pci_host_common_d3cold_possible()`, change
  `pcie_ports` again, manually alter ICC votes, blindly disable shared rails,
  send AOSS/QMP commands, or access guessed MMIO/AOP memory.
- Do not repeat the closed sleep-stats offset experiment or change `qcom_stats`
  offsets. The corrected RPMh probe was loaded only for the completed A/B; the
  device was rebooted afterward and its request cache is cleared. The probe is
  now absent; do not reload it for the next experiment.
- The on-device `sm8550-pcie-test-rollback.timer` is disabled. Its service is
  conditioned on `pcie_ports=compat` being absent, so it would not guard the
  current OPP candidate, which retains `pcie_ports=compat`. Do not treat the
  old timer as recovery coverage.

## Next action

The stock Linux boot remains the only deployed boot; the candidate is not
staged. Its exact prior failure stage is unknown because no candidate boot ID
or pstore record survived. The newest `20260920-05` candidate starts its
120-second initrd timer from `basic.target.wants` and orders the timer before
`basic.target` and `dracut-pre-mount.service`; it restores the known stock ESP
image if switch-root has not begun. The existing five-minute root-systemd
timer covers later failures. Neither timer can help if the kernel or initrd
systemd fails before the `basic.target` transaction starts. No remote
ABL/BootNext route is exposed, so that residual case still needs manual ABL
recovery. Do not stage or reboot the candidate until that manual recovery is
available. The PCIe-MEM OPP A/B remains the best single-variable test once this
gate is met. Do not directly load Android modules; port behavior against Linux
7.2.3. For persistent Android Wireless debugging, wait
until Android is reachable and add a Magisk late-start helper rather than
editing its unmounted userdata from Linux. Do not select **UNINSTALL CFW** in
ABL if recovery is needed. See the
[Android rollback receipt](receipts/2026-09-20-android-esp-rollback.md),
[ABL access notes](receipts/2026-09-20-post-apply-device-reachability.md), and
completed MC4/SH5 receipt:
[`rpmh-dcvs-pair-ab.md`](receipts/2026-09-20-rpmh-dcvs-pair-ab.md).

The archived Linux trace and host reanalysis remain under
`.external-research/sm8550-suspend-lab-runs/`; do not edit their raw data.

## Working files

- Chronology, corrections, and test receipts: [lab-notebook.md](lab-notebook.md)
- Latest read-only Linux PM snapshot: [live PM receipt](../../receipts/2026-09-19-live-pm-readout.txt)
- Android SLEEP/WAKE TCS and ICC excerpts: `../../receipts/2026-09-19-android-deep-rpmh/`
- Latest Android PCIe callback, module-hash, and Linux OPP source audit:
  [validation receipt](../../receipts/2026-09-20-android-live-pcie-validation.md)
- Existing harness: [sm8550_suspend_lab.py](sm8550_suspend_lab.py)
- Kernel/package patch stack: sibling checkout
  `../../../armada-packages/kernel/patches/`
