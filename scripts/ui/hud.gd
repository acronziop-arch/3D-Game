class_name Hud
extends CanvasLayer
## Игровой интерфейс. Собирается кодом из стилей UiStyle:
##   слева сверху — основные ресурсы, кнопка «…» со списком всех ресурсов и мини-карта;
##   справа сверху — часы, сезон, погода и шестерёнка настроек;
##   снизу — текущее действие, меню стройки и панель инструментов;
##   справа снизу — кнопки действий текущего инструмента (построить, повернуть…);
##   окна (ремесло, все ресурсы, карта, настройки) открываются по одному.
## На телефоне (Platform.is_touch) всё компактнее и не заходит под вырез экрана.
## Тройное касание двумя пальцами (на ПК — H) прячет весь интерфейс.

## Выход на стартовый экран (кнопка «В главное меню» в настройках).
signal menu_requested
signal markers_changed

const LOADING_TIPS := [
	"Срубите пару деревьев и постройте лесопилку — из брёвен выйдут доски.",
	"Два пальца вверх-вниз наклоняют камеру, щипок — приближает.",
	"Три быстрых касания двумя пальцами прячут интерфейс.",
	"В настройках есть раздел «Управление» с подсказками.",
	"Ставьте метки на карте, чтобы не потерять свои деревни.",
	"Огонь гаснет под дождём и на сильном ветру.",
]

const GROUPS := [["raw", "Сырьё"], ["animal", "Из сундуков"], ["processed", "Материалы"]]
const TOOLS := [
	[Interaction.Tool.HARVEST, "tool_harvest", "Добыча", "1"],
	[Interaction.Tool.BUILD, "tool_build", "Стройка", "2"],
	[Interaction.Tool.FLATTEN, "tool_flatten", "Ровнять", "3"],
	[Interaction.Tool.NATURE, "tool_nature", "Природа", "4"],
	[Interaction.Tool.EDIT, "tool_edit", "Правка", "5"],
]
const NATURE_ICONS := {"mow": "mow", "grass": "grass_short", "tall": "grass_tall", "flowers": "flower"}
const NATURE_SHORT := {"mow": "Косить", "grass": "Трава", "tall": "Высокая", "flowers": "Цветы"}
## Ширина колонки кнопок действий (вместе с отступом).
const ACTIONS_WIDTH := 74.0

var interaction: Interaction
var thumbnails: Thumbnails

var _touch := false
var _ui_hidden := false
var _root: Control
var _labels: WorldLabels
var _bottom: VBoxContainer
var _top_left: VBoxContainer
var _resource_bar: PanelContainer
var _main_counts := {}
var _all_panel: PanelContainer
var _all_counts := {}
var _minimap: Minimap
var _map_frame: Control
var _map_panel: MapPanel
var _clock_row: HBoxContainer
var _clock_time: Label
var _clock_icon: TextureRect
var _season_icon: TextureRect
var _weather_icon: TextureRect
var _clock_sub: Label
var _settings: SettingsDialog
var _tool_buttons := {}
var _build_panel: PanelContainer
var _category_buttons := {}
var _build_grid: Container
var _build_scroll: SmoothScroll
var _build_cards := {}
var _card_styles := {}
var _category := "production"
## Открыта ли лента зданий (на ПК — меню стройки).
var _drawer_open := false
var _craft_panel: PanelContainer
var _craft_scroll: SmoothScroll
var _craft_rows := {}
var _drops: ScreenDrops
var _wipe: WorldWipe
## Очередь ремесла, которая сейчас нарисована (чтобы не пересобирать её без нужды).
var _craft_queue_key := "-"
var _craft_progress: ProgressBar
var _craft_queue: HBoxContainer
var _craft_queue_scroll: SmoothScroll
var _craft_status: Label
var _job_panel: PanelContainer
var _job_icon: TextureRect
var _job_label: Label
var _job_bar: ProgressBar
var _hover_panel: PanelContainer
var _hover_label: RichTextLabel
var _hint_panel: PanelContainer
var _hint_label: RichTextLabel
var _actions: GridContainer
var _actions_key := ""
## Состояние кнопок, которое меняется без пересборки (режим природы, высота, культура).
var _actions_state := ""
var _action_refreshers: Array[Callable] = []
var _action_styles := {}
var _rotate_hold: Button
var _hint_max_width := 600.0
var _notices: Notices
var _loading: Control
var _loading_bar: ProgressBar
var _loading_text: Label
var _portrait_hint: Control
var _info_timer := 0.0


func _ready() -> void:
	_touch = Platform.is_touch
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiStyle.make_theme()
	# Иконки — картинки 128 px: при уменьшении берутся мип-уровни, без ряби.
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_root)
	thumbnails = Thumbnails.new()
	add_child(thumbnails)
	thumbnails.thumbnail_ready.connect(_on_thumbnail)
	# Капли дождя и снежинки на экране — под всем интерфейсом.
	_drops = ScreenDrops.new()
	_root.add_child(_drops)
	# Надписи над миром — самый нижний слой интерфейса.
	_labels = WorldLabels.new()
	_root.add_child(_labels)

	_bottom = VBoxContainer.new()
	_bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_theme_constant_override("separation", _px(10, 6))
	_root.add_child(_bottom)

	_build_resources()
	_build_clock()
	_build_job_panel()
	_build_build_panel()
	_build_hint()
	_build_toolbar()
	_build_actions()
	_build_craft_panel()
	if not _touch:
		_build_hover()
	_map_panel = MapPanel.new()
	_root.add_child(_map_panel)
	_map_panel.markers_changed.connect(func() -> void: markers_changed.emit())
	_settings = SettingsDialog.new()
	_root.add_child(_settings)
	_settings.save_requested.connect(func() -> void:
		show_message("Мир сохранён" if WorldState.save_game() else "Не удалось сохранить"))
	_settings.menu_requested.connect(func() -> void: menu_requested.emit())
	# Время, сезон и погода из настроек меняются сразу — за косой чёрной полосой.
	_wipe = WorldWipe.new()
	add_child(_wipe)
	Settings.changed.connect(func(key: String) -> void:
		if key in ["time_mode", "season_mode", "weather_mode"] and Settings.get_value(key) != "auto":
			_wipe.play(Weather.snap_to_settings))
	# Сообщения — поверх всех окон, чтобы их было видно и при открытых настройках.
	_build_toast()
	_build_loading()
	if _touch:
		_build_portrait_hint()
	Inventory.changed.connect(_on_inventory_changed)
	Crafting.queue_changed.connect(_refresh_crafting)
	Crafting.crafted.connect(func(id: String) -> void: show_message("Готово: %s" % GameData.RECIPES[id]["name"]))
	GameMode.mode_changed.connect(func() -> void:
		_refresh_build_cards()
		_refresh_crafting())
	Weather.weather_changed.connect(func(_id: String) -> void: show_message("Погода: %s" % Weather.weather_name()))
	Weather.season_changed.connect(func(_i: int) -> void: show_message("Наступает %s" % Weather.season_name().to_lower()))
	_on_inventory_changed("")
	thumbnails.request(GameData.BUILDINGS.keys())
	Platform.layout_changed.connect(_apply_layout)
	_apply_layout.call_deferred()


## Подготовка под экраном загрузки (шаги для ShaderWarmup): каждое окно один кадр
## рисуется целиком — текст раскладывается, буквы нужных размеров попадают в кэш шрифта,
## значки и рамки — в видеопамять; собираются шейдеры капель и смены погоды. Тогда
## первое открытие окна в игре не подтормаживает.
func warmup_steps() -> Array[Callable]:
	var steps: Array[Callable] = []
	var panels: Array[Control] = [_build_panel, _craft_panel, _all_panel, _settings, _map_panel]
	for i in panels.size() + 1:
		steps.append(func() -> Variant:
			if i > 0:
				_warm_panel(panels[i - 1], false)
			if i < panels.size():
				_warm_panel(panels[i], true)
			return null)
	steps.append(func() -> Variant:
		_drops.warm()
		_wipe.warm()
		return null)
	return steps


