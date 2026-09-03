extends Control

const CARD_BUTTON_SETTING := preload("res://core/ui/components/card_button_setting.tscn")
const DROPDOWN := preload("res://core/ui/components/dropdown.tscn")
const QUICK_BAR_CARD := preload("res://core/ui/card_ui/quick_bar/qb_card.tscn")
const SLIDER := preload("res://core/ui/components/slider.tscn")
const TEXT_INPUT := preload("res://core/ui/components/text_input.tscn")
const TOGGLE := preload("res://core/ui/components/toggle.tscn")
const BODY_LABELS := preload("res://plugins/armada-control/ogui-body-label.tres")
const BACKEND_SCRIPT := preload("res://plugins/armada-control/backend.gd")

var backend
var config: Dictionary = {}
var selected_profile := "balanced"
var reset_profile_pending := false
var cpu_slider: ValueSlider
var gpu_min_slider: ValueSlider
var gpu_slider: ValueSlider
var fan_curve_dropdown: Dropdown
var governor_dropdown: Dropdown
var underclock_dropdown: Dropdown
var curve_editor_dropdown: Dropdown
var curve_point_dropdown: Dropdown
var curve_temp_slider: ValueSlider
var curve_pwm_slider: ValueSlider
var fan_stop_toggle: Toggle
var fan_stop_temp_slider: ValueSlider
var fan_fix_pwm_button: CardButtonSetting
var fan_reset_curve_button: CardButtonSetting
var curve_name_input: ComponentTextInput
var curve_delete_dropdown: Dropdown
var selected_curve := ""
var selected_curve_point := 0
var selected_delete_curve := ""
var delete_curve_pending := false
var reset_curve_pending := false
var _syncing_curve_controls := false
var status_label: Label
var fan_state: Dictionary = {}
var fan_original_state: Dictionary = {}
var fan_stop_previous_min_pwm := -1
var fans_parent: Container
var current_appid := ""
var compat_tools: Array = []
var compat_tool := ""
var global_resolution := "Default"
var installed_games: Array = []
var rgb_brightness_slider: ValueSlider
var rgb_color_slider: ValueSlider
var _syncing_rgb_controls := false
var content_root: VBoxContainer
var calibration_button: CardButtonSetting
var calibration_timer: Timer
var calibration_capture: Dictionary = {}
var calibration_recording := false
var calibration_sliders: Dictionary = {}
var reset_calibration_pending := false
var restart_game_mode_pending := false
var selected_game_appid := ""
var game_target_dropdown: Dropdown
var games_controls: VBoxContainer
var custom_cores_text := ""
var custom_gamescope_cores_text := ""
var environment_dropdown: Dropdown
var environment_name_input: ComponentTextInput
var environment_value_input: ComponentTextInput
var selected_environment_key := ""
var reset_game_pending := false
var compat_appid := ""
var compat_target_dropdown: Dropdown
var compat_controls: VBoxContainer
var compat_appid_input: ComponentTextInput
var compat_launch_input: ComponentTextInput
var compat_launch_options := ""
var compat_game_tool := ""
var compat_game_resolution := "Default"
var compat_reset_pending := false
var compat_reset_all_pending := false


func _init() -> void:
    var section := Label.new()
    section.name = "SectionLabel"
    section.text = "Armada Control"
    section.label_settings = BODY_LABELS
    add_child(section)


func _ready() -> void:
    backend = BACKEND_SCRIPT.new()
    _load_config()
    _build()


func _load_config() -> bool:
    var loaded := false
    var response = backend.call_action("get_config")
    if response.get("ok", false):
        config = response.get("result", {})
        loaded = true
    var games = backend.call_action("get_installed_games")
    if games.get("ok", false):
        installed_games = games.get("result", [])
    var fans = backend.call_action("get_fans_state")
    if fans.get("ok", false):
        fan_state = fans.get("result", {})
        fan_original_state = fan_state.duplicate(true)
    var runtime = backend.call_action("get_runtime_game")
    if runtime.get("ok", false) and runtime.get("result") is Dictionary:
        current_appid = String(runtime["result"].get("appid", ""))
    var tools = backend.call_steam("get_global_compat_tools")
    if tools.get("ok", false):
        compat_tools = tools.get("result", {}).get("tools", [])
    var resolution = backend.call_steam("get_global_resolution")
    if resolution.get("ok", false):
        global_resolution = String(resolution.get("result", {}).get("value", "Default"))
    compat_tool = String(config.get("tweaks", {}).get("global", {}).get("windowsCompatTool", ""))
    selected_profile = String(config.get("power", {}).get("general", {}).get("default_profile", "balanced"))
    compat_appid = current_appid
    for game in installed_games:
        if game is Dictionary and String(game.get("appid", "")) == current_appid:
            selected_game_appid = current_appid
            break
    return loaded


func _build() -> void:
    var content := VBoxContainer.new()
    content.name = "ArmadaContent"
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content_root = content
    add_child(content)

    status_label = Label.new()
    status_label.name = "ArmadaStatus"
    status_label.label_settings = BODY_LABELS
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    content.add_child(status_label)

    _section(content, "Power", _build_power)
    _section(content, "Fans", _build_fans)
    _section(content, "Games", _build_games)
    _section(content, "Compatibility", _build_compatibility)
    _section(content, "System", _build_system)
    _section(content, "Actions", _build_actions)
    _update_status()

    var focus_group := FocusGroup.new()
    focus_group.current_focus = _first_focusable(content)
    add_child(focus_group)


func _section(parent: Container, title: String, builder: Callable) -> void:
    var card := QUICK_BAR_CARD.instantiate() as QuickBarCard
    card.title = title

    var content := VBoxContainer.new()
    card.add_content(content)
    builder.call(content)

    var focus_group := FocusGroup.new()
    focus_group.current_focus = _first_focusable(content)
    content.add_child(focus_group)
    parent.add_child(card)


func _build_power(parent: Container) -> void:
    var power: Dictionary = config.get("power", {})
    var profiles: Dictionary = power.get("profiles", {})
    var options: Array = []
    for name in profiles:
        var profile: Dictionary = profiles[name]
        options.append({"data": name, "label": String(profile.get("label", name))})
    if options.is_empty():
        options = [
            {"data": "eco", "label": "Eco"},
            {"data": "balanced", "label": "Balanced"},
            {"data": "performance", "label": "Performance"},
        ]
    _dropdown(parent, "Power profile", options, selected_profile, _select_profile)

    var profile: Dictionary = profiles.get(selected_profile, {})
    var device_class := String(config.get("cpuDeviceClass", ""))
    var underclock_sets: Dictionary = power.get("underclocks", {})
    var underclocks: Dictionary = underclock_sets.get(device_class, {})
    if not underclocks.is_empty():
        var underclock_options: Array = [{"data": "none", "label": "None"}]
        for name in underclocks:
            underclock_options.append({"data": name, "label": String(name).capitalize()})
        underclock_dropdown = _dropdown(parent, "CPU underclock", underclock_options, String(profile.get("cpu_underclock", "none")), func(value): _save_profile_value("cpu_underclock", value))
    else:
        cpu_slider = _slider(parent, "CPU maximum", _percent(profile.get("cpu_max", "1.0")), 35, 100, func(value): _save_profile_limit("cpu_max", value / 100.0))
    gpu_min_slider = _slider(parent, "GPU minimum", _percent(profile.get("gpu_min", "0.0")), 0, 100, func(value): _save_profile_limit("gpu_min", value / 100.0))
    gpu_slider = _slider(parent, "GPU maximum", _percent(profile.get("gpu_max", "1.0")), 35, 100, func(value): _save_profile_limit("gpu_max", value / 100.0))
    var curves: Array = []
    for name in power.get("fan_curves", {}):
        curves.append({"data": name, "label": String(power["fan_curves"][name].get("label", name))})
    if not curves.is_empty():
        fan_curve_dropdown = _dropdown(parent, "Fan curve", curves, String(profile.get("fan_curve", curves[0]["data"])), func(value): _save_profile_value("fan_curve", value))
    var governors: Array = []
    for name in config.get("perf", {}).get("governors", []):
        governors.append({"data": name, "label": name})
    if not governors.is_empty():
        governor_dropdown = _dropdown(parent, "CPU governor", governors, String(profile.get("cpu_governor", governors[0]["data"])), func(value): _save_profile_value("cpu_governor", value))
    _action(parent, "Reset profile", _reset_profile)


