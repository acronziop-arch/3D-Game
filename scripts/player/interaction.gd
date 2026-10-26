class_name Interaction
extends Node3D
## Инструменты игрока и очередь действий.
##   1 Добыча — щелчок по дереву, кусту, камню, руде или сундуку ставит его в очередь;
##     щелчок по зданию показывает его название.
##   2 Стройка — размещение выбранного здания (поворот на любой угол).
##   3 Ровнять — зажать ЛКМ: земля тянется к высоте точки нажатия (авто) или к ней
##     плюс/минус заданная поправка.
##   4 Природа — косить траву, сеять траву и цветы, сажать деревья.
##   5 Правка — выбрать здание: передвинуть, повернуть или снести.
## Действия выполняются по одному, у каждого своё время (не больше 30 с).
## В творческом режиме добыча мгновенная.
## На телефоне те же инструменты работают от касаний (см. TouchInput).

enum Tool { HARVEST, BUILD, FLATTEN, NATURE, EDIT }

signal tool_changed(tool: Tool)
signal message(text: String)
signal hover_changed(text: String)
signal jobs_changed
## Изменилось что-то, от чего зависят кнопки действий (режим природы, выбор…).
signal options_changed

const MAX_JOBS := 6
const RING_COLOR := Color(1.0, 0.95, 0.7, 0.9)
const BRUSH_COLOR := Color(0.55, 0.85, 1.0, 0.9)
const JOB_COLOR := Color(1.0, 0.86, 0.45, 0.9)
const NATURE_COLOR := Color(0.6, 1.0, 0.55, 0.9)
const NATURE_MODES := {
	"mow": "Косить траву",
	"grass": "Сеять траву",
	"tall": "Высокая трава",
	"flowers": "Сажать цветы",
	"tree": "Сажать деревья",
}
const TREE_SPECIES := ["tree_oak", "tree_birch", "tree_apple", "tree_pine", "tree_maple", "tree_spruce"]

@export var brush_radius := 5.0
@export var flatten_speed := 4.0

var camera_rig: CameraRig
var chunk_manager: ChunkManager
var building_system: BuildingSystem
var tool := Tool.HARVEST
## [{"kind": "prop"|"chest", "name", "time", "elapsed", ...}]
var jobs: Array[Dictionary] = []
## Поправка высоты выравнивания, м (0 — авто: по высоте точки нажатия).
var flatten_offset := 0.0
var nature_mode := "mow"
var tree_species := 0
var selected_building: Building

var _ground: Variant = null
var _hover := {}
var _hover_building: Building
var _hover_text := ""
var _flattening := false
var _flatten_target := 0.0
var _painting := false
## Рисование дорожки (зажата мышь или палец ведёт по земле).
var _build_painting := false
var _paint_timer := 0.0
var _ring: Node3D
var _ring_target := Vector3.ZERO
var _ring_scale := 1.0
var _time := 0.0
## Касания: где «указатель» (последний палец), к какой точке привязан призрак здания
## и что сказать о том, на что нажали.
var _touch_point := Vector2.ZERO
var _touch_anchor: Variant = null
var _ghost_offset := Vector3.ZERO
var _touch_info := ""
var _touch_info_timer := 0.0


func _ready() -> void:
	_ring = make_ring(RING_COLOR)
	_ring.visible = false
	add_child(_ring)


## Кольцо-«стакан»: тонкий обод у земли и светящаяся стенка, тающая кверху.
static func make_ring(color: Color) -> Node3D:
	var root := Node3D.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ring.gdshader")
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("band_height", 0.55)
	mat.render_priority = 3
	var band := CylinderMesh.new()
	band.top_radius = 1.0
	band.bottom_radius = 1.0
	band.height = 0.55
	band.radial_segments = 40
	band.rings = 1
	band.cap_top = false
	band.cap_bottom = false
	var band_mi := MeshInstance3D.new()
	band_mi.mesh = band
	band_mi.material_override = mat
	band_mi.position.y = 0.275
	band_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(band_mi)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.04
	torus.rings = 40
	torus.ring_segments = 4
	var rim_mat := StandardMaterial3D.new()
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_mat.albedo_color = color
	rim_mat.render_priority = 3
	var rim := MeshInstance3D.new()
	rim.mesh = torus
	rim.material_override = rim_mat
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rim)
	root.set_meta("materials", [mat, rim_mat])
	return root