func _warm_panel(panel: Control, shown: bool) -> void:
	if panel == _build_panel:
		# Все карточки сразу, а не только открытой вкладки.
		for id: String in _build_cards:
			_build_cards[id]["button"].visible = shown or GameData.BUILDINGS[id]["category"] == _category
	elif panel == _settings and shown:
		_settings.open()
	elif panel == _map_panel and shown:
		_map_panel.open()
	UiStyle.fade_now(panel, shown)
	if panel == _craft_panel and shown:
		_refresh_crafting()


func bind(target: Interaction) -> void:
	interaction = target
	interaction.tool_changed.connect(_on_tool_changed)
	interaction.message.connect(show_message)
	interaction.hover_changed.connect(_on_hover_changed)
	# Режим, высота, культура: кнопки обновляются на месте (набор сверяет _update_actions).
	interaction.options_changed.connect(func() -> void: _actions_state = "")
	interaction.building_system.placed.connect(func(_b: Building) -> void: _refresh_build_cards())
	_minimap.chunk_manager = interaction.chunk_manager
	_minimap.camera_rig = interaction.camera_rig
	_minimap.building_system = interaction.building_system
	_map_panel.setup(interaction.chunk_manager, interaction.camera_rig, interaction.building_system)
	_on_tool_changed(interaction.tool)


## Размер для ПК или для телефона.
func _px(pc: float, touch: float) -> float:
	return touch if _touch else pc


func is_modal_open() -> bool:
	return _settings.is_open() or _map_panel.is_open()


## Окна открываются по одному: открытие одного закрывает остальные
## (меню стройки — тоже окно).
func _close_panels(except := "") -> void:
	if except != "drawer" and _drawer_open:
		_set_drawer(false)
	if except != "settings" and _settings.is_open():
		_settings.close()
	if except != "map" and _map_panel.is_open():
		_map_panel.close()
	if except != "craft" and _craft_panel.get_meta("fade_target", false):
		UiStyle.fade(_craft_panel, false)
	if except != "resources" and _all_panel.get_meta("fade_target", false):
		UiStyle.fade(_all_panel, false)


func open_settings() -> void:
	_close_panels("settings")
	_settings.open()


func open_map() -> void:
	_close_panels("map")
	_map_panel.open()


func toggle_resources() -> void:
	var show: bool = not _all_panel.get_meta("fade_target", false)
	if show:
		_close_panels("resources")
	UiStyle.fade(_all_panel, show)


func toggle_crafting() -> void:
	var show: bool = not _craft_panel.get_meta("fade_target", false)
	if show:
		_close_panels("craft")
	UiStyle.fade(_craft_panel, show)
	_refresh_crafting()
	if _touch and not _hint_panel.has_meta("flash"):
		_on_hover_changed(str(_hint_panel.get_meta("current", "")))


## Закрывает верхнее открытое окно (кнопка «Назад» на Android). false — закрывать нечего.
func close_top_panel() -> bool:
	if _settings.is_open():
		_settings.close()
	elif _map_panel.is_open():
		_map_panel.close()
	elif _all_panel.get_meta("fade_target", false):
		UiStyle.fade(_all_panel, false)
	elif _craft_panel.get_meta("fade_target", false):
		toggle_crafting()
	elif _drawer_open and interaction.building_system.selected_id != "":
		_set_drawer(false)
	else:
		return false
	return true


## Прячет весь интерфейс, оставляя только мир (и возвращает его).
func toggle_ui_hidden() -> void:
	_ui_hidden = not _ui_hidden
	_close_panels()
	for c in _root.get_children():
		if c == _notices or c == _loading or c == _portrait_hint:
			continue
		var target := 0.0 if _ui_hidden else 1.0
		if c is Control:
			var ctl := c as Control
			if not _ui_hidden and ctl.has_meta("was_hidden"):
				ctl.remove_meta("was_hidden")
				continue
			if _ui_hidden and not ctl.visible:
				ctl.set_meta("was_hidden", true)
				continue
			ctl.visible = true
			var tw := ctl.create_tween()
			tw.tween_property(ctl, "modulate:a", target, 0.25)
			if _ui_hidden:
				tw.tween_callback(ctl.hide)
	if _ui_hidden:
		show_message("Меню скрыто — %s, чтобы вернуть" % ("трижды коснитесь экрана двумя пальцами" if _touch else "нажмите H"))


func is_ui_hidden() -> bool:
	return _ui_hidden


## Расставляет панели с учётом безопасной зоны экрана (вырез и полоска «домой» на iPhone).
func _apply_layout() -> void:
	var m := Platform.safe_margins() if _touch else {"left": 16.0, "top": 16.0, "right": 16.0, "bottom": 16.0}
	var vp := _root.get_viewport_rect().size
	# Панели привязаны к углам; смещения задаём от угла, остальное растёт само.
	_pin(_top_left, m["left"], m["top"], m["left"], m["top"])
	_pin(_clock_row, -m["right"], m["top"], -m["right"], m["top"])
	_pin(_bottom, 0.0, -m["bottom"], 0.0, -m["bottom"])
	_pin(_actions, -m["right"], -m["bottom"], -m["right"], -m["bottom"])
	# Сообщения — по центру под верхней строкой, не шире промежутка между
	# мини-картой и часами.
	var toast_y: float = m["top"] + _resource_bar.get_combined_minimum_size().y + 10.0
	_notices.position.y = toast_y
	_hint_max_width = minf(vp.x - 2.0 * (maxf(m["left"], m["right"]) + ACTIONS_WIDTH + 12.0), 720.0)
	var below_bar: float = m["top"] + _resource_bar.get_combined_minimum_size().y + 8.0
	_pin(_all_panel, m["left"], below_bar, m["left"], below_bar)
	var all_room: float = vp.y - below_bar - m["bottom"] - 60.0
	var all_scroll := _all_panel.find_child("Scroll", true, false) as SmoothScroll
	all_scroll.custom_minimum_size.y = minf(all_scroll.content().get_combined_minimum_size().y, all_room)
	var side := maxf(m["left"], m["right"]) + ACTIONS_WIDTH
	_build_panel.custom_minimum_size.x = minf(maxf(vp.x - side * 2.0, 360.0), 1000.0)
	# Ремесло — справа, под часами: центр экрана остаётся для сообщений.
	var craft_top: float = m["top"] + _clock_row.get_combined_minimum_size().y + 10.0
	_pin(_craft_panel, -m["right"], craft_top, -m["right"], craft_top)
	_craft_panel.custom_minimum_size.x = minf(_px(480, 440), vp.x - m["left"] - m["right"] - _minimap.custom_minimum_size.x - 40.0)
	# Снизу оставляем место панели инструментов и строке подсказки.
	# На телефоне строка подсказки на это время прячется (см. _on_hover_changed).
	var craft_room: float = vp.y - craft_top - m["bottom"] - _px(92, 80) - _px(48, 0) - _px(120, 76)
	_craft_scroll.custom_minimum_size.y = clampf(_craft_scroll.content().get_combined_minimum_size().y, 80.0, maxf(craft_room, 80.0))
	if _portrait_hint:
		# Браузер на телефоне не умеет закрепить альбомную ориентацию — просим повернуть.
		_portrait_hint.visible = vp.x < vp.y


## Смещения краёв от точек привязки; размер дорастает до минимального сам
## (в сторону, заданную grow_horizontal / grow_vertical).
static func _pin(c: Control, left: float, top: float, right: float, bottom: float) -> void:
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom


