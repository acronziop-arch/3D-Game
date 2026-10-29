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

const ROTOR_PIVOT := {"windmill": Vector3(0, 8.35, 2.85), "watermill": Vector3(0.3, 2.0, 3.0)}

## Здания строятся в «полный» размер, а в игру попадают уменьшенными, чтобы
## одноэтажный дом был заметно ниже деревьев. Настил и мосты — по размеру воды и рек.
const MODEL_SCALE := 0.72
## Верх настила построек на воде (в координатах модели до масштаба) — вровень с блоком настила.
const PIER_DECK := 0.8 / MODEL_SCALE
## Лодки стоят над водой: днище чуть выше волн, внутри — сухой настил (в координатах модели).
const BOAT_LIFT := 0.08
const FULL_SIZE := ["platform", "bridge_wood", "bridge_stone", "campfire", "torch", "fence_stone",
	"path_dirt", "path_wood", "path_stone", "path_brick", "garden_bed", "vegetable_garden",
	"haystack", "woodpile", "barrels", "crates", "cart", "scarecrow", "beehives", "trough", "bench", "signpost", "shrine"]


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
		"tavern": _tavern(g, rng)
		"bakery": _bakery(g, rng)
		"stable": _stable(g, rng)
		"town_hall": _town_hall(g, rng)
		"storehouse": _storehouse(g, rng)
		"dovecote": _dovecote(g, rng)
		"bathhouse": _bathhouse(g, rng)
		"manor": _manor(g, rng)
		"guardhouse": _guardhouse(g, rng)
		"gatehouse": _gatehouse(g, rng)
		"haystack": _haystack(g, rng)
		"woodpile": _woodpile(g, rng)
		"barrels": _barrels(g, rng)
		"crates": _crates(g, rng)
		"cart": _cart(g, rng)
		"scarecrow": _scarecrow(g, rng)
		"beehives": _beehives(g, rng)
		"trough": _trough_decor(g, rng)
		"bench": _bench(g, rng)
		"signpost": _signpost(g, rng)
		"watermill":
			_watermill(g, rng)
			rotor = Geo.new()
			rotor.with_uv2 = false
			_waterwheel(rotor, rng)
		"lighthouse": _lighthouse(g, rng)
		"library": _library(g, rng)
		"bell_tower": _bell_tower(g, rng)
		"chicken_coop": _chicken_coop(g, rng)
		"fishing_hut": _fishing_hut(g, rng)
		"fish_store": _fish_store(g, rng)
		"greenhouse": _greenhouse(g, rng)
		"gazebo": _gazebo(g, rng)
		"fountain": _fountain(g, rng)
		"shrine": _shrine(g, rng)
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
		holes: Array = [], thickness := 0.4, row_offset := 0, insets: Array = []) -> Array:
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
		# По углам — угловые камни (quoins): ряд стены кончается у них, а не заходит внутрь.
		var inset: Vector2 = insets[row] if row < insets.size() else Vector2.ZERO
		for seg in _free_segments(inset.x, length - inset.y, v, v + ch, snapped):
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
		g.pane = Vector2(rect.size.x - f, rect.size.y - f)
		g.box("opening", Vector3(cx, (y0 + y1) * 0.5, -thickness * 0.55), Vector3(rect.size.x - f, rect.size.y - f, 0.05),
			GD.MATERIALS["opening"]["color"].lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.04))
		g.pane = Vector2.ZERO
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


## Ящик с цветами под окном (в осях стены: x — вдоль, y — вверх, z — наружу).
static func flower_box(g: Geo, rng: RandomNumberGenerator, rect: Rect2, mat: String) -> void:
	var cx := rect.position.x + rect.size.x * 0.5
	var y0 := rect.position.y
	var w := rect.size.x * 0.95
	var c := col(mat, rng, 0.04).darkened(0.08)
	g.box(mat, Vector3(cx, y0 - 0.13, 0.2), Vector3(w, 0.2, 0.22), c, 0.025)
	for sx: float in [-1.0, 1.0]:
		g.box(mat, Vector3(cx + sx * w * 0.35, y0 - 0.3, 0.13), Vector3(0.05, 0.16, 0.12), c.darkened(0.1), 0.01)
	g.box("soil", Vector3(cx, y0 - 0.02, 0.2), Vector3(w - 0.06, 0.03, 0.17), col("soil", rng, 0.05))
	var palette := [Color(0.86, 0.22, 0.24), Color(0.95, 0.76, 0.2), Color(0.9, 0.45, 0.62), Color(0.62, 0.42, 0.85), Color(0.98, 0.96, 0.92)]
	var tint: Color = palette[rng.randi() % palette.size()]
	var n := maxi(3, roundi(w / 0.11))
	for i in n:
		var x := cx - w * 0.5 + (i + 0.5) * w / n
		var leaf := Color(0.3, 0.55, 0.22).darkened(rng.randf_range(0.0, 0.15))
		g.blob("crop", Vector3(x, y0 + 0.02, 0.2 + rng.randf_range(-0.04, 0.04)), Vector3(0.09, 0.08, 0.09), leaf, rng, 0, 0.1, 0.2)
		if rng.randf() < 0.8:
			var flower: Color = tint if rng.randf() < 0.7 else palette[rng.randi() % palette.size()]
			g.blob("crop", Vector3(x + rng.randf_range(-0.02, 0.02), y0 + 0.1 + rng.randf_range(0.0, 0.05), 0.2 + rng.randf_range(-0.05, 0.05)),
				Vector3.ONE * 0.075, flower, rng, 0, 0.1, 0.2)


## Козырёк над дверью на двух подпорках и ступенька у порога.
static func door_canopy(g: Geo, rng: RandomNumberGenerator, rect: Rect2, mat: String) -> void:
	var cx := rect.position.x + rect.size.x * 0.5
	var top := rect.end.y + 0.14
	var w := rect.size.x + 0.55
	var c := col(mat, rng, 0.04)
	for s: float in [-1.0, 1.0]:
		var b := Basis(Vector3.BACK, -s * 0.42)
		g.box(mat, Vector3(cx + s * w * 0.25, top + 0.12, 0.38), Vector3(w * 0.56, 0.05, 0.78), c.darkened(0.04 if s > 0 else 0.0), 0.012, b)
	for sx: float in [-1.0, 1.0]:
		var foot := Vector3(cx + sx * (rect.size.x * 0.5 + 0.12), top - 0.38, 0.03)
		g.rod(mat, foot, Vector3(foot.x, top + 0.02, 0.62), 0.035, 0.035, 4, c.darkened(0.1), false)
	g.box(mat, Vector3(cx, rect.position.y - 0.08, 0.32), Vector3(rect.size.x + 0.35, 0.16, 0.48), c.darkened(0.12), 0.03)


## Угловые камни (перевязка углов), как на референсе крепости.
## Выступ угловых камней за угол стены.
const QUOIN_OUT := 0.085


## Длина углового камня ряда i в углу (sx, sz): вдоль X (along_x) или вдоль Z.
## Длинные и короткие камни чередуются — так кладут углы настоящих домов.
static func _quoin_size(sx: float, sz: float, i: int, along_x: bool) -> float:
	var long := (i + int(sx > 0) + int(sz > 0)) % 2 == 0
	return (0.62 if long else 0.4) if along_x else (0.4 if long else 0.62)


## Сколько от начала и конца каждого ряда стены занимают угловые камни (см. walls).
static func _quoin_insets(side: String, height: float, course: float) -> Array:
	# Углы в начале и в конце стены и ось, вдоль которой она идёт.
	var corners := {
		"front": [Vector2(-1, 1), Vector2(1, 1), true],
		"right": [Vector2(1, 1), Vector2(1, -1), false],
		"back": [Vector2(1, -1), Vector2(-1, -1), true],
		"left": [Vector2(-1, -1), Vector2(-1, 1), false],
	}
	var info: Array = corners[side]
	var a: Vector2 = info[0]
	var b: Vector2 = info[1]
	var out := []
	for i in maxi(1, roundi(height / course)):
		out.append(Vector2(_quoin_size(a.x, a.y, i, info[2]), _quoin_size(b.x, b.y, i, info[2])) - Vector2.ONE * (QUOIN_OUT - 0.01))
	return out


static func quoins(g: Geo, rng: RandomNumberGenerator, w: float, d: float, y0: float, height: float, mat: String, course: float) -> void:
	var courses := maxi(1, roundi(height / course))
	course = height / courses
	var dp := QUOIN_OUT
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			for i in courses:
				var qa := _quoin_size(sx, sz, i, true)
				var qb := _quoin_size(sx, sz, i, false)
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
		var insets := []
		if opts.get("quoins", false):
			insets = _quoin_insets(side, height, STYLES[style]["course"])
		var snapped := wall_body(g, rng, length, height, style, holes, thickness, row_offsets[side], insets)
		for i in snapped.size():
			if kinds[i] == "door":
				door(g, rng, snapped[i], door_mat, frame_mat, thickness)
				if opts.get("canopy", false):
					door_canopy(g, rng, snapped[i], frame_mat)
			else:
				window(g, rng, snapped[i], frame_mat, glass, thickness, opts.get("sill", ""), opts.get("stained", false))
				if opts.get("flowers", false) and snapped[i].position.y > 0.4 and rng.randf() < 0.75:
					flower_box(g, rng, snapped[i], frame_mat)
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
	], {"frame": "log_dark", "door": "log_dark", "thickness": 0.34, "flowers": true, "canopy": true})
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
	], {"frame": "plank_dark", "door": "plank_dark", "corner_trim": "plank_dark", "flowers": true, "canopy": true})
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
	], {"frame": "stone_block", "door": "plank", "glass": true, "quoins": true, "flowers": true, "canopy": true})
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
	walls(g, rng, w, d, BASE, 2.3, "brick", ops, {"frame": "stone_block", "door": "plank", "glass": true, "quoins": true, "sill": "stone_block", "flowers": true, "canopy": true})
	# Карниз между этажами.
	g.box("stone_block", Vector3(0, BASE + 2.37, 0), Vector3(w + 0.22, 0.16, d + 0.22), col("stone_block", rng), 0.04)
	walls(g, rng, w, d, BASE + 2.45, 2.1, "brick", [
		{"side": "front", "u": -1.6, "v": 0.5, "w": 0.8, "h": 1.05},
		{"side": "front", "u": 0.0, "v": 0.5, "w": 0.8, "h": 1.05},
		{"side": "front", "u": 1.6, "v": 0.5, "w": 0.8, "h": 1.05},
		{"side": "back", "u": 0.0, "v": 0.5, "w": 0.8, "h": 1.05},
	], {"frame": "stone_block", "glass": true, "quoins": true, "sill": "stone_block", "flowers": true})
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
	gable_roof(g, rng, Vector3(0, BASE + 3.2, 0), w, d, 1.4, "log_dark", "boards", 0.45, "log", "")
	# Пильный стол и штабель брёвен.
	g.box("log_dark", Vector3(0.2, BASE + 0.45, -0.3), Vector3(3.6, 0.9, 1.0), col("log_dark", rng), 0.05)
	g.box("log", Vector3(0.2, BASE + 0.95, -0.3), Vector3(3.2, 0.12, 0.7), col("log", rng), 0.03)
	# Штабель лежит на земле перед цоколем; «yard» — на склоне он ложится по земле (Building._fit_yard).
	g.tag = "yard"
	for i in 6:
		var row := 0 if i < 3 else 1
		var k := i if i < 3 else i - 3
		if row == 1 and k == 2:
			continue
		var z := 2.6 + (k + row * 0.5) * 0.48
		g.rod("log", Vector3(-2.0, 0.2 + row * 0.42, z), Vector3(2.0, 0.2 + row * 0.42, z), 0.22, 0.22, 8, col("log", rng))
	g.tag = ""


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
	gable_roof(g, rng, Vector3(0, BASE + 2.75, 0), w, d, 1.5, "plank_dark", "shingle", 0.4, "plank", "")
	g.tag = "yard"
	for i in 5:
		var p := Vector3(rng.randf_range(-1.8, 1.8), 0.22 + (0.5 if i == 4 else 0.0), d * 0.5 + 0.6 + rng.randf_range(0.0, 0.5))
		g.box("stone", p, Vector3(0.7, 0.5, 0.5), col("stone", rng), 0.07, Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)))
	g.tag = ""
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
	gable_roof(g, rng, Vector3(3.3, BASE + 2.4, 0), 2.8, 1.6, 0.7, "plank_dark", "shingle", 0.3, "plank", "")
	g.box("plank", Vector3(3.3, BASE + 0.35, 0), Vector3(1.4, 0.7, 2.2), col("plank", rng), 0.04)


static func _tannery(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 4.8
	var d := 3.6
	g.box("log", Vector3(0, (UNDER + BASE) * 0.5, -0.4), Vector3(w + 0.3, BASE - UNDER, d + 0.3), col("log", rng).darkened(0.3))
	g.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.4)))
	walls(g, rng, w, d, BASE, 2.5, "plank", [
		{"side": "front", "u": -0.9, "w": 0.95, "h": 1.9, "type": "door"},
		{"side": "front", "u": 1.2, "v": 0.9, "w": 0.8, "h": 0.8},
	], {"frame": "log_dark", "door": "plank_dark", "corner_trim": "log", "canopy": true})
	gable_roof(g, rng, Vector3(0, BASE + 2.5, 0), w, d, 1.5, "plank_dark", "boards", 0.45, "plank", "")
	g.pop()
	# Чаны для кож — у правой стены, чтобы не загораживать дверь; стоят на земле и на склоне.
	g.tag = "yard"
	for z: float in [-1.5, -0.1]:
		var at := Vector3(w * 0.5 + 0.85, 0, z)
		g.cylinder("plank", at, 0.55, 0.6, 0.9, 10, col("plank", rng), true, true)
		g.cylinder("log_dark", at + Vector3(0, 0.15, 0), 0.58, 0.58, 0.08, 10, col("log_dark", rng))
		g.cylinder("log_dark", at + Vector3(0, 0.7, 0), 0.62, 0.62, 0.08, 10, col("log_dark", rng))
		g.cylinder("water", at + Vector3(0, 0.84, 0), 0.5, 0.5, 0.02, 10, Color(0.42, 0.34, 0.22))
	g.tag = ""


