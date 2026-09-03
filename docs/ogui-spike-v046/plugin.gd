extends Plugin

const QUICK_BAR_META := "armada_control_quick_bar"

var quick_bar_item: Control
var mounted_cards: Array[Control] = []


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
    for card in mounted_cards:
        if is_instance_valid(card):
            card.queue_free()
    mounted_cards.clear()
    if is_instance_valid(quick_bar_item):
        quick_bar_item.queue_free()
