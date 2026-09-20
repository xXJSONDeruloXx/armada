# Matching-config Nova PCIe OPP build

Checked 2026-09-20 on the external AArch64 build volume at
`/Volumes/NovaKernelBuild/work/linux-7.2.3`.

The command `make -j8 ARCH=arm64 Image dtbs` completed with exit status 0.
The scratch `.config` SHA-256 is
`2219546e268f72bb2bcbac96943202e9e50731b6e531e3193cc73b1976d2fbef`, equal to
the captured Nova config. `scripts/extract-ikconfig` from the generated Image
returns the same hash.

| Artifact | SHA-256 |
|---|---|
| `arch/arm64/boot/Image` | `15b46efc40d15200523b5c7ec623f54d4ac03bddfe798f1d8842ebf1fa2824d9` |
| `arch/arm64/boot/dts/qcom/qcs8550-retroidpocket-rpnova.dtb` | `72da8e0e5151d346fe48d5b46738fe74cac74981ffd9709a81d7df79df44d422` |
| `vmlinux` | `3267ff07685321e4fd3cb9c8966418c605a0de30f37d12b7b02e58e5c3b1a82e` |
| `drivers/pci/controller/dwc/pcie-qcom.o` | `43ea771dc73da10b7d78f149e9be7c1907be02c2ae94d07e7b4dab51d45916f1` |

The compiled PCIe object contains the diagnostic OPP error string. Decompiling
the Nova DTB confirms `armada,diag-pcie-mem-suspend-opp` and
`opp-test-sleep-bw`: synthetic `opp-hz = 2`, `opp-peak-kBps = <1000 1>`, and
`required-opps` points to phandle `0x26`, which is `opp-64` / level `0x40`
(`low_svs`). The DTS mtime predates its DTB mtime, so this DTB was already
built from the unchanged candidate DTS; its hash and contents were checked
after the Image rebuild.

The candidate has not been packaged as an OCI image, staged with bootc, or
booted on the Nova. It remains a diagnostic-only kernel/Image/DTB artifact.