static func set_ring_color(ring: Node3D, color: Color) -> void:
	var mats: Array = ring.get_meta("materials")
	(mats[0] as ShaderMaterial).set_shader_parameter("color", color)
	(mats[1] as StandardMaterial3D).albedo_color = color


func set_tool(new_tool: Tool) -> void:
	if new_tool != Tool.BUILD or building_system.moving:
		building_system.cancel()
	if is_instance_valid(_hover_building):
		_hover_building.set_highlight(false)
	_hover_building = null
	select_building(null)
	_flattening = false
	_painting = false
	_end_build_paint()
	_touch_info = ""
	tool = new_tool
	tool_changed.emit(tool)


func start_building(building_id: String) -> void:
	set_tool(Tool.BUILD)
	building_system.select(building_id)
	if Platform.is_touch:
		# Призрак появляется в центре экрана — дальше его можно тянуть пальцем.
		var center := get_viewport().get_visible_rect().size * Vector2(0.5, 0.45)
		_touch_anchor = _ground_at(center)
	tool_changed.emit(tool)


func _unhandled_input(event: InputEvent) -> void:
	# В сенсорном режиме мышиные события — копии касаний (их разбирает TouchInput).
	if Platform.is_touch and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if event.is_action_pressed("tool_harvest"):
		set_tool(Tool.HARVEST)
	elif event.is_action_pressed("tool_build"):
		set_tool(Tool.BUILD)
	elif event.is_action_pressed("tool_flatten"):
		set_tool(Tool.FLATTEN)
	elif event.is_action_pressed("tool_nature"):
		set_tool(Tool.NATURE)
	elif event.is_action_pressed("tool_edit"):
		set_tool(Tool.EDIT)
	elif event.is_action_pressed("rotate_building"):
		var back := (event as InputEventKey).shift_pressed if event is InputEventKey else false
		if tool == Tool.BUILD:
			rotate_building(-1.0 if back else 1.0)
		elif tool == Tool.EDIT:
			edit_rotate(-1.0 if back else 1.0)
	elif event.is_action_pressed("edit_move") and tool == Tool.EDIT:
		edit_move()
	elif event.is_action_pressed("edit_delete") and tool == Tool.EDIT:
		demolish_selected()
	elif event.is_action_pressed("brush_bigger"):
		resize_brush(1.0)
	elif event.is_action_pressed("brush_smaller"):
		resize_brush(-1.0)
	elif event.is_action_pressed("flatten_up") and tool == Tool.FLATTEN:
		adjust_flatten_offset(0.5)
	elif event.is_action_pressed("flatten_down") and tool == Tool.FLATTEN:
		adjust_flatten_offset(-0.5)
	elif event.is_action_pressed("cancel"):
		if tool == Tool.BUILD and building_system.moving:
			building_system.cancel()
			set_tool(Tool.EDIT)
		elif tool != Tool.HARVEST:
			set_tool(Tool.HARVEST)
		else:
			cancel_all_jobs()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if (mb.ctrl_pressed or mb.alt_pressed) and mb.pressed and tool == Tool.BUILD \
				and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			building_system.rotate_ghost_by(deg_to_rad(5.0) * (1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0))
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_primary_action()
			else:
				_flattening = false
				_painting = false
				_end_build_paint()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed and camera_rig.was_right_click():
			if tool == Tool.BUILD and building_system.moving:
				building_system.cancel()
				set_tool(Tool.EDIT)
			elif tool != Tool.HARVEST:
				set_tool(Tool.HARVEST)
		elif mb.shift_pressed and mb.pressed and tool in [Tool.FLATTEN, Tool.NATURE]:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				resize_brush(0.5)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				resize_brush(-0.5)


