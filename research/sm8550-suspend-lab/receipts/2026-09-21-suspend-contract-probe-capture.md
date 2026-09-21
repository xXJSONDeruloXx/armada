# Stock suspend-contract probe capture

**Captured:** 2026-09-21 08:32 UTC\
**Device:** stock Armada `20260915.feca679`, Linux `7.2.3`\
**Boot ID:** `3656b0e7-5671-4b7e-9368-67965daa251a` before and after\
**Run:** `20260921T083212Z-add6da4cda42`\
**Mode:** direct `deep`, RTC wake after 15 seconds\
**Changed behavior:** none; run-scoped read-only trace events and kprobes

The archive is
`/Users/danhimebauch/Developer/.external-research/sm8550-suspend-lab-runs/20260921T083212Z-add6da4cda42/device/`.

## Direct observations

The suspend interval was 12.208 seconds, the harness returned successfully on
the same boot, and `wlp1s0` returned `UP` with `LOWER_UP`. The dynamic probe
hit counts were one for each new ath12k/MHI/RPMh event; misses were zero.

The trace records this sequence in the ath12k late system-suspend callback:

```text
ath12k_core_suspend_late entry: ab=0xffff00080d9e0000
ath12k_pci_power_down:          same ab, is_suspend=1
mhi_power_down_keep_dev:        controller=0xffff000808af7800, graceful=1
ath12k_core_suspend_late return: retval=0
```

This proves the ath12k continuation guard passed and the driver requested its
HIF/MHI suspend power-down path. The source routes `ath12k_pci_power_down(...,
true)` through `ath12k_mhi_stop(..., true)` and `mhi_power_down_keep_dev()`.
It does **not** prove that the WCN silicon or PCIe link physically powered
off. In particular, `pci_set_power_state()` still had zero hits for the
Qualcomm root port and endpoint.

The subsequent `__pci_host_common_d3cold_possible()` walk observed only the
root port `17cb:0113` in software `PCI_UNKNOWN` (state 5) and returned
`-EOPNOTSUPP` (`-95`). The normal DesignWare host link-teardown path therefore
remains unproven. This is a distinct blocker from whether ath12k called its
own late power-down routine.

The new `rpmh_flush()` kretprobe recorded one return with `retval=0` from
`rpmh_rsc_pd_callback()`. The same trace recorded all six Apps-RSC SLEEP
commands on TCS 3 and six WAKE commands on TCS 5:

| State | Address | Data |
|---|---:|---:|
| SLEEP | `0x50000` | `0x600001dc` |
| SLEEP | `0x50004` | `0x600001dc` |
| SLEEP | `0x50010` | `0x40000000` |
| SLEEP | `0x50038` | `0x40000000` |
| SLEEP | `0x50048` | `0x00000000` |
| SLEEP | `0x50044` | `0x40000000` |
| WAKE | `0x50000` | `0x60000823` |
| WAKE | `0x50004` | `0x600011db` |
| WAKE | `0x50010` | `0x60004001` |
| WAKE | `0x50038` | `0x60004001` |
| WAKE | `0x50048` | `0x20004001` |
| WAKE | `0x50044` | `0x60004001` |

The successful `rpmh_flush()` return plus the trace confirms Linux's RSC
software flush completed without error and staged/enabled the SLEEP/WAKE
slots. It is not an AOP/RPMh firmware acknowledgment; Linux does not expose a
separate completion for these firmware-triggered sleep sets. The AOSD, CXSD,
and scalar DDR count/duration deltas remained zero. ADSP advanced by 277
counts / 403,659,061 raw duration units. Detailed DDR ID `0xd0` duration
advanced by 406,940,773 raw ticks with no count change; its state meaning and
units remain unknown.

## Interpretation

One earlier uncertainty is closed: Linux did not skip ath12k's late HIF power
down. It actually invoked the driver's suspend-specific PCI/MHI power-down
path, but Linux still did not request a PCI D-state transition or pass the
root-port D3cold eligibility check. Thus the relevant Linux-vs-Android gap is
now narrower: Android's connected-DRV suspend additionally drives the
Qualcomm PCIe host/ICC path to its suspend state; Linux's ath12k suspend
callback does not establish that same host-controller state.

Another uncertainty is closed at the software layer: `rpmh_flush()` returned
success. The missing observation is firmware acceptance/application after
handoff, for which the zero named residency counters remain the nearest
trustworthy signal.

No ICC request, PCI state, regulator state, image, or boot policy changed.
The trace instance and every owned probe were removed. The full archive
records the per-probe zero-miss cleanup result.

## Source references

- [ath12k late suspend and HIF power-down](https://github.com/gregkh/linux/blob/v7.2.3/drivers/net/wireless/ath/ath12k/core.c#L102-L179)
- [ath12k PCI power-down and suspend PM ops](https://github.com/gregkh/linux/blob/v7.2.3/drivers/net/wireless/ath/ath12k/pci.c#L1459-L1490)
- [ath12k MHI stop and `POWER_OFF_KEEP_DEV`](https://github.com/gregkh/linux/blob/v7.2.3/drivers/net/wireless/ath/ath12k/mhi.c#L382-L489)
- [RPMh `rpmh_flush()` return contract](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh.c#L421-L485)
- [RPMh sleep/wake slot programming without AP trigger](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L367-L406) and [TCS command write path](https://github.com/gregkh/linux/blob/v7.2.3/drivers/soc/qcom/rpmh-rsc.c#L727-L755)

## Artifact hashes

| Artifact | SHA-256 |
|---|---|
| `raw/trace/trace.txt` | `d2a9071534b616fe492109bcb711b471f4f9c2acd23ab08ee6d0c425343f865a` |
| `raw/trace/kprobe_profile.txt` | `4f676b3e3d87cce96b887ea27d046fc95348d21fb16a3b7e3d6c351f0e1685f2` |
| `derived/summary.json` | `87ab945f0a7b400684c7393ed60159b4f517ddc9a7aac240f70795e521c5c9ec` |
| `meta/trace.json` | `81d6c13e6c2d808a21d9eba439d41ecc6ca9f89ad5d14752fe688f104adf17eb` |
| `cleanup/trace.json` | `c6882ec3018857c3762a78c805799b370b8d94dc7a57b347c88395eeb4bef068` |
