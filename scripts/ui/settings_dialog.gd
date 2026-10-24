class_name SettingsDialog
extends Control
## Модальное окно настроек: время суток, погода, времена года, графика.
## Открывается шестерёнкой справа сверху, закрывается крестиком, Esc или кликом мимо.

signal new_world_requested
signal save_requested

var _panel: PanelContainer
var _value_labels := {}
var _confirm_new := false
var _new_button: Button


func _ready() -> void:
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
	_panel.add_theme_stylebox_override("panel", UiStyle.panel(22, 22))
	_panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.add_child(UiStyle.icon_rect("settings", 30))
	header.add_child(UiStyle.label("Настройки", 26, UiStyle.TEXT, 800))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_btn := Button.new()
	close_btn.icon = UiStyle.icon("close")
	close_btn.add_theme_constant_override("icon_max_width", 20)
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.tooltip_text = "Закрыть (Esc)"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	box.add_child(header)

	_section(box, "Время суток")
	_chips(box, "time_mode", [["auto", "Авто", "auto"], ["day", "Только день", "day"], ["night", "Только ночь", "night"]], 3)
	_slider(box, "day_minutes", "Длина суток", 4.0, 30.0, 1.0, func(v: float) -> String: return "%d мин" % v)

	_section(box, "Погода")
	var weather := [["auto", "Авто", "auto"]]
	for id: String in Weather.WEATHERS:
		weather.append([id, Weather.WEATHERS[id]["name"], "weather_" + id])
	_chips(box, "weather_mode", weather, 5)

	_section(box, "Время года")
	var seasons := [["auto", "Авто", "auto"]]
	for s: Dictionary in Weather.SEASONS:
		seasons.append([s["id"], s["name"], "season_" + s["id"]])
	_chips(box, "season_mode", seasons, 5)
	_slider(box, "season_days", "Длина сезона", 1.0, 10.0, 1.0, func(v: float) -> String: return "%d сут." % v)

	_section(box, "Графика")
	var toggles := GridContainer.new()
	toggles.columns = 3
	toggles.add_theme_constant_override("h_separation", 18)
	for entry in [["reflections", "Отражения на воде"], ["shadows", "Тени"], ["fish", "Рыбы в воде"]]:
		var cb := CheckButton.new()
		cb.text = entry[1]
		cb.button_pressed = Settings.get_value(entry[0])
		cb.toggled.connect(func(on: bool) -> void: Settings.set_value(entry[0], on))
		toggles.add_child(cb)
	box.add_child(toggles)
	_slider(box, "view_distance", "Дальность прорисовки", 4.0, 10.0, 1.0, func(v: float) -> String: return "%d м" % (v * 32))

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	footer.alignment = BoxContainer.ALIGNMENT_END
	var save := Button.new()
	save.text = "Сохранить мир"
	save.custom_minimum_size = Vector2(170, 42)
	save.pressed.connect(func() -> void: save_requested.emit())
	footer.add_child(save)
	_new_button = Button.new()
	_new_button.text = "Новый мир"
	_new_button.custom_minimum_size = Vector2(170, 42)
	_new_button.add_theme_color_override("font_color", UiStyle.BAD)
	_new_button.add_theme_color_override("font_hover_color", UiStyle.BAD)
	_new_button.pressed.connect(_on_new_world)
	footer.add_child(_new_button)
	box.add_child(footer)


func _section(parent: Control, title: String) -> void:
	var l := UiStyle.label(title, 15, UiStyle.BRAND_DARK, 800)
	parent.add_child(l)


func _chips(parent: Control, key: String, options: Array, columns: int) -> void:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var group := ButtonGroup.new()
	for opt in options:
		var b := Button.new()
		b.text = opt[1]
		b.icon = UiStyle.icon(opt[2])
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_constant_override("icon_max_width", 24)
		b.add_theme_constant_override("h_separation", 8)
		b.custom_minimum_size = Vector2(136, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = Settings.get_value(key) == opt[0]
		b.toggled.connect(func(on: bool) -> void:
			if on:
				Settings.set_value(key, opt[0]))
		grid.add_child(b)
	parent.add_child(grid)


func _slider(parent: Control, key: String, title: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UiStyle.label(title, 15, UiStyle.TEXT, 600)
	l.custom_minimum_size = Vector2(200, 0)
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
	value.custom_minimum_size = Vector2(80, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	s.value_changed.connect(func(v: float) -> void:
		value.text = fmt.call(v)
		Settings.set_value(key, int(v) if key == "view_distance" else v))
	parent.add_child(row)


func _on_new_world() -> void:
	if not _confirm_new:
		_confirm_new = true
		_new_button.text = "Точно? Ещё раз"
		return
	new_world_requested.emit()


func open() -> void:
	_confirm_new = false
	_new_button.text = "Новый мир"
	UiStyle.fade(self, true, 0.22)


func close() -> void:
	UiStyle.fade(self, false, 0.18)


func is_open() -> bool:
	return get_meta("fade_target", false)


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("cancel"):
		close()
		get_viewport().set_input_as_handled()
