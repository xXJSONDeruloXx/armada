extends VBoxContainer

var status_label: Label
var toggle_button: Button
var toggled := false

func _ready() -> void:
    var title := Label.new()
    title.text = "Armada Control test"
    add_child(title)

    status_label = Label.new()
    status_label.text = "D-pad to move · A to press · B to close"
    add_child(status_label)

    var first := Button.new()
    first.text = "Button one"
    first.pressed.connect(func(): status_label.text = "Button one pressed")
    add_child(first)

    toggle_button = Button.new()
    toggle_button.text = "Toggle: Off"
    toggle_button.pressed.connect(toggle)
    add_child(toggle_button)

    var close := Button.new()
    close.text = "Close test panel"
    close.pressed.connect(_close_overlay)
    add_child(close)

    var focus_group := FocusGroup.new()
    add_child(focus_group)
    first.grab_focus.call_deferred()

func toggle() -> void:
    toggled = not toggled
    toggle_button.text = "Toggle: " + ("On" if toggled else "Off")
    status_label.text = "Toggle pressed"

func _close_overlay() -> void:
    get_parent().queue_free()
