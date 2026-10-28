class_name SettingsDialog
extends Control
## Окно настроек: слева разделы (Игра, Мир, Графика, Деревни, Управление, О проекте), справа —
## карточки на своих подложках. У каждой настройки — заголовок, пояснение и
## понятный переключатель. «Управление» — подробная справка со скриншотами игры,
## где номерами и стрелками показано, куда нажимать.
## Открывается шестерёнкой справа сверху, закрывается крестиком, Esc или кликом мимо.

signal save_requested
## Сохранить мир и выйти на стартовый экран со списком миров.
signal menu_requested
## «Очистить кэш» (см. Platform.clear_cache).
signal cache_clear_requested
## Открыть готовую деревню (VillageBuilder.PRESETS) новым миром.
signal village_requested(id: String)

const WIDTH := 940.0
## Оттенки фирменных цветов для подложек и акцентов.
const CARD := Color("#FBF8F3")
const CARD_ALT := Color("#F4EDE3")
const CARD_BORDER := Color("#E6DACB")
const BADGE := Color("#EADFD0")
const NAV_BG := Color("#EFE7DC")
const ACCENT := Color("#E8643C")
const SECTIONS := [
	["game", "Игра", "icon_game"],
	["world", "Мир", "season_summer"],
	["graphics", "Графика", "lantern"],
	["villages", "Деревни", "icon_village"],
	["help", "Управление", "help"],
	["about", "О проекте", "icon_about"],
]
## Снимки для «О проекте»: файл в assets/about и подпись.
const ABOUT_SHOTS := [
	["harbor_day", "Озёрная гавань ясным утром"],
	["merchants_evening", "Купеческий город поздним вечером"],
	["mill_rain", "Мельница у реки в дождь"],
	["north_snow", "Северная заимка в снегопад"],
	["abbey_fog", "Монастырская обитель в тумане"],
	["harbor_night", "Ночные огни гавани"],
]

var _panel: PanelContainer
## Элементы, которые при открытии окна заново читают значения из Settings
## (настройки могли поменяться не через это окно).
var _chips_by_key := {}
var _sliders := []
var _toggles := {}
var _touch := false
var _world_title: Label
var _scroll: SmoothScroll
var _pages := {}
var _nav_buttons := {}
var _section := "game"
var _help_box: VBoxContainer
var _body: BoxContainer
var _nav_box: BoxContainer
var _nav_scroll: ScrollContainer
var _about_grid: GridContainer
var _help_touch := true
## Ряды из двух широких кнопок: на узком экране они встают одна под другой.
var _stack_rows: Array[BoxContainer] = []


func _ready() -> void:
	_touch = Platform.is_touch
	_help_touch = _touch
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	modulate.a = 0.0
	var dim := ColorRect.new()
	dim.color = Color(0.18, 0.13, 0.09, 0.42)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.panel(24, 14 if _touch else 18))
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	center.add_child(_panel)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 10 if _touch else 14)
	_panel.add_child(frame)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.add_child(UiStyle.icon_rect("settings", 30 if _touch else 34))
	header.add_child(UiStyle.label("Настройки", 22 if _touch else 26, UiStyle.TEXT, 900))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_btn := UiStyle.close_button(44.0 if _touch else 40.0)
	close_btn.tooltip_text = "Закрыть (Esc)"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	frame.add_child(header)

	# Направление меняется на вертикальном экране (см. _fit).
	var body := BoxContainer.new()
	body.add_theme_constant_override("separation", 12 if _touch else 16)
	frame.add_child(body)
	_body = body
	body.add_child(_build_nav())

	_scroll = SmoothScroll.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	var pages := MarginContainer.new()
	pages.add_theme_constant_override("margin_right", 10)
	pages.mouse_filter = Control.MOUSE_FILTER_PASS
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	for s: Array in SECTIONS:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 10 if _touch else 12)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.mouse_filter = Control.MOUSE_FILTER_PASS
		page.visible = s[0] == _section
		pages.add_child(page)
		_pages[s[0]] = page
	_build_game(_pages["game"])
	_build_world(_pages["world"])
	_build_graphics(_pages["graphics"])
	_build_villages(_pages["villages"])
	_help_box = _pages["help"]
	_build_help()
	_build_about(_pages["about"])

	Platform.layout_changed.connect(_fit)
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()
	Settings.changed.connect(func(_key: String) -> void:
		if is_open():
			_sync())


# --- Каркас ----------------------------------------------------------------------------------------

func _build_nav() -> Control:
	var nav := PanelContainer.new()
	nav.add_theme_stylebox_override("panel", UiStyle.box(NAV_BG, 18, 8))
	# Разделов много: на узком экране строка листается вбок, на широком колонка — вниз,
	# а окно не растёт и подписи не обрезаются.
	_nav_scroll = ScrollContainer.new()
	_nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_nav_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_nav_scroll.scroll_deadzone = 8
	nav.add_child(_nav_scroll)
	var box := BoxContainer.new()
	box.vertical = true
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nav_scroll.add_child(box)
	_nav_box = box
	var group := ButtonGroup.new()
	for s: Array in SECTIONS:
		var b := Button.new()
		b.text = s[1]
		b.icon = UiStyle.icon(s[2])
		b.add_theme_constant_override("icon_max_width", 30 if _touch else 32)
		b.add_theme_constant_override("h_separation", 10)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = s[0] == _section
		b.custom_minimum_size = Vector2(150 if _touch else 180, 50 if _touch else 54)
		b.add_theme_font_override("font", UiStyle.font(800))
		b.add_theme_font_size_override("font_size", 15 if _touch else 17)
		_style_nav_button(b, 10)
		b.pressed.connect(func() -> void: _show_section(s[0]))
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(b)
		_nav_buttons[s[0]] = b
	return nav


