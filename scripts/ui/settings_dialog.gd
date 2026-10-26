class_name SettingsDialog
extends Control
## Модальное окно настроек: режим игры, время суток, погода, времена года, графика.
## Открывается шестерёнкой справа сверху, закрывается крестиком, Esc или кликом мимо.
## Содержимое листается (на телефоне — пальцем, с пружиной у краёв, как в iOS),
## а окно не заходит под вырез экрана.

signal new_world_requested
signal save_requested

const WIDTH := 760.0

var _panel: PanelContainer
## Элементы, которые при открытии окна заново читают значения из Settings
## (настройки могли поменяться не через это окно).
var _chips_by_key := {}
var _sliders := []
var _toggles := {}
var _confirm_new := false
var _new_button: Button
var _touch := false
var _scroll: SmoothScroll
var _body: VBoxContainer


func _ready() -> void:
	_touch = Platform.is_touch
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	modulate.a = 0.0
	var dim := ColorRect.new()
	dim.color = Color(0.18, 0.13, 0.09, 0.38)
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
	_panel.add_theme_stylebox_override("panel", UiStyle.panel(22, 16 if _touch else 22))
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	center.add_child(_panel)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 10 if _touch else 12)
	_panel.add_child(frame)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.add_child(UiStyle.icon_rect("settings", 26 if _touch else 30))
	header.add_child(UiStyle.label("Настройки", 22 if _touch else 26, UiStyle.TEXT, 800))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_btn := UiStyle.close_button(44.0 if _touch else 40.0)
	close_btn.tooltip_text = "Закрыть (Esc)"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	frame.add_child(header)

	_scroll = SmoothScroll.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(_scroll)
	# Справа поле, чтобы полоска прокрутки не наезжала на значения.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_left", 2)
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10 if _touch else 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_child(box)
	_body = box

	_section(box, "Игра")
	_chips(box, "game_mode", [["normal", "Обычный", "tool_harvest"], ["creative", "Творческий", "marker_star"]], 2)
	box.add_child(_hint(
		"Творческий режим: ресурсы не кончаются, здания появляются сразу, а добыча и ремесло — мгновенные."))
	_toggle_grid(box, [["keep_cleared", "Не выращивать траву и деревья на выровненной земле"]], 1)

	_section(box, "Время суток")
	_chips(box, "time_mode", [["auto", "Авто", "auto"], ["day", "Только день", "day"], ["night", "Только ночь", "night"]], 3)
	_slider(box, "day_minutes", "Длина суток", 4.0, 30.0, 1.0, func(v: float) -> String: return "%d мин" % v)

	_section(box, "Погода")
	var weather := [["auto", "Авто", "auto"]]
	for id: String in Weather.WEATHERS:
		weather.append([id, Weather.WEATHERS[id]["name"], "weather_" + id])
	_chips(box, "weather_mode", weather, 5 if not _touch else 4)

	_section(box, "Время года")
	var seasons := [["auto", "Авто", "auto"]]
	for s: Dictionary in Weather.SEASONS:
		seasons.append([s["id"], s["name"], "season_" + s["id"]])
	_chips(box, "season_mode", seasons, 5 if not _touch else 3)
	_slider(box, "season_days", "Длина сезона", 1.0, 10.0, 1.0, func(v: float) -> String: return "%d сут." % v)

	_section(box, "Графика")
	var quality := [["auto", "Авто", "auto"]]
	for level: String in Settings.QUALITY_LEVELS:
		quality.append([level, Settings.QUALITY_NAMES[level], ""])
	quality.append(["custom", "Своё", ""])
	_chips(box, "quality", quality, 6 if not _touch else 3)
	box.add_child(_hint("«Авто» подбирает качество под устройство и понижает его, если игра начинает подтормаживать."))
	_row_label(box, "Тени")
	_chips(box, "shadow_quality", [["off", "Нет", ""], ["low", "Простые", ""], ["medium", "Средние", ""], ["high", "Мягкие", ""]], 4)
	var entries := [["reflections", "Отражения на воде"], ["fish", "Рыбы в воде"]]
	if Platform.is_mobile():
		entries.append(["haptics", "Вибрация"])
	_toggle_grid(box, entries, 2 if _touch else 3)
	_slider(box, "view_distance", "Дальность прорисовки", 4.0, 10.0, 1.0, func(v: float) -> String: return "%d м" % (v * 32))
	# Трава пересеивается в каждом чанке — применяем, когда ползунок отпустили.
	_slider(box, "grass", "Густота травы", 0.0, 1.0, 0.05, func(v: float) -> String: return "%d%%" % roundi(v * 100.0), true)
	_slider(box, "grass_distance", "Дальность травы", 25.0, 140.0, 5.0, func(v: float) -> String: return "%d м" % v, true)
	_slider(box, "render_scale", "Чёткость картинки", 0.5, 1.0, 0.05, func(v: float) -> String: return "%d%%" % roundi(v * 100.0), true)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	footer.alignment = BoxContainer.ALIGNMENT_END
	var save := Button.new()
	save.text = "Сохранить мир"
	save.custom_minimum_size = Vector2(170, 44 if _touch else 42)
	save.pressed.connect(func() -> void: save_requested.emit())
	footer.add_child(save)
	_new_button = Button.new()
	_new_button.text = "Новый мир"
	_new_button.custom_minimum_size = Vector2(170, 44 if _touch else 42)
	_new_button.add_theme_color_override("font_color", UiStyle.BAD)
	_new_button.add_theme_color_override("font_hover_color", UiStyle.BAD)
	_new_button.pressed.connect(_on_new_world)
	footer.add_child(_new_button)
	frame.add_child(footer)
	Platform.layout_changed.connect(_fit)
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()
	Settings.changed.connect(func(_key: String) -> void:
		if is_open():
			_sync())


