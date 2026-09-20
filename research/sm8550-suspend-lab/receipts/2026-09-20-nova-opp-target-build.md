# Nova PCIe bandwidth A/B targeted build

Built 2026-09-20 in an isolated source tree on `/Volumes/NovaKernelBuild`.
No source under the armada-packages checkout was edited, and no artifact was
installed on either Android or Armada Linux.

## Inputs and scope

- Linux stable source: `7.2.3`.
- Armada package patch series: 145 patches applied with zero failures.
- Diagnostic C proposal: `proposals/pcie-qcom-diagnostic-opp.patch`, after
  patch 0513.
- Nova-only DTS proposal: `proposals/rpnova-diagnostic-opp.diff`.
- The candidate reduces only the PCIe memory-path peak from 500,000 to
  1,000 kB/s for host-active direct `PM_SUSPEND_MEM`, keeping
  `required-opps = low_svs` and the CPU-path peak at 1 kB/s.
- The C proposal tracks successful selection of the test OPP. Resume first
  restores the maximum OPP, then the existing live-link updater reapplies the
  negotiated OPP if the link is up. If the link is down, the maximum OPP
  remains instead of the reduced test OPP.

## Build and validation

The pinned Fedora 44 AArch64 builder ran only:

```text
make ARCH=arm64 -j8 drivers/pci/controller/dwc/pcie-qcom.o \
  qcom/qcs8550-retroidpocket-rpnova.dtb
```

The revised C diff passed reverse/apply checks against the patched Linux tree.
The object compiled as AArch64 ELF with debug information. DTC decompilation
confirmed the Nova host has `armada,diag-pcie-mem-suspend-opp` and its OPP
table has `opp-hz = <0x00 0x02>`, `required-opps = <low_svs>`, and
`opp-peak-kBps = <0x3e8 0x01>`. The common SM8550 DTS was not edited. DTC also
reported existing duplicate unit-address warnings for QUP nodes, unrelated to
this change.

Artifacts:

| Target | Size | SHA-256 |
|---|---:|---|
| `drivers/pci/controller/dwc/pcie-qcom.o` | 586 KiB | `bca7e626ae96c0ed7003b42eadc969f358db54ce433436743b6077ea243239d0` |
| `qcom/qcs8550-retroidpocket-rpnova.dtb` | 143,771 bytes | `72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422` |

The full kernel image, modules, package tarball, and bootc layer have not been
built. The candidate has not been deployed or tested in a suspend cycle. The
live device remains on its original rooted Android boot with Wireless ADB and
Wi-Fi up.

## Proposal diff review

At 10:00 UTC the C proposal was regenerated with minimal diff alignment so it
shows only the diagnostic state field, setter, suspend opt-in, and resume
restore. The earlier hunk display made the unchanged patch-0513 OPP helper's
similar body look duplicated; that code is already in the pre-candidate
source. Applying the cleaned diff to a reconstructed pre-candidate copy
reproduces the current scratch `pcie-qcom.c` byte-for-byte. There is no source
or behavior change from the object build above, so its SHA-256 remains valid.
No package source file or device was changed.
