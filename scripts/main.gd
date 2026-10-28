extends Node3D
## Точка входа: связывает системы между собой, показывает стартовый экран со
## списком миров и строит выбранный мир. `-- --new-world` — сразу новый мир.

## Автосохранение раз в 5 минут (и сразу, когда игру сворачивают). В браузере —
## раз в минуту: вкладку могут закрыть, не дав записать сохранение.
const AUTOSAVE_INTERVAL := 300.0
const AUTOSAVE_INTERVAL_WEB := 60.0

## Авто-качество: замеряем частоту кадров окнами по PERF_WINDOW секунд.
const PERF_WINDOW := 4.0
## Доля полосы загрузки на подготовку графики (остальное — стартовый кусок мира).
const WARMUP_SHARE := 0.35

var _autosave := AUTOSAVE_INTERVAL
var _markers: Markers
var _paths: PathSystem
var _fences: FenceSystem
var _perf_time := 0.0
var _perf_frames := 0
var _perf_grace := 10.0
var _warmup: ShaderWarmup
var _world_ready := false
## Модели ещё подгружаются в фоне (ModelLibrary.preload_step).
var _preloading_models := false
var _normal_chunk_pace := []
## JS-функция «страницу спрятали» (в браузере): держим ссылку, чтобы её не собрал сборщик мусора.
var _on_page_hide: JavaScriptObject

@onready var chunk_manager: ChunkManager = $ChunkManager
@onready var camera_rig: CameraRig = $CameraRig
@onready var building_system: BuildingSystem = $BuildingSystem
@onready var interaction: Interaction = $Interaction
@onready var hud: Hud = $Hud
@onready var water: Water = $Water
@onready var atmosphere: Atmosphere = $Atmosphere
@onready var sun: DirectionalLight3D = $Sun


