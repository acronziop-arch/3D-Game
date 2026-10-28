class_name FenceSystem
extends Node3D
## Ограды «протягиванием»: игрок ведёт пальцем (или мышью), и следом встаёт ограда
## любой формы — как дорожка (PathSystem), а не повёрнутая готовая секция. Линия
## сглаживается, ограда идёт по рельефу:
##   fence_stone — камни в три ряда с обеих сторон, между ними и под ними — раствор,
##                 поверху плоские камни;
##   palisade    — заострённые колья вплотную и две жерди с внутренней стороны.
## Ограды хранятся в WorldState.fences: {"type": id здания, "points": PackedVector2Array,
## "seed": int}. Меш ограды разбит на куски по PIECE м: пока её ведут или под ней ровняют
## землю, перестраиваются только задетые куски. Цена метра — GameData.BUILDINGS[id]["drawn"].
## Начатая у конца ограды того же вида — продолжает её; доведённая до своего начала — замыкается.

## Шаг записи точек за пальцем и шаг сглаженной линии, м.
const RECORD_STEP := 0.6
const CURVE_STEP := 0.25
## Длина куска меша, м.
const PIECE := 4.0
## Сколько кусков перестраивать за кадр после выравнивания земли и подгрузки чанков.
const REBUILDS_PER_FRAME := 3
## Каменная ограда: полутолщина раствора, его верх, ряды камней и сколько уходит в землю.
const WALL_HALF := 0.2
const WALL_TOP := 0.9
const WALL_ROWS := 3
const WALL_SINK := 0.45
const MORTAR := Color(0.71, 0.69, 0.64)
## Частокол: шаг, радиус и высота кольев, высоты жердей и длина их звеньев.
const STAKE_STEP := 0.32
const STAKE_R := 0.15
const STAKE_H := 1.8
const STAKE_SINK := 0.45
const RAILS := [0.55, 1.2]
const RAIL_STEP := 1.0
## Насколько далеко от линии ограды можно промахнуться пальцем или мышью, выбирая её, м.
const PICK_REACH := 0.9

var chunk_manager: ChunkManager

## Параллельно WorldState.fences: {"node": Node3D, "pieces": Array (MeshInstance3D),
## "rects": Array (Rect2 куска), "curve": {"p": точки линии, "s": путь до них, "length"},
## "dirty": {номер куска: true} — перестроить, когда дойдёт очередь}.
var _items: Array[Dictionary] = []
## Ограда, которую сейчас ведут (−1 — никакую), и что было до начала (если продолжают).
var _drawing := -1
var _backup := PackedVector2Array()
var _drawn := 0.0
var _paid_units := 0
## До какой точки рисуемой ограды трава уже убрана.
var _faded_upto := 0
var _selected := -1


static func cost_of(fence_type: String) -> Dictionary:
	return GameData.BUILDINGS[fence_type]["drawn"]


# --- Рисование ------------------------------------------------------------------------------

func is_drawing() -> bool:
	return _drawing >= 0


## Начать ограду в точке земли. Пустая строка — начали; иначе причина.
func begin(fence_type: String, at: Vector3) -> String:
	finish()
	if at.y < WorldGen.WATER_LEVEL + 0.1:
		return "Ограду не поставить в воде"
	var p := Vector2(at.x, at.z)
	_drawn = 0.0
	_paid_units = 0
	_backup = PackedVector2Array()
	var i := _end_near(fence_type, p)
	if i >= 0:
		# Начали у конца ограды того же вида — продолжаем её, без шва.
		var pts: PackedVector2Array = (WorldState.fences[i]["points"] as PackedVector2Array).duplicate()
		_backup = pts.duplicate()
		if pts[0].distance_to(p) < pts[pts.size() - 1].distance_to(p):
			pts.reverse()
			WorldState.fences[i]["points"] = pts
			_rebuild(i)
		_faded_upto = pts.size()
	else:
		WorldState.fences.append({"type": fence_type, "points": PackedVector2Array([p]), "seed": randi() % 1000000})
		_items.append(_new_item())
		i = WorldState.fences.size() - 1
		_faded_upto = 0
	_drawing = i
	return ""


