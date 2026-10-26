class_name GroundCover
extends RefCounted
## Покров земли: густая низкая и высокая трава, цветы и опавшие листья. Это не
## отдельные объекты, а тысячи экземпляров MultiMesh на чанк: координаты считаются
## в рабочем потоке (WorldGen.generate_chunk) и сразу пишутся в буфер MultiMesh.
## Трава берёт цвет земли под собой, качается волнами ветра, желтеет осенью и
## прячется под снег. Цветам цвет лепестков задаёт экземпляр. Листьев на земле
## становится больше к концу осени.

## Floats на экземпляр в буфере MultiMesh: 12 — трансформация, 4 — цвет, 4 — свои данные.
const GRASS_STRIDE := 16
const LITTER_STRIDE := 20

## Цвета лепестков: поляна одного цвета смотрится естественнее пёстрой каши.
const FLOWER_COLORS := [Color(0.96, 0.33, 0.36), Color(0.99, 0.85, 0.3), Color(0.97, 0.97, 0.97),
	Color(0.68, 0.5, 0.96), Color(0.99, 0.58, 0.78), Color(0.35, 0.55, 0.98)]

static var _grass_mesh: ArrayMesh
static var _tall_mesh: ArrayMesh
static var _flower_mesh: ArrayMesh
static var _litter_mesh: ArrayMesh
static var _grass_material: ShaderMaterial
static var _flower_material: ShaderMaterial
static var _litter_material: ShaderMaterial


## Пучок из 14 изогнутых травинок. UV.y — доля высоты (0 у земли, 1 на кончике).
static func grass_mesh() -> ArrayMesh:
	if _grass_mesh:
		return _grass_mesh
	_grass_mesh = _blades(14, 0.46, Vector2(0.28, 0.66), 0.038, 7)
	return _grass_mesh


