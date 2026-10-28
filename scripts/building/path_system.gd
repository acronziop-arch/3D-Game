class_name PathSystem
extends Node3D
## Плавные дорожки: игрок ведёт пальцем (или мышью) из любого места, и за ним
## ложится ровная лента — не из плиток. Линия сглаживается, лента повторяет
## рельеф, концы скруглены, узор рисует шейдер path.gdshader. Трава под дорожкой
## убирается. Дорожки хранятся в WorldState.paths:
##   {"type": "dirt" | "wood" | "stone" | "brick", "points": PackedVector2Array, "width": float,
##    "layer": int — порядок: где дорожки перекрываются, видна та, у которой слой выше}
## Новая дорожка ложится под старые, которые пересекает: она обрывается ровно по их
## краю. Начатая у конца дорожки того же вида — продолжает её, без шва в узоре.

const WIDTH := 1.6
## Шаг записи точек за пальцем и шаг ленты, м.
const RECORD_STEP := 0.6
const MESH_STEP := 0.35
const LIFT := 0.045
const KINDS := {"dirt": 0, "wood": 1, "stone": 2, "brick": 3}
## Порядок отрисовки дорожек (render_priority): все — раньше воды, кольца кисти и огня;
## у старших слоёв — позже, то есть поверх. Рисуемая сейчас — под всеми.
const PRIORITY_TOP := -40
const PRIORITY_DRAWING := -100
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
## До какой точки рисуемой дорожки трава уже убрана.
var _faded_upto := 0
var _selected := -1
## Дорожка того же вида, которую сейчас продолжают (−1 — рисуется новая).
var _continuing := -1


## Стоимость участка дорожки (как у плитки того же вида).
static func cost_of(path_type: String) -> Dictionary:
	return GameData.BUILDINGS["path_" + path_type]["cost"]


func material_for(path_type: String, priority := PRIORITY_TOP) -> ShaderMaterial:
	var key := "%s:%d" % [path_type, priority]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/path.gdshader")
		m.set_shader_parameter("kind", KINDS.get(path_type, 0))
		m.set_shader_parameter("width", WIDTH)
		m.render_priority = priority
		_materials[key] = m
	return _materials[key]


## Материал дорожки из WorldState.paths с её местом в порядке перекрытия.
func _material_of(entry: Dictionary) -> ShaderMaterial:
	return material_for(entry["type"], PRIORITY_TOP + maxi(int(entry.get("layer", 0)), PRIORITY_DRAWING - PRIORITY_TOP + 1))


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
	_preview.material_override = material_for(_type, PRIORITY_DRAWING)
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.layers = Chunk.DETAIL_LAYER
	add_child(_preview)
	_faded_upto = 0
	# Начали у конца дорожки того же вида — продолжаем её (одна лента, узор без шва).
	_continuing = _end_near(path_type, Vector2(at.x, at.z))
	if _continuing >= 0:
		var pts: PackedVector2Array = WorldState.paths[_continuing]["points"]
		if pts[0].distance_to(Vector2(at.x, at.z)) < pts[pts.size() - 1].distance_to(Vector2(at.x, at.z)):
			pts = pts.duplicate()
			pts.reverse()
		_points = pts.duplicate()
		_faded_upto = _points.size()
		if is_instance_valid(_meshes[_continuing]):
			_meshes[_continuing].visible = false
		_preview.material_override = _material_of(WorldState.paths[_continuing])
		_rebuild_preview()
	else:
		_points[0] = _onto_path(_points[0])
	return ""


## Точка на другой дорожке переносится на её середину: тогда скруглённый конец новой
## дорожки целиком уходит под старую, и новая начинается ровно от её края.
func _onto_path(p: Vector2, skip := -1) -> Vector2:
	var best := p
	var best_d := INF
	for i in WorldState.paths.size():
		if i == skip:
			continue
		var entry: Dictionary = WorldState.paths[i]
		var half := float(entry.get("width", WIDTH)) * 0.5
		if not _bounds(entry).has_point(p):
			continue
		var pts: PackedVector2Array = entry["points"]
		for k in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])
			var d := q.distance_to(p)
			if d < half and d < best_d:
				best_d = d
				best = q
	return best


