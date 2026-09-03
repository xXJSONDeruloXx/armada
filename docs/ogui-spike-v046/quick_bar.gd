extends Control

const CARD_BUTTON_SETTING := preload("res://core/ui/components/card_button_setting.tscn")
const DROPDOWN := preload("res://core/ui/components/dropdown.tscn")
const SLIDER := preload("res://core/ui/components/slider.tscn")
const TOGGLE := preload("res://core/ui/components/toggle.tscn")
const BODY_LABELS := preload("res://plugins/armada-control/ogui-body-label.tres")
const BACKEND_SCRIPT := preload("res://plugins/armada-control/backend.gd")

var backend
var config: Dictionary = {}
var selected_profile := "balanced"
var cpu_slider: ValueSlider
var gpu_min_slider: ValueSlider
var gpu_slider: ValueSlider
var status_label: Label
var fan_state: Dictionary = {}
var current_appid := ""
var compat_tools: Array = []
var compat_tool := ""
var installed_games: Array = []
var calibration_button: CardButtonSetting
var calibration_timer: Timer
var calibration_capture: Dictionary = {}
var calibration_recording := false


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


func _load_config() -> void:
    var response = backend.call_action("get_config")
    if response.get("ok", false):
        config = response.get("result", {})
    var games = backend.call_action("get_installed_games")
    if games.get("ok", false):
        installed_games = games.get("result", [])
    var fans = backend.call_action("get_fans_state")
    if fans.get("ok", false):
        fan_state = fans.get("result", {})
    var runtime = backend.call_action("get_runtime_game")
    if runtime.get("ok", false) and runtime.get("result") is Dictionary:
        current_appid = String(runtime["result"].get("appid", ""))
    var tools = backend.call_steam("get_global_compat_tools")
    if tools.get("ok", false):
        compat_tools = tools.get("result", {}).get("tools", [])
    compat_tool = String(config.get("tweaks", {}).get("global", {}).get("windowsCompatTool", ""))
    selected_profile = String(config.get("power", {}).get("general", {}).get("default_profile", "balanced"))


func _build() -> void:
    var content := VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_child(content)

    status_label = Label.new()
    status_label.label_settings = BODY_LABELS
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    content.add_child(status_label)

    _build_power(content)
    _build_fans(content)
    _build_games(content)
    _build_compatibility(content)
    _build_system(content)
    _build_actions(content)
    _update_status()

    var focus_group := FocusGroup.new()
    focus_group.current_focus = _first_focusable(content)
    add_child(focus_group)


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
    cpu_slider = _slider(parent, "CPU maximum", _percent(profile.get("cpu_max", "1.0")), 35, 100, func(value): _save_profile_limit("cpu_max", value / 100.0))
    gpu_min_slider = _slider(parent, "GPU minimum", _percent(profile.get("gpu_min", "0.0")), 0, 100, func(value): _save_profile_limit("gpu_min", value / 100.0))
    gpu_slider = _slider(parent, "GPU maximum", _percent(profile.get("gpu_max", "1.0")), 35, 100, func(value): _save_profile_limit("gpu_max", value / 100.0))
    var curves: Array = []
    for name in power.get("fan_curves", {}):
        curves.append({"data": name, "label": String(power["fan_curves"][name].get("label", name))})
    if not curves.is_empty():
        _dropdown(parent, "Fan curve", curves, String(profile.get("fan_curve", curves[0]["data"])), func(value): _save_profile_value("fan_curve", value))
    var governors: Array = []
    for name in config.get("perf", {}).get("governors", []):
        governors.append({"data": name, "label": name})
    if not governors.is_empty():
        _dropdown(parent, "CPU governor", governors, String(profile.get("cpu_governor", governors[0]["data"])), func(value): _save_profile_value("cpu_governor", value))


func _build_system(parent: Container) -> void:
    var controller_options: Array = config.get("controllerTypes", [
        {"data": "deck-uhid", "label": "Steam Deck"},
        {"data": "xb360", "label": "Xbox 360"},
        {"data": "ds5", "label": "DualSense"},
    ])
    _dropdown(parent, "Controller emulation", controller_options, String(config.get("controllerType", "deck-uhid")), func(value): _call("set_controller_type", {"value": value}))
    _toggle(parent, "Automatic compatibility", _global_tweak("autoApplyCompat"), func(value): _save_tweak("autoApplyCompat", value))
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
            _slider(parent, "RGB brightness", float(rgb.get("brightness", 100)), 0, 100, func(value): _set_rgb_brightness(value, rgb))

    var temp = _call_result("get_current_temp")
    if temp != null:
        var temperature := Label.new()
        temperature.text = "Temperature: %s °C" % temp
        temperature.label_settings = BODY_LABELS
        parent.add_child(temperature)


