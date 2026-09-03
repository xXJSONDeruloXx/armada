extends Plugin

const QUICK_BAR_META := "armada_control_quick_bar"
const OVERLAY_SCENE := preload("res://plugins/armada-control/overlay.tscn")

var quick_bar_item: Control
var mounted_status: Label
var mounted_cards: Array[Control] = []
var overlay_item: OverlayProvider


func _ready() -> void:
    if "--overlay-mode" in OS.get_cmdline_args():
        call_deferred("_register_overlay")
        return
    call_deferred("_register_quick_bar")


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
    container.add_overlay(overlay_item)
    logger.info("Mounted Armada overlay provider")
    _claim_overlay_window()


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
    if xwayland.set_input_focus(window_id, 1) != OK:
        logger.warn("Unable to set OGUI input focus")
    if xwayland.set_overlay(window_id, 1) != OK:
        logger.warn("Unable to set OGUI overlay state")
    var input_plumber := load("res://core/systems/input/input_plumber.tres")
    if input_plumber:
        input_plumber.manage_all_devices = true
        input_plumber.set_intercept_mode(2)


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
    if "--overlay-mode" in OS.get_cmdline_args():
        var input_plumber := load("res://core/systems/input/input_plumber.tres")
        if input_plumber:
            input_plumber.set_intercept_mode(1)
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