## Рамки кнопки раздела; pad — внутренние поля (в строке разделов на телефоне — узкие).
func _style_nav_button(b: Button, pad: int) -> void:
	b.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0), 14, pad))
	b.add_theme_stylebox_override("hover", UiStyle.box(Color(CARD, 0.7), 14, pad))
	b.add_theme_stylebox_override("pressed", UiStyle.box(CARD, 14, pad, 2, UiStyle.BRAND, true))
	b.add_theme_stylebox_override("hover_pressed", UiStyle.box(CARD, 14, pad, 2, UiStyle.BRAND_DARK, true))


func _show_section(id: String) -> void:
	_section = id
	for key: String in _nav_buttons:
		(_nav_buttons[key] as Button).set_pressed_no_signal(key == id)
	_nav_scroll.ensure_control_visible.call_deferred(_nav_buttons[id])
	for key: String in _pages:
		(_pages[key] as Control).visible = key == id
	_scroll.reset()
	_fit()


## Окно не шире экрана без вырезов и не выше его — содержимое раздела листается.
## На вертикальном экране разделы — строкой сверху, а не колонкой слева.
func _fit() -> void:
	var m := Platform.safe_margins()
	var vp := get_viewport_rect().size
	var portrait := vp.x < vp.y
	_body.vertical = portrait
	_nav_box.vertical = not portrait
	_nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if portrait else ScrollContainer.SCROLL_MODE_DISABLED
	_nav_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if portrait else ScrollContainer.SCROLL_MODE_SHOW_NEVER
	# Строка разделов на узком экране — своей высоты; колонка на широком — во всю высоту
	# окна (кнопки, что не влезли, листаются).
	_nav_scroll.custom_minimum_size = Vector2(0, 66) if portrait else Vector2(150 if _touch else 180, 0)
	for b: Button in _nav_buttons.values():
		b.custom_minimum_size = Vector2(76, 58) if portrait else Vector2(150 if _touch else 180, 50 if _touch else 54)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if portrait else Control.SIZE_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER if portrait else HORIZONTAL_ALIGNMENT_LEFT
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP if portrait else VERTICAL_ALIGNMENT_CENTER
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if portrait else HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 12 if portrait else (15 if _touch else 17))
		# Подпись целиком: строка разделов листается, а не обрезает их.
		b.clip_text = false
		if b.get_meta("pad", -1) != (3 if portrait else 10):
			b.set_meta("pad", 3 if portrait else 10)
			_style_nav_button(b, 3 if portrait else 10)
		b.add_theme_constant_override("icon_max_width", 24 if portrait else (30 if _touch else 32))
	_panel.custom_minimum_size.x = minf(WIDTH, vp.x - m["left"] - m["right"] - 12.0)
	if _about_grid:
		_about_grid.columns = 1 if _panel.custom_minimum_size.x < 620.0 else 2
	# Иначе две кнопки рядом распирали бы раздел «Игра» шире остальных.
	for row in _stack_rows:
		row.vertical = portrait
	var chrome := (44.0 + 10.0 + 40.0) if _touch else (40.0 + 14.0 + 52.0)
	if portrait:
		chrome += 66.0 + 16.0 + 12.0
	var room: float = vp.y - m["top"] - m["bottom"] - chrome
	_scroll.custom_minimum_size.y = maxf(room, 160.0)


## Карточка раздела: значок в кружке, заголовок и пояснение, ниже — содержимое.
func _card(parent: Control, icon_name: String, title: String, desc := "", alt := false) -> VBoxContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_theme_stylebox_override("panel", UiStyle.box(CARD_ALT if alt else CARD, 18, 14 if _touch else 16, 2, CARD_BORDER))
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(head)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UiStyle.box(BADGE, 14, 6))
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	badge.add_child(UiStyle.icon_rect(icon_name, 34 if _touch else 38))
	head.add_child(badge)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(UiStyle.label(title, 17 if _touch else 19, UiStyle.TEXT, 900))
	if desc != "":
		titles.add_child(_desc(desc))
	return box


func _desc(text: String) -> Label:
	var l := UiStyle.label(text, 13 if _touch else 14, UiStyle.MUTED, 700)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Строка настройки: слева название и пояснение, справа — переключатель.
