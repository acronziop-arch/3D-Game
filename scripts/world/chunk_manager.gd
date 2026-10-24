class_name ChunkManager
extends Node3D
## Бесконечный мир: держит загруженными чанки вокруг камеры, новые генерирует
## в фоновых потоках (WorkerThreadPool), дальние выгружает. Здесь же —
## выравнивание рельефа (правки сохраняются в WorldState.terrain_edits).

signal initial_area_ready

@export var view_radius := 7
@export var max_tasks_in_flight := 4
## Сколько готовых чанков добавлять в сцену за кадр — чтобы не было рывков.
@export var finalize_per_frame := 2
@export var initial_radius := 3

var gen: WorldGen
var chunks := {}
## Позиция, вокруг которой грузится мир (её задаёт камера).
var focus := Vector3.ZERO

var _pending := {}
var _wanted: Array[Vector2i] = []
var _center := Vector2i(1 << 30, 1 << 30)
var _dirty := {}
var _rebuild_timer := 0.0
var _initial_done := false


func start(world_seed: int) -> void:
	gen = WorldGen.new(world_seed)


static func chunk_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / WorldGen.CHUNK_SIZE), floori(z / WorldGen.CHUNK_SIZE))


func _process(delta: float) -> void:
	if gen == null:
		return
	var center := chunk_of(focus.x, focus.z)
	if center != _center:
		_center = center
		_update_wanted()
	_dispatch()
	_finalize()
	_rebuild_timer -= delta
	if _rebuild_timer <= 0.0 and not _dirty.is_empty():
		_rebuild_timer = 0.06
		for c: Vector2i in _dirty:
			if chunks.has(c):
				chunks[c].rebuild_terrain()
		_dirty.clear()


func _update_wanted() -> void:
	_wanted.clear()
	var r2 := view_radius * view_radius
	for dz in range(-view_radius, view_radius + 1):
		for dx in range(-view_radius, view_radius + 1):
			if dx * dx + dz * dz <= r2:
				_wanted.append(_center + Vector2i(dx, dz))
	_wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - _center).length_squared() < (b - _center).length_squared())
	# Выгружаем то, что далеко ушло за радиус (с запасом, чтобы не мигало на границе).
	var keep2 := (view_radius + 2) * (view_radius + 2)
	for c: Vector2i in chunks.keys():
		if (c - _center).length_squared() > keep2:
			chunks[c].queue_free()
			chunks.erase(c)


func _dispatch() -> void:
	for c in _wanted:
		if _pending.size() >= max_tasks_in_flight:
			return
		if chunks.has(c) or _pending.has(c):
			continue
		var out := {}
		var edits := _edits_for_chunk(c)
		var task := WorkerThreadPool.add_task(gen.generate_chunk.bind(
			c, edits, WorldState.removed_in_chunk(c), WorldState.opened_chests.has(c), out))
		_pending[c] = {"task": task, "out": out}