# --- Ресурсы и мини-карта ----------------------------------------------------------------------

func _build_resources() -> void:
	# Слева сверху: ресурсы, под ними — мини-карта.
	_top_left = VBoxContainer.new()
	_top_left.add_theme_constant_override("separation", _px(10, 8))
	_top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_top_left)
	_resource_bar = PanelContainer.new()
	_resource_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if _touch:
		_resource_bar.add_theme_stylebox_override("panel", UiStyle.panel(14, 9))
	_top_left.add_child(_resource_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(14, 9))
	_resource_bar.add_child(row)
	for id: String in GameData.MAIN_RESOURCES:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", _px(5, 3))
		item.tooltip_text = GameData.res_name(id)
		item.mouse_filter = Control.MOUSE_FILTER_PASS
		item.add_child(UiStyle.icon_rect(id, _px(30, 24)))
		var count := UiStyle.label("0", _px(18, 15), UiStyle.TEXT, 800)
		count.custom_minimum_size = Vector2(_px(30, 24), 0)
		item.add_child(count)
		row.add_child(item)
		_main_counts[id] = count
		if _touch:
			# Подсказок при наведении на телефоне нет — название показываем по нажатию.
			item.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed:
					show_message("%s: %s" % [GameData.res_name(id), _count_text(id)]))
	var more := Button.new()
	more.icon = UiStyle.icon("more")
	more.add_theme_constant_override("icon_max_width", _px(22, 20))
	more.custom_minimum_size = Vector2(_px(40, 42), _px(34, 30))
	more.tooltip_text = "Все ресурсы"
	more.pressed.connect(toggle_resources)
	row.add_child(more)

	# Мини-карта под ресурсами: скруглённый квадрат, карта заполняет его целиком
	# и обрезана ровно по скруглению; по нажатию — большая карта.
	var map_frame := PanelContainer.new()
	_map_frame = map_frame
	var radius := int(_px(18, 14))
	var frame_style := UiStyle.box(Color(UiStyle.BASE, 0.97), radius, 0, 0, UiStyle.BRAND, true)
	map_frame.add_theme_stylebox_override("panel", frame_style)
	map_frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_top_left.add_child(map_frame)
	_minimap = Minimap.new()
	var side := _px(150, 96)
	_minimap.custom_minimum_size = Vector2(side, side)
	_minimap.view_meters = 220.0
	_minimap.corner_radius = radius
	_minimap.tooltip_text = "Карта [Tab]"
	_minimap.tapped.connect(func(_p: Vector2) -> void: open_map())
	map_frame.add_child(_minimap)

	_all_panel = PanelContainer.new()
	_all_panel.visible = false
	_all_panel.modulate.a = 0.0
	_root.add_child(_all_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_all_panel.add_child(outer)
	var title := HBoxContainer.new()
	var title_label := UiStyle.label("Все ресурсы", _px(18, 16), UiStyle.TEXT, 800)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(title_label)
	var close := UiStyle.close_button(_px(38, 40))
	close.pressed.connect(func() -> void: UiStyle.fade(_all_panel, false))
	title.add_child(close)
	outer.add_child(title)
	var scroll := SmoothScroll.new()
	scroll.name = "Scroll"
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _px(6, 4))
	scroll.add_child(box)
	for group: Array in GROUPS:
		box.add_child(UiStyle.label(group[1], _px(13, 12), UiStyle.BRAND_DARK, 800))
		var grid := GridContainer.new()
		grid.columns = int(_px(3, 4))
		grid.add_theme_constant_override("h_separation", _px(18, 12))
		grid.add_theme_constant_override("v_separation", _px(4, 2))
		for id: String in GameData.RESOURCES:
			if GameData.RESOURCES[id]["group"] != group[0]:
				continue
			var item := HBoxContainer.new()
			item.add_theme_constant_override("separation", 6)
			item.custom_minimum_size = Vector2(_px(190, 150), _px(34, 30))
			item.add_child(UiStyle.icon_rect(id, _px(30, 26)))
			item.add_child(UiStyle.label(GameData.res_name(id), _px(15, 13), UiStyle.TEXT, 600))
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item.add_child(spacer)
			var count := UiStyle.label("0", _px(15, 13), UiStyle.TEXT, 800)
			item.add_child(count)
			grid.add_child(item)
			_all_counts[id] = count
		box.add_child(grid)


func _count_text(id: String) -> String:
	return "∞" if GameMode.is_creative() else str(Inventory.count(id))


func _on_inventory_changed(res_id: String) -> void:
	var ids: Array = GameData.RESOURCES.keys() if res_id == "" else [res_id]
	for id: String in ids:
		var n := Inventory.count(id)
		for map: Dictionary in [_main_counts, _all_counts]:
			if not map.has(id):
				continue
			var l: Label = map[id]
			l.text = _count_text(id)
			l.add_theme_color_override("font_color", UiStyle.TEXT if n > 0 or GameMode.is_creative() else UiStyle.MUTED)
			if res_id != "":
				l.pivot_offset = l.size * 0.5
				l.scale = Vector2.ONE * 1.35
				l.create_tween().tween_property(l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_build_cards()
	_refresh_crafting()


# --- Часы, погода и настройки ------------------------------------------------------------------

func _build_clock() -> void:
	_clock_row = HBoxContainer.new()
	_clock_row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_clock_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_clock_row.add_theme_constant_override("separation", _px(10, 8))
	_clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_clock_row)
	var clock := PanelContainer.new()
	if _touch:
		clock.add_theme_stylebox_override("panel", UiStyle.panel(14, 9))
		# На телефоне строка «сезон · погода · биом» спрятана — она появляется по нажатию.
		clock.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed:
				show_message(_clock_sub.text))
	_clock_row.add_child(clock)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	clock.add_child(box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", _px(8, 6))
	_clock_icon = UiStyle.icon_rect("clock_day", _px(26, 22))
	line.add_child(_clock_icon)
	_clock_time = UiStyle.label("12:00", _px(20, 17), UiStyle.TEXT, 800)
	line.add_child(_clock_time)
	_season_icon = UiStyle.icon_rect("season_summer", _px(24, 21))
	line.add_child(_season_icon)
	_weather_icon = UiStyle.icon_rect("weather_clear", _px(26, 22))
	line.add_child(_weather_icon)
	box.add_child(line)
	_clock_sub = UiStyle.label("", 13, UiStyle.MUTED, 700)
	_clock_sub.visible = not _touch
	box.add_child(_clock_sub)
	var gear := Button.new()
	gear.icon = UiStyle.icon("settings")
	gear.add_theme_constant_override("icon_max_width", _px(28, 24))
	gear.custom_minimum_size = Vector2.ONE * _px(52, 44)
	gear.add_theme_stylebox_override("normal", UiStyle.panel(16, 10))
	gear.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.BASE, 16, 10, 3, UiStyle.BRAND_DARK, true))
	gear.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.SURFACE_HOVER, 16, 10, 2, UiStyle.BRAND_DARK, true))
	gear.tooltip_text = "Настройки"
	gear.pressed.connect(open_settings)
	_clock_row.add_child(gear)


func _update_clock() -> void:
	_clock_time.text = Weather.clock_text()
	_clock_icon.texture = UiStyle.icon("clock_day" if Weather.daylight() > 0.5 else "clock_night")
	_season_icon.texture = UiStyle.icon("season_" + Weather.SEASONS[Weather.season_index()]["id"])
	_weather_icon.texture = UiStyle.icon("weather_" + Weather.weather)
	var biome := ""
	if interaction:
		var p := interaction.camera_rig.global_position
		biome = interaction.chunk_manager.get_biome_name(p.x, p.z)
	_clock_sub.text = "%s · %s · %s" % [Weather.season_name(), Weather.weather_name(), biome]


