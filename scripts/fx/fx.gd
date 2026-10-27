class_name Fx
extends RefCounted
## Мелкие эффекты: всплывающий текст «+5 Брёвна», облачко пыли.
## Текст рисует интерфейс (WorldLabels) — его не красит ночь и туман.


static func floating_text(world_pos: Vector3, text: String, color := Color.WHITE, delay := 0.0, line := 0) -> void:
	if WorldLabels.instance:
		WorldLabels.instance.float_text(world_pos, text, color, delay, line)


static func show_loot(_parent: Node, world_pos: Vector3, loot: Dictionary) -> void:
	var i := 0
	for id: String in loot:
		floating_text(world_pos, "+%d %s" % [loot[id], GameData.res_name(id)], GameData.res_color(id).darkened(0.35), i * 0.18, i)
		i += 1


static func burst(parent: Node, world_pos: Vector3, color: Color, amount := 16, size := 0.18) -> void:
	var p := burst_node(color, amount, size)
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	p.finished.connect(p.queue_free)


## Облачко кубиков (ещё не запущенное) — его же показывает подготовка графики при запуске.
static func burst_node(color: Color, amount := 16, size := 0.18) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -6.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	cube.material = mat
	p.mesh = cube
	return p
