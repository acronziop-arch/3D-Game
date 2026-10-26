class_name BuildingFactory
extends RefCounted
## Генератор моделей зданий в «игрушечном» стиле: кладка из отдельных скошенных
## камней со швами, угловые камни, обшивка досками, окна в рамах с голубым стеклом,
## дощатые двери, крыши из рядов гонта или черепицы.
##
## Результат сохраняет в models/buildings/<id>.glb инструмент tools/export_models.gd.
## Правило: каждая деталь помечена материалом из GameData.MATERIALS, и все
## материалы модели обязаны быть в стоимости здания (это проверяет тест).
##
## Оси: +Z — фасад, Y — вверх, 0 — уровень земли. Цоколь уходит под землю.
##
## Двери и окна помечены (Geo.tag = "opening"): в превью стройки они видны
## другим оттенком. Окна без стекла — открытые: тёмная комната и распахнутые ставни.

const GD := preload("res://scripts/autoload/game_data.gd")

const BASE := 0.3
const UNDER := -1.3

const STYLES := {
	"stone_block": {"mat": "stone_block", "course": 0.38, "len": 0.62, "var": 0.34, "depth": 0.08, "bevel": 0.07, "gap": 0.05},
	"stone": {"mat": "stone", "course": 0.34, "len": 0.5, "var": 0.45, "depth": 0.1, "bevel": 0.085, "gap": 0.055},
	"brick": {"mat": "brick", "course": 0.25, "len": 0.56, "var": 0.06, "depth": 0.045, "bevel": 0.035, "gap": 0.034},
	"plank": {"mat": "plank", "course": 0.25, "len": 2.6, "var": 0.4, "depth": 0.04, "bevel": 0.026, "gap": 0.028},
	"plank_v": {"mat": "plank", "course": 0.27, "len": 0.0, "var": 0.0, "depth": 0.04, "bevel": 0.026, "gap": 0.028},
	"log": {"mat": "log", "course": 0.34, "len": 0.0, "var": 0.0, "depth": 0.0, "bevel": 0.0, "gap": 0.0},
	# Крупная кладка крепостных стен (меньше камней — легче для телефона).
	"stone_big": {"mat": "stone_block", "course": 0.55, "len": 1.0, "var": 0.35, "depth": 0.1, "bevel": 0.09, "gap": 0.06},
	"brick_big": {"mat": "brick", "course": 0.32, "len": 0.72, "var": 0.06, "depth": 0.05, "bevel": 0.04, "gap": 0.04},
}

const ROTOR_PIVOT := {"windmill": Vector3(0, 8.35, 2.85)}

## Здания строятся в «полный» размер, а в игру попадают уменьшенными, чтобы
## одноэтажный дом был заметно ниже деревьев. Настил и мосты — по размеру воды и рек.
const MODEL_SCALE := 0.72
const FULL_SIZE := ["platform", "bridge_wood", "bridge_stone", "campfire", "torch", "fence_stone",
	"path_dirt", "path_wood", "path_stone", "path_brick", "garden_bed", "vegetable_garden"]


static func scale_of(id: String) -> float:
	return 1.0 if id in FULL_SIZE else MODEL_SCALE


static func col(mat: String, rng: RandomNumberGenerator, amount := 0.07) -> Color:
	var c: Color = GD.MATERIALS[mat]["color"]
	var k := 1.0 + rng.randf_range(-amount, amount)
	var warm := rng.randf_range(-0.015, 0.015)
	return Color(c.r * k + warm, c.g * k, c.b * k - warm)


## {"static": Geo, "rotor": Geo или null, "pivot": Vector3}
static func build(id: String) -> Dictionary:
	var g := Geo.new()
	g.with_uv2 = false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var rotor: Geo = null
	match id:
		"hut": _hut(g, rng)
		"wood_house": _wood_house(g, rng)
		"stone_house": _stone_house(g, rng)
		"brick_house": _brick_house(g, rng)
		"barn": _barn(g, rng)
		"tent": _tent(g, rng)
		"sawmill": _sawmill(g, rng)
		"stonemason": _stonemason(g, rng)
		"kiln": _kiln(g, rng)
		"tannery": _tannery(g, rng)
		"weaver": _weaver(g, rng)
		"glassworks": _glassworks(g, rng)
		"smithy": _smithy(g, rng)
		"well": _well(g, rng)
		"market": _market(g, rng)
		"chapel": _chapel(g, rng)
		"church": _church(g, rng)
		"windmill":
			_windmill(g, rng)
			rotor = Geo.new()
			rotor.with_uv2 = false
			_windmill_rotor(rotor, rng)
		"cannon": _cannon(g, rng)
		"watchtower": _watchtower(g, rng)
		"palisade": _palisade(g, rng)
		"keep": _keep(g, rng)
		"platform": _platform(g, rng)
		"bridge_wood": _bridge_wood(g, rng)
		"bridge_stone": _bridge_stone(g, rng)
		"fort_wood": _fort_wood(g, rng)
		"castle": _castle(g, rng)
		"citadel": _citadel(g, rng)
		"campfire": _campfire(g, rng)
		"torch": _torch(g, rng)
		"fence_stone": _fence_stone(g, rng)
		"path_dirt", "path_wood", "path_stone", "path_brick": _path(g, rng, id.substr(5))
		"garden_bed": _garden_bed(g, rng)
		"vegetable_garden": _vegetable_garden(g, rng)
		_:
			push_warning("Нет генератора здания: %s" % id)
			g.box("plank", Vector3(0, 1, 0), Vector3(2, 2, 2), Color.MAGENTA)
	var k := scale_of(id)
	if k != 1.0:
		g.scale_all(k)
		if rotor:
			rotor.scale_all(k)
	return {"static": g, "rotor": rotor, "pivot": ROTOR_PIVOT.get(id, Vector3.ZERO) * k}


# =====================================================================================
#  Стены
# =====================================================================================

## Базис стены: x — вдоль стены, y — вверх, z — наружу.
static func wall_frame(origin: Vector3, along: Vector3) -> Transform3D:
	along = along.normalized()
	return Transform3D(Basis(along, Vector3.UP, along.cross(Vector3.UP)), origin)


static func _free_segments(a: float, b: float, v0: float, v1: float, holes: Array) -> Array[Vector2]:
	var segs: Array[Vector2] = [Vector2(a, b)]
	for h: Rect2 in holes:
		if h.position.y >= v1 - 0.001 or h.end.y <= v0 + 0.001:
			continue
		var next: Array[Vector2] = []
		for s in segs:
			if h.end.x <= s.x or h.position.x >= s.y:
				next.append(s)
				continue
			if h.position.x > s.x:
				next.append(Vector2(s.x, h.position.x))
			if h.end.x < s.y:
				next.append(Vector2(h.end.x, s.y))
		segs = next
	return segs


## Тело стены в текущей системе координат (после g.push(wall_frame(...))).
## holes — Rect2(u, v, ширина, высота) в координатах стены. Возвращает проёмы,
## подогнанные к рядам кладки (под них потом ставятся рамы).
static func wall_body(g: Geo, rng: RandomNumberGenerator, length: float, height: float, style: String,
		holes: Array = [], thickness := 0.4, row_offset := 0) -> Array:
	var s: Dictionary = STYLES[style]
	var ch: float = s["course"]
	var courses := maxi(1, roundi(height / ch))
	ch = height / courses
	var snapped := []
	for h: Rect2 in holes:
		var v0 := floorf(h.position.y / ch + 0.001) * ch
		var v1 := minf(ceilf(h.end.y / ch - 0.001) * ch, height)
		snapped.append(Rect2(h.position.x, v0, h.size.x, v1 - v0))
	var mat: String = s["mat"]
	if style == "plank_v":
		_vertical_boards(g, rng, length, height, snapped, thickness, s)
		return snapped
	for row in courses:
		var v := row * ch
		for seg in _free_segments(0.0, length, v, v + ch, snapped):
			if seg.y - seg.x < 0.05:
				continue
			if style == "log":
				var r := ch * 0.55
				var ext0 := 0.3 if seg.x < 0.01 else 0.0
				var ext1 := 0.3 if seg.y > length - 0.01 else 0.0
				g.rod(mat, Vector3(seg.x - ext0, v + r, -thickness * 0.5), Vector3(seg.y + ext1, v + r, -thickness * 0.5),
					r, r, 8, col(mat, rng, 0.08))
				continue
			var core := col(mat, rng, 0.02).darkened(0.28)
			g.box(mat, Vector3((seg.x + seg.y) * 0.5, v + ch * 0.5, -thickness * 0.5), Vector3(seg.y - seg.x, ch, thickness), core)
			_course_tiles(g, rng, s, seg.x, seg.y, v, ch, row + row_offset)
	return snapped


static func _course_tiles(g: Geo, rng: RandomNumberGenerator, s: Dictionary, u0: float, u1: float, v: float, ch: float, row: int) -> void:
	var mat: String = s["mat"]
	var gap: float = s["gap"]
	var stony := mat in ["stone", "stone_block", "slate"]
	var u := u0
	var first := true
	while u < u1 - 0.04:
		var length: float = s["len"] * (1.0 + rng.randf_range(-s["var"], s["var"]))
		if first and row % 2 == 1:
			length *= 0.5
		first = false
		var e := minf(u + length, u1)
		if u1 - e < s["len"] * 0.3:
			e = u1
		var tw := e - u - gap
		var cx := (u + e) * 0.5
		if tw > 0.06 and stony:
			var room := ch - gap
			if tw > 0.32 and rng.randf() < 0.22:
				# Иногда на месте одного камня — два поменьше, друг над другом.
				var split := rng.randf_range(0.38, 0.62)
				var h0 := room * split - gap * 0.5
				var h1 := room - h0 - gap
				_stone(g, rng, s, cx, v + gap * 0.5 + h0 * 0.5, tw, h0)
				_stone(g, rng, s, cx + rng.randf_range(-0.04, 0.04), v + gap * 0.5 + h0 + gap + h1 * 0.5, tw * rng.randf_range(0.82, 1.0), h1)
			else:
				var th := room * rng.randf_range(0.82, 1.0)
				_stone(g, rng, s, cx, v + ch * 0.5 + rng.randf_range(-0.5, 0.5) * (room - th), tw, th)
		elif tw > 0.06:
			g.tile(mat, Vector3(cx, v + ch * 0.5, 0), Vector3.BACK, Vector3.UP, tw, ch - gap,
				s["depth"] * rng.randf_range(0.8, 1.2), s["bevel"], col(mat, rng))
		u = e


## Один камень кладки: свой размер, выступ, наклон и оттенок — стена выглядит живой.
static func _stone(g: Geo, rng: RandomNumberGenerator, s: Dictionary, cx: float, cy: float, w: float, h: float) -> void:
	var mat: String = s["mat"]
	var c := col(mat, rng, 0.11)
	var pick := rng.randf()
	if pick < 0.13:
		c = c.lightened(0.13)
	elif pick < 0.26:
		c = c.darkened(0.14)
	elif pick < 0.36:
		c = Color(c.r * 1.06, c.g * 1.01, c.b * 0.9)
	elif pick < 0.44:
		c = Color(c.r * 0.94, c.g * 0.98, c.b * 1.06)
	var tilt := rng.randf_range(-0.045, 0.045)
	g.tile(mat, Vector3(cx, cy, 0), Vector3.BACK, Vector3(sin(tilt), cos(tilt), 0), w, h,
		s["depth"] * rng.randf_range(0.65, 1.45), s["bevel"] * rng.randf_range(0.9, 1.35), c)


static func _vertical_boards(g: Geo, rng: RandomNumberGenerator, length: float, height: float, holes: Array, thickness: float, s: Dictionary) -> void:
	var mat: String = s["mat"]
	var bw: float = s["course"]
	var count := maxi(1, roundi(length / bw))
	bw = length / count
	g.box(mat, Vector3(length * 0.5, height * 0.5, -thickness * 0.5), Vector3(length, height, thickness), col(mat, rng, 0.02).darkened(0.3))
	for i in count:
		var u0 := i * bw
		var u1 := u0 + bw
		var spans: Array[Vector2] = [Vector2(0, height)]
		for h: Rect2 in holes:
			if h.end.x <= u0 or h.position.x >= u1:
				continue
			var next: Array[Vector2] = []
			for sp in spans:
				if h.position.y > sp.x:
					next.append(Vector2(sp.x, minf(h.position.y, sp.y)))
				if h.end.y < sp.y:
					next.append(Vector2(maxf(h.end.y, sp.x), sp.y))
			spans = next
		for sp in spans:
			if sp.y - sp.x > 0.1:
				g.tile(mat, Vector3((u0 + u1) * 0.5, (sp.x + sp.y) * 0.5, 0), Vector3.BACK, Vector3.UP,
					bw - s["gap"], sp.y - sp.x - 0.02, s["depth"], s["bevel"], col(mat, rng))