func resize_brush(step: float) -> void:
	brush_radius = clampf(brush_radius + step, 1.0, 14.0)
	Platform.haptic(0.15)
	options_changed.emit()


func adjust_flatten_offset(step: float) -> void:
	flatten_offset = clampf(flatten_offset + step, -6.0, 6.0)
	Platform.haptic(0.15)
	options_changed.emit()


func reset_flatten_offset() -> void:
	flatten_offset = 0.0
	options_changed.emit()


## «Авто» или «+1.5 м» — для подсказок и кнопок.
func flatten_offset_text() -> String:
	if is_zero_approx(flatten_offset):
		return "авто"
	return "%+.1f м" % flatten_offset


func set_nature_mode(mode: String) -> void:
	nature_mode = mode
	options_changed.emit()


func next_tree_species() -> void:
	tree_species = (tree_species + 1) % TREE_SPECIES.size()
	options_changed.emit()


func tree_species_name() -> String:
	return GameData.PROPS[TREE_SPECIES[tree_species]]["name"]


## Ставит здание на место призрака (кнопка «Построить» на телефоне, ЛКМ на ПК).
func confirm_build() -> void:
	if building_system.selected_id == "":
		message.emit("Выберите здание в меню снизу")
		return
	var was_moving := building_system.moving != null
	var reason := building_system.try_place()
	if reason != "":
		message.emit(reason)
		Platform.haptic(0.2)
		return
	Platform.haptic(0.7)
	if was_moving:
		set_tool(Tool.EDIT)


## Дорожка: первая плитка сразу, дальше — следом за мышью или пальцем.
func _begin_build_paint() -> void:
	var reason := building_system.paint_begin()
	_build_painting = true
	if reason != "" and reason.begins_with("Не хватает"):
		message.emit(reason)
	else:
		Platform.haptic(0.3)


func _paint_build_to(ground: Variant) -> void:
	if not _build_painting or ground == null:
		return
	var before := building_system.buildings.size()
	var reason := building_system.paint_to(ground)
	if building_system.buildings.size() > before:
		Platform.haptic(0.15)
	if reason.begins_with("Не хватает"):
		message.emit(reason)
		_end_build_paint()


func _end_build_paint() -> void:
	if _build_painting:
		_build_painting = false
		building_system.paint_end()


## Грядка: сменить культуру (у новой — до постройки, у готовой — в правке).
func next_crop() -> void:
	if tool == Tool.EDIT and is_instance_valid(selected_building) and selected_building.has_crops():
		var c := building_system.cycle_crop(selected_building)
		message.emit("Посажено: %s" % CropPatch.CROPS[c]["name"])
	else:
		building_system.crop_choice = CropPatch.next_crop(building_system.crop_choice)
	options_changed.emit()
	Platform.haptic(0.2)


func rotate_building(direction := 1.0) -> void:
	building_system.rotate_ghost(direction)
	Platform.haptic(0.15)


func select_building(b: Building) -> void:
	if is_instance_valid(selected_building):
		selected_building.set_highlight(false)
	selected_building = b
	if b:
		b.set_highlight(true)
	options_changed.emit()


## Правка: передвинуть выбранное здание (оно становится призраком).
func edit_move() -> void:
	if not is_instance_valid(selected_building) or not selected_building.is_complete:
		return
	var b := selected_building
	select_building(null)
	tool = Tool.BUILD
	building_system.start_move(b)
	if Platform.is_touch:
		_touch_anchor = b.position
	tool_changed.emit(tool)


## Правка: повернуть выбранное здание на месте на 15°.
func edit_rotate(direction := 1.0) -> void:
	if not is_instance_valid(selected_building):
		return
	var reason := building_system.rotate_building(selected_building, direction)
	if reason != "":
		message.emit(reason)
	Platform.haptic(0.15)


