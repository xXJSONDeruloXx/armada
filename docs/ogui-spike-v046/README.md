# OpenGamepadUI v0.46.0 Armada plugin

This directory preserves the isolated OGUI plugin used against OpenGamepadUI v0.46.0 on Retroid Pocket Nova. It is not part of Armada production packaging.

- Upstream source commit: `b149644f46b71e175a2ad223e84c18361596691e`
- Official ARM64 release: `v0.46.0`
- The plugin registers an Armada card in OGUI's native Guide+B Quick Bar. The card keeps the Armada controls in the existing right-side panel and uses OGUI's card buttons, dropdown, slider, toggle, focus, theme, and icon components while calling Armada's group-scoped overlay API through `armada-overlay-call`.
- The plugin attaches its card to the Quick Bar's native scroll viewport after the Quick Bar is ready. OGUI v0.46's convenience `add_to_quick_bar()` path crashed on this Godot 4.7 ARM64 build during dynamic card insertion; using the documented Quick Bar scene/container with the same native controls avoids that path while preserving the side-panel behavior.
- `hardware_manager.patch` keeps renderer identity when Nova has no PCI/APU GPU identity, tolerates missing sysfs files, and rejects Nova's `0xffffffff` GLX device sentinel. `plugin_manager.patch` defers plugin loading until the manager enters the scene tree; without it, overlay-mode plugin instances were constructed but never became usable nodes.
- Both patches apply cleanly to upstream commit `b149644f46b71e175a2ad223e84c18361596691e` (v0.46.0). The source-built ARM64 runtime was smoke-tested on Nova: it remains alive, loads the plugin, owns `STEAM_INPUT_FOCUS`/`STEAM_OVERLAY`, and uses OGUI's own Gamescope/InputPlumber resources.

The plugin intentionally does not copy OGUI source, binaries, native extensions, or assets into Armada. Rebuild the plugin archive from the files in this directory using OGUI's plugin archive layout. The earlier centered-provider probe remains in git history; the current implementation is Quick Bar-only. See the living PRD for device commands, hashes, startup output, and the adoption decision.
