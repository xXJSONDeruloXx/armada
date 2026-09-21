# Phase-02 candidate stopped in initrd: BTF-invalid stock modules

Captured 2026-09-21 01:34 UTC on `feat/sm8550-suspend-lab`, after applying
the phase-02 candidate with ABL recovery available. This was a bootability
diagnostic only. No PCIe OPP suspend A/B ran.

## Evidence

- ESP recovery marker:
  `event=stock_kernel_restored boot_id=529c658e-7b48-47ca-b626-a579fd239cf2`.
- The candidate-root phase marker is absent.
- The bounded initrd journal is preserved in
  [`2026-09-21-pcie-opp-phase-02-initrd-journal.txt`](2026-09-21-pcie-opp-phase-02-initrd-journal.txt):
  500 lines, 45,091 bytes, SHA-256
  `4da561bfacec200ffa7cc1321d0113b502ccbd011d736075896b87558b8646db`.
- The command line requires a Btrfs root (`root=UUID=c8f19552-6d5f-4d2e-be10-17b11c3d9d15`,
  `rootflags=subvol=root,...`, and `rd.driver.pre=btrfs`).
- At 1.060 s, the kernel reports `failed to validate module [dm_mod] BTF: -22`;
  `modprobe` then reports `could not insert 'dm_mod': Invalid argument`.
  At 1.376 s, `btrfs` insertion fails with the same `Invalid argument`, after
  kernel BTF-validation errors. Similar BTF validation failures appear for
  other stock modules in the initrd.
- Initrd systemd reaches `sysinit.target`, completes `dracut-initqueue`, and
  finishes `dracut-pre-mount`; there is no `initrd-switch-root.target` or
  candidate-root marker. The existing recovery service starts at about 121 s
  and the ESP marker confirms it restored the known-good kernel.

## Diagnosis

The phase-02 image recipe copied the diagnostic `vmlinuz` and Nova DTB into
the cached Armada base but did not copy a matching `/usr/lib/modules/7.2.3`
tree. The base therefore retained stock modules while booting the candidate
kernel. This candidate's `.BTF` hash is
`cd7334c576a197a39b0e5121d2b3fb9c38fef8af6b034beb039d1b04b4bbbb44`; the
stock running kernel's `.BTF` hash is
`fb193ea5c32178ae22d52e30a62986e4bbc2c3db01bfa530f34b257fe94b45a1` (see
[`candidate BTF receipt`](2026-09-20-candidate-pcie-btf.md)). The kernel's
module BTF-validation errors plus the recipe's mixed kernel/module payload
strongly explain why the essential stock Btrfs module could not load and the
candidate never reached its root filesystem. This is a boot image packaging
failure, not evidence about suspend behavior.

The existing build output at `/Volumes/NovaKernelBuild/work/linux-7.2.3`
contains the matching candidate `vmlinux`, `Image`, config, and diagnostic
PCIe source, but has no `fs/btrfs/btrfs.ko`, `drivers/md/dm-mod.ko`, or
`Module.symvers`. The config has `CONFIG_BTRFS_FS=m`, `CONFIG_BLK_DEV_DM=m`,
`CONFIG_DEBUG_INFO_BTF=y`, and `CONFIG_DEBUG_INFO_BTF_MODULES=y`. A matching
module-only build and packaging path must be established before another
candidate boot.

## Recovery state and next step

The Nova is back on stock Armada `20260915.feca679`, kernel `7.2.3`, boot ID
`f884a7fb-79d5-4247-9d1e-c634ed2b0141`. Wi-Fi is connected, systemd is
running with zero failed units, bootc reports `staged: null` and
`rollback: null`, and OSTree has only the stock default deployment. The
original PCIe OPP and kernel remain untouched in the running deployment.

Next, identify the exact build container/toolchain and source snapshot for
the candidate, then attempt a modules-only build from that existing configured
tree. Package the matching module tree and regenerate the candidate initramfs;
verify it contains matching Btrfs and device modules before applying. Do not
extend the recovery timer or run the suspend A/B until the candidate root
marker is positively observed.
