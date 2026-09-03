extends OverlayProvider

const QUICK_BAR_SCRIPT := preload("res://plugins/armada-control/quick_bar.gd")

var content: Control


func _ready() -> void:
    provider_id = "armada-control"

    var center := CenterContainer.new()
    center.name = "ArmadaControlCenter"
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(center)

    var panel := PanelContainer.new()
    panel.name = "ArmadaControlOverlay"
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


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_released("ogui_east") \
            or event.is_action_released("ogui_back") \
            or event.is_action_released("ogui_east_ov"):
        get_viewport().set_input_as_handled()
        queue_free()
