extends OverlayProvider

const BACKEND_SCRIPT := preload("res://plugins/armada-control/backend.gd")
const CARD_ICON_BUTTON := preload("res://core/ui/components/card_icon_button.tscn")
const CARD_BUTTON_SETTING := preload("res://core/ui/components/card_button_setting.tscn")
const DROPDOWN := preload("res://core/ui/components/dropdown.tscn")
const SLIDER := preload("res://core/ui/components/slider.tscn")
const TOGGLE := preload("res://core/ui/components/toggle.tscn")
const TITLE_LABELS := preload("res://plugins/armada-control/ogui-title-label.tres")
const SUBHEADING_LABELS := preload("res://plugins/armada-control/ogui-body-label.tres")

const PAGE_DEFINITIONS := [
    {"title": "Status", "icon": "ui/icons/status-active.svg"},
    {"title": "Power", "icon": "ui/icons/performance_icon.svg"},
    {"title": "Fans", "icon": "ui/icons/arrows-counter-clockwise-fill.svg"},
    {"title": "Games", "icon": "ui/icons/game-controller.svg"},
    {"title": "Settings", "icon": "ui/icons/gear-fill.svg"},
]

var backend
var config: Dictionary = {}
var pages: Array[Control] = []
var nav_buttons: Array[Control] = []
var current_page := 0
var status_label: Label
var panel: PanelContainer


func _ready() -> void:
    provider_id = "armada-control"
    backend = BACKEND_SCRIPT.new()
    _build_shell()
    call_deferred("_fit_to_viewport")
    get_tree().create_timer(0.1).timeout.connect(_refresh)


func _fit_to_viewport() -> void:
    size = get_viewport().get_visible_rect().size


func _build_shell() -> void:
    panel = PanelContainer.new()
    panel.name = "ArmadaControlPanel"
    panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
    panel.position = Vector2(120, 80)
    panel.size = Vector2(920, 720)
    add_child(panel)
    panel.visible = true

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 20)
    margin.add_theme_constant_override("margin_top", 20)
    margin.add_theme_constant_override("margin_right", 20)
    margin.add_theme_constant_override("margin_bottom", 20)
    panel.add_child(margin)

    var shell := HBoxContainer.new()
    shell.add_theme_constant_override("separation", 20)
    margin.add_child(shell)

    var navigation := VBoxContainer.new()
    navigation.custom_minimum_size = Vector2(68, 0)
    navigation.add_theme_constant_override("separation", 8)
    shell.add_child(navigation)
    _build_navigation(navigation)

    var page_column := VBoxContainer.new()
    page_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    shell.add_child(page_column)
    _build_page_column(page_column)


func _build_navigation(parent: VBoxContainer) -> void:
    for index in PAGE_DEFINITIONS.size():
        var definition: Dictionary = PAGE_DEFINITIONS[index]
        var slot := Control.new()
        slot.custom_minimum_size = Vector2(68, 64)
        parent.add_child(slot)

        var selected := PanelContainer.new()
        selected.name = "Selected"
        selected.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        selected.visible = index == current_page
        var selection_style = get_theme_stylebox("panel_focus", "SelectableText")
        if selection_style:
            selected.add_theme_stylebox_override("panel", selection_style.duplicate())
        slot.add_child(selected)

        var button := CARD_ICON_BUTTON.instantiate() as CardIconButton
        button.name = definition["title"] + "Button"
        button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        button.focus_mode = Control.FOCUS_ALL
        button.set("texture", load("res://assets/" + definition["icon"]))
        slot.add_child(button)
        var icon := button.get_node_or_null("Icon") as TextureRect
        if icon:
            icon.custom_minimum_size = Vector2(34, 34)
        button.pressed.connect(_show_page.bind(index))
        nav_buttons.append(button)

    for index in nav_buttons.size():
        var button := nav_buttons[index]
        if index > 0:
            button.focus_neighbor_top = nav_buttons[index - 1].get_path()
        if index + 1 < nav_buttons.size():
            button.focus_neighbor_bottom = nav_buttons[index + 1].get_path()