func _build_system(parent: Container) -> void:
    _action(parent, "Refresh device state", _refresh_device_state)
    var controller_options: Array = config.get("controllerTypes", [
        {"data": "deck-uhid", "label": "Steam Deck"},
        {"data": "xb360", "label": "Xbox 360"},
        {"data": "ds5", "label": "DualSense"},
    ])
    _dropdown(parent, "Controller emulation", controller_options, String(config.get("controllerType", "deck-uhid")), func(value): _call("set_controller_type", {"value": value}))
    _toggle(parent, "Automatic ABL updates", bool(config.get("ablAutoEnabled", false)), func(value): _call("set_abl_auto_enabled", {"enabled": value}))
    _toggle(parent, "Enable SSH", bool(config.get("sshEnabled", false)), func(value): _call("set_ssh_enabled", {"enabled": value}))
    _toggle(parent, "Enable MTP", bool(config.get("mtpEnabled", false)), func(value): _call("set_mtp_enabled", {"enabled": value}))
    var sleep_modes: Array = config.get("sleepModes", [])
    if sleep_modes.size() > 1:
        _dropdown(parent, "Sleep mode", sleep_modes, String(config.get("sleepMode", sleep_modes[0])), func(value): _call("set_sleep_mode", {"value": value}))
    var desktop_modes: Array = config.get("desktopModes", [])
    if desktop_modes.size() > 1:
        _dropdown(parent, "Desktop mode", desktop_modes, String(config.get("desktopMode", desktop_modes[0])), func(value): _call("set_desktop_mode", {"value": value}))
    if bool(config.get("rgbSupported", false)):
        var rgb = _call_result("get_rgb")
        if rgb is Dictionary:
            _toggle(parent, "RGB lighting", bool(rgb.get("enabled", false)), func(value): _set_rgb(value, rgb))
            rgb_brightness_slider = _slider(parent, "RGB brightness", float(rgb.get("brightness", 100)), 0, 100, func(value): _set_rgb_brightness(value, rgb))
            rgb_color_slider = _slider(parent, "RGB color", _rgb_hue(String(rgb.get("color", "FFFFFF"))), 0, 359, func(value): _set_rgb_color(value, rgb))
            rgb_brightness_slider.editable = bool(rgb.get("enabled", false))
            rgb_color_slider.editable = bool(rgb.get("enabled", false))

    for item in [{"key": "osVersion", "label": "OS version"}, {"key": "ablVersion", "label": "ABL version"}]:
        var version := String(config.get(item["key"], ""))
        if not version.is_empty():
            var version_label := Label.new()
            version_label.text = "%s: %s" % [item["label"], version]
            version_label.label_settings = BODY_LABELS
            parent.add_child(version_label)

    var temp = _call_result("get_current_temp")
    if temp != null:
        var temperature := Label.new()
        temperature.text = "Temperature: %s °C" % temp
        temperature.label_settings = BODY_LABELS
        parent.add_child(temperature)


func _build_fans(parent: Container) -> void:
    fans_parent = parent
    var settings: Dictionary = fan_state.get("fanSettings", {})
    if settings.is_empty():
        _action(parent, "Refresh fan state", _refresh_fans)
        return

    var curves: Dictionary = fan_state.get("fanCurves", {})
    var curve_options: Array = []
    for name in curves:
        var curve: Dictionary = curves[name]
        curve_options.append({"data": name, "label": String(curve.get("label", name))})
    curve_options.sort_custom(func(a, b): return String(a["label"]) < String(b["label"]))
    selected_curve = _active_curve(curves)
    curve_editor_dropdown = _dropdown(parent, "Curve", curve_options, selected_curve, _select_curve)
    curve_point_dropdown = _dropdown(parent, "Point", [], "", _select_curve_point)
    curve_point_dropdown.ready.connect(_populate_curve_points)
    curve_temp_slider = _slider(parent, "Point temperature", 60, 0, 120, _stage_curve_temperature)
    curve_pwm_slider = _slider(parent, "Point PWM", 128, 0, 255, _stage_curve_pwm)
    curve_pwm_slider.step = 5
    _action(parent, "Add point", _add_curve_point)
    _action(parent, "Remove point", _remove_curve_point)
    var fan_stop_enabled := _curve_has_fan_stop()
    fan_stop_toggle = _toggle(parent, "Fan stop", fan_stop_enabled, _toggle_fan_stop)
    fan_stop_temp_slider = _slider(parent, "Fan stop temperature", _fan_stop_temperature(), 0, 120, _stage_fan_stop_temperature)
    fan_stop_temp_slider.visible = fan_stop_enabled
    fan_fix_pwm_button = _action(parent, "Fix minimum PWM", _fix_minimum_pwm)
    fan_fix_pwm_button.visible = _fan_below_min_pwm()
    fan_reset_curve_button = _action(parent, "Reset curve to factory", _reset_curve)
    fan_reset_curve_button.visible = fan_state.get("factoryFanCurves", {}).has(selected_curve)
    _build_curve_management(parent)

    var current_temp = fan_state.get("currentTemp")
    if current_temp != null:
        var temperature := Label.new()
        temperature.text = "Fan temperature: %s °C" % current_temp
        temperature.label_settings = BODY_LABELS
        parent.add_child(temperature)
    _slider(parent, "Ramp up", float(settings.get("ramp_up", 36)), 1, 255, func(value): _stage_fan_setting("ramp_up", value))
    _slider(parent, "Ramp down", float(settings.get("ramp_down", 6)), 1, 255, func(value): _stage_fan_setting("ramp_down", value))
    _slider(parent, "Smoothing (%)", roundi(float(settings.get("smoothing", 0.0)) * 100.0), 0, 99, func(value): _stage_fan_setting("smoothing", value / 100.0))
    var minimum_pwm_slider := _slider(parent, "Minimum PWM", float(settings.get("min_pwm", 0)), 0, 255, func(value): _stage_fan_setting("min_pwm", roundi(value)))
    minimum_pwm_slider.step = 5
    _action(parent, "Save fan settings", _save_fans)
    _action(parent, "Revert changes", _revert_fans)


func _build_curve_management(parent: Container) -> void:
    curve_name_input = TEXT_INPUT.instantiate() as ComponentTextInput
    curve_name_input.title = "New curve"
    curve_name_input.description = ""
    curve_name_input.placeholder_text = "Name"
    parent.add_child(curve_name_input)
    var curve_description := curve_name_input.get_node_or_null("DescriptionLabel") as Label
    if curve_description:
        curve_description.visible = false
    curve_name_input.ready.connect(func():
        curve_name_input.description = ""
        var ready_curve_description := curve_name_input.get_node_or_null("DescriptionLabel") as Label
        if ready_curve_description:
            ready_curve_description.visible = false
        call_deferred("_hide_component_description", curve_name_input)
    )
    curve_name_input.tree_entered.connect(func(): call_deferred("_hide_component_description", curve_name_input))
    call_deferred("_hide_component_description", curve_name_input)
    _action(parent, "Create curve", _create_curve)

    var curves: Dictionary = fan_state.get("fanCurves", {})
    var protected: Dictionary = fan_state.get("factoryFanCurves", {})
    var profiles: Dictionary = fan_state.get("profiles", {})
    var used: Dictionary = {}
    for profile in profiles.values():
        if profile is Dictionary:
            used[String(profile.get("fan_curve", ""))] = true
    var deletable: Array = []
    for name in curves:
        if not protected.has(name) and not used.has(name):
            deletable.append({"data": name, "label": String(curves[name].get("label", name))})
    deletable.sort_custom(func(a, b): return String(a["label"]) < String(b["label"]))
    selected_delete_curve = String(deletable[0]["data"]) if not deletable.is_empty() else ""
    curve_delete_dropdown = _dropdown(parent, "Delete curve", deletable, selected_delete_curve, _select_delete_curve)
    _action(parent, "Delete curve", _delete_curve)


func _select_delete_curve(name: String) -> void:
    selected_delete_curve = name
    delete_curve_pending = false


func _create_curve() -> void:
    var name := _curve_slug(curve_name_input.text)
    if name.is_empty():
        _update_status("Enter a curve name")
        return
    var curves: Dictionary = fan_state.get("fanCurves", {})
    if curves.has(name):
        _update_status("Curve already exists")
        return
    curves[name] = {"label": curve_name_input.text.strip_edges(), "curve": "40:0,60:128,80:255"}
    fan_state["fanCurves"] = curves
    selected_curve = name
    selected_curve_point = 0
    curve_name_input.text = ""
    _refresh_curve_dropdowns()
    _update_status("Curve staged")


func _delete_curve() -> void:
    if selected_delete_curve.is_empty():
        return
    if not delete_curve_pending:
        delete_curve_pending = true
        _update_status("Press A again to delete curve")
        return
    var curves: Dictionary = fan_state.get("fanCurves", {})
    var protected: Dictionary = fan_state.get("factoryFanCurves", {})
    var profiles: Dictionary = fan_state.get("profiles", {})
    for profile in profiles.values():
        if profile is Dictionary and String(profile.get("fan_curve", "")) == selected_delete_curve:
            _update_status("Curve is in use")
            delete_curve_pending = false
            return
    if protected.has(selected_delete_curve):
        _update_status("Factory curve")
        delete_curve_pending = false
        return
    curves.erase(selected_delete_curve)
    fan_state["fanCurves"] = curves
    selected_delete_curve = ""
    delete_curve_pending = false
    selected_curve = _active_curve(curves)
    selected_curve_point = 0
    _refresh_curve_dropdowns()
    _update_status("Curve staged")


