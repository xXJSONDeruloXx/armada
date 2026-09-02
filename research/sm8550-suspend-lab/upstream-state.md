# SM8550 suspend lab upstream state

Inspection date: 2026-09-01 (America/New_York)

The commit IDs below were obtained from the repositories' live remote HEADs on
the inspection date. They are provenance anchors, not floating branch names.

| Source | Branch | HEAD | Relevant observation |
|---|---|---|---|
| [armada-os/armada](https://github.com/armada-os/armada) | `main` | `71e45aa956ad53834ebaaefd6070f28f43d4462d` | Nova profile is SM8550 and has no per-device suspend override, so the global fake default remains the normal policy. The shipped real path is `/usr/libexec/armada/suspend-dispatch` -> `systemd-sleep`; the autonomous lab agent invokes that dispatcher directly and writes the post-resume snapshot after it returns. |
| [armada-os/armada-packages](https://github.com/armada-os/armada-packages) | `main` | `2c93e73cbe1bcf4d443495e94fbaa5e7a8cf7141` | Kernel `VERSION=7.2`; the patch manifest includes Armada's `0513` PCIe suspend-OPP behavior and `0520` SM8550 suspend-only OPP. It does not include the Qualcomm DWC3 skip-PHY change or Thorch's RPMh regulator-state pair. |
| [ROCKNIX/distribution](https://github.com/ROCKNIX/distribution) | `next` | `1ebff24f36501fb6493beb2bf83bf2604536d9aa` | Current SM8550 tree retains the shared Nova -> RP6 DTS shape and the older PCIe/IPCC/SM8550 patch lineage. The inspected current tree has no Armada-style `0513`/`0520` suspend-OPP pair. |
| [thorch-os/thorch](https://github.com/thorch-os/thorch) | `main` | `82e7472e6cad5c08a55c3aef92ef5be218621b2c` | Carries `0218` qcom-rpmh suspend-state support, `0219` regulator-core s2idle mapping, `0220` PCIe suspend-OPP selection, `0221` SM8550 suspend OPP DT, an s2idle systemd policy, and DWC3 autosuspend. These are Thor-owned changes and are not assumed valid for Nova. |
| [shuuri-labs/pocknix-os](https://github.com/shuuri-labs/pocknix-os) | `main` | `120f7d74b5430b181c81bf195ec4478171618b19` | Current SM8550 BSP pins s2idle, disables CPU0 state1 while awake and enables it only in the sleep window, and autosuspends the primary DWC3 controller. Nova still inherits the RP6 DTS. |
| [jaewun/qcom-aop-debug](https://github.com/jaewun/qcom-aop-debug) | `main` | `89a19b70f554e17ddcf64c3e84037b6532202137` | Provides observation-oriented docs/collection and experimental AOP debugfs work. Its own documentation warns that monitor bits are firmware-domain observations, not direct Linux-device attribution; no undocumented AOP/QMP command is used by this harness. |
| [torvalds/linux](https://github.com/torvalds/linux) | `master` | `786262be6048deab760f68c8acc2c85607165894` | Mainline DWC3 Qualcomm code does not contain the skip-PHY-init software-node change; qcom PCIe still drops the OPP to `NULL` in suspend; qcom-rpmh has no suspend-state ops; qcom RSC has no v3 timeout diagnostic helper. |

## Current Armada inspection

At inspection start, the checkout was clean at Armada `71e45aa`. `Containerfile` pins the
kernel package image to:

```text
ghcr.io/armada-os/armada-packages/kernel@sha256:d7ec91a4dc38557e7efed0ee7ea39af509614cc8bd2448fd7f59ac8c96fffbe8
```

The userspace path is important for the lab. The systemd override installs
`ExecStart=/usr/libexec/armada/suspend-dispatch`; the dispatcher selects the
requested `mem_sleep` mode and then calls `systemd-sleep`, so the system-sleep
hooks run. The lab's autonomous root-owned agent invokes that shipped
dispatcher and waits for its return; it does not directly start
`systemd-suspend.service`. The SM8550 sleep hook enables CPU0's deep idle state
only inside the real-suspend window and restores it before rendering. The USB
rule changes the idle DWC3 controller and USB devices to runtime-PM `auto`.

The existing `armada-sleep-debug` utility already reports useful wake, IRQ,
cpuidle, qcom-stats, audio, thermal, and power-supply information. It stores a
single mutable state directory and enables PM/TSENS debug switches, so the new
runner invokes it inside a per-run directory and records/restores those
switches around the call.

## Relevant current Linux/Qualcomm work

- The July 2026 [DWC3 Qualcomm skip-PHY-init proposal](https://lkml.iu.edu/2607.2/15543.html)
  explains the extra USB-core `phy_init` reference that can keep a Qualcomm
  host PHY from reaching `phy_exit` during system suspend. A follow-up records
  an ACK, but the change is not in the inspected Linux master.
- The August 2026 [RPMh RSC v3 diagnostic series](https://lkml.iu.edu/2608.1/07181.html)
  adds reverse CMD-DB address/name decoding and structured timeout diagnostics.
  Qualcomm's `qualcomm-linux/kernel` merged its three commits into
  `qcom-6.18.y` on 2026-08-20 (RSC commit `403d2a6ac9213a7454fa31744f8ad6089d368cd8`;
  CMD-DB commits `946390ea27648ac0e76ecd1950405f1ce3ed5640` and
  `b98e95ae006480d4d6c384725beede55ed3092d7`). Torvalds Linux master and
  Armada's current kernel package still do not carry it. It is useful
  instrumentation if the target kernel can accept it; it is not a reason to
  send undocumented firmware commands.
- Mainline does contain recent qcom-rpmh readback work, but that is distinct
  from Thorch's SLEEP/WAKE suspend-state implementation. The inspected
  [qcom-rpmh regulator history](https://github.com/torvalds/linux/commits/master/drivers/regulator/qcom-rpmh-regulator.c)
  therefore does not close that gap.
- The [Qualcomm PHY runtime-PM race fixes](https://lkml.iu.edu/2607.2/07927.html)
  and the [PSCI CPU-PM-domain RFC](https://lkml.iu.edu/2608.2/06516.html) are
  relevant background for resume/runtime-PM behavior, but neither is evidence
  of a Nova-specific suspend fix.

## Working conclusion before hardware measurement

There are credible candidate blockers, especially residual DWC3 PHY references
and the SM8550 storage/PCIe/RPMh vote interactions, but the current Nova has
not been measured by this lab yet. The first hardware run must establish the
actual boot image, sleep mode, AOSD/CXSD behavior, IRQ deltas, and runtime-PM
state before any kernel patch or regulator constraint is proposed.

## Post-measurement status

The historical pre-measurement paragraph above is retained as provenance. The
current Nova is now measured on Armada `20260830.71e45aa` / kernel `7.2.0`:
11 uninstrumented stock short cycles passed the real-suspend success gates,
and scoped UFS plus RPMh/AOSS/ICC traces have been collected. The traces show
Linux RPMh sleep/wake-set programming but do not expose firmware acceptance or
residency decisions. No kernel, package, firmware, AOP, or boot artifact has
been changed; candidate-fix work remains pending safer source/provenance
instrumentation.

The later read-only root preflight at
`/Users/kurt/Developer/sm8550-suspend-lab-runs/preflight-20260901T170713Z-4aa81059d0be.json`
found readable `interconnect_summary`, `interconnect_graph`,
`pm_genpd_summary`, and full `cmd-db` debugfs output on the current boot. The
four `qcom_aoss` control-like files reject reads with `EINVAL`; no write was
attempted. These are awake-state diagnostic interfaces, not evidence that a
particular vote persisted through suspend. The package source at `2c93e73`
still contains no RSC/AOP diagnostic patch, and the external `qcom-aop-debug`
material is not installed or invoked. The ten-cycle stock target is exceeded
by 11 clean current-image cycles; blind repeats remain deferred while the safe
observation-only instrumentation boundary is reviewed.

The package branch later advanced to `f595f0f` with the observation-only
successful-path RSC snapshot notifier. It was built as
`armada-kernel-7.2.0.tar.zst` (SHA-256
`6ad795b7a50318d1af7e75ccc7e9576edefea6700b4cea6a38e14374935c56c3`) and
booted as a uniquely tagged local OCI layer. The corrected RSC run showed the
sleep/wake TCS contents persisted with no Linux-visible status error. A live
UFS trace then resolved IRQ 170 and showed all UFS interrupt/command activity
around the transition, not inside the deep-sleep interval; the earlier IRQ-169
receipt is retained as a filter-correction failure. This rules out the
historical SDHCI storm as the next fix target but does not distinguish AOP
policy/acceptance from residency-counter semantics.