func _ready() -> void:
	chunk_manager.view_radius = Platform.view_radius()
	if Platform.is_mobile() or Platform.is_web:
		# Новые чанки — по одному за кадр, чтобы на телефоне и в браузере не было рывков.
		chunk_manager.finalize_per_frame = 1
		chunk_manager.max_tasks_in_flight = 3
	if Platform.is_web and not OS.has_feature("threads"):
		# Браузер без потоков (сборка без многопоточности или страница не изолирована):
		# мир строится в главном потоке, по чанку за кадр.
		chunk_manager.use_threads = false
		chunk_manager.max_tasks_in_flight = 1
	elif Platform.threaded():
		# Потоки есть: стартовый кусок мира больше, пройденное держим загруженным дольше,
		# новые чанки строятся сразу в нескольких потоках.
		chunk_manager.initial_radius = 4
		chunk_manager.keep_margin = 3
		chunk_manager.max_tasks_in_flight = maxi(chunk_manager.max_tasks_in_flight, 4)
	chunk_manager.chunk_loaded.connect(building_system.on_chunk_loaded)
	chunk_manager.chunk_loaded.connect(Minimap.explore)
	chunk_manager.chunk_loaded.connect(water.write_flow)
	_paths = PathSystem.new()
	_paths.name = "Paths"
	_paths.chunk_manager = chunk_manager
	add_child(_paths)
	chunk_manager.chunk_loaded.connect(_paths.on_chunk_loaded)
	_fences = FenceSystem.new()
	_fences.name = "Fences"
	_fences.chunk_manager = chunk_manager
	add_child(_fences)
	chunk_manager.chunk_loaded.connect(_fences.on_chunk_loaded)
	# Землю выравнивают: здания, дорожки и ограды встают на неё сразу, во время мазка.
	chunk_manager.terrain_changed.connect(building_system.reground_area)
	chunk_manager.terrain_changed.connect(_paths.on_terrain_changed)
	chunk_manager.terrain_changed.connect(_fences.on_terrain_changed)
	# После пересева травы в чанке снова убираем её под зданиями, дорожками и оградами.
	chunk_manager.building_hook = func(chunk: Chunk) -> void:
		building_system.on_chunk_loaded(chunk)
		_paths.on_chunk_loaded(chunk)
		_fences.on_chunk_loaded(chunk)
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
	interaction.path_system = _paths
	interaction.fence_system = _fences
	water.camera_rig = camera_rig
	water.chunk_manager = chunk_manager
	atmosphere.camera_rig = camera_rig
	hud.bind(interaction)
	hud.menu_requested.connect(_to_menu)
	hud.cache_clear_requested.connect(_clear_cache)
	hud.village_requested.connect(_open_village)
	_markers = Markers.new()
	_markers.name = "Markers"
	_markers.chunk_manager = chunk_manager
	add_child(_markers)
	hud.markers_changed.connect(_markers.refresh)
	Settings.changed.connect(_on_setting_changed)
	Platform.layout_changed.connect(_apply_graphics)
	if OS.has_feature("web"):
		# Выбор многопоточности хранит страница — берём его оттуда.
		var mode: Variant = JavaScriptBridge.eval("window.everstead && window.everstead.threadsMode ? window.everstead.threadsMode() : 'auto'")
		if mode is String and mode != Settings.get_value("web_threads"):
			Settings.set_value("web_threads", mode)
	# Касания понимаются на любом устройстве (и на ноутбуке с сенсорным экраном).
	var touch := TouchInput.new()
	touch.name = "TouchInput"
	touch.camera_rig = camera_rig
	touch.interaction = interaction
	touch.hide_ui_requested.connect(hud.toggle_ui_hidden)
	add_child(touch)
	_apply_graphics()

	# Запуск по шагам, чтобы браузер не «зависал»: первый кадр — только экран
	# загрузки, затем шейдеры компилируются по одному за кадр. Потом — стартовый
	# экран со списком миров, и только когда мир выбран, он строится.
	chunk_manager.running = false
	water.visible = false
	get_viewport().disable_3d = true
	_warmup = ShaderWarmup.new()
	_warmup.name = "ShaderWarmup"
	_warmup.steps = _warmup_steps()
	# Солнце и луна: день, сумерки, ночь (дальше их снова ведёт Atmosphere).
	var moon: DirectionalLight3D = atmosphere.moon
	_warmup.light_setups = [
		func() -> void:
			sun.visible = true
			moon.visible = false,
		func() -> void:
			sun.visible = true
			moon.visible = true,
		func() -> void:
			sun.visible = false
			moon.visible = true,
	]
	_warmup.progress.connect(func(f: float) -> void: _report_loading(f * WARMUP_SHARE, "Готовим графику…"))
	_warmup.finished.connect(_on_warmup_done)
	add_child(_warmup)
	_report_loading(0.0, "Готовим графику…")


func _on_warmup_done() -> void:
	_warmup.queue_free()
	# `-- --new-world [--seed=N]` — сразу новый мир, без стартового экрана (для проверок).
	if "--new-world" in OS.get_cmdline_user_args():
		var seed_value := -1
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--seed="):
				seed_value = int(arg.substr(7))
		WorldState.create_world("Новый мир", seed_value)
	# `-- --village=ID` — сразу готовая деревня (для проверок и снимков).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--village="):
			VillageBuilder.create(arg.substr(10))
	if WorldState.world_id != "":
		_start_world()
		return
	# Пока открыт стартовый экран, 3D не рисуется — телефон не греется зря.
	get_viewport().disable_3d = true
	var start := StartScreen.new()
	start.name = "StartScreen"
	start.chosen.connect(func() -> void:
		get_viewport().disable_3d = false
		_start_world())
	add_child(start)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.everstead && window.everstead.ready()")