## Окно в рамке. rect — проём в координатах стены (как вернул wall_body).
## glass = false — окно без стекла: тёмная комната и распахнутые ставни
## (стекло — отдельный ресурс, у простых домов его нет в стоимости).
static func window(g: Geo, rng: RandomNumberGenerator, rect: Rect2, frame_mat: String, glass: bool, thickness := 0.4, sill_mat := "",
		stained := false) -> void:
	var f := 0.09
	var depth := 0.09
	var c := col(frame_mat, rng, 0.03)
	var x0 := rect.position.x
	var x1 := rect.end.x
	var y0 := rect.position.y
	var y1 := rect.end.y
	var cx := (x0 + x1) * 0.5
	var prev_tag := g.tag
	g.tag = "opening"
	g.begin()
	g.box(frame_mat, Vector3(cx, y1 - f * 0.5, depth * 0.3), Vector3(rect.size.x + f, f, depth * 1.6), c, 0.025)
	g.box(frame_mat, Vector3(x0 + f * 0.5, (y0 + y1) * 0.5, depth * 0.3), Vector3(f, rect.size.y, depth * 1.6), c, 0.025)
	g.box(frame_mat, Vector3(x1 - f * 0.5, (y0 + y1) * 0.5, depth * 0.3), Vector3(f, rect.size.y, depth * 1.6), c, 0.025)
	var sm := sill_mat if sill_mat != "" else frame_mat
	g.box(sm, Vector3(cx, y0 + f * 0.4, depth * 0.6), Vector3(rect.size.x + f * 2.2, f * 0.9, depth * 2.4), col(sm, rng, 0.03), 0.03)
	if glass and stained:
		# Витраж: мозаика из цветных стёкол.
		var palette := [Color(0.3, 0.45, 0.85), Color(0.8, 0.25, 0.25), Color(0.95, 0.75, 0.25), Color(0.3, 0.65, 0.4), Color(0.55, 0.35, 0.75)]
		var rows := maxi(2, roundi(rect.size.y / 0.35))
		var pw := (rect.size.x - f) / 2.0
		var ph := (rect.size.y - f) / rows
		for r in rows:
			for k in 2:
				g.pane = Vector2(pw - 0.02, ph - 0.02)
				g.box("glass", Vector3(x0 + f * 0.5 + (k + 0.5) * pw, y0 + f * 0.5 + (r + 0.5) * ph, -thickness * 0.35),
					Vector3(pw - 0.02, ph - 0.02, 0.05), palette[rng.randi() % palette.size()])
		g.pane = Vector2.ZERO
	elif glass:
		g.pane = Vector2(rect.size.x - f, rect.size.y - f)
		g.box("glass", Vector3(cx, (y0 + y1) * 0.5, -thickness * 0.35), Vector3(rect.size.x - f, rect.size.y - f, 0.05),
			col("glass", rng, 0.06))
		g.pane = Vector2.ZERO
	if glass:
		g.box(frame_mat, Vector3(cx, (y0 + y1) * 0.5, -thickness * 0.3), Vector3(0.05, rect.size.y - f, 0.08), c)
		if rect.size.y > 0.7:
			g.box(frame_mat, Vector3(cx, (y0 + y1) * 0.5 + 0.03, -thickness * 0.3), Vector3(rect.size.x - f, 0.05, 0.08), c)
	else:
		# Тёмная комната за проёмом (вечером в ней теплится свет) и распахнутые ставни.
		g.box("opening", Vector3(cx, (y0 + y1) * 0.5, -thickness * 0.55), Vector3(rect.size.x - f, rect.size.y - f, 0.05),
			GD.MATERIALS["opening"]["color"])
		var shutter := frame_mat if GD.MATERIALS.has(frame_mat) and (frame_mat.begins_with("plank") or frame_mat.begins_with("log")) \
			else "plank_dark"
		if not shutter.ends_with("_dark") and GD.MATERIALS.has(shutter + "_dark"):
			shutter += "_dark"
		var sw := rect.size.x * 0.5
		var sh := rect.size.y - f * 0.6
		for side: float in [-1.0, 1.0]:
			var open := deg_to_rad(150.0)
			var dir := Vector3(-side * cos(open), 0.0, sin(open))
			var hinge := Vector3(x0 if side < 0.0 else x1, (y0 + y1) * 0.5, 0.07)
			var normal := Vector3(dir.z, 0.0, -dir.x) * -side
			var basis := Basis(dir, Vector3.UP, normal)
			var boards := 3
			for b in boards:
				var along := (b + 0.5) * sw / boards
				g.box(shutter, hinge + dir * along, Vector3(sw / boards - 0.018, sh, 0.045), col(shutter, rng), 0.012, basis)
			g.box(shutter, hinge + dir * sw * 0.5 + Vector3(0, sh * 0.28, 0) + normal * 0.03, Vector3(sw * 0.9, 0.07, 0.03),
				col(shutter, rng).darkened(0.12), 0.01, basis)
	g.end()
	g.tag = prev_tag


## Дверь из вертикальных досок в рамке.
static func door(g: Geo, rng: RandomNumberGenerator, rect: Rect2, door_mat: String, frame_mat: String, thickness := 0.4) -> void:
	var f := 0.1
	var c := col(frame_mat, rng, 0.03)
	var x0 := rect.position.x
	var x1 := rect.end.x
	var y1 := rect.end.y
	var cx := (x0 + x1) * 0.5
	var prev_tag := g.tag
	g.tag = "opening"
	g.begin()
	g.box(frame_mat, Vector3(cx, y1 - f * 0.5, 0.04), Vector3(rect.size.x + f, f, 0.16), c, 0.03)
	g.box(frame_mat, Vector3(x0 + f * 0.5, rect.position.y + rect.size.y * 0.5, 0.04), Vector3(f, rect.size.y, 0.16), c, 0.03)
	g.box(frame_mat, Vector3(x1 - f * 0.5, rect.position.y + rect.size.y * 0.5, 0.04), Vector3(f, rect.size.y, 0.16), c, 0.03)
	var inner_w := rect.size.x - f * 2
	var boards := maxi(2, roundi(inner_w / 0.2))
	var bw := inner_w / boards
	var plane := -0.08
	g.box(door_mat, Vector3(cx, rect.position.y + (rect.size.y - f) * 0.5, plane - 0.03), Vector3(inner_w, rect.size.y - f, 0.06),
		col(door_mat, rng, 0.02).darkened(0.35))
	for b in boards:
		var bx := x0 + f + (b + 0.5) * bw
		g.tile(door_mat, Vector3(bx, rect.position.y + (rect.size.y - f) * 0.5, plane), Vector3.BACK, Vector3.UP,
			bw - 0.025, rect.size.y - f - 0.02, 0.035, 0.012, col(door_mat, rng, 0.06))
	for y: float in [0.3, 0.75]:
		g.tile(door_mat, Vector3(cx, rect.position.y + (rect.size.y - f) * y, plane + 0.035), Vector3.BACK, Vector3.UP,
			inner_w - 0.06, 0.1, 0.025, 0.01, col(door_mat, rng, 0.03).darkened(0.12))
	g.blob(door_mat, Vector3(x1 - f - 0.12, rect.position.y + rect.size.y * 0.47, plane + 0.08), Vector3.ONE * 0.045,
		col(door_mat, rng).darkened(0.45), rng, 0, 0.0, 0.1)
	g.end()
	g.tag = prev_tag


## Угловые камни (перевязка углов), как на референсе крепости.
static func quoins(g: Geo, rng: RandomNumberGenerator, w: float, d: float, y0: float, height: float, mat: String, course: float) -> void:
	var courses := maxi(1, roundi(height / course))
	course = height / courses
	var dp := 0.085
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			for i in courses:
				var long := (i + int(sx > 0) + int(sz > 0)) % 2 == 0
				var qa := 0.62 if long else 0.4
				var qb := 0.4 if long else 0.62
				var c := col(mat, rng, 0.06).lightened(0.04)
				g.box(mat, Vector3(sx * (w * 0.5 - qa * 0.5 + dp), y0 + (i + 0.5) * course, sz * (d * 0.5 - qb * 0.5 + dp)),
					Vector3(qa, course - 0.04, qb), c, 0.05)


## Четыре стены прямоугольного здания с проёмами.
## openings: [{"side": "front"|"back"|"left"|"right", "u": смещение от центра стены,
##   "v": низ проёма, "w": ширина, "h": высота, "type": "window"|"door"}]
static func walls(g: Geo, rng: RandomNumberGenerator, w: float, d: float, y0: float, height: float, style: String,
		openings: Array = [], opts := {}) -> void:
	var thickness: float = opts.get("thickness", 0.4)
	var frame_mat: String = opts.get("frame", "plank")
	var door_mat: String = opts.get("door", "plank_dark")
	var glass: bool = opts.get("glass", false)
	var sides := {
		"front": [Vector3(-w * 0.5, y0, d * 0.5), Vector3.RIGHT, w],
		"right": [Vector3(w * 0.5, y0, d * 0.5), Vector3.FORWARD, d],
		"back": [Vector3(w * 0.5, y0, -d * 0.5), Vector3.LEFT, w],
		"left": [Vector3(-w * 0.5, y0, -d * 0.5), Vector3.BACK, d],
	}
	var row_offsets := {"front": 0, "right": 1, "back": 0, "left": 1}
	for side: String in sides:
		var info: Array = sides[side]
		var length: float = info[2]
		var holes := []
		var kinds := []
		for o: Dictionary in openings:
			if o["side"] != side:
				continue
			holes.append(Rect2(length * 0.5 + o["u"] - o["w"] * 0.5, o.get("v", 0.0), o["w"], o["h"]))
			kinds.append(o.get("type", "window"))
		g.push(wall_frame(info[0], info[1]))
		var snapped := wall_body(g, rng, length, height, style, holes, thickness, row_offsets[side])
		for i in snapped.size():
			if kinds[i] == "door":
				door(g, rng, snapped[i], door_mat, frame_mat, thickness)
			else:
				window(g, rng, snapped[i], frame_mat, glass, thickness, opts.get("sill", ""), opts.get("stained", false))
		g.pop()
	if opts.get("quoins", false):
		quoins(g, rng, w, d, y0, height, STYLES[style]["mat"], STYLES[style]["course"])
	if opts.has("corner_trim"):
		var tm: String = opts["corner_trim"]
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				g.box(tm, Vector3(sx * (w * 0.5 + 0.02), y0 + height * 0.5, sz * (d * 0.5 + 0.02)), Vector3(0.2, height, 0.2), col(tm, rng, 0.03), 0.03)


## Цоколь: массивный блок под землёй и ряд крупных камней над ней.
static func plinth(g: Geo, rng: RandomNumberGenerator, w: float, d: float, mat := "stone", top := BASE) -> void:
	g.box(mat, Vector3(0, (UNDER + top) * 0.5, 0), Vector3(w, top - UNDER, d), col(mat, rng, 0.02).darkened(0.3))
	var style := "stone" if mat == "stone" else "stone_block"
	var s: Dictionary = STYLES[style].duplicate()
	s["len"] = 0.7
	var sides := [
		[Vector3(-w * 0.5, 0, d * 0.5), Vector3.RIGHT, w], [Vector3(w * 0.5, 0, d * 0.5), Vector3.FORWARD, d],
		[Vector3(w * 0.5, 0, -d * 0.5), Vector3.LEFT, w], [Vector3(-w * 0.5, 0, -d * 0.5), Vector3.BACK, d],
	]
	for info: Array in sides:
		g.push(wall_frame(info[0], info[1]))
		_course_tiles(g, rng, s, 0.0, info[2], -0.25, top + 0.25, 0)
		g.pop()


# =====================================================================================
#  Крыши
# =====================================================================================

## Двускатная крыша, конёк вдоль X. top — центр верха стен.
## style: "shingle" (ряды гонта), "boards" (доски вдоль ската), "tile" (черепица).
static func gable_roof(g: Geo, rng: RandomNumberGenerator, top: Vector3, w: float, d: float, rise: float, mat: String,
		style := "shingle", overhang := 0.45, gable_style := "", gable_mat := "") -> void:
	var half := d * 0.5 + overhang
	var drop := overhang * rise / (d * 0.5)
	var slope_len := Vector2(half, rise + drop).length()
	var angle := atan2(rise + drop, half)
	var length := w + overhang * 2.0
	for s: float in [-1.0, 1.0]:
		var eave := top + Vector3(0, -drop, s * half)
		var ridge := top + Vector3(0, rise, 0)
		var mid := (eave + ridge) * 0.5
		var basis := Basis(Vector3.RIGHT, s * angle)
		var normal := basis * Vector3.UP
		var down := (eave - ridge).normalized()
		g.box(mat, mid - normal * 0.09, Vector3(length, 0.18, slope_len), col(mat, rng, 0.02).darkened(0.3), 0.0, basis)
		match style:
			"boards":
				var count := maxi(2, roundi(length / 0.5))
				var bw := length / count
				for i in count:
					var x := -length * 0.5 + (i + 0.5) * bw
					g.tile(mat, mid + Vector3(x, 0, 0), normal, -down, bw - 0.03, slope_len - 0.02, 0.06, 0.025, col(mat, rng, 0.08))
			"tile":
				var rows := maxi(2, roundi(slope_len / 0.38))
				var rh := slope_len / rows
				for r in rows:
					var center := eave - down * (r + 0.5) * rh
					var count := maxi(2, roundi(length / 0.44))
					var tw := length / count
					for i in count:
						var x := -length * 0.5 + (i + 0.5 + (0.5 if r % 2 == 1 else 0.0)) * tw
						if x > length * 0.5 - tw * 0.3:
							continue
						g.tile(mat, center + Vector3(x, 0, 0) + normal * 0.0, normal, -down, tw - 0.03, rh + 0.04, 0.07, 0.03, col(mat, rng, 0.07))
			_:
				var rows := maxi(2, roundi(slope_len / 0.4))
				var rh := slope_len / rows
				for r in rows:
					var center := eave - down * (r + 0.5) * rh
					var x := -length * 0.5
					var first := true
					while x < length * 0.5 - 0.05:
						var sw := rng.randf_range(0.45, 0.9)
						if first and r % 2 == 1:
							sw *= 0.5
						first = false
						var e := minf(x + sw, length * 0.5)
						if length * 0.5 - e < 0.2:
							e = length * 0.5
						g.tile(mat, center + Vector3((x + e) * 0.5, 0, 0) + down * 0.03, normal + down * 0.12, -down,
							e - x - 0.03, rh + 0.06, 0.06, 0.025, col(mat, rng, 0.08))
						x = e
	g.box(mat, top + Vector3(0, rise + 0.07, 0), Vector3(length + 0.14, 0.26, 0.4), col(mat, rng, 0.03).darkened(0.1), 0.09)
	if gable_style != "":
		for sx: float in [-1.0, 1.0]:
			gable_fill(g, rng, top + Vector3(sx * w * 0.5, 0, 0), d, rise, gable_style, Vector3(sx, 0, 0), gable_mat)


