extends Plugin

const QUICK_BAR_META := "armada_control_quick_bar"

var quick_bar_item: Control
var mounted_status: Label
var mounted_cards: Array[Control] = []
var overlay_window_id := 0


func _ready() -> void:
    # Overlay summoning (Guide+B) is owned entirely by OGUI core and
    # InputPlumber's stock intercept triggers. This plugin never programs
    # activation chords: the intercept slot is single-writer and overriding
    # it breaks the native summon. See overlay-summon.md.
    if "--overlay-mode" in OS.get_cmdline_args():
        call_deferred("_register_quick_bar")
        call_deferred("_claim_overlay_window")
        return
    call_deferred("_register_quick_bar")


func _claim_overlay_window() -> void:
    var gamescope := load("res://core/systems/gamescope/gamescope.tres")
    if not gamescope:
        logger.warn("OGUI Gamescope integration is unavailable")
        return
    var xwayland = gamescope.get_xwayland(gamescope.XWAYLAND_TYPE_OGUI)
    if not xwayland:
        logger.warn("OGUI XWayland integration is unavailable")
        return
    var windows: PackedInt64Array = xwayland.get_windows_for_pid(OS.get_process_id())
    if windows.is_empty():
        logger.warn("OGUI window was not found")
        return
    var window_id := windows[0]
    overlay_window_id = window_id
    if xwayland.set_input_focus(window_id, 1) != OK:
        logger.warn("Unable to set OGUI input focus")
    if xwayland.set_overlay(window_id, 1) != OK:
        logger.warn("Unable to set OGUI overlay state")
    var input_plumber := load("res://core/systems/input/input_plumber.tres")
    if input_plumber:
        input_plumber.manage_all_devices = true
        input_plumber.set_intercept_mode(2)


func _release_overlay_window() -> void:
    if overlay_window_id <= 0:
        return
    var gamescope := load("res://core/systems/gamescope/gamescope.tres")
    if gamescope:
        var xwayland = gamescope.get_xwayland(gamescope.XWAYLAND_TYPE_OGUI)
        if xwayland:
            xwayland.set_input_focus(overlay_window_id, 0)
            xwayland.set_overlay(overlay_window_id, 0)
    var input_plumber := load("res://core/systems/input/input_plumber.tres")
    if input_plumber:
        input_plumber.set_intercept_mode(InputPlumberInstance.INTERCEPT_MODE_NONE)
    overlay_window_id = 0


func _register_quick_bar() -> void:
    await get_tree().create_timer(1.0).timeout
    var quick_bar := get_tree().get_first_node_in_group("quick-bar")
    if not quick_bar:
        logger = Log.get_logger("ArmadaControl", Log.LEVEL.DEBUG)
        logger.warn("OGUI Quick Bar is unavailable; Armada side card is disabled")
        return

    if not quick_bar.is_node_ready():
        quick_bar.ready.connect(_add_quick_bar_item.bind(quick_bar), CONNECT_ONE_SHOT)
        return
    _add_quick_bar_item(quick_bar)


func _add_quick_bar_item(quick_bar: Control) -> void:
    var quick_bar_script = load("res://plugins/armada-control/quick_bar.gd")
    if not quick_bar_script:
        logger = Log.get_logger("ArmadaControl", Log.LEVEL.DEBUG)
        logger.error("Armada Quick Bar script could not be loaded")
        return
    var item := quick_bar_script.new() as Control
    if not item:
        logger = Log.get_logger("ArmadaControl", Log.LEVEL.DEBUG)
        logger.error("Armada Quick Bar script is not a Control")
        return
    var viewport := quick_bar.get_node_or_null(
        "MarginContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/Viewport"
    ) as VBoxContainer
    if not viewport:
        logger = Log.get_logger("ArmadaControl", Log.LEVEL.DEBUG)
        logger.error("OGUI Quick Bar content viewport could not be found")
        return
    for child in viewport.get_children():
        if child is Control and child.get_meta(QUICK_BAR_META, false):
            quick_bar_item = child
            return
    item.ready.connect(_mount_quick_bar_cards.bind(viewport, item))
    item.set_meta(QUICK_BAR_META, true)
    quick_bar_item = item
    viewport.add_child(item)


func _mount_quick_bar_cards(viewport: VBoxContainer, item: Control) -> void:
    var content := item.get_node_or_null("ArmadaContent") as VBoxContainer
    if not content:
        logger = Log.get_logger("ArmadaControl", Log.LEVEL.DEBUG)
        logger.error("Armada Quick Bar content container could not be found")
        return
    for child in content.get_children():
        if child is Label and child.name == "ArmadaStatus":
            content.remove_child(child)
            viewport.add_child(child)
            mounted_status = child
            continue
        if not child is QuickBarCard:
            continue
        content.remove_child(child)
        child.set_meta(QUICK_BAR_META, true)
        viewport.add_child(child)
        mounted_cards.append(child)
    item.visible = false
    item.focus_mode = Control.FOCUS_NONE
    logger.info("Mounted %d Armada cards into native Quick Bar" % mounted_cards.size())
    var viewport_focus_group := viewport.get_node_or_null("FocusGroup") as FocusGroup
    if viewport_focus_group:
        viewport_focus_group.call_deferred("recalculate_focus")


func _exit_tree() -> void:
    _release_overlay_window()
    if is_instance_valid(quick_bar_item) and quick_bar_item.has_method("_stop_calibration_session"):
        quick_bar_item.call("_stop_calibration_session")
    if "--overlay-mode" in OS.get_cmdline_args():
        var input_plumber := load("res://core/systems/input/input_plumber.tres")
        if input_plumber:
            input_plumber.set_intercept_mode(InputPlumberInstance.INTERCEPT_MODE_NONE)
    for card in mounted_cards:
        if is_instance_valid(card):
            card.queue_free()
    mounted_cards.clear()
    if is_instance_valid(mounted_status):
        mounted_status.queue_free()
    mounted_status = null
    if is_instance_valid(quick_bar_item):
        quick_bar_item.queue_free()
