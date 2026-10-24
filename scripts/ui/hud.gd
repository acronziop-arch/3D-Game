class_name Hud
extends CanvasLayer
## Игровой интерфейс. Собирается кодом из стилей UiStyle:
##   слева сверху — основные ресурсы и кнопка «…» со списком всех ресурсов;
##   справа сверху — часы, сезон, погода и шестерёнка настроек;
##   снизу — текущее действие, меню стройки и панель инструментов;
##   справа — ремесло.

signal new_world_requested

const GROUPS := [["raw", "Сырьё"], ["animal", "Из сундуков"], ["processed", "Материалы"]]
const TOOLS := [
	[Interaction.Tool.HARVEST, "tool_harvest", "Добыча", "1"],
	[Interaction.Tool.BUILD, "tool_build", "Стройка", "2"],
	[Interaction.Tool.FLATTEN, "tool_flatten", "Ровнять", "3"],
	[Interaction.Tool.DEMOLISH, "tool_demolish", "Снос", "4"],
]

var interaction: Interaction
var thumbnails: Thumbnails

var _root: Control
var _bottom: VBoxContainer
var _main_counts := {}
var _all_panel: PanelContainer
var _all_counts := {}
var _clock_time: Label
var _clock_icon: TextureRect
var _season_icon: TextureRect
var _weather_icon: TextureRect
var _clock_sub: Label
var _settings: SettingsDialog
var _tool_buttons := {}
var _build_panel: PanelContainer
var _category_buttons := {}
var _build_grid: HFlowContainer
var _build_cards := {}
var _category := "production"
var _craft_panel: PanelContainer
var _craft_rows := {}
var _craft_progress: ProgressBar
var _craft_queue_label: Label
var _job_panel: PanelContainer
var _job_icon: TextureRect
var _job_label: Label
var _job_bar: ProgressBar
var _hover_panel: PanelContainer
var _hover_label: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _loading: Control
var _info_timer := 0.0


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiStyle.make_theme()
	add_child(_root)
	thumbnails = Thumbnails.new()
	add_child(thumbnails)
	thumbnails.thumbnail_ready.connect(_on_thumbnail)

	_bottom = VBoxContainer.new()
	_bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom.position.y = -16
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_theme_constant_override("separation", 10)
	_root.add_child(_bottom)

	_build_resources()
	_build_clock()
	_build_job_panel()
	_build_build_panel()
	_build_toolbar()
	_build_craft_panel()
	_build_hover()
	_build_toast()
	_settings = SettingsDialog.new()
	_root.add_child(_settings)
	_settings.save_requested.connect(func() -> void:
		show_message("Мир сохранён" if WorldState.save_game() else "Не удалось сохранить"))
	_settings.new_world_requested.connect(func() -> void: new_world_requested.emit())
	_build_loading()
	Inventory.changed.connect(_on_inventory_changed)
	Crafting.queue_changed.connect(_refresh_crafting)
	Crafting.crafted.connect(func(id: String) -> void: show_message("Готово: %s" % GameData.RECIPES[id]["name"]))
	Weather.weather_changed.connect(func(_id: String) -> void: show_message("Погода: %s" % Weather.weather_name()))
	Weather.season_changed.connect(func(_i: int) -> void: show_message("Наступает %s" % Weather.season_name().to_lower()))
	_on_inventory_changed("")
	thumbnails.request(GameData.BUILDINGS.keys())


func bind(target: Interaction) -> void:
	interaction = target
	interaction.tool_changed.connect(_on_tool_changed)
	interaction.message.connect(show_message)
	interaction.hover_changed.connect(_on_hover_changed)
	interaction.building_system.placed.connect(func(_b: Building) -> void: _refresh_build_cards())
	_on_tool_changed(interaction.tool)


func is_modal_open() -> bool:
	return _settings.is_open()


# --- Ресурсы ---------------------------------------------------------------------------------

