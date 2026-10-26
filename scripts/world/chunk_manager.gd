class_name ChunkManager
extends Node3D
## Бесконечный мир: держит загруженными чанки вокруг камеры, новые генерирует
## в фоновых потоках (WorkerThreadPool), дальние выгружает. Здесь же —
## выравнивание рельефа (правки сохраняются в WorldState.terrain_edits).

signal initial_area_ready
## Новый чанк добавлен в сцену (здания убирают под собой траву).
signal chunk_loaded(chunk: Chunk)

@export var view_radius := 7
@export var max_tasks_in_flight := 4
## Сколько готовых чанков добавлять в сцену за кадр — чтобы не было рывков.
@export var finalize_per_frame := 2
@export var initial_radius := 3
## false — чанки генерируются прямо в главном потоке (браузер без потоков).
var use_threads := true
## false — мир пока не строится (идёт подготовка графики при запуске).
var running := true
## Чанки, которым ещё нужно пересеять траву (см. refresh_all_cover).
var _cover_queue: Array = []
## Чанки, где меняли рельеф: после мазка объекты и трава в них проверяются заново.
var _content_dirty := {}
var _content_queue: Array = []

var gen: WorldGen
var chunks := {}
## Проверки зданий (их задаёт main.gd): убрать траву под зданиями чанка
## и узнать, стоит ли здание в точке.
var building_hook: Callable = func(_chunk: Chunk) -> void: pass
var blocked_by_building: Callable = func(_p: Vector2) -> bool: return false
## Позиция, вокруг которой грузится мир (её задаёт камера).
var focus := Vector3.ZERO

var _pending := {}
var _wanted: Array[Vector2i] = []
var _center := Vector2i(1 << 30, 1 << 30)
var _dirty := {}
var _rebuild_timer := 0.0
var _initial_done := false


## Стартовая область мира загружена.
func is_ready() -> bool:
	return _initial_done


func start(world_seed: int) -> void:
	gen = WorldGen.new(world_seed)


func set_view_radius(radius: int) -> void:
	view_radius = radius
	_center = Vector2i(1 << 30, 1 << 30)


static func chunk_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / WorldGen.CHUNK_SIZE), floori(z / WorldGen.CHUNK_SIZE))


func _process(delta: float) -> void:
	if gen == null or not running:
		return
	var center := chunk_of(focus.x, focus.z)
	if center != _center:
		_center = center
		_update_wanted()
	_dispatch()
	_finalize()
	# Новая густота травы: перестраиваем покров по чанку за кадр, ближние — первыми.
	if not _cover_queue.is_empty():
		_refresh_cover(_cover_queue.pop_front())
	elif not _content_queue.is_empty() and _dirty.is_empty():
		_refresh_content(_content_queue.pop_front())
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
		var args := [c, _edits_for_chunk(c), WorldState.removed_in_chunk(c), WorldState.opened_chests.has(c), out,
			cover_density(), _extra_for_chunk(c)]
		if use_threads:
			_pending[c] = {"task": WorkerThreadPool.add_task(gen.generate_chunk.bindv(args)), "out": out}
		else:
			gen.generate_chunk.callv(args)
			_pending[c] = {"task": -1, "out": out}


func _finalize() -> void:
	var done := 0
	for c: Vector2i in _pending.keys():
		if done >= finalize_per_frame:
			break
		var job: Dictionary = _pending[c]
		if job["task"] >= 0:
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
		chunk_loaded.emit(chunk)
		done += 1
	if not _initial_done and _initial_area_loaded():
		_initial_done = true
		initial_area_ready.emit()


## Доля стартового круга, которая уже загружена (для экрана загрузки).
func initial_progress() -> float:
	var r := mini(initial_radius, view_radius)
	var total := 0
	var have := 0
	var center := chunk_of(focus.x, focus.z)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz <= r * r:
				total += 1
				if chunks.has(center + Vector2i(dx, dz)):
					have += 1
	return float(have) / maxf(total, 1)