# --- Панель инструментов ------------------------------------------------------------------------

func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("panel", UiStyle.panel(_px(20, 18), _px(10, 6)))
	_bottom.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(8, 4))
	bar.add_child(row)
	for t: Array in TOOLS:
		var b := _tool_button(t[1], t[2], t[3])
		b.toggle_mode = true
		b.pressed.connect(func() -> void:
			# Повторное нажатие «Стройки» открывает и закрывает меню зданий.
			if t[0] == Interaction.Tool.BUILD and interaction.tool == Interaction.Tool.BUILD and not interaction.building_system.moving:
				_set_drawer(not _drawer_open)
				b.set_pressed_no_signal(true)
				return
			interaction.set_tool(t[0]))
		row.add_child(b)
		_tool_buttons[t[0]] = b
	var sep := VSeparator.new()
	sep.add_theme_stylebox_override("separator", UiStyle.box(UiStyle.BRAND, 1, 0))
	row.add_child(sep)
	var craft := _tool_button("tool_craft", "Ремесло", "C")
	craft.pressed.connect(toggle_crafting)
	row.add_child(craft)


func _tool_button(icon_name: String, text: String, hotkey: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(_px(86, 62), _px(74, 54))
	b.tooltip_text = "%s [%s]" % [text, hotkey]
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", _px(2, 1))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UiStyle.icon_rect(icon_name, _px(36, 28))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ic)
	var l := UiStyle.label(text, _px(13, 11), UiStyle.TEXT, 700)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	b.add_child(box)
	if not _touch:
		var key := UiStyle.label(hotkey, 11, UiStyle.BRAND_DARK, 800)
		key.position = Vector2(6, 3)
		b.add_child(key)
	return b


func _on_tool_changed(tool: Interaction.Tool) -> void:
	for t in _tool_buttons:
		_tool_buttons[t].set_pressed_no_signal(t == tool)
	var bs := interaction.building_system
	# Меню зданий открыто, пока здание не выбрано (на ПК — всю стройку).
	if tool == Interaction.Tool.BUILD and bs.moving == null:
		_set_drawer(bs.selected_id == "" or not _touch)
	else:
		_set_drawer(false)
	_actions_key = ""


func _set_drawer(open: bool) -> void:
	if open and not _drawer_open:
		_close_panels("drawer")
	_drawer_open = open
	UiStyle.fade(_build_panel, open)
	if open:
		_refresh_build_cards()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_crafting"):
		toggle_crafting()
	elif event.is_action_pressed("toggle_map"):
		if _map_panel.is_open():
			_map_panel.close()
		else:
			open_map()
	elif event.is_action_pressed("hide_ui"):
		toggle_ui_hidden()
	elif event.is_action_pressed("quick_save"):
		show_message("Мир сохранён" if WorldState.save_game() else "Не удалось сохранить")
	elif event.is_action_pressed("cancel") and (_all_panel.get_meta("fade_target", false) or _craft_panel.get_meta("fade_target", false)):
		_close_panels()
		get_viewport().set_input_as_handled()


# --- Меню стройки ---------------------------------------------------------------------------------

func _build_build_panel() -> void:
	_build_panel = PanelContainer.new()
	_build_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_build_panel.custom_minimum_size = Vector2(980, 0)
	_build_panel.visible = false
	_build_panel.modulate.a = 0.0
	_build_panel.add_theme_stylebox_override("panel", UiStyle.panel(16, int(_px(10, 8))))
	_bottom.add_child(_build_panel)
	# Фон меню: контурные рисунки фирменным цветом.
	var doodles := Doodles.new()
	doodles.line_width = _px(2.0, 1.6)
	_build_panel.add_child(doodles)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _px(10, 6))
	_build_panel.add_child(box)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", _px(6, 4))
	var group := ButtonGroup.new()
	for cat: String in GameData.BUILDING_CATEGORIES:
		var b := Button.new()
		b.text = GameData.BUILDING_CATEGORIES[cat]
		b.icon = UiStyle.icon("cat_" + cat)
		b.add_theme_constant_override("icon_max_width", _px(22, 18))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = cat == _category
		b.custom_minimum_size = Vector2(0, _px(38, 34))
		# На ПК вкладки делят ширину поровну; на телефоне они своей ширины
		# и листаются вбок, чтобы названия не обрезались.
		if not _touch:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.clip_text = true
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.add_theme_font_size_override("font_size", int(_px(14, 12)))
		b.pressed.connect(func() -> void:
			_category = cat
			_build_scroll.reset()
			_refresh_build_cards())
		tabs.add_child(b)
		_category_buttons[cat] = b
	if _touch:
		var tab_scroll := SmoothScroll.new()
		tab_scroll.horizontal = true
		tab_scroll.bar_room = 8.0
		tab_scroll.add_child(tabs)
		box.add_child(tab_scroll)
	else:
		box.add_child(tabs)
	# Лента карточек листается пальцем или колесом вбок.
	_build_scroll = SmoothScroll.new()
	_build_scroll.horizontal = true
	_build_scroll.bar_room = 8.0
	_build_scroll.custom_minimum_size = Vector2(0, _px(176, 140) + 8.0)
	_build_grid = HBoxContainer.new()
	_build_grid.add_theme_constant_override("separation", _px(8, 6))
	box.add_child(_build_scroll)
	_build_scroll.add_child(_build_grid)
	# Карточки чуть прозрачные — сквозь них виден рисунок фона меню.
	_card_styles = {
		"normal": UiStyle.box(Color(UiStyle.SURFACE, 0.72), 14, 8),
		"selected": UiStyle.box(UiStyle.BRAND.lightened(0.35), 14, 8, 2, UiStyle.BRAND_DARK),
		"disabled": UiStyle.box(Color(UiStyle.SURFACE, 0.55), 14, 8),
	}
	for id: String in GameData.BUILDINGS:
		_build_cards[id] = _make_card(id)
		_build_grid.add_child(_build_cards[id]["button"])


func _make_card(id: String) -> Dictionary:
	var def: Dictionary = GameData.BUILDINGS[id]
	var w := _px(160, 116)
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, _px(172, 136))
	b.tooltip_text = def["desc"]
	b.clip_contents = true
	# Иначе лента не листается, если палец начал движение на карточке.
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.pressed.connect(func() -> void:
		interaction.start_building(id)
		Platform.haptic(0.2))
	b.gui_input.connect(func(e: InputEvent) -> void:
		# Недоступная карточка: сразу говорим, чего не хватает.
		if b.disabled and e is InputEventMouseButton and not (e as InputEventMouseButton).pressed:
			show_message("Не хватает: %s" % Rich.cost(Inventory.missing(def["cost"]))))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 6
	box.offset_right = -6
	box.offset_top = 4
	box.offset_bottom = -4
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(0, _px(84, 58))
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.texture = thumbnails.texture_for(id, UiStyle.icon("cat_" + def["category"]))
	box.add_child(thumb)
	var title := UiStyle.label(def["name"], _px(14, 12), UiStyle.TEXT, 800)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.custom_minimum_size.x = w - 14.0
	box.add_child(title)
	var time_row := HBoxContainer.new()
	time_row.alignment = BoxContainer.ALIGNMENT_CENTER
	time_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_row.add_child(UiStyle.icon_rect("timer", _px(14, 12)))
	var time_label := UiStyle.label("%d с" % def["time"], _px(12, 11), UiStyle.MUTED, 700)
	time_row.add_child(time_label)
	box.add_child(time_row)
	# Стоимость переносится на вторую строку, если не влезает в карточку.
	var cost := HFlowContainer.new()
	cost.alignment = FlowContainer.ALIGNMENT_CENTER
	cost.add_theme_constant_override("h_separation", 5)
	cost.add_theme_constant_override("v_separation", 0)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.custom_minimum_size.x = w - 14.0
	box.add_child(cost)
	# Строка стоимости собирается один раз; при обновлении меняется только цвет чисел.
	var cost_labels := {}
	for res: String in def["cost"]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 1)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(UiStyle.icon_rect(res, int(_px(16, 14))))
		var l := UiStyle.label(str(def["cost"][res]), int(_px(14, 12)), UiStyle.TEXT, 800)
		item.add_child(l)
		cost.add_child(item)
		cost_labels[res] = l
	if def["cost"].is_empty():
		cost.add_child(UiStyle.label("бесплатно", int(_px(13, 11)), UiStyle.MUTED, 800))
	b.add_theme_stylebox_override("normal", _card_styles["normal"])
	b.add_theme_stylebox_override("disabled", _card_styles["disabled"])
	return {"button": b, "thumb": thumb, "cost_labels": cost_labels, "time": time_label, "state": {}}