## Сносит выбранное здание.
func demolish_selected() -> void:
	if not is_instance_valid(selected_building):
		return
	if _demolish(selected_building):
		selected_building = null
		options_changed.emit()


func _demolish(b: Building) -> bool:
	var blocked := building_system.can_demolish(b)
	if blocked != "":
		message.emit(blocked)
		return false
	var refund := building_system.demolish(b)
	Fx.show_loot(self, b.global_position + Vector3(0, 2, 0), refund)
	Platform.haptic(0.6)
	return true


## Короткая подпись с названием здания над ним.
func _show_building_name(b: Building) -> void:
	if WorldLabels.instance:
		var state := "" if b.is_complete else "  (строится)"
		WorldLabels.instance.show_name(b.global_position + Vector3(0, b.top_height + 0.6, 0),
			GameData.BUILDINGS[b.id]["name"] + state)


# --- Касания (вызывает TouchInput) ------------------------------------------------------

func _ground_at(screen: Vector2) -> Variant:
	var cam := camera_rig.camera
	return chunk_manager.raycast(cam.project_ray_origin(screen), cam.project_ray_normal(screen))


func touch_tap(screen: Vector2) -> void:
	_touch_point = screen
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var ground: Variant = chunk_manager.raycast(from, dir)
	var ground_t: float = from.distance_to(ground) if ground != null else 700.0
	match tool:
		Tool.HARVEST:
			# Палец толще курсора — цель можно задеть чуть мимо.
			var slack := ground_t * 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / get_viewport().get_visible_rect().size.y * 14.0
			var target := chunk_manager.pick(from, dir, ground_t + 1.0, slack)
			if target.is_empty():
				var b := building_system.pick(from, dir)
				if b:
					_show_building_name(b)
				_set_touch_info("")
				return
			var info := _target_info(target)
			var queued := _toggle_job(target)
			_set_touch_info("%s — %s%s" % [info["name"], info["hint"], "" if queued else " · убрано из очереди"])
			Platform.haptic(0.25)
		Tool.BUILD:
			if building_system.selected_id == "":
				message.emit("Выберите здание в меню снизу")
			elif ground != null:
				_touch_anchor = ground
		Tool.NATURE:
			if nature_mode == "tree" and ground != null:
				_plant_tree(ground)
			elif ground != null:
				chunk_manager.paint_cover(ground, brush_radius * 0.5, nature_mode)
				Platform.haptic(0.15)
		Tool.EDIT:
			var b := building_system.pick(from, dir)
			select_building(null if b == selected_building else b)
			if b:
				_show_building_name(b)
				Platform.haptic(0.2)


## Палец начал движение: true — инструмент забирает жест себе, иначе это движение камеры.
func touch_drag_begin(screen: Vector2) -> bool:
	match tool:
		Tool.BUILD:
			if building_system.is_paintable():
				# Дорожку рисуют пальцем: плитки ложатся следом.
				var start: Variant = _ground_at(screen)
				if start == null:
					return false
				_touch_anchor = start
				building_system.update_ghost(start, 1.0)
				_begin_build_paint()
				return true
			if building_system.selected_id == "" or _touch_anchor == null:
				return false
			var cam := camera_rig.camera
			var from := cam.project_ray_origin(screen)
			var dir := cam.project_ray_normal(screen)
			var ground: Variant = chunk_manager.raycast(from, dir)
			if ground == null or not building_system.ghost_hit(from, dir):
				return false
			_ghost_offset = (_touch_anchor as Vector3) - (ground as Vector3)
			return true
		Tool.FLATTEN:
			var ground: Variant = _ground_at(screen)
			if ground == null:
				return false
			_touch_point = screen
			_start_flatten(ground)
			return true
		Tool.NATURE:
			if nature_mode == "tree":
				return false
			_touch_point = screen
			_painting = true
			_paint_timer = 0.0
			return true
	return false