## Заполнение фронтона (треугольник под крышей) тем же стилем, что и стены.
static func gable_fill(g: Geo, rng: RandomNumberGenerator, base: Vector3, width: float, rise: float, style: String, outward: Vector3, mat_override := "") -> void:
	var s: Dictionary = STYLES[style].duplicate()
	if mat_override != "":
		s["mat"] = mat_override
	var mat: String = s["mat"]
	var along := Vector3.UP.cross(outward).normalized()
	g.push(wall_frame(base - along * width * 0.5, along))
	var ch: float = s["course"] if style != "log" else 0.34
	var rows := maxi(1, roundi(rise / ch))
	ch = rise / rows
	for r in rows:
		var v := r * ch
		var hw := width * 0.5 * (1.0 - (v + ch) / rise)
		if hw < 0.08:
			hw = 0.08
		var u0 := width * 0.5 - hw
		var u1 := width * 0.5 + hw
		if style == "log":
			g.rod(mat, Vector3(u0, v + ch * 0.5, -0.2), Vector3(u1, v + ch * 0.5, -0.2), ch * 0.5, ch * 0.5, 7, col(mat, rng))
			continue
		g.box(mat, Vector3(width * 0.5, v + ch * 0.5, -0.2), Vector3(u1 - u0, ch, 0.4), col(mat, rng, 0.02).darkened(0.3))
		if style == "plank_v":
			var count := maxi(1, roundi((u1 - u0) / 0.27))
			var bw := (u1 - u0) / count
			for i in count:
				g.tile(mat, Vector3(u0 + (i + 0.5) * bw, v + ch * 0.5, 0), Vector3.BACK, Vector3.UP, bw - 0.025, ch - 0.01, 0.035, 0.015, col(mat, rng))
		else:
			_course_tiles(g, rng, s, u0, u1, v, ch, r)
	g.pop()


## Четырёхскатная крыша-шатёр (пирамида) из рядов гонта.
static func pyramid_roof(g: Geo, rng: RandomNumberGenerator, top: Vector3, half: float, rise: float, mat: String, overhang := 0.35) -> void:
	var hb := half + overhang
	var apex := top + Vector3(0, rise, 0)
	for side in 4:
		var yaw := Basis(Vector3.UP, side * PI * 0.5)
		var e0 := top + yaw * Vector3(-hb, -overhang * 0.4, hb)
		var e1 := top + yaw * Vector3(hb, -overhang * 0.4, hb)
		var normal := (e1 - e0).cross(apex - e0).normalized() * -1.0
		if normal.y < 0.0:
			normal = -normal
		g.tri(mat, e0, e1, apex, col(mat, rng, 0.02).darkened(0.3), normal)
		var rows := maxi(2, roundi((apex - e0).length() / 0.4))
		for r in rows:
			var t0 := float(r) / rows
			var t1 := float(r + 1) / rows
			var a := e0.lerp(apex, t0)
			var b := e1.lerp(apex, t0)
			var a1 := e0.lerp(apex, t1)
			var row_center := (a + b + a1 + e1.lerp(apex, t1)) * 0.25
			var width := a.distance_to(b)
			var up := (a1 - a).normalized()
			var count := maxi(1, roundi(width / 0.6))
			for i in count:
				var x := (i + 0.5) / count - 0.5
				var cw := width / count
				var right := (b - a).normalized()
				g.tile(mat, row_center + right * x * width * (1.0 - 0.5 / rows) + normal * 0.02, normal + up * -0.1, up,
					cw * (1.0 - t0 * 0.6) - 0.03, a.distance_to(a1) + 0.05, 0.05, 0.02, col(mat, rng, 0.08))


## Тело вращения: profile — массив Vector2(радиус, высота) снизу вверх.
static func lathe(g: Geo, mat: String, center: Vector3, profile: Array, segments: int, rng: RandomNumberGenerator, amount := 0.04) -> void:
	g.begin()
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var c := col(mat, rng, amount)
		for k in segments:
			var a0 := TAU * k / segments
			var a1 := TAU * (k + 1) / segments
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var v00 := center + d0 * p0.x + Vector3(0, p0.y, 0)
			var v10 := center + d1 * p0.x + Vector3(0, p0.y, 0)
			var v01 := center + d0 * p1.x + Vector3(0, p1.y, 0)
			var v11 := center + d1 * p1.x + Vector3(0, p1.y, 0)
			var mid := (d0 + d1).normalized()
			var ref := mid * (p1.y - p0.y) + Vector3(0, p0.x - p1.x, 0)
			if ref.length_squared() < 1e-6:
				ref = Vector3.UP if p1.y >= p0.y else Vector3.DOWN
			if p1.x < 0.001:
				g.tri(mat, v00, v10, v01, c, ref)
			elif p0.x < 0.001:
				g.tri(mat, v00, v11, v01, c, ref)
			else:
				g.quad(mat, v00, v10, v11, v01, c, ref)
	g.end()


## Круглая стена (башня мельницы, колодец, печь) из камней на цилиндре.
## openings: [{"angle": рад, "v": низ, "w": ширина (м), "h": высота, "type": "window"|"door"}]
static func round_wall(g: Geo, rng: RandomNumberGenerator, base: Vector3, r0: float, r1: float, height: float, style: String,
		openings: Array = [], opts := {}) -> void:
	var s: Dictionary = STYLES[style]
	var mat: String = s["mat"]
	var ch: float = s["course"]
	var courses := maxi(1, roundi(height / ch))
	ch = height / courses
	for row in courses:
		var v := row * ch
		var ra := lerpf(r0, r1, v / height)
		var rb := lerpf(r0, r1, (v + ch) / height)
		var rm := (ra + rb) * 0.5
		lathe(g, mat, base, [Vector2(ra, v), Vector2(rb, v + ch)], 16, rng, 0.0)
		var circ := TAU * rm
		var count := maxi(6, roundi(circ / s["len"]))
		var step := TAU / count
		var phase := (row % 2) * step * 0.5
		for i in count:
			var a := phase + i * step + rng.randf_range(-0.04, 0.04)
			var blocked := false
			for o: Dictionary in openings:
				var half: float = (o["w"] * 0.5 + 0.12) / rm
				if absf(wrapf(a - o["angle"], -PI, PI)) < half + step * 0.4 and v + ch > o.get("v", 0.0) and v < o.get("v", 0.0) + o["h"]:
					blocked = true
			if blocked:
				continue
			var dir := Vector3(cos(a), 0, sin(a))
			var slope := Vector3(0, ch, 0) + dir * (rb - ra)
			g.tile(mat, base + dir * rm + Vector3(0, v + ch * 0.5, 0), dir - slope.normalized() * dir.dot(slope.normalized()), slope,
				circ / count - s["gap"], ch - s["gap"], s["depth"], s["bevel"], col(mat, rng))
	# Проёмы в круглой стене не вырезаются: рамы, стекло и двери ставятся на поверхность.
	for o: Dictionary in openings:
		var a: float = o["angle"]
		var v: float = o.get("v", 0.0)
		var r := lerpf(r0, r1, (v + o["h"] * 0.5) / height)
		var dir := Vector3(cos(a), 0, sin(a))
		var along := Vector3.UP.cross(dir)
		var is_door: bool = o.get("type", "window") == "door"
		var lift := 0.12 if is_door else 0.0
		g.push(wall_frame(base + dir * (r + lift) - along * o["w"] * 0.5, along))
		var rect := Rect2(0, v, o["w"], o["h"])
		if is_door:
			door(g, rng, rect, opts.get("door", "plank_dark"), opts.get("frame", "plank"), 0.3)
		else:
			window(g, rng, rect, opts.get("frame", "plank"), opts.get("glass", false), -0.1)
		g.pop()


# =====================================================================================
#  Здания
# =====================================================================================

