extends Plugin

const QUICK_BAR_META := "armada_control_quick_bar"
const OVERLAY_SCENE := preload("res://plugins/armada-control/overlay.tscn")

var quick_bar_item: Control
var mounted_status: Label
var mounted_cards: Array[Control] = []
var overlay_item: OverlayProvider
var overlay_container: OverlayContainer
var overlay_window_id := 0
var activation_input_plumber


func _ready() -> void:
    if "--overlay-mode" in OS.get_cmdline_args():
        call_deferred("_configure_overlay_activation")
        call_deferred("_register_overlay")
        return
    call_deferred("_register_quick_bar")


func _configure_overlay_activation() -> void:
    logger = Log.get_logger("ArmadaControl", Log.LEVEL.DEBUG)
    activation_input_plumber = load("res://core/systems/input/input_plumber.tres")
    if not activation_input_plumber:
        return
    if not activation_input_plumber.composite_device_added.is_connected(_apply_activation_to_device):
        activation_input_plumber.composite_device_added.connect(_apply_activation_to_device)
    if not activation_input_plumber.started.is_connected(_apply_overlay_activation):
        activation_input_plumber.started.connect(_apply_overlay_activation)
    _apply_overlay_activation()
    get_tree().create_timer(2.0).timeout.connect(_apply_overlay_activation, CONNECT_ONE_SHOT)


func _apply_overlay_activation() -> void:
    var triggers := _overlay_activation_events()
    if triggers.is_empty() or not activation_input_plumber:
        return
    activation_input_plumber.set_intercept_activation(triggers, "Gamepad:Button:QuickAccess2")
    logger.info("Configured OGUI activation triggers: " + str(triggers))
    for device in activation_input_plumber.get_composite_devices():
        _apply_activation_to_device(device)


func _apply_activation_to_device(device) -> void:
    var triggers := _overlay_activation_events()
    if not triggers.is_empty() and device:
        device.set_intercept_activation(triggers, "Gamepad:Button:QuickAccess2")


func _overlay_activation_events() -> PackedStringArray:
    var config_home := OS.get_environment("XDG_CONFIG_HOME")
    if config_home.is_empty():
        config_home = OS.get_environment("HOME").path_join(".config")
    var file := FileAccess.open(config_home.path_join("armada/overlay.json"), FileAccess.READ)
    var config: Dictionary = {}
    if file:
        var parsed = JSON.parse_string(file.get_as_text())
        if parsed is Dictionary:
            config = parsed
    var layout := "centered"
    if OS.get_environment("ARMADA_OGUI_LAYOUT") == "side":
        layout = "side"
    elif config.get("layout", "centered") == "side":
        layout = "side"
    var chord_key := "sideChord" if layout == "side" else "centeredChord"
    var chord: String = config.get(chord_key, "start_select")
    match chord:
        "guide":
            return PackedStringArray(["Gamepad:Button:Guide"])
        "quick_access":
            return PackedStringArray(["Gamepad:Button:QuickAccess"])
        "select_l1":
            return PackedStringArray(["Gamepad:Button:Select", "Gamepad:Button:LeftTop"])
        "select_r1":
            return PackedStringArray(["Gamepad:Button:Select", "Gamepad:Button:RightTop"])
        _:
            return PackedStringArray(["Gamepad:Button:Start", "Gamepad:Button:Select"])


func _register_overlay() -> void:
    logger = Log.get_logger("ArmadaControl", Log.LEVEL.DEBUG)
    var main: Control
    for candidate in get_tree().get_nodes_in_group("main"):
        if candidate is Control:
            main = candidate
            break
    var container := get_tree().get_first_node_in_group("overlay") as OverlayContainer
    if not container and main:
        container = OverlayContainer.new()
        container.name = "ArmadaControlOverlayContainer"
        container.z_index = 20
        main.add_child(container)
    if container and main:
        container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        container.size = main.size
    if not container:
        logger.error("OGUI overlay container is unavailable")
        return
    overlay_item = OVERLAY_SCENE.instantiate() as OverlayProvider
    if not overlay_item:
        logger.error("Armada overlay scene could not be instantiated")
        return
    overlay_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    overlay_item.size_flags_vertical = Control.SIZE_EXPAND_FILL
    overlay_item.custom_minimum_size = container.size
    overlay_container = container
    container.add_overlay(overlay_item)
    overlay_item.tree_exited.connect(_release_overlay_window)
    logger.info("Mounted Armada overlay provider")
    get_viewport().size_changed.connect(_update_overlay_geometry)
    _update_overlay_geometry()
    _claim_overlay_window()


func _update_overlay_geometry() -> void:
    if not is_instance_valid(overlay_container):
        return
    var size := get_viewport().get_visible_rect().size
    overlay_container.size = size
    if is_instance_valid(overlay_item):
        overlay_item.custom_minimum_size = size


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
    if is_instance_valid(overlay_item):
        overlay_item.queue_free()