func _finalize() -> void:
	var done := 0
	for c: Vector2i in _pending.keys():
		if done >= finalize_per_frame:
			break
		var job: Dictionary = _pending[c]
		if not WorkerThreadPool.is_task_completed(job["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(job["task"])
		_pending.erase(c)
		if (c - _center).length_squared() > (view_radius + 2) * (view_radius + 2):
			continue
		var chunk := Chunk.new()
		chunk.setup(c, job["out"])
		add_child(chunk)
		chunks[c] = chunk
		done += 1
	if not _initial_done and _initial_area_loaded():
		_initial_done = true
		initial_area_ready.emit()


func _initial_area_loaded() -> bool:
	for dz in range(-initial_radius, initial_radius + 1):
		for dx in range(-initial_radius, initial_radius + 1):
			if not chunks.has(_center + Vector2i(dx, dz)):
				return false
	return true


func _exit_tree() -> void:
	for c: Vector2i in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[c]["task"])
	_pending.clear()


func _edits_for_chunk(c: Vector2i) -> Dictionary:
	var result := {}
	if WorldState.terrain_edits.is_empty():
		return result
	for j in WorldGen.RES + 1:
		for i in WorldGen.RES + 1:
			var key := Vector2i(c.x * WorldGen.RES + i, c.y * WorldGen.RES + j)
			if WorldState.terrain_edits.has(key):
				result[key] = WorldState.terrain_edits[key]
	return result


# --- Запросы к миру --------------------------------------------------------------

func get_chunk_at(x: float, z: float) -> Chunk:
	return chunks.get(chunk_of(x, z))


func get_height(x: float, z: float) -> float:
	var chunk := get_chunk_at(x, z)
	if chunk:
		return chunk.height_local(x - chunk.position.x, z - chunk.position.z)
	return gen.height_at(x, z) if gen else 0.0


func get_biome_name(x: float, z: float) -> String:
	return gen.biome_name(gen.biome_at(x, z, get_height(x, z)))


## Точка, где луч встречает землю или воду (null — не встретил).
## Шаг подстраивается под высоту над землёй, в конце — уточнение делением пополам.
func raycast(from: Vector3, dir: Vector3, max_distance := 700.0) -> Variant:
	var t := 0.0
	var prev := 0.0
	while t < max_distance:
		var p := from + dir * t
		var surface := maxf(get_height(p.x, p.z), WorldGen.WATER_LEVEL)
		if p.y <= surface:
			var a := prev
			var b := t
			for i in 10:
				var m := (a + b) * 0.5
				var pm := from + dir * m
				if pm.y <= maxf(get_height(pm.x, pm.z), WorldGen.WATER_LEVEL):
					b = m
				else:
					a = m
			return from + dir * b
		prev = t
		t += clampf((p.y - surface) * 0.5, 0.2, 4.0)
	return null


## Ближайший добываемый объект или сундук под лучом мыши.
func pick(from: Vector3, dir: Vector3, max_t: float) -> Dictionary:
	var best := {}
	var to := from + dir * max_t
	var a := chunk_of(minf(from.x, to.x), minf(from.z, to.z))
	var b := chunk_of(maxf(from.x, to.x), maxf(from.z, to.z))
	for cz in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			var chunk: Chunk = chunks.get(Vector2i(cx, cz))
			if chunk == null:
				continue
			var hit := chunk.pick(from, dir)
			if not hit.is_empty() and hit["t"] < max_t and (best.is_empty() or hit["t"] < best["t"]):
				best = hit
	return best


func props_in_rect(rect: Rect2, harvestable_only: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for chunk in _chunks_in_rect(rect):
		for p in chunk.props_in_rect(rect, harvestable_only):
			p["chunk"] = chunk
			result.append(p)
	return result


func _chunks_in_rect(rect: Rect2) -> Array[Chunk]:
	var result: Array[Chunk] = []
	var a := chunk_of(rect.position.x, rect.position.y)
	var b := chunk_of(rect.end.x, rect.end.y)
	for cz in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			if chunks.has(Vector2i(cx, cz)):
				result.append(chunks[Vector2i(cx, cz)])
	return result


## Убирает траву и цветы под новым зданием.
func clear_decor(rect: Rect2) -> void:
	for p in props_in_rect(rect, false):
		if GameData.PROPS[p["id"]]["kind"] == "decor":
			p["chunk"].remove_prop(p)


func has_chest_in_rect(rect: Rect2) -> bool:
	for chunk in _chunks_in_rect(rect):
		if is_instance_valid(chunk.chest) and not chunk.chest.opened:
			var p := chunk.chest.global_position
			if rect.grow(0.6).has_point(Vector2(p.x, p.z)):
				return true
	return false


# --- Выравнивание рельефа -----------------------------------------------------------

func vertex_height(vx: int, vz: int) -> float:
	var key := Vector2i(vx, vz)
	if WorldState.terrain_edits.has(key):
		return WorldState.terrain_edits[key]
	var c := Vector2i(floori(float(vx) / WorldGen.RES), floori(float(vz) / WorldGen.RES))
	if chunks.has(c):
		return chunks[c].get_vertex_height(vx - c.x * WorldGen.RES, vz - c.y * WorldGen.RES)
	return gen.height_at(vx * WorldGen.CELL, vz * WorldGen.CELL)


func set_vertex_height(vx: int, vz: int, h: float) -> void:
	WorldState.terrain_edits[Vector2i(vx, vz)] = h
	# Вершина на границе принадлежит сразу нескольким чанкам.
	var cx := floori(float(vx) / WorldGen.RES)
	var cz := floori(float(vz) / WorldGen.RES)
	for oz in [0, -1]:
		for ox in [0, -1]:
			var c := Vector2i(cx + ox, cz + oz)
			var i := vx - c.x * WorldGen.RES
			var j := vz - c.y * WorldGen.RES
			if i > WorldGen.RES or j > WorldGen.RES:
				continue
			if chunks.has(c):
				chunks[c].set_vertex_height(i, j, h)
				_dirty[c] = true


## Плавно тянет вершины в круге к высоте target. step — метров за вызов.
func flatten(center: Vector3, radius: float, target: float, step: float) -> void:
	var c := WorldGen.CELL
	for vz in range(floori((center.z - radius) / c), ceili((center.z + radius) / c) + 1):
		for vx in range(floori((center.x - radius) / c), ceili((center.x + radius) / c) + 1):
			var d := Vector2(vx * c - center.x, vz * c - center.z).length()
			if d > radius:
				continue
			var weight := 1.0 - smoothstep(radius * 0.55, radius, d)
			var current := vertex_height(vx, vz)
			var next := move_toward(current, target, step * weight)
			if absf(next - current) > 0.001:
				set_vertex_height(vx, vz, next)