## Стартовый круг загружен. Он не больше круга прорисовки: чанки за ним не грузятся,
## и при малой дальности ожидание угловых чанков квадрата не закончилось бы никогда.
func _initial_area_loaded() -> bool:
	var r := mini(initial_radius, view_radius)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz <= r * r and not chunks.has(_center + Vector2i(dx, dz)):
				return false
	return true


func _exit_tree() -> void:
	for c: Vector2i in _pending:
		if _pending[c]["task"] >= 0:
			WorkerThreadPool.wait_for_task_completion(_pending[c]["task"])
	_pending.clear()


## Густота травы 0..1: настройка игрока с поправкой качества графики.
func cover_density() -> float:
	return float(Settings.get_value("grass"))


func _extra_for_chunk(c: Vector2i) -> Dictionary:
	return {"cover": WorldState.cover_edits_for_chunk(c), "planted": WorldState.planted_in_chunk(c),
		"keep_cleared": bool(Settings.get_value("keep_cleared"))}


func _edits_for_chunk(c: Vector2i) -> Dictionary:
	var result := {}
	if WorldState.terrain_edits.is_empty():
		return result
	for j in range(-1, WorldGen.RES + 2):
		for i in range(-1, WorldGen.RES + 2):
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
	if gen.ruin_near(x, z):
		return "Руины"
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
## slack — запас радиуса, м (палец на телефоне менее точен, чем курсор).
func pick(from: Vector3, dir: Vector3, max_t: float, slack := 0.0) -> Dictionary:
	var best := {}
	var to := from + dir * max_t
	var a := chunk_of(minf(from.x, to.x), minf(from.z, to.z))
	var b := chunk_of(maxf(from.x, to.x), maxf(from.z, to.z))
	for cz in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			var chunk: Chunk = chunks.get(Vector2i(cx, cz))
			if chunk == null:
				continue
			var hit := chunk.pick(from, dir, slack)
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


## Убирает траву, цветы, кусты и опавшие листья под новым зданием.
func clear_decor(rect: Rect2) -> void:
	for p in props_in_rect(rect, false):
		if not GameData.blocks_building(p["id"]):
			p["chunk"].remove_prop(p)
	for chunk in _chunks_in_rect(rect):
		chunk.clear_cover(rect)


# --- Природа: покос, посев, посадка деревьев ----------------------------------------

## Косит или сеет траву в круге: mode — "mow", "grass", "tall", "flowers".
func paint_cover(center: Vector3, radius: float, mode: String) -> void:
	var touched := {}
	var r := maxf(radius, 1.0)
	for cz in range(floori((center.z - r) / 2.0), floori((center.z + r) / 2.0) + 1):
		for cx in range(floori((center.x - r) / 2.0), floori((center.x + r) / 2.0) + 1):
			var cell_center := Vector2(cx * 2.0 + 1.0, cz * 2.0 + 1.0)
			if cell_center.distance_to(Vector2(center.x, center.z)) > r + 0.5:
				continue
			var cell := Vector2i(cx, cz)
			if WorldState.cover_edits.get(cell, "") == mode:
				continue
			WorldState.cover_edits[cell] = mode
			touched[chunk_of(cell_center.x, cell_center.y)] = true
	for c: Vector2i in touched:
		_refresh_cover(c)


func _refresh_cover(c: Vector2i) -> void:
	var chunk: Chunk = chunks.get(c)
	if chunk == null:
		return
	var edits := _edits_for_chunk(c)
	var out := {}
	gen._scatter_cover(c, chunk.heights, chunk.colors, cover_density(), out, WorldState.cover_edits_for_chunk(c),
		edits if Settings.get_value("keep_cleared") else {})
	chunk.rebuild_cover(out)
	building_hook.call(chunk)


