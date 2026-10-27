class_name FarForest
extends Node3D
## Земля, деревья, камни и руины далёких чанков. Вблизи у каждого чанка свои объекты
## (по одному на вид и вариант модели), а издалека всё это — сотни отдельных
## вызовов отрисовки. Здесь далёкие чанки собраны в области REGION × REGION чанков,
## и в каждой области один объект на вид дерева или камня. Для браузера на телефоне
## это заметно разгружает процессор: вызовов отрисовки становится в разы меньше.

## Сторона области в чанках.
const REGION := 4
## Чисел на экземпляр в буфере MultiMesh: 12 — трансформация, 4 — цвет.
const STRIDE := 16

## Vector2i(область) -> {"chunks": {Vector2i: Chunk}, "nodes": Array[MultiMeshInstance3D], "dirty": bool}
var _regions := {}


## Дописывает экземпляр в буфер {"buf", "n"} (без временных массивов — так быстрее).
static func put(entry: Dictionary, xf: Transform3D, color: Color) -> void:
	var buf: PackedFloat32Array = entry["buf"]
	var o: int = entry["n"] * STRIDE
	if o + STRIDE > buf.size():
		buf.resize(maxi(buf.size() * 2, STRIDE * 64))
	var b := xf.basis
	buf[o] = b.x.x
	buf[o + 1] = b.y.x
	buf[o + 2] = b.z.x
	buf[o + 3] = xf.origin.x
	buf[o + 4] = b.x.y
	buf[o + 5] = b.y.y
	buf[o + 6] = b.z.y
	buf[o + 7] = xf.origin.y
	buf[o + 8] = b.x.z
	buf[o + 9] = b.y.z
	buf[o + 10] = b.z.z
	buf[o + 11] = xf.origin.z
	buf[o + 12] = color.r
	buf[o + 13] = color.g
	buf[o + 14] = color.b
	buf[o + 15] = color.a
	entry["n"] = entry["n"] + 1


static func region_of(c: Vector2i) -> Vector2i:
	return Vector2i(floori(float(c.x) / REGION), floori(float(c.y) / REGION))


## Чанк ушёл далеко (его объекты рисует область) или вернулся / выгрузился (remove).
func add_chunk(chunk: Chunk) -> void:
	var r := region_of(chunk.coord)
	if not _regions.has(r):
		_regions[r] = {"chunks": {}, "nodes": [], "dirty": false}
	_regions[r]["chunks"][chunk.coord] = chunk
	_regions[r]["dirty"] = true


func remove_chunk(coord: Vector2i) -> void:
	var r := region_of(coord)
	if _regions.has(r) and _regions[r]["chunks"].has(coord):
		_regions[r]["chunks"].erase(coord)
		_regions[r]["dirty"] = true


## Объекты далёкого чанка изменились (срубили дерево, выровняли землю).
func mark_dirty(coord: Vector2i) -> void:
	var r := region_of(coord)
	if _regions.has(r):
		_regions[r]["dirty"] = true


func is_dirty(coord: Vector2i) -> bool:
	var r := region_of(coord)
	return _regions.has(r) and _regions[r]["dirty"]


## Сразу перестраивает область чанка (если она изменилась) — когда чанк только что
## отдал ей свои объекты, чтобы деревья не пропали ни на кадр.
func rebuild_now(coord: Vector2i) -> void:
	var r := region_of(coord)
	if _regions.has(r) and _regions[r]["dirty"]:
		_rebuild(r, _regions[r])
		if _regions[r]["chunks"].is_empty():
			_regions.erase(r)


## Перестраивает до limit изменившихся областей. Возвращает, сколько перестроено.
func rebuild_dirty(limit: int) -> int:
	var done := 0
	for r: Vector2i in _regions.keys():
		if done >= limit:
			break
		var region: Dictionary = _regions[r]
		if not region["dirty"]:
			continue
		_rebuild(r, region)
		done += 1
		if region["chunks"].is_empty():
			_regions.erase(r)
	return done


func _rebuild(r: Vector2i, region: Dictionary) -> void:
	region["dirty"] = false
	for n: Node in region["nodes"]:
		n.queue_free()
	region["nodes"] = []
	var origin := Vector3(r.x, 0, r.y) * (REGION * WorldGen.CHUNK_SIZE)
	var by_id := {}
	for c: Vector2i in region["chunks"].keys():
		var chunk: Chunk = region["chunks"][c]
		if not is_instance_valid(chunk):
			region["chunks"].erase(c)
			continue
		chunk.collect_far_props(by_id, origin)
	# Земля области — одним мешем вместо шестнадцати.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_ground := false
	for c: Vector2i in region["chunks"]:
		var chunk: Chunk = region["chunks"][c]
		var mesh := chunk.terrain_mesh()
		if mesh:
			st.append_from(mesh, 0, Transform3D(Basis.IDENTITY, chunk.position - origin))
			has_ground = true
	if has_ground:
		var ground := MeshInstance3D.new()
		ground.mesh = st.commit()
		ground.mesh.surface_set_material(0, ModelLibrary.terrain_material())
		# Так далеко тени уже не рисуются.
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ground.position = origin
		add_child(ground)
		region["nodes"].append(ground)
		# Теперь землю рисует область — свою чанки прячут (не раньше: иначе мелькнёт дыра).
		for c: Vector2i in region["chunks"]:
			(region["chunks"][c] as Chunk).set_terrain_in_region(true)
	for key: String in by_id:
		var entry: Dictionary = by_id[key]
		var parts := key.split(":")
		var buf: PackedFloat32Array = entry["buf"]
		buf.resize(int(entry["n"]) * STRIDE)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = ModelLibrary.prop_mesh(parts[0], int(parts[1]))
		mm.instance_count = entry["n"]
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = ModelLibrary.foliage_material()
		# Так далеко тени уже не рисуются.
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.position = origin
		add_child(mmi)
		region["nodes"].append(mmi)
