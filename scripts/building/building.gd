class_name Building
extends Node3D
## Здание в мире. Модель — models/buildings/<id>.glb. Стройку рисует шейдер
## building.gdshader: детали по очереди падают на место с лёгким отскоком,
## ещё не построенная часть видна как голубой полупрозрачный чертёж, вокруг
## стоят строительные леса. Пока здание строится, у него свои копии материалов
## (параметр build_progress), а готовое переходит на общие материалы.
## Время стройки — GameData.BUILDINGS[id].time (не больше 30 с).

signal completed(building: Building)

static var _ghost_material: ShaderMaterial
static var _ghost_opening_material: ShaderMaterial
static var _highlight_material: StandardMaterial3D

var id := ""
## Поворот вокруг вертикали, радианы (любой угол).
var yaw := 0.0
var progress := 0.0
var is_complete := false
var footprint := Rect2()
var top_height := 0.0
## Культура на грядке и время посадки (для зданий с "crops").
var crop := ""
var planted := 0.0
## Нормаль земли для дорожек, которые ложатся по склону ("tilt").
var ground_normal := Vector3.UP

var _mesh: MeshInstance3D
var _ghost: MeshInstance3D
var _rotor: Node3D
var _rotor_mesh: MeshInstance3D
var _rotor_speed := 0.0
var _label := {}
var _dust: CPUParticles3D
var _scaffold: MeshInstance3D
var _removing := false
var _crops: CropPatch
## Свои копии материалов на время стройки (у них меняется build_progress).
var _progress_materials: Array[ShaderMaterial] = []


## Прямоугольник, который здание занимает на земле (мировые XZ, с учётом поворота).
static func footprint_for(building_id: String, pos: Vector3, angle: float) -> Rect2:
	var b: AABB = ModelLibrary.building(building_id)["bounds"]
	var basis := Basis(Vector3.UP, angle)
	var rect := Rect2()
	for i in 4:
		var corner := Vector3(b.position.x if i % 2 == 0 else b.end.x, 0, b.position.z if i < 2 else b.end.z)
		var w := pos + basis * corner
		if i == 0:
			rect = Rect2(Vector2(w.x, w.z), Vector2.ZERO)
		else:
			rect = rect.expand(Vector2(w.x, w.z))
	return rect


## Повёрнутый прямоугольник здания на земле: {"c": центр, "h": полуразмеры, "a": угол}.
static func obb_for(building_id: String, pos: Vector3, angle: float, grow := 0.0) -> Dictionary:
	var b: AABB = ModelLibrary.building(building_id)["bounds"]
	var c := pos + Basis(Vector3.UP, angle) * Vector3(b.get_center().x, 0, b.get_center().z)
	var half := Vector2(b.size.x, b.size.z) * 0.5 + Vector2.ONE * grow
	return {"c": Vector2(c.x, c.z), "h": half.max(Vector2.ONE * 0.05), "a": angle}


static func _obb_axes(o: Dictionary) -> Array[Vector2]:
	var a: float = o["a"]
	# Поворот вокруг Y на угол a: локальная X — (cos, -sin), локальная Z — (sin, cos) в плоскости XZ.
	return [Vector2(cos(a), -sin(a)), Vector2(sin(a), cos(a))]


static func obb_has_point(o: Dictionary, p: Vector2) -> bool:
	var axes := _obb_axes(o)
	var d: Vector2 = p - o["c"]
	var h: Vector2 = o["h"]
	return absf(d.dot(axes[0])) <= h.x and absf(d.dot(axes[1])) <= h.y


## Пересекаются ли два повёрнутых прямоугольника (теорема о разделяющей оси).
static func obb_overlap(a: Dictionary, b: Dictionary) -> bool:
	var axes_a := _obb_axes(a)
	var axes_b := _obb_axes(b)
	var d: Vector2 = b["c"] - a["c"]
	var ha: Vector2 = a["h"]
	var hb: Vector2 = b["h"]
	for axis: Vector2 in axes_a + axes_b:
		var ra := absf(axes_a[0].dot(axis)) * ha.x + absf(axes_a[1].dot(axis)) * ha.y
		var rb := absf(axes_b[0].dot(axis)) * hb.x + absf(axes_b[1].dot(axis)) * hb.y
		if absf(d.dot(axis)) > ra + rb:
			return false
	return true


