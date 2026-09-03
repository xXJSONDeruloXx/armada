extends OverlayProvider

const QUICK_BAR_SCRIPT := preload("res://plugins/armada-control/quick_bar.gd")

var content: Control


func _ready() -> void:
    provider_id = "armada-control"

    var panel := PanelContainer.new()
    panel.name = "ArmadaControlOverlay"
    panel.custom_minimum_size = Vector2(720, 640)
    panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    add_child(panel)

    var scroll := ScrollContainer.new()
    scroll.name = "ArmadaControlScroll"
    panel.add_child(scroll)

    content = QUICK_BAR_SCRIPT.new() as Control
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(content)

    var focus_group := FocusGroup.new()
    focus_group.current_focus = _first_focusable(content)
    content.add_child(focus_group)


func _first_focusable(node: Node) -> Control:
    for child in node.get_children():
        if child is Control and child.focus_mode != Control.FOCUS_NONE and child.visible:
            return child
        var nested := _first_focusable(child)
        if nested:
            return nested
    return null
