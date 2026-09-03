extends OverlayProvider

var toggled := false

func _ready() -> void:
    provider_id = "armada-control-test"
    var panel := PanelContainer.new()
    panel.name = "ArmadaControlTestPanel"
    panel.custom_minimum_size = Vector2(620, 420)
    panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    add_child(panel)

    var content := VBoxContainer.new()
    panel.add_child(content)

    var title := Label.new()
    title.text = "Armada Control test"
    content.add_child(title)

    var status_label := Label.new()
    status_label.name = "StatusLabel"
    status_label.text = "D-pad to move · A to press · B to close"
    content.add_child(status_label)

    var first := Button.new()
    first.text = "Button one"
    first.pressed.connect(func(): status_label.text = "Button one pressed")
    content.add_child(first)

    var toggle_button := Button.new()
    toggle_button.text = "Toggle: Off"
    toggle_button.pressed.connect(func():
        toggled = not toggled
        toggle_button.text = "Toggle: " + ("On" if toggled else "Off")
        status_label.text = "Toggle pressed"
    )
    content.add_child(toggle_button)

    var close := Button.new()
    close.text = "Close test panel"
    close.pressed.connect(_close_overlay)
    content.add_child(close)

    var focus_group := FocusGroup.new()
    content.add_child(focus_group)
    first.grab_focus.call_deferred()

func _close_overlay() -> void:
    queue_free()