## Точки-пробы внутри повёрнутого прямоугольника (n × n).
static func obb_samples(o: Dictionary, n: int) -> Array[Vector2]:
	var axes := _obb_axes(o)
	var h: Vector2 = o["h"]
	var result: Array[Vector2] = []
	for iz in n:
		for ix in n:
			var u := lerpf(-h.x, h.x, ix / float(n - 1))
			var v := lerpf(-h.y, h.y, iz / float(n - 1))
			result.append(o["c"] + axes[0] * u + axes[1] * v)
	return result


func obb(grow := 0.0) -> Dictionary:
	return obb_for(id, position, yaw, grow)


static func ghost_material(opening := false) -> ShaderMaterial:
	if _ghost_material == null:
		_ghost_material = ShaderMaterial.new()
		_ghost_material.shader = load("res://shaders/ghost.gdshader")
		# Чертёж рисуется после воды, иначе вода «срезает» его у берега.
		# Перед цветом — проход глубины (приоритет ниже — рисуется раньше).
		_ghost_material.render_priority = 3
		var depth := ShaderMaterial.new()
		depth.shader = load("res://shaders/ghost_depth.gdshader")
		depth.render_priority = 2
		_ghost_material.next_pass = depth
		_ghost_opening_material = _ghost_material.duplicate()
		_ghost_opening_material.set_shader_parameter("highlight", 1.0)
	return _ghost_opening_material if opening else _ghost_material


## Ставит на меш чертёж: двери и окна — светлым тёплым оттенком.
## Возвращает созданные копии материалов (чтобы менять им цвет и прогресс).
static func apply_ghost_materials(mi: MeshInstance3D, own_copies: bool) -> Array[ShaderMaterial]:
	var made: Array[ShaderMaterial] = []
	for i in mi.mesh.get_surface_count():
		var m := ghost_material(ModelLibrary.surface_tag(mi.mesh, i) == "opening")
		if own_copies:
			m = m.duplicate()
			m.next_pass = m.next_pass.duplicate()
			made.append(m)
		mi.set_surface_override_material(i, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return made


static func highlight_material() -> StandardMaterial3D:
	if _highlight_material == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.3, 0.25, 0.35)
		_highlight_material = m
	return _highlight_material


func setup(building_id: String, angle: float, instant: bool) -> void:
	id = building_id
	yaw = angle
	rotation.y = angle
	_apply_tilt()
	footprint = footprint_for(id, position, angle)
	var data := ModelLibrary.building(id)
	top_height = (data["bounds"] as AABB).end.y
	name = "%s_%d" % [id, get_instance_id()]

	_mesh = MeshInstance3D.new()
	_mesh.mesh = data["mesh"]
	add_child(_mesh)
	if data["rotor_mesh"]:
		_rotor = Node3D.new()
		_rotor.position = data["pivot"]
		add_child(_rotor)
		_rotor_mesh = MeshInstance3D.new()
		_rotor_mesh.mesh = data["rotor_mesh"]
		_rotor.add_child(_rotor_mesh)

	var def: Dictionary = GameData.BUILDINGS[id]
	if instant or GameMode.is_creative() or def.get("light", false) and def["time"] <= 0.6:
		ModelLibrary.apply_building_materials(_mesh)
		if _rotor_mesh:
			ModelLibrary.apply_building_materials(_rotor_mesh)
		progress = 1.0
		_finish(not instant)
		return

	_use_progress_materials(_mesh)
	if _rotor_mesh:
		_use_progress_materials(_rotor_mesh)
	_ghost = MeshInstance3D.new()
	_ghost.mesh = data["mesh"]
	add_child(_ghost)
	_progress_materials.append_array(apply_ghost_materials(_ghost, true))
	_set_progress(0.0)

	var b: AABB = data["bounds"]
	# Мелочь (факел, ограда, грядка) строится без лесов и подписи.
	if def.get("light", false):
		return
	_scaffold = _make_scaffold(b)
	add_child(_scaffold)
	_scaffold.position.y = -b.end.y
	_scaffold.create_tween().tween_property(_scaffold, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if WorldLabels.instance:
		_label = WorldLabels.instance.track(self, Vector3(0, top_height + 0.8, 0), "", true)

	_dust = CPUParticles3D.new()
	_dust.amount = 24
	_dust.lifetime = 1.2
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(b.size.x * 0.5, 0.2, b.size.z * 0.5)
	_dust.position = Vector3(b.get_center().x, 0.3, b.get_center().z)
	_dust.direction = Vector3.UP
	_dust.spread = 40.0
	_dust.gravity = Vector3(0, 0.4, 0)
	_dust.initial_velocity_min = 0.3
	_dust.initial_velocity_max = 0.9
	var puff := SphereMesh.new()
	puff.radius = 0.16
	puff.height = 0.32
	puff.radial_segments = 5
	puff.rings = 3
	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color = Color(0.85, 0.8, 0.7)
	dust_mat.roughness = 1.0
	puff.material = dust_mat
	_dust.mesh = puff
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0))
	_dust.scale_amount_curve = curve
	add_child(_dust)
	_update_label()