## Мир выбран (WorldState уже открыл или создал его) — строим его под экраном загрузки.
func _start_world() -> void:
	Minimap.reset_canvas()
	chunk_manager.start(WorldState.world_seed)
	if not WorldState.camera_state.is_empty():
		camera_rig.set_state(WorldState.camera_state)
	else:
		camera_rig.teleport(chunk_manager.gen.find_spawn())
	chunk_manager.focus = camera_rig.position
	chunk_manager.initial_area_ready.connect(_on_world_ready, CONNECT_ONE_SHOT)
	# Под экраном загрузки рывки не видны — стартовый кусок мира строим быстрее.
	_normal_chunk_pace = [chunk_manager.finalize_per_frame, chunk_manager.max_tasks_in_flight]
	chunk_manager.finalize_per_frame = 4
	chunk_manager.max_tasks_in_flight = maxi(chunk_manager.max_tasks_in_flight, 6 if Platform.threaded() else 4)
	chunk_manager.running = true
	_report_loading(WARMUP_SHARE, "Строим мир…")


## По виду материала на шаг — в том же формате, в каком их рисует мир.
func _warmup_steps() -> Array[Callable]:
	var far := float(Settings.get_value("grass_distance"))
	var steps: Array[Callable] = [
		# Кадр только с экраном загрузки.
		func() -> Variant: return null,
		# Небо.
		func() -> Variant:
			get_viewport().disable_3d = false
			return null,
		func() -> Variant: return ShaderWarmup.quad(ModelLibrary.terrain_material()),
		func() -> Variant: return ShaderWarmup.multimesh(ModelLibrary.foliage_material()),
		func() -> Variant: return ShaderWarmup.multimesh(GroundCover.grass_material(far), true, false, false),
		func() -> Variant: return ShaderWarmup.multimesh(GroundCover.litter_material(far * 1.15), true, true, false),
		func() -> Variant: return ShaderWarmup.quad(ModelLibrary.building_material("plank")),
		func() -> Variant: return ShaderWarmup.quad(ModelLibrary.building_material("water"), false),
		func() -> Variant: return ShaderWarmup.quad(ModelLibrary.building_material("pane"), false),
		func() -> Variant: return ShaderWarmup.quad(Building.ghost_material(), false),
		func() -> Variant: return ShaderWarmup.quad(_paths.material_for("path_dirt"), false),
		func() -> Variant: return ShaderWarmup.multimesh(ModelLibrary.fish_material(), false, true, false),
		func() -> Variant: return Interaction.make_ring(Color.WHITE),
		func() -> Variant: return Fire.new(),
		# Всё, что впервые появляется уже в игре: выделение, всплески и пыль стройки,
		# искры сундука, метки, вода на рисовой грядке, дождь, снег и листопад.
		func() -> Variant: return ShaderWarmup.quad(Building.highlight_material(), false),
		func() -> Variant:
			var burst := Fx.burst_node(Color.WHITE, 2)
			burst.emitting = true
			return burst,
		func() -> Variant: return ShaderWarmup.cpu_particles(Chest.sparkle_material(Color.WHITE)),
		func() -> Variant: return ShaderWarmup.quad(Markers.pole_material()),
		func() -> Variant: return ShaderWarmup.quad(Markers.flag_material(Color.WHITE)),
		func() -> Variant: return ShaderWarmup.quad(CropPatch.rice_water(), false),
		func() -> Variant: return atmosphere.warmup_node(),
		# Вода — последней: её шейдер самый тяжёлый. Сначала кусочек при разном
		# освещении (как у остальных материалов), потом — сама водная гладь.
		func() -> Variant: return ShaderWarmup.quad(water.material_override, false),
		func() -> Variant:
			water.visible = true
			return null,
	]
	# Окна интерфейса, капли на экране и смена погоды.
	steps.append_array(hud.warmup_steps())
	return steps


## Ход загрузки: на экран загрузки игры и в браузерный (он закрывает холст).
func _report_loading(fraction: float, text: String) -> void:
	hud.set_loading(fraction, text)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.everstead && window.everstead.progress(%f, %s)" % [fraction, JSON.stringify(text)])


