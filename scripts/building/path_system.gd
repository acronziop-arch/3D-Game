class_name PathSystem
extends Node3D
## Плавные дорожки: игрок ведёт пальцем (или мышью) из любого места, и за ним
## ложится ровная лента — не из плиток. Линия сглаживается, лента повторяет
## рельеф, концы скруглены, узор рисует шейдер path.gdshader. Трава под дорожкой
## убирается. Дорожки хранятся в WorldState.paths:
##   {"type": "dirt" | "wood" | "stone" | "brick", "points": PackedVector2Array, "width": float}

const WIDTH := 1.6
## Шаг записи точек за пальцем и шаг ленты, м.
const RECORD_STEP := 0.6
const MESH_STEP := 0.35
const LIFT := 0.045
const KINDS := {"dirt": 0, "wood": 1, "stone": 2, "brick": 3}
## Сколько метров дорожки даёт одна «плитка» стоимости.
const METERS_PER_COST := 2.0

var chunk_manager: ChunkManager

var _meshes: Array[MeshInstance3D] = []
var _materials := {}
## Рисуемая сейчас дорожка.
var _drawing := false
var _type := "dirt"
var _points := PackedVector2Array()
var _preview: MeshInstance3D
var _paid_meters := 0.0
var _length := 0.0
var _selected := -1


## Стоимость участка дорожки (как у плитки того же вида).
static func cost_of(path_type: String) -> Dictionary:
	return GameData.BUILDINGS["path_" + path_type]["cost"]


func material_for(path_type: String) -> ShaderMaterial:
	if not _materials.has(path_type):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/path.gdshader")
		m.set_shader_parameter("kind", KINDS.get(path_type, 0))
		m.set_shader_parameter("width", WIDTH)
		_materials[path_type] = m
	return _materials[path_type]


# --- Рисование ------------------------------------------------------------------------------

func is_drawing() -> bool:
	return _drawing


## Начать дорожку в точке земли. Пустая строка — начали; иначе причина.
func begin(path_type: String, at: Vector3) -> String:
	finish()
	if at.y < WorldGen.WATER_LEVEL + 0.1:
		return "Дорожку не проложить по воде"
	_type = path_type
	_drawing = true
	_points = PackedVector2Array([Vector2(at.x, at.z)])
	_length = 0.0
	_paid_meters = 0.0
	_preview = MeshInstance3D.new()
	_preview.material_override = material_for(_type)
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_preview)
	return ""


## Палец ушёл дальше: добавляем точки. Пустая строка — всё хорошо; иначе причина остановки.
func extend(at: Vector3) -> String:
	if not _drawing:
		return ""
	var p := Vector2(at.x, at.z)
	var last := _points[_points.size() - 1]
	var dist := last.distance_to(p)
	if dist < RECORD_STEP:
		return ""
	# Быстрый взмах — дописываем промежуточные точки, чтобы лента была ровной.
	var steps := ceili(dist / RECORD_STEP)
	for i in range(1, steps + 1):
		var q := last.lerp(p, float(i) / steps)
		if chunk_manager.get_height(q.x, q.y) < WorldGen.WATER_LEVEL + 0.1:
			# Вода: эту дорожку заканчиваем, новая начнётся на берегу.
			finish()
			return "Дорожка обрывается у воды"
		var step_len := _points[_points.size() - 1].distance_to(q)
		if not _pay(step_len):
			_rebuild_preview()
			finish()
			return "Не хватает: %s" % GameData.cost_text(Inventory.missing(cost_of(_type)))
		_points.append(q)
		_length += step_len
	_rebuild_preview()
	return ""


## Списывает стоимость за каждые METERS_PER_COST метров.
func _pay(step_len: float) -> bool:
	var need := _length + step_len
	while _paid_meters < need:
		var cost := cost_of(_type)
		if not Inventory.spend(cost):
			return false
		_paid_meters += METERS_PER_COST
	return true