func _on_thumbnail(id: String, tex: Texture2D) -> void:
	if _build_cards.has(id):
		_build_cards[id]["thumb"].texture = tex


## Карточки меню стройки. Пока меню закрыто, ничего не делаем (ресурсы меняются часто —
## каждая добыча), а при открытии обновляем; меняются только цвета и подписи, без новых узлов.
func _refresh_build_cards() -> void:
	if _build_cards.is_empty():
		return
	if not _drawer_open:
		return
	var creative := GameMode.is_creative()
	for id: String in _build_cards:
		var def: Dictionary = GameData.BUILDINGS[id]
		var card: Dictionary = _build_cards[id]
		var b: Button = card["button"]
		b.visible = def["category"] == _category
		if not b.visible:
			continue
		var state: Dictionary = card["state"]
		var labels: Dictionary = card["cost_labels"]
		for res: String in labels:
			var enough := creative or Inventory.count(res) >= int(def["cost"][res])
			if state.get(res) != enough:
				state[res] = enough
				(labels[res] as Label).add_theme_color_override("font_color", UiStyle.TEXT if enough else UiStyle.BAD)
		var affordable := Inventory.has_all(def["cost"])
		var time_label: Label = card["time"]
		# Чего не хватает — видно прямо на карточке, а выбрать её нельзя.
		time_label.text = ("сразу" if creative or def["time"] <= 0.0 else "%d с" % ceili(def["time"])) if affordable else "Не хватает"
		if state.get("affordable") != affordable:
			state["affordable"] = affordable
			time_label.add_theme_color_override("font_color", UiStyle.MUTED if affordable else UiStyle.BAD)
			b.disabled = not affordable
			b.modulate = Color.WHITE if affordable else Color(1, 1, 1, 0.62)
		var selected := interaction != null and interaction.building_system.selected_id == id
		if state.get("selected") != selected:
			state["selected"] = selected
			b.add_theme_stylebox_override("normal", _card_styles["selected" if selected else "normal"])


# --- Ремесло --------------------------------------------------------------------------------------

func _build_craft_panel() -> void:
	_craft_panel = PanelContainer.new()
	_craft_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_craft_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_craft_panel.custom_minimum_size = Vector2(_px(480, 440), 0)
	_craft_panel.add_theme_stylebox_override("panel", UiStyle.panel(16, int(_px(14, 10))))
	_craft_panel.visible = false
	_craft_panel.modulate.a = 0.0
	_root.add_child(_craft_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _px(8, 6))
	_craft_panel.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.add_child(UiStyle.icon_rect("tool_craft", _px(28, 22)))
	var title := UiStyle.label("Ремесло", _px(22, 17), UiStyle.TEXT, 800)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	# Очередь: одинаковые рецепты складываются в «×N», длинная очередь листается вбок,
	# а ширина окна от неё не меняется.
	var queue_row := HBoxContainer.new()
	queue_row.add_theme_constant_override("separation", 6)
	_craft_status = UiStyle.label("", _px(13, 12), UiStyle.MUTED, 700)
	queue_row.add_child(_craft_status)
	_craft_queue_scroll = SmoothScroll.new()
	_craft_queue_scroll.horizontal = true
	_craft_queue_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_queue_scroll.custom_minimum_size = Vector2(10, 26)
	queue_row.add_child(_craft_queue_scroll)
	_craft_queue = HBoxContainer.new()
	_craft_queue.add_theme_constant_override("separation", 5)
	_craft_queue_scroll.add_child(_craft_queue)
	var close := UiStyle.close_button(_px(38, 36))
	close.pressed.connect(toggle_crafting)
	if _touch:
		# На телефоне высоты мало: очередь — в одной строке с заголовком, чтобы
		# под ней поместилось больше рецептов.
		title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		queue_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(queue_row)
		header.add_child(close)
		box.add_child(header)
	else:
		header.add_child(close)
		box.add_child(header)
		box.add_child(queue_row)
	_craft_progress = ProgressBar.new()
	_craft_progress.max_value = 1.0
	_craft_progress.step = 0.0
	_craft_progress.show_percentage = false
	_craft_progress.custom_minimum_size = Vector2(0, _px(8, 5))
	box.add_child(_craft_progress)
	_craft_scroll = SmoothScroll.new()
	box.add_child(_craft_scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", _px(6, 5))
	_craft_scroll.add_child(rows)
	for id: String in GameData.RECIPES:
		var r: Dictionary = GameData.RECIPES[id]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.SURFACE, 12, int(_px(8, 4))))
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		row.add_child(line)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2 if not _touch else 0)
		var formula := HBoxContainer.new()
		formula.add_theme_constant_override("separation", 6)
		var ins := UiStyle.cost_row(r["in"], int(_px(20, 18)))
		var in_labels := {}
		var k := 0
		for res: String in r["in"]:
			in_labels[res] = ins.get_child(k).get_child(1)
			k += 1
		formula.add_child(ins)
		formula.add_child(UiStyle.icon_rect("arrow", 18))
		formula.add_child(UiStyle.cost_row(r["out"], int(_px(20, 18)), false))
		info.add_child(formula)
		var sub := UiStyle.label("", 12 if not _touch else 11, UiStyle.MUTED, 700)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(sub)
		line.add_child(info)
		var b := Button.new()
		b.text = "Сделать"
		b.custom_minimum_size = Vector2(_px(96, 88), _px(36, 34))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.pressed.connect(func() -> void:
			var reason := Crafting.enqueue(id)
			if reason != "":
				show_message(reason)
			else:
				Platform.haptic(0.3))
		line.add_child(b)
		rows.add_child(row)
		_craft_rows[id] = {"button": b, "sub": sub, "in_labels": in_labels, "state": {}}


