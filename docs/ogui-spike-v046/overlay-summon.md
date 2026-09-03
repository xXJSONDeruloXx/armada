# OGUI overlay summon: Guide+B and why we must not touch it

Verified end-to-end on Nova hardware 2026-09-03 (InputPlumber 0.78.1,
OGUI pinned commit `b149644f`). Read this before touching anything related
to activation chords, intercept triggers, or summon behavior.

## The working chain

1. Physical **Guide+B** press on the controller.
2. InputPlumber matches its **stock** intercept activation triggers
   (`Gamepad:Button:Guide` + `Gamepad:Button:East` → target
   `Gamepad:Button:QuickAccess2`), programmed by OGUI core itself at startup
   and on every composite-device add
   (`core/ui/card_ui_overlay_mode/card_ui_overlay_mode.gd`).
3. The translated event reaches OGUI as `ui_quick2`, mapped to `ogui_qb_ov`,
   handled by `overlay_mode_input_manager._quick_bar_input`, which pushes
   `quick_bar_state` onto the popup state machine.
4. OGUI's native Quick Bar menu opens over the game with its default cards
   **plus** our mounted Armada cards (Power, Fans, Games, Compatibility,
   System, Actions).
5. Back/East dismisses back to the game. The process stays resident and the
   chord re-summons indefinitely.

## The hard constraint: single-writer intercept slot

`SetInterceptActivation` holds **one** trigger set per composite device;
last writer wins. OGUI core rewrites its stock triggers on startup and on
every device add. Anything else that programs triggers races it
nondeterministically.

History: our plugin used to program its own chords (default Start+Select)
on startup, a 2s timer, and every device add. While ours was active,
**neither** Start+Select **nor** Guide+B summoned anything: ours replaced
stock, and ours never produced a working summon on this stack. Fix (commit
"stop overriding overlay summon chord"): the plugin no longer programs
intercept activation at all. OGUI core owns the chord. Do not re-add trigger
programming without solving the single-writer race first.

## OGUI core owns Gamescope/input state, not us

Upstream `card_ui_overlay_mode` switches the full hardware contract on
menu/base state transitions (`_on_base_state_entered/_on_base_state_exited`):
closed = InputPlumber PASS + OGUI focus 0 + underlay focus 1 + OGUI
overlay 0; open menu = InputPlumber ALL + OGUI focus 1 + underlay focus 0 +
OGUI overlay 1. Our plugin used to grab all of that unconditionally at
startup (`_claim_overlay_window`), which put hardware in "menu open" state
while the state machine sat in base: Steam lost input, no menu was visible,
and no chord could summon. The plugin must never write Gamescope
focus/overlay atoms, `manage_all_devices`, or the intercept mode. The repo
test enforces this. Symptom signature of this bug class: cards log mounted
but nothing is visible and Steam loses controller focus.

The launcher exit trap (`inputplumber-intercept reset`) is the deliberate
exception: it only restores PASS at process exit so a crash cannot brick
gamepad input, and never grabs anything at startup.

## Currently inert prefs (reserved, do nothing today)

`~/.config/armada/overlay.json` keys `layout`, `centeredChord`, `sideChord`,
`swipeEnabled`, `swipeEdge`, `swipeDistance`: nothing reads them since the
gestures daemon and the private overlay provider were removed. The System
card still edits layout/swipe rows; the chord dropdowns were removed. If
chord choice ever returns, it needs a design that does not fight OGUI core
for the single slot.

## Debugging summon issues

- Watch InputPlumber find the chord:
  `journalctl -u inputplumber.service` shows `Found activation chord!`
  plus the intercept mode switch when a physical chord translates.
- Watch raw D-Bus traffic (needs root, system bus eavesdropping is
  admin-only):
  `busctl --system monitor --match "type=signal"`.
- OGUI side: our plugin logs mount state (`Mounted N Armada cards into
  native Quick Bar`); core logs state pushes (`GlobalStateMachine`,
  `MenuStateMachine`, `PopupStateMachine`).
- Synthetic chords injected via `SendButtonChord` **bypass** InputPlumber
  trigger translation and arrive raw at the focused app. They are useless
  for testing summon; only physical presses count.
- Steam's own screenshots capture the game layer, **not** overlay windows.
  To see overlays headlessly, capture the Steam Link client window
  (`screencapture -R` with the window bounds from System Events).