## Дорожка вида path_type, конец которой рядом с точкой (−1 — нет такой).
func _end_near(path_type: String, p: Vector2) -> int:
	var best := -1
	var best_d := WIDTH * 0.75
	for i in WorldState.paths.size():
		var entry: Dictionary = WorldState.paths[i]
		if entry["type"] != path_type:
			continue
		var pts: PackedVector2Array = entry["points"]
		for q in [pts[0], pts[pts.size() - 1]]:
			var d := (q as Vector2).distance_to(p)
			if d < best_d:
				best_d = d
				best = i
	return best


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
			return "Не хватает: %s" % Rich.cost(Inventory.missing(cost_of(_type)), 16)
		_points.append(q)
		_length += step_len
	_rebuild_preview()
	# Трава под только что проложенным куском уходит сразу, плавно, за пальцем
	# (но не от случайного касания: только когда дорожка уже точно начата).
	if _length >= 0.3:
		_fade_ground(_points.slice(maxi(_faded_upto - 1, 0)), WIDTH)
		_faded_upto = _points.size()
	return ""


## Трава под точками дорожки плавно уходит (без рывка после того, как палец отпустили).
func _fade_ground(pts: PackedVector2Array, w: float) -> void:
	var cells := _cells_under(pts, w)
	if cells.is_empty():
		return
	var rect := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		rect = rect.expand(p)
	rect = rect.grow(w)
	for c: Vector2i in chunk_manager.chunks:
		var chunk: Chunk = chunk_manager.chunks[c]
		if Rect2(chunk.position.x, chunk.position.z, WorldGen.CHUNK_SIZE, WorldGen.CHUNK_SIZE).intersects(rect):
			chunk.fade_cover_cells(cells)


## Клетки 1 м под лентой шириной w вдоль точек.
static func _cells_under(pts: PackedVector2Array, w: float) -> Dictionary:
	var cells := {}
	var r := ceili(w * 0.5)
	for p in pts:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := p + Vector2(dx, dz)
				if q.distance_to(p) <= w * 0.5 + 0.5:
					cells[Vector2i(floori(q.x), floori(q.y))] = true
	return cells


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
	var continuing := _continuing
	_continuing = -1
	if _points.size() < 2 or _length < 0.3:
		# Нечаянное касание — дорожки нет (продолжаемая остаётся, как была).
		_points = PackedVector2Array()
		if continuing >= 0 and is_instance_valid(_meshes[continuing]):
			_meshes[continuing].visible = true
		return
	_points[_points.size() - 1] = _onto_path(_points[_points.size() - 1], continuing)
	var i := continuing
	if i >= 0:
		WorldState.paths[i]["points"] = _points
		_meshes[i].visible = true
	else:
		WorldState.paths.append({"type": _type, "points": _points, "width": WIDTH})
		i = WorldState.paths.size() - 1
		WorldState.paths[i]["layer"] = _layer_under(i)
		_meshes.append(null)
	_build(i)
	_clear_ground(WorldState.paths[i], null, true)
	_points = PackedVector2Array()


## Слой новой дорожки i: ниже всех более старых, которые она пересекает (слой 0 — верхний).
func _layer_under(i: int) -> int:
	var entry: Dictionary = WorldState.paths[i]
	var layer := 0
	for k in i:
		var other: Dictionary = WorldState.paths[k]
		if _paths_touch(entry, other):
			layer = mini(layer, int(other.get("layer", 0)) - 1)
	return layer


