# PCIe OPP candidate pre-boot harness preflight

Captured 2026-09-20 17:05 UTC by the updated suspend-lab runner, before
applying the staged image. The full 772,738-byte JSON is retained outside Git:

`/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/preflight-20260920T170503Z-c3a905c8d802.json`

SHA-256:
`19fa45c781d913b6dda1a4619f3e15cec249c8531bbd3e7082822e856daf8d8a`.

## Gates

- Runner source SHA-256 is
  `e6937306bf03bb868988a5ced0627abd0ee328349d2a6bb11e35675596bff0ad`,
  matching the local checkout at pushed commit `b790120`.
- Device is still on Linux kernel `7.2.3`, boot ID
  `55fdad18-019d-4c92-8ebd-8a558574c1d3`, with `[s2idle] deep` selected and
  Wi-Fi enabled.
- Bootc reports candidate digest
  `sha256:d7eb055720a28bddc8f6a3e7267d6e56c54c53de719963ed06c1228f851e101b`
  staged as `downloadOnly=true`, while booted and rollback deployments remain
  on the original pinned base. `rollbackQueued=false`.
- All nine `pcie-d3cold` required tracepoints are present:
  `rpmh:rpmh_send_msg`, `rpmh:rpmh_tx_done`, `qcom_aoss:aoss_send`,
  `qcom_aoss:aoss_send_done`, `interconnect:icc_set_bw`,
  `interconnect:icc_set_bw_end`, `power:device_pm_callback_start`,
  `power:device_pm_callback_end`, and `power:suspend_resume`.
- `psci_system_suspend_enter` and
  `__pci_host_common_d3cold_possible` are available and not blacklisted.

This confirms the device can collect the planned PCIe host, bandwidth, RPMh,
AOSS, and suspend events after the candidate boots. It does not itself prove
the candidate BTF hash until that kernel is running; the strict profile gate
will compare the live hash to the inspected stock/candidate allowlist before
registering the field-reading probe.