static func _hut(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 4.0
	var d := 3.4
	g.box("log", Vector3(0, (UNDER + 0.15) * 0.5, 0), Vector3(w + 0.4, 0.15 - UNDER, d + 0.4), col("log", rng).darkened(0.3))
	walls(g, rng, w, d, 0.15, 2.4, "log", [
		{"side": "front", "u": 0.0, "w": 0.95, "h": 1.75, "type": "door"},
		{"side": "left", "u": 0.0, "v": 0.9, "w": 0.6, "h": 0.6},
	], {"frame": "log_dark", "door": "log_dark", "thickness": 0.34})
	gable_roof(g, rng, Vector3(0, 2.55, 0), w, d, 1.5, "log_dark", "boards", 0.45, "log", "")


static func _wood_house(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 4.6
	var d := 3.8
	plinth(g, rng, w + 0.3, d + 0.3, "stone")
	walls(g, rng, w, d, BASE, 2.6, "plank", [
		{"side": "front", "u": 0.8, "w": 0.95, "h": 1.9, "type": "door"},
		{"side": "front", "u": -1.0, "v": 0.85, "w": 0.95, "h": 0.95},
		{"side": "left", "u": 0.0, "v": 0.85, "w": 0.9, "h": 0.9},
		{"side": "right", "u": 0.0, "v": 0.85, "w": 0.9, "h": 0.9},
	], {"frame": "plank_dark", "door": "plank_dark", "corner_trim": "plank_dark"})
	gable_roof(g, rng, Vector3(0, BASE + 2.6, 0), w, d, 1.7, "plank", "boards", 0.5, "plank", "")
	g.box("log", Vector3(0, BASE + 2.6 + 1.75, 0), Vector3(w + 1.1, 0.22, 0.22), col("log", rng), 0.04)
	_chimney(g, rng, Vector3(1.2, BASE + 2.6, -0.7), 0.6, 2.2, "stone")


static func _chimney(g: Geo, rng: RandomNumberGenerator, base: Vector3, size: float, height: float, mat: String) -> void:
	var course: float = STYLES["brick" if mat == "brick" else ("stone" if mat == "stone" else "stone_block")]["course"]
	var rows := maxi(2, roundi(height / course))
	var rh := height / rows
	for r in rows:
		var jitter := Vector3(rng.randf_range(-0.02, 0.02), 0, rng.randf_range(-0.02, 0.02))
		g.box(mat, base + jitter + Vector3(0, (r + 0.5) * rh, 0), Vector3(size, rh - 0.03, size), col(mat, rng), 0.04,
			Basis(Vector3.UP, rng.randf_range(-0.04, 0.04)))
	g.box(mat, base + Vector3(0, height + 0.08, 0), Vector3(size + 0.15, 0.16, size + 0.15), col(mat, rng).darkened(0.05), 0.04)


static func _stone_house(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 5.0
	var d := 4.0
	plinth(g, rng, w + 0.3, d + 0.3, "stone_block")
	walls(g, rng, w, d, BASE, 3.0, "stone_block", [
		{"side": "front", "u": 0.0, "w": 1.0, "h": 2.0, "type": "door"},
		{"side": "front", "u": -1.55, "v": 1.0, "w": 0.8, "h": 1.1},
		{"side": "front", "u": 1.55, "v": 1.0, "w": 0.8, "h": 1.1},
		{"side": "left", "u": 0.0, "v": 1.0, "w": 0.8, "h": 1.1},
		{"side": "right", "u": 0.0, "v": 1.0, "w": 0.8, "h": 1.1},
	], {"frame": "stone_block", "door": "plank", "glass": true, "quoins": true})
	gable_roof(g, rng, Vector3(0, BASE + 3.04, 0), w, d, 1.9, "plank_dark", "shingle", 0.5, "stone_block", "")
	_chimney(g, rng, Vector3(-1.5, BASE + 3.0, -0.8), 0.65, 2.4, "stone_block")


static func _brick_house(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 5.2
	var d := 4.2
	plinth(g, rng, w + 0.3, d + 0.3, "stone_block")
	var ops := [
		{"side": "front", "u": 0.0, "w": 1.0, "h": 2.0, "type": "door"},
		{"side": "front", "u": -1.6, "v": 0.9, "w": 0.8, "h": 1.05},
		{"side": "front", "u": 1.6, "v": 0.9, "w": 0.8, "h": 1.05},
		{"side": "left", "u": 0.0, "v": 0.9, "w": 0.8, "h": 1.05},
		{"side": "right", "u": 0.0, "v": 0.9, "w": 0.8, "h": 1.05},
	]
	walls(g, rng, w, d, BASE, 2.3, "brick", ops, {"frame": "stone_block", "door": "plank", "glass": true, "quoins": true, "sill": "stone_block"})
	# Карниз между этажами.
	g.box("stone_block", Vector3(0, BASE + 2.37, 0), Vector3(w + 0.22, 0.16, d + 0.22), col("stone_block", rng), 0.04)
	walls(g, rng, w, d, BASE + 2.45, 2.1, "brick", [
		{"side": "front", "u": -1.6, "v": 0.5, "w": 0.8, "h": 1.05},
		{"side": "front", "u": 0.0, "v": 0.5, "w": 0.8, "h": 1.05},
		{"side": "front", "u": 1.6, "v": 0.5, "w": 0.8, "h": 1.05},
		{"side": "back", "u": 0.0, "v": 0.5, "w": 0.8, "h": 1.05},
	], {"frame": "stone_block", "glass": true, "quoins": true, "sill": "stone_block"})
	gable_roof(g, rng, Vector3(0, BASE + 4.6, 0), w, d, 2.0, "roof_tile", "tile", 0.45, "brick", "")
	_chimney(g, rng, Vector3(1.6, BASE + 4.6, -1.0), 0.65, 2.6, "brick")


static func _barn(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 6.6
	var d := 4.8
	plinth(g, rng, w + 0.3, d + 0.3, "stone")
	walls(g, rng, w, d, BASE, 3.2, "plank_v", [
		{"side": "front", "u": 0.0, "w": 2.4, "h": 2.6, "type": "door"},
		{"side": "left", "u": 0.0, "v": 1.6, "w": 0.8, "h": 0.8},
		{"side": "right", "u": 0.0, "v": 1.6, "w": 0.8, "h": 0.8},
	], {"frame": "log", "door": "plank_dark", "corner_trim": "log"})
	for a: float in [0.82, -0.82]:
		g.box("log", Vector3(0, BASE + 1.25, d * 0.5 + 0.12), Vector3(0.14, 2.7, 0.1), col("log", rng), 0.03, Basis(Vector3.BACK, a))
	gable_roof(g, rng, Vector3(0, BASE + 3.2, 0), w, d, 2.4, "plank_dark", "shingle", 0.5, "plank_v", "")


static func _tent(g: Geo, rng: RandomNumberGenerator) -> void:
	g.rod("log", Vector3(0, -0.5, 0), Vector3(0, 4.0, 0), 0.09, 0.07, 6, col("log", rng))
	for i in 3:
		var a := i * TAU / 3.0 + 0.3
		g.rod("log", Vector3(cos(a) * 0.1, 3.1, sin(a) * 0.1), Vector3(cos(a) * 0.35, 4.2, sin(a) * 0.35), 0.05, 0.04, 5, col("log", rng))
	var n := 8
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0) * 2.1, 0.05, sin(a0) * 2.1)
		var p1 := Vector3(cos(a1) * 2.1, 0.05, sin(a1) * 2.1)
		var apex := Vector3(0, 3.3, 0)
		var mid := (p0 + p1) * 0.5
		var c := col("leather", rng, 0.08) if i % 2 == 0 else col("leather", rng, 0.05).darkened(0.12)
		if i == 2:
			# Откинутый полог входа.
			g.tri("leather", p0, mid + Vector3(0, 1.3, 0) * 1.0 + (mid - Vector3.ZERO).normalized() * 0.35, apex, c, mid)
			g.tri("leather", mid, p1, apex, c, mid)
			continue
		g.tri("leather", p0, p1, apex, c, mid + Vector3(0, 1, 0))
		g.rod("log", p0 + Vector3(0, -0.4, 0), p0 + Vector3(0, 0.2, 0), 0.05, 0.03, 4, col("log", rng))


static func _sawmill(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 6.2
	var d := 4.2
	plinth(g, rng, w, d, "stone")
	for x: float in [-2.8, 0.0, 2.8]:
		for z: float in [-1.8, 1.8]:
			g.rod("log", Vector3(x, BASE, z), Vector3(x, BASE + 3.0, z), 0.2, 0.18, 7, col("log", rng))
	for z: float in [-1.8, 1.8]:
		g.rod("log", Vector3(-3.1, BASE + 3.1, z), Vector3(3.1, BASE + 3.1, z), 0.17, 0.17, 7, col("log", rng))
	gable_roof(g, rng, Vector3(0, BASE + 3.2, 0), w, d, 1.4, "log_dark", "boards", 0.45)
	# Пильный стол и штабель брёвен.
	g.box("log_dark", Vector3(0.2, BASE + 0.45, -0.3), Vector3(3.6, 0.9, 1.0), col("log_dark", rng), 0.05)
	g.box("log", Vector3(0.2, BASE + 0.95, -0.3), Vector3(3.2, 0.12, 0.7), col("log", rng), 0.03)
	for i in 6:
		var row := 0 if i < 3 else 1
		var k := i if i < 3 else i - 3
		if row == 1 and k == 2:
			continue
		var z := 2.6 + (k + row * 0.5) * 0.48
		g.rod("log", Vector3(-2.0, BASE + 0.22 + row * 0.42, z), Vector3(2.0, BASE + 0.22 + row * 0.42, z), 0.22, 0.22, 8, col("log", rng))


static func _stonemason(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 5.4
	var d := 4.2
	plinth(g, rng, w, d, "stone")
	g.push(wall_frame(Vector3(w * 0.5 - 0.2, BASE, -d * 0.5 + 0.2), Vector3.LEFT))
	wall_body(g, rng, w - 0.4, 2.7, "plank")
	g.pop()
	for side: float in [-1.0, 1.0]:
		# Левая стена идёт от задней стены вперёд, правая — от фасада назад (наружу смотрят обе).
		var start := Vector3(side * (w * 0.5 - 0.2), BASE, -d * 0.5 + 0.2 if side < 0 else d * 0.5 - 0.6)
		g.push(wall_frame(start, Vector3.BACK if side < 0 else Vector3.FORWARD))
		wall_body(g, rng, d - 0.8, 2.7, "plank")
		g.pop()
		g.rod("log", Vector3(side * (w * 0.5 - 0.2), BASE, d * 0.5 - 0.3), Vector3(side * (w * 0.5 - 0.2), BASE + 2.9, d * 0.5 - 0.3), 0.18, 0.16, 7, col("log", rng))
	gable_roof(g, rng, Vector3(0, BASE + 2.75, 0), w, d, 1.5, "plank_dark", "shingle", 0.4)
	for i in 5:
		var p := Vector3(rng.randf_range(-1.8, 1.8), BASE + 0.25 + (0.5 if i == 4 else 0.0), d * 0.5 + 0.6 + rng.randf_range(0.0, 0.5))
		g.box("stone", p, Vector3(0.7, 0.5, 0.5), col("stone", rng), 0.07, Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)))
	g.box("plank", Vector3(0, BASE + 0.45, -0.6), Vector3(2.0, 0.9, 0.8), col("plank", rng), 0.04)


static func _kiln(g: Geo, rng: RandomNumberGenerator) -> void:
	g.box("stone", Vector3(0, (UNDER + BASE) * 0.5, 0), Vector3(4.6, BASE - UNDER, 4.6), col("stone", rng).darkened(0.3))
	round_wall(g, rng, Vector3(0, BASE, 0), 1.9, 1.8, 1.4, "stone", [{"angle": PI * 0.5, "v": 0.0, "w": 0.9, "h": 1.0, "type": "door"}],
		{"door": "plank_dark", "frame": "plank"})
	# Глиняный купол.
	var profile := []
	for i in 7:
		var t := float(i) / 6.0
		profile.append(Vector2(1.85 * cos(t * PI * 0.5) + 0.35 * t, t * 1.9))
	profile.append(Vector2(0.38, 2.1))
	lathe(g, "clay", Vector3(0, BASE + 1.4, 0), profile, 12, rng)
	g.cylinder("clay", Vector3(0, BASE + 3.4, 0), 0.38, 0.3, 1.1, 8, col("clay", rng), true)
	for z: float in [-1.3, 1.3]:
		g.box("plank", Vector3(3.3, BASE + 1.2, z), Vector3(0.22, 2.4, 0.22), col("plank", rng), 0.03)
	gable_roof(g, rng, Vector3(3.3, BASE + 2.4, 0), 2.8, 1.6, 0.7, "plank_dark", "shingle", 0.3)
	g.box("plank", Vector3(3.3, BASE + 0.35, 0), Vector3(1.4, 0.7, 2.2), col("plank", rng), 0.04)


static func _tannery(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 4.8
	var d := 3.6
	g.box("log", Vector3(0, (UNDER + BASE) * 0.5, -0.4), Vector3(w + 0.3, BASE - UNDER, d + 0.3), col("log", rng).darkened(0.3))
	g.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.4)))
	walls(g, rng, w, d, BASE, 2.5, "plank", [
		{"side": "front", "u": -0.9, "w": 0.95, "h": 1.9, "type": "door"},
		{"side": "front", "u": 1.2, "v": 0.9, "w": 0.8, "h": 0.8},
	], {"frame": "log_dark", "door": "plank_dark", "corner_trim": "log"})
	gable_roof(g, rng, Vector3(0, BASE + 2.5, 0), w, d, 1.5, "plank_dark", "boards", 0.45)
	g.pop()
	for x: float in [-1.4, 0.0, 1.4]:
		g.cylinder("plank", Vector3(x, 0, 2.4), 0.55, 0.6, 0.9, 10, col("plank", rng))
		g.cylinder("log_dark", Vector3(x, 0.15, 2.4), 0.58, 0.58, 0.08, 10, col("log_dark", rng))
		g.cylinder("log_dark", Vector3(x, 0.7, 2.4), 0.62, 0.62, 0.08, 10, col("log_dark", rng))


static func _weaver(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 5.0
	var d := 4.2
	plinth(g, rng, w + 0.3, d + 0.3, "stone")
	walls(g, rng, w, d, BASE, 2.7, "plank", [
		{"side": "front", "u": 0.0, "w": 1.0, "h": 1.95, "type": "door"},
		{"side": "front", "u": -1.6, "v": 0.9, "w": 0.85, "h": 0.85},
		{"side": "front", "u": 1.6, "v": 0.9, "w": 0.85, "h": 0.85},
		{"side": "right", "u": 0.0, "v": 0.9, "w": 0.85, "h": 0.85},
	], {"frame": "plank_dark", "door": "plank_dark", "corner_trim": "plank_dark"})
	gable_roof(g, rng, Vector3(0, BASE + 2.7, 0), w, d, 1.8, "plank_dark", "shingle", 0.5, "plank_v", "")


static func _glassworks(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 6.0
	var d := 4.6
	plinth(g, rng, w + 0.3, d + 0.3, "stone_block")
	walls(g, rng, w, d, BASE, 3.0, "brick", [
		{"side": "front", "u": -1.2, "w": 1.2, "h": 2.1, "type": "door"},
		{"side": "front", "u": 1.4, "v": 1.0, "w": 0.9, "h": 1.0},
		{"side": "left", "u": 0.0, "v": 1.0, "w": 0.9, "h": 1.0},
	], {"frame": "stone_block", "door": "plank_dark", "quoins": true})
	gable_roof(g, rng, Vector3(0, BASE + 3.0, 0), w, d, 1.8, "slate", "shingle", 0.45, "brick", "")
	_chimney(g, rng, Vector3(1.8, BASE + 3.0, -1.2), 0.9, 3.4, "brick")
	var dome := []
	for i in 6:
		var t := float(i) / 5.0
		dome.append(Vector2(1.0 * cos(t * PI * 0.5) + 0.05, t * 1.1))
	g.box("stone_block", Vector3(1.6, 0.2, 3.1), Vector3(2.2, 0.4, 2.0), col("stone_block", rng), 0.05)
	lathe(g, "brick", Vector3(1.6, 0.4, 3.1), dome, 10, rng)


static func _smithy(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 5.8
	var d := 4.4
	plinth(g, rng, w + 0.3, d + 0.3, "stone_block")
	walls(g, rng, w, d, BASE, 1.15, "stone_block", [
		{"side": "front", "u": -1.2, "w": 1.1, "h": 1.15, "type": "door"},
	], {"frame": "stone_block", "door": "plank_dark", "quoins": true})
	walls(g, rng, w, d, BASE + 1.15, 1.6, "plank", [
		{"side": "front", "u": -1.2, "w": 1.1, "h": 0.95, "type": "door"},
		{"side": "front", "u": 1.4, "v": 0.3, "w": 0.9, "h": 0.8},
	], {"frame": "plank_dark", "door": "plank_dark", "corner_trim": "plank_dark"})
	gable_roof(g, rng, Vector3(0, BASE + 2.75, 0), w, d, 1.7, "slate", "shingle", 0.45, "plank_v", "")
	_chimney(g, rng, Vector3(-2.0, BASE + 2.75, -1.2), 0.9, 2.6, "brick")
	# Горн и кожаные меха снаружи.
	g.box("brick", Vector3(1.6, 0.5, 3.0), Vector3(1.5, 1.0, 1.1), col("brick", rng), 0.04)
	g.box("brick", Vector3(1.6, 1.05, 3.0), Vector3(1.6, 0.12, 1.2), col("brick", rng).darkened(0.1), 0.03)
	g.blob("leather", Vector3(0.45, 0.85, 3.0), Vector3(0.45, 0.22, 0.32), col("leather", rng), rng, 1, 0.1, 0.2)
	g.box("plank", Vector3(0.45, 0.4, 3.0), Vector3(0.5, 0.8, 0.5), col("plank", rng), 0.03)


static func _well(g: Geo, rng: RandomNumberGenerator) -> void:
	g.cylinder("stone", Vector3(0, UNDER, 0), 1.2, 1.2, -UNDER, 12, col("stone", rng).darkened(0.3), false)
	round_wall(g, rng, Vector3(0, 0, 0), 1.15, 1.1, 0.95, "stone")
	g.cylinder("stone", Vector3(0, 0.9, 0), 1.18, 1.18, 0.12, 14, col("stone", rng).lightened(0.05))
	for x: float in [-1.0, 1.0]:
		g.box("plank", Vector3(x, 1.6, 0), Vector3(0.18, 1.6, 0.18), col("plank", rng), 0.03)
	g.rod("iron", Vector3(-1.15, 2.05, 0), Vector3(1.15, 2.05, 0), 0.07, 0.07, 8, col("iron", rng))
	g.rod("iron", Vector3(1.15, 2.05, 0), Vector3(1.15, 1.8, 0.25), 0.04, 0.04, 5, col("iron", rng))
	g.cylinder("plank_dark", Vector3(0, 1.25, 0), 0.22, 0.26, 0.35, 8, col("plank_dark", rng))
	g.rod("iron", Vector3(0, 1.6, 0), Vector3(0, 2.0, 0), 0.015, 0.015, 3, col("iron", rng))
	gable_roof(g, rng, Vector3(0, 2.4, 0), 2.0, 1.6, 0.8, "plank_dark", "shingle", 0.3)


static func _market(g: Geo, rng: RandomNumberGenerator) -> void:
	g.box("plank", Vector3(0, (UNDER + 0.2) * 0.5, 0), Vector3(3.8, 0.2 - UNDER, 2.8), col("plank", rng).darkened(0.3))
	for i in 9:
		g.tile("plank", Vector3(-1.9 + (i + 0.5) * 3.8 / 9.0, 0.2, 0), Vector3.UP, Vector3.FORWARD, 3.8 / 9.0 - 0.03, 2.75, 0.04, 0.015, col("plank", rng))
	for x: float in [-1.6, 1.6]:
		for z: float in [-1.2, 1.2]:
			g.rod("log", Vector3(x, 0.2, z), Vector3(x, 2.7, z), 0.09, 0.08, 6, col("log", rng))
	g.box("plank", Vector3(0, 0.75, 0.85), Vector3(3.2, 1.0, 0.7), col("plank", rng), 0.04)
	g.box("plank_dark", Vector3(0, 1.28, 0.85), Vector3(3.3, 0.08, 0.8), col("plank_dark", rng), 0.02)
	# Полосатый тканевый навес.
	var stripes := 8
	for i in stripes:
		var x0 := -2.0 + i * 4.0 / stripes
		var c := Color(0.94, 0.9, 0.82) if i % 2 == 0 else Color(0.78, 0.36, 0.3)
		for s: float in [-1.0, 1.0]:
			var a := Vector3(x0, 2.7, s * 1.55)
			var b := Vector3(x0 + 4.0 / stripes, 2.7, s * 1.55)
			var top := Vector3(0, 3.3, 0)
			g.quad("cloth", a, b, Vector3(b.x, top.y, 0), Vector3(a.x, top.y, 0), c, Vector3(0, 1, s * 0.6))
			g.quad("cloth", a, b, Vector3(b.x, top.y, 0), Vector3(a.x, top.y, 0), c.darkened(0.25), Vector3(0, -1, -s * 0.6))
		g.tri("cloth", Vector3(x0, 2.7, 1.55), Vector3(x0 + 4.0 / stripes, 2.7, 1.55), Vector3(x0 + 2.0 / stripes, 2.45, 1.6), c, Vector3.BACK)
	for p: Vector3 in [Vector3(-1.0, 1.5, 0.85), Vector3(0.1, 1.5, 0.8), Vector3(1.1, 1.5, 0.9)]:
		g.box("plank_dark", p, Vector3(0.6, 0.38, 0.45), col("plank_dark", rng), 0.03, Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)))


static func _chapel(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 4.0
	var d := 6.0
	g.box("log", Vector3(0, (UNDER + BASE) * 0.5, 0), Vector3(w + 0.4, BASE - UNDER, d + 0.4), col("log", rng).darkened(0.3))
	for z: float in [-1.0, 1.0]:
		g.rod("log", Vector3(-w * 0.5 - 0.3, BASE * 0.5, z * (d * 0.5 + 0.05)), Vector3(w * 0.5 + 0.3, BASE * 0.5, z * (d * 0.5 + 0.05)), 0.2, 0.2, 8, col("log", rng))
	# Здание вытянуто вдоль Z: стены строим в повёрнутой системе.
	g.push(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO))
	walls(g, rng, d, w, BASE, 3.2, "plank_v", [
		{"side": "left", "u": 0.0, "w": 1.1, "h": 2.2, "type": "door"},
		{"side": "front", "u": -1.4, "v": 1.2, "w": 0.6, "h": 1.2},
		{"side": "front", "u": 1.0, "v": 1.2, "w": 0.6, "h": 1.2},
		{"side": "back", "u": -1.0, "v": 1.2, "w": 0.6, "h": 1.2},
		{"side": "back", "u": 1.4, "v": 1.2, "w": 0.6, "h": 1.2},
	], {"frame": "plank_dark", "door": "plank_dark", "corner_trim": "log"})
	gable_roof(g, rng, Vector3(0, BASE + 3.2, 0), d, w, 2.3, "plank_dark", "shingle", 0.4, "plank_v", "")
	g.pop()
	# Звонница над входом.
	var tz := d * 0.5 - 0.9
	var ty := BASE + 4.6
	g.box("plank", Vector3(0, ty + 0.7, tz), Vector3(1.4, 1.6, 1.4), col("plank", rng), 0.04)
	for x: float in [-0.5, 0.5]:
		g.box("plank_dark", Vector3(x * 0.9, ty + 0.9, tz + 0.71), Vector3(0.35, 0.8, 0.04), col("plank_dark", rng).darkened(0.3))
	pyramid_roof(g, rng, Vector3(0, ty + 1.5, tz), 0.7, 1.9, "plank_dark", 0.2)
	g.box("plank", Vector3(0, ty + 3.85, tz), Vector3(0.1, 0.9, 0.1), col("plank", rng))
	g.box("plank", Vector3(0, ty + 4.0, tz), Vector3(0.5, 0.1, 0.1), col("plank", rng))
	for x: float in [-0.9, 0.9]:
		g.cylinder("wax", Vector3(x, 0.0, d * 0.5 + 0.55), 0.07, 0.065, 0.45, 6, col("wax", rng))
		g.cylinder("plank_dark", Vector3(x, -0.05, d * 0.5 + 0.55), 0.14, 0.12, 0.1, 6, col("plank_dark", rng))


static func _church(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 5.6
	var nave := 8.0
	var zc := -1.2
	plinth(g, rng, w + 0.3, nave + 6.4, "stone_block")
	# Неф вдоль Z.
	g.push(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0, zc)))
	walls(g, rng, nave, w, BASE, 4.4, "stone_block", [
		{"side": "front", "u": -2.4, "v": 1.2, "w": 0.8, "h": 2.2},
		{"side": "front", "u": 0.0, "v": 1.2, "w": 0.8, "h": 2.2},
		{"side": "front", "u": 2.4, "v": 1.2, "w": 0.8, "h": 2.2},
		{"side": "back", "u": -2.4, "v": 1.2, "w": 0.8, "h": 2.2},
		{"side": "back", "u": 0.0, "v": 1.2, "w": 0.8, "h": 2.2},
		{"side": "back", "u": 2.4, "v": 1.2, "w": 0.8, "h": 2.2},
	], {"frame": "stone_block", "glass": true, "quoins": true, "stained": true})
	gable_roof(g, rng, Vector3(0, BASE + 4.44, 0), nave, w, 2.6, "slate", "shingle", 0.45)
	g.pop()
	# Апсида с медным куполом.
	var apse := Vector3(0, BASE, zc - nave * 0.5)
	round_wall(g, rng, apse, 2.0, 2.0, 3.6, "stone_block")
	var cone := []
	for i in 6:
		var t := float(i) / 5.0
		cone.append(Vector2(2.25 * (1.0 - t * t), 3.6 + t * 1.6))
	lathe(g, "copper", apse, cone, 14, rng)
	# Колокольня у входа.
	var tower := Vector3(0, BASE, zc + nave * 0.5 + 1.4)
	var tw := 2.8
	g.push(Transform3D(Basis.IDENTITY, Vector3(tower.x, 0, tower.z)))
	walls(g, rng, tw, tw, BASE, 8.0, "stone_block", [
		{"side": "front", "u": 0.0, "w": 1.3, "h": 2.4, "type": "door"},
		{"side": "front", "u": 0.0, "v": 4.2, "w": 0.9, "h": 1.3},
		{"side": "left", "u": 0.0, "v": 6.0, "w": 0.8, "h": 1.4},
		{"side": "right", "u": 0.0, "v": 6.0, "w": 0.8, "h": 1.4},
		{"side": "back", "u": 0.0, "v": 6.0, "w": 0.8, "h": 1.4},
	], {"frame": "stone_block", "door": "plank", "glass": true, "quoins": true})
	g.box("stone_block", Vector3(0, BASE + 8.1, 0), Vector3(tw + 0.4, 0.22, tw + 0.4), col("stone_block", rng), 0.05)
	g.pop()
	var dome_base := Vector3(tower.x, BASE + 8.2, tower.z)
	round_wall(g, rng, dome_base, 1.0, 1.0, 0.8, "stone_block")
	var onion := [Vector2(1.05, 0.8), Vector2(1.35, 1.25), Vector2(1.38, 1.6), Vector2(1.2, 2.05), Vector2(0.8, 2.5),
		Vector2(0.35, 2.95), Vector2(0.12, 3.35), Vector2(0.0, 3.6)]
	lathe(g, "copper", dome_base, onion, 16, rng)
	var cross := dome_base + Vector3(0, 3.6, 0)
	g.box("copper", cross + Vector3(0, 0.55, 0), Vector3(0.1, 1.1, 0.1), col("copper", rng).lightened(0.15))
	g.box("copper", cross + Vector3(0, 0.75, 0), Vector3(0.55, 0.1, 0.1), col("copper", rng).lightened(0.15))
	for x: float in [-1.0, 1.0]:
		g.cylinder("wax", Vector3(x, 0.0, tower.z + tw * 0.5 + 0.5), 0.07, 0.065, 0.5, 6, col("wax", rng))
		g.cylinder("plank_dark", Vector3(x, -0.05, tower.z + tw * 0.5 + 0.5), 0.14, 0.12, 0.1, 6, col("plank_dark", rng))


static func _windmill(g: Geo, rng: RandomNumberGenerator) -> void:
	g.cylinder("stone_block", Vector3(0, UNDER, 0), 2.6, 2.6, BASE - UNDER, 16, col("stone_block", rng).darkened(0.3), true)
	round_wall(g, rng, Vector3(0, BASE, 0), 2.4, 2.2, 3.4, "stone_block", [
		{"angle": PI * 0.35, "v": 0.0, "w": 1.0, "h": 2.0, "type": "door"},
		{"angle": PI * 0.75, "v": 1.2, "w": 0.6, "h": 0.9},
	], {"frame": "plank", "door": "plank", "glass": true})
	# Пояс между ярусами, как на референсе: снизу он закрывает верх первого яруса,
	# сверху — заходит под второй, поэтому щели между ярусами нет.
	lathe(g, "stone_block", Vector3(0, BASE + 3.4, 0), [Vector2(2.05, -0.04), Vector2(2.42, 0.0), Vector2(2.42, 0.28),
		Vector2(2.1, 0.32), Vector2(1.7, 0.36)], 18, rng)
	g.cylinder("stone_block", Vector3(0, BASE + 3.3, 0), 2.25, 1.97, 0.5, 18, col("stone_block", rng).darkened(0.25), false)
	round_wall(g, rng, Vector3(0, BASE + 3.66, 0), 1.95, 1.8, 3.26, "stone_block", [
		{"angle": PI * 0.5, "v": 1.0, "w": 0.55, "h": 0.85},
		{"angle": -PI * 0.1, "v": 1.6, "w": 0.55, "h": 0.85},
	], {"frame": "plank", "glass": true})
	# Шапка-домик с двускатной крышей.
	var cap_y := BASE + 6.92
	g.box("stone_block", Vector3(0, cap_y + 0.05, 0), Vector3(3.9, 0.12, 3.9), col("stone_block", rng), 0.04)
	g.push(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0, 0)))
	walls(g, rng, 3.2, 2.6, cap_y + 0.1, 0.9, "stone_block", [], {"quoins": false})
	gable_roof(g, rng, Vector3(0, cap_y + 1.0, 0), 3.2, 2.6, 1.6, "slate", "shingle", 0.35, "stone_block", "")
	g.pop()
	g.rod("log", Vector3(0, ROTOR_PIVOT["windmill"].y, 1.0), Vector3(0, ROTOR_PIVOT["windmill"].y, 2.7), 0.2, 0.18, 8, col("log", rng))