func _refresh_curve_dropdowns() -> void:
    var curves: Dictionary = fan_state.get("fanCurves", {})
    var options: Array = []
    for name in curves:
        options.append({"data": name, "label": String(curves[name].get("label", name))})
    options.sort_custom(func(a, b): return String(a["label"]) < String(b["label"]))
    if curve_editor_dropdown:
        curve_editor_dropdown.clear()
        var values: Array = []
        for option in options:
            curve_editor_dropdown.add_item(String(option["label"]))
            values.append(String(option["data"]))
        curve_editor_dropdown.set_meta("armada_values", values)
        if not values.is_empty():
            curve_editor_dropdown.select(_dropdown_index(curve_editor_dropdown, selected_curve))
    if curve_delete_dropdown:
        var protected: Dictionary = fan_state.get("factoryFanCurves", {})
        var profiles: Dictionary = fan_state.get("profiles", {})
        var used: Dictionary = {}
        for profile in profiles.values():
            if profile is Dictionary:
                used[String(profile.get("fan_curve", ""))] = true
        var deletable: Array = []
        for name in curves:
            if not protected.has(name) and not used.has(name):
                deletable.append({"data": name, "label": String(curves[name].get("label", name))})
        deletable.sort_custom(func(a, b): return String(a["label"]) < String(b["label"]))
        var delete_values: Array = []
        curve_delete_dropdown.clear()
        for option in deletable:
            curve_delete_dropdown.add_item(String(option["label"]))
            delete_values.append(String(option["data"]))
        curve_delete_dropdown.set_meta("armada_values", delete_values)
        if selected_delete_curve.is_empty() or not delete_values.has(selected_delete_curve):
            selected_delete_curve = String(delete_values[0]) if not delete_values.is_empty() else ""
        if not delete_values.is_empty():
            curve_delete_dropdown.select(_dropdown_index(curve_delete_dropdown, selected_delete_curve))
    _populate_curve_points()
    if fan_stop_toggle:
        fan_stop_toggle.button_pressed = _curve_has_fan_stop()
    if fan_stop_temp_slider:
        fan_stop_temp_slider.value = _fan_stop_temperature()
        fan_stop_temp_slider.visible = fan_stop_toggle.button_pressed if fan_stop_toggle else false
    if fan_fix_pwm_button:
        fan_fix_pwm_button.visible = _fan_below_min_pwm()
    if fan_reset_curve_button:
        fan_reset_curve_button.visible = fan_state.get("factoryFanCurves", {}).has(selected_curve)


func _curve_slug(value: String) -> String:
    var regex := RegEx.new()
    regex.compile("[^a-zA-Z0-9_]+")
    var result := regex.sub(value.strip_edges().to_lower(), "_", true)
    while result.begins_with("_"):
        result = result.trim_prefix("_")
    while result.ends_with("_"):
        result = result.trim_suffix("_")
    return result.left(32)


func _active_curve(curves: Dictionary) -> String:
    var active_profile := String(fan_state.get("activeProfile", ""))
    var profiles: Dictionary = fan_state.get("profiles", {})
    var active: Dictionary = profiles.get(active_profile, {})
    var name := String(active.get("fan_curve", ""))
    if curves.has(name):
        return name
    var names: Array = curves.keys()
    names.sort()
    return String(names[0]) if not names.is_empty() else ""


func _curve_points() -> Array:
    var curves: Dictionary = fan_state.get("fanCurves", {})
    var curve: Dictionary = curves.get(selected_curve, {})
    var points: Array = []
    for item in String(curve.get("curve", "")).split(","):
        var parts := item.strip_edges().split(":")
        if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
            continue
        points.append({"temp": clampi(int(parts[0]), 0, 120), "pwm": clampi(int(parts[1]), 0, 255)})
    points.sort_custom(func(a, b): return int(a["temp"]) < int(b["temp"]))
    return points


func _write_curve_points(points: Array) -> void:
    var curves: Dictionary = fan_state.get("fanCurves", {})
    var curve: Dictionary = curves.get(selected_curve, {})
    points.sort_custom(func(a, b): return int(a["temp"]) < int(b["temp"]))
    var values: Array = []
    for point in points:
        values.append("%d:%d" % [int(point["temp"]), int(point["pwm"])])
    curve["curve"] = ",".join(values)
    curves[selected_curve] = curve
    fan_state["fanCurves"] = curves


func _populate_curve_points() -> void:
    if not curve_point_dropdown:
        return
    var points := _curve_points()
    curve_point_dropdown.clear()
    var indexes: Array = []
    for index in points.size():
        var point: Dictionary = points[index]
        curve_point_dropdown.add_item("%d °C / %d%%" % [int(point["temp"]), roundi(float(point["pwm"]) / 255.0 * 100.0)])
        indexes.append(index)
    curve_point_dropdown.set_meta("armada_values", indexes)
    if points.is_empty():
        selected_curve_point = 0
        return
    selected_curve_point = clampi(selected_curve_point, 0, points.size() - 1)
    curve_point_dropdown.select(selected_curve_point)
    _sync_curve_point(points[selected_curve_point])


func _sync_curve_point(point: Dictionary) -> void:
    if not curve_temp_slider or not curve_pwm_slider:
        return
    _syncing_curve_controls = true
    curve_temp_slider.value = int(point.get("temp", 60))
    curve_pwm_slider.value = int(point.get("pwm", 128))
    _syncing_curve_controls = false


func _select_curve(name: String) -> void:
    selected_curve = name
    selected_curve_point = 0
    reset_curve_pending = false
    _populate_curve_points()


func _select_curve_point(value: String) -> void:
    if not value.is_valid_int():
        return
    selected_curve_point = int(value)
    var points := _curve_points()
    if selected_curve_point >= 0 and selected_curve_point < points.size():
        _sync_curve_point(points[selected_curve_point])


func _stage_curve_temperature(value: float) -> void:
    if _syncing_curve_controls:
        return
    var points := _curve_points()
    if selected_curve_point < 0 or selected_curve_point >= points.size():
        return
    points[selected_curve_point]["temp"] = clampi(roundi(value), 0, 120)
    _write_curve_points(points)
    _populate_curve_points()
    _update_status("Fan point staged")


func _stage_curve_pwm(value: float) -> void:
    if _syncing_curve_controls:
        return
    var points := _curve_points()
    if selected_curve_point < 0 or selected_curve_point >= points.size():
        return
    points[selected_curve_point]["pwm"] = clampi(roundi(value), 0, 255)
    _write_curve_points(points)
    _populate_curve_points()
    _update_status("Fan point staged")


func _add_curve_point() -> void:
    var points := _curve_points()
    var added := {"temp": 60, "pwm": 128}
    if not points.is_empty():
        var last: Dictionary = points[points.size() - 1]
        if int(last["temp"]) >= 120:
            _update_status("Curve already reaches 120 °C")
            return
        added = {"temp": mini(int(last["temp"]) + 10, 120), "pwm": int(last["pwm"])}
    points.append(added)
    points.sort_custom(func(a, b): return int(a["temp"]) < int(b["temp"]))
    selected_curve_point = points.find(added)
    _write_curve_points(points)
    _populate_curve_points()
    _update_status("Fan point added")


func _remove_curve_point() -> void:
    var points := _curve_points()
    if points.size() <= 1:
        _update_status("Keep one fan point")
        return
    points.remove_at(clampi(selected_curve_point, 0, points.size() - 1))
    selected_curve_point = clampi(selected_curve_point - 1, 0, points.size() - 1)
    _write_curve_points(points)
    _populate_curve_points()
    _update_status("Fan point removed")


func _curve_has_fan_stop() -> bool:
    var points := _curve_points()
    return not points.is_empty() and int(points[0]["pwm"]) == 0


func _fan_stop_temperature() -> float:
    var points := _curve_points()
    var temperature := 60
    for point in points:
        if int(point["pwm"]) != 0:
            break
        temperature = int(point["temp"])
    return temperature


func _toggle_fan_stop(enabled: bool) -> void:
    if enabled:
        fan_stop_previous_min_pwm = int(fan_state.get("fanSettings", {}).get("min_pwm", 0))
        _set_fan_stop_points(60)
    else:
        _restore_fan_points()
        if not _other_curve_has_fan_stop() and fan_stop_previous_min_pwm >= 0:
            _stage_fan_setting("min_pwm", fan_stop_previous_min_pwm)
        fan_stop_previous_min_pwm = -1
    if fan_stop_temp_slider:
        fan_stop_temp_slider.visible = enabled
    if enabled:
        _stage_fan_setting("min_pwm", 0)
    _populate_curve_points()
    _update_status("Fan stop staged")


func _stage_fan_stop_temperature(value: float) -> void:
    if not fan_stop_toggle or not fan_stop_toggle.button_pressed or _syncing_curve_controls:
        return
    _set_fan_stop_points(clampi(roundi(value), 0, 120))
    _populate_curve_points()
    _update_status("Fan stop staged")


func _set_fan_stop_points(temperature: int) -> void:
    var points := _restore_fan_points_array(_curve_points())
    var zeroed: Array = []
    var above: Array = []
    for point in points:
        if int(point["temp"]) <= temperature:
            zeroed.append({"temp": int(point["temp"]), "pwm": 0})
        else:
            above.append(point)
    if zeroed.is_empty() or int(zeroed[zeroed.size() - 1]["temp"]) != temperature:
        zeroed.append({"temp": temperature, "pwm": 0})
    if above.is_empty() and temperature < 120:
        zeroed.append({"temp": mini(temperature + 10, 120), "pwm": 128})
    elif not above.is_empty():
        zeroed.append_array(above)
    _write_curve_points(zeroed)


func _restore_fan_points() -> void:
    _write_curve_points(_restore_fan_points_array(_curve_points()))


func _restore_fan_points_array(points: Array) -> Array:
    var zero_count := 0
    while zero_count < points.size() and int(points[zero_count]["pwm"]) == 0:
        zero_count += 1
    if zero_count == 0:
        return points
    var restore_pwm := 128
    if zero_count < points.size():
        restore_pwm = int(points[zero_count]["pwm"])
    for index in zero_count:
        points[index]["pwm"] = restore_pwm
    if zero_count == points.size() and int(points[zero_count - 1]["temp"]) < 120:
        points.append({"temp": mini(int(points[zero_count - 1]["temp"]) + 20, 120), "pwm": restore_pwm})
    return points


