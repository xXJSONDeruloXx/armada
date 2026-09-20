# Android WCN suspend and wake evidence boundary

Reviewed 2026-09-20 22:58 UTC from the saved rooted-Android capture. No new
Android suspend or device change was performed.

## What the trace establishes

The preserved excerpt is
[`android-icc-suspend-excerpt.txt`](2026-09-19-android-deep-rpmh/android-icc-suspend-excerpt.txt):

- Lines 1-4 show `pmo_core_enable_wow_in_fw` reporting WoW enabled for system
  suspend and `__wlan_hdd_bus_suspend` succeeding.
- Lines 19-24 show HIF wake IRQ 324 shortly before the kernel aborts suspend;
  the kernel reports `[timerfd]` as an active/pending wakeup-source label.
  Lines 32-41 show WLAN bus resume and a logged WLAN wake packet. This sequence
  does not isolate either event as the sole reason suspend did not complete.
- The next attempt starts at line 56. Lines 70-77 again show WLAN system-WoW
  setup and bus suspend success. Lines 79-86 show secondary CPUs being taken
  offline, and lines 99-101 identify `pm8xxx_rtc_alarm` as the wake source.

This confirms Android's WCN suspend callback prepares firmware WoW and that an
HIF wake interrupt was logged during an incomplete suspend attempt. It does
**not** establish that the HIF IRQ caused the abort or that Wi-Fi woke the
system from the completed low-power state. The earlier source audit found that
Linux `eventpoll` can name an `EPOLLWAKEUP` source after the watched file's
dentry; thus `[timerfd]` is not proof that a timer expired or identification
of the event that prevented suspend. The later completed deep entry woke by
RTC, not Wi-Fi.

## What remains unproven

The excerpt has no matching per-device suspend or wake evidence for UFS, USB,
DSI, or DisplayPort. It also does not prove that PCIe or the shared LDOE rails
were physically off when firmware WoW was armed, nor that a Wi-Fi interrupt can
resume the device after the successful deep path. The AOP/RPMh request trace is
still request evidence, not proof that every sleep request was applied.

Do not infer that LDOE1/LDOE3 may safely be disabled from the WoW log. Keep the
shared-rail wake-safety item open. A useful future test must bracket the
Android suspend service's wakeup history and kernel wake IRQs around a
confirmed completed deep interval, with an intentional Wi-Fi or USB event and
an RTC fallback. Do not use the `[timerfd]` name alone to decide whether a
competing timer expired; the existing successful RTC wake does not validate
Wi-Fi or USB wake from deep.