func touch_drag(screen: Vector2) -> void:
	_touch_point = screen
	if tool == Tool.BUILD:
		var ground: Variant = _ground_at(screen)
		if ground != null and _build_painting:
			_touch_anchor = ground
			_paint_build_to(ground)
		elif ground != null:
			_touch_anchor = (ground as Vector3) + _ghost_offset


func touch_drag_end() -> void:
	_flattening = false
	_painting = false
	_end_build_paint()


func _set_touch_info(text: String) -> void:
	_touch_info = text
	_touch_info_timer = 3.5


func _start_flatten(ground: Vector3) -> void:
	_flattening = true
	_flatten_target = snappedf(maxf(ground.y + flatten_offset, WorldGen.WATER_LEVEL - 4.0), 0.25)


func _plant_tree(ground: Vector3) -> void:
	var reason := chunk_manager.plant_tree(ground, TREE_SPECIES[tree_species])
	if reason != "":
		message.emit(reason)
		Platform.haptic(0.2)
	else:
		Fx.burst(self, ground + Vector3(0, 0.3, 0), Color(0.5, 0.75, 0.35), 10, 0.12)
		Platform.haptic(0.35)


func _primary_action() -> void:
	match tool:
		Tool.HARVEST:
			if not _hover.is_empty():
				_toggle_job(_hover)
			elif is_instance_valid(_hover_building):
				_show_building_name(_hover_building)
		Tool.BUILD:
			if building_system.is_paintable():
				_begin_build_paint()
			else:
				confirm_build()
		Tool.FLATTEN:
			if _ground != null:
				_start_flatten(_ground)
		Tool.NATURE:
			if _ground == null:
				return
			if nature_mode == "tree":
				_plant_tree(_ground)
			else:
				_painting = true
				_paint_timer = 0.0
		Tool.EDIT:
			select_building(null if _hover_building == selected_building else _hover_building)
			if selected_building:
				_show_building_name(selected_building)