## Дорожка закончена: сохраняем (если она не совсем крошечная).
func finish() -> void:
	if not _drawing:
		return
	_drawing = false
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	if _points.size() < 2 or _length < 0.3:
		# Нечаянное касание — дорожки нет.
		_points = PackedVector2Array()
		return
	WorldState.paths.append({"type": _type, "points": _points, "width": WIDTH})
	var i := WorldState.paths.size() - 1
	_meshes.append(null)
	_build(i)
	_clear_ground(WorldState.paths[i])
	_points = PackedVector2Array()


func _rebuild_preview() -> void:
	if is_instance_valid(_preview):
		_preview.mesh = build_mesh(_points, WIDTH)


# --- Хранение и показ ------------------------------------------------------------------------

## После загрузки мира: все дорожки заново.
func restore() -> void:
	for m in _meshes:
		if is_instance_valid(m):
			m.queue_free()
	_meshes.clear()
	for i in WorldState.paths.size():
		_meshes.append(null)
		_build(i)


func _build(i: int) -> void:
	var entry: Dictionary = WorldState.paths[i]
	var mi := _meshes[i]
	if not is_instance_valid(mi):
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_meshes[i] = mi
	mi.mesh = build_mesh(entry["points"], entry.get("width", WIDTH))
	mi.material_override = material_for(entry["type"])


## Чанк загрузился или земля изменилась: дорожки в нём ложатся на рельеф заново,
## трава под ними убирается.
func on_chunk_loaded(chunk: Chunk) -> void:
	var area := Rect2(chunk.position.x, chunk.position.z, WorldGen.CHUNK_SIZE, WorldGen.CHUNK_SIZE)
	for i in WorldState.paths.size():
		var entry: Dictionary = WorldState.paths[i]
		if _bounds(entry).intersects(area):
			_build(i)
			_clear_ground(entry, chunk)


func refresh_area(rect: Rect2) -> void:
	for i in WorldState.paths.size():
		if _bounds(WorldState.paths[i]).intersects(rect):
			_build(i)


static func _bounds(entry: Dictionary) -> Rect2:
	var pts: PackedVector2Array = entry["points"]
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r.grow(float(entry.get("width", WIDTH)))


## Трава и мелочь под дорожкой убираются (only — в указанном чанке).
func _clear_ground(entry: Dictionary, only: Chunk = null) -> void:
	var cells := {}
	var w: float = entry.get("width", WIDTH)
	var pts := _smooth(entry["points"])
	for i in pts.size():
		var p := pts[i]
		var r := ceili(w * 0.5)
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := p + Vector2(dx, dz)
				if q.distance_to(p) <= w * 0.5 + 0.5:
					cells[Vector2i(floori(q.x), floori(q.y))] = true
	var rect := _bounds(entry)
	if only:
		only.clear_cover_cells(cells)
		return
	for p in chunk_manager.props_in_rect(rect, false):
		if not GameData.blocks_building(p["id"]) and GameData.PROPS[p["id"]]["kind"] == "decor":
			var wp: Vector3 = (p["chunk"] as Chunk).to_global(p["pos"])
			if cells.has(Vector2i(floori(wp.x), floori(wp.z))):
				(p["chunk"] as Chunk).remove_prop(p)
	for c: Vector2i in chunk_manager.chunks:
		var chunk: Chunk = chunk_manager.chunks[c]
		if Rect2(chunk.position.x, chunk.position.z, WorldGen.CHUNK_SIZE, WorldGen.CHUNK_SIZE).intersects(rect):
			chunk.clear_cover_cells(cells)


# --- Правка: выбрать и убрать ----------------------------------------------------------------

## Дорожка под точкой земли (−1 — нет).
func pick(at: Vector3) -> int:
	var p := Vector2(at.x, at.z)
	var best := -1
	var best_d := INF
	for i in WorldState.paths.size():
		var entry: Dictionary = WorldState.paths[i]
		if not _bounds(entry).has_point(p):
			continue
		var pts: PackedVector2Array = entry["points"]
		for k in pts.size() - 1:
			var d := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1]).distance_to(p)
			if d < best_d:
				best_d = d
				best = i
	return best if best_d <= WIDTH * 0.6 else -1


func select(i: int) -> void:
	if _selected >= 0 and _selected < _meshes.size() and is_instance_valid(_meshes[_selected]):
		_meshes[_selected].material_overlay = null
	_selected = i
	if i >= 0 and i < _meshes.size() and is_instance_valid(_meshes[i]):
		_meshes[i].material_overlay = Building.highlight_material()


