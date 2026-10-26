extends Node3D
## Точка входа: связывает системы между собой, загружает или создаёт мир.
## Новый мир — кнопка в настройках или запуск с аргументом `-- --new-world`.

## Автосохранение раз в 5 минут (и сразу, когда игру сворачивают).
const AUTOSAVE_INTERVAL := 300.0

## Авто-качество: замеряем частоту кадров окнами по PERF_WINDOW секунд.
const PERF_WINDOW := 4.0

var _autosave := AUTOSAVE_INTERVAL
var _markers: Markers
var _perf_time := 0.0
var _perf_frames := 0
var _perf_grace := 10.0

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
	Minimap.reset_canvas()

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
	chunk_manager.chunk_loaded.connect(Minimap.explore)
	chunk_manager.chunk_loaded.connect(water.write_flow)
	chunk_manager.building_hook = building_system.on_chunk_loaded
	chunk_manager.blocked_by_building = func(p: Vector2) -> bool:
		for b in building_system.buildings:
			if is_instance_valid(b) and Building.obb_has_point(b.obb(0.5), p):
				return true
		return false
	Crafting.station_distance = _station_distance
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
	_markers = Markers.new()
	_markers.name = "Markers"
	_markers.chunk_manager = chunk_manager
	add_child(_markers)
	hud.markers_changed.connect(_markers.refresh)
	Settings.changed.connect(_on_setting_changed)
	if Platform.is_touch:
		var touch := TouchInput.new()
		touch.name = "TouchInput"
		touch.camera_rig = camera_rig
		touch.interaction = interaction
		touch.hide_ui_requested.connect(hud.toggle_ui_hidden)
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
	_markers.refresh()
	hud.hide_loading()
	hud.show_message("Добро пожаловать! Срубите пару деревьев и постройте лесопилку.")


func _on_setting_changed(key: String) -> void:
	match key:
		"view_distance":
			chunk_manager.set_view_radius(Settings.get_value("view_distance"))
		"grass":
			chunk_manager.refresh_all_cover()
		"grass_distance":
			chunk_manager.apply_cover_distance()
		"render_scale", "shadow_quality":
			_apply_graphics()
		"quality":
			_perf_grace = 10.0


## Разрешение 3D-картинки и качество теней.
func _apply_graphics() -> void:
	var vp := get_viewport()
	var render_scale: float = clampf(float(Settings.get_value("render_scale")), 0.5, 1.0)
	vp.scaling_3d_scale = render_scale
	# На ПК при уменьшенном разрешении — FSR (чётче), на телефоне и в браузере — простое.
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.99 and forward_plus and not Platform.is_mobile() \
		else Viewport.SCALING_3D_MODE_BILINEAR
	# Тени: размер карты теней, мягкость краёв и дальность.
	var q: String = Settings.get_value("shadow_quality")
	sun.shadow_enabled = q != "off"
	var atlas := 2048
	var filter := RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	match q:
		"low":
			atlas = 1024
			filter = RenderingServer.SHADOW_QUALITY_SOFT_LOW
			sun.shadow_blur = 1.6
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 70.0
			sun.light_angular_distance = 0.0
		"medium":
			sun.shadow_blur = 2.2
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 110.0
			sun.light_angular_distance = 0.0
		"high":
			atlas = 4096
			filter = RenderingServer.SHADOW_QUALITY_SOFT_HIGH
			sun.shadow_blur = 2.4
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 160.0
			# Солнце — не точка: тень у основания резкая, а дальше расплывается.
			sun.light_angular_distance = 0.0 if Platform.is_web else 1.0
	RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(filter)


## Авто-качество: если кадры не успевают несколько секунд подряд — ступенью ниже.
func _watch_performance(delta: float) -> void:
	if Settings.get_value("quality") != "auto" or not chunk_manager.is_ready():
		return
	# Свёрнутая вкладка или долгий кадр (загрузка) — не повод снижать графику.
	if delta > 0.5 or not get_window().has_focus():
		_perf_time = 0.0
		_perf_frames = 0
		return
	if _perf_grace > 0.0:
		_perf_grace -= delta
		return
	_perf_time += delta
	_perf_frames += 1
	if _perf_time < PERF_WINDOW:
		return
	var fps := _perf_frames / _perf_time
	_perf_time = 0.0
	_perf_frames = 0
	var target := 60.0 if Engine.max_fps <= 0 else minf(60.0, Engine.max_fps)
	if fps < target * 0.72:
		var level := Settings.lower_auto_quality()
		if level != "":
			hud.show_message("Графика: %s — чтобы игра шла плавно" % Settings.QUALITY_NAMES[level].to_lower())
			_perf_grace = 8.0


## Расстояние от камеры до ближайшей готовой мастерской (для ремесла).
func _station_distance(station: String) -> float:
	var best := INF
	var focus := camera_rig.position
	for b in building_system.buildings:
		if is_instance_valid(b) and b.id == station and b.is_complete:
			best = minf(best, Vector2(b.position.x - focus.x, b.position.z - focus.z).length())
	return best


func _new_world() -> void:
	WorldState.new_world()
	WorldState.save_game()
	get_tree().reload_current_scene()


func _process(delta: float) -> void:
	WorldState.camera_state = camera_rig.get_state()
	_watch_performance(delta)
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
