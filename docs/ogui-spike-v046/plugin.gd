extends Plugin

func _ready() -> void:
    if "--overlay-mode" in OS.get_cmdline_args():
        return
    call_deferred("_register_quick_bar")


func _register_quick_bar() -> void:
    var quick_bar := get_tree().get_first_node_in_group("quick-bar")
    if not quick_bar:
        logger = Log.get_logger("ArmadaControl", Log.LEVEL.DEBUG)
        logger.warn("OGUI Quick Bar is unavailable; Armada side card is disabled")
        return

    var quick_bar_script = load("res://plugins/armada-control/quick_bar.gd")
    if not quick_bar_script:
        logger = Log.get_logger("ArmadaControl", Log.LEVEL.DEBUG)
        logger.error("Armada Quick Bar script could not be loaded")
        return
    var quick_bar_item = quick_bar_script.new()
    add_to_quick_bar(quick_bar_item, load("res://assets/ui/icons/gear-fill.svg"))