func _toggle_row(parent: Control, key: String, title: String, desc: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 1)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_child(UiStyle.label(title, 15 if _touch else 16, UiStyle.TEXT, 800))
	if desc != "":
		texts.add_child(_desc(desc))
	row.add_child(texts)
	var cb := CheckButton.new()
	cb.button_pressed = Settings.get_value(key)
	cb.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	cb.mouse_filter = Control.MOUSE_FILTER_PASS
	cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _touch:
		cb.custom_minimum_size = Vector2(56, 44)
	row.add_child(cb)
	_toggles[key] = cb
	parent.add_child(row)


## Кнопки-варианты сеткой не больше columns в ряд. На узком экране колонок меньше:
## подпись кнопки всегда видна целиком, а не обрезается.
func _chips(parent: Control, key: String, options: Array, columns: int) -> void:
	var grid := GridContainer.new()
	grid.columns = columns
	var cell := 0.0
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	var group := ButtonGroup.new()
	_chips_by_key[key] = {}
	for opt: Array in options:
		var b := Button.new()
		b.text = opt[1]
		if opt[2] != "":
			b.icon = UiStyle.icon(opt[2])
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_constant_override("icon_max_width", 26)
		b.add_theme_constant_override("h_separation", 8)
		b.add_theme_font_override("font", UiStyle.font(800))
		b.add_theme_font_size_override("font_size", 14 if _touch else 15)
		b.add_theme_stylebox_override("normal", UiStyle.box(Color.WHITE, 12, 8, 2, CARD_BORDER))
		b.add_theme_stylebox_override("hover", UiStyle.box(Color.WHITE, 12, 8, 2, UiStyle.BRAND))
		b.add_theme_stylebox_override("pressed", UiStyle.box(Color("#E9DCC8"), 12, 8, 3, UiStyle.BRAND_DARK))
		b.add_theme_stylebox_override("hover_pressed", UiStyle.box(Color("#E9DCC8"), 12, 8, 3, UiStyle.BRAND_DARK))
		b.custom_minimum_size = Vector2(96, 44) if _touch else Vector2(110, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cell = maxf(cell, maxf(b.custom_minimum_size.x, _chip_width(opt[1], opt[2] != "")))
		# Иначе список не листается, если палец начал движение на кнопке.
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.button_pressed = Settings.get_value(key) == opt[0]
		b.toggled.connect(func(on: bool) -> void:
			if on:
				Settings.set_value(key, opt[0]))
		grid.add_child(b)
		_chips_by_key[key][opt[0]] = b
	parent.add_child(grid)
	grid.resized.connect(func() -> void:
		var fit := clampi(floori((grid.size.x + 8.0) / (cell + 8.0)), 1, columns)
		if fit != grid.columns:
			grid.columns = fit)


## Ширина кнопки-варианта, при которой подпись (со значком) видна целиком:
## текст, значок 26 с отступом 8, поля рамки по 8 и небольшой запас.
func _chip_width(text: String, with_icon: bool) -> float:
	var w := UiStyle.font(800).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14 if _touch else 15).x
	return w + (34.0 if with_icon else 0.0) + 16.0 + 8.0


## Ползунок: название с пояснением, значение крупно справа.
## on_release — сохранять значение, только когда ползунок отпустили (тяжёлые настройки).
func _slider(parent: Control, key: String, title: String, desc: String, lo: float, hi: float, step: float,
		fmt: Callable, on_release := false) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 1)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_child(UiStyle.label(title, 15 if _touch else 16, UiStyle.TEXT, 800))
	if desc != "":
		texts.add_child(_desc(desc))
	head.add_child(texts)
	var value_box := PanelContainer.new()
	value_box.add_theme_stylebox_override("panel", UiStyle.box(BADGE, 10, 6))
	value_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value := UiStyle.label("", 15 if _touch else 16, UiStyle.BRAND_DARK, 900)
	value.custom_minimum_size.x = 64
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_box.add_child(value)
	head.add_child(value_box)
	box.add_child(head)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size.y = 34 if _touch else 26
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(s)
	value.text = fmt.call(s.value)
	var store := func(v: float) -> void: Settings.set_value(key, int(v) if key == "view_distance" else v)
	s.value_changed.connect(func(v: float) -> void:
		value.text = fmt.call(v)
		if not (on_release and s.has_meta("dragging")):
			store.call(v))
	if on_release:
		s.drag_started.connect(func() -> void: s.set_meta("dragging", true))
		s.drag_ended.connect(func(_changed: bool) -> void:
			s.remove_meta("dragging")
			store.call(s.value))
	parent.add_child(box)
	_sliders.append({"key": key, "slider": s, "label": value, "fmt": fmt})


# --- Разделы ---------------------------------------------------------------------------------------