## Палец ушёл дальше: добавляем точки. Пустая строка — всё хорошо; иначе причина остановки.
func extend(at: Vector3) -> String:
	if _drawing < 0:
		return ""
	var entry: Dictionary = WorldState.fences[_drawing]
	var pts: PackedVector2Array = (entry["points"] as PackedVector2Array).duplicate()
	var p := Vector2(at.x, at.z)
	var last := pts[pts.size() - 1]
	var dist := last.distance_to(p)
	if dist < RECORD_STEP:
		return ""
	var old_length: float = _items[_drawing]["curve"].get("length", 0.0)
	var reason := ""
	# Быстрый взмах — дописываем промежуточные точки, чтобы линия была ровной.
	var steps := ceili(dist / RECORD_STEP)
	for k in range(1, steps + 1):
		var q := last.lerp(p, float(k) / steps)
		if chunk_manager.get_height(q.x, q.y) < WorldGen.WATER_LEVEL + 0.1:
			reason = "Ограда обрывается у воды"
			break
		var step_len := pts[pts.size() - 1].distance_to(q)
		if not _pay(entry["type"], step_len):
			reason = "Не хватает: %s" % Rich.cost(Inventory.missing(cost_of(entry["type"])), 16)
			break
		pts.append(q)
		_drawn += step_len
	entry["points"] = pts
	# Конец линии сглаживается заново — перестраиваем последние метры.
	_rebuild(_drawing, floori(maxf(old_length - 1.5, 0.0) / PIECE))
	if _drawn >= 0.3:
		_clear_ground(_drawing, null, true, maxi(_faded_upto - 1, 0))
		_faded_upto = pts.size()
	if reason != "":
		finish()
	return reason


## Списывает цену метра за каждый начатый метр.
func _pay(fence_type: String, step_len: float) -> bool:
	while _paid_units < _drawn + step_len:
		if not Inventory.spend(cost_of(fence_type)):
			return false
		_paid_units += 1
	return true


## Ограда закончена: сохраняем (если она не совсем крошечная).
func finish() -> void:
	if _drawing < 0:
		return
	var i := _drawing
	_drawing = -1
	var entry: Dictionary = WorldState.fences[i]
	if _drawn < 0.3:
		# Нечаянное касание — ограды нет (продолжаемая остаётся, как была), уплаченное — назад.
		if not GameMode.is_creative() and _paid_units > 0:
			var refund := {}
			var cost := cost_of(entry["type"])
			for res: String in cost:
				refund[res] = int(cost[res]) * _paid_units
			Inventory.add_all(refund)
		if _backup.is_empty():
			_erase(i)
		else:
			entry["points"] = _backup
			_rebuild(i)
		_backup = PackedVector2Array()
		return
	_backup = PackedVector2Array()
	var pts: PackedVector2Array = (entry["points"] as PackedVector2Array).duplicate()
	var length: float = _items[i]["curve"].get("length", 0.0)
	# Довели до начала — ограда замыкается в кольцо.
	if pts.size() > 3 and length > 4.0 and pts[pts.size() - 1].distance_to(pts[0]) < 1.2:
		pts.append(pts[0])
		entry["points"] = pts
		_rebuild(i, floori(maxf(length - 1.5, 0.0) / PIECE))
	_clear_ground(i, null, true)


## Ограда вида fence_type, конец которой рядом с точкой (−1 — нет такой).
func _end_near(fence_type: String, p: Vector2) -> int:
	var best := -1
	var best_d := 1.0
	for i in WorldState.fences.size():
		var entry: Dictionary = WorldState.fences[i]
		var pts: PackedVector2Array = entry["points"]
		if entry["type"] != fence_type or pts.size() < 2 or pts[0].distance_to(pts[pts.size() - 1]) < 0.05:
			continue
		for q in [pts[0], pts[pts.size() - 1]]:
			var d := (q as Vector2).distance_to(p)
			if d < best_d:
				best_d = d
				best = i
	return best


# --- Хранение и показ ------------------------------------------------------------------------

## После загрузки мира: все ограды заново.
func restore() -> void:
	for item in _items:
		(item["node"] as Node3D).queue_free()
	_items.clear()
	_drawing = -1
	_selected = -1
	for i in WorldState.fences.size():
		_items.append(_new_item())
		_rebuild(i)


