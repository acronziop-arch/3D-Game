class_name Atmosphere
extends Node3D
## Всё, что видно от погоды и времени суток: солнце и луна, небо с облаками,
## туман, дождь, снег, молнии и глобальные параметры шейдеров (ветер, влага, снег,
## листва). Логика времени и погоды — в автозагрузке Weather.

const RAIN_LAYER := 4

@export var sun: DirectionalLight3D
@export var moon: DirectionalLight3D
@export var world_environment: WorldEnvironment

var camera_rig: CameraRig

var _sky_material: ShaderMaterial
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _rain_material: ParticleProcessMaterial
var _snow_material: ParticleProcessMaterial
var _cloud_offset := Vector2.ZERO
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
	Settings.changed.connect(func(key: String) -> void:
		if key == "shadows":
			sun.shadow_enabled = Settings.get_value("shadows"))
	sun.shadow_enabled = Settings.get_value("shadows")


func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 7000
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
	p.amount = 6000
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
	var far := lerpf(215.0, 80.0, Weather.fog) * (1.0 - Weather.rain * 0.25)
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
	_particles()

	RenderingServer.global_shader_parameter_set("wind_dir", Weather.wind_dir)
	RenderingServer.global_shader_parameter_set("wind_strength", Weather.wind)
	RenderingServer.global_shader_parameter_set("wetness", Weather.wetness)
	RenderingServer.global_shader_parameter_set("snow_cover", Weather.snow_cover)
	RenderingServer.global_shader_parameter_set("leaf_amount", Weather.leaf_amount())
	RenderingServer.global_shader_parameter_set("autumn", Weather.autumn_amount())
	RenderingServer.global_shader_parameter_set("spring", Weather.spring_amount())
	RenderingServer.global_shader_parameter_set("night", 1.0 - daylight)
	RenderingServer.global_shader_parameter_set("rain", Weather.rain)


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


func _particles() -> void:
	if camera_rig == null:
		return
	var focus := camera_rig.global_position
	var wind := Vector3(Weather.wind_dir.x, 0, Weather.wind_dir.y) * Weather.wind
	_rain.global_position = focus + Vector3(0, 26, 0) - wind * 8.0
	_snow.global_position = focus + Vector3(0, 14, 0) - wind * 10.0
	_rain.emitting = Weather.rain > 0.02
	_rain.amount_ratio = clampf(Weather.rain, 0.0, 1.0)
	_rain_material.direction = (Vector3(0, -1, 0) + wind * 0.35).normalized()
	_snow.emitting = Weather.snow > 0.02
	_snow.amount_ratio = clampf(Weather.snow, 0.0, 1.0)
	_snow_material.gravity = Vector3(0, -0.6, 0) + wind * 3.0