# --- Каждый кадр ------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var touch := Platform.is_touch
	var camera := camera_rig.camera
	var pointer := _touch_point if touch else get_viewport().get_mouse_position()
	var over_ui := not touch and get_viewport().gui_get_hovered_control() != null
	var from := camera.project_ray_origin(pointer)
	var dir := camera.project_ray_normal(pointer)
	if touch:
		# Под пальцем землю ищем, только пока им ровняют или красят.
		_ground = chunk_manager.raycast(from, dir) if (_flattening or _painting) else null
	else:
		_ground = null if over_ui else chunk_manager.raycast(from, dir)
	var ground_t: float = from.distance_to(_ground) if _ground != null else 700.0
	_touch_info_timer -= delta
	if _touch_info_timer <= 0.0:
		_touch_info = ""

	var text := ""
	var ring_visible := false
	var ring_color := RING_COLOR
	match tool:
		Tool.HARVEST when touch:
			text = _touch_info
			if text == "" and jobs.is_empty():
				text = "Нажмите на дерево, куст, камень, руду или сундук"
		Tool.HARVEST:
			_hover = {} if over_ui else chunk_manager.pick(from, dir, ground_t + 1.0)
			_hover_building = null
			if not _hover.is_empty():
				ring_visible = true
				var info := _target_info(_hover)
				_ring_target = info["pos"]
				_ring_scale = info["radius"]
				text = "%s — %s" % [info["name"], info["hint"]]
			elif not over_ui:
				_hover_building = building_system.pick(from, dir)
				if _hover_building:
					text = GameData.BUILDINGS[_hover_building.id]["name"]
		Tool.BUILD:
			building_system.update_ghost(_touch_anchor if touch else _ground, delta)
			if not touch:
				_paint_build_to(_ground)
			var id := building_system.selected_id
			if id == "":
				text = "Выберите здание в меню снизу"
			elif building_system.moving:
				text = "Переносим: %s" % GameData.BUILDINGS[id]["name"]
				if not building_system.is_valid and building_system.invalid_reason != "":
					text += "\n" + building_system.invalid_reason
				elif touch:
					text += "\nТяните здание пальцем · ✓ — поставить"
				else:
					text += "\nЛКМ — поставить · R / Shift+R — повернуть · ПКМ — отмена"
			else:
				var def: Dictionary = GameData.BUILDINGS[id]
				var time_text := "сразу" if GameMode.is_creative() else "%d с" % def["time"]
				text = "%s · %s · %s" % [def["name"], time_text, GameData.cost_text(def["cost"])]
				if not building_system.is_valid and building_system.invalid_reason != "":
					text += "\n" + building_system.invalid_reason
				elif touch:
					text += "\nТяните здание пальцем или нажмите, куда поставить"
				else:
					text += "\nЛКМ — построить · R / Shift+R или Ctrl+колесо — повернуть · ПКМ — отмена"
		Tool.FLATTEN:
			if _ground != null:
				ring_visible = true
				_ring_target = _ground
				_ring_scale = brush_radius
				ring_color = BRUSH_COLOR
				if _flattening:
					chunk_manager.flatten(_ground, brush_radius, _flatten_target, flatten_speed * delta)
			var mode := "высота: %s" % flatten_offset_text()
			if touch:
				text = "Проведите пальцем — выровнять · %s · кисть %d м\nКамера — двумя пальцами" % [mode, roundi(brush_radius)]
			else:
				text = "Зажмите ЛКМ — выровнять · %s (PgUp / PgDn) · [ ] — кисть %d м" % [mode, roundi(brush_radius)]
		Tool.NATURE:
			if _ground != null:
				ring_visible = true
				_ring_target = _ground
				_ring_scale = 1.2 if nature_mode == "tree" else brush_radius * 0.5
				ring_color = NATURE_COLOR
				if _painting and nature_mode != "tree":
					_paint_timer -= delta
					if _paint_timer <= 0.0:
						_paint_timer = 0.12
						chunk_manager.paint_cover(_ground, brush_radius * 0.5, nature_mode)
			if nature_mode == "tree":
				text = "Нажмите, куда посадить: %s. Дерево вырастет за пару минут" % tree_species_name()
			else:
				text = "%s — %s" % [NATURE_MODES[nature_mode], "проведите пальцем" if touch else "зажмите ЛКМ"]
		Tool.EDIT:
			if not touch:
				var b: Building = null if over_ui else building_system.pick(from, dir)
				if b != _hover_building:
					if is_instance_valid(_hover_building) and _hover_building != selected_building:
						_hover_building.set_highlight(false)
					if b and b != selected_building:
						b.set_highlight(true)
					_hover_building = b
			if not is_instance_valid(selected_building) or selected_building.is_queued_for_deletion():
				selected_building = null
			if selected_building:
				text = "%s — передвинуть, повернуть или снести (вернётся %s)" % [GameData.BUILDINGS[selected_building.id]["name"],
					"половина ресурсов" if selected_building.is_complete else "всё"]
				if not touch:
					text += "\nM — передвинуть · R — повернуть · Delete — снести"
			else:
				text = "Нажмите на здание, чтобы выбрать его"

	_update_ring(ring_visible, ring_color, delta)
	if text != _hover_text:
		_hover_text = text
		hover_changed.emit(text)
	_process_jobs(delta)


func _update_ring(shown: bool, color: Color, delta: float) -> void:
	if not shown:
		_ring.visible = false
		return
	var k := 1.0 - exp(-20.0 * delta)
	if not _ring.visible:
		_ring.position = _ring_target
		_ring.scale = Vector3.ONE * _ring_scale
	_ring.visible = true
	set_ring_color(_ring, color)
	_ring.position = _ring.position.lerp(_ring_target + Vector3(0, 0.05, 0), k)
	var pulse := 1.0 + sin(_time * 5.0) * 0.04
	_ring.scale = _ring.scale.lerp(Vector3(_ring_scale * pulse, 1.0, _ring_scale * pulse), k)