func _new_item() -> Dictionary:
	var node := Node3D.new()
	add_child(node)
	return {"node": node, "pieces": [], "rects": [], "curve": {}, "dirty": {}}


func _erase(i: int) -> void:
	if _selected == i:
		select(-1)
	elif _selected > i:
		_selected -= 1
	(_items[i]["node"] as Node3D).queue_free()
	_items.remove_at(i)
	WorldState.fences.remove_at(i)


## Линия ограды i заново и куски меша начиная с from_piece.
func _rebuild(i: int, from_piece := 0) -> void:
	var item := _items[i]
	var curve := _curve(WorldState.fences[i]["points"])
	item["curve"] = curve
	var count := ceili(curve["length"] / PIECE) if curve["length"] > 0.05 else 0
	var pieces: Array = item["pieces"]
	while pieces.size() > count:
		var mi: Variant = pieces.pop_back()
		if is_instance_valid(mi):
			(mi as Node).queue_free()
	(item["rects"] as Array).resize(count)
	for k in range(maxi(from_piece, 0), count):
		_build_piece(i, k)


func _build_piece(i: int, k: int) -> void:
	var item := _items[i]
	var entry: Dictionary = WorldState.fences[i]
	var curve: Dictionary = item["curve"]
	var pieces: Array = item["pieces"]
	while pieces.size() <= k:
		pieces.append(null)
	(item["dirty"] as Dictionary).erase(k)
	var s0 := k * PIECE
	var s1 := minf((k + 1) * PIECE, curve["length"])
	var g := Geo.new()
	g.with_uv2 = false
	var seed_value := int(entry.get("seed", 0))
	if entry["type"] == "palisade":
		_palisade(g, curve, s0, s1, seed_value)
	else:
		_stone_wall(g, curve, s0, s1, seed_value)
	var mi: MeshInstance3D = pieces[k]
	if not is_instance_valid(mi):
		mi = MeshInstance3D.new()
		(item["node"] as Node3D).add_child(mi)
		pieces[k] = mi
	item["rects"][k] = _rect_of(curve, s0, s1)
	if g.is_empty():
		mi.mesh = null
		return
	mi.mesh = g.build_mesh()
	ModelLibrary.apply_building_materials(mi)
	mi.material_overlay = Building.highlight_material() if i == _selected else null


## Прямоугольник (x, z) куска ограды с запасом.
static func _rect_of(curve: Dictionary, s0: float, s1: float) -> Rect2:
	var pts: PackedVector2Array = curve["p"]
	var dist: PackedFloat32Array = curve["s"]
	var r := Rect2(_frame(curve, s0)[0], Vector2.ZERO)
	for k in pts.size():
		if dist[k] > s0 and dist[k] < s1:
			r = r.expand(pts[k])
	r = r.expand(_frame(curve, s1)[0])
	return r.grow(1.0)


## Земля изменилась (выравнивают): задетые куски встают на неё — по нескольку за кадр.
func on_terrain_changed(rect: Rect2) -> void:
	for item in _items:
		var rects: Array = item["rects"]
		for k in rects.size():
			if rects[k] is Rect2 and (rects[k] as Rect2).intersects(rect):
				item["dirty"][k] = true


## Чанк загрузился (или в нём пересеяли траву): ограды в нём встают на рельеф,
## трава под ними убирается.
func on_chunk_loaded(chunk: Chunk) -> void:
	var area := Rect2(chunk.position.x, chunk.position.z, WorldGen.CHUNK_SIZE, WorldGen.CHUNK_SIZE)
	for i in _items.size():
		var rects: Array = _items[i]["rects"]
		var touched := false
		for k in rects.size():
			if rects[k] is Rect2 and (rects[k] as Rect2).intersects(area):
				_items[i]["dirty"][k] = true
				touched = true
		if touched:
			_clear_ground(i, chunk)


func _process(_delta: float) -> void:
	var budget := REBUILDS_PER_FRAME
	for i in _items.size():
		var dirty: Dictionary = _items[i]["dirty"]
		while not dirty.is_empty() and budget > 0:
			var k: int = dirty.keys()[0]
			dirty.erase(k)
			if k < (_items[i]["pieces"] as Array).size():
				_build_piece(i, k)
			budget -= 1
		if budget <= 0:
			return


