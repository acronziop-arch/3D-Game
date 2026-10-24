class_name Building
extends Node3D
## Здание в мире. Модель — models/buildings/<id>.glb. Стройку рисует шейдер
## building.gdshader: каждая деталь «прилетает» сверху на своё место, снизу вверх,
## а ещё не построенная часть видна как голубой полупрозрачный чертёж.
## Время стройки — GameData.BUILDINGS[id].time (не больше 30 с).

signal completed(building: Building)

static var _ghost_material: ShaderMaterial
static var _highlight_material: StandardMaterial3D

var id := ""
var rot_steps := 0
var progress := 0.0
var is_complete := false
var footprint := Rect2()
var top_height := 0.0

var _mesh: MeshInstance3D
var _ghost: MeshInstance3D
var _rotor: Node3D
var _rotor_mesh: MeshInstance3D
var _rotor_speed := 0.0
var _label: Label3D
var _dust: CPUParticles3D
var _removing := false


static func footprint_for(building_id: String, pos: Vector3, steps: int) -> Rect2:
	var b: AABB = ModelLibrary.building(building_id)["bounds"]
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


static func ghost_material() -> ShaderMaterial:
	if _ghost_material == null:
		_ghost_material = ShaderMaterial.new()
		_ghost_material.shader = load("res://shaders/ghost.gdshader")
	return _ghost_material


static func highlight_material() -> StandardMaterial3D:
	if _highlight_material == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.3, 0.25, 0.35)
		_highlight_material = m
	return _highlight_material


func setup(building_id: String, steps: int, instant: bool) -> void:
	id = building_id
	rot_steps = steps
	rotation.y = steps * PI * 0.5
	footprint = footprint_for(id, position, steps)
	var data := ModelLibrary.building(id)
	top_height = (data["bounds"] as AABB).end.y
	name = "%s_%d" % [id, get_instance_id()]

	_mesh = MeshInstance3D.new()
	_mesh.mesh = data["mesh"]
	ModelLibrary.apply_building_materials(_mesh)
	add_child(_mesh)
	if data["rotor_mesh"]:
		_rotor = Node3D.new()
		_rotor.position = data["pivot"]
		add_child(_rotor)
		_rotor_mesh = MeshInstance3D.new()
		_rotor_mesh.mesh = data["rotor_mesh"]
		ModelLibrary.apply_building_materials(_rotor_mesh)
		_rotor.add_child(_rotor_mesh)

	if instant:
		progress = 1.0
		_finish(false)
		return

	_set_progress(0.0)
	_ghost = MeshInstance3D.new()
	_ghost.mesh = data["mesh"]
	_ghost.material_override = ghost_material()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	_ghost.set_instance_shader_parameter("build_progress", 0.0)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font = UiStyle.font(800)
	_label.font_size = 44
	_label.outline_size = 12
	_label.modulate = Color(0.25, 0.2, 0.16)
	_label.outline_modulate = Color(0.96, 0.95, 0.93)
	_label.pixel_size = 0.0007
	_label.fixed_size = true
	_label.no_depth_test = true
	_label.render_priority = 10
	_label.position = Vector3(0, top_height + 1.5, 0)
	add_child(_label)

	var b: AABB = data["bounds"]
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


func _set_progress(value: float) -> void:
	_mesh.set_instance_shader_parameter("build_progress", value)
	if _rotor_mesh:
		_rotor_mesh.set_instance_shader_parameter("build_progress", value)
	if _ghost:
		_ghost.set_instance_shader_parameter("build_progress", value)


func _process(delta: float) -> void:
	if _rotor:
		# Крылья мельницы: чем сильнее ветер, тем быстрее.
		var target := (0.35 + Weather.wind * 1.8) if is_complete else 0.0
		_rotor_speed = lerpf(_rotor_speed, target, 1.0 - exp(-0.6 * delta))
		_rotor.rotate_object_local(Vector3.BACK, _rotor_speed * delta)
	if is_complete or _removing:
		return
	# Подпись с fixed_size видна только перед камерой, иначе она проецируется зеркально.
	var cam := get_viewport().get_camera_3d()
	if cam:
		var p := _label.global_position
		_label.visible = not cam.is_position_behind(p) and cam.global_position.distance_to(p) < 160.0
	progress = minf(progress + delta / build_time(), 1.0)
	_set_progress(progress)
	_update_label()
	if progress >= 1.0:
		_finish(true)


func _update_label() -> void:
	if _label:
		_label.text = "%s  %d%%" % [GameData.BUILDINGS[id]["name"], roundi(progress * 100.0)]


func _finish(animate: bool) -> void:
	is_complete = true
	WorldState.register_completed(id)
	_set_progress(1.0)
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if animate:
		_dust.emitting = false
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.05, 0.93, 1.05), 0.12).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_mesh, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_label, "modulate:a", 0.0, 0.6)
		tw.parallel().tween_property(_label, "outline_modulate:a", 0.0, 0.6)
		tw.tween_callback(_label.queue_free)
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
	var tw := create_tween()
	tw.tween_method(_set_progress, progress, 0.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
	Fx.burst(get_parent(), global_position + Vector3(0, 0.5, 0), Color(0.75, 0.7, 0.6), 30, 0.3)
