class_name Splash
extends Node3D
## Брызги воды: капли подпрыгивают там, где струя бьёт в воду (фонтан, колесо мельницы).
##   radius > 0 — капли по кругу этого радиуса (струи фонтана падают в бассейн кольцом);
##   radius = 0 — из одной точки (струйка на макушке фонтана, вода с жёлоба на колесо).
## Зимой, когда вода замерзает, брызг нет.

var radius := 0.0
## Сила брызг: высота подскока капель, м.
var power := 0.3

var _particles: CPUParticles3D

static var _material: StandardMaterial3D


func _ready() -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_material.vertex_color_use_as_albedo = true
		_material.albedo_color = Color(0.9, 0.96, 1.0, 0.85)
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	q.material = _material
	p.mesh = q
	p.amount = 46 if radius > 0.0 else 22
	p.lifetime = 0.55
	p.local_coords = false
	var speed := sqrt(2.0 * 9.8 * power)
	p.direction = Vector3.UP
	p.spread = 28.0 if radius > 0.0 else 40.0
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	if radius > 0.0:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = radius
		p.emission_ring_inner_radius = radius * 0.85
		p.emission_ring_height = 0.0
	else:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.06
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-radius - 1.0, -1.0, -radius - 1.0), Vector3(radius * 2.0 + 2.0, 3.0, radius * 2.0 + 2.0))
	add_child(p)
	_particles = p


func _process(_delta: float) -> void:
	_particles.emitting = is_visible_in_tree() and Weather.ice < 0.6