## Окно ремесла. Как и меню стройки, обновляется, только когда открыто, и без новых
## узлов: меняются подписи и цвета. Очередь пересобирается, только если она изменилась.
func _refresh_crafting() -> void:
	if _craft_rows.is_empty():
		return
	if not _craft_panel.get_meta("fade_target", false):
		return
	for id: String in _craft_rows:
		var r: Dictionary = GameData.RECIPES[id]
		var row: Dictionary = _craft_rows[id]
		var state: Dictionary = row["state"]
		var reason := Crafting.check(id)
		var station: String = GameData.BUILDINGS[r["station"]]["name"]
		var time_text := "сразу" if GameMode.is_creative() else "%d с" % r["time"]
		row["sub"].text = "%s · %s%s" % [station, time_text, "" if reason == "" else " · " + reason]
		if state.get("ok") != (reason == ""):
			state["ok"] = reason == ""
			row["sub"].add_theme_color_override("font_color", UiStyle.MUTED if reason == "" else UiStyle.BAD)
			row["button"].disabled = reason != ""
		var labels: Dictionary = row["in_labels"]
		for res: String in labels:
			var enough := Inventory.count(res) >= int(r["in"][res])
			if state.get(res) != enough:
				state[res] = enough
				(labels[res] as Label).add_theme_color_override("font_color", UiStyle.TEXT if enough else UiStyle.BAD)
	var groups := Crafting.grouped()
	var key := str(groups)
	if key == _craft_queue_key:
		return
	_craft_queue_key = key
	for c in _craft_queue.get_children():
		c.queue_free()
	if groups.is_empty():
		_craft_status.text = "Очередь пуста"
	else:
		_craft_status.text = "В работе:"
		for g: Dictionary in groups:
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.SURFACE, 10, 4, 1, UiStyle.BRAND))
			chip.mouse_filter = Control.MOUSE_FILTER_PASS
			var chip_row := HBoxContainer.new()
			chip_row.add_theme_constant_override("separation", 3)
			chip_row.add_child(UiStyle.icon_rect(GameData.RECIPES[g["id"]]["out"].keys()[0], 16))
			var text: String = GameData.RECIPES[g["id"]]["name"]
			if g["count"] > 1:
				text += " ×%d" % g["count"]
			chip_row.add_child(UiStyle.label(text, 12, UiStyle.TEXT, 800))
			chip.add_child(chip_row)
			_craft_queue.add_child(chip)


# --- Текущее действие, подсказки, сообщения ---------------------------------------------------------

func _build_job_panel() -> void:
	_job_panel = PanelContainer.new()
	_job_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_job_panel.custom_minimum_size = Vector2(_px(400, 320), 0)
	_job_panel.visible = false
	_job_panel.modulate.a = 0.0
	if _touch:
		_job_panel.add_theme_stylebox_override("panel", UiStyle.panel(14, 8))
	_bottom.add_child(_job_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(10, 8))
	_job_panel.add_child(row)
	_job_icon = UiStyle.icon_rect("tool_harvest", _px(32, 26))
	row.add_child(_job_icon)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", _px(4, 3))
	row.add_child(box)
	_job_label = UiStyle.label("", _px(15, 13), UiStyle.TEXT, 700)
	box.add_child(_job_label)
	_job_bar = ProgressBar.new()
	_job_bar.max_value = 1.0
	_job_bar.step = 0.0
	_job_bar.show_percentage = false
	_job_bar.custom_minimum_size = Vector2(0, _px(10, 8))
	box.add_child(_job_bar)


func _update_job_panel() -> void:
	var jobs := interaction.jobs
	UiStyle.fade(_job_panel, not jobs.is_empty())
	if jobs.is_empty():
		return
	var job: Dictionary = jobs[0]
	var verb := "Открываем" if job["kind"] == "chest" else "Добываем"
	var rest := "" if jobs.size() == 1 else "   +%d в очереди" % (jobs.size() - 1)
	_job_label.text = "%s: %s  %.1f / %.0f с%s" % [verb, job["name"], minf(job["elapsed"], job["time"]), job["time"], rest]
	if job["kind"] == "chest":
		_job_icon.texture = UiStyle.icon("hide")
	else:
		var drops: Dictionary = GameData.PROPS[job["prop"]["id"]].get("drops", {})
		_job_icon.texture = UiStyle.icon(drops.keys()[0] if not drops.is_empty() else "tool_harvest")
	_job_bar.value = interaction.current_job_fraction()


func _build_hover() -> void:
	_hover_panel = PanelContainer.new()
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(UiStyle.BASE, 0.97), 10, 9, 2, UiStyle.BRAND, true))
	_hover_panel.visible = false
	_root.add_child(_hover_panel)
	_hover_label = Rich.label(14)
	_hover_panel.add_child(_hover_label)


## Подсказка-плашка над панелью инструментов (на телефоне — вместо подсказки у курсора).
func _build_hint() -> void:
	_hint_panel = PanelContainer.new()
	_hint_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(UiStyle.BASE, 0.94), 12, 7, 2, UiStyle.BRAND, true))
	_hint_panel.visible = false
	_hint_panel.modulate.a = 0.0
	_bottom.add_child(_hint_panel)
	# Подсказка с разметкой: заголовок, значки ресурсов, клавиши и причина отказа.
	_hint_label = Rich.label(int(_px(15, 13)))
	_hint_panel.add_child(_hint_label)


func _on_hover_changed(text: String) -> void:
	if _touch:
		if _hint_panel.has_meta("flash"):
			# Сейчас в строке сообщение — подсказку покажем после него.
			_hint_panel.set_meta("normal_text", text)
			return
		_hint_panel.set_meta("current", text)
		if text != "":
			# Длинная подсказка переносится и не выходит за края экрана.
			Rich.fit(_hint_label, text, _hint_max_width)
			_hint_panel.reset_size()
		# Пока открыто ремесло, подсказка не нужна — место отдаём рецептам.
		UiStyle.fade(_hint_panel, text != "" and not _craft_panel.get_meta("fade_target", false), 0.2)
		return
	Rich.fit(_hover_label, text, 460.0, false)
	_hover_panel.reset_size()
	_hover_panel.visible = text != ""


# --- Кнопки действий ------------------------------------------------------------------------------

func _build_actions() -> void:
	# Колонка кнопок действий; если кнопок много и не хватает высоты — две колонки.
	_actions = GridContainer.new()
	_actions.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_actions.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_actions.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_actions.add_theme_constant_override("v_separation", 8)
	_actions.add_theme_constant_override("h_separation", 8)
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_actions)


func _action_button(icon_name: String, text: String, toggled := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(ACTIONS_WIDTH - 8.0, 58)
	if _action_styles.is_empty():
		# Обычный светлый цвет, как у всех кнопок: тёмная заливка выглядела «недоступной».
		_action_styles = {
			"normal": UiStyle.box(Color(UiStyle.BASE, 0.97), 18, 6, 2, UiStyle.BRAND, true),
			"toggled": UiStyle.box(UiStyle.BRAND.lightened(0.35), 18, 6, 2, UiStyle.BRAND_DARK, true),
			"hover": UiStyle.box(UiStyle.SURFACE_HOVER, 18, 6, 2, UiStyle.BRAND_DARK, true),
		}
	b.add_theme_stylebox_override("hover", _action_styles["hover"])
	b.add_theme_stylebox_override("pressed", _action_styles["hover"])
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UiStyle.icon_rect(icon_name, 26)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ic)
	var l := UiStyle.label(text, 11, UiStyle.TEXT, 800)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	b.add_child(box)
	b.set_meta("icon", ic)
	b.set_meta("label", l)
	_set_action_state(b, icon_name, text, toggled)
	_actions.add_child(b)
	return b


## Кнопка остаётся на месте, меняются только иконка, подпись и подсветка.
func _set_action_state(b: Button, icon_name: String, text: String, toggled: bool) -> void:
	(b.get_meta("icon") as TextureRect).texture = UiStyle.icon(icon_name)
	(b.get_meta("label") as Label).text = text
	b.add_theme_stylebox_override("normal", _action_styles["toggled" if toggled else "normal"])


## Кнопка, у которой подпись или подсветка зависят от состояния (режим природы,
## высота выравнивания, культура): state() -> [иконка, подпись, подсвечена ли].
func _state_button(state: Callable) -> Button:
	var st: Array = state.call()
	var b := _action_button(st[0], st[1], st[2])
	_action_refreshers.append(func() -> void:
		var now: Array = state.call()
		_set_action_state(b, now[0], now[1], now[2]))
	return b


## «Повернуть»: короткое нажатие — на 15°, удержание — плавно на любой угол.
func _rotate_button() -> Button:
	var b := _action_button("rotate", "Повернуть")
	b.button_down.connect(func() -> void:
		b.set_meta("held", 0.0)
		b.set_meta("spun", false))
	b.button_up.connect(func() -> void:
		if not b.get_meta("spun", false):
			interaction.rotate_building()
		b.remove_meta("held"))
	_rotate_hold = b
	return b


