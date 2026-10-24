class_name Building
extends Node3D
## Здание в мире. Пока идёт стройка, видна полупрозрачная «тень» будущего
## здания, а детали по одной «выпрыгивают» снизу вверх. Время стройки
## берётся из GameData.BUILDINGS[id].time (не больше 30 с).

signal completed(building: Building)

static var _silhouette_material: StandardMaterial3D
static var _highlight_material: StandardMaterial3D

var id := ""
var rot_steps := 0
var progress := 0.0
var is_complete := false
var footprint := Rect2()
var top_height := 0.0

var _parts: Array[MeshInstance3D] = []
var _shadows: Array[MeshInstance3D] = []
var _revealed := 0
var _visual: Node3D
var _rotor: Node3D
var _rotor_axis := Vector3.FORWARD
var _rotor_speed := 0.0
var _label: Label3D
var _dust: CPUParticles3D
var _removing := false


static func footprint_for(building_id: String, pos: Vector3, steps: int) -> Rect2:
	var b := Blueprints.bounds(building_id)
	var yaw := Basis(Vector3.UP, steps * PI * 0.5)
	var rect := Rect2()
	for i in 4:
		var corner := Vector3(b.position.x if i % 2 == 0 else b.end.x, 0, b.position.z if i < 2 else b.end.z)
		var w := pos + yaw * corner
		if i == 0:
			rect = Rect2(Vector2(w.x, w.z), Vector2.ZERO)
		else:
			rect = rect.expand(Vector2(w.x, w.z))
	return rect


static func silhouette_material() -> StandardMaterial3D:
	if _silhouette_material == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.62, 0.85, 1.0, 0.24)
		_silhouette_material = m
	return _silhouette_material


static func highlight_material() -> StandardMaterial3D:
	if _highlight_material == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.25, 0.2, 0.35)
		_highlight_material = m
	return _highlight_material


func setup(building_id: String, steps: int, instant: bool) -> void:
	id = building_id
	rot_steps = steps
	rotation.y = steps * PI * 0.5
	footprint = footprint_for(id, position, steps)
	top_height = Blueprints.bounds(id).end.y
	name = "%s_%d" % [id, get_instance_id()]

	_visual = Node3D.new()
	add_child(_visual)
	var rotor_def: Dictionary = Blueprints.ROTORS.get(id, {})
	if not rotor_def.is_empty():
		_rotor = Node3D.new()
		_rotor.position = rotor_def["pivot"]
		_rotor_axis = rotor_def["axis"]
		_visual.add_child(_rotor)

	for part in Blueprints.built_parts(id):
		var xform: Transform3D = part["xform"]
		var parent := _visual
		if part["group"] == "rotor" and _rotor:
			parent = _rotor
			xform = _rotor.transform.affine_inverse() * xform
		var mi := MeshInstance3D.new()
		mi.mesh = part["mesh"]
		mi.transform = xform
		parent.add_child(mi)
		_parts.append(mi)
		if not instant:
			mi.scale = Vector3.ONE * 0.001
			mi.visible = false
			var shadow := MeshInstance3D.new()
			shadow.mesh = part["mesh"]
			shadow.transform = xform
			shadow.material_override = silhouette_material()
			shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(shadow)
			_shadows.append(shadow)

	if instant:
		_revealed = _parts.size()
		progress = 1.0
		_finish(false)
		return

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	_label.outline_size = 12
	_label.pixel_size = 0.005
	_label.fixed_size = true
	_label.no_depth_test = true
	_label.position = Vector3(0, top_height + 1.5, 0)
	add_child(_label)

	_dust = CPUParticles3D.new()
	_dust.amount = 24
	_dust.lifetime = 1.2
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var b := Blueprints.bounds(id)
	_dust.emission_box_extents = Vector3(b.size.x * 0.5, 0.2, b.size.z * 0.5)
	_dust.position = Vector3(b.get_center().x, 0.3, b.get_center().z)
	_dust.direction = Vector3.UP
	_dust.spread = 40.0
	_dust.gravity = Vector3(0, 0.4, 0)
	_dust.initial_velocity_min = 0.3
	_dust.initial_velocity_max = 0.9
	var puff := SphereMesh.new()
	puff.radius = 0.18
	puff.height = 0.36
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


func build_time() -> float:
	return GameData.BUILDINGS[id]["time"]


func _process(delta: float) -> void:
	if _rotor:
		var target_speed := deg_to_rad(Blueprints.ROTORS[id]["speed"]) if is_complete else 0.0
		_rotor_speed = lerpf(_rotor_speed, target_speed, 1.0 - exp(-0.8 * delta))
		_rotor.rotate_object_local(_rotor_axis, _rotor_speed * delta)
	if is_complete or _removing:
		return
	# Подпись с fixed_size видна только перед камерой, иначе она проецируется зеркально.
	var cam := get_viewport().get_camera_3d()
	if cam:
		var p := _label.global_position
		_label.visible = not cam.is_position_behind(p) and cam.global_position.distance_to(p) < 160.0
	progress = minf(progress + delta / build_time(), 1.0)
	# Последняя деталь появляется на 92% — оставшееся время она «досаживается».
	var should_reveal := ceili(progress / 0.92 * _parts.size())
	while _revealed < mini(should_reveal, _parts.size()):
		_reveal(_revealed)
		_revealed += 1
	_update_label()
	if progress >= 1.0:
		_finish(true)


func _reveal(i: int) -> void:
	var mi := _parts[i]
	mi.visible = true
	_shadows[i].visible = false
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_label() -> void:
	if _label:
		_label.text = "%s  %d%%" % [GameData.BUILDINGS[id]["name"], roundi(progress * 100.0)]


func _finish(animate: bool) -> void:
	is_complete = true
	WorldState.register_completed(id)
	for mi in _parts:
		mi.visible = true
		if not animate:
			mi.scale = Vector3.ONE
	for s in _shadows:
		s.queue_free()
	_shadows.clear()
	if animate:
		_dust.emitting = false
		var tw := create_tween()
		tw.tween_property(_visual, "scale", Vector3(1.06, 0.92, 1.06), 0.12).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_visual, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_label, "modulate:a", 0.0, 0.6)
		tw.tween_callback(_label.queue_free)
		Fx.burst(get_parent(), global_position + Vector3(0, 0.5, 0), Color(0.9, 0.85, 0.7), 24, 0.25)
	completed.emit(self)


func set_highlight(on: bool) -> void:
	for mi in _parts:
		mi.material_overlay = highlight_material() if on else null


## Плавно «разбирает» здание и удаляет узел.
func demolish() -> void:
	if _removing:
		return
	_removing = true
	if is_complete:
		WorldState.unregister_completed(id)
	set_highlight(false)
	var tw := create_tween().set_parallel(true)
	var n := _parts.size()
	for i in n:
		var mi := _parts[n - 1 - i]
		tw.tween_property(mi, "scale", Vector3.ONE * 0.001, 0.25).set_delay(i * 0.6 / n) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
	Fx.burst(get_parent(), global_position + Vector3(0, 0.5, 0), Color(0.75, 0.7, 0.6), 30, 0.3)