## Дорожка ложится по склону: «верх» здания смотрит по нормали земли.
func _apply_tilt() -> void:
	if not GameData.BUILDINGS[id].get("tilt", false) or ground_normal.is_equal_approx(Vector3.UP):
		return
	var n := ground_normal.normalized()
	if n.y < 0.5:
		return
	basis = Basis(Quaternion(Vector3.UP, n)) * Basis(Vector3.UP, yaw)


## Сменить культуру на грядке (сажается заново).
func set_crop(crop_id: String) -> void:
	crop = crop_id
	planted = Time.get_unix_time_from_system()
	if _crops:
		_crops.setup(crop, planted, GameData.BUILDINGS[id]["crops"], GameData.BUILDINGS[id].get("crop_top", 0.2))


func has_crops() -> bool:
	return GameData.BUILDINGS[id].has("crops")


func _add_extras() -> void:
	var def: Dictionary = GameData.BUILDINGS[id]
	for f: Array in def.get("fire", []):
		var fire := Fire.new()
		fire.size = f[1]
		fire.position = f[0]
		add_child(fire)
	if def.has("crops"):
		if crop == "":
			crop = "wheat"
		if planted <= 0.0:
			planted = Time.get_unix_time_from_system()
		_crops = CropPatch.new()
		add_child(_crops)
		_crops.setup(crop, planted, def["crops"], def.get("crop_top", 0.2))


## Свои копии материалов для меша (общие материалы держат build_progress = 1).
func _use_progress_materials(mi: MeshInstance3D) -> void:
	for i in mi.mesh.get_surface_count():
		var m := ModelLibrary.building_material(ModelLibrary._surface_material_name(mi.mesh, i)).duplicate() as ShaderMaterial
		mi.set_surface_override_material(i, m)
		_progress_materials.append(m)


## Строительные леса: стойки по периметру, настилы и раскосы из жердей.
func _make_scaffold(b: AABB) -> MeshInstance3D:
	var g := Geo.new()
	g.with_uv2 = false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var pad := 0.35
	var x0 := b.position.x - pad
	var x1 := b.end.x + pad
	var z0 := b.position.z - pad
	var z1 := b.end.z + pad
	var height := clampf(b.end.y * 0.8, 1.6, 9.0)
	var wood := Color(0.62, 0.45, 0.28)
	var posts: Array[Vector3] = []
	for side in 4:
		var a := Vector3(x0, 0, z0) if side == 0 else (Vector3(x1, 0, z0) if side == 1 else (Vector3(x1, 0, z1) if side == 2 else Vector3(x0, 0, z1)))
		var c := Vector3(x1, 0, z0) if side == 0 else (Vector3(x1, 0, z1) if side == 1 else (Vector3(x0, 0, z1) if side == 2 else Vector3(x0, 0, z0)))
		var count := maxi(1, ceili(a.distance_to(c) / 2.2))
		for i in count:
			posts.append(a.lerp(c, float(i) / count))
		for level in range(1, int(height / 1.4) + 1):
			var y := level * 1.4
			g.rod("log", a + Vector3(0, y, 0), c + Vector3(0, y, 0), 0.04, 0.04, 4, wood.darkened(rng.randf_range(0.0, 0.15)), false)
		g.rod("log", a + Vector3(0, 0.2, 0), c + Vector3(0, height * 0.9, 0), 0.03, 0.03, 4, wood.darkened(0.2), false)
	for p in posts:
		g.rod("log", p + Vector3(0, -0.2, 0), p + Vector3(0, height, 0), 0.05, 0.045, 5, wood.lightened(rng.randf_range(-0.05, 0.08)))
	var mi := MeshInstance3D.new()
	mi.mesh = g.build_mesh()
	mi.material_override = ModelLibrary.building_material("log")
	return mi