## Трава и мелочь под оградой убираются (only — только в этом чанке, сразу; smooth — трава
## уходит плавно, за пальцем; from — с какой точки записанной линии).
func _clear_ground(i: int, only: Chunk = null, smooth := false, from := 0) -> void:
	var raw: PackedVector2Array = WorldState.fences[i]["points"]
	if raw.size() < 2:
		return
	var pts := PathSystem._smooth(raw.slice(from), CURVE_STEP) if from > 0 else _items[i]["curve"]["p"] as PackedVector2Array
	var cells := PathSystem._cells_under(pts, 0.3)
	if only:
		only.clear_cover_cells(cells)
		return
	var rect := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		rect = rect.expand(p)
	rect = rect.grow(1.0)
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

## Ограда под лучом из камеры (−1 — нет): луч сверяется с серединой ограды по высоте,
## а не с землёй за ней — высокий частокол выбирается нажатием прямо на колья.
func pick(from: Vector3, dir: Vector3) -> int:
	var best := -1
	var best_d := PICK_REACH
	for i in _items.size():
		var tall := STAKE_H if WorldState.fences[i]["type"] == "palisade" else WALL_TOP
		var pts: PackedVector2Array = _items[i]["curve"].get("p", PackedVector2Array())
		for k in range(0, pts.size(), 2):
			var q := pts[k]
			var c := Vector3(q.x, _height(q) + tall * 0.5, q.y)
			var t := (c - from).dot(dir)
			if t <= 0.0:
				continue
			var d := (from + dir * t).distance_to(c)
			if d < best_d:
				best_d = d
				best = i
	return best


func select(i: int) -> void:
	for k in [_selected, i]:
		if k < 0 or k >= _items.size():
			continue
		for mi: Variant in _items[k]["pieces"]:
			if is_instance_valid(mi):
				(mi as MeshInstance3D).material_overlay = Building.highlight_material() if k == i else null
	_selected = i


func selected() -> int:
	return _selected


func name_of(i: int) -> String:
	return GameData.BUILDINGS[str(WorldState.fences[i]["type"])]["name"]


func length_of(i: int) -> float:
	return _items[i]["curve"].get("length", 0.0)


## Убирает ограду и возвращает половину потраченного.
func remove(i: int) -> Dictionary:
	if i < 0 or i >= WorldState.fences.size():
		return {}
	select(-1)
	var refund := {}
	if not GameMode.is_creative():
		var units := floori(ceilf(length_of(i)) * 0.5)
		var cost := cost_of(WorldState.fences[i]["type"])
		for res: String in cost:
			if units * int(cost[res]) > 0:
				refund[res] = units * int(cost[res])
		Inventory.add_all(refund)
	_erase(i)
	return refund


# --- Геометрия ---------------------------------------------------------------------------------

func _height(p: Vector2) -> float:
	return chunk_manager.get_height(p.x, p.y) if chunk_manager else 0.0


## Сглаженная линия: точки через CURVE_STEP и путь до каждой от начала.
static func _curve(raw: PackedVector2Array) -> Dictionary:
	var pts := PathSystem._smooth(raw, CURVE_STEP) if raw.size() >= 2 else raw
	var dist := PackedFloat32Array()
	dist.resize(pts.size())
	var total := 0.0
	for k in pts.size():
		if k > 0:
			total += pts[k].distance_to(pts[k - 1])
		dist[k] = total
	return {"p": pts, "s": dist, "length": total if pts.size() >= 2 else 0.0}


## Точка на линии через s м от начала и направление линии там: [Vector2, Vector2].
static func _frame(curve: Dictionary, s: float) -> Array:
	var pts: PackedVector2Array = curve["p"]
	var dist: PackedFloat32Array = curve["s"]
	var n := pts.size()
	if n < 2:
		return [pts[0] if n > 0 else Vector2.ZERO, Vector2.RIGHT]
	var k := clampi(floori(s / CURVE_STEP), 0, n - 2)
	while k > 0 and dist[k] > s:
		k -= 1
	while k < n - 2 and dist[k + 1] < s:
		k += 1
	var seg := maxf(dist[k + 1] - dist[k], 0.0001)
	var p := pts[k].lerp(pts[k + 1], clampf((s - dist[k]) / seg, 0.0, 1.0))
	# Направление — по соседним отрезкам: на изгибах камни и жерди поворачиваются плавно.
	var t := pts[mini(k + 2, n - 1)] - pts[maxi(k - 1, 0)]
	return [p, t.normalized() if t.length_squared() > 1e-8 else Vector2.RIGHT]