func _build_game(page: VBoxContainer) -> void:
	var mode := _card(page, "icon_modes", "Режим игры", "Обычный — добывайте, стройте и развивайтесь. Творческий — всё сразу и без ограничений.")
	_chips(mode, "game_mode", [["normal", "Обычный", "tool_harvest"], ["creative", "Творческий", "cat_special"]], 2)
	var land := _card(page, "tool_flatten", "Земля", "", true)
	_toggle_row(land, "clear_flattened", "Пустая выровненная земля",
		"Включено — на выровненной земле не растут трава и деревья. Выключено — они остаются, а на поднятой до гор земле растёт только горное.")
	if Platform.is_mobile():
		_toggle_row(land, "haptics", "Вибрация", "Лёгкий отклик при нажатиях и стройке.")
	var save_card := _card(page, "map", "Мир",
		"Игра сохраняется сама — регулярно и при сворачивании. В главном меню — все ваши миры и новый мир.")
	# Заголовок карточки — имя открытого мира (обновляется при каждом открытии окна).
	_world_title = save_card.get_child(0).get_child(1).get_child(0)
	# Длинное имя мира не раздвигает окно.
	_world_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	_stack_rows.append(row)
	var save := Button.new()
	save.text = "Сохранить мир"
	save.icon = UiStyle.icon("check")
	save.add_theme_constant_override("icon_max_width", 24)
	save.custom_minimum_size = Vector2(0, 46 if _touch else 44)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.mouse_filter = Control.MOUSE_FILTER_PASS
	save.pressed.connect(func() -> void: save_requested.emit())
	row.add_child(save)
	var menu := Button.new()
	menu.text = "В главное меню"
	menu.icon = UiStyle.icon("house_blue")
	menu.add_theme_constant_override("icon_max_width", 24)
	menu.custom_minimum_size = Vector2(0, 46 if _touch else 44)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.mouse_filter = Control.MOUSE_FILTER_PASS
	menu.pressed.connect(func() -> void: menu_requested.emit())
	row.add_child(menu)
	save_card.add_child(row)
	var cache := _card(page, "trash", "Кэш",
		"Если после обновления игра осталась прежней — очистите кэш: она скачается заново и перезапустится. Миры и настройки останутся."
		if Platform.is_web else "Собранные шейдеры удалятся и соберутся заново при следующем запуске. Миры и настройки останутся.", true)
	var clear := Button.new()
	clear.text = "Очистить кэш"
	clear.icon = UiStyle.icon("trash")
	clear.add_theme_constant_override("icon_max_width", 24)
	clear.custom_minimum_size = Vector2(0, 46 if _touch else 44)
	clear.mouse_filter = Control.MOUSE_FILTER_PASS
	clear.pressed.connect(_on_clear_cache.bind(clear))
	cache.add_child(clear)


## «Очистить кэш». В браузере игра после этого перезапустится — просим нажать ещё раз.
func _on_clear_cache(b: Button) -> void:
	if Platform.is_web and not b.has_meta("armed"):
		b.set_meta("armed", true)
		b.text = "Нажмите ещё раз"
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			if is_instance_valid(b) and b.has_meta("armed"):
				b.remove_meta("armed")
				b.text = "Очистить кэш")
		return
	b.remove_meta("armed")
	b.text = "Очистить кэш"
	cache_clear_requested.emit()


func _build_world(page: VBoxContainer) -> void:
	var time := _card(page, "clock_day", "Время суток", "«Авто» — день сменяется ночью сам. Можно оставить только день или только ночь.")
	_chips(time, "time_mode", [["auto", "Авто", "auto"], ["day", "День", "day"], ["night", "Ночь", "night"]], 3)
	_slider(time, "day_minutes", "Длина суток", "Сколько реальных минут длятся одни сутки.", 4.0, 30.0, 1.0,
		func(v: float) -> String: return "%d мин" % v)
	var weather := _card(page, "weather_cloudy", "Погода", "Погода меняется плавно. Выбранная сразу наступит за шторкой.", true)
	var options := [["auto", "Авто", "auto"]]
	for id: String in Weather.WEATHERS:
		options.append([id, Weather.WEATHERS[id]["name"], "weather_" + id])
	_chips(weather, "weather_mode", options, 3 if _touch else 4)
	var season := _card(page, "season_autumn", "Время года", "Весна, лето, осень и зима: листва, снег, лёд на озёрах.")
	var seasons := [["auto", "Авто", "auto"]]
	for s: Dictionary in Weather.SEASONS:
		seasons.append([s["id"], s["name"], "season_" + s["id"]])
	_chips(season, "season_mode", seasons, 3 if _touch else 5)
	_slider(season, "season_days", "Длина сезона", "Сколько суток длится одно время года.", 1.0, 10.0, 1.0,
		func(v: float) -> String: return "%d сут." % v)


