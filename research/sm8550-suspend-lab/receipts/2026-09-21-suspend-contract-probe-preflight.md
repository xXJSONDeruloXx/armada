# Suspend-contract probe preflight

**Captured:** 2026-09-21 08:29 UTC\
**Device:** stock Armada `20260915.feca679`, Linux `7.2.3`\
**Boot ID:** `3656b0e7-5671-4b7e-9368-67965daa251a`

This fresh read-only preflight checked symbols needed to close two specific
software-path gaps: whether ath12k enters its guarded late power-down path,
and whether Linux's SLEEP/WAKE RSC flush reports software programming success.
The full preflight is
`/tmp/nova-preflight-contract/preflight-20260921T082929Z-bbefe93cba99.json`
(SHA-256 `4b0772f13cdea109adfb76d9ab8bbde6e9bb0f3165522a5e3d0f8d58eb0f4f62`).

The running kernel has kprobes enabled. The following functions are present
in `available_filter_functions` and absent from the blacklist:

```text
ath12k_core_suspend [ath12k]
ath12k_core_suspend_late [ath12k]
ath12k_pci_power_down [ath12k]
mhi_power_down_keep_dev
rpmh_flush
```

There were no matching registered probes. The static
`ath12k_core_continue_suspend_resume()` and `ath12k_mhi_set_state()` helpers
are not probeable on this build, so instrumentation will not target them. A
run-scoped probe on `ath12k_pci_power_down(ab, true)` is a direct indication
that the late path passed its continuation guard and reached the HIF power-down
callback; `mhi_power_down_keep_dev()` shows the corresponding MHI action was
requested. Neither proves the physical endpoint/link state. A kretprobe on
`rpmh_flush()` reports only the Linux flush result; it cannot acknowledge that
firmware triggered or applied the sleep requests.

No device setting or behavior was changed. The next observation uses the
existing short direct-deep control with only these additional run-scoped
probes.
