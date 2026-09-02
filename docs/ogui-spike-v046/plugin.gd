extends Plugin

const OVERLAY_SCENE := preload("res://plugins/armada-control/overlay.tscn")

func _init() -> void:
    print("Armada Control test plugin init")

func _ready() -> void:
    logger = Log.get_logger("ArmadaControlSpike", Log.LEVEL.DEBUG)
    print("Armada Control test plugin ready")
    get_tree().create_timer(2.0).timeout.connect(_mount)

func _mount() -> void:
    print("Armada Control test plugin mounting")
    var main := get_tree().get_first_node_in_group("main")
    if not main:
        logger.error("OGUI main scene was not found")
        return
    logger.info("Mounting Armada Control test panel")
    var panel := PanelContainer.new()
    panel.name = "ArmadaControlTestPanel"
    panel.custom_minimum_size = Vector2(620, 420)
    panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    panel.add_child(OVERLAY_SCENE.instantiate())
    main.add_child(panel)
    main.call_deferred("_on_base_state_exited", null)