func _build_graphics(page: VBoxContainer) -> void:
	var quality := _card(page, "lantern", "Качество картинки",
		"«Авто» подбирает качество под устройство и понижает его, если игра подтормаживает. На высоком за окнами видны комнаты.")
	var levels := [["auto", "Авто", "auto"]]
	for level: String in Settings.QUALITY_LEVELS:
		levels.append([level, Settings.QUALITY_NAMES[level], ""])
	levels.append(["custom", "Своё", ""])
	_chips(quality, "quality", levels, 3)
	_slider(quality, "render_scale", "Чёткость", "Меньше — быстрее, но картинка мягче.", 0.5, 1.0, 0.05,
		func(v: float) -> String: return "%d%%" % roundi(v * 100.0), true)
	var textures := _card(page, "marker_tree", "Текстуры",
		"«Мультик» — мягкие пятна цвета, как в мультфильме. «Реализм» — волокна дерева, кора, зерно камня и листочки с рельефом.", true)
	_chips(textures, "textures", [["cartoon", "Мультик", ""], ["realism", "Реализм", ""]], 2)
	var shadows := _card(page, "day", "Тени", "Мягкие тени красивее, простые — быстрее.")
	_chips(shadows, "shadow_quality", [["off", "Нет", ""], ["low", "Простые", ""], ["medium", "Средние", ""], ["high", "Мягкие", ""]], 4 if not _touch else 2)
	_slider(shadows, "shadow_distance", "Дальность теней", "Как далеко от камеры видны тени. Дальше — красивее, но тяжелее.",
		40.0, 400.0, 10.0, func(v: float) -> String: return "%d м" % v, true)
	var water := _card(page, "cat_water", "Вода", "", true)
	_toggle_row(water, "reflections", "Отражения", "Небо, деревья и дома отражаются в воде.")
	_toggle_row(water, "fish", "Рыбы", "В реках и озёрах плавают рыбы.")
	var nature := _card(page, "grass_tall", "Трава и дальность")
	_slider(nature, "view_distance", "Дальность прорисовки", "Как далеко виден мир.", 4.0, 10.0, 1.0,
		func(v: float) -> String: return "%d м" % (v * 32))
	# Трава пересеивается в каждом чанке — применяем, когда ползунок отпустили.
	_slider(nature, "grass", "Густота травы", "", 0.0, 1.0, 0.05, func(v: float) -> String: return "%d%%" % roundi(v * 100.0), true)
	_slider(nature, "grass_distance", "Дальность травы", "Дальше этого трава плавно уходит в землю.", 25.0, 140.0, 5.0,
		func(v: float) -> String: return "%d м" % v, true)
	if Platform.is_web:
		_build_threads(page)


## Браузер: многопоточная сборка (мир строится в фоновых потоках).
func _build_threads(page: VBoxContainer) -> void:
	var card := _card(page, "compass", "Многопоточность",
		"Мир строится в фоновых потоках процессора — меньше рывков, когда вы ведёте камеру. "
		+ "Если игра в браузере вылетает — выключите. Меняется после перезапуска игры.", true)
	_chips(card, "web_threads", [["auto", "Авто", "auto"], ["off", "Выключена", ""]], 2)
	var status := _desc("")
	if OS.has_feature("threads"):
		status.text = "Сейчас: включена — мир строится в фоне."
	elif Settings.get_value("web_threads") == "off":
		status.text = "Сейчас: выключена."
	else:
		status.text = "Сейчас: выключена — браузер пока не разрешил потоки. Обычно они включаются со второго запуска."
	card.add_child(status)
	var restart := Button.new()
	restart.text = "Перезапустить игру"
	restart.icon = UiStyle.icon("rotate")
	restart.add_theme_constant_override("icon_max_width", 24)
	restart.custom_minimum_size = Vector2(0, 46 if _touch else 44)
	restart.mouse_filter = Control.MOUSE_FILTER_PASS
	restart.pressed.connect(func() -> void:
		WorldState.save_game()
		JavaScriptBridge.eval("window.everstead && setTimeout(window.everstead.reload, 300)"))
	card.add_child(restart)


# --- Управление ------------------------------------------------------------------------------------