## Ось «вдоль ограды» на отрезке [a, b] пути с учётом уклона земли.
func _along(curve: Dictionary, a: float, b: float, t: Vector2) -> Vector3:
	var rise := _height(_frame(curve, b)[0]) - _height(_frame(curve, a)[0])
	return Vector3(t.x, rise / maxf(b - a, 0.01), t.y).normalized()


## Каменная ограда на участке [s0, s1] пути: стенка раствора, по ней камни рядами
## с обеих сторон (между ними видны швы) и плоские камни поверху.
func _stone_wall(g: Geo, c: Dictionary, s0: float, s1: float, seed_value: int) -> void:
	var total: float = c["length"]
	if total < 0.05:
		return
	var m := maxi(ceili((s1 - s0) / CURVE_STEP), 1)
	var prev: Array[Vector3] = []
	for j in m + 1:
		var s := lerpf(s0, s1, float(j) / m)
		var f := _frame(c, s)
		var p: Vector2 = f[0]
		var t: Vector2 = f[1]
		var side := Vector2(-t.y, t.x) * WALL_HALF
		var top := _height(p) + WALL_TOP
		var bottom := minf(_height(p + side), _height(p - side)) - WALL_SINK
		var ring: Array[Vector3] = [Vector3(p.x + side.x, bottom, p.y + side.y), Vector3(p.x + side.x, top, p.y + side.y),
			Vector3(p.x - side.x, top, p.y - side.y), Vector3(p.x - side.x, bottom, p.y - side.y)]
		var out := Vector3(side.x, 0.0, side.y)
		if j > 0:
			g.quad("stone", prev[0], ring[0], ring[1], prev[1], MORTAR, out)
			g.quad("stone", prev[1], ring[1], ring[2], prev[2], MORTAR, Vector3.UP)
			g.quad("stone", prev[2], ring[2], ring[3], prev[3], MORTAR, -out)
		if (j == 0 and s0 <= 0.0) or (j == m and s1 >= total - 0.001):
			g.quad("stone", ring[0], ring[1], ring[2], ring[3], MORTAR.darkened(0.06), Vector3(t.x, 0.0, t.y) * (-1.0 if j == 0 else 1.0))
		prev = ring
	var rng := RandomNumberGenerator.new()
	var base: Color = GameData.MATERIALS["stone"]["color"]
	var row_h := WALL_TOP / WALL_ROWS
	# Ряды камней: у каждого ряда своя последовательность, она всегда идёт от начала
	# ограды — так камни не «переезжают», когда ограду ведут дальше.
	for side_sign: float in [1.0, -1.0]:
		for row in WALL_ROWS:
			rng.seed = hash([seed_value, side_sign, row])
			var u := 0.03
			var first := true
			while u < total - 0.1 and u < s1:
				var length := rng.randf_range(0.34, 0.6)
				if first and row % 2 == 1:
					length *= 0.5
				first = false
				var gap := rng.randf_range(0.035, 0.06)
				var height := row_h - rng.randf_range(0.035, 0.07)
				var depth := rng.randf_range(0.05, 0.09)
				var lift := rng.randf_range(-0.015, 0.015)
				var shade := 1.0 + rng.randf_range(-0.1, 0.08)
				var warm := rng.randf_range(-0.015, 0.03)
				length = minf(length, total - 0.03 - u)
				if u >= s0 and length > 0.12:
					var f := _frame(c, u + length * 0.5)
					var p: Vector2 = f[0]
					var t: Vector2 = f[1]
					var along := _along(c, u, u + length, t)
					var normal := Vector3(-t.y, 0.0, t.x) * side_sign
					var up := normal.cross(along)
					if up.y < 0.0:
						up = -up
					var q := p + Vector2(normal.x, normal.z) * WALL_HALF
					g.tile("stone", Vector3(q.x, _height(p) + row * row_h + row_h * 0.5 + lift, q.y), normal, up,
						length, height, depth, 0.035, Color(base.r * shade + warm, base.g * shade, base.b * shade - warm))
				u += length + gap
	# Плоские камни поверху — во всю толщину, с небольшим свесом.
	rng.seed = hash([seed_value, 7])
	var u := 0.0
	while u < total - 0.05 and u < s1:
		var length := minf(rng.randf_range(0.42, 0.7), total - u)
		var gap := rng.randf_range(0.015, 0.035)
		var width := WALL_HALF * 2.0 + rng.randf_range(0.1, 0.18)
		var yaw := rng.randf_range(-0.05, 0.05)
		var shade := 1.0 + rng.randf_range(-0.04, 0.12)
		if u >= s0 and length > 0.1:
			var f := _frame(c, u + length * 0.5)
			var p: Vector2 = f[0]
			var x := _along(c, u, u + length, f[1])
			var y := (Vector3.UP - x * x.y).normalized()
			var basis := Basis(Vector3.UP, yaw) * Basis(x, y, x.cross(y))
			g.box("stone", Vector3(p.x, _height(p) + WALL_TOP + 0.06, p.y), Vector3(length - gap, 0.12, width),
				Color(base.r * shade, base.g * shade, base.b * shade), 0.04, basis)
		u += length


