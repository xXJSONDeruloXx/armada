# Nova PCIe sleep-bandwidth diagnostic proposal

This is a prepared, not-applied experiment for the Linux-only suspend lab. It
is deliberately split because the kernel C change belongs in the package's
Linux patch series, while the board property and test OPP belong in the
vendored Nova DTS.

- `pcie-qcom-diagnostic-opp.patch` applies to Linux v7.2.3 after Armada
  patches 0512/0513. It adds a test-only OPP setter and uses it only in the
  host-unsuspended, `PM_SUSPEND_MEM`, OPP-managed fallback when the Nova DT
  property is present.
- `rpnova-diagnostic-opp.diff` applies at the armada-packages repository root.
  It adds the property and a 2 Hz synthetic OPP only to the Nova board file's
  existing `pcie0_opp_table`. The OPP preserves `rpmhpd_opp_low_svs` and the
  CPU path's 1 kB/s floor while lowering only the PCIe memory path from the
  active 500,000 kB/s to 1,000 kB/s.

This does not set PCI D-state, bypass D3cold eligibility, change regulators,
retag ICC paths, touch sleep-stat offsets, or change `opp-suspend-1`. It is
not a production fix. If the test OPP is unavailable or cannot be applied, the
suspend callback returns the error and the suspend attempt should fail closed.

The C test path tracks whether it selected the diagnostic OPP. On resume it
restores the maximum safe OPP first, then the existing link-status updater
reselects the negotiated link OPP when the link is up. If the link is down,
the maximum OPP remains selected to avoid leaving the reduced test bandwidth
in place while the link recovers.

The expected source-series placement for the C patch is immediately after
0513; 0520 supplies the existing suspend OPP and does not touch this driver.
Do not apply these artifacts to Android. Before a Linux device test, build the
changed object and Nova DTB, deploy through a verified reversible kernel
layer, and confirm resume reselects the active link OPP.