## Справка: тема, скриншот с номерами и пояснения к номерам (для касаний и для мыши).
const HELP := [
	{"title": "Экран игры", "icon": "icon_village", "image": "hud",
		"touch": [
			"[b]Ресурсы[/b] — сколько у вас брёвен, досок, камня. Кнопка «…» — все ресурсы.",
			"[b]Мини-карта[/b] — где вы и что уже разведано. Нажмите — откроется большая карта.",
			"[b]Часы, сезон и погода.[/b] Нажмите — подробности.",
			"[b]Настройки[/b] — это окно.",
			"[b]Инструменты[/b]: Добыча, Стройка, Ровнять, Природа, Правка и Ремесло.",
			"[b]Подсказка[/b] — что можно сделать прямо сейчас."],
		"pc": [
			"[b]Ресурсы[/b] — сколько у вас брёвен, досок, камня. «…» — все ресурсы.",
			"[b]Мини-карта[/b]. Нажмите на неё или {Tab} — большая карта.",
			"[b]Часы, сезон и погода.[/b]",
			"[b]Настройки[/b] — это окно, {Esc} закрывает.",
			"[b]Инструменты[/b]: {1} {2} {3} {4} {5}, а {C} — Ремесло.",
			"[b]Подсказка у курсора[/b] — что можно сделать прямо сейчас."]},
	{"title": "Камера", "icon": "move", "image": "gestures",
		"touch": [
			"[b]Один палец[/b] — двигать камеру. Сильный взмах — камера ещё немного прокатится.",
			"[b]Щипок[/b] — приблизить или отдалить.",
			"[b]Два пальца по кругу[/b] — повернуть камеру.",
			"[b]Два пальца вверх-вниз[/b] — наклонить камеру.",
			"[b]Три быстрых касания двумя пальцами[/b] — спрятать интерфейс (и вернуть)."],
		"pc": [
			"{W A S D} или стрелки — двигать камеру, с {Shift} — быстрее. Средняя кнопка мыши — тащить.",
			"[b]Колесо мыши[/b] — приблизить или отдалить.",
			"[b]Правая кнопка[/b] + движение мыши или {Q} / {E} — повернуть.",
			"[b]Правая кнопка[/b] + мышь вверх-вниз — наклонить.",
			"{H} — спрятать интерфейс (и вернуть)."]},
	{"title": "Добыча", "icon": "tool_harvest", "image": "harvest",
		"touch": [
			"Нажмите на [b]дерево, куст, камень, руду или сундук[/b] — начнётся добыча.",
			"[b]Полоска[/b] показывает ход. Отметьте несколько целей — они встанут в очередь.",
			"[b]Подсказка[/b]: сколько времени нужно и что выпадет."],
		"pc": [
			"{ЛКМ} на [b]дерево, куст, камень, руду или сундук[/b] — начнётся добыча.",
			"[b]Полоска[/b] показывает ход. Несколько целей встают в очередь.",
			"[b]Подсказка у курсора[/b]: время и что выпадет."]},
	{"title": "Стройка: выбор здания", "icon": "tool_build", "image": "build_menu",
		"touch": [
			"[b]«Стройка»[/b]: нажмите ещё раз — меню зданий откроется или закроется.",
			"[b]Разделы[/b]: мастерские, жильё, особые, оборона, на воде, двор, сад и декор.",
			"[b]Карточка[/b]: цена и время. Если чего-то не хватает — это видно сразу."],
		"pc": [
			"{2} или «Стройка» — меню зданий; ещё раз — закрыть.",
			"[b]Разделы[/b]: мастерские, жильё, особые, оборона, на воде, двор, сад и декор.",
			"[b]Карточка[/b]: цена и время. Недоступное — сразу видно."]},
	{"title": "Стройка: куда поставить", "icon": "marker_pin", "image": "build_place",
		"touch": [
			"[b]Тяните здание пальцем[/b] или нажмите на землю, куда поставить.",
			"[b]«Повернуть»[/b]: нажмите — повернуть, удерживайте — плавно крутить.",
			"[b]«Построить»[/b] — поставить здание.",
			"[b]«Отмена»[/b] — убрать чертёж.",
			"[b]Подсказка[/b]: цена и почему здесь нельзя строить."],
		"pc": [
			"[b]Ведите мышью[/b] — чертёж идёт за курсором.",
			"{R} / {Shift+R} или {Ctrl} + колесо — повернуть.",
			"{ЛКМ} — построить.",
			"{ПКМ} или {Esc} — отмена.",
			"[b]Подсказка у курсора[/b]: цена и почему здесь нельзя строить."]},
	{"title": "Правка", "icon": "tool_edit", "image": "edit",
		"touch": [
			"Нажмите на [b]здание[/b], чтобы выбрать его.",
			"[b]«Переместить»[/b] — перенести на новое место.",
			"[b]«Повернуть»[/b] — развернуть на месте.",
			"[b]«Снести»[/b]: вернётся половина ресурсов, а за недостроенное — всё."],
		"pc": [
			"{ЛКМ} на [b]здание[/b] — выбрать.",
			"{M} — переместить.",
			"{R} — повернуть.",
			"{Delete} — снести: вернётся половина ресурсов, за недостроенное — всё."]},
	{"title": "Ровнять", "icon": "tool_flatten", "image": "flatten",
		"touch": [
			"[b]Высота[/b]: поднять, выровнять по месту касания («Авто») или опустить.",
			"[b]Кисть[/b]: шире или уже.",
			"[b]Проведите пальцем[/b] по земле. Камера в это время — двумя пальцами."],
		"pc": [
			"{PgUp} / {PgDn} — высота выше или ниже.",
			"{[} и {]} — размер кисти.",
			"[b]Зажмите {ЛКМ}[/b] и ведите по земле."]},
	{"title": "Ремесло", "icon": "tool_craft", "image": "craft",
		"touch": [
			"[b]«Ремесло»[/b] — окно рецептов.",
			"Нажмите [b]«Сделать»[/b]: одинаковые заказы складываются «×N», работа идёт и при закрытом окне. Мастерская должна быть рядом."],
		"pc": [
			"{C} — окно рецептов.",
			"[b]«Сделать»[/b]: одинаковые заказы складываются «×N», работа идёт и при закрытом окне. Мастерская должна быть рядом."]},
	{"title": "Карта и метки", "icon": "map", "image": "map",
		"touch": ["Нажмите на карту — [b]поставить метку[/b]: выберите цвет и значок, чтобы отметить свою деревню."],
		"pc": ["{ЛКМ} на карте — [b]поставить метку[/b]: цвет и значок, чтобы отметить свою деревню."]},
]