static func _paths_touch(a: Dictionary, b: Dictionary) -> bool:
	if not _bounds(a).intersects(_bounds(b)):
		return false
	var reach := (float(a.get("width", WIDTH)) + float(b.get("width", WIDTH))) * 0.5
	var pa: PackedVector2Array = a["points"]
	var pb: PackedVector2Array = b["points"]
	for p in pa:
		for k in pb.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, pb[k], pb[k + 1]).distance_to(p) < reach:
				return true
	return false


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
		# Старые сохранения слоёв не знали: считаем по порядку постройки.
		if not WorldState.paths[i].has("layer"):
			WorldState.paths[i]["layer"] = _layer_under(i)
		_meshes.append(null)
		_build(i)


func _build(i: int) -> void:
	var entry: Dictionary = WorldState.paths[i]
	var mi := _meshes[i]
	if not is_instance_valid(mi):
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = Chunk.DETAIL_LAYER
		add_child(mi)
		_meshes[i] = mi
	var arrays := build_arrays(entry["points"], entry.get("width", WIDTH))
	mi.mesh = _mesh_from(arrays)
	# Вершины остаются под рукой: при выравнивании земли сдвигаются только те, что под кистью.
	mi.set_meta("arrays", arrays)
	mi.material_override = _material_of(entry)


## Земля под частью дорожки i изменилась: вершины в rect встают на новую высоту.
func _refit(i: int, rect: Rect2) -> void:
	var mi := _meshes[i]
	if not is_instance_valid(mi) or not mi.has_meta("arrays") or (mi.get_meta("arrays") as Array).is_empty():
		_build(i)
		return
	var arrays: Array = mi.get_meta("arrays")
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	# Наклон берётся по точкам в 0.7 м вокруг вершины — их тоже задело.
	var area := rect.grow(0.8)
	var changed := false
	for v in verts.size():
		var q := Vector2(verts[v].x, verts[v].z)
		if area.has_point(q):
			var vert := verts[v]
			vert.y = chunk_manager.get_height(q.x, q.y) + LIFT
			verts[v] = vert
			normals[v] = _ground_normal(q)
			changed = true
	if changed:
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		mi.mesh = _mesh_from(arrays)


## Чанк загрузился или земля изменилась: дорожки в нём ложатся на рельеф заново,
## трава под ними убирается.
func on_chunk_loaded(chunk: Chunk) -> void:
	# Мир ещё грузится, дорожки не созданы (restore) — их уложат при создании.
	if _meshes.size() != WorldState.paths.size():
		return
	var area := Rect2(chunk.position.x, chunk.position.z, WorldGen.CHUNK_SIZE, WorldGen.CHUNK_SIZE)
	for i in WorldState.paths.size():
		var entry: Dictionary = WorldState.paths[i]
		if _bounds(entry).intersects(area):
			_refit(i, area)
			_clear_ground(entry, chunk)


func refresh_area(rect: Rect2) -> void:
	for i in WorldState.paths.size():
		if _bounds(WorldState.paths[i]).intersects(rect):
			_build(i)


## Землю выравнивают (несколько раз в секунду, пока идёт мазок): дорожки сразу ложатся
## на новую поверхность, а там, где земля ушла под воду, дорожка обрывается.
func on_terrain_changed(rect: Rect2) -> void:
	if _meshes.size() != WorldState.paths.size():
		return
	for i in range(WorldState.paths.size() - 1, -1, -1):
		var entry: Dictionary = WorldState.paths[i]
		if not _bounds(entry).intersects(rect):
			continue
		var parts := _dry_parts(entry["points"], rect)
		if parts.size() == 1 and parts[0].size() == (entry["points"] as PackedVector2Array).size():
			_refit(i, rect)
		else:
			_split(i, parts)


## Куски дорожки над водой (точки, где земля ушла под воду, выпадают). Проверяются
## только точки в rect: вне его земля не менялась, там дорожка и была на суше.
func _dry_parts(pts: PackedVector2Array, rect: Rect2) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = []
	var cur := PackedVector2Array()
	for k in pts.size():
		var p := pts[k]
		var wet := rect.has_point(p) and _is_wet(p)
		if not wet and k > 0:
			# Узкий проток между двумя точками тоже рвёт дорожку.
			var m := (p + pts[k - 1]) * 0.5
			if rect.has_point(m) and _is_wet(m):
				_keep_part(parts, cur)
				cur = PackedVector2Array()
		if wet:
			_keep_part(parts, cur)
			cur = PackedVector2Array()
		else:
			cur.append(p)
	_keep_part(parts, cur)
	return parts