func build_time() -> float:
	return GameData.BUILDINGS[id]["time"]


func _set_progress(value: float) -> void:
	for m in _progress_materials:
		m.set_shader_parameter("build_progress", value)
		if m.next_pass:
			(m.next_pass as ShaderMaterial).set_shader_parameter("build_progress", value)


func _process(delta: float) -> void:
	if _rotor:
		# Крылья мельницы: чем сильнее ветер, тем быстрее.
		var target := (0.35 + Weather.wind * 1.8) if is_complete else 0.0
		_rotor_speed = lerpf(_rotor_speed, target, 1.0 - exp(-0.6 * delta))
		_rotor.rotate_object_local(Vector3.BACK, _rotor_speed * delta)
	if is_complete or _removing:
		return
	progress = minf(progress + delta / build_time(), 1.0)
	_set_progress(progress)
	_update_label()
	if progress >= 1.0:
		_finish(true)


func _update_label() -> void:
	if not _label.is_empty():
		(_label["label"] as Label).text = "%s  %d%%" % [GameData.BUILDINGS[id]["name"], roundi(progress * 100.0)]
		(_label["bar"] as ProgressBar).value = progress


func _finish(animate: bool) -> void:
	is_complete = true
	WorldState.register_completed(id)
	# Готовое здание переходит на общие материалы.
	_progress_materials.clear()
	ModelLibrary.apply_building_materials(_mesh)
	if _rotor_mesh:
		ModelLibrary.apply_building_materials(_rotor_mesh)
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if not _label.is_empty() and WorldLabels.instance:
		WorldLabels.instance.untrack(_label)
		_label = {}
	if _scaffold:
		var sc := _scaffold
		_scaffold = null
		var tw := sc.create_tween()
		tw.tween_property(sc, "position:y", -top_height * 1.1, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(sc.queue_free)
	_add_extras()
	if animate:
		if _dust:
			_dust.emitting = false
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.06, 0.92, 1.06), 0.12).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_mesh, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		Fx.burst(get_parent(), global_position + Vector3(0, 0.5, 0), Color(0.9, 0.85, 0.7), 24, 0.25)
	completed.emit(self)


func set_highlight(on: bool) -> void:
	_mesh.material_overlay = highlight_material() if on else null
	if _rotor_mesh:
		_rotor_mesh.material_overlay = highlight_material() if on else null


## Плавно «разбирает» здание сверху вниз и удаляет узел.
func demolish() -> void:
	if _removing:
		return
	_removing = true
	if is_complete:
		WorldState.unregister_completed(id)
	set_highlight(false)
	if not _label.is_empty() and WorldLabels.instance:
		WorldLabels.instance.untrack(_label)
		_label = {}
	if _progress_materials.is_empty():
		_use_progress_materials(_mesh)
		if _rotor_mesh:
			_use_progress_materials(_rotor_mesh)
	var tw := create_tween()
	tw.tween_method(_set_progress, progress, 0.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
	if _scaffold:
		_scaffold.queue_free()
	Fx.burst(get_parent(), global_position + Vector3(0, 0.5, 0), Color(0.75, 0.7, 0.6), 30, 0.3)