## Картинка во всю ширину карточки, высота — по её пропорциям (без своей ширины: иначе
## она «распирала» бы окно на весь экран). max_height > 0 — не выше: в широком окне
## картинка становится полосой и не занимает весь экран.
func _picture(parent: Control, path: String, max_height := 0.0) -> Control:
	if not ResourceLoader.exists(path):
		return null
	var pic := TextureRect.new()
	pic.texture = load(path)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_PASS
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", UiStyle.box(Color.WHITE, 14, 4, 2, CARD_BORDER))
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	holder.add_child(pic)
	parent.add_child(holder)
	pic.set_meta("aspect", float(pic.texture.get_width()) / pic.texture.get_height())
	holder.resized.connect(func() -> void:
		var h := (holder.size.x - 8.0) / float(pic.get_meta("aspect"))
		pic.custom_minimum_size.y = minf(h, max_height) if max_height > 0.0 else h)
	return holder


## «Деревни»: готовые большие деревни — каждая открывается новым миром.
func _build_villages(page: VBoxContainer) -> void:
	_card(page, "icon_village", "Готовые деревни",
		"Десять больших деревень на красивых местах: улицы, площадь, дома, мастерские, огороды и огни по вечерам. "
		+ "Деревня откроется новым миром — нынешний мир сохранится и останется в главном меню.")
	var alt := true
	for p: Dictionary in VillageBuilder.PRESETS:
		var card := _card(page, "preset_" + p["id"], p["name"], p["desc"], alt)
		alt = not alt
		_picture(card, "res://assets/villages/%s.jpg" % p["id"], 240.0)
		var go := Button.new()
		go.text = "Открыть деревню"
		go.icon = UiStyle.icon("arrow")
		go.add_theme_constant_override("icon_max_width", 22)
		go.custom_minimum_size = Vector2(0, 46 if _touch else 44)
		go.mouse_filter = Control.MOUSE_FILTER_PASS
		go.pressed.connect(_on_village.bind(go, p["id"]))
		card.add_child(go)


## Открыть деревню — со второго нажатия: случайное касание не уводит из нынешнего мира.
func _on_village(b: Button, id: String) -> void:
	if not b.has_meta("armed"):
		b.set_meta("armed", true)
		b.text = "Нажмите ещё раз"
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			if is_instance_valid(b) and b.has_meta("armed"):
				b.remove_meta("armed")
				b.text = "Открыть деревню")
		return
	b.remove_meta("armed")
	b.text = "Открываем…"
	close()
	village_requested.emit(id)


## «О проекте»: снимки деревень в разную погоду и рассказ об игре.
func _build_about(page: VBoxContainer) -> void:
	var hero := _card(page, "marker_star", GameData.GAME_NAME,
		"Уютная стройка в живом трёхмерном мире: от первой хижины у озера до шумного купеческого города.")
	_picture(hero, "res://assets/about/%s.jpg" % ABOUT_SHOTS[0][0])
	hero.add_child(_desc(
		"Здесь нет спешки и проигрышей. Вы сами выбираете место, рубите лес, добываете камень и глину, "
		+ "обжигаете кирпич и варите стекло — и шаг за шагом превращаете дикий край в деревню, где вечером "
		+ "загораются окна и факелы, а над крышами поднимается дым из труб."))
	var gallery := _card(page, "weather_cloudy", "Деревни в разную погоду",
		"Солнце и дождь, туман и снег, закаты и ночи сменяют друг друга сами — деревня каждый раз выглядит по-новому.", true)
	var grid := GridContainer.new()
	# Колонок — сколько влезает по ширине окна (см. _fit).
	_about_grid = grid
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	gallery.add_child(grid)
	for i in range(1, ABOUT_SHOTS.size()):
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(cell)
		_picture(cell, "res://assets/about/%s.jpg" % ABOUT_SHOTS[i][0])
		var cap := UiStyle.label(ABOUT_SHOTS[i][1], 13 if _touch else 14, UiStyle.MUTED, 800)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Подпись переносится по словам и не раздвигает окно.
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cap.custom_minimum_size.x = 80
		cell.add_child(cap)
	var what := _card(page, "icon_buildings", "Что можно делать")
	for line: String in [
		"Строить больше 70 зданий: от шалаша и бани до замка, маяка и водяной мельницы.",
		"Прокладывать дорожки и протягивать ограды любой формы — пальцем или мышью.",
		"Ровнять землю, сеять траву и цветы, сажать сады и огороды.",
		"Добывать лес, камень и руду, открывать сундуки в руинах и ремеслом делать доски, кирпич, стекло и металл.",
		"Ставить метки на карте и путешествовать по огромному миру с озёрами, реками и горами.",
		"Открыть одну из десяти готовых деревень — и сразу гулять по большому живому поселению.",
	]:
		what.add_child(_help_item(what.get_child_count(), line))
	var why := _card(page, "marker_heart", "Почему это увлекательно",
		GameData.GAME_NAME + " — игра, в которую приятно возвращаться: пять минут перед сном или целый вечер. "
		+ "Каждое решение видно сразу — дом встаёт по брёвнышку, дорожка ложится за пальцем, а деревня растёт "
		+ "вместе с вашими задумками. Отлично подходит, чтобы отдохнуть, помечтать и порадоваться результату — "
		+ "одному или вместе с семьёй.", true)
	why.add_child(_desc("Творческий режим снимает все ограничения — стройте сразу, без добычи."))