func _target_info(target: Dictionary) -> Dictionary:
	if target.has("chest"):
		var chest: Chest = target["chest"]
		var def: Dictionary = GameData.CHESTS[chest.rarity]
		return {"name": def["name"], "pos": chest.global_position, "radius": 1.0,
			"time": _action_time(def["open_time"]), "hint": "%.1f с · животные ресурсы" % def["open_time"]}
	var p: Dictionary = target["prop"]
	var chunk: Chunk = target["chunk"]
	var pdef: Dictionary = GameData.PROPS[p["id"]]
	return {"name": pdef["name"], "pos": chunk.to_global(p["pos"]), "radius": float(pdef["radius"]) * float(p["scale"]),
		"time": _action_time(pdef["time"]), "hint": "%d с · даёт %s" % [pdef["time"], GameData.cost_text(pdef["drops"])]}


## В творческом режиме всё добывается мгновенно.
static func _action_time(t: float) -> float:
	return 0.15 if GameMode.is_creative() else t


# --- Очередь действий -----------------------------------------------------------------

func _same_target(job: Dictionary, target: Dictionary) -> bool:
	if target.has("chest"):
		return is_same(job.get("chest"), target["chest"])
	return is_same(job.get("prop"), target.get("prop"))


## true — цель добавлена в очередь, false — убрана из неё (или очередь полна).
func _toggle_job(target: Dictionary) -> bool:
	for i in jobs.size():
		if _same_target(jobs[i], target):
			_cancel_job(jobs[i])
			jobs.remove_at(i)
			jobs_changed.emit()
			return false
	if jobs.size() >= MAX_JOBS:
		message.emit("Очередь заполнена (максимум %d)" % MAX_JOBS)
		return false
	var info := _target_info(target)
	var job := target.duplicate()
	job["kind"] = "chest" if target.has("chest") else "prop"
	job["name"] = info["name"]
	job["time"] = float(info["time"])
	job["elapsed"] = 0.0
	var marker := make_ring(Color(1, 1, 1, 0.7))
	add_child(marker)
	marker.position = info["pos"] + Vector3(0, 0.04, 0)
	marker.scale = Vector3(info["radius"], 1.0, info["radius"])
	job["marker"] = marker
	jobs.append(job)
	jobs_changed.emit()
	return true


func cancel_all_jobs() -> void:
	for job in jobs:
		_cancel_job(job)
	jobs.clear()
	jobs_changed.emit()


func _job_alive(job: Dictionary) -> bool:
	if not is_instance_valid(job["chunk"]):
		return false
	if job["kind"] == "chest":
		return is_instance_valid(job["chest"]) and not job["chest"].opened
	return not job["prop"].get("removed", false)


func _cancel_job(job: Dictionary) -> void:
	if job.has("proxy"):
		job["proxy"].queue_free()
		if is_instance_valid(job["chunk"]):
			job["chunk"].set_prop_hidden(job["prop"], false)
	if job["kind"] == "chest" and is_instance_valid(job["chest"]):
		job["chest"].cancel_progress()
	if is_instance_valid(job.get("marker")):
		job["marker"].queue_free()


func _process_jobs(delta: float) -> void:
	if jobs.is_empty():
		return
	var job := jobs[0]
	if not _job_alive(job):
		_cancel_job(job)
		jobs.pop_front()
		jobs_changed.emit()
		return
	if not job.has("started"):
		job["started"] = true
		if job["kind"] == "prop":
			# Вместо экземпляра MultiMesh анимируем отдельную копию модели.
			var chunk: Chunk = job["chunk"]
			var proxy := MeshInstance3D.new()
			proxy.mesh = ModelLibrary.prop_mesh(job["prop"]["id"], job["prop"].get("variant", 0))
			proxy.material_override = ModelLibrary.foliage_material()
			add_child(proxy)
			proxy.global_transform = chunk.world_prop_transform(job["prop"])
			job["proxy"] = proxy
			job["base"] = proxy.global_transform
			chunk.set_prop_hidden(job["prop"], true)
	job["elapsed"] += delta
	var f: float = clampf(job["elapsed"] / job["time"], 0.0, 1.0)
	_animate_job(job, f)
	set_ring_color(job["marker"], Color(JOB_COLOR, 0.65 + 0.3 * sin(_time * 8.0)))
	if f >= 1.0:
		jobs.pop_front()
		job["marker"].queue_free()
		_complete_job(job)
		jobs_changed.emit()
		Platform.haptic(0.45)