func _build_fans(parent: Container) -> void:
    var settings: Dictionary = fan_state.get("fanSettings", {})
    if settings.is_empty():
        _action(parent, "Refresh fan state", _refresh_fans)
        return
    var current_temp = fan_state.get("currentTemp")
    if current_temp != null:
        var temperature := Label.new()
        temperature.text = "Fan temperature: %s °C" % current_temp
        temperature.label_settings = BODY_LABELS
        parent.add_child(temperature)
    _slider(parent, "Fan smoothing", float(settings.get("smoothing", 0.0)), 0, 1, func(value): _stage_fan_setting("smoothing", value))
    _slider(parent, "Minimum fan PWM", float(settings.get("min_pwm", 0)), 0, 255, func(value): _stage_fan_setting("min_pwm", value))
    _action(parent, "Save fan settings", _save_fans)


func _build_actions(parent: Container) -> void:
    _action(parent, "Reapply performance settings", func(): _call("reapply_perf"))
    calibration_button = _action(parent, "Start controller calibration", _toggle_calibration)
    _action(parent, "Reset controller calibration", func(): _call("reset_calibration"))
    _action(parent, "Restart Game Mode", func(): _call("restart_game_mode"))
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

    calibration_timer.stop()
    backend.call_action("end_calibration_session", {"token": "armada-ogui-quickbar"})
    var response = backend.call_action("save_calibration", {"capture": calibration_capture})
    calibration_recording = false
    calibration_button.button_text = "Start controller calibration"
    _update_status("Calibration saved" if response.get("ok", false) else backend.last_error)


func _capture_calibration_sample() -> void:
    if not calibration_recording:
        return
    var response = backend.call_action("get_controller_state")
    if not response.get("ok", false):
        _update_status(backend.last_error)
        return
    var controls: Dictionary = response.get("result", {}).get("controls", {})
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


func _build_games(parent: Container) -> void:
    var tweaks: Dictionary = config.get("tweaks", {})
    var global: Dictionary = tweaks.get("global", {})
    var fex_options: Array = []
    for name in config.get("fexProfiles", {}):
        fex_options.append({"data": name, "label": String(config["fexProfiles"][name].get("label", name))})
    if not fex_options.is_empty():
        _dropdown(parent, "FEX preset", fex_options, String(global.get("fexProfile", "default")), _save_fex_profile)
    var fex_config: Dictionary = global.get("fexConfig", {})
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
    var thunks: Dictionary = global.get("thunks", {})
    for key in ["Vulkan", "GL", "asound", "drm", "WaylandClient"]:
        _toggle(parent, "Host " + key, thunks.get(key, true) != false, _thunk_callback(key))
    _toggle(parent, "Gamescope realtime", bool(global.get("gamescopeRr", false)), func(value): _save_tweak("gamescopeRr", value))
    _toggle(parent, "Vulkan realtime queue", bool(global.get("gamescopeVulkanRealtime", false)), func(value): _save_tweak("gamescopeVulkanRealtime", value))


func _fex_callback(key: String) -> Callable:
    return func(value): _save_fex_knob(key, value)


func _thunk_callback(key: String) -> Callable:
    return func(value): _save_thunk(key, value)


func _build_compatibility(parent: Container) -> void:
    if compat_tools.is_empty():
        _action(parent, "Refresh Steam compatibility", func(): _refresh_compatibility())
        return
    _dropdown(parent, "Default Proton", compat_tools, compat_tool, _save_global_tool)
    _dropdown(parent, "Default resolution", ["Default", "Native", "1280x720", "960x540"], "Default", func(value): _call_steam("set_global_resolution", {"value": value}))
    if current_appid.is_valid_int() and not current_appid.is_empty():
        _action(parent, "Reset running game compatibility", func(): _reset_running_game())
    _action(parent, "Sweep Steam compatibility", func(): _sweep_compatibility())


func _refresh_compatibility() -> void:
    var response = backend.call_steam("get_global_compat_tools")
    if response.get("ok", false):
        compat_tools = response.get("result", {}).get("tools", [])
        _update_status("Steam compatibility refreshed")
    else:
        _update_status(backend.last_error)


func _save_global_tool(tool: String) -> void:
    compat_tool = tool
    var tweaks: Dictionary = config.get("tweaks", {}).duplicate(true)
    var global: Dictionary = tweaks.get("global", {})
    global["windowsCompatTool"] = tool
    tweaks["global"] = global
    _save_tweaks(tweaks)
    _sweep_compatibility()