func _build_help() -> void:
	var intro := _card(_help_box, "icon_modes", "Как играть",
		"Номера на картинках совпадают с пунктами под ними. Можно посмотреть управление для касаний или для мыши.")
	_help_choice(intro)
	var alt := false
	for topic: Dictionary in HELP:
		var box := _card(_help_box, topic["icon"], topic["title"], "", alt)
		alt = not alt
		var path := "res://assets/help/%s.jpg" % topic["image"]
		if ResourceLoader.exists(path):
			var pic := TextureRect.new()
			pic.texture = load(path)
			# Ширину картинке задаёт окно, высота — по пропорциям. Своей ширины у неё нет:
			# иначе она «распирала» бы окно на весь экран.
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			pic.mouse_filter = Control.MOUSE_FILTER_PASS
			var holder := PanelContainer.new()
			holder.add_theme_stylebox_override("panel", UiStyle.box(Color.WHITE, 14, 4, 2, CARD_BORDER))
			holder.mouse_filter = Control.MOUSE_FILTER_PASS
			holder.add_child(pic)
			box.add_child(holder)
			pic.set_meta("aspect", float(pic.texture.get_width()) / pic.texture.get_height())
			holder.resized.connect(func() -> void:
				pic.custom_minimum_size.y = (holder.size.x - 8.0) / float(pic.get_meta("aspect")))
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 6)
		list.mouse_filter = Control.MOUSE_FILTER_PASS
		list.set_meta("topic", topic)
		box.add_child(list)
	_fill_help()


func _help_choice(parent: Control) -> void:
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	_stack_rows.append(row)
	var group := ButtonGroup.new()
	for opt: Array in [[true, "Касания", "tool_harvest"], [false, "Мышь и клавиатура", "settings"]]:
		var b := Button.new()
		b.text = opt[1]
		b.icon = UiStyle.icon(opt[2])
		b.add_theme_constant_override("icon_max_width", 24)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = opt[0] == _help_touch
		b.custom_minimum_size = Vector2(0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.add_theme_stylebox_override("normal", UiStyle.box(Color.WHITE, 12, 8, 2, CARD_BORDER))
		b.add_theme_stylebox_override("pressed", UiStyle.box(Color("#E9DCC8"), 12, 8, 3, UiStyle.BRAND_DARK))
		b.add_theme_stylebox_override("hover_pressed", UiStyle.box(Color("#E9DCC8"), 12, 8, 3, UiStyle.BRAND_DARK))
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_help_touch = opt[0]
				_fill_help())
		row.add_child(b)
	parent.add_child(row)


## Пункты под картинками: номер в оранжевом кружке и пояснение.
func _fill_help() -> void:
	for card in _help_box.get_children():
		for list in card.find_children("*", "VBoxContainer", true, false):
			if not list.has_meta("topic"):
				continue
			for c in list.get_children():
				c.queue_free()
			var topic: Dictionary = list.get_meta("topic")
			var items: Array = topic["touch" if _help_touch else "pc"]
			for i in items.size():
				list.add_child(_help_item(i + 1, items[i]))


func _help_item(n: int, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var num := PanelContainer.new()
	num.add_theme_stylebox_override("panel", UiStyle.box(ACCENT, 13, 0, 2, Color.WHITE))
	num.custom_minimum_size = Vector2(26, 26)
	num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var nl := UiStyle.label(str(n), 14, Color.WHITE, 900)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.add_child(nl)
	row.add_child(num)
	var label := Rich.label(14 if _touch else 15, UiStyle.TEXT, 600)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.text = _keys(text)
	row.add_child(label)
	return row


## Клавиши в фигурных скобках — {Tab}, {ЛКМ} — в плашки.
static func _keys(text: String) -> String:
	var re := RegEx.create_from_string("\\{([^}]+)\\}")
	var out := text
	for m in re.search_all(text):
		var k := m.get_string(1).replace("[", "[lb]").replace("]", "[rb]")
		out = out.replace(m.get_string(0), Rich.key(k))
	return out


func open() -> void:
	_world_title.text = "Мир «%s»" % WorldState.world_name if WorldState.world_name != "" else "Мир"
	_sync()
	_fit()
	_scroll.reset()
	UiStyle.fade(self, true, 0.22)


func _sync() -> void:
	for key: String in _chips_by_key:
		var current: Variant = Settings.get_value(key)
		for value: String in _chips_by_key[key]:
			(_chips_by_key[key][value] as Button).set_pressed_no_signal(current == value)
	for entry: Dictionary in _sliders:
		var slider: HSlider = entry["slider"]
		if slider.has_meta("dragging"):
			continue
		var v := float(Settings.get_value(entry["key"]))
		slider.set_value_no_signal(v)
		(entry["label"] as Label).text = (entry["fmt"] as Callable).call(v)
	for key: String in _toggles:
		(_toggles[key] as CheckButton).set_pressed_no_signal(Settings.get_value(key))


func close() -> void:
	UiStyle.fade(self, false, 0.18)


func is_open() -> bool:
	return get_meta("fade_target", false)


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("cancel"):
		close()
		get_viewport().set_input_as_handled()
