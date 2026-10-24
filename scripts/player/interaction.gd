class_name Interaction
extends Node3D
## Инструменты игрока и очередь действий.
##   1 Добыча — щелчок по дереву, камню, руде или сундуку ставит его в очередь.
##   2 Стройка — размещение выбранного здания.
##   3 Выравнивание — зажать ЛКМ: земля тянется к высоте точки, где нажали.
##   4 Снос — щелчок по зданию, возвращается половина ресурсов.
## Действия выполняются по одному, у каждого своё время (не больше 30 с).

enum Tool { HARVEST, BUILD, FLATTEN, DEMOLISH }

signal tool_changed(tool: Tool)
signal message(text: String)
signal hover_changed(text: String)
signal jobs_changed

const MAX_JOBS := 6
const RING_COLOR := Color(1.0, 0.95, 0.7, 0.85)
const BRUSH_COLOR := Color(0.55, 0.85, 1.0, 0.85)

@export var brush_radius := 5.0
@export var flatten_speed := 4.0

var camera_rig: CameraRig
var chunk_manager: ChunkManager
var building_system: BuildingSystem
var tool := Tool.HARVEST
## [{"kind": "prop"|"chest", "name", "time", "elapsed", ...}]
var jobs: Array[Dictionary] = []

var _ground: Variant = null
var _hover := {}
var _hover_building: Building
var _hover_text := ""
var _flattening := false
var _flatten_target := 0.0
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _ring_target := Vector3.ZERO
var _ring_scale := 1.0
var _time := 0.0


func _ready() -> void:
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.albedo_color = RING_COLOR
	_ring = _make_ring(_ring_material)
	_ring.visible = false
	add_child(_ring)


static func _make_ring(mat: Material) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.84
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func set_tool(new_tool: Tool) -> void:
	if new_tool != Tool.BUILD:
		building_system.cancel()
	if tool == Tool.DEMOLISH and is_instance_valid(_hover_building):
		_hover_building.set_highlight(false)
	_hover_building = null
	_flattening = false
	tool = new_tool
	tool_changed.emit(tool)


func start_building(building_id: String) -> void:
	set_tool(Tool.BUILD)
	building_system.select(building_id)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("tool_harvest"):
		set_tool(Tool.HARVEST)
	elif event.is_action_pressed("tool_build"):
		set_tool(Tool.BUILD)
	elif event.is_action_pressed("tool_flatten"):
		set_tool(Tool.FLATTEN)
	elif event.is_action_pressed("tool_demolish"):
		set_tool(Tool.DEMOLISH)
	elif event.is_action_pressed("rotate_building") and tool == Tool.BUILD:
		building_system.rotate_ghost()
	elif event.is_action_pressed("brush_bigger"):
		_resize_brush(1.0)
	elif event.is_action_pressed("brush_smaller"):
		_resize_brush(-1.0)
	elif event.is_action_pressed("cancel"):
		if tool != Tool.HARVEST:
			set_tool(Tool.HARVEST)
		else:
			cancel_all_jobs()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_primary_action()
			else:
				_flattening = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed and camera_rig.was_right_click():
			if tool != Tool.HARVEST:
				set_tool(Tool.HARVEST)
		elif mb.shift_pressed and mb.pressed and tool == Tool.FLATTEN:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_resize_brush(0.5)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_resize_brush(-0.5)


func _resize_brush(step: float) -> void:
	brush_radius = clampf(brush_radius + step, 2.0, 14.0)


func _primary_action() -> void:
	match tool:
		Tool.HARVEST:
			if not _hover.is_empty():
				_toggle_job(_hover)
		Tool.BUILD:
			if building_system.selected_id == "":
				message.emit("Выберите здание в меню снизу")
				return
			var reason := building_system.try_place()
			if reason != "":
				message.emit(reason)
		Tool.FLATTEN:
			if _ground != null:
				_flattening = true
				_flatten_target = snappedf(maxf(_ground.y, WorldGen.WATER_LEVEL), 0.25)
		Tool.DEMOLISH:
			if is_instance_valid(_hover_building):
				var blocked := building_system.can_demolish(_hover_building)
				if blocked != "":
					message.emit(blocked)
					return
				var refund := building_system.demolish(_hover_building)
				Fx.show_loot(self, _hover_building.global_position + Vector3(0, 2, 0), refund)
				_hover_building = null


