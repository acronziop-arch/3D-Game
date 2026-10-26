class_name Thumbnails
extends Node
## Миниатюры зданий для меню стройки. Готовые снимки лежат в assets/thumbs
## (их делает tools/bake_thumbnails.gd). Если снимка нет — здание фотографируется
## прямо в игре в отдельном маленьком мире (свой свет, прозрачный фон),
## по одному зданию за кадр, чтобы не было подтормаживаний.

signal thumbnail_ready(building_id: String, texture: Texture2D)

const SIZE := Vector2i(192, 144)
const BAKED_DIR := "res://assets/thumbs/"

var textures := {}
## Размер снимка (инструмент запекания снимает крупнее).
var size := SIZE
var _queue: Array[String] = []
var _viewport: SubViewport
var _camera: Camera3D
var _pivot: Node3D
var _current := ""
var _wait := 0


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = size
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.82, 0.84, 0.88)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.96, 0.9)
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)


## Готовая миниатюра здания или fallback, пока её нет.
func texture_for(id: String, fallback: Texture2D) -> Texture2D:
	if not textures.has(id):
		var path := BAKED_DIR + id + ".png"
		if ResourceLoader.exists(path):
			textures[id] = load(path)
	return textures.get(id, fallback)


## force — снять заново, даже если готовый снимок есть (tools/bake_thumbnails.gd).
func request(ids: Array, force := false) -> void:
	# Без видеокарты (запуск --headless) фотографировать нечем.
	if DisplayServer.get_name() == "headless":
		return
	for id: String in ids:
		if (force or texture_for(id, null) == null) and not _queue.has(id):
			_queue.append(id)


## Есть ли ещё здания в очереди на снимок.
func is_busy() -> bool:
	return _current != "" or not _queue.is_empty()


func _process(_delta: float) -> void:
	if _current != "":
		_wait -= 1
		if _wait > 0:
			return
		var img := _viewport.get_texture().get_image()
		# Без видеокарты (запуск --headless) снимка нет — остаётся иконка категории.
		if img != null and not img.is_empty():
			var tex := ImageTexture.create_from_image(img)
			textures[_current] = tex
			thumbnail_ready.emit(_current, tex)
		for c in _pivot.get_children():
			c.queue_free()
		_current = ""
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _queue.is_empty():
		return
	_current = _queue.pop_front()
	var data := ModelLibrary.building(_current)
	var mi := MeshInstance3D.new()
	mi.mesh = data["mesh"]
	if data.has("plant"):
		mi.material_override = ModelLibrary.foliage_material()
	else:
		ModelLibrary.apply_building_materials(mi)
	_pivot.add_child(mi)
	if data["rotor_mesh"]:
		var rotor := MeshInstance3D.new()
		rotor.mesh = data["rotor_mesh"]
		rotor.position = data["pivot"]
		ModelLibrary.apply_building_materials(rotor)
		_pivot.add_child(rotor)
	var box: AABB = data["bounds"]
	# Подземный цоколь в кадр не берём.
	box = AABB(Vector3(box.position.x, maxf(box.position.y, -0.2), box.position.z),
		Vector3(box.size.x, box.end.y - maxf(box.position.y, -0.2), box.size.z))
	var center := box.get_center()
	var radius := box.size.length() * 0.5
	var dir := Vector3(0.85, 0.62, 1.0).normalized()
	_camera.position = center + dir * radius / tan(deg_to_rad(_camera.fov * 0.5)) * 0.95
	_camera.look_at(center)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_wait = 2
