class_name Fire
extends Node3D
## Живой огонь костра и факела: несколько язычков пламени (шейдер с бегущим
## шумом), искры, дым и мерцающий тёплый свет. size — высота пламени, м.
## В дождь, снегопад и сильный ветер огонь гаснет (остаётся дымок от углей),
## а когда непогода стихает — разгорается снова.

var size := 1.0

var _light: OmniLight3D
var _flames: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _t := 0.0
var _seed := 0.0
## 1 — горит, 0 — погас.
var _burn := 1.0
var _embers: GPUParticles3D
var _smoke: GPUParticles3D
## Сколько ещё дымят угли после того, как огонь погас, с.
var _smolder := 0.0

static var _noise: NoiseTexture2D
static var _ember_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D


func _ready() -> void:
	_seed = randf() * 10.0
	_burn = 0.0 if is_put_out() else 1.0
	if _noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.035
		n.fractal_octaves = 3
		_noise = NoiseTexture2D.new()
		_noise.width = 128
		_noise.height = 128
		_noise.seamless = true
		_noise.noise = n
	var shader: Shader = load("res://shaders/fire.gdshader")
	# Слои: широкое красное пламя, оранжевое и узкое яркое ядро.
	var layers := [[1.0, 1.0, 0.75], [0.78, 0.86, 0.95], [0.48, 0.62, 1.15]]
	for i in layers.size():
		var l: Array = layers[i]
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(size * 0.9 * l[0], size * 1.3 * l[1])
		quad.center_offset = Vector3(0, size * 0.65 * l[1], 0)
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("noise_tex", _noise)
		m.set_shader_parameter("seed", _seed + i * 3.7)
		m.set_shader_parameter("speed", 1.1 + i * 0.25)
		m.set_shader_parameter("intensity", l[2])
		m.render_priority = 3 + i
		mi.material_override = m
		mi.position = Vector3(0, 0, 0.01 * i)
		add_child(mi)
		_flames.append(mi)
		_materials.append(m)
	_embers = _make_embers()
	add_child(_embers)
	_smoke = _make_smoke()
	add_child(_smoke)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.3)
	_light.omni_range = 4.0 + size * 4.0
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = false
	# Далёкие огни гаснут: в деревне десятки факелов, а светить нужно только ближним.
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 45.0
	_light.distance_fade_length = 15.0
	_light.position = Vector3(0, size * 0.55, 0)
	add_child(_light)


func _make_embers() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(6, roundi(26 * size))
	p.lifetime = 1.6
	p.randomness = 0.6
	p.visibility_aabb = AABB(Vector3(-2, -0.5, -2) * size, Vector3(4, 6, 4) * size)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.22 * size
	m.direction = Vector3(0, 1, 0)
	m.spread = 22.0
	m.initial_velocity_min = 1.0 * size + 0.4
	m.initial_velocity_max = 2.2 * size + 0.6
	m.gravity = Vector3(0, 0.4, 0)
	m.damping_min = 0.6
	m.damping_max = 1.2
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.6
	m.turbulence_noise_scale = 1.2
	m.turbulence_influence_min = 0.05
	m.turbulence_influence_max = 0.14
	m.scale_min = 0.6
	m.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.92, 0.55, 1.0))
	ramp.set_color(1, Color(0.9, 0.2, 0.02, 0.0))
	ramp.add_point(0.45, Color(1.0, 0.55, 0.12, 1.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_ramp = tex
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.05
	if _ember_mat == null:
		_ember_mat = StandardMaterial3D.new()
		_ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ember_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ember_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_ember_mat.vertex_color_use_as_albedo = true
		_ember_mat.albedo_color = Color(1.6, 1.3, 1.0)
	quad.material = _ember_mat
	p.draw_pass_1 = quad
	return p


func _make_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(4, roundi(10 * size))
	p.lifetime = 3.6
	p.visibility_aabb = AABB(Vector3(-3, -0.5, -3) * size, Vector3(6, 9, 6) * size)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0, size * 0.9, 0)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.15 * size
	m.direction = Vector3(0, 1, 0)
	m.spread = 12.0
	m.initial_velocity_min = 0.5 + size * 0.3
	m.initial_velocity_max = 0.8 + size * 0.5
	m.gravity = Vector3(0.25, 0.15, 0.1)
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -25.0
	m.angular_velocity_max = 25.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	m.scale_min = 0.8 * size
	m.scale_max = 1.3 * size
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.45, 0.42, 0.4, 0.0))
	ramp.set_color(1, Color(0.6, 0.6, 0.6, 0.0))
	ramp.add_point(0.2, Color(0.42, 0.4, 0.38, 0.28))
	ramp.add_point(0.65, Color(0.55, 0.55, 0.55, 0.12))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	m.color_ramp = tex
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 1.1
	if _smoke_mat == null:
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var soft := GradientTexture2D.new()
		soft.gradient = g
		soft.fill = GradientTexture2D.FILL_RADIAL
		soft.fill_from = Vector2(0.5, 0.5)
		soft.fill_to = Vector2(0.5, 0.0)
		soft.width = 64
		soft.height = 64
		_smoke_mat.albedo_texture = soft
	quad.material = _smoke_mat
	p.draw_pass_1 = quad
	return p


## Погода, при которой огонь не горит.
static func is_put_out() -> bool:
	return Weather.rain > 0.35 or Weather.snow > 0.35 or Weather.wind > 0.6


func _process(delta: float) -> void:
	_t += delta
	var out := is_put_out()
	var was := _burn
	# Гаснет за пару секунд, разгорается медленнее.
	_burn = move_toward(_burn, 0.0 if out else 1.0, delta / (2.0 if out else 5.0))
	if was > 0.05 and _burn <= 0.05:
		_smolder = 14.0
	_smolder = maxf(_smolder - delta, 0.0)
	_embers.emitting = _burn > 0.45
	_smoke.emitting = _burn > 0.2 or _smolder > 0.0
	_light.visible = _burn > 0.01
	# Мерцание: два наложенных колебания и немного случайности.
	var flicker := 0.82 + 0.1 * sin(_t * 9.3 + _seed) + 0.06 * sin(_t * 23.0 + _seed * 2.0) + randf() * 0.04
	var dark := 1.0 - Weather.daylight()
	_light.light_energy = (0.7 + size * 0.9) * flicker * lerpf(0.45, 1.5, dark) * _burn
	_light.position.x = sin(_t * 5.0) * 0.03 * size
	for m in _materials:
		m.set_shader_parameter("darkness", dark)
	# Под дождём пламя чуть ниже.
	var k := (1.0 - Weather.rain * 0.25) * _burn
	for f in _flames:
		f.visible = _burn > 0.02
		f.scale = Vector3(lerpf(0.35, 1.0, _burn), maxf(k, 0.01) * (0.94 + 0.08 * sin(_t * 7.0 + f.get_index())), 1.0)