# --- Каждый кадр ------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var camera := camera_rig.camera
	var mouse := get_viewport().get_mouse_position()
	var over_ui := get_viewport().gui_get_hovered_control() != null
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	_ground = null if over_ui else chunk_manager.raycast(from, dir)
	var ground_t: float = from.distance_to(_ground) if _ground != null else 700.0

	var text := ""
	var ring_visible := false
	match tool:
		Tool.HARVEST:
			_hover = {} if over_ui else chunk_manager.pick(from, dir, ground_t + 1.0)
			if not _hover.is_empty():
				ring_visible = true
				var info := _target_info(_hover)
				_ring_target = info["pos"]
				_ring_scale = info["radius"]
				_ring_material.albedo_color = RING_COLOR
				text = "%s — %s" % [info["name"], info["hint"]]
		Tool.BUILD:
			building_system.update_ghost(_ground, delta)
			var id := building_system.selected_id
			if id == "":
				text = "Выберите здание в меню снизу"
			else:
				var def: Dictionary = GameData.BUILDINGS[id]
				text = "%s · %d с · %s" % [def["name"], def["time"], GameData.cost_text(def["cost"])]
				if not building_system.is_valid and building_system.invalid_reason != "":
					text += "\n" + building_system.invalid_reason
				else:
					text += "\nЛКМ — построить · R — повернуть · ПКМ — отмена"
		Tool.FLATTEN:
			if _ground != null:
				ring_visible = true
				_ring_target = _ground
				_ring_scale = brush_radius
				_ring_material.albedo_color = BRUSH_COLOR
				if _flattening:
					chunk_manager.flatten(_ground, brush_radius, _flatten_target, flatten_speed * delta)
			text = "Зажмите ЛКМ — выровнять по высоте точки нажатия · [ ] или Shift+колесо — размер (%d м)" % roundi(brush_radius)
		Tool.DEMOLISH:
			var b: Building = null if over_ui else building_system.pick(from, dir)
			if b != _hover_building:
				if is_instance_valid(_hover_building):
					_hover_building.set_highlight(false)
				if b:
					b.set_highlight(true)
				_hover_building = b
			if b:
				text = "Снести: %s (вернётся %s)" % [GameData.BUILDINGS[b.id]["name"],
					"половина ресурсов" if b.is_complete else "всё"]
			else:
				text = "Наведите на здание, чтобы снести"

	_update_ring(ring_visible, delta)
	if text != _hover_text:
		_hover_text = text
		hover_changed.emit(text)
	_process_jobs(delta)


func _update_ring(shown: bool, delta: float) -> void:
	if not shown:
		_ring.visible = false
		return
	var k := 1.0 - exp(-20.0 * delta)
	if not _ring.visible:
		_ring.position = _ring_target
		_ring.scale = Vector3.ONE * _ring_scale
	_ring.visible = true
	_ring.position = _ring.position.lerp(_ring_target + Vector3(0, 0.08, 0), k)
	var pulse := 1.0 + sin(_time * 5.0) * 0.04
	_ring.scale = _ring.scale.lerp(Vector3(_ring_scale, 1.0, _ring_scale) * pulse, k)


func _target_info(target: Dictionary) -> Dictionary:
	if target.has("chest"):
		var chest: Chest = target["chest"]
		var def: Dictionary = GameData.CHESTS[chest.rarity]
		return {"name": def["name"], "pos": chest.global_position, "radius": 1.0,
			"time": def["open_time"], "hint": "%.1f с · животные ресурсы" % def["open_time"]}
	var p: Dictionary = target["prop"]
	var chunk: Chunk = target["chunk"]
	var pdef: Dictionary = GameData.PROPS[p["id"]]
	return {"name": pdef["name"], "pos": chunk.to_global(p["pos"]), "radius": float(pdef["radius"]) * float(p["scale"]),
		"time": pdef["time"], "hint": "%d с → %s" % [pdef["time"], GameData.cost_text(pdef["drops"])]}


# --- Очередь действий -----------------------------------------------------------------

func _same_target(job: Dictionary, target: Dictionary) -> bool:
	if target.has("chest"):
		return is_same(job.get("chest"), target["chest"])
	return is_same(job.get("prop"), target.get("prop"))


func _toggle_job(target: Dictionary) -> void:
	for i in jobs.size():
		if _same_target(jobs[i], target):
			_cancel_job(jobs[i])
			jobs.remove_at(i)
			jobs_changed.emit()
			return
	if jobs.size() >= MAX_JOBS:
		message.emit("Очередь заполнена (максимум %d)" % MAX_JOBS)
		return
	var info := _target_info(target)
	var job := target.duplicate()
	job["kind"] = "chest" if target.has("chest") else "prop"
	job["name"] = info["name"]
	job["time"] = float(info["time"])
	job["elapsed"] = 0.0
	var marker := _make_ring(_ring_material.duplicate())
	marker.material_override.albedo_color = Color(1, 1, 1, 0.5)
	add_child(marker)
	marker.position = info["pos"] + Vector3(0, 0.06, 0)
	marker.scale = Vector3(info["radius"], 1.0, info["radius"])
	job["marker"] = marker
	jobs.append(job)
	jobs_changed.emit()


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
	var marker: MeshInstance3D = job["marker"]
	marker.material_override.albedo_color = Color(1.0, 0.9, 0.5, 0.6 + 0.3 * sin(_time * 8.0))
	if f >= 1.0:
		jobs.pop_front()
		marker.queue_free()
		_complete_job(job)
		jobs_changed.emit()


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
	return Color(0.55, 0.55, 0.56)