## Набор кнопок зависит от инструмента и выбора; пересобираем, только когда он меняется.
## Смена режима природы, высоты или культуры кнопки не пересоздаёт — они обновляются на месте.
func _update_actions() -> void:
	var bs := interaction.building_system
	var selected_crop: String = interaction.selected_building.crop if is_instance_valid(interaction.selected_building) else ""
	var key := "%d|%s|%s|%s|%s|%s|%s|%d" % [interaction.tool, bs.selected_id, bs.moving != null,
		is_instance_valid(interaction.selected_building), not interaction.jobs.is_empty(), _drawer_open,
		interaction.selected_building.get_instance_id() if is_instance_valid(interaction.selected_building) else 0,
		interaction.selected_path]
	var state := "%s|%s|%s|%s" % [interaction.nature_mode, interaction.flatten_offset_text(), bs.crop_choice, selected_crop]
	if key == _actions_key:
		if state != _actions_state:
			_actions_state = state
			for refresh: Callable in _action_refreshers:
				refresh.call()
		return
	_actions_key = key
	_actions_state = state
	_action_refreshers.clear()
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	var to_harvest := func() -> void: interaction.set_tool(Interaction.Tool.HARVEST)
	match interaction.tool:
		Interaction.Tool.BUILD:
			if bs.moving:
				_rotate_button()
				_action_button("close", "Отмена").pressed.connect(func() -> void: interaction.set_tool(Interaction.Tool.EDIT))
				_action_button("check", "Поставить").pressed.connect(interaction.confirm_build)
			elif bs.selected_id != "":
				if _touch:
					_action_button("cat_housing", "Здания").pressed.connect(func() -> void: _set_drawer(not _drawer_open))
				if GameData.BUILDINGS[bs.selected_id].has("crops"):
					_state_button(func() -> Array:
						var c: Dictionary = CropPatch.CROPS[bs.crop_choice]
						return [c["icon"], c["name"], true]).pressed.connect(interaction.next_crop)
				if bs.is_path():
					# Дорожка ложится плавной лентой следом за пальцем.
					_action_button("close", "Отмена").pressed.connect(to_harvest)
				else:
					_rotate_button()
					_action_button("close", "Отмена").pressed.connect(to_harvest)
					_action_button("check", "Построить").pressed.connect(interaction.confirm_build)
			elif _touch:
				_action_button("close", "Отмена").pressed.connect(to_harvest)
		Interaction.Tool.FLATTEN:
			_action_button("arrow_up", "Выше").pressed.connect(func() -> void: interaction.adjust_flatten_offset(0.5))
			_state_button(func() -> Array:
				return ["auto", interaction.flatten_offset_text().capitalize(), is_zero_approx(interaction.flatten_offset)]) \
				.pressed.connect(interaction.reset_flatten_offset)
			_action_button("arrow_down", "Ниже").pressed.connect(func() -> void: interaction.adjust_flatten_offset(-0.5))
			_action_button("plus", "Шире").pressed.connect(func() -> void: interaction.resize_brush(1.0))
			_action_button("minus", "Уже").pressed.connect(func() -> void: interaction.resize_brush(-1.0))
		Interaction.Tool.NATURE:
			for mode: String in NATURE_ICONS:
				_state_button(func() -> Array: return [NATURE_ICONS[mode], NATURE_SHORT[mode], interaction.nature_mode == mode]) \
					.pressed.connect(func() -> void: interaction.set_nature_mode(mode))
			_action_button("plus", "Шире").pressed.connect(func() -> void: interaction.resize_brush(1.0))
			_action_button("minus", "Уже").pressed.connect(func() -> void: interaction.resize_brush(-1.0))
		Interaction.Tool.EDIT:
			if interaction.selected_path >= 0:
				_action_button("trash", "Убрать").pressed.connect(interaction.remove_selected_path)
				_action_button("close", "Отмена").pressed.connect(func() -> void: interaction._edit_pick(null, null))
			elif is_instance_valid(interaction.selected_building):
				if interaction.selected_building.has_crops():
					var target: Building = interaction.selected_building
					_state_button(func() -> Array:
						var c: Dictionary = CropPatch.CROPS[target.crop if is_instance_valid(target) and target.crop != "" else "wheat"]
						return [c["icon"], c["name"], true]).pressed.connect(interaction.next_crop)
				_action_button("move", "Перенести").pressed.connect(interaction.edit_move)
				_action_button("rotate", "Повернуть").pressed.connect(func() -> void: interaction.edit_rotate(1.0))
				_action_button("trash", "Снести").pressed.connect(interaction.demolish_selected)
				_action_button("close", "Отмена").pressed.connect(func() -> void: interaction.select_building(null))
			else:
				_action_button("check", "Готово").pressed.connect(to_harvest)
		Interaction.Tool.HARVEST:
			if not interaction.jobs.is_empty():
				_action_button("close", "Очередь").pressed.connect(interaction.cancel_all_jobs)
	# Не залезаем на часы и шестерёнку сверху: лишние кнопки — во вторую колонку.
	var m := Platform.safe_margins() if _touch else {"top": 16.0, "bottom": 16.0}
	var room: float = _root.get_viewport_rect().size.y - m["top"] - _clock_row.size.y - 16.0 - m["bottom"]
	var count := _actions.get_child_count()
	_actions.columns = 2 if count * (58.0 + 8.0) - 8.0 > room else 1
	for c in _actions.get_children():
		c.modulate.a = 0.0
		c.create_tween().tween_property(c, "modulate:a", 1.0, 0.15)


func _build_toast() -> void:
	_notices = Notices.new()
	_notices.font_size = int(_px(17, 14))
	_notices.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.add_child(_notices)


func show_message(text: String) -> void:
	# На телефоне меню стройки занимает верх экрана — сообщение показываем в строке
	# подсказки над панелью инструментов, чтобы оно ничего не закрывало.
	if _touch and _drawer_open:
		_flash_hint(text)
		return
	_notices.show_text(text)


func _flash_hint(text: String) -> void:
	if not _hint_panel.has_meta("flash"):
		_hint_panel.set_meta("normal_text", _hint_panel.get_meta("current", ""))
	_hint_panel.set_meta("flash", Notices.SHOW_TIME)
	Rich.fit(_hint_label, text, _hint_max_width)
	_hint_label.add_theme_color_override("default_color", UiStyle.BRAND_DARK)
	_hint_panel.reset_size()
	UiStyle.fade(_hint_panel, true, 0.2)