## Частокол на участке [s0, s1] пути: заострённые колья вплотную друг к другу и две жерди
## с внутренней (левой по ходу) стороны.
func _palisade(g: Geo, c: Dictionary, s0: float, s1: float, seed_value: int) -> void:
	var total: float = c["length"]
	if total < 0.05:
		return
	var rng := RandomNumberGenerator.new()
	var wood: Color = GameData.MATERIALS["log"]["color"]
	var k := maxi(floori((s0 - STAKE_STEP * 0.5) / STAKE_STEP), 0)
	while true:
		var s := STAKE_STEP * 0.5 + k * STAKE_STEP
		if s >= s1 or s > total - 0.05:
			break
		if s >= s0:
			rng.seed = hash([seed_value, k])
			var p: Vector2 = _frame(c, s)[0]
			var height := STAKE_H + rng.randf_range(-0.12, 0.12)
			var r := STAKE_R * rng.randf_range(0.88, 1.05)
			var dir := Vector3(rng.randf_range(-0.03, 0.03), 1.0, rng.randf_range(-0.03, 0.03)).normalized()
			var shade := 1.0 + rng.randf_range(-0.1, 0.08)
			var color := Color(wood.r * shade, wood.g * shade, wood.b * shade)
			var foot := Vector3(p.x, _height(p) - STAKE_SINK, p.y)
			var head := foot + dir * (height + STAKE_SINK)
			g.rod("log", foot, head, r, r * 0.94, 6, color, false)
			g.rod("log", head, head + dir * 0.36, r * 0.94, 0.0, 6, color.lightened(0.12), false)
		k += 1
	var dark: Color = GameData.MATERIALS["log_dark"]["color"]
	var off := STAKE_R + 0.07
	var j := maxi(ceili(s0 / RAIL_STEP - 0.001), 0)
	while true:
		var a := j * RAIL_STEP
		if a >= s1 or a >= total - 0.01:
			break
		var b := minf(a + RAIL_STEP, total)
		var fa := _frame(c, a)
		var fb := _frame(c, b)
		var pa: Vector2 = fa[0] + Vector2(-(fa[1] as Vector2).y, (fa[1] as Vector2).x) * -off
		var pb: Vector2 = fb[0] + Vector2(-(fb[1] as Vector2).y, (fb[1] as Vector2).x) * -off
		var ha := _height(fa[0])
		var hb := _height(fb[0])
		for rail_y: float in RAILS:
			g.rod("log_dark", Vector3(pa.x, ha + rail_y, pa.y), Vector3(pb.x, hb + rail_y, pb.y), 0.065, 0.065, 5,
				dark.lightened(0.04 * (j % 3)), true)
		j += 1