func _sweep_compatibility() -> void:
    var games: Array = []
    for game in installed_games:
        if game is Dictionary and not bool(game.get("nonSteam", false)) and String(game.get("appid", "")).is_valid_int():
            games.append({"appid": String(game["appid"])})
    var response = _call_steam("sweep_compat", {"games": games, "tool": compat_tool, "auto_apply": true})
    _update_status("Compatibility sweep complete" if response.get("ok", false) else backend.last_error)


func _reset_running_game() -> void:
    var response = _call_steam("reset_game", {"appid": current_appid, "tool": compat_tool})
    _update_status("Running game reset" if response.get("ok", false) else backend.last_error)


func _call_steam(action: String, fields: Dictionary = {}) -> Dictionary:
    return backend.call_steam(action, fields)


func _action(parent: Container, text: String, callback: Callable) -> CardButtonSetting:
    var setting := CARD_BUTTON_SETTING.instantiate() as CardButtonSetting
    setting.text = text
    setting.button_text = "A"
    parent.add_child(setting)
    setting.pressed.connect(callback)
    return setting


func _dropdown(parent: Container, title: String, options: Array, selected_value: String, callback: Callable) -> void:
    var dropdown := DROPDOWN.instantiate() as Dropdown
    dropdown.title = title
    parent.add_child(dropdown)
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


func _toggle(parent: Container, title: String, value: bool, callback: Callable) -> void:
    var toggle := TOGGLE.instantiate() as Toggle
    toggle.text = title
    toggle.button_pressed = value
    parent.add_child(toggle)
    toggle.toggled.connect(callback)


func _slider(parent: Container, title: String, value: float, minimum: float, maximum: float, callback: Callable) -> ValueSlider:
    var slider := SLIDER.instantiate() as ValueSlider
    slider.text = title
    slider.min_value = minimum
    slider.max_value = maximum
    slider.value = value
    parent.add_child(slider)
    slider.value_changed.connect(callback)
    return slider


func _select_profile(name: String) -> void:
    selected_profile = name
    var profile: Dictionary = config.get("power", {}).get("profiles", {}).get(name, {})
    if cpu_slider:
        cpu_slider.value = _percent(profile.get("cpu_max", "1.0"))
    if gpu_slider:
        gpu_slider.value = _percent(profile.get("gpu_max", "1.0"))
    if gpu_min_slider:
        gpu_min_slider.value = _percent(profile.get("gpu_min", "0.0"))
    var power: Dictionary = config.get("power", {}).duplicate(true)
    var general: Dictionary = power.get("general", {})
    general["default_profile"] = name
    power["general"] = general
    _save_power(power)


func _save_profile_limit(key: String, value: float) -> void:
    var power: Dictionary = config.get("power", {}).duplicate(true)
    var profiles: Dictionary = power.get("profiles", {})
    var profile: Dictionary = profiles.get(selected_profile, {})
    profile[key] = "%.2f" % clampf(value, 0.0, 1.0)
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
        _update_status("Fan state refreshed")
    else:
        _update_status(backend.last_error)


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
    var global: Dictionary = tweaks.get("global", {})
    global["fexProfile"] = name
    if name != "custom":
        var profile: Dictionary = config.get("fexProfiles", {}).get(name, {})
        global["fexConfig"] = profile.get("config", {})
    tweaks["global"] = global
    _save_tweaks(tweaks)


func _save_fex_knob(key: String, value: bool) -> void:
    var tweaks: Dictionary = config.get("tweaks", {}).duplicate(true)
    var global: Dictionary = tweaks.get("global", {})
    var fex_config: Dictionary = global.get("fexConfig", {}).duplicate(true)
    fex_config[key] = "1" if value else "0"
    global["fexProfile"] = "custom"
    global["fexConfig"] = fex_config
    tweaks["global"] = global
    _save_tweaks(tweaks)


func _save_thunk(key: String, value: bool) -> void:
    var tweaks: Dictionary = config.get("tweaks", {}).duplicate(true)
    var global: Dictionary = tweaks.get("global", {})
    var thunks: Dictionary = global.get("thunks", {}).duplicate(true)
    thunks[key] = value
    global["thunks"] = thunks
    tweaks["global"] = global
    _save_tweaks(tweaks)


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
    _update_status("Saved" if response.get("ok", false) else backend.last_error)


func _set_rgb_brightness(value: float, previous: Dictionary) -> void:
    var response = backend.call_action("set_rgb", {
        "enabled": bool(previous.get("enabled", true)),
        "color": String(previous.get("color", "FFFFFF")),
        "brightness": int(value),
    })
    _update_status("Saved" if response.get("ok", false) else backend.last_error)


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
