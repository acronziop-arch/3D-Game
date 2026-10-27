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

## Vector2i(область) -> {"chunks": {Vector2i: Chunk}, "nodes": Array[MultiMeshInstance3D], "dirty": bool,
##   "ground": MeshInstance3D или null, "ground_dirty": bool — землю пересобрать после текущей сборки}
var _regions := {}
## false — землю областей собираем прямо в главном потоке (браузер без потоков).
var use_threads := true
## Земля областей, которая собирается в фоне: {"region", "r", "task", "out", "chunks"}.
var _ground_jobs: Array[Dictionary] = []


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
		_regions[r] = {"chunks": {}, "nodes": [], "dirty": false, "ground": null, "ground_dirty": false}
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
			_drop_region(r)


## Перестраивает до limit изменившихся областей и ставит готовую землю из фона.
## Возвращает, сколько областей перестроено.
func rebuild_dirty(limit: int) -> int:
	_poll_ground()
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
			_drop_region(r)
	return done


func _drop_region(r: Vector2i) -> void:
	var region: Dictionary = _regions[r]
	if is_instance_valid(region["ground"]):
		region["ground"].queue_free()
	_regions.erase(r)


func _exit_tree() -> void:
	for job in _ground_jobs:
		WorkerThreadPool.wait_for_task_completion(job["task"])
	_ground_jobs.clear()


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
	_start_ground(r, region)
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


# --- Земля области ---------------------------------------------------------------------------

## Земля области — одним мешем вместо шестнадцати. Собирается в фоновом потоке из копий
## вершин, которые чанки держат в памяти (читать их обратно из видеопамяти в браузере —
## долгая пауза). Пока новая земля не готова, видна прежняя или земля самих чанков:
## у них одинаковые вершины, так что подмена незаметна.
func _start_ground(r: Vector2i, region: Dictionary) -> void:
	for job in _ground_jobs:
		if is_same(job["region"], region):
			region["ground_dirty"] = true
			return
	var origin := Vector3(r.x, 0, r.y) * (REGION * WorldGen.CHUNK_SIZE)
	var parts := []
	var included: Array[Chunk] = []
	for c: Vector2i in region["chunks"]:
		var chunk: Chunk = region["chunks"][c]
		if is_instance_valid(chunk) and not chunk.terrain_arrays.is_empty():
			parts.append([chunk.terrain_arrays, chunk.position - origin])
			included.append(chunk)
	var out := {}
	if not use_threads or parts.is_empty():
		_merge_ground(parts, out)
		_finish_ground(r, region, out, included)
		return
	_ground_jobs.append({"region": region, "r": r, "out": out, "chunks": included,
		"task": WorkerThreadPool.add_task(_merge_ground.bind(parts, out))})


func _poll_ground() -> void:
	for i in range(_ground_jobs.size() - 1, -1, -1):
		var job: Dictionary = _ground_jobs[i]
		if not WorkerThreadPool.is_task_completed(job["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(job["task"])
		_ground_jobs.remove_at(i)
		var region: Dictionary = job["region"]
		var r: Vector2i = job["r"]
		# Область за это время могла опустеть и пропасть.
		if not is_same(_regions.get(r), region):
			continue
		_finish_ground(r, region, job["out"], job["chunks"])
		if region["ground_dirty"]:
			region["ground_dirty"] = false
			_start_ground(r, region)


func _finish_ground(r: Vector2i, region: Dictionary, out: Dictionary, included: Array[Chunk]) -> void:
	if is_instance_valid(region["ground"]):
		region["ground"].queue_free()
	region["ground"] = null
	if not out.has("arrays"):
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out["arrays"])
	mesh.surface_set_material(0, ModelLibrary.terrain_material())
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	# Так далеко тени уже не рисуются.
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position = Vector3(r.x, 0, r.y) * (REGION * WorldGen.CHUNK_SIZE)
	add_child(ground)
	region["ground"] = ground
	# Теперь землю рисует область — свою чанки прячут (не раньше: иначе мелькнёт дыра).
	for chunk in included:
		if is_instance_valid(chunk) and region["chunks"].get(chunk.coord) == chunk:
			chunk.set_terrain_in_region(true)


## Сшивает землю чанков в один набор массивов (работает в фоновом потоке).
static func _merge_ground(parts: Array, out: Dictionary) -> void:
	if parts.is_empty():
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part: Array in parts:
		var arrays: Array = part[0]
		var offset: Vector3 = part[1]
		var base := verts.size()
		verts.append_array(arrays[Mesh.ARRAY_VERTEX])
		for k in range(base, verts.size()):
			verts[k] = verts[k] + offset
		normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		colors.append_array(arrays[Mesh.ARRAY_COLOR])
		var first := indices.size()
		indices.append_array(arrays[Mesh.ARRAY_INDEX])
		for k in range(first, indices.size()):
			indices[k] += base
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	out["arrays"] = arrays
