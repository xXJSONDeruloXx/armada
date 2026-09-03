extends Control

signal open_requested

const CARD_BUTTON_SETTING := preload("res://core/ui/components/card_button_setting.tscn")
const BODY_LABELS := preload("res://plugins/armada-control/ogui-body-label.tres")
const BACKEND_SCRIPT := preload("res://plugins/armada-control/backend.gd")

var backend
var status_label: Label


func _ready() -> void:
    backend = BACKEND_SCRIPT.new()
    var section := Label.new()
    section.name = "SectionLabel"
    section.text = "Armada Control"
    section.label_settings = BODY_LABELS
    add_child(section)

    var content := VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_child(content)
    _add_action(content, "Open full control panel", open_requested.emit)
    _add_action(content, "Reapply performance", func(): _run_action("reapply_perf"))
    _add_action(content, "Refresh device state", func(): _run_action("get_config"))

    status_label = Label.new()
    status_label.label_settings = BODY_LABELS
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    content.add_child(status_label)

    var focus_group := FocusGroup.new()
    focus_group.current_focus = content.get_child(0)
    add_child(focus_group)


func _add_action(parent: Container, text: String, callback: Callable) -> void:
    var setting := CARD_BUTTON_SETTING.instantiate() as CardButtonSetting
    setting.text = text
    setting.button_text = "A"
    setting.show_label = true
    parent.add_child(setting)
    setting.pressed.connect(callback)


func _run_action(action: String) -> void:
    var response = backend.call_action(action)
    if response.get("ok", false):
        status_label.text = "Done"
    else:
        status_label.text = backend.last_error