func _other_curve_has_fan_stop() -> bool:
    var curves: Dictionary = fan_state.get("fanCurves", {})
    for name in curves:
        if String(name) == selected_curve:
            continue
        var points: Array = []
        for item in String(curves[name].get("curve", "")).split(","):
            var parts := item.strip_edges().split(":")
            if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
                points.append({"pwm": int(parts[1])})
        if not points.is_empty() and int(points[0]["pwm"]) == 0:
            return true
    return false


func _fan_below_min_pwm() -> bool:
    var minimum := int(fan_state.get("fanSettings", {}).get("min_pwm", 0))
    for point in _curve_points():
        if int(point["pwm"]) < minimum:
            return true
    return false


func _fix_minimum_pwm() -> void:
    var points := _curve_points()
    if points.is_empty():
        return
    var minimum := int(points[0]["pwm"])
    for point in points:
        minimum = mini(minimum, int(point["pwm"]))
    _stage_fan_setting("min_pwm", minimum)
    if fan_fix_pwm_button:
        fan_fix_pwm_button.visible = false
    _update_status("Minimum PWM staged")


func _reset_curve() -> void:
    var factory: Dictionary = fan_state.get("factoryFanCurves", {}).get(selected_curve, {})
    if factory.is_empty():
        _update_status("No factory curve")
        return
    if not reset_curve_pending:
        reset_curve_pending = true
        _update_status("Press A again to reset curve")
        return
    var curves: Dictionary = fan_state.get("fanCurves", {}).duplicate(true)
    curves[selected_curve] = factory.duplicate(true)
    fan_state["fanCurves"] = curves
    reset_curve_pending = false
    selected_curve_point = 0
    _refresh_curve_dropdowns()
    _update_status("Curve reset")


func _revert_fans() -> void:
    if fan_original_state.is_empty():
        _update_status("Original fan state unavailable")
        return
    fan_state = fan_original_state.duplicate(true)
    selected_curve = _active_curve(fan_state.get("fanCurves", {}))
    selected_curve_point = 0
    reset_curve_pending = false
    fan_stop_previous_min_pwm = -1
    _rebuild_fan_controls()
    _update_status("Fan changes reverted")


func _build_actions(parent: Container) -> void:
    _action(parent, "Reapply performance settings", func(): _call("reapply_perf"))
    calibration_button = _action(parent, "Start controller calibration", _toggle_calibration)
    for item in [
        {"key": "left_x", "label": "Left X", "minimum": -1.0, "maximum": 1.0},
        {"key": "left_y", "label": "Left Y", "minimum": -1.0, "maximum": 1.0},
        {"key": "right_x", "label": "Right X", "minimum": -1.0, "maximum": 1.0},
        {"key": "right_y", "label": "Right Y", "minimum": -1.0, "maximum": 1.0},
        {"key": "left_trigger", "label": "LT (%)", "minimum": 0.0, "maximum": 100.0},
        {"key": "right_trigger", "label": "RT (%)", "minimum": 0.0, "maximum": 100.0},
    ]:
        var slider := _slider(parent, item["label"], 0, item["minimum"], item["maximum"], func(_value): pass)
        slider.focus_mode = Control.FOCUS_NONE
        slider.editable = false
        if item["minimum"] < 0:
            slider.show_decimal = true
        calibration_sliders[item["key"]] = slider
    _action(parent, "Reset controller calibration", _reset_calibration)
    _action(parent, "Restart Game Mode", _restart_game_mode)
    calibration_timer = Timer.new()
    calibration_timer.wait_time = 0.1
    calibration_timer.timeout.connect(_capture_calibration_sample)
    add_child(calibration_timer)


func _toggle_calibration() -> void:
    if not calibration_recording:
        var response = backend.call_action("begin_calibration_session", {"token": "armada-ogui-quickbar"})
        if not response.get("ok", false):
            _update_status(backend.last_error)
            return
        calibration_capture = {}
        calibration_recording = true
        calibration_button.button_text = "Save calibration"
        calibration_timer.start()
        _update_status("Move both sticks and press both triggers")
        return

    _stop_calibration_session()
    var response = backend.call_action("save_calibration", {"capture": calibration_capture})
    calibration_button.button_text = "Start controller calibration"
    _update_status("Calibration saved" if response.get("ok", false) else backend.last_error)


func _stop_calibration_session() -> void:
    if calibration_timer:
        calibration_timer.stop()
    if not calibration_recording:
        return
    backend.call_action("end_calibration_session", {"token": "armada-ogui-quickbar"})
    calibration_recording = false


func _capture_calibration_sample() -> void:
    if not calibration_recording:
        return
    var response = backend.call_action("get_controller_state")
    if not response.get("ok", false):
        _update_status(backend.last_error)
        return
    var controls: Dictionary = response.get("result", {}).get("controls", {})
    _update_calibration_sliders(controls)
    for name in ["left_x", "left_y", "right_x", "right_y", "left_trigger", "right_trigger"]:
        var control: Dictionary = controls.get(name, {})
        if not control.has("value"):
            continue
        var value := float(control["value"])
        if not calibration_capture.has(name):
            calibration_capture[name] = {"center": value, "min": value, "max": value, "range": 0}
        var capture: Dictionary = calibration_capture[name]
        capture["min"] = minf(float(capture["min"]), value)
        capture["max"] = maxf(float(capture["max"]), value)
        capture["range"] = float(capture["max"]) - float(capture["min"])


func _update_calibration_sliders(controls: Dictionary) -> void:
    for name in ["left_x", "left_y", "right_x", "right_y"]:
        var control: Dictionary = controls.get(name, {})
        if not calibration_sliders.has(name) or not control.has("value"):
            continue
        var minimum := float(control.get("min", -32768))
        var maximum := float(control.get("max", 32767))
        var value := float(control.get("value", 0))
        var side := absf(minimum) if value < 0 else maximum
        calibration_sliders[name].value = clampf(value / side if side else 0.0, -1.0, 1.0)
    for name in ["left_trigger", "right_trigger"]:
        var control: Dictionary = controls.get(name, {})
        if not calibration_sliders.has(name) or not control.has("value"):
            continue
        var minimum := float(control.get("min", 0))
        var maximum := float(control.get("max", 1))
        var value := float(control.get("value", 0))
        calibration_sliders[name].value = clampf((value - minimum) / (maximum - minimum) * 100.0 if maximum != minimum else 0.0, 0.0, 100.0)


func _refresh_device_state() -> void:
    if not _load_config():
        _update_status(backend.last_error)
        return
    _rebuild_sections()
    _update_status("Device state refreshed")


func _rebuild_sections() -> void:
    if not content_root:
        return
    for child in content_root.get_children():
        if child == status_label or child is FocusGroup:
            continue
        child.free()
    cpu_slider = null
    gpu_min_slider = null
    gpu_slider = null
    fan_curve_dropdown = null
    governor_dropdown = null
    underclock_dropdown = null
    curve_editor_dropdown = null
    curve_point_dropdown = null
    curve_temp_slider = null
    curve_pwm_slider = null
    fan_stop_toggle = null
    fan_stop_temp_slider = null
    fan_fix_pwm_button = null
    fan_reset_curve_button = null
    curve_name_input = null
    curve_delete_dropdown = null
    fans_parent = null
    games_controls = null
    game_target_dropdown = null
    environment_dropdown = null
    environment_name_input = null
    environment_value_input = null
    compat_target_dropdown = null
    compat_appid_input = null
    compat_controls = null
    compat_launch_input = null
    rgb_brightness_slider = null
    rgb_color_slider = null
    calibration_button = null
    calibration_sliders.clear()
    _section(content_root, "Power", _build_power)
    _section(content_root, "Fans", _build_fans)
    _section(content_root, "Games", _build_games)
    _section(content_root, "Compatibility", _build_compatibility)
    _section(content_root, "System", _build_system)
    _section(content_root, "Actions", _build_actions)
    for child in get_children():
        if child is FocusGroup:
            child.current_focus = _first_focusable(content_root)
            child.call_deferred("grab_focus")
            break


func _reset_calibration() -> void:
    if not reset_calibration_pending:
        reset_calibration_pending = true
        _update_status("Press A again to reset calibration")
        return
    reset_calibration_pending = false
    _stop_calibration_session()
    _call("reset_calibration")


func _restart_game_mode() -> void:
    if not restart_game_mode_pending:
        restart_game_mode_pending = true
        _update_status("Press A again to restart Game Mode")
        return
    restart_game_mode_pending = false
    _call("restart_game_mode")


func _build_games(parent: Container) -> void:
    var target_options: Array = [{"data": "", "label": "Default"}]
    for game in installed_games:
        if game is Dictionary and not String(game.get("appid", "")).is_empty():
            target_options.append({"data": String(game["appid"]), "label": String(game.get("name", "App " + String(game["appid"])))})
    target_options.sort_custom(func(a, b):
        if String(a["data"]).is_empty():
            return true
        if String(b["data"]).is_empty():
            return false
        return String(a["label"]).to_lower() < String(b["label"]).to_lower()
    )
    game_target_dropdown = _dropdown(parent, "Target", target_options, selected_game_appid, _select_game_target)
    games_controls = VBoxContainer.new()
    games_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(games_controls)
    _build_games_controls(games_controls)