func _on_world_ready() -> void:
	_world_ready = true
	if not _normal_chunk_pace.is_empty():
		chunk_manager.finalize_per_frame = _normal_chunk_pace[0]
		chunk_manager.max_tasks_in_flight = _normal_chunk_pace[1]
	_perf_grace = 10.0
	_autosave = AUTOSAVE_INTERVAL_WEB if Platform.is_web else AUTOSAVE_INTERVAL
	building_system.restore_from_save()
	_paths.restore()
	_fences.restore()
	_markers.refresh()
	# С потоками остальные модели подгружаются в фоне, без рывков в игре.
	if Platform.threaded():
		ModelLibrary.begin_preload()
		_preloading_models = true
	_report_loading(1.0, "Готово!")
	hud.hide_loading()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.everstead && window.everstead.ready()")
		# Вкладку спрятали или перезагружают — сохраняем сразу, не дожидаясь автосохранения.
		_on_page_hide = JavaScriptBridge.create_callback(func(_args: Array) -> void:
			WorldState.camera_state = camera_rig.get_state()
			WorldState.save_game())
		var everstead: Variant = JavaScriptBridge.get_interface("everstead")
		if everstead:
			everstead.onHide = _on_page_hide
	if WorldState.buildings.is_empty():
		hud.show_message("Добро пожаловать в «%s»! Срубите пару деревьев и постройте лесопилку." % WorldState.world_name)
	else:
		hud.show_message("С возвращением в «%s»!" % WorldState.world_name)


func _on_setting_changed(key: String) -> void:
	match key:
		"web_threads":
			if OS.has_feature("web"):
				JavaScriptBridge.eval("window.everstead && window.everstead.setThreads && window.everstead.setThreads(%s)"
					% JSON.stringify(Settings.get_value("web_threads")))
		"view_distance":
			chunk_manager.set_view_radius(Platform.view_radius())
		"grass":
			chunk_manager.refresh_all_cover()
		"grass_distance":
			chunk_manager.apply_cover_distance()
		"render_scale", "shadow_quality", "shadow_distance", "textures":
			_apply_graphics()
		"quality":
			_perf_grace = 10.0
			_apply_graphics()


## Разрешение 3D-картинки и качество теней.
## Пикселей 3D-картинки (млн) на каждом уровне качества — для телефона и браузера.
## У iPhone экран втрое плотнее точек интерфейса (2556×1179 — 3 млн пикселей):
## считать 3D во всех них — втрое больше работы, а на глаз разница почти не видна.
## Интерфейс при этом остаётся в полном разрешении.
const PIXEL_BUDGET_MOBILE := [0.6, 0.85, 1.2, 1.6]
const PIXEL_BUDGET_WEB := [0.9, 1.4, 2.1, 3.0]


