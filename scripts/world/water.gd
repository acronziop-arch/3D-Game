class_name Water
extends MeshInstance3D
## Водная гладь: одна большая плоскость, которая едет за камерой, и камера
## отражений. Камера отражений — зеркальная копия игровой камеры под водой;
## её снимок шейдер воды накладывает как отражение. Всё, что ниже воды, шейдеры
## мира для неё не рисуют (clip_for_reflection), поэтому дно не мешает.
##
## Карта течения: каждый загруженный чанк кладёт свой кусочек (WorldGen.flow_block)
## в общую закольцованную текстуру FLOW_SIZE × FLOW_SIZE клеток по 4 м — шейдер
## читает её по мировым координатам, поэтому сдвигать её за камерой не нужно.

const WATER_LAYER := 2
const FLOW_SIZE := 256
## Отражение рисуется, если вода ближе этого к точке взгляда, м.
const REFLECT_DISTANCE := 190.0
## Дальше этого в воде ничего не отражается (дальше и рябь всё смазывает), м.
const REFLECT_FAR := 220.0

var camera_rig: CameraRig
var chunk_manager: ChunkManager

var _viewport: SubViewport
var _camera: Camera3D
var _material: ShaderMaterial
var _flow_img: Image
var _flow_tex: ImageTexture
var _flow_dirty := false
var _water_near := true
var _near_timer := 0.0


func _ready() -> void:
	# Камера отражений ставится после того, как игровая камера сдвинулась в этом
	# кадре, — иначе отражение отстаёт на кадр и «прыгает» при быстром движении.
	process_priority = 100
	layers = WATER_LAYER
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	plane.subdivide_width = 149
	plane.subdivide_depth = 149
	mesh = plane
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/water.gdshader")
	_material.set_shader_parameter("ripple_a", _noise_texture(0.035, 3, 7.0, 11))
	_material.set_shader_parameter("ripple_b", _noise_texture(0.06, 2, 4.0, 23))
	var caustic := FastNoiseLite.new()
	caustic.noise_type = FastNoiseLite.TYPE_CELLULAR
	caustic.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	caustic.frequency = 0.03
	caustic.fractal_type = FastNoiseLite.FRACTAL_NONE
	var caustic_tex := NoiseTexture2D.new()
	caustic_tex.width = 256
	caustic_tex.height = 256
	caustic_tex.seamless = true
	caustic_tex.noise = caustic
	_material.set_shader_parameter("caustic_tex", caustic_tex)
	material_override = _material
	_flow_img = Image.create(FLOW_SIZE, FLOW_SIZE, false, Image.FORMAT_RGBA8)
	_flow_img.fill(Color(0.5, 0.5, 1.0, 0.0))
	_flow_tex = ImageTexture.create_from_image(_flow_img)
	_material.set_shader_parameter("flow_map", _flow_tex)
	_material.set_shader_parameter("flow_world_size", FLOW_SIZE * WorldGen.CHUNK_SIZE / WorldGen.FLOW_RES)

	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.mesh_lod_threshold = 4.0
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.cull_mask = 0xFFFFF & ~WATER_LAYER & ~Atmosphere.RAIN_LAYER & ~Chunk.DETAIL_LAYER
	_viewport.add_child(_camera)
	_material.set_shader_parameter("reflection_tex", _viewport.get_texture())
	Settings.changed.connect(func(_key: String) -> void: _apply_settings())
	_apply_settings()


static func _noise_texture(frequency: float, octaves: int, bump: float, seed_value: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.seed = seed_value
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = bump
	tex.noise = noise
	return tex


func _apply_settings() -> void:
	_set_reflection(Settings.get_value("reflections") and _water_near)


## Отражение рисуется, только если включено и вода рядом (иначе это лишняя
## перерисовка всего мира каждый кадр).
func _set_reflection(on: bool) -> void:
	var mode := SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if _viewport.render_target_update_mode != mode:
		_viewport.render_target_update_mode = mode
		_material.set_shader_parameter("reflection_enabled", 1.0 if on else 0.0)


## Есть ли вода в загруженных чанках недалеко от камеры (раз в полсекунды).
func _check_water_near() -> void:
	var near := false
	if chunk_manager:
		var focus := Vector2(camera_rig.position.x, camera_rig.position.z)
		for chunk: Chunk in chunk_manager.chunks.values():
			if chunk.has_water and Vector2(chunk.position.x + WorldGen.CHUNK_SIZE * 0.5,
					chunk.position.z + WorldGen.CHUNK_SIZE * 0.5).distance_to(focus) < REFLECT_DISTANCE:
				near = true
				break
	if near != _water_near:
		_water_near = near
		_apply_settings()


## Чанк загрузился: его кусочек карты течения — в общую текстуру.
func write_flow(chunk: Chunk) -> void:
	if chunk.flow.is_empty():
		return
	var n := WorldGen.FLOW_RES
	var block := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, chunk.flow)
	_flow_img.blit_rect(block, Rect2i(0, 0, n, n), Vector2i(posmod(chunk.coord.x * n, FLOW_SIZE), posmod(chunk.coord.y * n, FLOW_SIZE)))
	_flow_dirty = true


func _process(delta: float) -> void:
	if _flow_dirty:
		_flow_dirty = false
		_flow_tex.update(_flow_img)
	if camera_rig == null:
		return
	_near_timer -= delta
	if _near_timer <= 0.0:
		_near_timer = 0.5
		_check_water_near()
	var main_cam := camera_rig.camera
	# Вершины плоскости лежат на сетке 6 м — двигаем её с тем же шагом, чтобы волны не «плыли».
	global_position = Vector3(snappedf(main_cam.global_position.x, 6.0), WorldGen.WATER_LEVEL, snappedf(main_cam.global_position.z, 6.0))
	if _viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED:
		return
	# Размер окна в пикселях (интерфейс может быть растянут, а отражению важны пиксели).
	# На телефоне с плотным экраном пикселей втрое больше, чем точек, — для ряби на
	# воде столько не нужно: ширина отражения ограничена.
	var size := Vector2(get_tree().root.size) * Platform.reflection_scale()
	var cap := 640.0 if Platform.is_mobile() else 1280.0
	if size.x > cap:
		size *= cap / size.x
	var target := Vector2i(maxi(64, int(size.x)), maxi(64, int(size.y)))
	if _viewport.size != target:
		_viewport.size = target
	_camera.fov = main_cam.fov
	_camera.near = main_cam.near
	_camera.far = REFLECT_FAR
	# Зеркалим камеру относительно плоскости воды; ось Y камеры переворачиваем,
	# чтобы базис остался правым — поэтому шейдер читает снимок с перевёрнутой V.
	var t := main_cam.global_transform
	var flip := Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1))
	var b := flip * t.basis * flip
	var o := t.origin
	o.y = 2.0 * WorldGen.WATER_LEVEL - o.y
	_camera.global_transform = Transform3D(b, o)