func _build_games_controls(parent: Container) -> void:
    var tweaks: Dictionary = config.get("tweaks", {})
    var target: Dictionary = _effective_tweaks(tweaks)
    var fex_options: Array = []
    for name in config.get("fexProfiles", {}):
        fex_options.append({"data": name, "label": String(config["fexProfiles"][name].get("label", name))})
    fex_options.append({"data": "custom", "label": "Custom"})
    if not fex_options.is_empty():
        _dropdown(parent, "FEX preset", fex_options, String(target.get("fexProfile", "default")), _save_fex_profile)
    var fex_config: Dictionary = target.get("fexConfig", {})
    var fex_knobs := {
        "TSOEnabled": "FEX TSO enabled",
        "X87ReducedPrecision": "FEX X87 reduced precision",
        "Multiblock": "FEX multiblock",
        "VectorTSOEnabled": "FEX vector TSO",
        "MemcpySetTSOEnabled": "FEX memcpy TSO",
        "HalfBarrierTSOEnabled": "FEX half barrier TSO",
    }
    for key in fex_knobs:
        _toggle(parent, fex_knobs[key], String(fex_config.get(key, "1")) == "1", _fex_callback(key))
    var thunks: Dictionary = target.get("thunks", {})
    for key in ["Vulkan", "GL", "asound", "drm", "WaylandClient"]:
        _toggle(parent, "Host " + key, thunks.get(key, true) != false, _thunk_callback(key))
    var perf: Dictionary = config.get("perf", {})
    var core_options := _core_options(perf.get("corePresets", []))
    var core_value := String(target.get("cores", "default"))
    var core_is_custom := core_value != "default" and not _option_has_data(core_options, core_value)
    if core_is_custom:
        custom_cores_text = core_value
    _dropdown(parent, "Game CPU cores", core_options, "custom" if core_is_custom else core_value, _select_core_setting.bind("cores"))
    if core_is_custom:
        _text_input(parent, "Custom CPU cores", custom_cores_text, "e.g. 7,3-6", _save_custom_cores.bind("cores"))
    _toggle(parent, "Wine CPU topology", target.get("wineTopology", true) != false, func(value): _save_selected_value("wineTopology", null if value else false))
    _slider(parent, "Game priority", float(target.get("nice", 0)), -20, 19, func(value): _save_selected_value("nice", roundi(value)))
    var gamescope_core_value := String(target.get("gamescopeCores", "default"))
    var gamescope_custom := gamescope_core_value != "default" and not _option_has_data(core_options, gamescope_core_value)
    if gamescope_custom:
        custom_gamescope_cores_text = gamescope_core_value
    _dropdown(parent, "Gamescope CPU cores", core_options, "custom" if gamescope_custom else gamescope_core_value, _select_core_setting.bind("gamescopeCores"))
    if gamescope_custom:
        _text_input(parent, "Custom Gamescope cores", custom_gamescope_cores_text, "e.g. 7,3-6", _save_custom_cores.bind("gamescopeCores"))
    _slider(parent, "Gamescope priority", float(target.get("gamescopeNice", 0)), -20, 19, func(value): _save_selected_value("gamescopeNice", roundi(value)))
    _toggle(parent, "Gamescope realtime", bool(target.get("gamescopeRr", false)), func(value): _save_selected_tweak("gamescopeRr", value))
    if selected_game_appid.is_empty():
        _toggle(parent, "Vulkan realtime queue", bool(target.get("gamescopeVulkanRealtime", false)), func(value): _save_tweak("gamescopeVulkanRealtime", value))
    var scheduler_options: Array = [{"data": "default", "label": "Default"}]
    for scheduler in perf.get("schedulers", []):
        scheduler_options.append({"data": scheduler, "label": String(scheduler).to_upper()})
    _dropdown(parent, "CPU scheduler", scheduler_options, String(target.get("scheduler", "default")), _select_scheduler)
    _build_environment(parent)


func _select_game_target(appid: String) -> void:
    selected_game_appid = appid
    _rebuild_games_controls()


func _rebuild_games_controls() -> void:
    if not games_controls:
        return
    for child in games_controls.get_children():
        child.free()
    _build_games_controls(games_controls)
    if game_target_dropdown:
        var focus_parent := games_controls.get_parent()
        for child in focus_parent.get_children():
            if child is FocusGroup:
                child.current_focus = game_target_dropdown
                break
        game_target_dropdown.grab_focus()


func _effective_tweaks(tweaks: Dictionary) -> Dictionary:
    var merged: Dictionary = tweaks.get("global", {}).duplicate(true)
    if selected_game_appid.is_empty():
        return merged
    var games: Dictionary = tweaks.get("games", {})
    var own: Dictionary = games.get(selected_game_appid, {})
    for key in own:
        merged[key] = own[key]
    return merged


func _selected_tweak_map(tweaks: Dictionary) -> Dictionary:
    if selected_game_appid.is_empty():
        return tweaks.get("global", {})
    var games: Dictionary = tweaks.get("games", {})
    return games.get(selected_game_appid, {"name": _selected_game_name()})


func _selected_game_name() -> String:
    for game in installed_games:
        if game is Dictionary and String(game.get("appid", "")) == selected_game_appid:
            return String(game.get("name", "App " + selected_game_appid))
    return "App " + selected_game_appid


func _core_options(presets: Array) -> Array:
    var options: Array = [{"data": "default", "label": "Default"}]
    for preset in presets:
        if preset is Dictionary:
            options.append({"data": String(preset.get("data", "")), "label": String(preset.get("label", preset.get("data", "")))})
    options.append({"data": "custom", "label": "Custom"})
    return options


func _option_has_data(options: Array, value: String) -> bool:
    for option in options:
        if option is Dictionary and String(option.get("data", "")) == value:
            return true
    return false


func _text_input(parent: Container, title: String, value: String, placeholder: String, callback: Callable) -> ComponentTextInput:
    var input := TEXT_INPUT.instantiate() as ComponentTextInput
    input.title = title
    input.description = ""
    input.text = value
    input.placeholder_text = placeholder
    parent.add_child(input)
    var description_label := input.get_node_or_null("DescriptionLabel") as Label
    if description_label:
        description_label.visible = false
    input.ready.connect(func():
        var ready_description := input.get_node_or_null("DescriptionLabel") as Label
        if ready_description:
            ready_description.visible = false
        call_deferred("_hide_component_description", input)
    )
    input.tree_entered.connect(func(): call_deferred("_hide_component_description", input))
    call_deferred("_hide_component_description", input)
    input.text_submitted.connect(callback)
    return input


func _hide_component_description(input: Control) -> void:
    if not is_instance_valid(input):
        return
    if input.is_inside_tree():
        await get_tree().process_frame
    if not is_instance_valid(input):
        return
    var description := input.get_node_or_null("DescriptionLabel") as Label
    if description:
        description.text = ""
        description.visible = false


func _select_core_setting(value: String, key: String) -> void:
    if value == "custom":
        var current := String(_effective_tweaks(config.get("tweaks", {})).get(key, ""))
        if key == "cores":
            custom_cores_text = current if current != "default" else ""
        else:
            custom_gamescope_cores_text = current if current != "default" else ""
        _rebuild_games_controls()
        return
    _save_selected_value(key, null if value == "default" else value)


func _save_custom_cores(value: String, key: String) -> void:
    var text := value.strip_edges()
    if not _valid_cpulist(text):
        _update_status("Invalid CPU list")
        return
    if key == "cores":
        custom_cores_text = text
    else:
        custom_gamescope_cores_text = text
    _save_selected_value(key, text)


func _valid_cpulist(text: String) -> bool:
    if text.is_empty():
        return false
    var seen: Dictionary = {}
    var cpu_count := int(config.get("perf", {}).get("cpuCount", 0))
    for part in text.split(","):
        var value := part.strip_edges()
        var range_parts := value.split("-")
        if range_parts.size() > 2 or value.is_empty():
            return false
        if not range_parts[0].is_valid_int() or (range_parts.size() == 2 and not range_parts[1].is_valid_int()):
            return false
        var low := int(range_parts[0])
        var high := low if range_parts.size() == 1 else int(range_parts[1])
        if high < low:
            return false
        for cpu in range(low, high + 1):
            if cpu_count > 0 and cpu >= cpu_count:
                return false
            if seen.has(cpu):
                return false
            seen[cpu] = true
    return not seen.is_empty()


func _select_scheduler(value: String) -> void:
    _save_selected_value("scheduler", null if value == "default" else value)


func _build_environment(parent: Container) -> void:
    var options := _environment_options()
    if selected_environment_key.is_empty() or not _option_has_data(options, selected_environment_key):
        selected_environment_key = String(options[0]["data"]) if not options.is_empty() else ""
    environment_dropdown = _dropdown(parent, "Environment variable", options, selected_environment_key, _select_environment_variable)
    environment_name_input = _text_input(parent, "Name", selected_environment_key, "Variable", _environment_input_submitted)
    environment_value_input = _text_input(parent, "Value", _environment_value(selected_environment_key), "Value", _environment_input_submitted)
    environment_value_input.ready.connect(_sync_environment_inputs)
    _action(parent, "Save variable", _save_environment_variable)
    _action(parent, "New variable", _new_environment_variable)
    _action(parent, "Delete variable", _delete_environment_variable)
    _action(parent, "Reset game settings" if not selected_game_appid.is_empty() else "Reset all game settings", _reset_game_tweaks)