func selected() -> int:
	return _selected


func name_of(i: int) -> String:
	return GameData.BUILDINGS["path_" + str(WorldState.paths[i]["type"])]["name"]


## Убирает дорожку и возвращает половину потраченного.
func remove(i: int) -> Dictionary:
	if i < 0 or i >= WorldState.paths.size():
		return {}
	select(-1)
	var entry: Dictionary = WorldState.paths[i]
	var refund := {}
	if not GameMode.is_creative():
		var pts: PackedVector2Array = entry["points"]
		var length := 0.0
		for k in pts.size() - 1:
			length += pts[k].distance_to(pts[k + 1])
		var units := floori(ceilf(length / METERS_PER_COST) * 0.5)
		var cost := cost_of(entry["type"])
		for res: String in cost:
			if units * int(cost[res]) > 0:
				refund[res] = units * int(cost[res])
		Inventory.add_all(refund)
	if is_instance_valid(_meshes[i]):
		_meshes[i].queue_free()
	_meshes.remove_at(i)
	WorldState.paths.remove_at(i)
	return refund


# --- Геометрия ---------------------------------------------------------------------------------

## Сглаживание (два прохода Чайкина) и равномерные точки через MESH_STEP.
static func _smooth(raw: PackedVector2Array) -> PackedVector2Array:
	var pts := raw
	for pass_i in 2:
		if pts.size() < 3:
			break
		var next := PackedVector2Array([pts[0]])
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			next.append(a.lerp(b, 0.25))
			next.append(a.lerp(b, 0.75))
		next.append(pts[pts.size() - 1])
		pts = next
	# Равномерный шаг.
	var out := PackedVector2Array([pts[0]])
	var carry := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var t := MESH_STEP - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += MESH_STEP
		carry = seg - (t - MESH_STEP)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > 0.05:
		out.append(pts[pts.size() - 1])
	return out


## Лента шириной width вдоль точек: 5 вершин поперёк, высота — по земле.
func build_mesh(raw: PackedVector2Array, width: float) -> ArrayMesh:
	if raw.size() < 2:
		return null
	var pts := _smooth(raw)
	if pts.size() < 2:
		return null
	var half := width * 0.5
	# Продлеваем концы на полширины — туда шейдер рисует скругления.
	var t0 := (pts[1] - pts[0]).normalized()
	var t1 := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	pts.insert(0, pts[0] - t0 * half)
	pts.append(pts[pts.size() - 1] + t1 * half)
	var dist := PackedFloat32Array()
	dist.resize(pts.size())
	var total := 0.0
	for i in pts.size():
		if i > 0:
			total += pts[i].distance_to(pts[i - 1])
		dist[i] = total
	var cols := [-1.12, -0.55, 0.0, 0.55, 1.12]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in pts.size():
		var prev := pts[maxi(i - 1, 0)]
		var nxt := pts[mini(i + 1, pts.size() - 1)]
		var tangent := (nxt - prev).normalized()
		var side := Vector2(-tangent.y, tangent.x)
		for k in cols.size():
			var off: float = cols[k] * half
			var q: Vector2 = pts[i] + side * off
			var h := chunk_manager.get_height(q.x, q.y) if chunk_manager else 0.0
			verts.append(Vector3(q.x, h + LIFT, q.y))
			normals.append(_ground_normal(q))
			uvs.append(Vector2(off, dist[i]))
			uv2s.append(Vector2(dist[i], total - dist[i]))
	var n := cols.size()
	for i in pts.size() - 1:
		for k in n - 1:
			var a := i * n + k
			var b := a + 1
			var c := a + n
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _ground_normal(q: Vector2) -> Vector3:
	if chunk_manager == null:
		return Vector3.UP
	var e := 0.7
	var hx := chunk_manager.get_height(q.x + e, q.y) - chunk_manager.get_height(q.x - e, q.y)
	var hz := chunk_manager.get_height(q.x, q.y + e) - chunk_manager.get_height(q.x, q.y - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()