func _build_resources() -> void:
	var bar := PanelContainer.new()
	bar.position = Vector2(16, 16)
	_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	for id: String in GameData.MAIN_RESOURCES:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		item.tooltip_text = GameData.res_name(id)
		item.mouse_filter = Control.MOUSE_FILTER_PASS
		item.add_child(UiStyle.icon_rect(id, 30))
		var count := UiStyle.label("0", 18, UiStyle.TEXT, 800)
		count.custom_minimum_size = Vector2(30, 0)
		item.add_child(count)
		row.add_child(item)
		_main_counts[id] = count
	var more := Button.new()
	more.icon = UiStyle.icon("more")
	more.add_theme_constant_override("icon_max_width", 22)
	more.custom_minimum_size = Vector2(40, 34)
	more.tooltip_text = "Все ресурсы"
	more.pressed.connect(func() -> void: UiStyle.fade(_all_panel, not _all_panel.get_meta("fade_target", false)))
	row.add_child(more)

	_all_panel = PanelContainer.new()
	_all_panel.position = Vector2(16, 76)
	_all_panel.visible = false
	_all_panel.modulate.a = 0.0
	_root.add_child(_all_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_all_panel.add_child(box)
	box.add_child(UiStyle.label("Все ресурсы", 18, UiStyle.TEXT, 800))
	for group: Array in GROUPS:
		box.add_child(UiStyle.label(group[1], 13, UiStyle.BRAND_DARK, 800))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 4)
		for id: String in GameData.RESOURCES:
			if GameData.RESOURCES[id]["group"] != group[0]:
				continue
			var item := HBoxContainer.new()
			item.add_theme_constant_override("separation", 6)
			item.custom_minimum_size = Vector2(190, 34)
			item.add_child(UiStyle.icon_rect(id, 30))
			item.add_child(UiStyle.label(GameData.res_name(id), 15, UiStyle.TEXT, 600))
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item.add_child(spacer)
			var count := UiStyle.label("0", 15, UiStyle.TEXT, 800)
			item.add_child(count)
			grid.add_child(item)
			_all_counts[id] = count
		box.add_child(grid)


func _on_inventory_changed(res_id: String) -> void:
	var ids: Array = GameData.RESOURCES.keys() if res_id == "" else [res_id]
	for id: String in ids:
		var n := Inventory.count(id)
		for map: Dictionary in [_main_counts, _all_counts]:
			if not map.has(id):
				continue
			var l: Label = map[id]
			l.text = str(n)
			l.add_theme_color_override("font_color", UiStyle.TEXT if n > 0 else UiStyle.MUTED)
			if res_id != "":
				l.pivot_offset = l.size * 0.5
				l.scale = Vector2.ONE * 1.35
				l.create_tween().tween_property(l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_build_cards()
	_refresh_crafting()


# --- Часы, погода и настройки ------------------------------------------------------------------

func _build_clock() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.position = Vector2(-16, 16)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(row)
	var clock := PanelContainer.new()
	row.add_child(clock)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	clock.add_child(box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	_clock_icon = UiStyle.icon_rect("clock_day", 26)
	line.add_child(_clock_icon)
	_clock_time = UiStyle.label("12:00", 20, UiStyle.TEXT, 800)
	line.add_child(_clock_time)
	_season_icon = UiStyle.icon_rect("season_summer", 24)
	line.add_child(_season_icon)
	_weather_icon = UiStyle.icon_rect("weather_clear", 26)
	line.add_child(_weather_icon)
	box.add_child(line)
	_clock_sub = UiStyle.label("", 13, UiStyle.MUTED, 700)
	box.add_child(_clock_sub)
	var gear := Button.new()
	gear.icon = UiStyle.icon("settings")
	gear.add_theme_constant_override("icon_max_width", 28)
	gear.custom_minimum_size = Vector2(52, 52)
	gear.add_theme_stylebox_override("normal", UiStyle.panel(16, 10))
	gear.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.BASE, 16, 10, 3, UiStyle.BRAND_DARK, true))
	gear.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.BRAND, 16, 10, 2, UiStyle.BRAND_DARK, true))
	gear.tooltip_text = "Настройки"
	gear.pressed.connect(func() -> void: _settings.open())
	row.add_child(gear)


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
	bar.add_theme_stylebox_override("panel", UiStyle.panel(20, 10))
	_bottom.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	for t: Array in TOOLS:
		var b := _tool_button(t[1], t[2], t[3])
		b.toggle_mode = true
		b.pressed.connect(func() -> void: interaction.set_tool(t[0]))
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
	b.custom_minimum_size = Vector2(92, 74)
	b.tooltip_text = "%s [%s]" % [text, hotkey]
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UiStyle.icon_rect(icon_name, 36)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ic)
	var l := UiStyle.label(text, 13, UiStyle.TEXT, 700)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	b.add_child(box)
	var key := UiStyle.label(hotkey, 11, UiStyle.BRAND_DARK, 800)
	key.position = Vector2(6, 3)
	b.add_child(key)
	return b


func _on_tool_changed(tool: Interaction.Tool) -> void:
	for t in _tool_buttons:
		_tool_buttons[t].set_pressed_no_signal(t == tool)
	UiStyle.fade(_build_panel, tool == Interaction.Tool.BUILD)
	if tool == Interaction.Tool.BUILD:
		_refresh_build_cards()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_crafting"):
		toggle_crafting()
	elif event.is_action_pressed("quick_save"):
		show_message("Мир сохранён" if WorldState.save_game() else "Не удалось сохранить")
	elif event.is_action_pressed("cancel") and _all_panel.get_meta("fade_target", false):
		UiStyle.fade(_all_panel, false)
		get_viewport().set_input_as_handled()


# --- Меню стройки ---------------------------------------------------------------------------------

