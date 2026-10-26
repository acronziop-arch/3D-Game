class_name Atmosphere
extends Node3D
## Всё, что видно от погоды и времени суток: солнце и луна, небо с облаками,
## туман, дождь, снег, листопад, молнии и глобальные параметры шейдеров (ветер,
## влага, снег, листва). Логика времени и погоды — в автозагрузке Weather.

const RAIN_LAYER := 4

@export var sun: DirectionalLight3D
@export var moon: DirectionalLight3D
@export var world_environment: WorldEnvironment

var camera_rig: CameraRig

var _sky_material: ShaderMaterial
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _leaves: GPUParticles3D
var _rain_material: ParticleProcessMaterial
var _snow_material: ParticleProcessMaterial
var _leaves_material: ParticleProcessMaterial
## Доля лиственного леса вокруг камеры: листья падают там, где есть деревья.
var _forest := 0.0
var _forest_timer := 0.0
var _cloud_offset := Vector2.ZERO
var _wind_phase := 0.0
var _wind_drift := Vector2.ZERO
var _flash := 0.0
var _next_lightning := 6.0


func _ready() -> void:
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = load("res://shaders/sky.gdshader")
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	_sky_material.set_shader_parameter("cloud_noise", tex)
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	world_environment.environment.background_mode = Environment.BG_SKY
	world_environment.environment.sky = sky
	_rain = _make_rain()
	_snow = _make_snow()
	_leaves = _make_leaves()


func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = roundi(7000 * Platform.particle_scale())
	p.lifetime = 1.1
	p.preprocess = 1.0
	p.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 60, 120))
	p.layers = RAIN_LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_material = ParticleProcessMaterial.new()
	_rain_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_material.emission_box_extents = Vector3(45, 1, 45)
	_rain_material.direction = Vector3(0, -1, 0)
	_rain_material.spread = 2.0
	_rain_material.initial_velocity_min = 22.0
	_rain_material.initial_velocity_max = 27.0
	_rain_material.gravity = Vector3(0, -9.8, 0)
	_rain_material.particle_flag_align_y = true
	p.process_material = _rain_material
	var drop := BoxMesh.new()
	drop.size = Vector3(0.025, 0.75, 0.025)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.8, 0.88, 1.0, 0.32)
	drop.material = mat
	p.draw_pass_1 = drop
	p.emitting = false
	add_child(p)
	return p


func _make_snow() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = roundi(6000 * Platform.particle_scale())
	p.lifetime = 9.0
	p.preprocess = 6.0
	p.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 60, 120))
	p.layers = RAIN_LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow_material = ParticleProcessMaterial.new()
	_snow_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_snow_material.emission_box_extents = Vector3(45, 8, 45)
	_snow_material.direction = Vector3(0, -1, 0)
	_snow_material.spread = 20.0
	_snow_material.initial_velocity_min = 1.2
	_snow_material.initial_velocity_max = 2.2
	_snow_material.gravity = Vector3(0, -0.6, 0)
	_snow_material.turbulence_enabled = true
	_snow_material.turbulence_noise_strength = 1.5
	_snow_material.turbulence_noise_scale = 6.0
	_snow_material.scale_min = 0.6
	_snow_material.scale_max = 1.3
	p.process_material = _snow_material
	var flake := QuadMesh.new()
	flake.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(1, 1, 1, 0.9)
	flake.material = mat
	p.draw_pass_1 = flake
	p.emitting = false
	add_child(p)
	return p