func _environment_options() -> Array:
    var keys: Dictionary = {}
    var tweaks: Dictionary = config.get("tweaks", {})
    var global: Dictionary = tweaks.get("global", {}).get("env", {})
    for key in global:
        keys[String(key)] = true
    if not selected_game_appid.is_empty():
        var games: Dictionary = tweaks.get("games", {})
        var own: Dictionary = games.get(selected_game_appid, {}).get("env", {})
        for key in own:
            keys[String(key)] = true
    var names: Array = keys.keys()
    names.sort()
    var options: Array = []
    for name in names:
        options.append({"data": name, "label": name})
    return options


func _environment_value(key: String) -> String:
    if key.is_empty():
        return ""
    var tweaks: Dictionary = config.get("tweaks", {})
    var global: Dictionary = tweaks.get("global", {}).get("env", {})
    if not selected_game_appid.is_empty():
        var games: Dictionary = tweaks.get("games", {})
        var own: Dictionary = games.get(selected_game_appid, {}).get("env", {})
        if own.has(key):
            return "" if own[key] == null else String(own[key])
    return String(global.get(key, ""))


func _select_environment_variable(key: String) -> void:
    selected_environment_key = key
    _sync_environment_inputs()


func _sync_environment_inputs() -> void:
    if environment_name_input:
        environment_name_input.text = selected_environment_key
    if environment_value_input:
        environment_value_input.text = _environment_value(selected_environment_key)


func _environment_input_submitted(_value: String) -> void:
    _update_status("Press Save variable")


func _save_environment_variable() -> void:
    var key := environment_name_input.text.strip_edges()
    if key.is_empty() or key.contains("=") or key.contains("\u0000"):
        _update_status("Invalid variable name")
        return
    var tweaks: Dictionary = config.get("tweaks", {}).duplicate(true)
    var target: Dictionary = _selected_tweak_map(tweaks).duplicate(true)
    var env: Dictionary = target.get("env", {}).duplicate(true)
    if selected_game_appid.is_empty():
        if selected_environment_key != key:
            env.erase(selected_environment_key)
    else:
        if selected_environment_key != key:
            env.erase(selected_environment_key)
    env[key] = environment_value_input.text
    target["env"] = env
    _set_selected_tweaks(tweaks, target)
    selected_environment_key = key
    _save_tweaks(tweaks)
    _refresh_environment_dropdown()
    _update_status("Variable staged")


func _new_environment_variable() -> void:
    selected_environment_key = ""
    _sync_environment_inputs()
    if environment_name_input:
        environment_name_input.grab_focus()


func _delete_environment_variable() -> void:
    var key := selected_environment_key
    if key.is_empty():
        return
    var tweaks: Dictionary = config.get("tweaks", {}).duplicate(true)
    var target: Dictionary = _selected_tweak_map(tweaks).duplicate(true)
    var env: Dictionary = target.get("env", {}).duplicate(true)
    if selected_game_appid.is_empty():
        env.erase(key)
    else:
        var global_env: Dictionary = tweaks.get("global", {}).get("env", {})
        if not env.has(key) and global_env.has(key):
            env[key] = null
        else:
            env.erase(key)
    if env.is_empty():
        target.erase("env")
    else:
        target["env"] = env
    _set_selected_tweaks(tweaks, target)
    selected_environment_key = ""
    _save_tweaks(tweaks)
    _refresh_environment_dropdown()
    _update_status("Variable deleted")


func _refresh_environment_dropdown() -> void:
    if not environment_dropdown:
        return
    var options := _environment_options()
    environment_dropdown.clear()
    var values: Array = []
    for option in options:
        environment_dropdown.add_item(String(option["label"]))
        values.append(String(option["data"]))
    environment_dropdown.set_meta("armada_values", values)
    if selected_environment_key.is_empty() or not values.has(selected_environment_key):
        selected_environment_key = String(values[0]) if not values.is_empty() else ""
    if not values.is_empty():
        environment_dropdown.select(_dropdown_index(environment_dropdown, selected_environment_key))
    _sync_environment_inputs()


func _reset_game_tweaks() -> void:
    if not reset_game_pending:
        reset_game_pending = true
        _update_status("Press A again to reset settings")
        return
    var tweaks: Dictionary = config.get("tweaks", {}).duplicate(true)
    if selected_game_appid.is_empty():
        tweaks["games"] = {}
    else:
        var games: Dictionary = tweaks.get("games", {})
        games.erase(selected_game_appid)
        tweaks["games"] = games
    reset_game_pending = false
    _save_tweaks(tweaks)
    _rebuild_games_controls()
    _update_status("Settings reset")


func _fex_callback(key: String) -> Callable:
    return func(value): _save_fex_knob(key, value)


func _thunk_callback(key: String) -> Callable:
    return func(value): _save_thunk(key, value)


func _build_compatibility(parent: Container) -> void:
    var target_options: Array = [{"data": "", "label": "Default"}]
    var seen: Dictionary = {}
    for game in installed_games:
        if not game is Dictionary:
            continue
        var appid := String(game.get("appid", ""))
        if not appid.is_valid_int() or seen.has(appid):
            continue
        seen[appid] = true
        target_options.append({"data": appid, "label": String(game.get("name", "App " + appid))})
    if current_appid.is_valid_int() and not seen.has(current_appid):
        target_options.append({"data": current_appid, "label": "App " + current_appid})
    target_options.append({"data": "__manual", "label": "Enter AppID manually"})
    target_options.sort_custom(func(a, b):
        if String(a["data"]).is_empty():
            return true
        if String(b["data"]).is_empty():
            return false
        if String(a["data"]) == "__manual":
            return false
        if String(b["data"]) == "__manual":
            return true
        return String(a["label"]).to_lower() < String(b["label"]).to_lower()
    )
    compat_target_dropdown = _dropdown(parent, "Game", target_options, compat_appid, _select_compat_target)
    compat_appid_input = _text_input(parent, "AppID", compat_appid, "Running or installed AppID", _compat_input_submitted)
    _action(parent, "Load AppID", _load_compat_appid)
    compat_controls = VBoxContainer.new()
    compat_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(compat_controls)
    _build_compatibility_controls(compat_controls)


func _build_compatibility_controls(parent: Container) -> void:
    _load_compat_game_state()
    if compat_tools.is_empty():
        _action(parent, "Refresh Steam compatibility", _refresh_compatibility)
    else:
        _dropdown(parent, "Default Proton", _compat_options(compat_tools), compat_tool, _save_global_tool)
    _toggle(parent, "Apply to new games", _global_tweak("autoApplyCompat"), func(value): _save_tweak("autoApplyCompat", value))
    _dropdown(parent, "Default resolution", ["Default", "Native", "1280x720", "960x540"], global_resolution, _save_global_resolution)
    if compat_appid.is_valid_int() and not compat_appid.is_empty():
        var tools_response := _call_steam("get_app_compat_tools", {"appid": compat_appid})
        var app_tools: Array = tools_response.get("result", {}).get("tools", []) if tools_response.get("ok", false) else []
        var app_options: Array = [
            {"data": "__default", "label": "Use Default"},
            {"data": "", "label": "Follow Steam"},
        ]
        var app_values: Dictionary = {"__default": true, "": true}
        for option in _compat_options(app_tools) + _compat_options(compat_tools):
            var value := String(option["data"])
            if app_values.has(value):
                continue
            app_values[value] = true
            app_options.append(option)
        if not compat_game_tool.is_empty() and not app_values.has(compat_game_tool):
            app_options.append({"data": compat_game_tool, "label": compat_game_tool})
        _dropdown(parent, "Compatibility tool", app_options, compat_game_tool, _save_compat_game_tool)
        _dropdown(parent, "Game resolution", ["Default", "Native", "1280x720", "960x540"], compat_game_resolution, _save_compat_game_resolution)
        compat_launch_input = _text_input(parent, "Launch options", compat_launch_options, "Steam launch options", _compat_input_submitted)
        _action(parent, "Save launch options", _save_compat_launch_options)
        _action(parent, "Reset game compatibility", _reset_compat_game)
    _action(parent, "Sweep Steam compatibility", func(): _sweep_compatibility())
    _action(parent, "Reset all game compatibility", _reset_all_compatibility)


func _select_compat_target(value: String) -> void:
    if value == "__manual":
        if compat_appid_input:
            compat_appid_input.grab_focus()
        return
    compat_appid = value
    _rebuild_compatibility_controls()


func _rebuild_compatibility_controls() -> void:
    if compat_appid_input:
        compat_appid_input.text = compat_appid
    if not compat_controls:
        return
    for child in compat_controls.get_children():
        child.free()
    compat_game_tool = ""
    compat_game_resolution = "Default"
    compat_launch_options = ""
    _build_compatibility_controls(compat_controls)
    if compat_target_dropdown:
        compat_target_dropdown.grab_focus()


func _compat_input_submitted(_value: String) -> void:
    _update_status("Press the matching save action")


func _load_compat_appid() -> void:
    var value := compat_appid_input.text.strip_edges()
    if not value.is_valid_int() or value.is_empty():
        _update_status("Invalid AppID")
        return
    compat_appid = value
    _rebuild_compatibility_controls()


