extends Plugin

func _ready() -> void:
    if "--overlay-mode" in OS.get_cmdline_args():
        return
    call_deferred("_register_quick_bar")


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
    var quick_bar_item = quick_bar_script.new()
    var viewport := quick_bar.get_node_or_null(
        "MarginContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/Viewport"
    ) as VBoxContainer
    if not viewport:
        logger = Log.get_logger("ArmadaControl", Log.LEVEL.DEBUG)
        logger.error("OGUI Quick Bar content viewport could not be found")
        return
    quick_bar_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    viewport.add_child(quick_bar_item)