static func _windmill_rotor(g: Geo, rng: RandomNumberGenerator) -> void:
	# Локальные координаты вокруг оси (pivot). Крылья в плоскости XY, смотрят на +Z.
	g.cylinder("log", Vector3(0, 0, -0.2), 0.42, 0.42, 0.4, 10, col("log", rng), true, true, 0.0, Basis(Vector3.RIGHT, PI * 0.5))
	g.blob("log", Vector3(0, 0, 0.25), Vector3(0.28, 0.28, 0.2), col("log", rng), rng, 1, 0.0, 0.1)
	for i in 4:
		var a := PI * 0.25 + i * PI * 0.5
		var dir := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-sin(a), cos(a), 0)
		var arm_basis := Basis(side, dir, Vector3.BACK)
		g.box("plank", dir * 2.9, Vector3(0.18, 5.8, 0.16), col("plank", rng), 0.03, arm_basis)
		# Решётка: рамка и перекладины, внутри — ткань.
		var inner := 0.9
		var outer := 5.6
		var width := 1.25
		var mid := dir * (inner + outer) * 0.5 + side * width * 0.5
		for s: float in [0.0, 1.0]:
			g.box("plank", dir * (inner + outer) * 0.5 + side * width * s + Vector3(0, 0, 0.02), Vector3(0.1, outer - inner, 0.1), col("plank", rng), 0.02, arm_basis)
		var bars := 5
		for b in bars + 1:
			var r := inner + (outer - inner) * b / bars
			g.box("plank", dir * r + side * width * 0.5 + Vector3(0, 0, 0.03), Vector3(width, 0.09, 0.09), col("plank", rng), 0.02, arm_basis)
		for b in bars:
			var r := inner + (outer - inner) * (b + 0.5) / bars
			var c := col("cloth", rng, 0.04)
			g.box("cloth", dir * r + side * width * 0.5 - Vector3(0, 0, 0.02), Vector3(width - 0.12, (outer - inner) / bars - 0.1, 0.04), c, 0.0, arm_basis)