## Осенний листопад: листья кружатся и сносятся ветром.
func _make_leaves() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = roundi(900 * Platform.particle_scale())
	p.lifetime = 10.0
	p.preprocess = 6.0
	p.visibility_aabb = AABB(Vector3(-50, -30, -50), Vector3(100, 45, 100))
	p.layers = RAIN_LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_leaves_material = ParticleProcessMaterial.new()
	_leaves_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_leaves_material.emission_box_extents = Vector3(34, 5, 34)
	_leaves_material.direction = Vector3(0, -1, 0)
	_leaves_material.spread = 35.0
	_leaves_material.initial_velocity_min = 0.3
	_leaves_material.initial_velocity_max = 0.9
	_leaves_material.gravity = Vector3(0, -0.5, 0)
	_leaves_material.turbulence_enabled = true
	_leaves_material.turbulence_noise_strength = 2.2
	_leaves_material.turbulence_noise_scale = 5.0
	_leaves_material.turbulence_noise_speed_random = 0.6
	_leaves_material.angle_min = -180.0
	_leaves_material.angle_max = 180.0
	_leaves_material.angular_velocity_min = -160.0
	_leaves_material.angular_velocity_max = 160.0
	_leaves_material.scale_min = 1.0
	_leaves_material.scale_max = 1.7
	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.3, 0.55, 0.8, 1.0])
	colors.colors = PackedColorArray([Color(0.86, 0.46, 0.12), Color(0.93, 0.72, 0.22), Color(0.74, 0.24, 0.1),
		Color(0.55, 0.36, 0.16), Color(0.8, 0.6, 0.2)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = colors
	_leaves_material.color_initial_ramp = ramp
	# Исчезают в конце жизни (уменьшаются), а не пропадают разом.
	var fade := Curve.new()
	fade.add_point(Vector2(0, 0))
	fade.add_point(Vector2(0.08, 1))
	fade.add_point(Vector2(0.85, 1))
	fade.add_point(Vector2(1, 0))
	var fade_tex := CurveTexture.new()
	fade_tex.curve = fade
	_leaves_material.scale_curve = fade_tex
	p.process_material = _leaves_material
	p.draw_pass_1 = _leaf_mesh()
	p.emitting = false
	add_child(p)
	return p


static func _leaf_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([Vector3(0, -0.11, 0), Vector3(0.06, 0, 0.01), Vector3(0, 0.11, 0),
		Vector3(0, -0.11, 0), Vector3(0, 0.11, 0), Vector3(-0.06, 0, 0.01)])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.BACK)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.85
	mat.backlight_enabled = true
	mat.backlight = Color(0.5, 0.35, 0.15)
	mesh.surface_set_material(0, mat)
	return mesh


func _process(delta: float) -> void:
	var daylight := Weather.daylight()
	var sun_angle := (Weather.hour - 6.0) / 12.0 * PI
	var elevation := sin(sun_angle) * deg_to_rad(62.0)
	var azimuth := deg_to_rad(110.0) - (Weather.hour / 24.0) * TAU
	var sun_dir := Vector3(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth))
	var moon_dir := Vector3(-sun_dir.x, absf(sun_dir.y) * 0.8 + 0.25, -sun_dir.z).normalized()
	_aim(sun, sun_dir)
	_aim(moon, moon_dir)

	var low := 1.0 - smoothstep(0.0, 0.45, sun_dir.y)
	var clear := 1.0 - Weather.overcast
	sun.visible = sun_dir.y > -0.08
	sun.light_energy = smoothstep(-0.05, 0.2, sun_dir.y) * (1.25 - Weather.overcast * 0.8) + _flash * 1.5
	sun.light_color = Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.6, 0.34), low * clear)
	moon.visible = daylight < 0.6
	moon.light_energy = (1.0 - daylight) * 0.22 * (1.0 - Weather.overcast * 0.6) + _flash * 0.8

	var env := world_environment.environment
	var horizon_day := Color(0.74, 0.85, 0.93).lerp(Color(0.66, 0.69, 0.72), Weather.overcast)
	var horizon := Color(0.07, 0.11, 0.2).lerp(horizon_day, daylight)
	if low > 0.0:
		horizon = horizon.lerp(Color(0.95, 0.62, 0.42), low * daylight * clear * 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.25, 0.4).lerp(Color(0.74, 0.8, 0.88), daylight).lerp(Color(0.62, 0.64, 0.68), Weather.overcast * daylight * 0.5)
	env.ambient_light_energy = lerpf(0.55, 0.95, daylight) + _flash * 2.0
	env.fog_light_color = horizon
	# Туман густеет к краю загруженного мира — чанки появляются незаметно.
	var view_far := float(Settings.get_value("view_distance")) * WorldGen.CHUNK_SIZE - 12.0
	var far := lerpf(view_far, 80.0, Weather.fog) * (1.0 - Weather.rain * 0.25)
	env.fog_depth_end = far
	env.fog_depth_begin = lerpf(far * 0.5, 8.0, Weather.fog)
	env.tonemap_exposure = lerpf(1.35, 1.0, daylight)

	_cloud_offset += Weather.wind_dir * (0.0015 + Weather.wind * 0.006) * delta
	_sky_material.set_shader_parameter("daylight", daylight)
	_sky_material.set_shader_parameter("sunset", low * daylight * clear)
	_sky_material.set_shader_parameter("overcast", Weather.overcast)
	_sky_material.set_shader_parameter("cloud_coverage", Weather.clouds)
	_sky_material.set_shader_parameter("cloud_darkness", clampf(Weather.overcast * 0.8 + Weather.storm * 0.4, 0.0, 1.0))
	_sky_material.set_shader_parameter("cloud_offset", _cloud_offset)
	_sky_material.set_shader_parameter("flash", _flash)

	_lightning(delta)
	_particles(delta)

	RenderingServer.global_shader_parameter_set("wind_dir", Weather.wind_dir)
	RenderingServer.global_shader_parameter_set("wind_strength", Weather.wind)
	RenderingServer.global_shader_parameter_set("wetness", Weather.wetness)
	RenderingServer.global_shader_parameter_set("snow_cover", Weather.snow_cover)
	RenderingServer.global_shader_parameter_set("leaf_amount", Weather.leaf_amount())
	RenderingServer.global_shader_parameter_set("autumn", Weather.autumn_amount())
	RenderingServer.global_shader_parameter_set("spring", Weather.spring_amount())
	RenderingServer.global_shader_parameter_set("night", 1.0 - daylight)
	RenderingServer.global_shader_parameter_set("rain", Weather.rain)
	RenderingServer.global_shader_parameter_set("frost", clampf(Weather.winter_amount() * 0.7 + Weather.snow * 0.5 + Weather.snow_cover * 0.3, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set("ice", Weather.ice)
	RenderingServer.global_shader_parameter_set("snowfall", Weather.snow)
	# Фаза качания и снос ряби копятся по кадрам: при смене погоды меняется
	# только скорость, поэтому деревья и вода не «проматываются» вперёд.
	_wind_phase = fmod(_wind_phase + delta * (1.0 + Weather.wind * 1.6), TAU * 1000.0)
	_wind_drift = (_wind_drift + Weather.wind_dir * (0.12 + Weather.wind * 0.35) * delta)
	if _wind_drift.length() > 6000.0:
		_wind_drift = Vector2.ZERO
	RenderingServer.global_shader_parameter_set("wind_phase", _wind_phase)
	RenderingServer.global_shader_parameter_set("wind_drift", _wind_drift)


static func _aim(light: DirectionalLight3D, toward_light: Vector3) -> void:
	var up := Vector3.UP if absf(toward_light.y) < 0.98 else Vector3.FORWARD
	light.global_transform.basis = Basis.looking_at(-toward_light, up)


func _lightning(delta: float) -> void:
	_flash = maxf(_flash - delta * 4.0, 0.0)
	if Weather.storm < 0.5:
		return
	_next_lightning -= delta
	if _next_lightning <= 0.0:
		_next_lightning = randf_range(4.0, 14.0)
		var tw := create_tween()
		tw.tween_property(self, "_flash", 1.0, 0.04)
		tw.tween_property(self, "_flash", 0.2, 0.08)
		tw.tween_property(self, "_flash", 0.9, 0.05)


func _particles(delta: float) -> void:
	if camera_rig == null:
		return
	var focus := camera_rig.global_position
	_forest_timer -= delta
	if _forest_timer <= 0.0:
		_forest_timer = 1.0
		_forest = lerpf(_forest, _forest_around(focus), 0.35)
	var wind := Vector3(Weather.wind_dir.x, 0, Weather.wind_dir.y) * Weather.wind
	_rain.global_position = focus + Vector3(0, 26, 0) - wind * 8.0
	_snow.global_position = focus + Vector3(0, 14, 0) - wind * 10.0
	_rain.emitting = Weather.rain > 0.02
	_rain.amount_ratio = clampf(Weather.rain, 0.0, 1.0)
	_rain_material.direction = (Vector3(0, -1, 0) + wind * 0.35).normalized()
	_snow.emitting = Weather.snow > 0.02
	_snow.amount_ratio = clampf(Weather.snow, 0.0, 1.0)
	_snow_material.gravity = Vector3(0, -0.6, 0) + wind * 3.0
	# Листопад — осенью, пока на деревьях ещё есть листья, и в лиственном лесу.
	var fall := Weather.autumn_amount() * smoothstep(0.02, 0.35, Weather.leaf_amount()) \
		* (0.15 + _forest * 0.85) * (1.0 - Weather.snow)
	_leaves.global_position = focus + Vector3(0, 9, 0) - wind * 6.0
	_leaves.emitting = fall > 0.03
	_leaves.amount_ratio = clampf(fall, 0.0, 1.0)
	_leaves_material.gravity = Vector3(0, -0.5, 0) + wind * 2.5


## Доля лиственного леса (дубы, берёзы, клёны) в пяти точках вокруг камеры.
func _forest_around(focus: Vector3) -> float:
	var cm := camera_rig.chunk_manager
	if cm == null or cm.gen == null:
		return 0.0
	var n := 0.0
	for o: Vector2 in [Vector2.ZERO, Vector2(18, 0), Vector2(-18, 0), Vector2(0, 18), Vector2(0, -18)]:
		var info: Array = WorldGen.COVER.get(cm.gen.climate_biome(focus.x + o.x, focus.z + o.y), [0.0, false])
		n += 1.0 if info[1] else 0.0
	return n / 5.0