func _build_loading() -> void:
	# Тот же вид, что и у браузерного экрана загрузки: тёплое небо, контурный
	# пейзаж, покачивающийся логотип, полоса хода и советы.
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color("#F8F3EA"))
	grad.set_color(1, Color("#E8DDCD"))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	_loading = bg
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_loading)
	var doodles := Doodles.new()
	doodles.line_width = _px(2.6, 2.0)
	doodles.alpha = 0.35
	doodles.set_anchors_preset(Control.PRESET_FULL_RECT)
	doodles.anchor_top = 0.55
	_loading.add_child(doodles)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(_px(10, 7)))
	box.position.y -= _px(40, 30)
	_loading.add_child(box)
	var logo_holder := Control.new()
	logo_holder.custom_minimum_size = Vector2.ONE * _px(110, 78)
	logo_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(logo_holder)
	var logo := TextureRect.new()
	logo.texture = load("res://icon.png") if ResourceLoader.exists("res://icon.png") else null
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo_holder.add_child(logo)
	logo.pivot_offset = logo_holder.custom_minimum_size * 0.5
	var bob := logo.create_tween().set_loops()
	bob.tween_property(logo, "position:y", -8.0, 1.2).set_trans(Tween.TRANS_SINE)
	bob.parallel().tween_property(logo, "rotation", deg_to_rad(2.0), 1.2).set_trans(Tween.TRANS_SINE)
	bob.tween_property(logo, "position:y", 0.0, 1.2).set_trans(Tween.TRANS_SINE)
	bob.parallel().tween_property(logo, "rotation", deg_to_rad(-2.0), 1.2).set_trans(Tween.TRANS_SINE)
	var title := UiStyle.label(GameData.GAME_NAME, _px(54, 40), UiStyle.TEXT, 900)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color.WHITE)
	title.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(title)
	_loading_text = UiStyle.label("Готовим графику…", _px(19, 15), UiStyle.BRAND_DARK, 800)
	_loading_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_loading_text)
	_loading_bar = ProgressBar.new()
	_loading_bar.show_percentage = false
	_loading_bar.max_value = 1.0
	_loading_bar.custom_minimum_size = Vector2(_px(420, 300), _px(16, 14))
	_loading_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var fill := UiStyle.box(UiStyle.BRAND_DARK, 10, 0)
	fill.border_width_top = 2
	fill.border_color = UiStyle.BRAND_DARK.lightened(0.25)
	_loading_bar.add_theme_stylebox_override("fill", fill)
	_loading_bar.add_theme_stylebox_override("background", UiStyle.box(Color("#EDE6DC"), 10, 0, 2, Color.WHITE))
	box.add_child(_loading_bar)
	var tip := UiStyle.label(LOADING_TIPS[randi() % LOADING_TIPS.size()], _px(15, 12), UiStyle.MUTED, 700)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size.x = _px(520, 380)
	box.add_child(tip)
	var tips_tw := tip.create_tween().set_loops()
	tips_tw.tween_interval(4.0)
	tips_tw.tween_property(tip, "modulate:a", 0.0, 0.3)
	tips_tw.tween_callback(func() -> void:
		var i := (LOADING_TIPS.find(tip.text) + 1) % LOADING_TIPS.size()
		tip.text = LOADING_TIPS[i])
	tips_tw.tween_property(tip, "modulate:a", 1.0, 0.3)


## Ход загрузки: доля 0..1 и что сейчас делается.
func set_loading(fraction: float, text: String) -> void:
	if not is_instance_valid(_loading) or _loading_bar == null:
		return
	_loading_text.text = text
	var target := maxf(_loading_bar.value, fraction)
	_loading_bar.create_tween().tween_property(_loading_bar, "value", target, 0.25)


## Телефон в портретной ориентации (бывает только в браузере): просим повернуть его.
func _build_portrait_hint() -> void:
	_portrait_hint = ColorRect.new()
	(_portrait_hint as ColorRect).color = UiStyle.BASE
	_portrait_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_hint.visible = false
	_root.add_child(_portrait_hint)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	_portrait_hint.add_child(box)
	var ic := UiStyle.icon_rect("rotate", 72)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ic)
	var title := UiStyle.label("Поверните телефон", 26, UiStyle.TEXT, 900)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := UiStyle.label("Играть удобнее горизонтально", 16, UiStyle.BRAND_DARK, 700)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)


func hide_loading() -> void:
	var tw := _loading.create_tween()
	tw.tween_property(_loading, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_loading.queue_free)


func _process(delta: float) -> void:
	# На телефоне меню стройки и ремесло занимают верх экрана — мини-карта
	# на это время уходит, чтобы не закрывать их.
	if _map_frame:
		var covered := bool(_all_panel.get_meta("fade_target", false))
		if _touch:
			covered = covered or _drawer_open
		_map_frame.modulate.a = move_toward(_map_frame.modulate.a, 0.0 if covered else 1.0, delta * 6.0)
		_map_frame.visible = _map_frame.modulate.a > 0.01
	_place_notices()
	_place_labels()
	if _hint_panel.has_meta("flash"):
		var left: float = _hint_panel.get_meta("flash") - delta
		if left > 0.0:
			_hint_panel.set_meta("flash", left)
		else:
			_hint_panel.remove_meta("flash")
			_hint_label.add_theme_color_override("default_color", UiStyle.TEXT)
			_on_hover_changed(str(_hint_panel.get_meta("normal_text", "")))
	_info_timer -= delta
	if _info_timer <= 0.0:
		_info_timer = 0.25
		_update_clock()
		if _craft_panel.visible:
			_refresh_craft_status()
	if interaction:
		_update_job_panel()
		_update_actions()
		# Удерживаемая «Повернуть» крутит призрак плавно (≈ 60° в секунду).
		if is_instance_valid(_rotate_hold) and _rotate_hold.has_meta("held"):
			var held: float = _rotate_hold.get_meta("held") + delta
			_rotate_hold.set_meta("held", held)
			if held > 0.3:
				_rotate_hold.set_meta("spun", true)
				interaction.building_system.rotate_ghost_by(deg_to_rad(60.0) * delta)
		# Полоска ремесла: плавно следует за прогрессом, а при смене рецепта — сразу к нулю.
		var f := Crafting.current_fraction()
		_craft_progress.value = f if f < _craft_progress.value else lerpf(_craft_progress.value, f, 1.0 - exp(-14.0 * delta))
	if _hover_panel and _hover_panel.visible:
		var target := get_viewport().get_mouse_position() + Vector2(22, 22)
		var vp := get_viewport().get_visible_rect().size
		target.x = minf(target.x, vp.x - _hover_panel.size.x - 8)
		target.y = minf(target.y, vp.y - _hover_panel.size.y - 8)
		_hover_panel.position = _hover_panel.position.lerp(target, 1.0 - exp(-25.0 * delta))


## Сообщения — в свободной полосе между мини-картой и открытым справа окном.
func _place_notices() -> void:
	var m := Platform.safe_margins() if _touch else {"left": 16.0, "top": 16.0, "right": 16.0, "bottom": 16.0}
	var vp := _root.get_viewport_rect().size
	var left: float = m["left"]
	if _map_frame and _map_frame.visible:
		left += _map_frame.size.x + 14.0
	var right: float = vp.x - m["right"]
	if _craft_panel.get_meta("fade_target", false):
		right = _craft_panel.global_position.x - 14.0
	_notices.max_width = clampf(right - left - 12.0, 200.0, 620.0)
	var x := (left + right) * 0.5 - _notices.size.x * 0.5
	_notices.position.x = lerpf(_notices.position.x, x, 0.35)


## Плашки над зданиями не заходят под верхнюю строку и нижнюю панель.
func _place_labels() -> void:
	var m := Platform.safe_margins() if _touch else {"left": 16.0, "top": 16.0, "right": 16.0, "bottom": 16.0}
	var vp := _root.get_viewport_rect().size
	var top: float = m["top"] + maxf(_resource_bar.size.y, _clock_row.size.y) + 8.0
	var bottom: float = _bottom.global_position.y - 8.0 if _bottom.visible else vp.y - m["bottom"]
	_labels.safe_rect = Rect2(m["left"], top, vp.x - m["left"] - m["right"], maxf(bottom - top, 40.0))


## Раз в четверть секунды: не ушли ли мы далеко от мастерских (рецепты блокируются).
func _refresh_craft_status() -> void:
	var paused := Crafting.is_paused()
	if paused != _craft_status.text.begins_with("Пауза"):
		# Подпись очереди пишется заново вместе с очередью.
		_craft_queue_key = "-"
		_refresh_crafting()
		if paused:
			_craft_status.text = "Пауза — мастерская далеко:"
	for id: String in _craft_rows:
		var reason := Crafting.check(id)
		if (reason != "") != (_craft_rows[id]["button"] as Button).disabled:
			_refresh_crafting()
			break
