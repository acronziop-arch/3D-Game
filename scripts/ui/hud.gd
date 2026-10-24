class_name Hud
extends CanvasLayer
## Интерфейс собирается кодом, чтобы его было легко менять вместе с данными.
## Позже его можно перенести в сцены .tscn и красиво оформить в редакторе.

const TEXT := Color(0.98, 0.94, 0.86)
const MUTED := Color(0.75, 0.7, 0.62)
const ACCENT := Color(0.9, 0.66, 0.32)
const BAD := Color(1.0, 0.5, 0.42)
const GROUP_ORDER := ["raw", "animal", "processed"]

var interaction: Interaction

var _root: Control
var _bottom: VBoxContainer
var _resources: HFlowContainer
var _resource_labels := {}
var _empty_label: Label
var _biome: Label
var _tool_buttons := {}
var _build_panel: PanelContainer
var _build_tabs: TabBar
var _build_grid: HFlowContainer
var _build_buttons := {}
var _craft_panel: PanelContainer
var _craft_rows := {}
var _craft_progress: ProgressBar
var _craft_queue_label: Label
var _job_panel: PanelContainer
var _job_label: Label
var _job_bar: ProgressBar
var _hover_panel: PanelContainer
var _hover_label: Label
var _toast: Label
var _toast_tween: Tween
var _loading: ColorRect
var _category := "production"
var _biome_timer := 0.0


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	# Нижняя стопка: текущее действие, меню стройки, инструменты.
	# Скрытые панели не занимают места, остальные сами сдвигаются вверх.
	_bottom = VBoxContainer.new()
	_bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom.position.y = -16
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_theme_constant_override("separation", 10)
	_root.add_child(_bottom)
	_build_top_bar()
	_build_job_panel()
	_build_build_panel()
	_build_toolbar()
	_build_craft_panel()
	_build_hover()
	_build_toast()
	_build_loading()
	Inventory.changed.connect(_on_inventory_changed)
	Crafting.queue_changed.connect(_refresh_crafting)
	Crafting.crafted.connect(func(id: String) -> void: show_message("Готово: %s" % GameData.RECIPES[id]["name"]))
	_on_inventory_changed("")


func bind(target: Interaction) -> void:
	interaction = target
	interaction.tool_changed.connect(_on_tool_changed)
	interaction.message.connect(show_message)
	interaction.hover_changed.connect(_on_hover_changed)
	interaction.building_system.placed.connect(func(_b: Building) -> void: _refresh_build_buttons())
	_on_tool_changed(interaction.tool)


# --- Оформление ---------------------------------------------------------------------

static func _box(color: Color, radius := 10, margin := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.13, 0.11, 0.09, 0.8), 12, 12))
	t.set_stylebox("normal", "Button", _box(Color(0.24, 0.2, 0.16, 0.92), 8, 8))
	t.set_stylebox("hover", "Button", _box(Color(0.34, 0.28, 0.21, 0.95), 8, 8))
	t.set_stylebox("pressed", "Button", _box(ACCENT.darkened(0.25), 8, 8))
	t.set_stylebox("hover_pressed", "Button", _box(ACCENT.darkened(0.15), 8, 8))
	t.set_stylebox("disabled", "Button", _box(Color(0.2, 0.18, 0.16, 0.7), 8, 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.2))
	t.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.4), 6, 0))
	t.set_stylebox("fill", "ProgressBar", _box(ACCENT, 6, 0))
	t.set_stylebox("tab_selected", "TabBar", _box(ACCENT.darkened(0.25), 8, 8))
	t.set_stylebox("tab_unselected", "TabBar", _box(Color(0.24, 0.2, 0.16, 0.9), 8, 8))
	t.set_stylebox("tab_hovered", "TabBar", _box(Color(0.34, 0.28, 0.21, 0.95), 8, 8))
	t.set_color("font_selected_color", "TabBar", Color.WHITE)
	t.set_color("font_unselected_color", "TabBar", TEXT)
	t.set_color("font_hovered_color", "TabBar", Color.WHITE)
	return t


func _label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Плавное появление/исчезновение панели.
func _fade(c: Control, shown: bool) -> void:
	if c.get_meta("fade_target", c.visible) == shown:
		return
	c.set_meta("fade_target", shown)
	if c.has_meta("fade_tween"):
		(c.get_meta("fade_tween") as Tween).kill()
	var tw := c.create_tween()
	c.set_meta("fade_tween", tw)
	if shown:
		c.visible = true
		tw.tween_property(c, "modulate:a", 1.0, 0.18)
	else:
		tw.tween_property(c, "modulate:a", 0.0, 0.15)
		tw.tween_callback(c.hide)


