# OpenGamepadUI v0.46.0 Armada plugin spike

This directory preserves the isolated OGUI feasibility probe used against OpenGamepadUI v0.46.0 on Retroid Pocket Nova. It is not part of Armada production packaging.

- Upstream source commit: `b149644f46b71e175a2ad223e84c18361596691e`
- Official ARM64 release: `v0.46.0`
- The test plugin is deliberately small: it mounts an `OverlayProvider` through OGUI's native `OverlayContainer`, with two buttons, a toggle, and close behavior so controller focus/navigation can be tested without Armada API side effects.
- `hardware_manager.patch` keeps renderer identity when Nova has no PCI/APU GPU identity, tolerates missing sysfs files, and rejects Nova's `0xffffffff` GLX device sentinel. `plugin_manager.patch` defers plugin loading until the manager enters the scene tree; without it, overlay-mode plugin instances were constructed but never became usable nodes.
- Both patches apply cleanly to upstream commit `b149644f46b71e175a2ad223e84c18361596691e` (v0.46.0). The source-built ARM64 runtime was smoke-tested on Nova: it remains alive, loads the plugin, owns `STEAM_INPUT_FOCUS`/`STEAM_OVERLAY`, and uses OGUI's own Gamescope/InputPlumber resources.

The spike intentionally does not copy OGUI source, binaries, native extensions, or assets into Armada. Rebuild the plugin archive from `plugin.gd`, `overlay.gd`, and `overlay.tscn` using OGUI's plugin archive layout. See the living PRD for device commands, hashes, startup output, and the adoption decision.
