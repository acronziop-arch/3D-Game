class_name Fx
extends RefCounted
## Мелкие эффекты: всплывающий текст «+5 Брёвна», облачко пыли.


static func floating_text(parent: Node, world_pos: Vector3, text: String, color := Color.WHITE, delay := 0.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = UiStyle.font(800)
	label.modulate = Color(color, 0.0)
	label.outline_modulate = Color(UiStyle.BASE, 0.0)
	label.font_size = 56
	label.outline_size = 16
	label.pixel_size = 0.0007
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.render_priority = 10
	parent.add_child(label)
	label.global_position = world_pos
	var tw := label.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(label, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(label, "outline_modulate:a", 0.95, 0.15)
	tw.parallel().tween_property(label, "global_position", world_pos + Vector3(0, 1.6, 0), 1.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(label, "outline_modulate:a", 0.0, 0.35)
	tw.tween_callback(label.queue_free)


static func show_loot(parent: Node, world_pos: Vector3, loot: Dictionary) -> void:
	# Надписи постоянного экранного размера: шаг между строками зависит от расстояния до камеры.
	var cam := parent.get_viewport().get_camera_3d()
	var step := 0.5 if cam == null else cam.global_position.distance_to(world_pos) * 0.04
	var i := 0
	for id: String in loot:
		floating_text(parent, world_pos + Vector3(0, i * step, 0), "+%d %s" % [loot[id], GameData.res_name(id)],
			GameData.res_color(id).darkened(0.35), i * 0.18)
		i += 1


static func burst(parent: Node, world_pos: Vector3, color: Color, amount := 16, size := 0.18) -> void:
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
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	p.finished.connect(p.queue_free)