## Пучок изогнутых травинок: count штук в круге radius, высота heights.x..heights.y.
static func _blades(count: int, radius: float, heights: Vector2, width: float, seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for b in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var lean_dir := Vector3(cos(a + rng.randf_range(-0.6, 0.6)), 0.0, sin(a + rng.randf_range(-0.6, 0.6)))
		var h := rng.randf_range(heights.x, heights.y) * (1.0 - r * 0.5)
		var side := Vector3(-lean_dir.z, 0.0, lean_dir.x) * width * rng.randf_range(0.8, 1.2)
		var mid := base + lean_dir * h * 0.15 + Vector3(0, h * 0.55, 0)
		var tip := base + lean_dir * h * 0.42 + Vector3(0, h, 0)
		var pts := [base - side, base + side, mid + side * 0.7, mid - side * 0.7]
		var hs := [0.0, 0.0, 0.55, 0.55]
		for t: Array in [[0, 1, 2], [0, 2, 3]]:
			for idx: int in t:
				verts.append(pts[idx])
				uvs.append(Vector2(0.5, hs[idx]))
		for p: Vector3 in [mid - side * 0.7, mid + side * 0.7, tip]:
			verts.append(p)
		uvs.append_array([Vector2(0.5, 0.55), Vector2(0.5, 0.55), Vector2(0.5, 1.0)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-1.0, 0, -1.0), Vector3(2.0, heights.y + 0.3, 2.0))
	return mesh


## Высокая трава: длинные широкие стебли, у части — колоски на макушке.
static func tall_grass_mesh() -> ArrayMesh:
	if _tall_mesh:
		return _tall_mesh
	_tall_mesh = _blades(10, 0.42, Vector2(0.75, 1.3), 0.05, 13)
	return _tall_mesh


## Пучок цветов: стебли (UV.x = 0) и головки-«звёздочки» (UV.x = 1, цвет от экземпляра).
static func flower_mesh() -> ArrayMesh:
	if _flower_mesh:
		return _flower_mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for f in 6:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * 0.35
		var h := rng.randf_range(0.25, 0.5)
		var top := base + Vector3(rng.randf_range(-0.05, 0.05), h, rng.randf_range(-0.05, 0.05))
		var side := Vector3(0.018, 0, 0.0).rotated(Vector3.UP, a)
		for p: Vector3 in [base - side, base + side, top + side, base - side, top + side, top - side]:
			verts.append(p)
			uvs.append(Vector2(0.0, p.y / h))
		# Головка: пять лепестков веером.
		var r := rng.randf_range(0.07, 0.11)
		var spin := rng.randf() * TAU
		for k in 5:
			var a0 := spin + TAU * k / 5.0
			var tip := top + Vector3(cos(a0) * r, 0.025, sin(a0) * r)
			var l := top + Vector3(cos(a0 - 0.45) * r * 0.55, 0.012, sin(a0 - 0.45) * r * 0.55)
			var rr := top + Vector3(cos(a0 + 0.45) * r * 0.55, 0.012, sin(a0 + 0.45) * r * 0.55)
			for p: Vector3 in [top + Vector3(0, 0.02, 0), l, tip, top + Vector3(0, 0.02, 0), tip, rr]:
				verts.append(p)
				uvs.append(Vector2(1.0, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	_flower_mesh = ArrayMesh.new()
	_flower_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_flower_mesh.custom_aabb = AABB(Vector3(-0.6, 0, -0.6), Vector3(1.2, 0.7, 1.2))
	return _flower_mesh


## Россыпь из 18 листьев на земле: бурые, рыжие, жёлтые, красные.
static func litter_mesh() -> ArrayMesh:
	if _litter_mesh:
		return _litter_mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var palette := [Color(0.48, 0.32, 0.16), Color(0.86, 0.46, 0.12), Color(0.92, 0.72, 0.22),
		Color(0.72, 0.22, 0.1), Color(0.58, 0.5, 0.22), Color(0.66, 0.4, 0.18)]
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for l in 18:
		var c := Vector3(rng.randf_range(-1.1, 1.1), 0.0, rng.randf_range(-1.1, 1.1))
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var leaf_len := rng.randf_range(0.11, 0.19)
		var y := 0.02 + l * 0.002
		var tip := c + dir * leaf_len + Vector3(0, y + 0.02, 0)
		var tail := c - dir * leaf_len + Vector3(0, y, 0)
		var l1 := c + side * leaf_len * 0.45 + Vector3(0, y + 0.01, 0)
		var r1 := c - side * leaf_len * 0.45 + Vector3(0, y + 0.01, 0)
		var col: Color = palette[rng.randi() % palette.size()]
		col = col.lightened(rng.randf_range(-0.08, 0.08))
		verts.append_array([tail, l1, tip, tail, tip, r1])
		for i in 6:
			colors.append(col)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	_litter_mesh = ArrayMesh.new()
	_litter_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _litter_mesh


## fade_end — дальность, м, на которой пучки травы уходят в землю (на телефоне ближе).
static func grass_material(fade_end: float) -> ShaderMaterial:
	if _grass_material == null:
		_grass_material = ShaderMaterial.new()
		_grass_material.shader = load("res://shaders/grass.gdshader")
	_grass_material.set_shader_parameter("fade_end", fade_end)
	return _grass_material


static func flower_material(fade_end: float) -> ShaderMaterial:
	if _flower_material == null:
		_flower_material = ShaderMaterial.new()
		_flower_material.shader = load("res://shaders/grass.gdshader")
		_flower_material.set_shader_parameter("flower", 1.0)
	_flower_material.set_shader_parameter("fade_end", fade_end)
	return _flower_material


static func litter_material(fade_end: float) -> ShaderMaterial:
	if _litter_material == null:
		_litter_material = ShaderMaterial.new()
		_litter_material.shader = load("res://shaders/litter.gdshader")
	_litter_material.set_shader_parameter("fade_end", fade_end)
	return _litter_material


## Записывает экземпляр (поворот вокруг Y + масштаб) в буфер MultiMesh.
static func write_instance(buffer: PackedFloat32Array, pos: Vector3, angle: float, scale: float, color: Color, custom := -1.0) -> void:
	var c := cos(angle) * scale
	var s := sin(angle) * scale
	buffer.append_array([c, 0.0, s, pos.x, 0.0, scale, 0.0, pos.y, -s, 0.0, c, pos.z, color.r, color.g, color.b, 1.0])
	if custom >= 0.0:
		buffer.append_array([custom, 0.0, 0.0, 0.0])


## Прячет экземпляры, чьи основания попали в прямоугольник (локальные XZ чанка).
static func hide_in_rect(buffer: PackedFloat32Array, stride: int, rect: Rect2) -> bool:
	var changed := false
	for i in range(0, buffer.size(), stride):
		if rect.has_point(Vector2(buffer[i + 3], buffer[i + 11])) and buffer[i + 5] != 0.0:
			for k in [0, 2, 5, 8, 10]:
				buffer[i + k] = 0.0
			changed = true
	return changed


## Прячет экземпляры, чьи основания попали в клетки 1×1 м (мировые координаты;
## origin — положение чанка). Нужно для дорожек произвольной формы.
static func hide_in_cells(buffer: PackedFloat32Array, stride: int, cells: Dictionary, origin: Vector2) -> bool:
	var changed := false
	for i in range(0, buffer.size(), stride):
		if buffer[i + 5] == 0.0:
			continue
		if cells.has(Vector2i(floori(buffer[i + 3] + origin.x), floori(buffer[i + 11] + origin.y))):
			for k in [0, 2, 5, 8, 10]:
				buffer[i + k] = 0.0
			changed = true
	return changed


## Ставит экземпляры на новую высоту земли после выравнивания.
static func refit_heights(buffer: PackedFloat32Array, stride: int, height: Callable) -> void:
	for i in range(0, buffer.size(), stride):
		buffer[i + 7] = height.call(buffer[i + 3], buffer[i + 11])