static func _cannon(g: Geo, rng: RandomNumberGenerator) -> void:
	for x: float in [-0.32, 0.32]:
		g.box("plank", Vector3(x, 0.75, -0.15), Vector3(0.14, 0.55, 1.9), col("plank", rng), 0.03, Basis(Vector3.RIGHT, -0.12))
	g.box("plank", Vector3(0, 0.55, -0.9), Vector3(0.7, 0.18, 0.8), col("plank", rng), 0.03)
	g.rod("log", Vector3(-0.75, 0.55, 0.25), Vector3(0.75, 0.55, 0.25), 0.08, 0.08, 6, col("log", rng))
	for x: float in [-0.6, 0.6]:
		var c := col("plank_dark", rng)
		g.cylinder("plank_dark", Vector3(x - 0.06, 0.55, 0.25), 0.55, 0.55, 0.12, 12, c, true, true, 0.0, Basis(Vector3.BACK, -PI * 0.5))
		for k in 6:
			var a := k * PI / 3.0
			g.rod("plank_dark", Vector3(x * 1.02, 0.55, 0.25), Vector3(x * 1.02, 0.55 + sin(a) * 0.5, 0.25 + cos(a) * 0.5), 0.03, 0.03, 4, c.lightened(0.08))
	var barrel := Basis(Vector3.RIGHT, deg_to_rad(82.0))
	g.cylinder("iron", Vector3(0, 1.0, -1.0), 0.32, 0.22, 2.6, 12, col("iron", rng), true, true, 0.0, barrel)
	for t: float in [0.0, 0.45, 1.0]:
		var p := Vector3(0, 1.0, -1.0) + barrel * Vector3(0, 2.6 * t * 0.97, 0)
		g.cylinder("iron", p, 0.34 - t * 0.1, 0.34 - t * 0.1, 0.12, 12, col("iron", rng).lightened(0.08), true, true, 0.0, barrel)
	g.blob("iron", Vector3(0, 1.0, -1.05), Vector3.ONE * 0.2, col("iron", rng), rng, 1, 0.0, 0.2)
	for p: Vector3 in [Vector3(0.9, 0.15, -1.0), Vector3(1.22, 0.15, -1.0), Vector3(1.06, 0.15, -1.3), Vector3(1.06, 0.42, -1.1)]:
		g.blob("iron", p, Vector3.ONE * 0.15, col("iron", rng), rng, 1, 0.0, 0.25)


static func _watchtower(g: Geo, rng: RandomNumberGenerator) -> void:
	var s := 3.2
	plinth(g, rng, s + 0.3, s + 0.3, "stone_block")
	walls(g, rng, s, s, BASE, 6.0, "stone_block", [
		{"side": "front", "u": 0.0, "w": 1.0, "h": 2.0, "type": "door"},
		{"side": "front", "u": 0.0, "v": 3.6, "w": 0.35, "h": 0.9},
		{"side": "left", "u": 0.0, "v": 2.8, "w": 0.35, "h": 0.9},
		{"side": "right", "u": 0.0, "v": 4.0, "w": 0.35, "h": 0.9},
	], {"frame": "stone_block", "door": "plank", "quoins": true})
	var top := BASE + 6.0
	g.box("plank", Vector3(0, top + 0.12, 0), Vector3(s + 1.2, 0.24, s + 1.2), col("plank", rng), 0.04)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			g.rod("log", Vector3(x * (s * 0.5 + 0.45), top + 0.2, z * (s * 0.5 + 0.45)), Vector3(x * (s * 0.5 + 0.45), top + 2.3, z * (s * 0.5 + 0.45)), 0.11, 0.1, 6, col("log", rng))
	for side in 4:
		var yaw := Basis(Vector3.UP, side * PI * 0.5)
		for k in 7:
			var u := -(s * 0.5 + 0.45) + k * (s + 0.9) / 6.0
			g.box("plank", yaw * Vector3(u, top + 0.65, s * 0.5 + 0.47), yaw * Vector3(0.14, 0.8, 0.08), col("plank", rng), 0.02)
		g.box("plank", yaw * Vector3(0, top + 1.05, s * 0.5 + 0.47), (yaw * Vector3(s + 1.0, 0.12, 0.12)).abs(), col("plank", rng), 0.02)
	pyramid_roof(g, rng, Vector3(0, top + 2.3, 0), s * 0.5 + 0.45, 2.1, "plank_dark", 0.35)


static func _palisade(g: Geo, rng: RandomNumberGenerator) -> void:
	for z: float in [-0.25, 0.25]:
		g.rod("log", Vector3(-2.0, 1.1 + z, -0.24), Vector3(2.0, 1.1 + z, -0.24), 0.08, 0.08, 6, col("log_dark", rng))
	for i in 5:
		var x := -1.6 + i * 0.8
		var h := 2.4 + rng.randf_range(-0.15, 0.15)
		g.rod("log", Vector3(x, -0.6, 0), Vector3(x, h, 0), 0.19, 0.18, 8, col("log", rng))
		g.cylinder("log", Vector3(x, h, 0), 0.18, 0.0, 0.5, 8, col("log", rng).lightened(0.12), false)


static func _keep(g: Geo, rng: RandomNumberGenerator) -> void:
	# Крепость по референсу: два объёма буквой Г, два этажа, зубцы на крыше.
	var parts := [[Vector3(-1.4, 0, 0.6), 5.2, 4.4], [Vector3(2.1, 0, -0.8), 3.4, 6.4]]
	for i in parts.size():
		var p: Array = parts[i]
		var c: Vector3 = p[0]
		var w: float = p[1]
		var d: float = p[2]
		g.push(Transform3D(Basis.IDENTITY, c))
		plinth(g, rng, w + 0.3, d + 0.3, "stone_block")
		var ops := []
		if i == 0:
			ops = [{"side": "front", "u": 0.6, "w": 1.2, "h": 2.0, "type": "door"}, {"side": "front", "u": -1.4, "v": 0.9, "w": 0.7, "h": 1.0},
				{"side": "left", "u": 0.0, "v": 0.9, "w": 0.7, "h": 1.0}]
		else:
			ops = [{"side": "front", "u": 0.0, "v": 0.9, "w": 0.7, "h": 1.0}, {"side": "right", "u": 1.4, "v": 0.9, "w": 0.7, "h": 1.0},
				{"side": "right", "u": -1.4, "v": 0.9, "w": 0.7, "h": 1.0}]
		walls(g, rng, w, d, BASE, 2.3, "stone_block", ops, {"frame": "stone_block", "door": "plank", "glass": true, "quoins": true})
		g.box("stone_block", Vector3(0, BASE + 2.38, 0), Vector3(w + 0.22, 0.16, d + 0.22), col("stone_block", rng), 0.04)
		var up := []
		for o: Dictionary in ops:
			if o.get("type", "") != "door":
				var o2 := o.duplicate()
				o2["v"] = 0.55
				up.append(o2)
		if i == 0:
			up.append({"side": "front", "u": 0.6, "v": 0.55, "w": 0.7, "h": 1.0})
		walls(g, rng, w, d, BASE + 2.46, 2.2, "stone_block", up, {"frame": "stone_block", "glass": true, "quoins": true})
		var top := BASE + 4.66
		g.box("stone_block", Vector3(0, top + 0.08, 0), Vector3(w, 0.16, d), col("stone_block", rng).darkened(0.1))
		# Зубцы: парапет и мерлоны по периметру.
		for side in 4:
			var along_x := side % 2 == 0
			var length := w if along_x else d
			var sign := 1.0 if side < 2 else -1.0
			var count := maxi(2, roundi(length / 0.95))
			for k in count:
				var u := -length * 0.5 + (k + 0.5) * length / count
				var pos := Vector3(u, 0, sign * (d * 0.5 - 0.2)) if along_x else Vector3(sign * (w * 0.5 - 0.2), 0, u)
				g.box("stone_block", pos + Vector3(0, top + 0.35, 0), Vector3(length / count - 0.04, 0.4, 0.42) if along_x else Vector3(0.42, 0.4, length / count - 0.04),
					col("stone_block", rng), 0.05)
				if k % 2 == 0:
					g.box("stone_block", pos + Vector3(0, top + 0.82, 0), Vector3(0.55, 0.5, 0.48) if along_x else Vector3(0.48, 0.5, 0.55), col("stone_block", rng).lightened(0.04), 0.06)
		g.pop()


static func _platform(g: Geo, rng: RandomNumberGenerator) -> void:
	var s := 4.0
	var deck := 0.75
	for x: float in [-1.6, 0.0, 1.6]:
		for z: float in [-1.6, 1.6]:
			g.rod("log", Vector3(x, -2.6, z), Vector3(x, deck - 0.1, z), 0.16, 0.16, 7, col("log", rng))
	for z: float in [-1.6, 1.6]:
		g.box("log", Vector3(0, deck - 0.2, z), Vector3(s, 0.2, 0.22), col("log", rng), 0.03)
	var boards := 10
	for i in boards:
		var x := -s * 0.5 + (i + 0.5) * s / boards
		g.box("plank", Vector3(x, deck, 0), Vector3(s / boards - 0.03, 0.1, s), col("plank", rng, 0.1), 0.02)
	for z: float in [-1.0, 1.0]:
		g.box("plank_dark", Vector3(0, deck + 0.02, z * (s * 0.5 - 0.06)), Vector3(s, 0.12, 0.12), col("plank_dark", rng), 0.02)