func _build_page_column(parent: VBoxContainer) -> void:
    var heading := _label("Armada Control", TITLE_LABELS)
    parent.add_child(heading)
    status_label = _label("Loading device state…", SUBHEADING_LABELS)
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    parent.add_child(status_label)

    var page_host := Control.new()
    page_host.name = "PageHost"
    page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(page_host)

    pages = []
    pages.append(_build_status_page())
    pages.append(_build_power_page())
    pages.append(_build_fans_page())
    pages.append(_build_games_page())
    pages.append(_build_settings_page())
    for page in pages:
        page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        page.visible = false
        page_host.add_child(page)
    _show_page(0)


func _label(text: String, settings: LabelSettings) -> Label:
    var label := Label.new()
    label.text = text
    label.label_settings = settings
    return label


func _page(title: String, description: String) -> VBoxContainer:
    var page := VBoxContainer.new()
    page.name = title.replace(" ", "") + "Page"
    page.add_theme_constant_override("separation", 10)
    page.add_child(_label(title, TITLE_LABELS))
    var description_label := _label(description, SUBHEADING_LABELS)
    description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    page.add_child(description_label)
    return page


func _scroll_page(page: VBoxContainer) -> VBoxContainer:
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    page.add_child(scroll)
    var content := VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(content)
    return content


func _button(parent: Container, text: String, callback: Callable) -> CardButtonSetting:
    var setting := CARD_BUTTON_SETTING.instantiate() as CardButtonSetting
    setting.text = text
    setting.button_text = "A"
    parent.add_child(setting)
    setting.pressed.connect(callback)
    return setting


func _dropdown(parent: Container, title: String, options: Array, selected_value: String, callback: Callable) -> Control:
    var dropdown := DROPDOWN.instantiate() as Dropdown
    dropdown.title = title
    parent.add_child(dropdown)
    dropdown.ready.connect(func():
        var selected_index := 0
        for index in options.size():
            var option = options[index]
            var value := String(option.get("data", option)) if option is Dictionary else String(option)
            var label := String(option.get("label", value)) if option is Dictionary else value
            dropdown.add_item(label)
            if value == selected_value:
                selected_index = index
        dropdown.select(selected_index)
        dropdown.item_selected.connect(func(index: int):
            if index >= 0 and index < options.size():
                var option = options[index]
                var value := String(option.get("data", option)) if option is Dictionary else String(option)
                callback.call(value)
        )
    )
    return dropdown


func _toggle(parent: Container, title: String, value: bool, callback: Callable) -> Control:
    var toggle := TOGGLE.instantiate() as Toggle
    toggle.text = title
    toggle.button_pressed = value
    parent.add_child(toggle)
    toggle.toggled.connect(callback)
    return toggle


func _slider(parent: Container, title: String, value: float, minimum: float, maximum: float, callback: Callable) -> Control:
    var slider := SLIDER.instantiate() as ValueSlider
    slider.text = title
    slider.min_value = minimum
    slider.max_value = maximum
    slider.value = value
    parent.add_child(slider)
    slider.value_changed.connect(callback)
    return slider


func _build_status_page() -> Control:
    var page := _page("Overview", "Armada device controls are available without Decky.")
    var content := _scroll_page(page)
    content.add_child(_label("The OGUI plugin owns the overlay focus while it is open.", SUBHEADING_LABELS))
    _button(content, "Refresh device state", _refresh)
    _button(content, "Reapply performance settings", func(): _call("reapply_perf"))
    _button(content, "Close overlay", queue_free)
    return page


func _build_power_page() -> Control:
    var page := _page("Power", "Select an Armada profile and tune CPU/GPU limits.")
    var content := _scroll_page(page)
    _button(content, "Load current profile", func(): _refresh())
    _button(content, "Save profile changes", func(): _save_power())
    return page