func _build_build_panel() -> void:
	_build_panel = PanelContainer.new()
	_build_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_build_panel.custom_minimum_size = Vector2(980, 0)
	_build_panel.visible = false
	_build_panel.modulate.a = 0.0
	_bottom.add_child(_build_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_build_panel.add_child(box)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for cat: String in GameData.BUILDING_CATEGORIES:
		var b := Button.new()
		b.text = GameData.BUILDING_CATEGORIES[cat]
		b.icon = UiStyle.icon("cat_" + cat)
		b.add_theme_constant_override("icon_max_width", 22)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = cat == _category
		b.custom_minimum_size = Vector2(0, 38)
		b.pressed.connect(func() -> void:
			_category = cat
			_refresh_build_cards())
		tabs.add_child(b)
		_category_buttons[cat] = b
	box.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 186)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_build_grid = HFlowContainer.new()
	_build_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_grid.add_theme_constant_override("h_separation", 8)
	_build_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_build_grid)
	for id: String in GameData.BUILDINGS:
		_build_cards[id] = _make_card(id)
		_build_grid.add_child(_build_cards[id]["button"])


func _make_card(id: String) -> Dictionary:
	var def: Dictionary = GameData.BUILDINGS[id]
	var b := Button.new()
	b.custom_minimum_size = Vector2(178, 178)
	b.tooltip_text = def["desc"]
	b.pressed.connect(func() -> void: interaction.start_building(id))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(0, 96)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.texture = thumbnails.textures.get(id, UiStyle.icon("cat_" + def["category"]))
	box.add_child(thumb)
	var title := UiStyle.label(def["name"], 14, UiStyle.TEXT, 800)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(title)
	var time_row := HBoxContainer.new()
	time_row.alignment = BoxContainer.ALIGNMENT_CENTER
	time_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_row.add_child(UiStyle.icon_rect("timer", 14))
	time_row.add_child(UiStyle.label("%d с" % def["time"], 12, UiStyle.MUTED, 700))
	box.add_child(time_row)
	var cost_holder := CenterContainer.new()
	cost_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cost_holder)
	return {"button": b, "thumb": thumb, "cost": cost_holder}


func _on_thumbnail(id: String, tex: Texture2D) -> void:
	if _build_cards.has(id):
		_build_cards[id]["thumb"].texture = tex


func _refresh_build_cards() -> void:
	if _build_cards.is_empty():
		return
	for id: String in _build_cards:
		var def: Dictionary = GameData.BUILDINGS[id]
		var card: Dictionary = _build_cards[id]
		var b: Button = card["button"]
		b.visible = def["category"] == _category
		if not b.visible:
			continue
		var holder: CenterContainer = card["cost"]
		for c in holder.get_children():
			c.queue_free()
		holder.add_child(UiStyle.cost_row(def["cost"], 18))
		var selected := interaction != null and interaction.building_system.selected_id == id
		b.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.BRAND.lightened(0.35) if selected else UiStyle.SURFACE, 14, 8,
			2 if selected else 0, UiStyle.BRAND_DARK))
		b.modulate = Color.WHITE if Inventory.has_all(def["cost"]) else Color(1, 1, 1, 0.78)


# --- Ремесло --------------------------------------------------------------------------------------

func _build_craft_panel() -> void:
	_craft_panel = PanelContainer.new()
	_craft_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_craft_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_craft_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_craft_panel.position.x = -16
	_craft_panel.custom_minimum_size = Vector2(440, 0)
	_craft_panel.visible = false
	_craft_panel.modulate.a = 0.0
	_root.add_child(_craft_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_craft_panel.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.add_child(UiStyle.icon_rect("tool_craft", 28))
	header.add_child(UiStyle.label("Ремесло", 22, UiStyle.TEXT, 800))
	box.add_child(header)
	_craft_queue_label = UiStyle.label("", 13, UiStyle.MUTED, 700)
	box.add_child(_craft_queue_label)
	_craft_progress = ProgressBar.new()
	_craft_progress.max_value = 1.0
	_craft_progress.show_percentage = false
	_craft_progress.custom_minimum_size = Vector2(0, 8)
	box.add_child(_craft_progress)
	for id: String in GameData.RECIPES:
		var r: Dictionary = GameData.RECIPES[id]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.SURFACE, 12, 8))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		row.add_child(line)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		var formula := HBoxContainer.new()
		formula.add_theme_constant_override("separation", 6)
		var ins := HBoxContainer.new()
		formula.add_child(ins)
		formula.add_child(UiStyle.label("→", 16, UiStyle.BRAND_DARK, 800))
		formula.add_child(UiStyle.cost_row(r["out"], 20, false))
		info.add_child(formula)
		var sub := UiStyle.label("", 12, UiStyle.MUTED, 700)
		info.add_child(sub)
		line.add_child(info)
		var b := Button.new()
		b.text = "Сделать"
		b.custom_minimum_size = Vector2(96, 36)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void:
			var reason := Crafting.enqueue(id)
			if reason != "":
				show_message(reason))
		line.add_child(b)
		box.add_child(row)
		_craft_rows[id] = {"button": b, "sub": sub, "ins": ins}