func _animate_job(job: Dictionary, f: float) -> void:
	if job["kind"] == "chest":
		job["chest"].set_progress(f)
		return
	var base: Transform3D = job["base"]
	var proxy: MeshInstance3D = job["proxy"]
	var kind: String = GameData.PROPS[job["prop"]["id"]]["kind"]
	if kind == "tree":
		var sway := sin(_time * 16.0) * 0.035 * (0.3 + f)
		proxy.global_transform = Transform3D(Basis(Vector3(1, 0, 0.4).normalized(), sway) * base.basis, base.origin)
	else:
		var shake := Vector3(sin(_time * 47.0), 0, cos(_time * 53.0)) * 0.05 * f
		proxy.global_transform = Transform3D(base.basis.scaled(Vector3.ONE * (1.0 + sin(_time * 20.0) * 0.03 * f)), base.origin + shake)


func current_job_fraction() -> float:
	if jobs.is_empty():
		return 0.0
	return clampf(jobs[0]["elapsed"] / jobs[0]["time"], 0.0, 1.0)


func _complete_job(job: Dictionary) -> void:
	if job["kind"] == "chest":
		var chest: Chest = job["chest"]
		var loot := chest.open()
		Inventory.add_all(loot)
		Fx.show_loot(self, chest.global_position + Vector3(0, 1.5, 0), loot)
		return
	var chunk: Chunk = job["chunk"]
	var p: Dictionary = job["prop"]
	var pdef: Dictionary = GameData.PROPS[p["id"]]
	chunk.remove_prop(p)
	Inventory.add_all(pdef["drops"])
	var proxy: MeshInstance3D = job["proxy"]
	var base: Transform3D = job["base"]
	var top := base.origin + Vector3(0, float(pdef["height"]) * float(p["scale"]) * 0.6, 0)
	Fx.show_loot(self, top, pdef["drops"])
	var tw := proxy.create_tween()
	if pdef["kind"] == "tree":
		# Дерево падает от камеры, чтобы было видно.
		var away := base.origin - camera_rig.camera.global_position
		away.y = 0.0
		var axis := Vector3.UP.cross(away.normalized()).normalized()
		if axis == Vector3.ZERO:
			axis = Vector3.RIGHT
		var fall := func(angle: float) -> void:
			proxy.global_transform = Transform3D(Basis(axis, angle) * base.basis, base.origin)
		tw.tween_method(fall, 0.0, deg_to_rad(86.0), 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void: Fx.burst(self, base.origin + away.normalized() * 3.0, Color(0.45, 0.6, 0.3), 14))
		tw.tween_interval(0.3)
		tw.tween_property(proxy, "scale", Vector3.ONE * 0.01, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	else:
		Fx.burst(self, base.origin + Vector3(0, 0.6, 0), _burst_color(p["id"]), 18)
		tw.tween_property(proxy, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(proxy.queue_free)


## Цвет «осколков» при добыче.
static func _burst_color(id: String) -> Color:
	match id:
		"ore_coal":
			return Color(0.15, 0.15, 0.16)
		"ore_copper":
			return Color(0.9, 0.52, 0.25)
		"ore_iron":
			return Color(0.66, 0.4, 0.32)
		"clay":
			return Color(0.7, 0.44, 0.3)
		"sand":
			return Color(0.94, 0.85, 0.6)
	if id.begins_with("bush"):
		return Color(0.4, 0.62, 0.3)
	return Color(0.55, 0.55, 0.56)
