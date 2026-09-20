# PCIe trace-probe BTF gate for the diagnostic kernel

Captured 2026-09-20 16:59 UTC while validating the staged PCIe OPP candidate.
This is a host-side analysis of the exact matching-config candidate
`vmlinux`; no device kernel was booted for this inspection.

## Why the existing probe gate needed a second hash

The harness's `pcie-d3cold` profile dereferences `struct pci_dev` fields in a
temporary kretprobe and correctly refuses to run unless the running kernel
release and `/sys/kernel/btf/vmlinux` hash match an inspected build. The
diagnostic PCIe change adds `diag_opp_active` to the driver-private
`struct qcom_pcie`, so the candidate's global BTF blob differs from stock even
though the `pci_dev` fields used by the probe are unchanged.

## Candidate BTF and layout verification

- Candidate `vmlinux` SHA-256:
  `3267ff07685321e4fd3cb9c8966418c605a0de30f37d12b7b02e58e5c3b1a82e`.
- Candidate ELF `.BTF` section: offset `0x2912000`, size `0x860010`.
- SHA-256 of the exact raw `.BTF` section:
  `cd7334c576a197a39b0e5121d2b3fb9c38fef8af6b034beb039d1b04b4bbbb44`.
- Stock running kernel `/sys/kernel/btf/vmlinux` hash:
  `fb193ea5c32178ae22d52e30a62986e4bbc2c3db01bfa530f34b257fe94b45a1`.
- `bpftool btf dump` of the candidate confirms these offsets, with bit offsets
  converted to bytes:

| Type/member | Candidate byte offset | Probe expects |
|---|---:|---:|
| `pci_dev.bus` | `0x10` | `0x10` |
| `pci_dev.devfn` | `0x38` | `0x38` |
| `pci_dev.vendor` | `0x3c` | `0x3c` |
| `pci_dev.device` | `0x3e` | `0x3e` |
| `pci_dev.class` | `0x44` | `0x44` |
| `pci_dev.current_state` | `0xa8` | `0xa8` |
| `pci_bus.number` | `0xd8` | `0xd8` |
| `pci_bus.domain_nr` | `0xdc` | `0xdc` |

The harness now accepts only the stock BTF hash and this exact candidate hash,
and records the actual hash used in each probe receipt. It continues to reject
any other kernel/BTF. `host self-test`, Python bytecode compilation, and
`git diff --check` passed after the change.