func toggle_crafting() -> void:
	UiStyle.fade(_craft_panel, not _craft_panel.get_meta("fade_target", false))
	_refresh_crafting()


func _refresh_crafting() -> void:
	if _craft_rows.is_empty():
		return
	for id: String in _craft_rows:
		var r: Dictionary = GameData.RECIPES[id]
		var row: Dictionary = _craft_rows[id]
		var reason := Crafting.check(id)
		var station: String = GameData.BUILDINGS[r["station"]]["name"]
		row["sub"].text = "%s · %d с%s" % [station, r["time"], "" if reason == "" else " · " + reason]
		row["sub"].add_theme_color_override("font_color", UiStyle.MUTED if reason == "" else UiStyle.BAD)
		row["button"].disabled = reason != ""
		var ins: HBoxContainer = row["ins"]
		for c in ins.get_children():
			c.queue_free()
		ins.add_child(UiStyle.cost_row(r["in"], 20))
	if Crafting.queue.is_empty():
		_craft_queue_label.text = "Очередь пуста"
	else:
		var names: PackedStringArray = []
		for id in Crafting.queue:
			names.append(GameData.RECIPES[id]["name"])
		_craft_queue_label.text = "В работе: " + ", ".join(names)


# --- Текущее действие, подсказки, сообщения ---------------------------------------------------------

func _build_job_panel() -> void:
	_job_panel = PanelContainer.new()
	_job_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_job_panel.custom_minimum_size = Vector2(400, 0)
	_job_panel.visible = false
	_job_panel.modulate.a = 0.0
	_bottom.add_child(_job_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_job_panel.add_child(row)
	_job_icon = UiStyle.icon_rect("tool_harvest", 32)
	row.add_child(_job_icon)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	row.add_child(box)
	_job_label = UiStyle.label("", 15, UiStyle.TEXT, 700)
	box.add_child(_job_label)
	_job_bar = ProgressBar.new()
	_job_bar.max_value = 1.0
	_job_bar.show_percentage = false
	_job_bar.custom_minimum_size = Vector2(0, 10)
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
	_job_bar.value = lerpf(_job_bar.value, interaction.current_job_fraction(), 0.5)


func _build_hover() -> void:
	_hover_panel = PanelContainer.new()
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(UiStyle.BASE, 0.97), 10, 9, 2, UiStyle.BRAND, true))
	_hover_panel.visible = false
	_root.add_child(_hover_panel)
	_hover_label = UiStyle.label("", 14, UiStyle.TEXT, 700)
	_hover_panel.add_child(_hover_label)


func _on_hover_changed(text: String) -> void:
	_hover_label.text = text
	_hover_panel.reset_size()
	_hover_panel.visible = text != ""


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position.y = 96
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel", UiStyle.box(Color(UiStyle.BASE, 0.97), 22, 12, 2, UiStyle.BRAND, true))
	_toast.modulate.a = 0.0
	_root.add_child(_toast)
	_toast_label = UiStyle.label("", 17, UiStyle.TEXT, 700)
	_toast.add_child(_toast_label)


func show_message(text: String) -> void:
	_toast_label.text = text
	_toast.reset_size()
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = _toast.create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_interval(2.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _build_loading() -> void:
	_loading = ColorRect.new()
	(_loading as ColorRect).color = UiStyle.BASE
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_loading)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading.add_child(box)
	var title := UiStyle.label("Тихие Земли", 54, UiStyle.TEXT, 900)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var line := ColorRect.new()
	line.color = UiStyle.BRAND
	line.custom_minimum_size = Vector2(220, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(line)
	var sub := UiStyle.label("Создаём мир…", 20, UiStyle.BRAND_DARK, 700)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)


func hide_loading() -> void:
	var tw := _loading.create_tween()
	tw.tween_property(_loading, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_loading.queue_free)


func _process(delta: float) -> void:
	_info_timer -= delta
	if _info_timer <= 0.0:
		_info_timer = 0.25
		_update_clock()
	if interaction:
		_update_job_panel()
		_craft_progress.value = Crafting.current_fraction()
	if _hover_panel.visible:
		var target := get_viewport().get_mouse_position() + Vector2(22, 22)
		var vp := get_viewport().get_visible_rect().size
		target.x = minf(target.x, vp.x - _hover_panel.size.x - 8)
		target.y = minf(target.y, vp.y - _hover_panel.size.y - 8)
		_hover_panel.position = _hover_panel.position.lerp(target, 1.0 - exp(-25.0 * delta))