## Окно не шире экрана без вырезов и не выше его — остальное листается.
func _fit() -> void:
	var m := Platform.safe_margins()
	var vp := get_viewport_rect().size
	_panel.custom_minimum_size.x = minf(WIDTH, vp.x - m["left"] - m["right"] - 12.0)
	var chrome := (44.0 + 44.0 + 56.0 + 20.0) if _touch else (40.0 + 42.0 + 70.0 + 24.0)
	var room: float = vp.y - m["top"] - m["bottom"] - chrome
	_scroll.custom_minimum_size.y = minf(_body.get_combined_minimum_size().y, maxf(room, 120.0))


func _section(parent: Control, title: String) -> void:
	var l := UiStyle.label(title, 15, UiStyle.BRAND_DARK, 800)
	parent.add_child(l)


func _row_label(parent: Control, title: String) -> void:
	parent.add_child(UiStyle.label(title, 15, UiStyle.TEXT, 600))


func _hint(text: String) -> Label:
	var l := UiStyle.label(text, 13, UiStyle.MUTED, 600)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200
	return l


func _toggle_grid(parent: Control, entries: Array, columns: int) -> void:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 18)
	for entry: Array in entries:
		var cb := CheckButton.new()
		cb.text = entry[1]
		cb.button_pressed = Settings.get_value(entry[0])
		cb.toggled.connect(func(on: bool) -> void: Settings.set_value(entry[0], on))
		cb.mouse_filter = Control.MOUSE_FILTER_PASS
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _touch:
			cb.custom_minimum_size.y = 44
		grid.add_child(cb)
		_toggles[entry[0]] = cb
	parent.add_child(grid)


func _chips(parent: Control, key: String, options: Array, columns: int) -> void:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var group := ButtonGroup.new()
	_chips_by_key[key] = {}
	for opt in options:
		var b := Button.new()
		b.text = opt[1]
		if opt[2] != "":
			b.icon = UiStyle.icon(opt[2])
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_constant_override("icon_max_width", 24)
		b.add_theme_constant_override("h_separation", 8)
		b.custom_minimum_size = Vector2(104, 44) if _touch else Vector2(112, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		# Иначе список не листается, если палец начал движение на кнопке.
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.button_pressed = Settings.get_value(key) == opt[0]
		b.toggled.connect(func(on: bool) -> void:
			if on:
				Settings.set_value(key, opt[0]))
		grid.add_child(b)
		_chips_by_key[key][opt[0]] = b
	parent.add_child(grid)


## on_release — сохранять значение, только когда ползунок отпустили (тяжёлые настройки).
func _slider(parent: Control, key: String, title: String, lo: float, hi: float, step: float, fmt: Callable, on_release := false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	if _touch:
		row.custom_minimum_size.y = 40
	var l := UiStyle.label(title, 15, UiStyle.TEXT, 600)
	l.custom_minimum_size = Vector2(170 if _touch else 210, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var value := UiStyle.label(fmt.call(s.value), 15, UiStyle.BRAND_DARK, 800)
	value.custom_minimum_size = Vector2(72, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
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
	parent.add_child(row)
	_sliders.append({"key": key, "slider": s, "label": value, "fmt": fmt})


func _on_new_world() -> void:
	if not _confirm_new:
		_confirm_new = true
		_new_button.text = "Точно? Ещё раз"
		return
	new_world_requested.emit()


func open() -> void:
	_confirm_new = false
	_new_button.text = "Новый мир"
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