func _load_compat_game_state() -> void:
    if not compat_appid.is_valid_int() or compat_appid.is_empty():
        return
    var state := _call_steam("get_compat_state", {"appid": compat_appid})
    if state.get("ok", false):
        compat_game_tool = String(state.get("result", {}).get("tool", ""))
    var launch := _call_steam("get_launch_options", {"appid": compat_appid})
    if launch.get("ok", false):
        compat_launch_options = String(launch.get("result", {}).get("options", ""))
    var resolution := _call_steam("get_resolution", {"appid": compat_appid})
    if resolution.get("ok", false):
        compat_game_resolution = String(resolution.get("result", {}).get("value", "Default"))


func _compat_options(tools: Array) -> Array:
    var options: Array = []
    var seen: Dictionary = {}
    for tool in tools:
        var value := ""
        var label := ""
        if tool is Dictionary:
            value = String(tool.get("data", tool.get("id", tool.get("strToolName", ""))))
            label = String(tool.get("label", tool.get("strDisplayName", value)))
        else:
            value = String(tool)
            label = value
        if value.is_empty() or seen.has(value):
            continue
        seen[value] = true
        options.append({"data": value, "label": label})
    return options


func _has_compat_tool(value: String) -> bool:
    for option in _compat_options(compat_tools):
        if String(option["data"]) == value:
            return true
    return false


func _save_global_resolution(value: String) -> void:
    var response := _call_steam("set_global_resolution", {"value": value})
    if response.get("ok", false):
        global_resolution = value
        _update_status("Saved")
    else:
        _update_status(backend.last_error)


func _save_compat_game_tool(value: String) -> void:
    var tool := compat_tool if value == "__default" else value
    var response := _call_steam("set_compat_tool", {"appid": compat_appid, "tool": tool})
    if response.get("ok", false):
        compat_game_tool = value
        _update_status("Saved")
    else:
        _update_status(backend.last_error)


func _save_compat_game_resolution(value: String) -> void:
    var response := _call_steam("set_resolution", {"appid": compat_appid, "value": value})
    if response.get("ok", false):
        compat_game_resolution = value
        _update_status("Saved")
    else:
        _update_status(backend.last_error)


func _save_compat_launch_options() -> void:
    var response := _call_steam("set_launch_options", {"appid": compat_appid, "options": compat_launch_input.text})
    if response.get("ok", false):
        compat_launch_options = compat_launch_input.text
    _update_status("Saved" if response.get("ok", false) else backend.last_error)


func _reset_compat_game() -> void:
    if not compat_reset_pending:
        compat_reset_pending = true
        _update_status("Press A again to reset game compatibility")
        return
    compat_reset_pending = false
    var response := _call_steam("reset_game", {"appid": compat_appid, "tool": compat_tool})
    _update_status("Reset" if response.get("ok", false) else backend.last_error)
    if response.get("ok", false):
        _rebuild_compatibility_controls()


func _reset_all_compatibility() -> void:
    if not compat_reset_all_pending:
        compat_reset_all_pending = true
        _update_status("Press A again to reset all game compatibility")
        return
    compat_reset_all_pending = false
    var failed := 0
    var count := 0
    for game in installed_games:
        if game is Dictionary and not bool(game.get("nonSteam", false)) and String(game.get("appid", "")).is_valid_int():
            count += 1
            var response := _call_steam("reset_game", {"appid": String(game["appid"]), "tool": compat_tool})
            if not response.get("ok", false):
                failed += 1
    _call("save_compat_applied", {"appids": []})
    _update_status("Reset %d games" % count if failed == 0 else "Reset completed with errors")


func _refresh_compatibility() -> void:
    var response = backend.call_steam("get_global_compat_tools")
    if response.get("ok", false):
        compat_tools = response.get("result", {}).get("tools", [])
        _rebuild_compatibility_controls()
        _update_status("Steam compatibility refreshed")
    else:
        _update_status(backend.last_error)


func _save_global_tool(tool: String) -> void:
    var old_tool := compat_tool
    compat_tool = tool
    var tweaks: Dictionary = config.get("tweaks", {}).duplicate(true)
    var global: Dictionary = tweaks.get("global", {})
    global["windowsCompatTool"] = tool
    tweaks["global"] = global
    _save_tweaks(tweaks)
    if old_tool != tool:
        var games: Array = []
        for game in installed_games:
            if game is Dictionary and not bool(game.get("nonSteam", false)) and String(game.get("appid", "")).is_valid_int():
                games.append({"appid": String(game["appid"])})
        var migration: Dictionary = {"games": games, "old_tool": old_tool, "new_tool": tool}
        if not _has_compat_tool(old_tool):
            var pinned = _call_result("get_compat_mapped_appids", {"tool": old_tool})
            if pinned is Array:
                migration["pinned"] = pinned
        var migrated := _call_steam("migrate_compat", migration)
        if not migrated.get("ok", false):
            _update_status(backend.last_error)
    _sweep_compatibility()


func _sweep_compatibility() -> void:
    var games: Array = []
    for game in installed_games:
        if game is Dictionary and not bool(game.get("nonSteam", false)) and String(game.get("appid", "")).is_valid_int():
            games.append({"appid": String(game["appid"])})
    var response = _call_steam("sweep_compat", {"games": games, "tool": compat_tool, "auto_apply": true})
    _update_status("Compatibility sweep complete" if response.get("ok", false) else backend.last_error)


func _call_steam(action: String, fields: Dictionary = {}) -> Dictionary:
    return backend.call_steam(action, fields)


func _action(parent: Container, text: String, callback: Callable) -> CardButtonSetting:
    var setting := CARD_BUTTON_SETTING.instantiate() as CardButtonSetting
    setting.text = text
    setting.description = ""
    setting.button_text = "A"
    parent.add_child(setting)
    setting.pressed.connect(callback)
    return setting


func _dropdown(parent: Container, title: String, options: Array, selected_value: String, callback: Callable) -> Dropdown:
    var dropdown := DROPDOWN.instantiate() as Dropdown
    dropdown.title = title
    dropdown.description = ""
    parent.add_child(dropdown)
    dropdown.ready.connect(func():
        var selected_index := 0
        var values: Array = []
        dropdown.clear()
        for index in options.size():
            var option = options[index]
            var value := String(option.get("data", option.get("id", option))) if option is Dictionary else String(option)
            var label := String(option.get("label", option.get("strDisplayName", value))) if option is Dictionary else value
            values.append(value)
            dropdown.add_item(label)
            if value == selected_value:
                selected_index = index
        dropdown.set_meta("armada_values", values)
        if not values.is_empty():
            dropdown.select(selected_index)
        dropdown.item_selected.connect(func(index: int):
            var current_values: Array = dropdown.get_meta("armada_values", [])
            if index >= 0 and index < current_values.size():
                callback.call(String(current_values[index]))
        )
    )
    return dropdown


func _dropdown_index(dropdown: Dropdown, value: String) -> int:
    var values: Array = dropdown.get_meta("armada_values", [])
    if values.is_empty():
        return 0
    for index in values.size():
        if String(values[index]) == value:
            return index
    return 0


func _toggle(parent: Container, title: String, value: bool, callback: Callable) -> Toggle:
    var toggle := TOGGLE.instantiate() as Toggle
    toggle.text = title
    toggle.description = ""
    toggle.button_pressed = value
    parent.add_child(toggle)
    toggle.toggled.connect(callback)
    return toggle


func _slider(parent: Container, title: String, value: float, minimum: float, maximum: float, callback: Callable) -> ValueSlider:
    var slider := SLIDER.instantiate() as ValueSlider
    slider.text = title
    slider.min_value = minimum
    slider.max_value = maximum
    slider.value = value
    parent.add_child(slider)
    slider.value_changed.connect(callback)
    return slider


func _reset_profile() -> void:
    if not reset_profile_pending:
        reset_profile_pending = true
        _update_status("Press A again to reset profile")
        return
    var defaults: Dictionary = config.get("powerDefaults", {}).get("profiles", {}).get(selected_profile, {})
    if defaults.is_empty():
        reset_profile_pending = false
        _update_status("Profile defaults unavailable")
        return
    var power: Dictionary = config.get("power", {}).duplicate(true)
    var profiles: Dictionary = power.get("profiles", {})
    profiles[selected_profile] = defaults.duplicate(true)
    power["profiles"] = profiles
    reset_profile_pending = false
    _save_power(power)
    _sync_profile_controls(profiles[selected_profile])
    _update_status("Profile reset")


func _sync_profile_controls(profile: Dictionary) -> void:
    if cpu_slider:
        cpu_slider.value = _percent(profile.get("cpu_max", "1.0"))
    if gpu_slider:
        gpu_slider.value = _percent(profile.get("gpu_max", "1.0"))
    if gpu_min_slider:
        gpu_min_slider.value = _percent(profile.get("gpu_min", "0.0"))
    if fan_curve_dropdown:
        fan_curve_dropdown.select(_dropdown_index(fan_curve_dropdown, String(profile.get("fan_curve", ""))))
    if governor_dropdown:
        governor_dropdown.select(_dropdown_index(governor_dropdown, String(profile.get("cpu_governor", ""))))
    if underclock_dropdown:
        underclock_dropdown.select(_dropdown_index(underclock_dropdown, String(profile.get("cpu_underclock", "none"))))


