extends OverlayProvider

const QUICK_BAR_SCRIPT := preload("res://plugins/armada-control/quick_bar.gd")

var content: Control


func _ready() -> void:
    provider_id = "armada-control"

    var panel := PanelContainer.new()
    panel.name = "ArmadaControlOverlay"
    if _overlay_layout() == "side":
        var side := HBoxContainer.new()
        side.name = "ArmadaControlSide"
        side.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(side)
        var spacer := Control.new()
        spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        side.add_child(spacer)
        panel.custom_minimum_size = Vector2(480, 0)
        panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
        side.add_child(panel)
    else:
        var center := CenterContainer.new()
        center.name = "ArmadaControlCenter"
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(center)
        panel.custom_minimum_size = Vector2(720, 640)
        center.add_child(panel)

    var scroll := ScrollContainer.new()
    scroll.name = "ArmadaControlScroll"
    panel.add_child(scroll)

    content = QUICK_BAR_SCRIPT.new() as Control
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(content)

    var focus_group: FocusGroup
    for child in content.get_children():
        if child is FocusGroup:
            focus_group = child
            break
    if focus_group:
        focus_group.call_deferred("grab_focus")


func _overlay_layout() -> String:
    if OS.get_environment("ARMADA_OGUI_LAYOUT") == "side":
        return "side"
    var config_home := OS.get_environment("XDG_CONFIG_HOME")
    if config_home.is_empty():
        config_home = OS.get_environment("HOME").path_join(".config")
    var file := FileAccess.open(config_home.path_join("armada/overlay.json"), FileAccess.READ)
    if not file:
        return "centered"
    var data = JSON.parse_string(file.get_as_text())
    return "side" if data is Dictionary and data.get("layout", "centered") == "side" else "centered"