static func _bridge_wood(g: Geo, rng: RandomNumberGenerator) -> void:
	var length := 14.0
	var width := 3.4
	var arch := 1.0
	var segs := 14
	var deck_y := func(z: float) -> float:
		var t := z / (length * 0.5)
		return 0.35 + arch * (1.0 - t * t)
	for i in segs:
		var z0 := -length * 0.5 + i * length / segs
		var z1 := z0 + length / segs
		var y0: float = deck_y.call(z0)
		var y1: float = deck_y.call(z1)
		var mid := Vector3(0, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
		var basis := Basis(Vector3.RIGHT, -atan2(y1 - y0, z1 - z0))
		g.box("plank", mid, Vector3(width, 0.12, length / segs - 0.03), col("plank", rng, 0.1), 0.02, basis)
		g.box("log", mid + Vector3(0, -0.18, 0), Vector3(width - 0.4, 0.22, length / segs + 0.02), col("log", rng).darkened(0.1), 0.0, basis)
		if i % 2 == 0:
			for s: float in [-1.0, 1.0]:
				g.rod("log", Vector3(s * width * 0.5, y0, z0), Vector3(s * width * 0.5, y0 + 1.0, z0), 0.08, 0.07, 6, col("log", rng))
	for s: float in [-1.0, 1.0]:
		for i in segs:
			var z0 := -length * 0.5 + i * length / segs
			var z1 := z0 + length / segs
			g.rod("log", Vector3(s * width * 0.5, deck_y.call(z0) + 0.95, z0), Vector3(s * width * 0.5, deck_y.call(z1) + 0.95, z1), 0.06, 0.06, 5, col("log", rng))
	for z: float in [-3.5, 0.0, 3.5]:
		for s: float in [-1.0, 1.0]:
			g.rod("log", Vector3(s * (width * 0.5 - 0.3), -3.0, z), Vector3(s * (width * 0.5 - 0.3), deck_y.call(z) - 0.25, z), 0.17, 0.17, 7, col("log", rng))


static func _bridge_stone(g: Geo, rng: RandomNumberGenerator) -> void:
	var length := 14.0
	var width := 3.6
	var segs := 16
	var deck_y := func(z: float) -> float:
		var t := z / (length * 0.5)
		return 0.4 + 1.2 * (1.0 - t * t)
	var arch_y := func(z: float) -> float:
		var t := z / 4.2
		return -0.6 + 1.6 * sqrt(maxf(0.0, 1.0 - t * t))
	for i in segs:
		var z0 := -length * 0.5 + i * length / segs
		var z1 := z0 + length / segs
		var zm := (z0 + z1) * 0.5
		var top: float = (deck_y.call(z0) + deck_y.call(z1)) * 0.5
		var bottom: float = arch_y.call(zm) if absf(zm) < 4.2 else -2.5
		var h := top - bottom
		var rows := maxi(1, roundi(h / 0.4))
		for r in rows:
			var y := bottom + (r + 0.5) * h / rows
			for s: float in [-1.0, 1.0]:
				g.box("stone_block", Vector3(s * (width * 0.5 - 0.25), y, zm), Vector3(0.5, h / rows - 0.04, length / segs - 0.04),
					col("stone_block", rng), 0.05)
			g.box("stone_block", Vector3(0, y, zm), Vector3(width - 0.9, h / rows, length / segs), col("stone_block", rng).darkened(0.3))
		g.box("stone", Vector3(0, top + 0.05, zm), Vector3(width - 0.9, 0.12, length / segs - 0.02), col("stone", rng, 0.1), 0.03,
			Basis(Vector3.RIGHT, -atan2(deck_y.call(z1) - deck_y.call(z0), z1 - z0)))
		for s: float in [-1.0, 1.0]:
			g.box("stone_block", Vector3(s * (width * 0.5 - 0.25), top + 0.4, zm), Vector3(0.45, 0.55, length / segs - 0.05),
				col("stone_block", rng).lightened(0.04), 0.06)


# =====================================================================================
#  Крепости
# =====================================================================================

## Зубцы по прямой: парапет и мерлоны через один. from/to — концы по низу парапета.
static func battlements(g: Geo, rng: RandomNumberGenerator, from: Vector3, to: Vector3, thickness: float, mat: String) -> void:
	var along := to - from
	var length := along.length()
	var dir := along / length
	var basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
	var mid := (from + to) * 0.5
	g.box(mat, mid + Vector3(0, 0.22, 0), Vector3(length, 0.44, thickness), col(mat, rng, 0.03).darkened(0.05), 0.04, basis)
	var count := maxi(3, roundi(length / 0.95))
	if count % 2 == 0:
		count += 1
	for k in count:
		if k % 2 == 1:
			continue
		var u := -length * 0.5 + (k + 0.5) * length / count
		g.box(mat, mid + dir * u + Vector3(0, 0.44 + 0.3, 0), Vector3(length / count - 0.05, 0.6, thickness + 0.06),
			col(mat, rng, 0.06), 0.05, basis)


## Круглая башня с зубцами и конической крышей.
static func round_tower(g: Geo, rng: RandomNumberGenerator, base: Vector3, r: float, height: float, style: String,
		roof_mat: String, openings: Array = [], opts := {}) -> void:
	var mat: String = STYLES[style]["mat"]
	g.cylinder(mat, base + Vector3(0, UNDER, 0), r + 0.1, r + 0.1, -UNDER + 0.2, 14, col(mat, rng, 0.02).darkened(0.3), false)
	round_wall(g, rng, base, r, r * 0.94, height, style, openings, opts)
	var top := base + Vector3(0, height, 0)
	# Выступающий пояс и зубцы по кругу.
	lathe(g, mat, top, [Vector2(r * 0.94, -0.05), Vector2(r * 1.12, 0.2), Vector2(r * 1.12, 0.32), Vector2(0.0, 0.32)], 14, rng, 0.03)
	var n := maxi(6, roundi(TAU * r * 1.1 / 0.9))
	for k in n:
		if k % 2 == 1:
			continue
		var a := TAU * (k + 0.5) / n
		var dir := Vector3(cos(a), 0, sin(a))
		g.box(mat, top + dir * r * 1.02 + Vector3(0, 0.62, 0), Vector3(TAU * r * 1.1 / n - 0.06, 0.6, 0.34), col(mat, rng, 0.06), 0.05,
			Basis(Vector3.UP, -a + PI * 0.5))
	if roof_mat != "":
		lathe(g, roof_mat, top + Vector3(0, 0.3, 0), [Vector2(r * 0.86, 0.0), Vector2(r * 0.55, r * 0.9), Vector2(0.0, r * 2.1)], 14, rng, 0.05)
		g.cylinder(roof_mat, top + Vector3(0, 0.3 + r * 2.1, 0), 0.05, 0.02, 0.6, 5, col("plank_dark", rng) if roof_mat != "plank_dark" else col(roof_mat, rng))


static func _fort_wood(g: Geo, rng: RandomNumberGenerator) -> void:
	var half := 6.0
	var gate := 1.4
	# Частокол по периметру: заострённые брёвна, ворота спереди.
	for side in 4:
		var yaw := Basis(Vector3.UP, side * PI * 0.5)
		var n := 24
		for i in n:
			var u := -half + 1.3 + (i + 0.5) * (half * 2.0 - 2.6) / n
			if side == 0 and absf(u) < gate:
				continue
			var p := yaw * Vector3(u, 0, half)
			var h := 3.1 + rng.randf_range(-0.18, 0.18)
			var c := col("log", rng, 0.1)
			g.rod("log", p + Vector3(0, -0.8, 0), p + Vector3(0, h, 0), 0.24, 0.23, 6, c, false)
			g.cylinder("log", p + Vector3(0, h, 0), 0.23, 0.0, 0.5, 6, c.lightened(0.1), false)
		# Связи изнутри и помост для стрелков.
		for y: float in [1.0, 2.2]:
			var a := yaw * Vector3(-half + 1.2, y, half - 0.28)
			var b := yaw * Vector3(half - 1.2, y, half - 0.28)
			g.rod("log_dark", a, b, 0.09, 0.09, 6, col("log_dark", rng), true)
		g.box("plank", yaw * Vector3(0, 2.05, half - 0.85), (yaw * Vector3(half * 2.0 - 2.6, 0.12, 0.9)).abs(), col("plank", rng), 0.02)
		for k in 5:
			var u := -half + 2.0 + k * (half * 2.0 - 4.0) / 4.0
			if side == 0 and absf(u) < gate + 0.3:
				continue
			g.rod("log_dark", yaw * Vector3(u, 0.0, half - 1.2), yaw * Vector3(u, 2.0, half - 1.2), 0.08, 0.08, 5, col("log_dark", rng))
	# Угловые башни из брёвен с шатровыми крышами.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := Vector3(sx * (half - 0.4), 0, sz * (half - 0.4))
			g.push(Transform3D(Basis.IDENTITY, c))
			g.box("log", Vector3(0, -0.6, 0), Vector3(2.8, 1.2, 2.8), col("log", rng).darkened(0.3))
			walls(g, rng, 2.4, 2.4, 0.0, 4.3, "log", [
				{"side": "front" if sz > 0 else "back", "u": 0.0, "v": 3.0, "w": 0.5, "h": 0.6},
				{"side": "right" if sx > 0 else "left", "u": 0.0, "v": 3.0, "w": 0.5, "h": 0.6},
			], {"frame": "log_dark", "thickness": 0.34})
			g.box("plank", Vector3(0, 4.42, 0), Vector3(3.0, 0.16, 3.0), col("plank", rng), 0.03)
			for k in 4:
				var yaw := Basis(Vector3.UP, k * PI * 0.5)
				g.box("plank", yaw * Vector3(0, 4.85, 1.45), (yaw * Vector3(3.0, 0.7, 0.1)).abs(), col("plank", rng), 0.02)
			for px: float in [-1.4, 1.4]:
				for pz: float in [-1.4, 1.4]:
					g.rod("log", Vector3(px, 4.4, pz), Vector3(px, 5.8, pz), 0.08, 0.08, 5, col("log", rng))
			pyramid_roof(g, rng, Vector3(0, 5.8, 0), 1.45, 1.9, "plank_dark", 0.3)
			g.pop()
	# Надвратная башенка и створки ворот.
	g.rod("log", Vector3(-gate - 0.1, -0.8, half), Vector3(-gate - 0.1, 4.6, half), 0.26, 0.24, 8, col("log", rng))
	g.rod("log", Vector3(gate + 0.1, -0.8, half), Vector3(gate + 0.1, 4.6, half), 0.26, 0.24, 8, col("log", rng))
	g.box("plank", Vector3(0, 3.35, half), Vector3(gate * 2.0 + 0.9, 0.2, 1.4), col("plank", rng), 0.03)
	for k in 2:
		var x := -gate * 0.5 if k == 0 else gate * 0.5
		var leaf := Basis(Vector3.UP, (0.55 if k == 0 else -0.55))
		var hinge := Vector3(-gate if k == 0 else gate, 0, half + 0.05)
		for b in 4:
			var bx := (b + 0.5) * gate / 4.0 * (1.0 if k == 0 else -1.0)
			g.box("plank", hinge + leaf * Vector3(bx, 1.4, 0), Vector3(gate / 4.0 - 0.03, 2.7, 0.1), col("plank", rng, 0.1), 0.02, leaf)
		g.box("plank_dark", hinge + leaf * Vector3(x, 0.8, 0.07), Vector3(gate - 0.1, 0.16, 0.06), col("plank_dark", rng), 0.02, leaf)
		g.box("plank_dark", hinge + leaf * Vector3(x, 2.1, 0.07), Vector3(gate - 0.1, 0.16, 0.06), col("plank_dark", rng), 0.02, leaf)
	for px: float in [-gate - 0.1, gate + 0.1]:
		g.rod("log", Vector3(px, 3.45, half - 0.55), Vector3(px, 4.8, half - 0.55), 0.08, 0.08, 5, col("log", rng))
		g.rod("log", Vector3(px, 3.45, half + 0.55), Vector3(px, 4.8, half + 0.55), 0.08, 0.08, 5, col("log", rng))
	gable_roof(g, rng, Vector3(0, 4.8, half), gate * 2.0 + 0.4, 1.3, 0.9, "plank_dark", "boards", 0.35, "plank", "")


static func _castle(g: Geo, rng: RandomNumberGenerator) -> void:
	var half := 6.5
	var h := 4.2
	var t := 0.9
	# Куртины между башнями: снаружи кладка, по верху — зубцы.
	for side in 4:
		var yaw := Basis(Vector3.UP, side * PI * 0.5)
		var holes := []
		if side == 0:
			holes = [Rect2(half - 1.55, 0.0, 3.1, h)]
		g.push(Transform3D(yaw, Vector3.ZERO))
		g.box("stone_block", Vector3(0, UNDER * 0.5, half - t * 0.5), Vector3(half * 2.0, -UNDER, t), col("stone_block", rng).darkened(0.3))
		g.push(wall_frame(Vector3(-half, 0, half), Vector3.RIGHT))
		wall_body(g, rng, half * 2.0, h, "stone_big", holes, t)
		g.pop()
		if side == 0:
			battlements(g, rng, Vector3(-half + 1.6, h, half - 0.25), Vector3(-1.9, h, half - 0.25), 0.4, "stone_block")
			battlements(g, rng, Vector3(1.9, h, half - 0.25), Vector3(half - 1.6, h, half - 0.25), 0.4, "stone_block")
		else:
			battlements(g, rng, Vector3(-half + 1.6, h, half - 0.25), Vector3(half - 1.6, h, half - 0.25), 0.4, "stone_block")
		g.box("plank", Vector3(0, h - 0.05, half - t - 0.45), Vector3(half * 2.0 - 3.0, 0.12, 0.9), col("plank", rng), 0.02)
		g.pop()
	# Круглые башни по углам.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var a := atan2(sz, sx)
			round_tower(g, rng, Vector3(sx * half, 0, sz * half), 1.8, 6.6, "stone_big", "slate", [
				{"angle": a, "v": 2.6, "w": 0.4, "h": 0.9}, {"angle": a + 0.9, "v": 4.4, "w": 0.4, "h": 0.9},
			], {"frame": "stone_block"})
	# Надвратная башня: арка ворот, решётка и дубовые створки.
	var gw := 2.0
	g.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, half - 0.2)))
	g.box("stone_block", Vector3(0, UNDER * 0.5, 0), Vector3(4.2, -UNDER, 2.2), col("stone_block", rng).darkened(0.3))
	walls(g, rng, 4.0, 2.0, 0.0, 6.0, "stone_big", [
		{"side": "front", "u": 0.0, "w": gw, "h": 2.9, "type": "door"},
		{"side": "back", "u": 0.0, "w": gw, "h": 2.9, "type": "door"},
		{"side": "front", "u": 0.0, "v": 4.0, "w": 0.45, "h": 0.9},
	], {"frame": "stone_block", "door": "plank_dark"})
	for k in 7:
		var x := -gw * 0.5 + 0.15 + k * (gw - 0.3) / 6.0
		g.box("iron", Vector3(x, 2.0, 1.08), Vector3(0.06, 1.6, 0.06), col("iron", rng), 0.0)
	for y: float in [1.5, 2.5]:
		g.box("iron", Vector3(0, y, 1.08), Vector3(gw - 0.2, 0.06, 0.06), col("iron", rng), 0.0)
	g.box("stone_block", Vector3(0, 6.08, 0), Vector3(4.0, 0.16, 2.0), col("stone_block", rng).darkened(0.1))
	for side in 4:
		var yaw := Basis(Vector3.UP, side * PI * 0.5)
		var l := 4.0 if side % 2 == 0 else 2.0
		var off := 1.0 if side % 2 == 0 else 2.0
		battlements(g, rng, yaw * Vector3(-l * 0.5, 6.12, off - 0.2), yaw * Vector3(l * 0.5, 6.12, off - 0.2), 0.36, "stone_block")
	g.pop()
	# Донжон в глубине двора.
	g.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, -2.0)))
	plinth(g, rng, 4.6, 4.6, "stone_block")
	walls(g, rng, 4.2, 4.2, BASE, 6.4, "stone_big", [
		{"side": "front", "u": 0.0, "w": 1.1, "h": 2.0, "type": "door"},
		{"side": "front", "u": 0.0, "v": 3.4, "w": 0.6, "h": 1.0},
		{"side": "left", "u": 0.0, "v": 3.4, "w": 0.6, "h": 1.0},
		{"side": "right", "u": 0.0, "v": 3.4, "w": 0.6, "h": 1.0},
	], {"frame": "stone_block", "door": "plank_dark", "quoins": true})
	pyramid_roof(g, rng, Vector3(0, BASE + 6.4, 0), 2.1, 3.0, "slate", 0.35)
	g.pop()