func _select_profile(name: String) -> void:
    selected_profile = name
    var profile: Dictionary = config.get("power", {}).get("profiles", {}).get(name, {})
    _sync_profile_controls(profile)


func _save_profile_limit(key: String, value: float) -> void:
    var power: Dictionary = config.get("power", {}).duplicate(true)
    var profiles: Dictionary = power.get("profiles", {})
    var profile: Dictionary = profiles.get(selected_profile, {})
    var normalized := clampf(value, 0.0, 1.0)
    profile[key] = "%.2f" % normalized
    if key == "gpu_min" and normalized > float(profile.get("gpu_max", 0.0)):
        profile["gpu_max"] = "%.2f" % normalized
    elif key == "gpu_max" and normalized < float(profile.get("gpu_min", 0.0)):
        profile["gpu_min"] = "%.2f" % normalized
    profiles[selected_profile] = profile
    power["profiles"] = profiles
    _save_power(power)


func _save_profile_value(key: String, value: String) -> void:
    var power: Dictionary = config.get("power", {}).duplicate(true)
    var profiles: Dictionary = power.get("profiles", {})
    var profile: Dictionary = profiles.get(selected_profile, {})
    profile[key] = value
    profiles[selected_profile] = profile
    power["profiles"] = profiles
    _save_power(power)


func _save_power(power: Dictionary) -> void:
    var response = backend.call_action("save_power_config", {"data": power})
    if response.get("ok", false):
        config["power"] = power
        _update_status("Power saved")
    else:
        _update_status(backend.last_error)


func _refresh_fans() -> void:
    var response = backend.call_action("get_fans_state")
    if response.get("ok", false):
        fan_state = response.get("result", {})
        fan_original_state = fan_state.duplicate(true)
        _rebuild_fan_controls()
        _update_status("Fan state refreshed")
    else:
        _update_status(backend.last_error)


func _rebuild_fan_controls() -> void:
    if not fans_parent:
        return
    for child in fans_parent.get_children():
        if child is FocusGroup:
            continue
        child.free()
    _build_fans(fans_parent)
    for child in fans_parent.get_children():
        if child is FocusGroup:
            child.current_focus = _first_focusable(fans_parent)
            break


func _stage_fan_setting(key: String, value: float) -> void:
    var settings: Dictionary = fan_state.get("fanSettings", {}).duplicate(true)
    settings[key] = value
    fan_state["fanSettings"] = settings
    _update_status("Fan setting staged")


func _save_fans() -> void:
    var response = backend.call_action("save_fan_curves", {
        "fanCurves": fan_state.get("fanCurves", {}),
        "fanSettings": fan_state.get("fanSettings", {}),
    })
    if response.get("ok", false):
        fan_state = response.get("result", fan_state)
        fan_original_state = fan_state.duplicate(true)
        _update_status("Fan settings saved")
    else:
        _update_status(backend.last_error)


func _global_tweak(key: String) -> bool:
    return bool(config.get("tweaks", {}).get("global", {}).get(key, false))


func _save_tweak(key: String, value: bool) -> void:
    var tweaks: Dictionary = config.get("tweaks", {}).duplicate(true)
    var global: Dictionary = tweaks.get("global", {})
    if value:
        global[key] = true
    else:
        global.erase(key)
    tweaks["global"] = global
    var response = backend.call_action("save_tweaks", {"data": tweaks})
    if response.get("ok", false):
        config["tweaks"] = tweaks
        _update_status("Saved")
    else:
        _update_status(backend.last_error)


func _save_fex_profile(name: String) -> void:
    var tweaks: Dictionary = config.get("tweaks", {}).duplicate(true)
    var target: Dictionary = _selected_tweak_map(tweaks).duplicate(true)
    target["fexProfile"] = name
    if name != "custom":
        var profile: Dictionary = config.get("fexProfiles", {}).get(name, {})
        target["fexConfig"] = profile.get("config", {})
    _set_selected_tweaks(tweaks, target)
    _save_tweaks(tweaks)


func _save_fex_knob(key: String, value: bool) -> void:
    var tweaks: Dictionary = config.get("tweaks", {}).duplicate(true)
    var target: Dictionary = _selected_tweak_map(tweaks).duplicate(true)
    var fex_config: Dictionary = _effective_tweaks(tweaks).get("fexConfig", {}).duplicate(true)
    fex_config[key] = "1" if value else "0"
    target["fexProfile"] = "custom"
    target["fexConfig"] = fex_config
    _set_selected_tweaks(tweaks, target)
    _save_tweaks(tweaks)


func _save_thunk(key: String, value: bool) -> void:
    var tweaks: Dictionary = config.get("tweaks", {}).duplicate(true)
    var target: Dictionary = _selected_tweak_map(tweaks).duplicate(true)
    var thunks: Dictionary = _effective_tweaks(tweaks).get("thunks", {}).duplicate(true)
    thunks[key] = value
    target["thunks"] = thunks
    _set_selected_tweaks(tweaks, target)
    _save_tweaks(tweaks)


func _save_selected_tweak(key: String, value: bool) -> void:
    var tweaks: Dictionary = config.get("tweaks", {}).duplicate(true)
    var target: Dictionary = _selected_tweak_map(tweaks).duplicate(true)
    if value:
        target[key] = true
    else:
        target.erase(key)
    _set_selected_tweaks(tweaks, target)
    _save_tweaks(tweaks)


func _save_selected_value(key: String, value: Variant) -> void:
    var tweaks: Dictionary = config.get("tweaks", {}).duplicate(true)
    var target: Dictionary = _selected_tweak_map(tweaks).duplicate(true)
    if value == null:
        target.erase(key)
    else:
        target[key] = value
    _set_selected_tweaks(tweaks, target)
    _save_tweaks(tweaks)


func _set_selected_tweaks(tweaks: Dictionary, target: Dictionary) -> void:
    if selected_game_appid.is_empty():
        tweaks["global"] = target
        return
    var games: Dictionary = tweaks.get("games", {})
    games[selected_game_appid] = target
    tweaks["games"] = games


func _save_tweaks(tweaks: Dictionary) -> void:
    var response = backend.call_action("save_tweaks", {"data": tweaks})
    if response.get("ok", false):
        config["tweaks"] = tweaks
        _update_status("Saved")
    else:
        _update_status(backend.last_error)


func _set_rgb(enabled: bool, previous: Dictionary) -> void:
    var response = backend.call_action("set_rgb", {
        "enabled": enabled,
        "color": String(previous.get("color", "FFFFFF")),
        "brightness": int(previous.get("brightness", 100)),
    })
    if response.get("ok", false):
        previous["enabled"] = enabled
        _sync_rgb_controls(previous)
        _update_status("Saved")
    else:
        _update_status(backend.last_error)


func _set_rgb_brightness(value: float, previous: Dictionary) -> void:
    var response = backend.call_action("set_rgb", {
        "enabled": bool(previous.get("enabled", true)),
        "color": String(previous.get("color", "FFFFFF")),
        "brightness": int(value),
    })
    if response.get("ok", false):
        previous["brightness"] = int(value)
        _update_status("Saved")
    else:
        _update_status(backend.last_error)


func _set_rgb_color(value: float, previous: Dictionary) -> void:
    if _syncing_rgb_controls:
        return
    var color := _rgb_color(value)
    var response = backend.call_action("set_rgb", {
        "enabled": bool(previous.get("enabled", true)),
        "color": color,
        "brightness": int(previous.get("brightness", 100)),
    })
    if response.get("ok", false):
        previous["color"] = color
        _update_status("Saved")
    else:
        _update_status(backend.last_error)


func _sync_rgb_controls(rgb: Dictionary) -> void:
    var enabled := bool(rgb.get("enabled", false))
    _syncing_rgb_controls = true
    if rgb_brightness_slider:
        rgb_brightness_slider.editable = enabled
    if rgb_color_slider:
        rgb_color_slider.editable = enabled
        rgb_color_slider.value = _rgb_hue(String(rgb.get("color", "FFFFFF")))
    _syncing_rgb_controls = false


func _rgb_hue(value: String) -> float:
    var color := Color.from_string("#" + value.strip_edges().trim_prefix("#"), Color.WHITE)
    return roundi(color.h * 359.0)


func _rgb_color(value: float) -> String:
    return Color.from_hsv(clampf(value / 360.0, 0.0, 1.0), 1.0, 1.0).to_html(false).to_upper()


func _call(action: String, fields: Dictionary = {}) -> void:
    var response = backend.call_action(action, fields)
    _update_status("Saved" if response.get("ok", false) else backend.last_error)


func _call_result(action: String, fields: Dictionary = {}):
    var response = backend.call_action(action, fields)
    if response.get("ok", false):
        return response.get("result")
    return null


func _update_status(message: String = "") -> void:
    if not status_label:
        return
    var device := String(config.get("cpuDeviceClass", "device"))
    status_label.text = message if not message.is_empty() else "Armada · %s" % device


func _percent(value) -> float:
    var number := float(value)
    return clampf(number * 100.0, 0.0, 100.0)


func _first_focusable(node: Node) -> Control:
    for child in node.get_children():
        if child is Control and child.focus_mode != Control.FOCUS_NONE and child.visible:
            return child
        var nested := _first_focusable(child)
        if nested:
            return nested
    return null
