# OpenGamepadUI v0.46.0 Armada plugin

This directory preserves the isolated OGUI plugin used against OpenGamepadUI v0.46.0 on Retroid Pocket Nova. It is not part of Armada production packaging.

- Upstream source commit: `b149644f46b71e175a2ad223e84c18361596691e`
- Official ARM64 release: `v0.46.0`
- The plugin registers an Armada card in OGUI's native Guide+B Quick Bar. The card keeps the Armada controls in the existing right-side panel and uses OGUI's card buttons, dropdown, slider, toggle, focus, theme, and icon components while calling Armada's group-scoped overlay API through `armada-overlay-call`.
- The plugin attaches its card to the Quick Bar's native scroll viewport after the Quick Bar is ready. OGUI v0.46's convenience `add_to_quick_bar()` path crashed on this Godot 4.7 ARM64 build during dynamic card insertion; using the documented Quick Bar scene/container with the same native controls avoids that path while preserving the side-panel behavior.
- Armada controls are grouped as OGUI `qb_card.tscn` expandable cards for Power, Fans, Games, Compatibility, System, and Actions. Each card is composed before tree insertion, matching OGUI's own Gamepad and Plugin Settings menus.
- The Power and Fans cards include profile reset, underclock presets, fan curve and point editing, factory-curve reset, minimum-PWM correction, fan-stop, responsiveness, protected curve management, and draft revert. The Games card includes Default/current-game targeting, inherited per-game FEX/thunk/performance settings, CPU lists, scheduler, priorities, and environment variables through native OGUI controls.
- The Compatibility card keeps Steam-private operations behind `armada-steam-call`: global and per-game Proton tools, apply-to-new-games policy, global and per-game resolution, launch options, manual AppID loading, single-game reset, all-game reset, and the existing sweep path.
- The direct Quick Bar mount is idempotent and removes its card during plugin teardown, covering OGUI plugin reload without leaving stale controls in the native viewport.
- Armada cards are reparented directly into OGUI's Quick Bar viewport after the plugin wrapper is ready. This keeps them in OGUI's native focus chain, so Down stays within the Quick Bar and B can close an expanded card without returning focus to Steam behind the panel.
- The `text-input-default.patch` OGUI patch clears the generic `TextInput` description placeholder. Plugin dropdowns also clear the scene's default item before inserting their real options, and empty dynamic lists are not selected.
- The same OGUI component patch routes `LineEdit.text_submitted` to the component signal. This keeps controller and OSK submission working for Armada's curve, CPU-list, environment, AppID, and launch-option fields.
- `hardware_manager.patch` keeps renderer identity when Nova has no PCI/APU GPU identity, tolerates missing sysfs files, and rejects Nova's `0xffffffff` GLX device sentinel. `plugin_manager.patch` defers plugin loading until the manager enters the scene tree; without it, overlay-mode plugin instances were constructed but never became usable nodes.
- Both patches apply cleanly to upstream commit `b149644f46b71e175a2ad223e84c18361596691e` (v0.46.0). The source-built ARM64 runtime was smoke-tested on Nova: it remains alive, loads the plugin, owns `STEAM_INPUT_FOCUS`/`STEAM_OVERLAY`, and uses OGUI's own Gamescope/InputPlumber resources.

The plugin intentionally does not copy OGUI source, binaries, native extensions, or assets into Armada. Rebuild the plugin archive from the files in this directory using OGUI's plugin archive layout. The earlier centered-provider probe remains in git history; the current implementation is Quick Bar-only. See the living PRD for device commands, hashes, startup output, and the adoption decision.

Build an archive with `./build-plugin.sh /path/to/armada-control.zip`, then place it in OGUI's user plugin directory.

When rebuilding the pinned OGUI source after changing scenes or core components, force the export target with `make -B GODOT=/usr/bin/godot build` so `.godot/exported` resources are regenerated. Verify the resulting PCK before staging it.