static func _weaver(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 5.0
	var d := 4.2
	plinth(g, rng, w + 0.3, d + 0.3, "stone")
	walls(g, rng, w, d, BASE, 2.7, "plank", [
		{"side": "front", "u": 0.0, "w": 1.0, "h": 1.95, "type": "door"},
		{"side": "front", "u": -1.6, "v": 0.9, "w": 0.85, "h": 0.85},
		{"side": "front", "u": 1.6, "v": 0.9, "w": 0.85, "h": 0.85},
		{"side": "right", "u": 0.0, "v": 0.9, "w": 0.85, "h": 0.85},
	], {"frame": "plank_dark", "door": "plank_dark", "corner_trim": "plank_dark", "flowers": true, "canopy": true})
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
	g.tag = "yard"
	g.box("brick", Vector3(1.6, 0.5, 3.0), Vector3(1.5, 1.0, 1.1), col("brick", rng), 0.04)
	g.box("brick", Vector3(1.6, 1.05, 3.0), Vector3(1.6, 0.12, 1.2), col("brick", rng).darkened(0.1), 0.03)
	g.blob("leather", Vector3(0.45, 0.85, 3.0), Vector3(0.45, 0.22, 0.32), col("leather", rng), rng, 1, 0.1, 0.2)
	g.box("plank", Vector3(0.45, 0.4, 3.0), Vector3(0.5, 0.8, 0.5), col("plank", rng), 0.03)
	g.tag = ""


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
	gable_roof(g, rng, Vector3(0, BASE + 4.44, 0), nave, w, 2.6, "slate", "shingle", 0.45, "stone_block", "")
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
	], {"frame": "plank", "door": "plank", "glass": true, "canopy": true})
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
	var breech := Vector3(0, 1.0, -1.0)
	var length := 2.6
	# Ствол полый: торец у дула — кольцо, внутри тёмный канал, в нём ядро.
	g.cylinder("iron", breech, 0.32, 0.22, length, 12, col("iron", rng), false, true, 0.0, barrel)
	for t: float in [0.0, 0.45]:
		var p := breech + barrel * Vector3(0, length * t * 0.97, 0)
		g.cylinder("iron", p, 0.34 - t * 0.1, 0.34 - t * 0.1, 0.12, 12, col("iron", rng).lightened(0.08), true, true, 0.0, barrel)
	var muzzle := breech + barrel * Vector3(0, length, 0)
	var ring := col("iron", rng).lightened(0.08)
	g.cylinder("iron", muzzle - barrel * Vector3(0, 0.12, 0), 0.26, 0.26, 0.12, 12, ring, false, false, 0.0, barrel)
	_bore(g, muzzle, barrel, 0.26, 0.13, 0.9, ring, col("iron", rng).darkened(0.75))
	g.blob("iron", muzzle - barrel * Vector3(0, 0.2, 0), Vector3.ONE * 0.12, col("iron", rng).darkened(0.25), rng, 1, 0.0, 0.08)
	g.blob("iron", Vector3(0, 1.0, -1.05), Vector3.ONE * 0.2, col("iron", rng), rng, 1, 0.0, 0.2)
	for p: Vector3 in [Vector3(0.9, 0.15, -1.0), Vector3(1.22, 0.15, -1.0), Vector3(1.06, 0.15, -1.3), Vector3(1.06, 0.42, -1.1)]:
		g.blob("iron", p, Vector3.ONE * 0.15, col("iron", rng), rng, 1, 0.0, 0.25)


## Дуло: кольцевой торец (r_out → r_in) и тёмный канал глубиной depth внутрь ствола.
## Ось ствола — локальная Y базиса basis, mouth — центр торца.
static func _bore(g: Geo, mouth: Vector3, basis: Basis, r_out: float, r_in: float, depth: float, ring: Color, dark: Color) -> void:
	var axis := basis * Vector3.UP
	var segs := 12
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := basis * Vector3(cos(a0), 0, sin(a0))
		var d1 := basis * Vector3(cos(a1), 0, sin(a1))
		g.quad("iron", mouth + d0 * r_in, mouth + d1 * r_in, mouth + d1 * r_out, mouth + d0 * r_out, ring, axis)
		# Стенки канала смотрят внутрь — к оси.
		var inward := -(d0 + d1).normalized()
		var back := mouth - axis * depth
		g.quad("iron", mouth + d0 * r_in, mouth + d1 * r_in, back + d1 * r_in, back + d0 * r_in,
			dark.lerp(ring, 0.25), inward + axis * 0.2)
		g.tri("iron", back, back + d1 * r_in, back + d0 * r_in, dark, axis)


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


# =====================================================================================
#  Здания поселения
# =====================================================================================

## Подвесная вывеска на кронштейне у угла (в осях здания: фасад смотрит в +Z).
static func _hanging_sign(g: Geo, rng: RandomNumberGenerator, at: Vector3, out: float, mat: String, frame: String) -> void:
	g.rod(frame, at, at + Vector3(0, 0, out), 0.05, 0.05, 5, col(frame, rng), false)
	g.rod(frame, at + Vector3(0, -0.45, 0), at + Vector3(0, -0.02, out * 0.6), 0.03, 0.03, 4, col(frame, rng), false)
	for z: float in [0.25, 0.75]:
		g.rod(frame, at + Vector3(0, 0, out * z), at + Vector3(0, -0.22, out * z), 0.012, 0.012, 3, col(frame, rng).darkened(0.3), false)
	g.box(mat, at + Vector3(0, -0.5, out * 0.5), Vector3(0.06, 0.55, out * 0.72), col(mat, rng), 0.02)


## Бочка: выпуклое тело из клёпок, два обруча и днища с обеих сторон
## (у лежащей бочки нижний торец тоже на виду).
static func _barrel(g: Geo, rng: RandomNumberGenerator, base: Vector3, h := 0.8, r := 0.3, basis := Basis.IDENTITY) -> void:
	g.push(Transform3D(basis, base))
	lathe(g, "plank_dark", Vector3.ZERO, [Vector2(0.0, 0.0), Vector2(r * 0.86, 0.0), Vector2(r, h * 0.3), Vector2(r * 1.04, h * 0.5),
		Vector2(r, h * 0.7), Vector2(r * 0.86, h), Vector2(0.0, h)], 10, rng, 0.08)
	for y: float in [0.16, 0.84]:
		g.cylinder("plank_dark", Vector3(0, h * y - 0.03, 0), r * 0.97, r * 0.97, 0.06, 10, col("plank_dark", rng).darkened(0.35), false)
	g.pop()


