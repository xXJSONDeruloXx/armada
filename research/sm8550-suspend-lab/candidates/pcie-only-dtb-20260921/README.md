# PCIe-only disabled-DTB positive control

Temporary diagnostic candidate for the Nova. It uses the already tested
phase-03 kernel/image as its base and changes only the DT status of
`/soc@0/pcie@1c00000` to `disabled`. The `89c000.serial` QUP2 client remains
unchanged. The candidate boots without Wi-Fi, runs one 15-second direct-deep
RTC cycle locally, stores the full harness run under `/var/home/armada`, then
requests bootc rollback. A six-minute root timer is the fallback, and the
inherited initrd guard covers a stalled initrd.

The DTB must be verified both at image build and candidate boot. Treat any
missing result or failed verification as a failed candidate boot, not a sleep
result. Keep this image diagnostic-only. It does not test PCIe/WCN resume
because the host is absent for the entire candidate boot.