# --- Верхняя панель: ресурсы и биом ------------------------------------------------------

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.size = Vector2(560, 0)
	_root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_empty_label = _label("Склад пуст — щёлкните по дереву, чтобы срубить его", 15, MUTED)
	box.add_child(_empty_label)
	_resources = HFlowContainer.new()
	_resources.add_theme_constant_override("h_separation", 14)
	_resources.add_theme_constant_override("v_separation", 6)
	box.add_child(_resources)

	var info := PanelContainer.new()
	info.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info.position = Vector2(-16, 16)
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.add_child(info)
	var info_box := VBoxContainer.new()
	info.add_child(info_box)
	_biome = _label("", 18)
	_biome.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_box.add_child(_biome)
	var hint := _label("F5 — сохранить · Esc — отмена", 13, MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_box.add_child(hint)


func _on_inventory_changed(res_id: String) -> void:
	if res_id == "":
		for c in _resources.get_children():
			c.queue_free()
		_resource_labels.clear()
		for group: String in GROUP_ORDER:
			for id: String in GameData.RESOURCES:
				if GameData.RESOURCES[id]["group"] == group and Inventory.count(id) > 0:
					_update_resource(id, false)
	else:
		_update_resource(res_id, true)
	_empty_label.visible = _resource_labels.is_empty()
	_refresh_build_buttons()
	_refresh_crafting()


func _update_resource(id: String, flash: bool) -> void:
	if not _resource_labels.has(id):
		if Inventory.count(id) <= 0:
			return
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.add_theme_stylebox_override("panel", _box(GameData.res_color(id), 4, 0))
		row.add_child(swatch)
		var l := _label("")
		row.add_child(l)
		_resources.add_child(row)
		_resource_labels[id] = l
	var label: Label = _resource_labels[id]
	label.text = "%s %d" % [GameData.res_name(id), Inventory.count(id)]
	if flash:
		label.modulate = Color(1.6, 1.4, 0.8)
		label.create_tween().tween_property(label, "modulate", Color.WHITE, 0.6)


func _process(delta: float) -> void:
	_biome_timer -= delta
	if _biome_timer <= 0.0 and interaction:
		_biome_timer = 0.5
		var p := interaction.camera_rig.global_position
		_biome.text = interaction.chunk_manager.get_biome_name(p.x, p.z)
	if interaction:
		_update_job_panel()
		_craft_progress.value = Crafting.current_fraction()
	if _hover_panel.visible:
		var target := get_viewport().get_mouse_position() + Vector2(22, 22)
		var vp := get_viewport().get_visible_rect().size
		target.x = minf(target.x, vp.x - _hover_panel.size.x - 8)
		target.y = minf(target.y, vp.y - _hover_panel.size.y - 8)
		_hover_panel.position = _hover_panel.position.lerp(target, 1.0 - exp(-25.0 * delta))


# --- Нижняя панель инструментов -------------------------------------------------------------

func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bottom.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	var tools := [
		[Interaction.Tool.HARVEST, "1  Добыча"],
		[Interaction.Tool.BUILD, "2  Стройка"],
		[Interaction.Tool.FLATTEN, "3  Выравнивание"],
		[Interaction.Tool.DEMOLISH, "4  Снос"],
	]
	for entry in tools:
		var b := Button.new()
		b.text = entry[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(130, 40)
		b.pressed.connect(func() -> void: interaction.set_tool(entry[0]))
		row.add_child(b)
		_tool_buttons[entry[0]] = b
	var craft := Button.new()
	craft.text = "C  Ремесло"
	craft.custom_minimum_size = Vector2(130, 40)
	craft.pressed.connect(toggle_crafting)
	row.add_child(craft)


func _on_tool_changed(tool: Interaction.Tool) -> void:
	for t in _tool_buttons:
		_tool_buttons[t].set_pressed_no_signal(t == tool)
	_fade(_build_panel, tool == Interaction.Tool.BUILD)
	if tool == Interaction.Tool.BUILD:
		_refresh_build_buttons()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_crafting"):
		toggle_crafting()
	elif event.is_action_pressed("quick_save"):
		show_message("Мир сохранён" if WorldState.save_game() else "Не удалось сохранить")


# --- Меню строительства ------------------------------------------------------------------------

func _build_build_panel() -> void:
	_build_panel = PanelContainer.new()
	_build_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_build_panel.custom_minimum_size = Vector2(900, 0)
	_build_panel.visible = false
	_build_panel.modulate.a = 0.0
	_bottom.add_child(_build_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_build_panel.add_child(box)
	_build_tabs = TabBar.new()
	for cat: String in GameData.BUILDING_CATEGORIES:
		_build_tabs.add_tab(GameData.BUILDING_CATEGORIES[cat])
	_build_tabs.tab_changed.connect(func(i: int) -> void:
		_category = GameData.BUILDING_CATEGORIES.keys()[i]
		_refresh_build_buttons())
	box.add_child(_build_tabs)
	_build_grid = HFlowContainer.new()
	_build_grid.add_theme_constant_override("h_separation", 8)
	_build_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_build_grid)
	for id: String in GameData.BUILDINGS:
		var def: Dictionary = GameData.BUILDINGS[id]
		var b := Button.new()
		b.custom_minimum_size = Vector2(210, 86)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = "%s · %d с\n%s" % [def["name"], def["time"], GameData.cost_text(def["cost"])]
		b.tooltip_text = def["desc"]
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func() -> void: interaction.start_building(id))
		_build_grid.add_child(b)
		_build_buttons[id] = b


func _refresh_build_buttons() -> void:
	if _build_grid == null:
		return
	for id: String in _build_buttons:
		var def: Dictionary = GameData.BUILDINGS[id]
		var b: Button = _build_buttons[id]
		b.visible = def["category"] == _category
		var affordable := Inventory.has_all(def["cost"])
		b.modulate = Color.WHITE if affordable else Color(1, 1, 1, 0.55)
		var selected := interaction != null and interaction.building_system.selected_id == id
		b.add_theme_color_override("font_color", ACCENT.lightened(0.3) if selected else TEXT)


# --- Ремесло -------------------------------------------------------------------------------------

func _build_craft_panel() -> void:
	_craft_panel = PanelContainer.new()
	_craft_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_craft_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_craft_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_craft_panel.position.x = -16
	_craft_panel.custom_minimum_size = Vector2(430, 0)
	_craft_panel.visible = false
	_craft_panel.modulate.a = 0.0
	_root.add_child(_craft_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_craft_panel.add_child(box)
	box.add_child(_label("Ремесло", 20, ACCENT.lightened(0.2)))
	_craft_queue_label = _label("", 14, MUTED)
	box.add_child(_craft_queue_label)
	_craft_progress = ProgressBar.new()
	_craft_progress.max_value = 1.0
	_craft_progress.show_percentage = false
	_craft_progress.custom_minimum_size = Vector2(0, 10)
	box.add_child(_craft_progress)
	for id: String in GameData.RECIPES:
		var r: Dictionary = GameData.RECIPES[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		info.add_child(_label("%s → %s" % [GameData.cost_text(r["in"]), GameData.cost_text(r["out"])], 15))
		var sub := _label("", 13, MUTED)
		info.add_child(sub)
		row.add_child(info)
		var b := Button.new()
		b.text = "Сделать"
		b.custom_minimum_size = Vector2(96, 34)
		b.pressed.connect(func() -> void:
			var reason := Crafting.enqueue(id)
			if reason != "":
				show_message(reason))
		row.add_child(b)
		box.add_child(row)
		_craft_rows[id] = {"button": b, "sub": sub}


func toggle_crafting() -> void:
	_fade(_craft_panel, not _craft_panel.get_meta("fade_target", false))
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
		row["sub"].add_theme_color_override("font_color", MUTED if reason == "" else BAD)
		row["button"].disabled = reason != ""
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
	_job_panel.custom_minimum_size = Vector2(380, 0)
	_job_panel.visible = false
	_job_panel.modulate.a = 0.0
	_bottom.add_child(_job_panel)
	var box := VBoxContainer.new()
	_job_panel.add_child(box)
	_job_label = _label("", 16)
	_job_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_job_label)
	_job_bar = ProgressBar.new()
	_job_bar.max_value = 1.0
	_job_bar.show_percentage = false
	_job_bar.custom_minimum_size = Vector2(0, 12)
	box.add_child(_job_bar)


func _update_job_panel() -> void:
	var jobs := interaction.jobs
	_fade(_job_panel, not jobs.is_empty())
	if jobs.is_empty():
		return
	var job: Dictionary = jobs[0]
	var verb := "Открываем" if job["kind"] == "chest" else "Добываем"
	var rest := "" if jobs.size() == 1 else "  (+%d в очереди)" % (jobs.size() - 1)
	_job_label.text = "%s: %s  %.1f / %.0f с%s" % [verb, job["name"], minf(job["elapsed"], job["time"]), job["time"], rest]
	_job_bar.value = lerpf(_job_bar.value, interaction.current_job_fraction(), 0.5)


func _build_hover() -> void:
	_hover_panel = PanelContainer.new()
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.add_theme_stylebox_override("panel", _box(Color(0.1, 0.08, 0.07, 0.85), 8, 8))
	_hover_panel.visible = false
	_root.add_child(_hover_panel)
	_hover_label = _label("", 14)
	_hover_panel.add_child(_hover_label)


func _on_hover_changed(text: String) -> void:
	_hover_label.text = text
	_hover_panel.reset_size()
	_hover_panel.visible = text != ""


func _build_toast() -> void:
	_toast = _label("", 20)
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position.y = -180
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_toast.modulate.a = 0.0
	_root.add_child(_toast)


func show_message(text: String) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = _toast.create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _build_loading() -> void:
	_loading = ColorRect.new()
	_loading.color = Color(0.68, 0.82, 0.92)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_loading)
	var l := _label("Создаём мир…", 28, Color(0.2, 0.25, 0.3))
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loading.add_child(l)


func hide_loading() -> void:
	var tw := _loading.create_tween()
	tw.tween_property(_loading, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_loading.queue_free)
