extends Node3D
## Точка входа: связывает системы между собой, загружает или создаёт мир.
## Новый мир — кнопка в настройках или запуск с аргументом `-- --new-world`.

const AUTOSAVE_INTERVAL := 60.0

var _autosave := AUTOSAVE_INTERVAL

@onready var chunk_manager: ChunkManager = $ChunkManager
@onready var camera_rig: CameraRig = $CameraRig
@onready var building_system: BuildingSystem = $BuildingSystem
@onready var interaction: Interaction = $Interaction
@onready var hud: Hud = $Hud
@onready var water: Water = $Water
@onready var atmosphere: Atmosphere = $Atmosphere


func _ready() -> void:
	var loaded := false
	if not "--new-world" in OS.get_cmdline_user_args():
		loaded = WorldState.load_game()
	if not loaded:
		WorldState.new_world()

	chunk_manager.view_radius = Settings.get_value("view_distance")
	chunk_manager.start(WorldState.world_seed)
	camera_rig.chunk_manager = chunk_manager
	building_system.chunk_manager = chunk_manager
	interaction.camera_rig = camera_rig
	interaction.chunk_manager = chunk_manager
	interaction.building_system = building_system
	water.camera_rig = camera_rig
	water.chunk_manager = chunk_manager
	atmosphere.camera_rig = camera_rig
	hud.bind(interaction)
	hud.new_world_requested.connect(_new_world)
	Settings.changed.connect(_on_setting_changed)

	if loaded and not WorldState.camera_state.is_empty():
		camera_rig.set_state(WorldState.camera_state)
	else:
		camera_rig.teleport(chunk_manager.gen.find_spawn())
	chunk_manager.focus = camera_rig.position
	chunk_manager.initial_area_ready.connect(_on_world_ready, CONNECT_ONE_SHOT)


func _on_world_ready() -> void:
	building_system.restore_from_save()
	hud.hide_loading()
	hud.show_message("Добро пожаловать! Срубите пару деревьев и постройте лесопилку.")


func _on_setting_changed(key: String) -> void:
	if key == "view_distance":
		chunk_manager.set_view_radius(Settings.get_value("view_distance"))


func _new_world() -> void:
	WorldState.new_world()
	WorldState.save_game()
	get_tree().reload_current_scene()


func _process(delta: float) -> void:
	WorldState.camera_state = camera_rig.get_state()
	_autosave -= delta
	if _autosave <= 0.0:
		_autosave = AUTOSAVE_INTERVAL
		WorldState.save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		WorldState.save_game()
