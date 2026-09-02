# OpenGamepadUI v0.46.0 Armada plugin spike

This directory preserves the isolated feasibility probe used against OpenGamepadUI v0.46.0 on Retroid Pocket Nova. It is not part of Armada production packaging.

- Upstream source commit: `b149644f46b71e175a2ad223e84c18361596691e`
- Official ARM64 release: `v0.46.0`
- The test plugin is deliberately small: it mounts a direct OGUI-root panel with two buttons, a toggle, and close behavior so controller focus/navigation can be tested without Armada API side effects.
- `hardware_manager.patch` is the only OGUI source change tested. It preserves renderer identity, tolerates missing DMI files and non-PCI GPU identity, and rejects Nova's `0xffffffff` GLX device sentinel.

The spike intentionally does not copy OGUI source, binaries, native extensions, or assets into Armada. Rebuild the plugin archive from `plugin.gd`, `overlay.gd`, and `overlay.tscn` using OGUI's plugin archive layout. See the living PRD for device commands, hashes, startup output, and the adoption decision.