static func _citadel(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 6.2
	var h := 9.0
	plinth(g, rng, w + 0.6, w + 0.6, "stone_block", 0.6)
	var ops := [{"side": "front", "u": 0.0, "w": 1.3, "h": 2.3, "type": "door"}]
	for side: String in ["front", "back", "left", "right"]:
		for floor_y: float in [3.3, 6.2]:
			ops.append({"side": side, "u": -1.4, "v": floor_y, "w": 0.75, "h": 1.3})
			ops.append({"side": side, "u": 1.4, "v": floor_y, "w": 0.75, "h": 1.3})
		if side != "front":
			ops.append({"side": side, "u": 0.0, "v": 0.9, "w": 0.75, "h": 1.2})
	walls(g, rng, w, w, 0.6, h, "brick_big", ops, {"frame": "stone_block", "door": "plank_dark", "glass": true, "quoins": true,
		"sill": "stone_block"})
	# Пояса из тёсаного камня между этажами.
	for y: float in [3.1, 6.0, 0.6 + h]:
		g.box("stone_block", Vector3(0, y, 0), Vector3(w + 0.3, 0.22, w + 0.3), col("stone_block", rng), 0.05)
	var top := 0.6 + h + 0.11
	# Башенки на углах (на консолях) и высокий шатёр.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := Vector3(sx * (w * 0.5), top - 1.4, sz * (w * 0.5))
			lathe(g, "stone_block", c, [Vector2(0.15, 0.0), Vector2(0.95, 1.4)], 10, rng, 0.03)
			round_wall(g, rng, c + Vector3(0, 1.4, 0), 0.95, 0.95, 1.9, "brick_big", [
				{"angle": atan2(sz, sx), "v": 0.5, "w": 0.35, "h": 0.8}], {"frame": "stone_block", "glass": true})
			lathe(g, "roof_tile", c + Vector3(0, 3.3, 0), [Vector2(1.15, 0.0), Vector2(0.6, 0.9), Vector2(0.0, 2.2)], 12, rng, 0.05)
	battlements(g, rng, Vector3(-w * 0.5 + 0.9, top, w * 0.5 - 0.2), Vector3(w * 0.5 - 0.9, top, w * 0.5 - 0.2), 0.36, "brick")
	battlements(g, rng, Vector3(-w * 0.5 + 0.9, top, -w * 0.5 + 0.2), Vector3(w * 0.5 - 0.9, top, -w * 0.5 + 0.2), 0.36, "brick")
	battlements(g, rng, Vector3(w * 0.5 - 0.2, top, -w * 0.5 + 0.9), Vector3(w * 0.5 - 0.2, top, w * 0.5 - 0.9), 0.36, "brick")
	battlements(g, rng, Vector3(-w * 0.5 + 0.2, top, -w * 0.5 + 0.9), Vector3(-w * 0.5 + 0.2, top, w * 0.5 - 0.9), 0.36, "brick")
	pyramid_roof(g, rng, Vector3(0, top, 0), w * 0.5 - 0.6, 4.6, "roof_tile", 0.1)
	g.cylinder("plank_dark", Vector3(0, top + 4.5, 0), 0.06, 0.03, 1.0, 5, col("plank_dark", rng))


# =====================================================================================
#  Двор: костёр, факел, ограда, дорожки
# =====================================================================================

static func _campfire(g: Geo, rng: RandomNumberGenerator) -> void:
	var n := 10
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.1, 0.1)
		g.blob("stone", Vector3(cos(a) * 0.64, 0.07, sin(a) * 0.64), Vector3(0.2, 0.15, 0.17) * rng.randf_range(0.85, 1.2),
			col("stone", rng, 0.14), rng, 1, 0.22)
	# Зола и угли.
	g.cylinder("log_dark", Vector3(0, -0.03, 0), 0.52, 0.44, 0.07, 12, col("log_dark", rng).darkened(0.5), true)
	for i in 6:
		g.box("log_dark", Vector3(rng.randf_range(-0.28, 0.28), 0.07, rng.randf_range(-0.28, 0.28)), Vector3(0.14, 0.07, 0.1),
			col("log_dark", rng).darkened(0.55), 0.02, Basis(Vector3.UP, rng.randf() * TAU))
	# Поленья шалашом, концы обуглены.
	var logs := 6
	for i in logs:
		var a := TAU * i / logs + 0.3
		var foot := Vector3(cos(a) * 0.44, 0.02, sin(a) * 0.44)
		var tip := Vector3(cos(a + 0.6) * 0.06, 0.66, sin(a + 0.6) * 0.06)
		g.rod("log", foot, foot.lerp(tip, 0.55), 0.065, 0.055, 6, col("log", rng, 0.1))
		g.rod("log_dark", foot.lerp(tip, 0.55), tip, 0.055, 0.04, 6, col("log_dark", rng).darkened(0.35))
	# Брёвна-скамейки.
	for k in 2:
		var a := PI * 0.25 + k * PI
		var c := Vector3(cos(a), 0.0, sin(a)) * 1.6
		var along := Vector3(-sin(a), 0, cos(a))
		g.rod("log", c - along * 0.75 + Vector3(0, 0.2, 0), c + along * 0.75 + Vector3(0, 0.2, 0), 0.2, 0.19, 8, col("log", rng))


static func _torch(g: Geo, rng: RandomNumberGenerator) -> void:
	for i in 5:
		var a := TAU * i / 5.0
		g.blob("stone", Vector3(cos(a) * 0.17, 0.05, sin(a) * 0.17), Vector3(0.12, 0.09, 0.11), col("stone", rng, 0.12), rng, 1, 0.2)
	g.rod("log", Vector3(0, -0.5, 0), Vector3(0, 1.78, 0), 0.055, 0.045, 7, col("log", rng))
	# Голова факела: обмотанная смоляная пакля в чаше.
	g.cylinder("log_dark", Vector3(0, 1.66, 0), 0.06, 0.13, 0.3, 8, col("log_dark", rng), true)
	for k in 3:
		g.cylinder("log_dark", Vector3(0, 1.7 + k * 0.08, 0), 0.08 + k * 0.016, 0.085 + k * 0.016, 0.04, 8,
			col("log_dark", rng).darkened(0.3), true)
	g.blob("log_dark", Vector3(0, 1.98, 0), Vector3(0.1, 0.06, 0.1), col("log_dark", rng).darkened(0.6), rng, 1, 0.2)


static func _fence_stone(g: Geo, rng: RandomNumberGenerator) -> void:
	var length := 4.0
	var t := 0.5
	var h := 0.95
	g.box("stone", Vector3(0, -0.4, 0), Vector3(length, 0.8, t), col("stone", rng).darkened(0.3))
	# Кладка с двух сторон и плоские камни поверху.
	g.push(wall_frame(Vector3(-length * 0.5, 0, t * 0.5), Vector3.RIGHT))
	wall_body(g, rng, length, h, "stone", [], t)
	g.pop()
	g.push(wall_frame(Vector3(length * 0.5, 0, -t * 0.5), Vector3.LEFT))
	wall_body(g, rng, length, h, "stone", [], 0.05, 1)
	g.pop()
	var u := -length * 0.5
	while u < length * 0.5 - 0.1:
		var l := minf(rng.randf_range(0.45, 0.75), length * 0.5 - u)
		g.box("stone", Vector3(u + l * 0.5, h + 0.07, rng.randf_range(-0.02, 0.02)), Vector3(l - 0.04, 0.14, t + 0.12),
			col("stone", rng, 0.12), 0.05, Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)))
		u += l


## Плитка дорожки 2×2 м. Дорожка идёт вдоль Z; подложка уходит в землю, чтобы
## на склоне не было щелей.
static func _path(g: Geo, rng: RandomNumberGenerator, kind: String) -> void:
	var s := 2.0
	g.box("soil", Vector3(0, -0.14, 0), Vector3(s, 0.3, s), col("soil", rng, 0.04).darkened(0.12))
	match kind:
		"dirt":
			g.box("soil", Vector3(0, 0.02, 0), Vector3(s - 0.04, 0.06, s - 0.04), col("soil", rng, 0.03).lightened(0.12), 0.03)
			for i in 14:
				var p := Vector3(rng.randf_range(-0.85, 0.85), 0.05, rng.randf_range(-0.9, 0.9))
				g.blob("soil", p, Vector3(rng.randf_range(0.12, 0.26), 0.035, rng.randf_range(0.1, 0.22)),
					col("soil", rng, 0.12).lightened(rng.randf_range(0.0, 0.2)), rng, 0, 0.2, 0.1)
		"wood":
			for x: float in [-0.6, 0.6]:
				g.box("plank_dark", Vector3(x, -0.02, 0), Vector3(0.14, 0.1, s), col("plank_dark", rng), 0.02)
			var n := 6
			for i in n:
				var z := -s * 0.5 + (i + 0.5) * s / n
				g.box("plank", Vector3(rng.randf_range(-0.04, 0.04), 0.07, z), Vector3(s - 0.1, 0.07, s / n - 0.04),
					col("plank", rng, 0.12), 0.02, Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)))
		"stone":
			g.box("soil", Vector3(0, 0.0, 0), Vector3(s, 0.04, s), col("soil", rng).darkened(0.05))
			var n := 5
			for j in n:
				for i in n:
					var off := 0.5 * (j % 2)
					var x := -s * 0.5 + (i + 0.5 + off * 0.5) * s / n
					if x > s * 0.5 - 0.15:
						continue
					var p := Vector3(x + rng.randf_range(-0.04, 0.04), 0.03, -s * 0.5 + (j + 0.5) * s / n + rng.randf_range(-0.03, 0.03))
					g.blob("stone", p, Vector3(0.17, 0.06, 0.16) * rng.randf_range(0.85, 1.12), col("stone", rng, 0.16), rng, 0, 0.14, 0.15)
		"brick":
			g.box("soil", Vector3(0, 0.0, 0), Vector3(s, 0.04, s), col("soil", rng).darkened(0.1))
			# Бордюр из кирпичей на ребро и «ёлочка» внутри.
			for x: float in [-1.0, 1.0]:
				for k in 5:
					g.box("brick", Vector3(x * (s * 0.5 - 0.1), 0.05, -s * 0.5 + (k + 0.5) * s / 5.0), Vector3(0.18, 0.1, s / 5.0 - 0.03),
						col("brick", rng, 0.08).darkened(0.08))
			var rows := 8
			for j in rows:
				for i in 4:
					var lean := 1.0 if (i + j) % 2 == 0 else -1.0
					var p := Vector3(-0.63 + i * 0.42, 0.05, -s * 0.5 + (j + 0.5) * s / rows)
					g.box("brick", p, Vector3(0.38, 0.08, 0.17), col("brick", rng, 0.1), 0.0, Basis(Vector3.UP, lean * PI * 0.25))


# =====================================================================================
#  Сад
# =====================================================================================

static func _garden_bed(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 1.4
	var d := 3.4
	g.box("soil", Vector3(0, -0.15, 0), Vector3(w, 0.5, d), col("soil", rng).darkened(0.2))
	for side in 4:
		var along_x := side % 2 == 0
		var sign := 1.0 if side < 2 else -1.0
		var p := Vector3(0, 0.15, sign * (d * 0.5 - 0.04)) if along_x else Vector3(sign * (w * 0.5 - 0.04), 0.15, 0)
		g.box("plank", p, Vector3(w, 0.3, 0.08) if along_x else Vector3(0.08, 0.3, d - 0.16), col("plank", rng, 0.1), 0.02)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.box("plank_dark", Vector3(sx * (w * 0.5 - 0.06), 0.18, sz * (d * 0.5 - 0.06)), Vector3(0.1, 0.36, 0.1), col("plank_dark", rng), 0.02)
	g.box("soil", Vector3(0, 0.2, 0), Vector3(w - 0.16, 0.08, d - 0.16), col("soil", rng, 0.04))
	for x: float in [-0.3, 0.3]:
		g.box("soil", Vector3(x, 0.25, 0), Vector3(0.3, 0.06, d - 0.3), col("soil", rng, 0.04).lightened(0.06), 0.03)


static func _vegetable_garden(g: Geo, rng: RandomNumberGenerator) -> void:
	var half := 3.2
	g.box("soil", Vector3(0, -0.12, 0), Vector3(half * 2.0, 0.3, half * 2.0), col("soil", rng).darkened(0.15))
	# Три гряды.
	for x: float in [-1.9, 0.0, 1.9]:
		g.box("soil", Vector3(x, 0.06, 0), Vector3(1.25, 0.16, 4.6), col("soil", rng, 0.04), 0.06)
		for k in 3:
			g.box("soil", Vector3(x - 0.36 + k * 0.36, 0.15, 0), Vector3(0.22, 0.05, 4.4), col("soil", rng, 0.04).lightened(0.06), 0.02)
	# Штакетник с калиткой спереди.
	for side in 4:
		var yaw := Basis(Vector3.UP, side * PI * 0.5)
		var n := 20
		for i in n:
			var u := -half + (i + 0.5) * half * 2.0 / n
			if side == 0 and absf(u) < 0.5:
				continue
			var p := yaw * Vector3(u, 0, half)
			g.box("plank", p + Vector3(0, 0.45, 0), Vector3(0.12, 0.9, 0.04) if side % 2 == 0 else Vector3(0.04, 0.9, 0.12),
				col("plank", rng, 0.08).lightened(0.12), 0.015)
		for y: float in [0.3, 0.7]:
			g.box("plank_dark", yaw * Vector3(0, y, half - 0.05), (yaw * Vector3(half * 2.0, 0.08, 0.04)).abs(), col("plank_dark", rng), 0.01)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.rod("log", Vector3(sx * half, -0.3, sz * half), Vector3(sx * half, 1.05, sz * half), 0.07, 0.065, 6, col("log", rng))
	for x: float in [-0.5, 0.5]:
		g.rod("log", Vector3(x, -0.3, half), Vector3(x, 1.05, half), 0.07, 0.065, 6, col("log", rng))