## Можно ли посадить здесь дерево: пустая строка — можно; иначе причина.
func can_plant_tree(pos: Vector3) -> String:
	if get_height(pos.x, pos.z) < WorldGen.WATER_LEVEL + 0.3:
		return "Дерево не растёт в воде"
	if not chunks.has(chunk_of(pos.x, pos.z)):
		return "Слишком далеко"
	if not props_in_rect(Rect2(pos.x - 1.6, pos.z - 1.6, 3.2, 3.2), true).filter(
			func(p: Dictionary) -> bool: return GameData.blocks_building(p["id"])).is_empty():
		return "Слишком близко к другому дереву или камню"
	if blocked_by_building.call(Vector2(pos.x, pos.z)):
		return "Здесь стоит здание"
	return ""


## Сажает дерево. Пустая строка — посажено; иначе причина, почему нельзя.
func plant_tree(pos: Vector3, id: String) -> String:
	var reason := can_plant_tree(pos)
	if reason != "":
		return reason
	var h := get_height(pos.x, pos.z)
	var c := chunk_of(pos.x, pos.z)
	var chunk: Chunk = chunks[c]
	var list: Array = WorldState.planted.get(c, [])
	var entry := {"id": id, "x": pos.x - chunk.position.x, "z": pos.z - chunk.position.z,
		"rot": randf() * TAU, "scale": randf_range(0.85, 1.15), "t": Time.get_unix_time_from_system()}
	list.append(entry)
	WorldState.planted[c] = list
	var variants: int = PropFactory.VARIANTS.get(id, 1)
	chunk.add_planted({"id": id, "index": WorldGen.PLANTED_INDEX + list.size() - 1,
		"pos": Vector3(entry["x"], h, entry["z"]), "rot": entry["rot"], "scale": entry["scale"],
		"variant": (list.size() - 1) % variants, "float": false, "planted_at": entry["t"]})
	return ""


## Пересоздаёт все чанки (например, после смены густоты травы).
## Мазок выравнивания закончен: объекты и трава в изменённых чанках — заново по
## правилам мира. Под водой ничего не растёт, на новых горах — только горное,
## а на выровненной земле (если так в настройках) — пусто.
func commit_terrain_edits() -> void:
	for c: Vector2i in _content_dirty:
		if not _content_queue.has(c):
			_content_queue.append(c)
	_content_dirty.clear()


func _refresh_content(c: Vector2i) -> void:
	var chunk: Chunk = chunks.get(c)
	if chunk == null:
		return
	var out := {}
	gen.generate_chunk(c, _edits_for_chunk(c), WorldState.removed_in_chunk(c), WorldState.opened_chests.has(c), out,
		cover_density(), _extra_for_chunk(c))
	chunk.replace_content(out)
	# Карта и всё, что лежит на земле (здания, дорожки), узнают о новом рельефе.
	WorldState.explored.erase(c)
	chunk_loaded.emit(chunk)


## Пересеять траву во всех чанках (сменилась густота). Мир при этом не пропадает.
func refresh_all_cover() -> void:
	_cover_queue = chunks.keys()
	_cover_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - _center).length_squared() < (b - _center).length_squared())


## Сменилась дальность травы: шейдеры и границы видимости.
func apply_cover_distance() -> void:
	var far := float(Settings.get_value("grass_distance"))
	GroundCover.grass_material(far)
	GroundCover.flower_material(far)
	GroundCover.litter_material(far * 1.15)
	for c: Vector2i in chunks:
		chunks[c].refit_cover_distance(far)


func reload_all() -> void:
	for c: Vector2i in chunks:
		chunks[c].queue_free()
	chunks.clear()
	_center = Vector2i(1 << 30, 1 << 30)


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
	# Вершина хранится и в соседних чанках (в их запасе по краю).
	var cx := floori(float(vx) / WorldGen.RES)
	var cz := floori(float(vz) / WorldGen.RES)
	for oz in [-1, 0, 1]:
		for ox in [-1, 0, 1]:
			var c := Vector2i(cx + ox, cz + oz)
			var i := vx - c.x * WorldGen.RES
			var j := vz - c.y * WorldGen.RES
			if i < -1 or j < -1 or i > WorldGen.RES + 1 or j > WorldGen.RES + 1:
				continue
			if chunks.has(c):
				chunks[c].set_vertex_height(i, j, h)
				_dirty[c] = true
				_content_dirty[c] = true


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