## Разрешение 3D-картинки, сглаживание, свечение и качество теней.
func _apply_graphics() -> void:
	var vp := get_viewport()
	var level := Settings.quality_level()
	var light := Platform.is_mobile() or Platform.is_web
	var render_scale: float = clampf(float(Settings.get_value("render_scale")), 0.5, 1.0)
	if light:
		var px := Vector2(get_window().size)
		var budget: float = (PIXEL_BUDGET_MOBILE if Platform.is_mobile() else PIXEL_BUDGET_WEB)[level] * 1000000.0
		render_scale = clampf(minf(render_scale, sqrt(budget / maxf(px.x * px.y, 1.0))), 0.4, 1.0)
	vp.scaling_3d_scale = render_scale
	# На ПК при уменьшенном разрешении — FSR (чётче), на телефоне и в браузере — простое.
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.99 and forward_plus and not Platform.is_mobile() \
		else Viewport.SCALING_3D_MODE_BILINEAR
	if light:
		# Сглаживание MSAA — только на максимуме: на плотном экране телефона «лесенки» почти не видно.
		vp.msaa_3d = Viewport.MSAA_2X if level >= 3 else Viewport.MSAA_DISABLED
		var env := get_world_3d().environment
		if env == null and has_node("WorldEnvironment"):
			env = ($WorldEnvironment as WorldEnvironment).environment
		if env:
			env.glow_enabled = level >= 2
	# Комнаты за окнами — только на высоком и наивысшем качестве.
	RenderingServer.global_shader_parameter_set("interiors", 1.0 if level >= 2 else 0.0)
	RenderingServer.global_shader_parameter_set("texture_detail", 1.0 if Settings.get_value("textures") == "realism" else 0.0)
	# Тени: размер карты теней, мягкость краёв и дальность (её игрок задаёт сам).
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
			sun.light_angular_distance = 0.0
		"medium":
			sun.shadow_blur = 2.2
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.light_angular_distance = 0.0
		"high":
			atlas = 4096
			filter = RenderingServer.SHADOW_QUALITY_SOFT_HIGH
			sun.shadow_blur = 2.4
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			# Солнце — не точка: тень у основания резкая, а дальше расплывается.
			sun.light_angular_distance = 0.0 if Platform.is_web else 1.0
	if light and q == "high":
		# На телефоне и в браузере каждое деление теней — ещё одна перерисовка мира:
		# два деления вместо четырёх и карта поменьше.
		atlas = 2048
		filter = RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	var distance := clampf(float(Settings.get_value("shadow_distance")), 40.0, 400.0)
	sun.directional_shadow_max_distance = distance
	# Ближнее деление — на то, что вокруг камеры (до ~70 м), иначе при большой дальности
	# тени вблизи становятся крупнозернистыми; дальние деления — растянуты на остальное.
	sun.directional_shadow_split_1 = clampf(70.0 / distance, 0.1, 0.5) \
		if sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS else clampf(30.0 / distance, 0.06, 0.2)
	sun.directional_shadow_split_2 = clampf(80.0 / distance, 0.15, 0.4)
	sun.directional_shadow_split_3 = clampf(160.0 / distance, 0.4, 0.7)
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


func _exit_tree() -> void:
	# Сцена уходит (выход в главное меню) — JS больше не должен звать её сохранение.
	if _on_page_hide:
		var everstead: Variant = JavaScriptBridge.get_interface("everstead")
		if everstead:
			everstead.onHide = null
		_on_page_hide = null


## «Очистить кэш» в настройках: мир сохраняется заранее — в браузере страница потом
## перезапустится.
func _clear_cache() -> void:
	WorldState.camera_state = camera_rig.get_state()
	WorldState.save_game()
	if Platform.clear_cache():
		hud.show_message("Скачиваем свежую версию игры — потом она перезапустится")
	else:
		hud.show_message("Кэш очищен — шейдеры соберутся заново при следующем запуске")


## Готовая деревня из настроек: текущий мир сохраняется, деревня открывается новым миром.
func _open_village(id: String) -> void:
	WorldState.camera_state = camera_rig.get_state()
	WorldState.save_game()
	WorldState.close_world()
	if not VillageBuilder.create(id):
		hud.show_message("Не получилось открыть деревню")
		return
	get_tree().reload_current_scene()


## «В главное меню»: сохраняем мир и показываем стартовый экран заново.
func _to_menu() -> void:
	WorldState.camera_state = camera_rig.get_state()
	WorldState.save_game()
	WorldState.close_world()
	get_tree().reload_current_scene()


func _process(delta: float) -> void:
	if not _world_ready:
		if chunk_manager.running:
			_report_loading(WARMUP_SHARE + (1.0 - WARMUP_SHARE) * chunk_manager.initial_progress(), "Строим мир…")
		return
	WorldState.camera_state = camera_rig.get_state()
	_watch_performance(delta)
	if _preloading_models:
		_preloading_models = ModelLibrary.preload_step()
	_autosave -= delta
	if _autosave <= 0.0:
		_autosave = AUTOSAVE_INTERVAL_WEB if Platform.is_web else AUTOSAVE_INTERVAL
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
