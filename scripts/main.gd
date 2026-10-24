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
@onready var sun: DirectionalLight3D = $Sun


func _ready() -> void:
	var loaded := false
	if not "--new-world" in OS.get_cmdline_user_args():
		loaded = WorldState.load_game()
	if not loaded:
		WorldState.new_world()

	chunk_manager.view_radius = Settings.get_value("view_distance")
	if Platform.is_mobile() or Platform.is_web:
		# Новые чанки — по одному за кадр, чтобы на телефоне и в браузере не было рывков.
		chunk_manager.finalize_per_frame = 1
		chunk_manager.max_tasks_in_flight = 3
	if Platform.is_web:
		# В браузере потоков нет: мир строится в главном потоке, по чанку за кадр.
		chunk_manager.use_threads = false
		chunk_manager.max_tasks_in_flight = 1
	chunk_manager.start(WorldState.world_seed)
	chunk_manager.chunk_loaded.connect(building_system.on_chunk_loaded)
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
	if Platform.is_touch:
		var touch := TouchInput.new()
		touch.name = "TouchInput"
		touch.camera_rig = camera_rig
		touch.interaction = interaction
		add_child(touch)
	_apply_graphics()

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
	match key:
		"view_distance":
			chunk_manager.set_view_radius(Settings.get_value("view_distance"))
		"grass":
			chunk_manager.reload_all()
		"render_scale":
			_apply_graphics()


## Разрешение 3D-картинки и облегчения для телефона.
func _apply_graphics() -> void:
	var vp := get_viewport()
	var render_scale: float = clampf(float(Settings.get_value("render_scale")), 0.5, 1.0)
	vp.scaling_3d_scale = render_scale
	# На ПК при уменьшенном разрешении — FSR (чётче), на телефоне — простое, оно дешевле.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.99 and not Platform.is_mobile() \
		else Viewport.SCALING_3D_MODE_BILINEAR
	if Platform.is_mobile():
		sun.directional_shadow_max_distance = 90.0
		sun.shadow_blur = 1.0


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
	if not is_node_ready():
		return
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			WorldState.save_game()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			# Телефон может закрыть свёрнутую игру, а браузер — вкладку без предупреждения.
			if (Platform.is_mobile() or Platform.is_web) and chunk_manager.is_ready():
				WorldState.save_game()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Кнопка «Назад» на Android: закрыть окно или выйти из инструмента.
			if hud.close_top_panel():
				return
			if interaction.tool != Interaction.Tool.HARVEST:
				interaction.set_tool(Interaction.Tool.HARVEST)
