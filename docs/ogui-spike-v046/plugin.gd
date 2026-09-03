extends Plugin

const QUICK_BAR_META := "armada_control_quick_bar"

var quick_bar_item: Control
var mounted_status: Label
var mounted_cards: Array[Control] = []
var state_watch_connected := false


func _ready() -> void:
    # Overlay summoning (Guide+B), Gamescope focus/overlay atoms, and the
    # InputPlumber intercept mode are owned entirely by OGUI core, which
    # switches them on menu/base state transitions. This plugin never
    # programs activation chords and never writes focus/overlay atoms or
    # the intercept mode: the intercept slot is single-writer and our old
    # startup claim broke the native summon. See overlay-summon.md.
    if "--overlay-mode" in OS.get_cmdline_args():
        call_deferred("_register_quick_bar")
        call_deferred("_watch_menu_state")
        return
    call_deferred("_register_quick_bar")


func _watch_menu_state() -> void:
    if state_watch_connected:
        return
    var quick_bar_state = load("res://assets/state/states/quick_bar_menu.tres")
    if quick_bar_state and quick_bar_state.has_signal("state_entered"):
        quick_bar_state.state_entered.connect(_on_quick_bar_opened)
        quick_bar_state.state_exited.connect(_on_quick_bar_closed)
        state_watch_connected = true
    var quick_bar := get_tree().get_first_node_in_group("quick-bar")
    if quick_bar and quick_bar is Control:
        if not quick_bar.visibility_changed.is_connected(_on_quick_bar_visibility):
            quick_bar.visibility_changed.connect(_on_quick_bar_visibility)


func _on_quick_bar_opened(_from) -> void:
    var quick_bar := get_tree().get_first_node_in_group("quick-bar")
    Log.get_logger("ArmadaControl", Log.LEVEL.DEBUG).info(
        "Native Quick Bar opened (visible=%s)" % str(quick_bar.visible if quick_bar else false))


func _on_quick_bar_closed(_to) -> void:
    Log.get_logger("ArmadaControl", Log.LEVEL.DEBUG).info("Native Quick Bar closed")


func _on_quick_bar_visibility() -> void:
    var quick_bar := get_tree().get_first_node_in_group("quick-bar")
    Log.get_logger("ArmadaControl", Log.LEVEL.DEBUG).info(
        "Native Quick Bar visibility=%s" % str(quick_bar.visible if quick_bar else false))


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
    if is_instance_valid(quick_bar_item) and quick_bar_item.has_method("_stop_calibration_session"):
        quick_bar_item.call("_stop_calibration_session")
    for card in mounted_cards:
        if is_instance_valid(card):
            card.queue_free()
    mounted_cards.clear()
    if is_instance_valid(mounted_status):
        mounted_status.queue_free()
    mounted_status = null
    if is_instance_valid(quick_bar_item):
        quick_bar_item.queue_free()
