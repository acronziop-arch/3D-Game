class_name WorldLabels
extends Control
## Надписи над миром, нарисованные интерфейсом, а не в 3D: их не красит ночь,
## туман и свечение, они всегда чёткие и одного размера.
##   track()      — плашка, которая следует за объектом (например, «Дом 42%»);
##   float_text() — всплывающая надпись «+5 Брёвна»;
##   show_name()  — короткая подпись над тем, на что нажали.

static var instance: WorldLabels

var _tracked: Array[Dictionary] = []
var _floating: Array[Dictionary] = []


func _ready() -> void:
	instance = self
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Плашка над объектом. Пока объект жив, она следует за точкой owner + offset.
## with_bar — под текстом полоска готовности; icon и accent — значок и цвет рамки
## (для меток игрока); дальше max_distance плашка прячется.
func track(owner: Node3D, offset: Vector3, text: String, with_bar := false, icon: Texture2D = null,
		accent := Color(0, 0, 0, 0), max_distance := 180.0) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := accent if accent.a > 0.0 else UiStyle.BRAND
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(UiStyle.BASE, 0.94), 12, 6, 2, border, true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	if icon:
		line.add_child(UiStyle.icon_rect("", 18))
		(line.get_child(0) as TextureRect).texture = icon
	var label := UiStyle.label(text, 13, UiStyle.TEXT, 800)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(label)
	var bar: ProgressBar = null
	if with_bar:
		bar = ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.custom_minimum_size = Vector2(90, 5)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(bar)
	add_child(panel)
	panel.modulate.a = 0.0
	var entry := {"owner": owner, "offset": offset, "panel": panel, "label": label, "bar": bar, "alpha": 0.0, "closing": false,
		"far": max_distance}
	_tracked.append(entry)
	return entry


## Плавно убирает плашку.
func untrack(entry: Dictionary) -> void:
	entry["closing"] = true


## line — номер строки, если надписей несколько (они идут столбиком).
func float_text(world_pos: Vector3, text: String, color: Color, delay := 0.0, line := 0) -> void:
	var label := UiStyle.label(text, 17, color, 900)
	label.add_theme_color_override("font_outline_color", Color(UiStyle.BASE, 0.95))
	label.add_theme_constant_override("outline_size", 7)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate.a = 0.0
	add_child(label)
	_floating.append({"label": label, "pos": world_pos, "t": -delay, "line": line})


## Короткая подпись над объектом (название здания по нажатию).
func show_name(world_pos: Vector3, text: String) -> void:
	var owner := Node3D.new()
	get_tree().current_scene.add_child(owner)
	owner.global_position = world_pos
	var entry := track(owner, Vector3.ZERO, text)
	get_tree().create_timer(2.2).timeout.connect(func() -> void:
		untrack(entry)
		owner.queue_free())


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var view := get_viewport_rect().size
	for i in range(_tracked.size() - 1, -1, -1):
		var e: Dictionary = _tracked[i]
		var panel: PanelContainer = e["panel"]
		var alive: bool = is_instance_valid(e["owner"]) and not e["closing"]
		var shown := false
		if is_instance_valid(e["owner"]):
			var p: Vector3 = (e["owner"] as Node3D).global_position + e["offset"]
			if not cam.is_position_behind(p) and cam.global_position.distance_to(p) < e["far"]:
				var sp := cam.unproject_position(p)
				panel.reset_size()
				panel.position = (sp - panel.size * Vector2(0.5, 1.0)).clamp(Vector2.ZERO, view - panel.size)
				shown = true
		var target := 1.0 if alive and shown else 0.0
		e["alpha"] = move_toward(e["alpha"], target, delta * 5.0)
		panel.modulate.a = e["alpha"]
		if not alive and e["alpha"] <= 0.0:
			panel.queue_free()
			_tracked.remove_at(i)
	for i in range(_floating.size() - 1, -1, -1):
		var f: Dictionary = _floating[i]
		f["t"] += delta
		var t: float = f["t"]
		var label: Label = f["label"]
		if t < 0.0:
			continue
		var p: Vector3 = f["pos"]
		var visible_now := not cam.is_position_behind(p)
		var sp := cam.unproject_position(p)
		label.reset_size()
		var rise := 1.0 - pow(1.0 - minf(t / 1.3, 1.0), 3.0)
		label.position = sp - label.size * 0.5 - Vector2(0, 46.0 * rise + 24.0 * f["line"])
		label.modulate.a = (minf(t / 0.15, 1.0) * (1.0 - clampf((t - 1.3) / 0.4, 0.0, 1.0))) if visible_now else 0.0
		if t > 1.75:
			label.queue_free()
			_floating.remove_at(i)
