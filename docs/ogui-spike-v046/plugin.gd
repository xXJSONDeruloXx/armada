extends Plugin

const OVERLAY_SCENE := preload("res://plugins/armada-control/overlay.tscn")
const QUICK_BAR_SCENE := preload("res://plugins/armada-control/quick_bar.gd")

func _ready() -> void:
    call_deferred("_register")


func _register() -> void:
    if "--overlay-mode" in OS.get_cmdline_args():
        _mount_overlay()
        return
    var quick_bar_item := QUICK_BAR_SCENE.new()
    quick_bar_item.open_requested.connect(_mount_overlay)
    add_to_quick_bar(quick_bar_item, load("res://assets/ui/icons/gear-fill.svg"))

func _mount_overlay() -> void:
    logger = Log.get_logger("ArmadaControlSpike", Log.LEVEL.DEBUG)
    var main: Control
    for candidate in get_tree().get_nodes_in_group("main"):
        if candidate is Control:
            main = candidate
            break
    if not main:
        logger.error("OGUI card UI scene was not found")
        return

    var container := get_tree().get_first_node_in_group("overlay") as OverlayContainer
    if not container:
        container = OverlayContainer.new()
        container.name = "ArmadaControlOverlayContainer"
        container.z_index = 20
        main.add_child(container)
        container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        container.size = get_viewport().get_visible_rect().size

    logger.info("Mounting Armada Control test overlay")
    container.add_overlay(OVERLAY_SCENE.instantiate())
    var gamescope := load("res://core/systems/gamescope/gamescope.tres")
    var xwayland = gamescope.get_xwayland(gamescope.XWAYLAND_TYPE_OGUI)
    var windows: PackedInt64Array = xwayland.get_windows_for_pid(OS.get_process_id())
    if windows.is_empty():
        logger.error("OGUI window was not found")
        return
    var window_id := windows[0]
    if xwayland.set_input_focus(window_id, 1) != OK:
        logger.error("Unable to set OGUI input focus")
    if xwayland.set_overlay(window_id, 1) != OK:
        logger.error("Unable to set OGUI overlay state")
    var input_plumber := load("res://core/systems/input/input_plumber.tres")
    input_plumber.manage_all_devices = true
    input_plumber.set_intercept_mode(2)
    logger.info("Armada Control test overlay owns Gamescope focus")