static func _tavern(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 6.4
	var d := 4.8
	plinth(g, rng, w + 0.3, d + 0.3, "stone")
	walls(g, rng, w, d, BASE, 2.4, "stone", [
		{"side": "front", "u": -0.5, "w": 1.1, "h": 2.0, "type": "door"},
		{"side": "front", "u": -2.2, "v": 0.8, "w": 0.95, "h": 0.95},
		{"side": "front", "u": 1.5, "v": 0.8, "w": 0.95, "h": 0.95},
		{"side": "left", "u": 0.0, "v": 0.8, "w": 0.9, "h": 0.95},
		{"side": "right", "u": 0.0, "v": 0.8, "w": 0.9, "h": 0.95},
		{"side": "back", "u": 1.2, "v": 0.8, "w": 0.9, "h": 0.95},
	], {"frame": "plank_dark", "door": "plank_dark", "glass": true, "quoins": true, "flowers": true, "canopy": true})
	# Второй этаж нависает над первым, как у фахверковых домов.
	g.box("plank_dark", Vector3(0, BASE + 2.5, 0), Vector3(w + 0.6, 0.2, d + 0.6), col("plank_dark", rng), 0.04)
	var uw := w + 0.4
	var ud := d + 0.4
	walls(g, rng, uw, ud, BASE + 2.6, 2.1, "plank", [
		{"side": "front", "u": -2.2, "v": 0.6, "w": 0.85, "h": 0.95},
		{"side": "front", "u": 0.0, "v": 0.6, "w": 0.85, "h": 0.95},
		{"side": "front", "u": 2.2, "v": 0.6, "w": 0.85, "h": 0.95},
		{"side": "back", "u": -1.2, "v": 0.6, "w": 0.85, "h": 0.95},
		{"side": "left", "u": 0.0, "v": 0.6, "w": 0.85, "h": 0.95},
		{"side": "right", "u": 0.0, "v": 0.6, "w": 0.85, "h": 0.95},
	], {"frame": "plank_dark", "glass": true, "corner_trim": "log", "flowers": true})
	# Раскосы фахверка между окнами.
	for x: float in [-1.1, 1.1]:
		for s: float in [-1.0, 1.0]:
			g.box("log", Vector3(x + s * 0.32, BASE + 3.6, ud * 0.5 + 0.06), Vector3(0.12, 2.0, 0.08), col("log", rng), 0.02,
				Basis(Vector3.BACK, s * 0.42))
	gable_roof(g, rng, Vector3(0, BASE + 4.7, 0), uw, ud, 2.2, "plank_dark", "shingle", 0.5, "plank", "")
	_chimney(g, rng, Vector3(-2.0, BASE + 4.7, -1.0), 0.7, 2.6, "stone")
	_hanging_sign(g, rng, Vector3(w * 0.5 + 0.05, BASE + 2.3, d * 0.5 - 0.1), 1.0, "plank", "log")
	# Бочки (под окном, не у самой двери) и скамья у входа.
	g.tag = "yard"
	_barrel(g, rng, Vector3(-2.45, 0.0, d * 0.5 + 0.55))
	_barrel(g, rng, Vector3(-2.95, 0.0, d * 0.5 + 0.75), 0.7, 0.27)
	g.tag = ""
	g.box("plank", Vector3(1.5, 0.45, d * 0.5 + 0.45), Vector3(1.6, 0.08, 0.36), col("plank", rng), 0.02)
	for x: float in [0.85, 2.15]:
		g.box("plank", Vector3(x, 0.22, d * 0.5 + 0.45), Vector3(0.08, 0.44, 0.3), col("plank", rng).darkened(0.1), 0.01)


static func _bakery(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 5.0
	var d := 4.2
	plinth(g, rng, w + 0.3, d + 0.3, "stone_block")
	walls(g, rng, w, d, BASE, 2.8, "stone_block", [
		{"side": "front", "u": 0.7, "w": 1.0, "h": 2.0, "type": "door"},
		{"side": "front", "u": -1.3, "v": 0.9, "w": 1.1, "h": 1.0},
		{"side": "left", "u": 0.0, "v": 0.9, "w": 0.85, "h": 1.0},
		{"side": "back", "u": 0.0, "v": 0.9, "w": 0.85, "h": 1.0},
	], {"frame": "plank", "door": "plank", "glass": true, "quoins": true, "flowers": true, "canopy": true})
	gable_roof(g, rng, Vector3(0, BASE + 2.84, 0), w, d, 1.9, "plank_dark", "shingle", 0.45, "stone_block", "")
	# Хлебная печь-купол сбоку, с трубой и светящимся устьем.
	var ov := Vector3(w * 0.5 + 1.05, 0, 0.2)
	g.box("stone_block", ov + Vector3(0, 0.4, 0), Vector3(1.9, 0.8, 2.0), col("stone_block", rng), 0.05)
	lathe(g, "brick", ov + Vector3(0, 0.8, 0), [Vector2(0.88, 0.0), Vector2(0.88, 0.3), Vector2(0.72, 0.78), Vector2(0.42, 1.08),
		Vector2(0.0, 1.18)], 14, rng, 0.06)
	g.box("brick", ov + Vector3(0, 1.15, 0.86), Vector3(0.7, 0.55, 0.3), col("brick", rng), 0.04)
	g.box("opening", ov + Vector3(0, 1.08, 1.0), Vector3(0.42, 0.34, 0.04), GD.MATERIALS["opening"]["color"])
	_chimney(g, rng, ov + Vector3(0.0, 1.6, -0.45), 0.42, 1.5, "brick")
	# Вывеска-крендель.
	var sign_at := Vector3(-w * 0.5 - 0.05, BASE + 2.4, d * 0.5 - 0.15)
	g.rod("plank_dark", sign_at, sign_at + Vector3(0, 0, 0.95), 0.045, 0.045, 5, col("plank_dark", rng), false)
	var pretzel := sign_at + Vector3(0, -0.45, 0.6)
	var bread := Color(0.82, 0.55, 0.24)
	for i in 10:
		var a0 := TAU * i / 10.0
		var a1 := TAU * (i + 1) / 10.0
		g.rod("crop", pretzel + Vector3(0, sin(a0) * 0.22, cos(a0) * 0.28), pretzel + Vector3(0, sin(a1) * 0.22, cos(a1) * 0.28), 0.05, 0.05, 5, bread, false)
	g.rod("crop", pretzel + Vector3(0, 0.22, 0), pretzel + Vector3(0, -0.12, 0.18), 0.05, 0.05, 5, bread, false)
	g.rod("crop", pretzel + Vector3(0, 0.22, 0), pretzel + Vector3(0, -0.12, -0.18), 0.05, 0.05, 5, bread, false)
	# Поленница для печи у задней стены.
	g.tag = "yard"
	for row in 3:
		for i in 6:
			var x := -1.9 + i * 0.32 + (row % 2) * 0.16
			g.rod("log", Vector3(x, 0.14 + row * 0.25, -d * 0.5 - 0.15), Vector3(x, 0.14 + row * 0.25, -d * 0.5 - 0.85), 0.12, 0.12, 6,
				col("log", rng, 0.12))
	g.tag = ""


static func _stable(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 8.0
	var d := 4.2
	plinth(g, rng, w + 0.3, d + 0.3, "stone")
	walls(g, rng, w, d, BASE, 2.7, "plank_v", [
		{"side": "front", "u": -2.6, "w": 1.3, "h": 1.95, "type": "door"},
		{"side": "front", "u": 0.0, "w": 1.3, "h": 1.95, "type": "door"},
		{"side": "front", "u": 2.6, "w": 1.3, "h": 1.95, "type": "door"},
		{"side": "left", "u": 0.0, "v": 1.3, "w": 0.8, "h": 0.7},
		{"side": "right", "u": 0.0, "v": 1.3, "w": 0.8, "h": 0.7},
	], {"frame": "log", "door": "plank_dark", "corner_trim": "log", "canopy": false})
	# Косые перекладины на воротах стойл.
	for x: float in [-2.6, 0.0, 2.6]:
		g.box("log", Vector3(x, BASE + 0.95, d * 0.5 + 0.1), Vector3(0.1, 1.9, 0.06), col("log", rng), 0.02, Basis(Vector3.BACK, 0.55))
	gable_roof(g, rng, Vector3(0, BASE + 2.7, 0), w, d, 1.7, "plank_dark", "boards", 0.6, "plank_v", "")
	# Дверца сеновала во фронтоне и тюки сена.
	g.box("plank_dark", Vector3(w * 0.5 + 0.05, BASE + 3.4, 0), Vector3(0.08, 0.8, 0.9), col("plank_dark", rng), 0.02)
	g.tag = "yard"
	for p: Vector3 in [Vector3(-w * 0.5 - 0.6, 0.3, 1.0), Vector3(-w * 0.5 - 0.6, 0.3, 0.1), Vector3(-w * 0.5 - 0.6, 0.85, 0.55)]:
		g.box("hay", p, Vector3(0.6, 0.55, 0.85), col("hay", rng, 0.08), 0.06)
	# Поилка у входа.
	_trough(g, rng, Vector3(1.3, 0, d * 0.5 + 0.9), 1.6)
	g.tag = ""


static func _town_hall(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 7.0
	var d := 5.0
	plinth(g, rng, w + 0.3, d + 0.3, "stone_block")
	walls(g, rng, w, d, BASE, 2.7, "stone_block", [
		{"side": "front", "u": 0.0, "w": 1.4, "h": 2.2, "type": "door"},
		{"side": "front", "u": -2.4, "v": 0.9, "w": 0.9, "h": 1.2},
		{"side": "front", "u": 2.4, "v": 0.9, "w": 0.9, "h": 1.2},
		{"side": "left", "u": 0.0, "v": 0.9, "w": 0.9, "h": 1.2},
		{"side": "right", "u": 0.0, "v": 0.9, "w": 0.9, "h": 1.2},
		{"side": "back", "u": -1.5, "v": 0.9, "w": 0.9, "h": 1.2},
		{"side": "back", "u": 1.5, "v": 0.9, "w": 0.9, "h": 1.2},
	], {"frame": "stone_block", "door": "plank_dark", "glass": true, "quoins": true, "canopy": true})
	g.box("stone_block", Vector3(0, BASE + 2.76, 0), Vector3(w + 0.24, 0.16, d + 0.24), col("stone_block", rng), 0.04)
	walls(g, rng, w, d, BASE + 2.84, 2.3, "plank", [
		{"side": "front", "u": -2.4, "v": 0.5, "w": 0.85, "h": 1.15},
		{"side": "front", "u": 0.0, "v": 0.5, "w": 0.85, "h": 1.15},
		{"side": "front", "u": 2.4, "v": 0.5, "w": 0.85, "h": 1.15},
		{"side": "back", "u": 0.0, "v": 0.5, "w": 0.85, "h": 1.15},
		{"side": "left", "u": 0.0, "v": 0.5, "w": 0.85, "h": 1.15},
		{"side": "right", "u": 0.0, "v": 0.5, "w": 0.85, "h": 1.15},
	], {"frame": "plank_dark", "glass": true, "corner_trim": "plank_dark", "flowers": true})
	gable_roof(g, rng, Vector3(0, BASE + 5.14, 0), w, d, 2.3, "roof_tile", "tile", 0.45, "plank", "")
	# Башня с часами над входом.
	var tz := d * 0.5 - 1.0
	var ty := BASE + 5.14
	g.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, tz)))
	walls(g, rng, 1.7, 1.7, ty, 2.4, "plank", [
		{"side": "left", "u": 0.0, "v": 1.2, "w": 0.6, "h": 0.8},
		{"side": "right", "u": 0.0, "v": 1.2, "w": 0.6, "h": 0.8},
		{"side": "back", "u": 0.0, "v": 1.2, "w": 0.6, "h": 0.8},
	], {"frame": "plank_dark", "corner_trim": "plank_dark"})
	g.pop()
	var face := Vector3(0, ty + 1.45, tz + 0.88)
	g.cylinder("stone_block", face, 0.52, 0.52, 0.06, 18, col("stone_block", rng).lightened(0.25), true, true, 0.0, Basis(Vector3.RIGHT, PI * 0.5))
	for k in 12:
		var a := TAU * k / 12.0
		g.box("plank_dark", face + Vector3(cos(a) * 0.42, sin(a) * 0.42, 0.07), Vector3.ONE * 0.06, col("plank_dark", rng).darkened(0.3))
	g.box("plank_dark", face + Vector3(0.0, 0.14, 0.09), Vector3(0.05, 0.3, 0.03), col("plank_dark", rng).darkened(0.4))
	g.box("plank_dark", face + Vector3(0.14, 0.04, 0.1), Vector3(0.3, 0.05, 0.03), col("plank_dark", rng).darkened(0.4), 0.0, Basis(Vector3.BACK, 0.4))
	pyramid_roof(g, rng, Vector3(0, ty + 2.42, tz), 0.85, 1.9, "roof_tile", 0.25)
	g.rod("plank_dark", Vector3(0, ty + 4.2, tz), Vector3(0, ty + 5.0, tz), 0.04, 0.03, 5, col("plank_dark", rng))


static func _storehouse(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 5.6
	var d := 4.0
	var floor_y := 0.85
	# Амбар на каменных столбиках: мыши не доберутся.
	for x: float in [-2.5, 0.0, 2.5]:
		for z: float in [-1.7, 1.7]:
			g.box("stone", Vector3(x, (UNDER + floor_y) * 0.5, z), Vector3(0.45, floor_y - UNDER, 0.45), col("stone", rng), 0.06)
			g.box("stone", Vector3(x, floor_y - 0.05, z), Vector3(0.62, 0.1, 0.62), col("stone", rng).lightened(0.05), 0.03)
	g.box("plank_dark", Vector3(0, floor_y + 0.08, 0), Vector3(w + 0.3, 0.16, d + 0.3), col("plank_dark", rng), 0.03)
	walls(g, rng, w, d, floor_y + 0.16, 2.5, "plank_v", [
		{"side": "front", "u": 0.0, "w": 1.8, "h": 2.0, "type": "door"},
		{"side": "left", "u": 0.0, "v": 1.4, "w": 0.6, "h": 0.5},
		{"side": "right", "u": 0.0, "v": 1.4, "w": 0.6, "h": 0.5},
	], {"frame": "log", "door": "plank_dark", "corner_trim": "log"})
	gable_roof(g, rng, Vector3(0, floor_y + 2.66, 0), w, d, 1.7, "plank_dark", "boards", 0.5, "plank_v", "")
	# Пандус к воротам и ящики.
	# Пандус спускается от ворот к земле (вдоль +Z, наружу).
	var ramp := Basis(Vector3.RIGHT, atan2(floor_y + 0.1, 1.6))
	for i in 6:
		g.box("plank", Vector3(-0.9 + (i + 0.5) * 0.3, (floor_y + 0.1) * 0.5, d * 0.5 + 0.95), Vector3(0.28, 0.06, 1.85),
			col("plank", rng, 0.08), 0.01, ramp)
	g.tag = "yard"
	for p: Vector3 in [Vector3(2.2, 0.3, d * 0.5 + 0.7), Vector3(2.75, 0.3, d * 0.5 + 0.55), Vector3(2.45, 0.9, d * 0.5 + 0.62)]:
		_crate(g, rng, p, 0.6, rng.randf_range(-0.3, 0.3))
	g.tag = ""


static func _dovecote(g: Geo, rng: RandomNumberGenerator) -> void:
	var r := 1.45
	var h := 4.4
	g.cylinder("stone", Vector3(0, UNDER, 0), r + 0.12, r + 0.12, -UNDER + 0.1, 14, col("stone", rng).darkened(0.3), false)
	var ops := [{"angle": PI * 0.5, "v": 0.0, "w": 0.85, "h": 1.75, "type": "door"}]
	for k in 5:
		ops.append({"angle": PI * 0.5 + (k + 0.5) * TAU / 5.0, "v": 3.0, "w": 0.34, "h": 0.42})
	round_wall(g, rng, Vector3.ZERO, r, r * 0.92, h, "stone", ops, {"frame": "plank", "door": "plank_dark"})
	# Карниз и пояс-«полка» под летками.
	lathe(g, "stone", Vector3(0, 2.86, 0), [Vector2(r * 0.93, 0.0), Vector2(r * 1.05, 0.06), Vector2(r * 1.05, 0.14), Vector2(r * 0.93, 0.16)], 16, rng, 0.03)
	var top := Vector3(0, h, 0)
	lathe(g, "plank_dark", top, [Vector2(r * 1.2, 0.0), Vector2(r * 1.2, 0.08), Vector2(r * 0.7, 0.9), Vector2(r * 0.22, 1.55), Vector2(0.0, 1.62)], 16, rng, 0.06)
	# Фонарик-домик на макушке.
	g.box("plank", top + Vector3(0, 1.75, 0), Vector3(0.4, 0.35, 0.4), col("plank", rng), 0.03)
	pyramid_roof(g, rng, top + Vector3(0, 1.92, 0), 0.2, 0.4, "plank_dark", 0.08)
	# Голуби на полке и крыше.
	for k in 4:
		var a := PI * 0.5 + 0.4 + k * 1.1
		var at := Vector3(cos(a) * r * 1.02, 3.04, sin(a) * r * 1.02) if k < 3 else top + Vector3(0.5, 0.5, 0.3)
		var bird := Color(0.92, 0.92, 0.9) if k % 2 == 0 else Color(0.62, 0.64, 0.7)
		g.blob("crop", at + Vector3(0, 0.08, 0), Vector3(0.1, 0.08, 0.14), bird, rng, 0, 0.05, 0.2)
		g.blob("crop", at + Vector3(0, 0.17, 0.08), Vector3.ONE * 0.055, bird, rng, 0, 0.05, 0.2)


static func _bathhouse(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 4.2
	var d := 3.4
	g.box("log", Vector3(0, (UNDER + 0.2) * 0.5, 0), Vector3(w + 0.4, 0.2 - UNDER, d + 0.4), col("log", rng).darkened(0.3))
	walls(g, rng, w, d, 0.2, 2.2, "log", [
		{"side": "front", "u": 1.0, "w": 0.85, "h": 1.7, "type": "door"},
		{"side": "front", "u": -0.9, "v": 1.0, "w": 0.55, "h": 0.5},
		{"side": "left", "u": 0.0, "v": 1.0, "w": 0.55, "h": 0.5},
	], {"frame": "log_dark", "door": "plank_dark", "thickness": 0.34, "canopy": true})
	gable_roof(g, rng, Vector3(0, 2.4, 0), w, d, 1.3, "plank_dark", "boards", 0.45, "log", "")
	_chimney(g, rng, Vector3(-1.2, 2.4, -0.6), 0.5, 1.6, "stone")
	# Лавка, кадушка и веники у стены.
	g.tag = "yard"
	g.box("plank", Vector3(-0.9, 0.45, d * 0.5 + 0.4), Vector3(1.5, 0.08, 0.36), col("plank", rng), 0.02)
	for x: float in [-1.5, -0.3]:
		g.box("plank", Vector3(x, 0.22, d * 0.5 + 0.4), Vector3(0.08, 0.44, 0.3), col("plank", rng).darkened(0.1), 0.01)
	# Кадушка — сбоку у задней стены: спереди она заслоняла дверь.
	_barrel(g, rng, Vector3(w * 0.5 + 0.5, 0.0, -0.9), 0.55, 0.32)
	g.tag = ""
	for k in 3:
		var at := Vector3(-0.4 + k * 0.25, 1.75, d * 0.5 + 0.2)
		g.rod("log", at, at + Vector3(0, -0.4, 0.02), 0.02, 0.02, 3, col("log", rng), false)
		g.blob("crop", at + Vector3(0, -0.55, 0.03), Vector3(0.1, 0.18, 0.06), Color(0.42, 0.52, 0.24), rng, 0, 0.15, 0.2)


static func _manor(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 8.4
	var d := 5.4
	plinth(g, rng, w + 0.3, d + 0.3, "stone_block")
	walls(g, rng, w, d, BASE, 2.6, "stone_block", [
		{"side": "front", "u": 0.0, "w": 1.2, "h": 2.1, "type": "door"},
		{"side": "front", "u": -3.0, "v": 0.85, "w": 0.85, "h": 1.15},
		{"side": "front", "u": -1.6, "v": 0.85, "w": 0.85, "h": 1.15},
		{"side": "front", "u": 1.6, "v": 0.85, "w": 0.85, "h": 1.15},
		{"side": "front", "u": 3.0, "v": 0.85, "w": 0.85, "h": 1.15},
		{"side": "left", "u": -1.0, "v": 0.85, "w": 0.85, "h": 1.15},
		{"side": "left", "u": 1.0, "v": 0.85, "w": 0.85, "h": 1.15},
		{"side": "right", "u": -1.0, "v": 0.85, "w": 0.85, "h": 1.15},
		{"side": "right", "u": 1.0, "v": 0.85, "w": 0.85, "h": 1.15},
		{"side": "back", "u": -2.0, "v": 0.85, "w": 0.85, "h": 1.15},
		{"side": "back", "u": 2.0, "v": 0.85, "w": 0.85, "h": 1.15},
	], {"frame": "stone_block", "door": "plank", "glass": true, "quoins": true, "flowers": true})
	g.box("stone_block", Vector3(0, BASE + 2.66, 0), Vector3(w + 0.24, 0.16, d + 0.24), col("stone_block", rng), 0.04)
	var up := []
	for u: float in [-3.0, -1.6, 0.0, 1.6, 3.0]:
		up.append({"side": "front", "u": u, "v": 0.45, "w": 0.8, "h": 1.1})
	for u: float in [-2.0, 0.0, 2.0]:
		up.append({"side": "back", "u": u, "v": 0.45, "w": 0.8, "h": 1.1})
	for u: float in [-1.0, 1.0]:
		up.append({"side": "left", "u": u, "v": 0.45, "w": 0.8, "h": 1.1})
		up.append({"side": "right", "u": u, "v": 0.45, "w": 0.8, "h": 1.1})
	walls(g, rng, w, d, BASE + 2.74, 2.3, "brick", up, {"frame": "stone_block", "glass": true, "quoins": true, "sill": "stone_block", "flowers": true})
	var roof_y := BASE + 5.04
	gable_roof(g, rng, Vector3(0, roof_y, 0), w, d, 2.5, "roof_tile", "tile", 0.5, "brick", "")
	# Слуховые окна на переднем скате.
	for x: float in [-2.2, 2.2]:
		var at := Vector3(x, roof_y + 0.55, d * 0.5 - 0.55)
		g.box("brick", at + Vector3(0, 0.25, -0.2), Vector3(1.0, 1.0, 1.2), col("brick", rng), 0.03)
		g.push(Transform3D(Basis.IDENTITY, at + Vector3(-0.3, -0.1, 0.42)))
		window(g, rng, Rect2(0, 0.0, 0.6, 0.7), "stone_block", true, 0.15)
		g.pop()
		gable_roof(g, rng, at + Vector3(0, 0.78, -0.2), 1.0, 1.2, 0.55, "roof_tile", "tile", 0.15, "brick", "")
	# Крыльцо с колоннами и ступенями.
	var pz := d * 0.5 + 1.0
	for x: float in [-1.1, 1.1]:
		g.cylinder("stone_block", Vector3(x, BASE, pz + 0.4), 0.16, 0.14, 2.35, 10, col("stone_block", rng).lightened(0.05), true)
		g.box("stone_block", Vector3(x, BASE + 0.08, pz + 0.4), Vector3(0.42, 0.16, 0.42), col("stone_block", rng), 0.03)
	g.box("stone_block", Vector3(0, BASE * 0.5, pz), Vector3(2.8, BASE + 0.02, 2.0), col("stone_block", rng), 0.04)
	g.box("stone_block", Vector3(0, 0.08, pz + 1.15), Vector3(2.4, 0.16, 0.4), col("stone_block", rng).darkened(0.05), 0.03)
	gable_roof(g, rng, Vector3(0, BASE + 2.4, pz - 0.1), 2.8, 2.2, 0.8, "roof_tile", "tile", 0.15, "plank", "")
	for x: float in [-2.6, 2.6]:
		_chimney(g, rng, Vector3(x, roof_y, -0.9), 0.6, 2.8, "brick")


static func _guardhouse(g: Geo, rng: RandomNumberGenerator) -> void:
	var s := 4.4
	var h := 3.2
	plinth(g, rng, s + 0.3, s + 0.3, "stone_block")
	walls(g, rng, s, s, BASE, h, "stone_big", [
		{"side": "front", "u": 0.0, "w": 1.0, "h": 2.0, "type": "door"},
		{"side": "left", "u": 0.0, "v": 1.1, "w": 0.26, "h": 0.9},
		{"side": "right", "u": 0.0, "v": 1.1, "w": 0.26, "h": 0.9},
		{"side": "back", "u": -0.9, "v": 1.1, "w": 0.26, "h": 0.9},
		{"side": "back", "u": 0.9, "v": 1.1, "w": 0.26, "h": 0.9},
	], {"frame": "stone_block", "door": "plank_dark", "quoins": true})
	var top := BASE + h
	g.box("stone_block", Vector3(0, top + 0.08, 0), Vector3(s + 0.3, 0.16, s + 0.3), col("stone_block", rng), 0.04)
	var hs := s * 0.5 + 0.05
	battlements(g, rng, Vector3(-hs, top + 0.16, hs), Vector3(hs, top + 0.16, hs), 0.4, "stone_block")
	battlements(g, rng, Vector3(-hs, top + 0.16, -hs), Vector3(hs, top + 0.16, -hs), 0.4, "stone_block")
	battlements(g, rng, Vector3(-hs, top + 0.16, -hs), Vector3(-hs, top + 0.16, hs), 0.4, "stone_block")
	battlements(g, rng, Vector3(hs, top + 0.16, -hs), Vector3(hs, top + 0.16, hs), 0.4, "stone_block")
	# Дозорная будка на крыше и стойка с копьями у входа.
	g.box("plank", Vector3(-0.6, top + 0.9, -0.6), Vector3(1.4, 1.4, 1.4), col("plank", rng), 0.04)
	pyramid_roof(g, rng, Vector3(-0.6, top + 1.6, -0.6), 0.7, 0.9, "plank_dark", 0.2)
	g.box("plank_dark", Vector3(1.6, 0.9, s * 0.5 + 0.3), Vector3(0.9, 0.08, 0.12), col("plank_dark", rng), 0.01)
	for k in 4:
		var x := 1.25 + k * 0.23
		g.rod("log", Vector3(x, 0.0, s * 0.5 + 0.35), Vector3(x + 0.05, 2.0, s * 0.5 + 0.2), 0.025, 0.02, 4, col("log", rng), false)
		g.cylinder("stone", Vector3(x + 0.05, 2.0, s * 0.5 + 0.2), 0.045, 0.0, 0.22, 4, col("stone", rng).darkened(0.2), false)


static func _gatehouse(g: Geo, rng: RandomNumberGenerator) -> void:
	var tw := 2.4
	var gap := 2.8
	var h := 5.2
	var d := 3.4
	for sx: float in [-1.0, 1.0]:
		var cx := sx * (gap * 0.5 + tw * 0.5)
		g.push(Transform3D(Basis.IDENTITY, Vector3(cx, 0, 0)))
		plinth(g, rng, tw + 0.3, d + 0.3, "stone_block")
		walls(g, rng, tw, d, BASE, h, "stone_big", [
			{"side": "front", "u": 0.0, "v": 2.2, "w": 0.26, "h": 0.9},
			{"side": "back", "u": 0.0, "v": 2.2, "w": 0.26, "h": 0.9},
		], {"frame": "stone_block", "quoins": true})
		var hx := tw * 0.5 + 0.05
		var hz := d * 0.5 + 0.05
		var top := BASE + h
		g.box("stone_block", Vector3(0, top + 0.08, 0), Vector3(tw + 0.3, 0.16, d + 0.3), col("stone_block", rng), 0.04)
		battlements(g, rng, Vector3(-hx, top + 0.16, hz), Vector3(hx, top + 0.16, hz), 0.4, "stone_block")
		battlements(g, rng, Vector3(-hx, top + 0.16, -hz), Vector3(hx, top + 0.16, -hz), 0.4, "stone_block")
		battlements(g, rng, Vector3(sx * hx, top + 0.16, -hz), Vector3(sx * hx, top + 0.16, hz), 0.4, "stone_block")
		g.pop()
	# Перемычка над проездом с зубцами.
	var arch_y := BASE + 3.1
	g.box("stone_block", Vector3(0, (arch_y + BASE + h) * 0.5, 0), Vector3(gap + 0.1, BASE + h - arch_y, d - 0.4), col("stone_block", rng).darkened(0.05), 0.04)
	for k in 7:
		var x := -gap * 0.5 + (k + 0.5) * gap / 7.0
		g.box("stone_block", Vector3(x, arch_y + 0.05, d * 0.5 - 0.15), Vector3(gap / 7.0 - 0.04, 0.34, 0.2), col("stone_block", rng, 0.08), 0.04,
			Basis(Vector3.BACK, (x / gap) * 0.5))
	battlements(g, rng, Vector3(-gap * 0.5, BASE + h + 0.16, d * 0.5 - 0.2), Vector3(gap * 0.5, BASE + h + 0.16, d * 0.5 - 0.2), 0.4, "stone_block")
	g.box("stone_block", Vector3(0, BASE + h + 0.08, 0), Vector3(gap, 0.16, d - 0.4), col("stone_block", rng), 0.04)
	# Распахнутые створки ворот и мостовая проезда.
	for sx: float in [-1.0, 1.0]:
		var hinge := Vector3(sx * gap * 0.5, BASE, d * 0.5 - 0.35)
		var leaf := Basis(Vector3.UP, sx * 1.2)
		g.push(Transform3D(leaf, hinge))
		g.box("plank_dark", Vector3(-sx * gap * 0.25, 1.4, 0), Vector3(gap * 0.48, 2.8, 0.1), col("plank_dark", rng), 0.02)
		for y: float in [0.5, 1.4, 2.3]:
			g.box("log", Vector3(-sx * gap * 0.25, y, 0.08), Vector3(gap * 0.46, 0.14, 0.06), col("log", rng), 0.02)
		g.pop()
	for i in 6:
		for j in 4:
			g.tile("stone", Vector3(-gap * 0.5 + (j + 0.5) * gap / 4.0, 0.03, -d * 0.5 + (i + 0.5) * d / 6.0), Vector3.UP, Vector3.FORWARD,
				gap / 4.0 - 0.06, d / 6.0 - 0.06, 0.05, 0.03, col("stone", rng, 0.1))


# =====================================================================================
#  Декор двора
# =====================================================================================

static func _crate(g: Geo, rng: RandomNumberGenerator, center: Vector3, size: float, yaw := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	g.box("plank", center, Vector3.ONE * size, col("plank", rng, 0.08), 0.02, b)
	var c := col("plank", rng).darkened(0.18)
	for s: float in [-1.0, 1.0]:
		g.box("plank", center + b * Vector3(0, 0, s * size * 0.5), Vector3(size * 1.02, 0.07, 0.03), c, 0.0, b)
		g.box("plank", center + b * Vector3(0, s * size * 0.42, size * 0.51), Vector3(size * 1.0, 0.06, 0.02), c, 0.0, b)
		g.box("plank", center + b * Vector3(s * size * 0.51, 0, 0), Vector3(0.03, size * 0.9, 0.07), c, 0.0, b * Basis(Vector3.RIGHT, 0.785))


static func _trough(g: Geo, rng: RandomNumberGenerator, at: Vector3, length := 1.8) -> void:
	for x: float in [-length * 0.38, length * 0.38]:
		g.box("log", at + Vector3(x, 0.2, 0), Vector3(0.14, 0.4, 0.6), col("log", rng), 0.03)
	g.box("plank_dark", at + Vector3(0, 0.38, 0), Vector3(length, 0.06, 0.6), col("plank_dark", rng), 0.01)
	for s: float in [-1.0, 1.0]:
		g.box("plank_dark", at + Vector3(0, 0.55, s * 0.28), Vector3(length, 0.34, 0.06), col("plank_dark", rng), 0.01)
		g.box("plank_dark", at + Vector3(s * length * 0.5, 0.55, 0), Vector3(0.06, 0.34, 0.6), col("plank_dark", rng), 0.01)
	g.box("water", at + Vector3(0, 0.66, 0), Vector3(length - 0.1, 0.02, 0.5), col("water", rng, 0.03))


static func _haystack(g: Geo, rng: RandomNumberGenerator) -> void:
	var profile := [Vector2(1.15, -0.1), Vector2(1.25, 0.35), Vector2(1.18, 0.75), Vector2(1.05, 1.15), Vector2(0.82, 1.55),
		Vector2(0.48, 1.95), Vector2(0.18, 2.15), Vector2(0.0, 2.22)]
	lathe(g, "hay", Vector3.ZERO, profile, 14, rng, 0.14)
	# Пучки соломы торчат во все стороны, внизу — потемневшая подстилка.
	for i in 90:
		var a := rng.randf() * TAU
		var y := rng.randf_range(0.0, 2.05)
		var r := lerpf(1.24, 0.25, pow(y / 2.15, 1.6))
		var dir := Vector3(cos(a), rng.randf_range(-0.6, 0.3), sin(a)).normalized()
		var c := col("hay", rng, 0.18).lightened(rng.randf_range(-0.08, 0.12))
		g.box("hay", Vector3(cos(a) * r, y, sin(a) * r), Vector3(0.035, 0.025, rng.randf_range(0.25, 0.45)), c, 0.0,
			Basis.looking_at(dir, Vector3.UP))
	g.cylinder("hay", Vector3(0, -0.1, 0), 1.32, 1.28, 0.16, 14, col("hay", rng).darkened(0.32), true)
	# Две верёвки поперёк стога.
	for k in 2:
		var yaw := Basis(Vector3.UP, k * PI * 0.5 + 0.3)
		var prev := Vector3.ZERO
		for i in 13:
			var t := float(i) / 12.0
			var ang := lerpf(-PI * 0.5, PI * 0.5, t)
			var p := yaw * Vector3(sin(ang) * 1.22, cos(ang) * 2.05 + 0.08, 0)
			if i > 0:
				g.rod("log", prev, p, 0.022, 0.022, 4, col("log", rng).lightened(0.15), false)
			prev = p
	g.rod("log", Vector3(0, 1.4, 0), Vector3(0.05, 2.75, 0.02), 0.05, 0.04, 5, col("log", rng))


static func _woodpile(g: Geo, rng: RandomNumberGenerator) -> void:
	var length := 2.4
	for x: float in [-length * 0.5 - 0.1, length * 0.5 + 0.1]:
		for z: float in [-0.35, 0.35]:
			g.rod("log", Vector3(x, -0.3, z), Vector3(x, 1.7, z), 0.06, 0.05, 5, col("log", rng))
	for row in 6:
		var n := 9 - (row % 2)
		for i in n:
			var x := -length * 0.5 + (i + 0.5 + (row % 2) * 0.5) * length / 9.0
			var y := 0.12 + row * 0.22
			g.rod("log", Vector3(x, y, -0.42), Vector3(x + rng.randf_range(-0.02, 0.02), y, 0.42), 0.11, 0.11, 6, col("log", rng, 0.14))
			g.cylinder("plank", Vector3(x, y, 0.42), 0.095, 0.095, 0.01, 6, col("plank", rng, 0.1).lightened(0.1), true, false, 0.0,
				Basis(Vector3.RIGHT, PI * 0.5))
	var roof := Basis(Vector3.RIGHT, 0.18)
	g.box("plank", Vector3(0, 1.82, 0.05), Vector3(length + 0.6, 0.06, 1.25), col("plank", rng), 0.01, roof)


static func _barrels(g: Geo, rng: RandomNumberGenerator) -> void:
	_barrel(g, rng, Vector3(-0.4, 0, 0))
	_barrel(g, rng, Vector3(0.3, 0, -0.25), 0.9, 0.33)
	_barrel(g, rng, Vector3(0.55, 0.3, 0.55), 0.8, 0.3, Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.RIGHT, 0.3))
	# Круглая деревянная крышка с ручкой на стоящей бочке.
	g.cylinder("plank", Vector3(-0.4, 0.795, 0), 0.265, 0.265, 0.035, 14, col("plank", rng), true, true)
	g.box("plank_dark", Vector3(-0.4, 0.85, 0), Vector3(0.2, 0.035, 0.05), col("plank_dark", rng), 0.01)


static func _crates(g: Geo, rng: RandomNumberGenerator) -> void:
	_crate(g, rng, Vector3(-0.35, 0.35, 0), 0.7, 0.1)
	_crate(g, rng, Vector3(0.4, 0.3, 0.1), 0.6, -0.25)
	_crate(g, rng, Vector3(-0.2, 0.98, 0.05), 0.56, 0.5)
	for i in 3:
		g.blob("crop", Vector3(-0.2 + (i - 1) * 0.14, 1.32, 0.05), Vector3.ONE * 0.07, Color(0.82, 0.18, 0.12).lightened(rng.randf() * 0.1), rng, 0, 0.05)


static func _cart(g: Geo, rng: RandomNumberGenerator) -> void:
	var bed_y := 0.75
	g.box("plank", Vector3(0, bed_y, 0), Vector3(1.4, 0.08, 2.2), col("plank", rng), 0.02)
	for s: float in [-1.0, 1.0]:
		g.box("plank", Vector3(s * 0.7, bed_y + 0.22, 0), Vector3(0.06, 0.36, 2.2), col("plank", rng).darkened(0.06), 0.01)
		g.box("plank", Vector3(0, bed_y + 0.22, s * 1.1), Vector3(1.4, 0.36, 0.06), col("plank", rng).darkened(0.06), 0.01)
	g.rod("log", Vector3(-0.85, 0.45, -0.3), Vector3(0.85, 0.45, -0.3), 0.06, 0.06, 6, col("log", rng))
	for s: float in [-1.0, 1.0]:
		var hub := Vector3(s * 0.85, 0.45, -0.3)
		var wheel := Basis(Vector3.BACK, PI * 0.5)
		g.cylinder("plank_dark", hub - Vector3(s * 0.05, 0, 0), 0.45, 0.45, 0.1, 14, col("plank_dark", rng), true, true, 0.0, wheel)
		g.cylinder("plank", hub - Vector3(s * 0.06, 0, 0), 0.08, 0.08, 0.12, 8, col("plank", rng).darkened(0.2), true, true, 0.0, wheel)
		# Оглобли упираются в землю.
		g.rod("log", Vector3(s * 0.45, bed_y - 0.05, 1.0), Vector3(s * 0.4, 0.05, 2.5), 0.05, 0.045, 5, col("log", rng), false)
	g.blob("hay", Vector3(0, bed_y + 0.45, -0.2), Vector3(0.6, 0.38, 0.85), col("hay", rng), rng, 1, 0.15, 0.2)


static func _scarecrow(g: Geo, rng: RandomNumberGenerator) -> void:
	g.rod("log", Vector3(0, -0.5, 0), Vector3(0, 1.9, 0), 0.06, 0.05, 6, col("log", rng))
	g.rod("log", Vector3(-0.85, 1.45, 0), Vector3(0.85, 1.45, 0), 0.045, 0.045, 5, col("log", rng))
	var shirt := Color(0.62, 0.22, 0.18) if rng.randf() < 0.5 else Color(0.3, 0.42, 0.62)
	g.box("crop", Vector3(0, 1.2, 0), Vector3(0.6, 0.65, 0.3), shirt, 0.06)
	for s: float in [-1.0, 1.0]:
		g.box("crop", Vector3(s * 0.52, 1.43, 0), Vector3(0.48, 0.2, 0.22), shirt.darkened(0.1), 0.05)
		g.blob("hay", Vector3(s * 0.85, 1.43, 0), Vector3(0.12, 0.08, 0.08), col("hay", rng), rng, 0, 0.3)
	g.box("crop", Vector3(0, 0.8, 0), Vector3(0.5, 0.25, 0.26), Color(0.42, 0.34, 0.24), 0.05)
	g.blob("hay", Vector3(0, 1.75, 0), Vector3(0.2, 0.22, 0.2), col("hay", rng).lightened(0.1), rng, 1, 0.1)
	lathe(g, "plank_dark", Vector3(0, 1.9, 0), [Vector2(0.38, 0.0), Vector2(0.38, 0.03), Vector2(0.18, 0.06), Vector2(0.16, 0.28), Vector2(0.0, 0.3)], 10, rng)


static func _beehives(g: Geo, rng: RandomNumberGenerator) -> void:
	g.box("plank", Vector3(0, 0.45, 0), Vector3(2.2, 0.08, 0.6), col("plank", rng), 0.02)
	for x: float in [-0.95, 0.95]:
		g.box("plank", Vector3(x, 0.22, 0), Vector3(0.1, 0.44, 0.5), col("plank", rng).darkened(0.1), 0.01)
	for k in 3:
		var at := Vector3(-0.7 + k * 0.7, 0.49, 0)
		lathe(g, "hay", at, [Vector2(0.27, 0.0), Vector2(0.28, 0.12), Vector2(0.24, 0.3), Vector2(0.14, 0.44), Vector2(0.0, 0.48)], 10, rng, 0.08)
		for ring in 4:
			g.cylinder("hay", at + Vector3(0, 0.06 + ring * 0.1, 0), 0.28 - ring * 0.03, 0.27 - ring * 0.035, 0.03, 10, col("hay", rng).darkened(0.15), false)
		g.box("opening", at + Vector3(0, 0.05, 0.26), Vector3(0.09, 0.05, 0.03), GD.MATERIALS["opening"]["color"])


static func _trough_decor(g: Geo, rng: RandomNumberGenerator) -> void:
	_trough(g, rng, Vector3.ZERO, 2.0)
	g.rod("log", Vector3(1.25, -0.3, -0.1), Vector3(1.25, 1.2, -0.1), 0.06, 0.05, 6, col("log", rng))
	_barrel(g, rng, Vector3(-1.35, 0, 0.1), 0.6, 0.26)


static func _bench(g: Geo, rng: RandomNumberGenerator) -> void:
	g.box("plank", Vector3(0, 0.45, 0), Vector3(1.6, 0.07, 0.42), col("plank", rng), 0.02)
	g.box("plank", Vector3(0, 0.82, -0.2), Vector3(1.6, 0.25, 0.06), col("plank", rng), 0.02, Basis(Vector3.RIGHT, -0.15))
	for x: float in [-0.68, 0.68]:
		g.box("plank_dark", Vector3(x, 0.22, 0.12), Vector3(0.08, 0.45, 0.08), col("plank_dark", rng), 0.01)
		g.box("plank_dark", Vector3(x, 0.45, -0.18), Vector3(0.08, 0.9, 0.08), col("plank_dark", rng), 0.01)
		g.box("plank_dark", Vector3(x, 0.62, 0.0), Vector3(0.07, 0.06, 0.4), col("plank_dark", rng), 0.01)


static func _signpost(g: Geo, rng: RandomNumberGenerator) -> void:
	for i in 4:
		var a := TAU * i / 4.0 + 0.3
		g.blob("stone", Vector3(cos(a) * 0.22, 0.06, sin(a) * 0.22), Vector3(0.14, 0.1, 0.12), col("stone", rng, 0.12), rng, 1, 0.2)
	g.rod("log", Vector3(0, -0.5, 0), Vector3(0, 2.25, 0), 0.07, 0.06, 6, col("log", rng))
	g.cylinder("log", Vector3(0, 2.25, 0), 0.09, 0.0, 0.16, 6, col("log", rng).darkened(0.1), false)
	for k in 3:
		var yaw := [0.4, 2.2, -1.1][k] as float
		var b := Basis(Vector3.UP, yaw)
		var y := 1.9 - k * 0.34
		var c := col("plank", rng, 0.1)
		g.box("plank", Vector3(0, y, 0) + b * Vector3(0.45, 0, 0), Vector3(0.8, 0.22, 0.04), c, 0.01, b)
		g.tri("plank", Vector3(0, y + 0.11, 0) + b * Vector3(0.85, 0, 0.02), Vector3(0, y - 0.11, 0) + b * Vector3(0.85, 0, 0.02),
			Vector3(0, y, 0) + b * Vector3(1.02, 0, 0.02), c, b * Vector3.BACK)
		g.tri("plank", Vector3(0, y + 0.11, 0) + b * Vector3(0.85, 0, -0.02), Vector3(0, y - 0.11, 0) + b * Vector3(0.85, 0, -0.02),
			Vector3(0, y, 0) + b * Vector3(1.02, 0, -0.02), c, b * Vector3.FORWARD)
		g.box("plank_dark", Vector3(0, y, 0) + b * Vector3(0.45, 0, 0.025), Vector3(0.5, 0.03, 0.01), col("plank_dark", rng).darkened(0.3), 0.0, b)


# =====================================================================================
#  Новые постройки: мельница на воде, маяк, библиотека, колокольня, курятник,
#  рыбацкая хижина, теплица, беседка, фонтан, придорожная часовенка
# =====================================================================================

static func _watermill(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 4.4
	var d := 4.0
	plinth(g, rng, w + 0.3, d + 0.3, "stone")
	walls(g, rng, w, d, BASE, 3.0, "plank", [
		{"side": "right", "u": 0.3, "w": 0.95, "h": 1.9, "type": "door"},
		{"side": "left", "u": 0.0, "v": 1.0, "w": 0.8, "h": 0.8},
		{"side": "back", "u": 0.8, "v": 1.0, "w": 0.8, "h": 0.8},
		{"side": "front", "u": -1.55, "v": 1.6, "w": 0.6, "h": 0.7},
	], {"frame": "plank_dark", "door": "plank_dark", "corner_trim": "log", "canopy": true})
	gable_roof(g, rng, Vector3(0, BASE + 3.0, 0), w, d, 1.8, "plank_dark", "shingle", 0.45, "plank", "")
	var p: Vector3 = ROTOR_PIVOT["watermill"]
	# Ось колеса: из стены к опоре-козлам.
	g.rod("log", Vector3(p.x, p.y, d * 0.5 - 0.1), Vector3(p.x, p.y, p.z + 0.75), 0.13, 0.13, 8, col("log", rng))
	for s: float in [-1.0, 1.0]:
		g.rod("log", Vector3(p.x + s * 0.55, -0.4, p.z + 0.7), Vector3(p.x, p.y + 0.15, p.z + 0.7), 0.1, 0.09, 6, col("log", rng))
	# Яма с водой под колесом: каменный бортик.
	var pit_c := Vector3(p.x, 0, p.z)
	g.box("water", pit_c + Vector3(0, 0.02, 0), Vector3(2.7, 0.08, 1.5), col("water", rng, 0.02))
	for s: float in [-1.0, 1.0]:
		g.box("stone", pit_c + Vector3(s * 1.45, -0.1, 0), Vector3(0.3, 0.6, 1.8), col("stone", rng), 0.06)
	g.box("stone", pit_c + Vector3(0, -0.1, 0.85), Vector3(3.2, 0.6, 0.3), col("stone", rng), 0.06)
	g.box("stone", pit_c + Vector3(0, -0.45, 0), Vector3(2.7, 0.3, 1.5), col("stone", rng).darkened(0.3))
	# Жёлоб на столбах приносит воду на макушку колеса.
	var top := p.y + 1.9 + 0.32
	var x0 := p.x + 0.35
	var x1 := p.x + 4.2
	for x: float in [p.x + 2.0, p.x + 3.6]:
		g.rod("log", Vector3(x, -0.4, p.z), Vector3(x, top - 0.12, p.z), 0.1, 0.09, 6, col("log", rng))
		g.box("log", Vector3(x, top - 0.14, p.z), Vector3(0.16, 0.12, 0.9), col("log", rng), 0.02)
	g.box("plank_dark", Vector3((x0 + x1) * 0.5, top - 0.05, p.z), Vector3(x1 - x0, 0.08, 0.6), col("plank_dark", rng), 0.02)
	for s: float in [-1.0, 1.0]:
		g.box("plank_dark", Vector3((x0 + x1) * 0.5, top + 0.1, p.z + s * 0.28), Vector3(x1 - x0, 0.3, 0.06), col("plank_dark", rng), 0.01)
	g.box("water", Vector3((x0 + x1) * 0.5 + 0.05, top + 0.08, p.z), Vector3(x1 - x0 - 0.1, 0.02, 0.5), col("water", rng, 0.02))
	# Струя с конца жёлоба на лопасти.
	g.box("water", Vector3(x0 - 0.03, top - 0.2, p.z), Vector3(0.08, 0.36, 0.46), col("water", rng, 0.02).lightened(0.15))
	# Мешки муки у двери.
	g.tag = "yard"
	for k in 2:
		g.blob("cloth", Vector3(w * 0.5 + 0.45, 0.3, -0.6 - k * 0.55), Vector3(0.26, 0.32, 0.22), col("cloth", rng, 0.05), rng, 1, 0.1, 0.15)
	g.tag = ""


## Колесо в плоскости XY вокруг оси Z (в осях узла Rotor).
static func _waterwheel(g: Geo, rng: RandomNumberGenerator) -> void:
	var r := 1.9
	var half := 0.42
	g.cylinder("log", Vector3(0, 0, -half - 0.12), 0.28, 0.28, half * 2.0 + 0.24, 10, col("log", rng), true, true, 0.0, Basis(Vector3.RIGHT, PI * 0.5))
	var n := 16
	for s: float in [-1.0, 1.0]:
		var z := s * half
		for k in n:
			var a := TAU * (k + 0.5) / n
			var chord := 2.0 * (r - 0.05) * sin(PI / n) + 0.04
			g.box("log_dark", Vector3(cos(a), sin(a), 0) * (r - 0.05) + Vector3(0, 0, z), Vector3(chord, 0.16, 0.1),
				col("log_dark", rng, 0.04), 0.02, Basis(Vector3.BACK, a + PI * 0.5))
		for k in 8:
			var a := TAU * k / 8.0
			g.box("log_dark", Vector3(cos(a), sin(a), 0) * r * 0.5 + Vector3(0, 0, z), Vector3(0.1, r, 0.08),
				col("log_dark", rng, 0.04), 0.0, Basis(Vector3.BACK, a - PI * 0.5))
	for k in n:
		var a := TAU * k / n
		g.box("plank", Vector3(cos(a), sin(a), 0) * (r + 0.02), Vector3(0.06, 0.5, half * 2.0 + 0.12),
			col("plank", rng, 0.08), 0.01, Basis(Vector3.BACK, a - PI * 0.5))


static func _lighthouse(g: Geo, rng: RandomNumberGenerator) -> void:
	var h := 8.5
	g.cylinder("stone_block", Vector3(0, UNDER, 0), 2.35, 2.35, BASE - UNDER, 16, col("stone_block", rng).darkened(0.3), true)
	round_wall(g, rng, Vector3(0, BASE, 0), 2.0, 1.45, h, "stone_block", [
		{"angle": PI * 0.5, "v": 0.0, "w": 1.0, "h": 2.0, "type": "door"},
		{"angle": PI * 0.5, "v": 3.6, "w": 0.5, "h": 0.8},
		{"angle": -PI * 0.35, "v": 5.8, "w": 0.5, "h": 0.8},
	], {"frame": "plank", "door": "plank_dark", "glass": true})
	# Красные пояса.
	for band: Vector2 in [Vector2(2.4, 3.1), Vector2(6.0, 6.7)]:
		var ra := lerpf(2.0, 1.45, band.x / h) + 0.13
		var rb := lerpf(2.0, 1.45, band.y / h) + 0.13
		lathe(g, "brick", Vector3(0, BASE, 0), [Vector2(ra - 0.1, band.x), Vector2(ra, band.x + 0.04), Vector2(rb, band.y - 0.04),
			Vector2(rb - 0.1, band.y)], 18, rng, 0.02)
	var top := Vector3(0, BASE + h, 0)
	# Галерея с перилами.
	g.cylinder("stone_block", top, 2.0, 2.05, 0.25, 16, col("stone_block", rng).lightened(0.05), true, true)
	var posts := 16
	for k in posts:
		var a := TAU * k / posts
		g.rod("iron", top + Vector3(cos(a) * 1.9, 0.25, sin(a) * 1.9), top + Vector3(cos(a) * 1.9, 1.0, sin(a) * 1.9), 0.035, 0.035, 4, col("iron", rng))
	for y: float in [0.62, 1.0]:
		for k in posts:
			var a0 := TAU * k / posts
			var a1 := TAU * (k + 1) / posts
			g.rod("iron", top + Vector3(cos(a0) * 1.9, y, sin(a0) * 1.9), top + Vector3(cos(a1) * 1.9, y, sin(a1) * 1.9), 0.03, 0.03, 4, col("iron", rng), false)
	# Фонарь: стеклянный барабан, ночью светится.
	g.cylinder("iron", top + Vector3(0, 0.25, 0), 1.05, 1.05, 0.3, 10, col("iron", rng), true)
	g.cylinder("glass", top + Vector3(0, 0.55, 0), 0.95, 0.95, 1.5, 10, col("glass", rng), false)
	for k in 10:
		var a := TAU * k / 10.0
		g.rod("iron", top + Vector3(cos(a) * 0.97, 0.55, sin(a) * 0.97), top + Vector3(cos(a) * 0.97, 2.05, sin(a) * 0.97), 0.04, 0.04, 4, col("iron", rng))
	g.cylinder("iron", top + Vector3(0, 2.05, 0), 1.08, 1.08, 0.14, 10, col("iron", rng), true)
	lathe(g, "copper", top + Vector3(0, 2.19, 0), [Vector2(1.25, 0.0), Vector2(1.0, 0.45), Vector2(0.55, 0.95), Vector2(0.18, 1.25), Vector2(0.0, 1.3)], 12, rng)
	g.blob("copper", top + Vector3(0, 3.55, 0), Vector3.ONE * 0.16, col("copper", rng).lightened(0.15), rng, 1, 0.05, 0.1)
	g.rod("iron", top + Vector3(0, 3.6, 0), top + Vector3(0, 4.2, 0), 0.03, 0.02, 4, col("iron", rng))


static func _library(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 6.4
	var d := 4.8
	plinth(g, rng, w + 0.3, d + 0.3, "stone_block")
	walls(g, rng, w, d, BASE, 3.8, "stone_block", [
		{"side": "front", "u": 0.0, "w": 1.2, "h": 2.3, "type": "door"},
		{"side": "front", "u": -2.1, "v": 0.9, "w": 0.9, "h": 2.2},
		{"side": "front", "u": 2.1, "v": 0.9, "w": 0.9, "h": 2.2},
		{"side": "left", "u": 0.0, "v": 0.9, "w": 0.9, "h": 2.2},
		{"side": "right", "u": 0.0, "v": 0.9, "w": 0.9, "h": 2.2},
		{"side": "back", "u": -1.4, "v": 0.9, "w": 0.9, "h": 2.2},
		{"side": "back", "u": 1.4, "v": 0.9, "w": 0.9, "h": 2.2},
	], {"frame": "stone_block", "door": "plank", "glass": true, "quoins": true})
	g.box("stone_block", Vector3(0, BASE + 3.88, 0), Vector3(w + 0.35, 0.18, d + 0.35), col("stone_block", rng), 0.05)
	gable_roof(g, rng, Vector3(0, BASE + 3.95, 0), w, d, 2.0, "slate", "shingle", 0.45, "stone_block", "")
	# Портик у входа: ступени, две колонны и фронтон.
	for k in 2:
		g.box("stone_block", Vector3(0, 0.08 + k * 0.12 - 0.06, d * 0.5 + 0.75 - k * 0.25), Vector3(2.8 - k * 0.3, 0.16 + k * 0.12, 1.1 - k * 0.5),
			col("stone_block", rng).lightened(0.05), 0.04)
	for x: float in [-1.15, 1.15]:
		lathe(g, "stone_block", Vector3(x, BASE, d * 0.5 + 0.95), [Vector2(0.28, 0.0), Vector2(0.28, 0.18), Vector2(0.2, 0.26), Vector2(0.18, 2.5),
			Vector2(0.26, 2.62), Vector2(0.28, 2.78), Vector2(0.0, 2.78)], 10, rng, 0.02)
	var py := BASE + 2.78
	g.box("stone_block", Vector3(0, py + 0.12, d * 0.5 + 0.55), Vector3(3.0, 0.24, 1.3), col("stone_block", rng), 0.04)
	gable_roof(g, rng, Vector3(0, py + 0.24, d * 0.5 + 0.55), 1.3, 3.0, 0.75, "slate", "shingle", 0.15, "stone_block", "")
	# Башенка-читальня у заднего угла.
	var tower := Vector3(w * 0.5 - 0.3, BASE, -d * 0.5 + 0.3)
	round_wall(g, rng, tower, 1.25, 1.2, 5.6, "stone_block", [
		{"angle": 0.2, "v": 3.9, "w": 0.45, "h": 0.9},
		{"angle": -1.4, "v": 3.9, "w": 0.45, "h": 0.9},
	], {"frame": "stone_block", "glass": true})
	lathe(g, "slate", tower + Vector3(0, 5.6, 0), [Vector2(1.45, 0.0), Vector2(1.0, 0.8), Vector2(0.45, 1.8), Vector2(0.0, 2.4)], 12, rng, 0.04)
	g.rod("iron", tower + Vector3(0, 7.95, 0), tower + Vector3(0, 8.5, 0), 0.03, 0.02, 4, col("iron", rng))
	# Вывеска с раскрытой книгой.
	var sign_at := Vector3(-1.0, BASE + 3.1, d * 0.5 + 0.05)
	g.rod("iron", sign_at, sign_at + Vector3(0, 0, 0.7), 0.035, 0.035, 4, col("iron", rng), false)
	g.box("plank", sign_at + Vector3(0, -0.42, 0.42), Vector3(0.06, 0.55, 0.62), col("plank", rng), 0.02)
	for s: float in [-1.0, 1.0]:
		g.box("cloth", sign_at + Vector3(s * 0.05, -0.42, 0.42), Vector3(0.02, 0.36, 0.48), Color(0.94, 0.9, 0.8), 0.0)


static func _bell_tower(g: Geo, rng: RandomNumberGenerator) -> void:
	var s := 3.0
	var h := 6.0
	plinth(g, rng, s + 0.35, s + 0.35, "stone_block")
	walls(g, rng, s, s, BASE, h, "stone_block", [
		{"side": "front", "u": 0.0, "w": 1.1, "h": 2.1, "type": "door"},
		{"side": "front", "u": 0.0, "v": 3.6, "w": 0.5, "h": 0.9},
		{"side": "left", "u": 0.0, "v": 2.8, "w": 0.45, "h": 0.8},
		{"side": "right", "u": 0.0, "v": 4.2, "w": 0.45, "h": 0.8},
	], {"frame": "stone_block", "door": "plank_dark", "glass": true, "quoins": true})
	var top := BASE + h
	g.box("stone_block", Vector3(0, top + 0.1, 0), Vector3(s + 0.4, 0.2, s + 0.4), col("stone_block", rng), 0.05)
	# Звонница: столбы по углам, балка и колокол.
	var bh := 2.3
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.box("stone_block", Vector3(sx * (s * 0.5 - 0.25), top + 0.2 + bh * 0.5, sz * (s * 0.5 - 0.25)), Vector3(0.5, bh, 0.5),
				col("stone_block", rng), 0.05)
	for k in 4:
		var b := Basis(Vector3.UP, k * PI * 0.5)
		g.box("stone_block", b * Vector3(0, top + 0.35, s * 0.5 - 0.25), Vector3(s - 1.0, 0.3, 0.3), col("stone_block", rng), 0.04, b)
	g.box("plank_dark", Vector3(0, top + bh - 0.05, 0), Vector3(s - 0.4, 0.22, 0.22), col("plank_dark", rng), 0.03)
	var bell := Vector3(0, top + 0.95, 0)
	lathe(g, "copper", bell, [Vector2(0.62, 0.0), Vector2(0.58, 0.12), Vector2(0.46, 0.35), Vector2(0.4, 0.75), Vector2(0.3, 1.0),
		Vector2(0.12, 1.08), Vector2(0.0, 1.1)], 14, rng)
	g.rod("iron", bell + Vector3(0, 1.1, 0), Vector3(0, top + bh - 0.15, 0), 0.05, 0.05, 4, col("iron", rng))
	g.blob("iron", bell + Vector3(0, 0.05, 0), Vector3.ONE * 0.1, col("iron", rng), rng, 0, 0.05, 0.1)
	g.box("stone_block", Vector3(0, top + bh + 0.3, 0), Vector3(s + 0.3, 0.2, s + 0.3), col("stone_block", rng), 0.05)
	pyramid_roof(g, rng, Vector3(0, top + bh + 0.4, 0), s * 0.5 + 0.1, 2.6, "slate", 0.25)
	# Флюгер-петушок.
	var spire := Vector3(0, top + bh + 3.0, 0)
	g.rod("iron", spire, spire + Vector3(0, 0.9, 0), 0.04, 0.03, 4, col("iron", rng))
	g.box("iron", spire + Vector3(0, 0.7, 0), Vector3(0.5, 0.05, 0.05), col("iron", rng))
	g.blob("copper", spire + Vector3(0.05, 0.95, 0), Vector3(0.18, 0.14, 0.04), col("copper", rng).lightened(0.2), rng, 0, 0.1, 0.1)


static func _chicken_coop(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 2.4
	var d := 1.8
	var floor_y := 0.7
	var cz := -0.9
	g.push(Transform3D(Basis.IDENTITY, Vector3(0, 0, cz)))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			g.rod("log", Vector3(sx * (w * 0.5 - 0.15), -0.4, sz * (d * 0.5 - 0.15)), Vector3(sx * (w * 0.5 - 0.15), floor_y, sz * (d * 0.5 - 0.15)),
				0.08, 0.07, 6, col("log", rng))
	g.box("plank_dark", Vector3(0, floor_y - 0.05, 0), Vector3(w + 0.1, 0.12, d + 0.1), col("plank_dark", rng), 0.02)
	walls(g, rng, w, d, floor_y, 1.4, "plank_v", [
		{"side": "front", "u": 0.6, "w": 0.45, "h": 0.6, "type": "door"},
		{"side": "front", "u": -0.6, "v": 0.6, "w": 0.45, "h": 0.4},
		{"side": "left", "u": 0.0, "v": 0.6, "w": 0.4, "h": 0.35},
	], {"frame": "plank_dark", "door": "plank_dark", "thickness": 0.2})
	gable_roof(g, rng, Vector3(0, floor_y + 1.4, 0), w, d, 0.85, "plank_dark", "boards", 0.3, "plank_v", "")
	g.pop()
	# Лесенка с перекладинами к дверце.
	var r0 := Vector3(0.6, floor_y, cz + d * 0.5)
	var r1 := Vector3(0.6, 0.0, cz + d * 0.5 + 1.0)
	var rb := Basis(Vector3.RIGHT, atan2(floor_y, 1.0))
	g.box("plank", (r0 + r1) * 0.5 + Vector3(0, 0.02, 0), Vector3(0.45, 0.04, r0.distance_to(r1)), col("plank", rng), 0.01, rb)
	for k in 4:
		g.box("plank_dark", r0.lerp(r1, (k + 0.5) / 4.0) + Vector3(0, 0.05, 0), Vector3(0.42, 0.03, 0.04), col("plank_dark", rng), 0.0, rb)
	# Загончик из штакетника перед курятником (с сеном, кормушкой и курами — по земле).
	g.tag = "yard"
	var x0 := -1.6
	var x1 := 1.6
	var z0 := cz + d * 0.5 - 0.1
	var z1 := 1.9
	var edges := [[Vector3(x0, 0, z0), Vector3(x0, 0, z1)], [Vector3(x0, 0, z1), Vector3(x1, 0, z1)], [Vector3(x1, 0, z1), Vector3(x1, 0, z0)]]
	for e: Array in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var span := a.distance_to(b)
		var dir := (b - a) / span
		var yaw := atan2(-dir.z, dir.x)
		for y: float in [0.25, 0.6]:
			g.box("plank_dark", (a + b) * 0.5 + Vector3(0, y, 0), Vector3(span, 0.06, 0.04), col("plank_dark", rng), 0.0, Basis(Vector3.UP, yaw))
		var count := roundi(span / 0.24)
		for k in count + 1:
			var at := a.lerp(b, float(k) / count)
			g.box("plank", at + Vector3(0, 0.33, 0), Vector3(0.07, 0.86, 0.035), col("plank", rng, 0.1), 0.01, Basis(Vector3.UP, yaw))
			g.tri("plank", at + Vector3(0, 0.76, 0) + Basis(Vector3.UP, yaw) * Vector3(-0.035, 0, 0.02),
				at + Vector3(0, 0.76, 0) + Basis(Vector3.UP, yaw) * Vector3(0.035, 0, 0.02), at + Vector3(0, 0.84, 0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.02),
				col("plank", rng), Basis(Vector3.UP, yaw) * Vector3.BACK)
	# Сено, кормушка и куры.
	g.blob("hay", Vector3(-1.05, 0.12, 0.6), Vector3(0.38, 0.2, 0.3), col("hay", rng), rng, 1, 0.25, 0.2)
	_trough(g, rng, Vector3(0.6, -0.25, 1.35), 0.9)
	var hens := [[Vector3(-0.5, 0, 1.1), 0.4], [Vector3(0.2, 0, 0.7), 2.2], [Vector3(-0.1, 0, 1.55), -1.2], [Vector3(1.05, 0, 0.55), 3.4]]
	for i in hens.size():
		var at: Vector3 = hens[i][0]
		var b := Basis(Vector3.UP, hens[i][1])
		var body := Color(0.95, 0.93, 0.88) if i % 2 == 0 else Color(0.66, 0.4, 0.22)
		g.blob("crop", at + Vector3(0, 0.2, 0), Vector3(0.15, 0.13, 0.19), body, rng, 1, 0.05, 0.15)
		g.blob("crop", at + Vector3(0, 0.27, 0) + b * Vector3(0, 0.0, -0.17), Vector3(0.08, 0.05, 0.1), body.darkened(0.05), rng, 0, 0.05, 0.1)
		var head := at + Vector3(0, 0.36, 0) + b * Vector3(0, 0, 0.16)
		g.blob("crop", head, Vector3.ONE * 0.075, body, rng, 0, 0.05, 0.1)
		g.box("crop", head + Vector3(0, 0.08, 0), Vector3(0.03, 0.06, 0.08), Color(0.85, 0.15, 0.12), 0.0, b)
		g.box("crop", head + b * Vector3(0, -0.01, 0.08), Vector3(0.04, 0.03, 0.06), Color(0.95, 0.7, 0.2), 0.0, b)
		for s: float in [-1.0, 1.0]:
			g.rod("crop", at + b * Vector3(s * 0.05, 0.1, 0), at + b * Vector3(s * 0.05, 0.0, 0.02), 0.012, 0.012, 3, Color(0.95, 0.7, 0.2), false)
	g.tag = ""


## Настил постройки на воде из обычных блоков настила 4×4 м (такие же доски, сваи и высота):
## к нему пристраиваются другие настилы. cells — середины блоков в метрах.
static func _deck_blocks(g: Geo, rng: RandomNumberGenerator, cells: Array) -> void:
	var k := 1.0 / MODEL_SCALE
	for c: Vector3 in cells:
		g.push(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * k), c * k))
		_platform(g, rng)
		g.pop()


## Лесенка с края настила в воду (к лодке).
static func _water_ladder(g: Geo, rng: RandomNumberGenerator, top: Vector3, bottom_y: float, width := 0.55) -> void:
	for s: float in [-1.0, 1.0]:
		var x := top + Vector3(s * width * 0.5, 0, 0)
		g.rod("log", Vector3(x.x, bottom_y, x.z), x + Vector3(0, 0.6, 0), 0.045, 0.045, 5, col("log", rng))
	var y := top.y - 0.3
	while y > bottom_y + 0.1:
		g.rod("log", Vector3(top.x - width * 0.5, y, top.z), Vector3(top.x + width * 0.5, y, top.z), 0.035, 0.035, 5, col("log", rng))
		y -= 0.32


## Вёсельная лодка (нос — к +X): обшивка из досок по шпангоутам, настил на дне, скамья и весло.
static func _rowboat(g: Geo, rng: RandomNumberGenerator, xf: Transform3D) -> void:
	g.push(xf)
	var hull := col("plank_dark", rng)
	var stations := 9
	var prev: Array[Vector3] = []
	for i in stations:
		var t := float(i) / (stations - 1) * 2.0 - 1.0
		var x := t * 1.3
		var half := 0.55 * sqrt(maxf(1.0 - t * t, 0.0))
		var keel := 0.05 + 0.14 * t * t
		var top := 0.42 + 0.1 * t * t
		var bilge := 0.14 + 0.12 * t * t
		var ring: Array[Vector3] = [Vector3(x, top, -half), Vector3(x, bilge, -half * 0.78), Vector3(x, keel, 0.0),
			Vector3(x, bilge, half * 0.78), Vector3(x, top, half)]
		if i > 0:
			for k in 4:
				var mid := (prev[k] + ring[k + 1]) * 0.5
				var out := mid - Vector3(mid.x, 0.35, 0.0)
				g.quad("plank_dark", prev[k], ring[k], ring[k + 1], prev[k + 1], hull.lightened(0.04 * (k % 2)), out)
				g.quad("plank_dark", prev[k], ring[k], ring[k + 1], prev[k + 1], hull.darkened(0.25), -out)
			for k: int in [0, 4]:
				g.rod("plank", prev[k], ring[k], 0.03, 0.03, 4, col("plank", rng), false)
		prev = ring
	# Настил на дне: доски вдоль лодки.
	for z: float in [-0.18, -0.06, 0.06, 0.18]:
		g.box("plank", Vector3(0, 0.2, z), Vector3(1.4, 0.03, 0.11), col("plank", rng, 0.1), 0.0)
	g.box("plank", Vector3(0.1, 0.32, 0), Vector3(0.28, 0.05, 1.0), col("plank", rng), 0.01)
	g.rod("plank", Vector3(-0.7, 0.36, 0.25), Vector3(0.9, 0.3, 0.42), 0.03, 0.03, 4, col("plank", rng))
	g.box("plank", Vector3(0.95, 0.3, 0.43), Vector3(0.4, 0.03, 0.13), col("plank", rng), 0.0, Basis(Vector3.UP, -0.1))
	g.pop()


## Причальная тумба на настиле и верёвка к носу лодки (провисает).
static func _mooring(g: Geo, rng: RandomNumberGenerator, post: Vector3, bow: Vector3) -> void:
	g.rod("log", post, post + Vector3(0, 0.5, 0), 0.11, 0.1, 7, col("log", rng))
	g.cylinder("log", post + Vector3(0, 0.5, 0), 0.13, 0.13, 0.05, 7, col("log", rng).darkened(0.1))
	var a := post + Vector3(0, 0.38, 0)
	var mid := (a + bow) * 0.5 + Vector3(0, -0.2, 0)
	var rope := Color(0.55, 0.46, 0.32)
	g.rod("cloth", a, mid, 0.022, 0.022, 4, rope, false)
	g.rod("cloth", mid, bow, 0.022, 0.022, 4, rope, false)


## Связка рыбы на нитке: рыбины одна под другой (dried — вяленая, золотистая).
static func _fish_string(g: Geo, rng: RandomNumberGenerator, at: Vector3, count := 3, dried := false) -> void:
	g.rod("cloth", at, at + Vector3(0, -0.12 - count * 0.24, 0), 0.008, 0.008, 3, Color(0.5, 0.44, 0.34), false)
	for k in count:
		var c := Color(0.78, 0.58, 0.32) if dried else Color(0.68, 0.72, 0.76)
		g.blob("crop", at + Vector3(0, -0.24 - k * 0.24, 0), Vector3(0.05, 0.13, 0.025), c.darkened(rng.randf() * 0.12),
			rng, 0, 0.1, 0.25)


## Ящик с уловом: рыба горкой сверху.
static func _fish_crate(g: Geo, rng: RandomNumberGenerator, base: Vector3, yaw := 0.0) -> void:
	_crate(g, rng, base + Vector3(0, 0.25, 0), 0.5, yaw)
	for k in 5:
		var off := Basis(Vector3.UP, yaw) * Vector3(rng.randf_range(-0.14, 0.14), 0, rng.randf_range(-0.14, 0.14))
		g.blob("crop", base + Vector3(0, 0.53 + k * 0.02, 0) + off, Vector3(0.15, 0.04, 0.055),
			Color(0.66, 0.7, 0.74).darkened(rng.randf() * 0.15), rng, 0, 0.1, 0.25, 0.0)


## Рыбацкая хижина на блоке настила 4×4 м (край настила — ±2 м, в модели ±2/MODEL_SCALE).
static func _fishing_hut(g: Geo, rng: RandomNumberGenerator) -> void:
	var deck := PIER_DECK
	var edge := 2.0 / MODEL_SCALE
	_deck_blocks(g, rng, [Vector3.ZERO])
	# Домик на задней половине настила, дверь — к воде.
	var w := 3.0
	var d := 2.2
	g.push(Transform3D(Basis.IDENTITY, Vector3(-0.75, 0, -1.0)))
	walls(g, rng, w, d, deck, 2.1, "plank", [
		{"side": "front", "u": 0.75, "w": 0.85, "h": 1.75, "type": "door"},
		{"side": "front", "u": -0.7, "v": 0.85, "w": 0.6, "h": 0.6},
		{"side": "left", "u": 0.0, "v": 0.85, "w": 0.5, "h": 0.5},
		{"side": "back", "u": 0.5, "v": 0.85, "w": 0.5, "h": 0.5},
	], {"frame": "plank_dark", "door": "plank_dark", "thickness": 0.25, "corner_trim": "log"})
	gable_roof(g, rng, Vector3(0, deck + 2.1, 0), w, d, 1.1, "plank_dark", "boards", 0.4, "plank", "")
	# Железная труба печки.
	g.rod("iron", Vector3(0.8, deck + 2.5, -0.45), Vector3(0.8, deck + 3.55, -0.45), 0.09, 0.09, 8, col("iron", rng))
	g.cylinder("iron", Vector3(0.8, deck + 3.55, -0.45), 0.15, 0.04, 0.12, 8, col("iron", rng).darkened(0.1))
	g.pop()
	# Сушилка для сетей у правого края: два столба, жердь и сеть ячейками.
	var nx := 2.3
	for z: float in [-1.7, 0.3]:
		g.rod("log", Vector3(nx, deck, z), Vector3(nx, deck + 1.7, z), 0.06, 0.05, 5, col("log", rng))
	g.rod("log", Vector3(nx, deck + 1.65, -1.85), Vector3(nx, deck + 1.65, 0.45), 0.045, 0.045, 5, col("log", rng))
	var net := Color(0.3, 0.33, 0.26)
	for k in 9:
		var z := -1.62 + k * 0.22
		var sag := 0.06 * sin(k * 1.1)
		g.rod("cloth", Vector3(nx, deck + 1.6, z), Vector3(nx, deck + 0.45 + sag, z + 0.03), 0.012, 0.012, 3, net, false)
	for j in 7:
		var y := deck + 1.55 - j * 0.17
		g.rod("cloth", Vector3(nx, y, -1.64), Vector3(nx, y + 0.03 * sin(j * 1.7), 0.24), 0.012, 0.012, 3, net, false)
	g.box("plank_dark", Vector3(nx, deck + 0.44, -0.7), Vector3(0.05, 0.05, 1.9), col("plank_dark", rng), 0.0)
	# Вяленая рыба под свесом крыши, у двери — бочка, ящик с уловом и удочки.
	for k in 4:
		_fish_string(g, rng, Vector3(-2.0 + k * 0.3, deck + 2.05, 0.3), 2, true)
	_barrel(g, rng, Vector3(-2.2, deck, 1.0), 0.6, 0.26)
	_fish_crate(g, rng, Vector3(-1.5, deck, 1.5), 0.3)
	for k in 2:
		var foot := Vector3(1.0 + k * 0.18, deck, 0.4)
		g.rod("log", foot, foot + Vector3(-0.15 + k * 0.1, 2.3, -0.2), 0.025, 0.012, 4, col("log", rng).lightened(0.1))
	# Лесенка в воду, тумба и лодка на привязи у переднего края.
	_water_ladder(g, rng, Vector3(-1.0, deck, edge + 0.06), -0.5)
	_mooring(g, rng, Vector3(1.1, deck, edge - 0.35), Vector3(1.65, BOAT_LIFT + 0.45, edge + 0.68))
	_rowboat(g, rng, Transform3D(Basis(Vector3.UP, -0.04), Vector3(0.4, BOAT_LIFT, edge + 0.68)))


## Склад рыбы на двух блоках настила (8×4 м): амбар, коптильня, вешала и журавль.
static func _fish_store(g: Geo, rng: RandomNumberGenerator) -> void:
	var deck := PIER_DECK
	var edge := 2.0 / MODEL_SCALE
	_deck_blocks(g, rng, [Vector3(-2, 0, 0), Vector3(2, 0, 0)])
	# Амбар: широкие ворота к воде — улов заносят прямо с лодок.
	var w := 5.0
	var d := 3.2
	g.push(Transform3D(Basis.IDENTITY, Vector3(-2.6, 0, -0.8)))
	walls(g, rng, w, d, deck, 2.5, "plank", [
		{"side": "front", "u": 0.3, "w": 1.6, "h": 2.0, "type": "door"},
		{"side": "front", "u": -1.6, "v": 1.1, "w": 0.6, "h": 0.6},
		{"side": "left", "u": 0.0, "v": 1.1, "w": 0.6, "h": 0.6},
		{"side": "back", "u": -0.8, "v": 1.1, "w": 0.6, "h": 0.6},
		{"side": "back", "u": 1.2, "v": 1.1, "w": 0.6, "h": 0.6},
	], {"frame": "plank_dark", "door": "plank_dark", "thickness": 0.25, "corner_trim": "log"})
	gable_roof(g, rng, Vector3(0, deck + 2.5, 0), w, d, 1.4, "plank_dark", "shingle", 0.38, "plank", "")
	# Вывеска справа от ворот (под крышей ей места нет): доска с рыбой.
	g.box("plank", Vector3(1.8, deck + 1.6, d * 0.5 + 0.15), Vector3(1.0, 0.34, 0.06), col("plank", rng).lightened(0.08), 0.02)
	g.blob("crop", Vector3(1.8, deck + 1.6, d * 0.5 + 0.19), Vector3(0.34, 0.1, 0.02), Color(0.5, 0.62, 0.72), rng, 0, 0.05, 0.2, 0.0)
	g.pop()
	# Коптильня: каменная печь с трубой (из трубы идёт дымок — см. GameData «fire»).
	var smoke := Vector3(-4.7, deck, 2.0)
	g.box("stone", smoke + Vector3(0, 0.55, 0), Vector3(1.0, 1.1, 0.9), col("stone", rng), 0.05)
	g.box("stone", smoke + Vector3(0, 1.15, 0), Vector3(1.1, 0.12, 1.0), col("stone", rng).darkened(0.1), 0.04)
	g.box("iron", smoke + Vector3(0, 0.45, 0.46), Vector3(0.5, 0.45, 0.04), col("iron", rng).darkened(0.2), 0.02)
	_chimney(g, rng, smoke + Vector3(-0.15, 1.2, -0.1), 0.42, 1.0, "stone")
	# Бочки с солёной рыбой слева от ворот, мешки соли и ящики с уловом справа.
	for p: Vector3 in [Vector3(-3.7, deck, 1.3), Vector3(-3.2, deck, 1.75), Vector3(-3.75, deck, 1.95)]:
		_barrel(g, rng, p, 0.7, 0.28)
	_barrel(g, rng, Vector3(-3.5, deck + 0.7, 1.55), 0.6, 0.25)
	for k in 2:
		g.blob("cloth", Vector3(-1.15 + k * 0.42, deck + 0.22, 1.3), Vector3(0.22, 0.24, 0.18), Color(0.86, 0.82, 0.72), rng, 1, 0.12, 0.2)
	_fish_crate(g, rng, Vector3(-0.2, deck, 1.9), 0.2)
	_fish_crate(g, rng, Vector3(0.45, deck, 1.45), -0.15)
	_crate(g, rng, Vector3(-0.15, deck + 0.25, 1.25), 0.5, 0.1)
	# Вешала: два ряда жердей вдоль склада, на них вялится рыба.
	for rz: float in [-1.9, -0.7]:
		for x: float in [0.9, 4.9]:
			g.rod("log", Vector3(x, deck, rz), Vector3(x, deck + 1.75, rz), 0.055, 0.05, 5, col("log", rng))
		for h: float in [1.7, 1.1]:
			g.rod("log", Vector3(0.8, deck + h, rz), Vector3(5.0, deck + h, rz), 0.04, 0.04, 5, col("log", rng))
			for k in 11:
				_fish_string(g, rng, Vector3(1.1 + k * 0.36, deck + h - 0.02, rz), 1, h > 1.5)
	# Журавль: столб с укосиной над водой, блок, верёвка, корзина с уловом и ворот у столба.
	var post := Vector3(1.6, deck, edge - 0.35)
	var tip := Vector3(1.6, deck + 3.0, edge + 1.4)
	g.rod("log", post, post + Vector3(0, 3.2, 0), 0.13, 0.11, 7, col("log", rng))
	g.rod("log", post + Vector3(0, 3.0, -0.15), tip, 0.08, 0.07, 6, col("log", rng))
	g.rod("log", post + Vector3(0, 2.0, 0.05), post + Vector3(0, 3.0, 1.1), 0.06, 0.06, 5, col("log", rng))
	g.cylinder("iron", tip + Vector3(-0.06, -0.12, 0), 0.12, 0.12, 0.12, 8, col("iron", rng), true, true, 0.0, Basis(Vector3.FORWARD, PI * 0.5))
	var rope := Color(0.55, 0.46, 0.32)
	var hang := Vector3(tip.x, deck + 0.75, tip.z)
	g.rod("cloth", tip + Vector3(0, -0.2, 0), hang + Vector3(0, 0.55, 0), 0.02, 0.02, 4, rope, false)
	g.rod("cloth", tip + Vector3(0, -0.05, -0.1), post + Vector3(0.12, 0.7, 0.12), 0.02, 0.02, 4, rope, false)
	g.cylinder("plank_dark", hang, 0.32, 0.38, 0.42, 9, col("plank_dark", rng), false, true)
	for k in 4:
		g.blob("crop", hang + Vector3(rng.randf_range(-0.15, 0.15), 0.42, rng.randf_range(-0.15, 0.15)), Vector3(0.14, 0.05, 0.05),
			Color(0.66, 0.7, 0.74).darkened(rng.randf() * 0.15), rng, 0, 0.1, 0.25, 0.0)
	for s: float in [-1.0, 1.0]:
		g.rod("cloth", hang + Vector3(s * 0.3, 0.4, 0), hang + Vector3(0, 0.55, 0), 0.012, 0.012, 3, rope, false)
	for s: float in [-1.0, 1.0]:
		g.box("log", post + Vector3(s * 0.35, 0.35, -0.3), Vector3(0.1, 0.7, 0.12), col("log", rng), 0.02)
	g.cylinder("log", post + Vector3(-0.32, 0.62, -0.3), 0.13, 0.13, 0.64, 8, col("log", rng).darkened(0.1), true, true, 0.0,
		Basis(Vector3.FORWARD, -PI * 0.5))
	g.rod("iron", post + Vector3(0.38, 0.62, -0.3), post + Vector3(0.38, 0.35, -0.12), 0.025, 0.025, 4, col("iron", rng))
	# Лесенка, тумба и лодка у переднего края.
	_water_ladder(g, rng, Vector3(3.0, deck, edge + 0.06), -0.5)
	_mooring(g, rng, Vector3(4.7, deck, edge - 0.35), Vector3(4.85, BOAT_LIFT + 0.45, edge + 0.72))
	_rowboat(g, rng, Transform3D(Basis(Vector3.UP, 0.04), Vector3(3.6, BOAT_LIFT, edge + 0.72)))


## Брус квадратного сечения t от точки a до точки b.
static func _beam(g: Geo, mat: String, a: Vector3, b: Vector3, t: float, color: Color) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.001:
		return
	var y := dir / length
	var x := y.cross(Vector3.UP) if absf(y.y) < 0.99 else Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y)
	g.box(mat, (a + b) * 0.5, Vector3(t, length, t), color, 0.01, Basis(x, y, z))


static func _greenhouse(g: Geo, rng: RandomNumberGenerator) -> void:
	var w := 4.4
	var d := 3.0
	var y0 := 0.35
	var y1 := y0 + 1.9
	var ridge := y1 + 1.2
	var t := 0.09
	var hx := w * 0.5
	var hz := d * 0.5
	# Цоколь: фундамент под землёй и каменный бортик по периметру (без нахлёстов).
	g.box("stone", Vector3(0, (UNDER - 0.05) * 0.5, 0), Vector3(w + 0.3, -UNDER - 0.05, d + 0.3), col("stone", rng).darkened(0.3))
	var curb := 0.26
	for s: float in [-1.0, 1.0]:
		g.box("stone", Vector3(0, y0 * 0.5 - 0.05, s * hz), Vector3(w + curb, y0 + 0.1, curb), col("stone", rng), 0.04)
		g.box("stone", Vector3(s * hx, y0 * 0.5 - 0.05, 0), Vector3(curb, y0 + 0.1, d - curb), col("stone", rng), 0.04)
	# Пол: утоптанная земля и дорожка из плит посередине.
	g.box("soil", Vector3(0, y0 - 0.06, 0), Vector3(w - curb, 0.08, d - curb), col("soil", rng).darkened(0.1))
	for k in 7:
		var x := -hx + 0.55 + k * 0.56
		g.box("stone", Vector3(x, y0 - 0.005, 0), Vector3(0.5, 0.05, 0.6), col("stone", rng, 0.1).lightened(0.1), 0.02,
			Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)))
	var frame := col("plank_dark", rng)
	var bays := 5
	# Каркас: стойки, обвязка снизу и сверху, средний ригель — все узлы сходятся в одних точках.
	for s: float in [-1.0, 1.0]:
		var z := s * hz
		for i in bays + 1:
			var x := -hx + i * w / bays
			_beam(g, "plank_dark", Vector3(x, y0, z), Vector3(x, y1, z), t, frame)
		_beam(g, "plank_dark", Vector3(-hx - t * 0.5, y0 + t * 0.5, z), Vector3(hx + t * 0.5, y0 + t * 0.5, z), t, frame)
		_beam(g, "plank_dark", Vector3(-hx - t * 0.5, y1, z), Vector3(hx + t * 0.5, y1, z), t, frame)
		_beam(g, "plank_dark", Vector3(-hx, y0 + 0.85, z), Vector3(hx, y0 + 0.85, z), t * 0.7, frame)
	for s: float in [-1.0, 1.0]:
		var x := s * hx
		_beam(g, "plank_dark", Vector3(x, y0 + t * 0.5, -hz), Vector3(x, y0 + t * 0.5, hz), t, frame)
		_beam(g, "plank_dark", Vector3(x, y1, -hz), Vector3(x, y1, hz), t, frame)
		# Стойки торца — до ската крыши.
		for z: float in [-hz * 0.5, hz * 0.5]:
			if s > 0.0:
				continue
			_beam(g, "plank_dark", Vector3(x, y0, z), Vector3(x, y1 + (ridge - y1) * (1.0 - absf(z) / hz), z), t, frame)
		_beam(g, "plank_dark", Vector3(x, y0, 0.0) if s < 0.0 else Vector3(x, y0 + 1.9, 0.0), Vector3(x, ridge, 0.0), t, frame)
	# Стропила от обвязки к коньку на каждой стойке, конёк.
	for i in bays + 1:
		var x := -hx + i * w / bays
		for s: float in [-1.0, 1.0]:
			_beam(g, "plank_dark", Vector3(x, y1, s * hz), Vector3(x, ridge, 0.0), t, frame)
	_beam(g, "plank_dark", Vector3(-hx - t, ridge, 0), Vector3(hx + t, ridge, 0), t * 1.2, frame)
	# Стёкла — прозрачные, чуть утоплены в каркас.
	var glass := col("pane", rng, 0.02)
	for s: float in [-1.0, 1.0]:
		var z := s * hz
		g.box("pane", Vector3(0, (y0 + y1) * 0.5, z), Vector3(w, y1 - y0, 0.02), glass)
		var slope_len := Vector2(hz, ridge - y1).length()
		var b := Basis(Vector3.RIGHT, s * atan2(ridge - y1, hz))
		g.box("pane", Vector3(0, (y1 + ridge) * 0.5, s * hz * 0.5), Vector3(w, 0.02, slope_len), glass, 0.0, b)
	for s: float in [-1.0, 1.0]:
		var x := s * hx
		if s < 0.0:
			g.box("pane", Vector3(x, (y0 + y1) * 0.5, 0), Vector3(0.02, y1 - y0, d), glass)
		else:
			for side: float in [-1.0, 1.0]:
				g.box("pane", Vector3(x, (y0 + y1) * 0.5, side * (hz + 0.45) * 0.5), Vector3(0.02, y1 - y0, hz - 0.45), glass)
		g.tri("pane", Vector3(x, y1, -hz), Vector3(x, y1, hz), Vector3(x, ridge, 0), glass, Vector3(s, 0, 0))
	# Дверь в правом торце: рама, стекло, ручка; над ней — перемычка.
	var door := Rect2(-0.45, y0, 0.9, 1.9)
	for z: float in [door.position.x, door.end.x]:
		_beam(g, "plank_dark", Vector3(hx, y0, z), Vector3(hx, y0 + 1.9, z), t, frame)
	_beam(g, "plank_dark", Vector3(hx + 0.02, y0 + 0.04, -0.4), Vector3(hx + 0.02, y0 + 0.04, 0.4), 0.06, frame)
	_beam(g, "plank_dark", Vector3(hx + 0.02, y0 + 1.86, -0.4), Vector3(hx + 0.02, y0 + 1.86, 0.4), 0.06, frame)
	_beam(g, "plank_dark", Vector3(hx + 0.02, y0 + 0.8, -0.4), Vector3(hx + 0.02, y0 + 0.8, 0.4), 0.05, frame)
	g.box("pane", Vector3(hx + 0.02, y0 + 0.95, 0), Vector3(0.02, 1.85, 0.8), glass)
	g.box("plank", Vector3(hx + 0.08, y0 + 0.95, 0.3), Vector3(0.05, 0.05, 0.12), col("plank", rng).darkened(0.3), 0.01)
	# Внутри: две гряды в дощатых коробах, вдоль них — помидоры на кольях, капуста и рассада.
	for s: float in [-1.0, 1.0]:
		var z := s * 0.95
		g.box("plank", Vector3(-0.15, y0 + 0.2, z), Vector3(3.7, 0.4, 0.7), col("plank", rng), 0.02)
		g.box("soil", Vector3(-0.15, y0 + 0.41, z), Vector3(3.6, 0.04, 0.62), col("soil", rng).darkened(0.05))
		for k in 6:
			var at := Vector3(-1.75 + k * 0.62, y0 + 0.43, z)
			if s < 0.0:
				# Помидоры: колышек, куст и красные плоды.
				g.rod("plank", at, at + Vector3(0, 1.1, 0), 0.02, 0.02, 4, col("plank", rng), false)
				for j in 4:
					var leaf := Color(0.3, 0.55, 0.2).lightened(rng.randf_range(-0.08, 0.12))
					g.blob("crop", at + Vector3(rng.randf_range(-0.12, 0.12), 0.25 + j * 0.22, rng.randf_range(-0.1, 0.1)),
						Vector3(0.16, 0.13, 0.16), leaf, rng, 1, 0.3, 0.2)
				for j in 3:
					g.blob("crop", at + Vector3(rng.randf_range(-0.14, 0.14), 0.3 + rng.randf_range(0.0, 0.6), rng.randf_range(-0.14, 0.14)),
						Vector3.ONE * 0.06, Color(0.86, 0.18, 0.12).lightened(rng.randf_range(0.0, 0.1)), rng, 0, 0.05, 0.1)
			elif k % 2 == 0:
				# Капуста — тугие кочаны.
				g.blob("crop", at + Vector3(0, 0.13, 0), Vector3(0.2, 0.15, 0.2), Color(0.55, 0.72, 0.4), rng, 1, 0.12, 0.2)
				g.blob("crop", at + Vector3(0, 0.08, 0), Vector3(0.27, 0.07, 0.27), Color(0.38, 0.6, 0.3), rng, 1, 0.25, 0.2)
			else:
				# Рассада и цветы.
				for j in 3:
					var p := at + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
					g.rod("crop", p, p + Vector3(0, 0.2, 0), 0.012, 0.012, 3, Color(0.35, 0.6, 0.25), false)
					var petal := [Color(0.95, 0.8, 0.3), Color(0.92, 0.45, 0.6), Color(0.6, 0.45, 0.9)][j] as Color
					g.blob("crop", p + Vector3(0, 0.22, 0), Vector3(0.06, 0.04, 0.06), petal, rng, 0, 0.1, 0.1)
	# Стол с горшками у дальнего торца и подвесные кашпо под коньком.
	var tx := -hx + 0.42
	g.box("plank", Vector3(tx, y0 + 0.78, 0), Vector3(0.55, 0.06, 1.1), col("plank", rng), 0.02)
	for z: float in [-0.45, 0.45]:
		_beam(g, "plank_dark", Vector3(tx, y0, z), Vector3(tx, y0 + 0.75, z), 0.06, frame)
	for k in 4:
		var at := Vector3(tx + rng.randf_range(-0.12, 0.12), y0 + 0.81, -0.4 + k * 0.27)
		lathe(g, "soil", at, [Vector2(0.06, 0.0), Vector2(0.09, 0.16), Vector2(0.1, 0.17), Vector2(0.0, 0.17)], 8, rng, 0.05)
		g.blob("crop", at + Vector3(0, 0.23, 0), Vector3(0.1, 0.09, 0.1), Color(0.32, 0.58, 0.24).lightened(rng.randf_range(-0.1, 0.1)),
			rng, 0, 0.25, 0.2)
	for x: float in [-1.0, 0.6]:
		var at := Vector3(x, ridge - 0.65, 0)
		g.rod("plank", at + Vector3(0, 0.15, 0), Vector3(x, ridge, 0), 0.01, 0.01, 3, col("plank", rng), false)
		lathe(g, "soil", at, [Vector2(0.0, 0.0), Vector2(0.12, 0.02), Vector2(0.14, 0.15), Vector2(0.0, 0.15)], 8, rng, 0.05)
		for j in 4:
			var a := TAU * j / 4.0
			g.blob("crop", at + Vector3(cos(a) * 0.12, -0.08 - (j % 2) * 0.1, sin(a) * 0.12), Vector3(0.07, 0.14, 0.07),
				Color(0.36, 0.62, 0.26), rng, 0, 0.2, 0.2)


static func _gazebo(g: Geo, rng: RandomNumberGenerator) -> void:
	var r := 1.9
	var floor_y := 0.35
	g.cylinder("stone", Vector3(0, UNDER, 0), r + 0.1, r + 0.1, -UNDER, 6, col("stone", rng).darkened(0.3), false)
	g.cylinder("plank", Vector3(0, 0.0, 0), r + 0.05, r + 0.05, floor_y, 6, col("plank", rng), true, false)
	for k in 6:
		var a := TAU * (k + 0.5) / 6.0
		g.box("stone", Vector3(cos(a), 0, sin(a)) * (r * 0.9) + Vector3(0, 0.1, 0), Vector3(0.6, 0.3, 0.3), col("stone", rng), 0.06,
			Basis(Vector3.UP, -a + PI * 0.5))
	# Ступени ко входу (спереди, между двумя столбами).
	var front := PI * 0.5
	for k in 2:
		var dir := Vector3(cos(front), 0, sin(front))
		g.box("plank", dir * (r + 0.25 - k * 0.15) + Vector3(0, floor_y * (0.33 + k * 0.33) - 0.05, 0), Vector3(1.1, 0.12, 0.35),
			col("plank", rng), 0.02)
	var post_h := 2.3
	var corners: Array[Vector3] = []
	for k in 6:
		var a := TAU * k / 6.0 + PI / 6.0
		corners.append(Vector3(cos(a), 0, sin(a)) * (r - 0.12))
	for c in corners:
		g.rod("log", c + Vector3(0, floor_y, 0), c + Vector3(0, floor_y + post_h, 0), 0.1, 0.09, 6, col("log", rng))
	# Перила со балясинами на всех сторонах, кроме входа.
	for k in 6:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 6]
		var mid_angle := atan2(((a + b) * 0.5).z, ((a + b) * 0.5).x)
		var top := floor_y + post_h
		var dir := (b - a).normalized()
		var yaw := atan2(-dir.z, dir.x)
		g.box("plank_dark", (a + b) * 0.5 + Vector3(0, top - 0.1, 0), Vector3(a.distance_to(b), 0.18, 0.1), col("plank_dark", rng), 0.02, Basis(Vector3.UP, yaw))
		if absf(angle_difference(mid_angle, front)) < 0.3:
			continue
		g.box("plank_dark", (a + b) * 0.5 + Vector3(0, floor_y + 0.85, 0), Vector3(a.distance_to(b), 0.08, 0.12), col("plank_dark", rng), 0.02, Basis(Vector3.UP, yaw))
		for i in 5:
			var at := a.lerp(b, (i + 1) / 6.0)
			g.box("plank", at + Vector3(0, floor_y + 0.42, 0), Vector3(0.06, 0.8, 0.06), col("plank", rng), 0.01)
		# Скамья вдоль задних сторон.
		var inward := -((a + b) * 0.5).normalized()
		g.box("plank", (a + b) * 0.5 + inward * 0.28 + Vector3(0, floor_y + 0.45, 0), Vector3(a.distance_to(b) - 0.5, 0.06, 0.38),
			col("plank", rng), 0.02, Basis(Vector3.UP, yaw))
	# Шестигранная крыша и маковка.
	var roof_y := floor_y + post_h
	lathe(g, "plank_dark", Vector3(0, roof_y, 0), [Vector2(r + 0.45, -0.05), Vector2(r + 0.45, 0.06), Vector2(r * 0.5, 1.0), Vector2(0.0, 1.55)], 6, rng, 0.04)
	for k in 6:
		var a := TAU * k / 6.0
		var dir := Vector3(cos(a), 0, sin(a))
		g.rod("log", Vector3(0, roof_y + 1.55, 0), dir * (r + 0.45) + Vector3(0, roof_y + 0.06, 0), 0.05, 0.05, 4, col("log", rng).darkened(0.1))
	g.blob("plank", Vector3(0, roof_y + 1.65, 0), Vector3.ONE * 0.14, col("plank", rng), rng, 1, 0.05, 0.1)
	g.rod("plank", Vector3(0, roof_y + 1.7, 0), Vector3(0, roof_y + 2.1, 0), 0.03, 0.01, 4, col("plank", rng))


static func _fountain(g: Geo, rng: RandomNumberGenerator) -> void:
	var r := 1.9
	var rim := 0.6
	g.cylinder("stone", Vector3(0, UNDER, 0), r + 0.15, r + 0.15, -UNDER, 16, col("stone", rng).darkened(0.3), true)
	round_wall(g, rng, Vector3.ZERO, r, r, rim, "stone")
	lathe(g, "stone_block", Vector3(0, rim, 0), [Vector2(r - 0.2, -0.02), Vector2(r - 0.2, 0.1), Vector2(r + 0.16, 0.12), Vector2(r + 0.2, 0.0),
		Vector2(r + 0.12, -0.06)], 18, rng, 0.02)
	g.cylinder("water", Vector3(0, rim - 0.1, 0), r - 0.18, r - 0.18, 0.04, 18, col("water", rng, 0.02))
	# Столб с чашей.
	lathe(g, "stone_block", Vector3(0, 0, 0), [Vector2(0.55, 0.0), Vector2(0.5, rim + 0.05), Vector2(0.3, rim + 0.2), Vector2(0.22, 1.2),
		Vector2(0.3, 1.32), Vector2(0.0, 1.32)], 12, rng, 0.02)
	var bowl := Vector3(0, 1.3, 0)
	lathe(g, "stone_block", bowl, [Vector2(0.25, 0.0), Vector2(0.65, 0.12), Vector2(0.9, 0.3), Vector2(0.95, 0.38), Vector2(0.82, 0.4),
		Vector2(0.0, 0.32)], 14, rng, 0.02)
	g.cylinder("water", bowl + Vector3(0, 0.33, 0), 0.82, 0.82, 0.04, 14, col("water", rng, 0.02))
	# Вода переливается через край чаши струйками и падает в бассейн.
	var streams := 10
	for k in streams:
		var a := TAU * (k + 0.5) / streams
		var dir := Vector3(cos(a), 0, sin(a))
		var pts: Array[Vector3] = []
		var radii: Array[float] = []
		for i in 6:
			var t := i / 5.0
			pts.append(bowl + dir * (0.96 + t * 0.3) + Vector3(0, 0.38 - t * t * 1.1, 0))
			radii.append(0.035 + t * 0.02)
		g.tube("water", pts, radii, 5, col("water", rng, 0.02).lightened(0.3))
	# Наверху — маленькая чаша-шишка и струйка.
	lathe(g, "stone_block", bowl + Vector3(0, 0.3, 0), [Vector2(0.12, 0.0), Vector2(0.1, 0.35), Vector2(0.24, 0.45), Vector2(0.18, 0.6),
		Vector2(0.0, 0.66)], 10, rng, 0.02)
	g.cylinder("water", bowl + Vector3(0, 0.96, 0), 0.05, 0.02, 0.4, 6, col("water", rng, 0.02).lightened(0.2), false)
	g.blob("water", bowl + Vector3(0, 1.38, 0), Vector3(0.12, 0.08, 0.12), col("water", rng, 0.02).lightened(0.25), rng, 0, 0.1, 0.05)


static func _shrine(g: Geo, rng: RandomNumberGenerator) -> void:
	for i in 5:
		var a := TAU * i / 5.0 + 0.2
		g.blob("stone", Vector3(cos(a) * 0.28, 0.08, sin(a) * 0.28), Vector3(0.18, 0.13, 0.15), col("stone", rng, 0.12), rng, 1, 0.2)
	g.box("stone", Vector3(0, 0.12, 0), Vector3(0.42, 0.3, 0.42), col("stone", rng), 0.05)
	g.rod("log", Vector3(0, -0.4, 0), Vector3(0, 1.35, 0), 0.07, 0.065, 6, col("log", rng))
	# Домик-киот: задняя стенка, бока, полочка и двускатная крыша.
	var y := 1.35
	g.box("plank", Vector3(0, y + 0.03, 0), Vector3(0.62, 0.06, 0.42), col("plank", rng), 0.01)
	g.box("plank", Vector3(0, y + 0.33, -0.18), Vector3(0.58, 0.6, 0.05), col("plank", rng).darkened(0.1), 0.01)
	for s: float in [-1.0, 1.0]:
		g.box("plank", Vector3(s * 0.28, y + 0.33, 0), Vector3(0.05, 0.6, 0.4), col("plank", rng), 0.01)
	# Крыша — два ската из досок и конёк.
	for side: float in [-1.0, 1.0]:
		g.box("plank_dark", Vector3(0, y + 0.74, side * 0.16), Vector3(0.8, 0.05, 0.4), col("plank_dark", rng), 0.015,
			Basis(Vector3.RIGHT, side * 0.6))
	for side: float in [-1.0, 1.0]:
		g.tri("plank", Vector3(side * 0.3, y + 0.63, -0.2), Vector3(side * 0.3, y + 0.63, 0.2), Vector3(side * 0.3, y + 0.86, 0.0),
			col("plank", rng), Vector3(side, 0, 0))
	g.box("plank_dark", Vector3(0, y + 0.87, 0), Vector3(0.86, 0.06, 0.06), col("plank_dark", rng).darkened(0.1), 0.01)
	# Образок в рамке и две свечи — ночью теплится огонёк.
	g.box("plank_dark", Vector3(0, y + 0.38, -0.15), Vector3(0.3, 0.38, 0.03), col("plank_dark", rng).darkened(0.2), 0.01)
	g.box("cloth", Vector3(0, y + 0.38, -0.13), Vector3(0.22, 0.3, 0.02), Color(0.86, 0.68, 0.32), 0.0)
	for s: float in [-1.0, 1.0]:
		g.cylinder("wax", Vector3(s * 0.15, y + 0.06, 0.06), 0.03, 0.03, 0.14, 6, col("wax", rng))
	# Цветы у подножия.
	for k in 4:
		var a := TAU * k / 4.0 + 0.6
		var at := Vector3(cos(a) * 0.42, 0.0, sin(a) * 0.42)
		g.rod("crop", at, at + Vector3(0, 0.22, 0), 0.012, 0.012, 3, Color(0.3, 0.55, 0.2), false)
		var petal := [Color(0.95, 0.85, 0.3), Color(0.9, 0.4, 0.5), Color(0.95, 0.95, 0.9), Color(0.6, 0.45, 0.85)][k] as Color
		g.blob("crop", at + Vector3(0, 0.25, 0), Vector3(0.06, 0.04, 0.06), petal, rng, 0, 0.1, 0.1)