func _build_fans_page() -> Control:
    var page := _page("Fans", "Monitor temperature and save fan curve settings.")
    var content := _scroll_page(page)
    content.add_child(_label("Fan controls appear when the device advertises a fan backend.", SUBHEADING_LABELS))
    _button(content, "Refresh fan state", func(): _refresh_fans())
    _button(content, "Save fan settings", func(): _save_fans())
    return page


func _build_games_page() -> Control:
    var page := _page("Games", "Armada game tweaks and compatibility actions.")
    var content := _scroll_page(page)
    content.add_child(_label("Game-specific FEX and launch settings are loaded from the shared Armada schema.", SUBHEADING_LABELS))
    _button(content, "Refresh installed games", _refresh)
    _button(content, "Reapply performance settings", func(): _call("reapply_perf"))
    return page


func _build_settings_page() -> Control:
    var page := _page("Settings", "Controller, system, and overlay controls.")
    var content := _scroll_page(page)
    var controller_options: Array = config.get("controllerTypes", [
        {"data": "deck-uhid", "label": "Steam Deck"},
        {"data": "xb360", "label": "Xbox 360"},
        {"data": "ds5", "label": "DualSense"},
    ])
    _dropdown(content, "Controller emulation", controller_options, String(config.get("controllerType", "deck-uhid")), func(value): _call("set_controller_type", {"value": value}))
    _toggle(content, "Enable SSH", bool(config.get("sshEnabled", false)), func(value): _call("set_ssh_enabled", {"enabled": value}))
    _toggle(content, "Enable MTP", bool(config.get("mtpEnabled", false)), func(value): _call("set_mtp_enabled", {"enabled": value}))
    _toggle(content, "Automatic ABL updates", bool(config.get("ablAutoEnabled", false)), func(value): _call("set_abl_auto_enabled", {"enabled": value}))
    _button(content, "Launch calibration", func(): _call("begin_calibration_session", {"token": "armada-ogui"}))
    _button(content, "Restart Game Mode", func(): _call("restart_game_mode"))
    return page


func _show_page(index: int) -> void:
    if pages.is_empty():
        return
    current_page = clampi(index, 0, pages.size() - 1)
    for page_index in pages.size():
        pages[page_index].visible = page_index == current_page
        if page_index == current_page:
            var focusable := _first_focusable(pages[page_index])
            if focusable:
                focusable.grab_focus.call_deferred()
    for button_index in nav_buttons.size():
        var slot := nav_buttons[button_index].get_parent()
        var selected := slot.get_node_or_null("Selected")
        if selected:
            selected.visible = button_index == current_page


func _first_focusable(node: Node) -> Control:
    for child in node.get_children():
        if child is Control and child.focus_mode != Control.FOCUS_NONE and child.visible:
            return child
        var nested := _first_focusable(child)
        if nested:
            return nested
    return null


func _refresh() -> void:
    var capabilities = backend.call_action("get_capabilities")
    var response = backend.call_action("get_config")
    if response.get("ok", false):
        config = response.get("result", {})
        status_label.text = "API v%s · %s" % [capabilities.get("result", {}).get("api", "?"), config.get("cpuDeviceClass", "device")]
    else:
        status_label.text = backend.last_error


func _refresh_fans() -> void:
    var response = backend.call_action("get_fans_state")
    if response.get("ok", false):
        status_label.text = "Fan state refreshed"
    else:
        status_label.text = backend.last_error


func _save_power() -> void:
    var response = backend.call_action("save_power_config", {"data": config.get("power", {})})
    if response.get("ok", false):
        status_label.text = "Power profile saved"
    else:
        status_label.text = backend.last_error


func _save_fans() -> void:
    var response = backend.call_action("get_fans_state")
    if response.get("ok", false):
        status_label.text = "Fan settings ready"
    else:
        status_label.text = backend.last_error


func _call(action: String, fields: Dictionary = {}) -> void:
    var response = backend.call_action(action, fields)
    if response.get("ok", false):
        status_label.text = "Saved"
    else:
        status_label.text = backend.last_error
    if response.get("ok", false) and action.begins_with("set_"):
        _refresh()