func _is_wet(p: Vector2) -> bool:
	return chunk_manager.get_height(p.x, p.y) < WorldGen.WATER_LEVEL + 0.05


static func _keep_part(parts: Array[PackedVector2Array], pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	var length := 0.0
	for k in pts.size() - 1:
		length += pts[k].distance_to(pts[k + 1])
	if length >= 0.3:
		parts.append(pts)


## Дорожка i распалась на куски (часть ушла под воду): вместо неё — куски того же вида.
func _split(i: int, parts: Array[PackedVector2Array]) -> void:
	if _selected >= i:
		select(-1)
	var entry: Dictionary = WorldState.paths[i]
	if is_instance_valid(_meshes[i]):
		_meshes[i].queue_free()
	_meshes.remove_at(i)
	WorldState.paths.remove_at(i)
	for k in parts.size():
		WorldState.paths.insert(i + k, {"type": entry["type"], "points": parts[k], "width": entry.get("width", WIDTH),
			"layer": entry.get("layer", 0)})
		_meshes.insert(i + k, null)
		_build(i + k)


static func _bounds(entry: Dictionary) -> Rect2:
	var pts: PackedVector2Array = entry["points"]
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r.grow(float(entry.get("width", WIDTH)))


## Трава и мелочь под дорожкой убираются (only — в указанном чанке, сразу;
## smooth — трава уходит плавно: так заканчивается только что нарисованная дорожка).
func _clear_ground(entry: Dictionary, only: Chunk = null, smooth := false) -> void:
	var w: float = entry.get("width", WIDTH)
	var cells := _cells_under(_smooth(entry["points"]), w)
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
			if smooth:
				chunk.fade_cover_cells(cells)
			else:
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


## Выделенная дорожка подсвечивается своим же шейдером (параметр highlight): поверх
## ленты, сдвинутой к камере, отдельный слой подсветки был бы не виден.
func select(i: int) -> void:
	if _selected >= 0 and _selected < _meshes.size() and is_instance_valid(_meshes[_selected]):
		_meshes[_selected].material_override = _material_of(WorldState.paths[_selected])
	_selected = i
	if i >= 0 and i < _meshes.size() and is_instance_valid(_meshes[i]):
		var m := _material_of(WorldState.paths[i]).duplicate() as ShaderMaterial
		m.set_shader_parameter("highlight", 1.0)
		_meshes[i].material_override = m


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

## Сглаживание (два прохода Чайкина) и равномерные точки через step.
static func _smooth(raw: PackedVector2Array, step := MESH_STEP) -> PackedVector2Array:
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
		var t := step - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += step
		carry = seg - (t - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > 0.05:
		out.append(pts[pts.size() - 1])
	return out


## Лента шириной width вдоль точек: 5 вершин поперёк, высота — по земле.
func build_mesh(raw: PackedVector2Array, width: float) -> ArrayMesh:
	return _mesh_from(build_arrays(raw, width))


static func _mesh_from(arrays: Array) -> ArrayMesh:
	if arrays.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Массивы ленты для ArrayMesh (пустой — дорожка слишком короткая).
func build_arrays(raw: PackedVector2Array, width: float) -> Array:
	if raw.size() < 2:
		return []
	var pts := _smooth(raw)
	if pts.size() < 2:
		return []
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
	return arrays


func _ground_normal(q: Vector2) -> Vector3:
	if chunk_manager == null:
		return Vector3.UP
	var e := 0.7
	var hx := chunk_manager.get_height(q.x + e, q.y) - chunk_manager.get_height(q.x - e, q.y)
	var hz := chunk_manager.get_height(q.x, q.y + e) - chunk_manager.get_height(q.x, q.y - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()
