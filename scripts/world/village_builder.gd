class_name VillageBuilder
extends RefCounted
## Готовые деревни (Настройки → «Деревни»). Каждая — новый мир, а в нём на красивом месте
## (у озера, у реки, в лесу, у гор…) стоит большая продуманная деревня: площадь с фонтаном
## или колодцем, улицы-дорожки, дома лицом к улице, мастерские и хозяйство на окраинах,
## огороды, сады, ограды, факелы вдоль улиц. Всё раскладывается в WorldState ещё до того,
## как мир начнёт строиться: земля под домами выровнена, деревья на их месте убраны.

const PRESETS: Array[Dictionary] = [
	{"id": "harbor", "name": "Озёрная гавань", "seed": 41017, "site": "lake", "path": "wood",
		"desc": "Рыбацкая деревня на берегу озера: причалы, маяк, таверна и рыбацкие хижины.",
		"plaza": "well", "landmarks": ["tavern", "market", "chapel"],
		"houses": {"wood_house": 8, "hut": 4, "bathhouse": 2},
		"workshops": ["sawmill", "smithy", "storehouse"],
		"shore": {"lighthouse": 1, "platform": 3, "fishing_hut": 4},
		"farm": {"vegetable_garden": 3, "chicken_coop": 1, "beehives": 1},
		"orchard": 8, "ring": "", "towers": 0},
	{"id": "mill", "name": "Мельница у реки", "seed": 52221, "site": "river", "path": "dirt",
		"desc": "Хлебное село у реки: водяная и ветряные мельницы, пекарня, поля и амбары.",
		"plaza": "fountain", "landmarks": ["bakery", "tavern", "chapel"],
		"houses": {"wood_house": 6, "stone_house": 4, "hut": 2},
		"workshops": ["storehouse", "smithy"],
		"shore": {"watermill": 1, "fishing_hut": 1},
		"farm": {"windmill": 2, "barn": 2, "stable": 1, "vegetable_garden": 5, "haystack": 4, "scarecrow": 2},
		"orchard": 6, "ring": "", "towers": 0},
	{"id": "outpost", "name": "Лесная застава", "seed": 63311, "site": "pine", "path": "dirt",
		"desc": "Острог в хвойном лесу: частокол, сторожевые башни, бани и лесопилка.",
		"plaza": "campfire", "landmarks": ["guardhouse", "tavern", "chapel"],
		"houses": {"hut": 7, "wood_house": 3, "bathhouse": 2},
		"workshops": ["sawmill", "smithy", "tannery", "storehouse"],
		"shore": {},
		"farm": {"woodpile": 4, "chicken_coop": 1, "vegetable_garden": 2},
		"orchard": 0, "ring": "palisade", "towers": 4},
	{"id": "highland", "name": "Горное подворье", "seed": 74401, "site": "mountain", "path": "stone",
		"desc": "Каменное село у подножия гор: крепость, каменотёсня, кузница и часовня.",
		"plaza": "well", "landmarks": ["keep", "church", "tavern"],
		"houses": {"stone_house": 8, "brick_house": 2},
		"workshops": ["stonemason", "smithy", "kiln", "storehouse"],
		"shore": {},
		"farm": {"stable": 1, "vegetable_garden": 2, "haystack": 2},
		"orchard": 4, "ring": "fence_stone", "towers": 2},
	{"id": "birches", "name": "Берёзовая слобода", "seed": 85513, "site": "birch", "path": "dirt",
		"desc": "Уютная слобода в берёзовой роще: беседки, ульи, огороды и теплицы.",
		"plaza": "gazebo", "landmarks": ["chapel", "bathhouse", "market"],
		"houses": {"wood_house": 8, "hut": 4},
		"workshops": ["weaver", "sawmill"],
		"shore": {},
		"farm": {"greenhouse": 2, "vegetable_garden": 4, "beehives": 3, "chicken_coop": 2},
		"orchard": 10, "ring": "", "towers": 0},
	{"id": "merchants", "name": "Купеческий город", "seed": 96611, "site": "plains", "path": "brick",
		"desc": "Торговый городок: ратуша, рынок, усадьбы купцов, библиотека и фонтан.",
		"plaza": "fountain", "landmarks": ["town_hall", "market", "library", "tavern"],
		"houses": {"brick_house": 7, "manor": 2, "stone_house": 3},
		"workshops": ["bakery", "glassworks", "smithy", "storehouse"],
		"shore": {},
		"farm": {"stable": 1, "dovecote": 1, "vegetable_garden": 2},
		"orchard": 4, "ring": "", "towers": 0},
	{"id": "farms", "name": "Хутора в полях", "seed": 17713, "site": "plains", "path": "dirt",
		"desc": "Хутора среди полей: амбары, конюшни, курятники, мельницы и стога.",
		"plaza": "well", "landmarks": ["barn", "stable", "chapel"],
		"houses": {"wood_house": 6, "hut": 3},
		"workshops": ["storehouse", "sawmill"],
		"shore": {},
		"farm": {"windmill": 2, "barn": 2, "chicken_coop": 3, "vegetable_garden": 7, "haystack": 6, "scarecrow": 3, "beehives": 2},
		"orchard": 8, "ring": "", "towers": 0},
	{"id": "fortress", "name": "Крепость на холме", "seed": 28811, "site": "hill", "path": "stone",
		"desc": "Замок на холме: стены, надвратная башня, караульни и пушки.",
		"plaza": "castle", "landmarks": ["church", "guardhouse", "tavern"],
		"houses": {"stone_house": 7, "brick_house": 2},
		"workshops": ["smithy", "stonemason", "storehouse"],
		"shore": {},
		"farm": {"stable": 1, "cannon": 3, "vegetable_garden": 2},
		"orchard": 0, "ring": "fence_stone", "towers": 4, "gate": "gatehouse"},
	{"id": "abbey", "name": "Монастырская обитель", "seed": 39917, "site": "maple", "path": "stone",
		"desc": "Тихая обитель в кленовом лесу: храм, колокольня, библиотека и сады.",
		"plaza": "fountain", "landmarks": ["church", "bell_tower", "library"],
		"houses": {"stone_house": 5, "wood_house": 3},
		"workshops": ["bakery", "weaver"],
		"shore": {},
		"farm": {"greenhouse": 2, "vegetable_garden": 4, "beehives": 3, "gazebo": 1},
		"orchard": 12, "ring": "fence_stone", "towers": 0},
	{"id": "north", "name": "Северная заимка", "seed": 40123, "site": "tundra", "path": "dirt",
		"desc": "Заимка в заснеженной тайге: срубы, бани, костры и частокол.",
		"plaza": "campfire", "landmarks": ["tavern", "chapel", "storehouse"],
		"houses": {"hut": 9, "bathhouse": 3},
		"workshops": ["sawmill", "tannery", "smithy"],
		"shore": {},
		"farm": {"woodpile": 5, "watchtower": 1},
		"orchard": 0, "ring": "palisade", "towers": 2},
]

## Ширина дорожки и запас до домов.
const STREET_HALF := 0.8
const SETBACK := 1.6
const PLAZA_R := 7.5
const PAD_FALLOFF := 4.5
const TORCH_STEP := 13.0

var gen: WorldGen
var preset: Dictionary
var rng := RandomNumberGenerator.new()

var center := Vector2.ZERO
var axis := Vector2.RIGHT
var water_dir := Vector2.ZERO
## Радиус площади: у замка посередине — шире (улицы начинаются за его стенами).
var plaza_r := PLAZA_R

var edits := {}
var buildings: Array = []
var paths: Array = []
var fences: Array = []
var planted := {}
## Занятые места (многоугольники пятен с запасом) и улицы (ломаные).
var _polys: Array[PackedVector2Array] = []
var _poly_ids: Array[String] = []
var _streets: Array[PackedVector2Array] = []
## Где убрать деревья и камни: [точка, радиус].
var _clear: Array[Array] = []


static func preset_by_id(id: String) -> Dictionary:
	for p in PRESETS:
		if p["id"] == id:
			return p
	return {}


## Новый мир с деревней по пресету: WorldState заполнен и сохранён, мир готов к запуску.
static func create(id: String) -> bool:
	var p := preset_by_id(id)
	if p.is_empty():
		return false
	WorldState.create_world(p["name"], p["seed"])
	var vb := VillageBuilder.new()
	vb.plan(WorldGen.new(WorldState.world_seed, WorldState.terrain_version), p)
	vb.apply()
	WorldState.save_game()
	return true


## Раскладка деревни (без WorldState: её можно проверить отдельно).
func plan(world_gen: WorldGen, p: Dictionary) -> void:
	gen = world_gen
	preset = p
	rng.seed = hash([p["id"], p["seed"]])
	var middle: String = p["plaza"]
	if middle != "":
		plaza_r = maxf(PLAZA_R, (Footprints.BASE.get(middle, Rect2()) as Rect2).size.length() * 0.5 + 2.0)
	_find_site()
	_lay_streets()
	_place_plaza()
	# Факелы — сразу за улицами: дома потом встают за ними, и улицы освещены целиком.
	_place_torches()
	_place_shore()
	_place_houses()
	_place_farm()
	_place_defense()
	_place_decor()
	_place_orchard()
	_lay_paths()


func apply() -> void:
	WorldState.terrain_edits = edits
	WorldState.buildings = buildings
	WorldState.paths = paths
	WorldState.fences = fences
	WorldState.planted = planted
	WorldState.removed_props = _removed_props()
	var h := height(center)
	var look := atan2(-axis.x, -axis.y) + PI * 0.2
	WorldState.camera_state = {"pos": Vector3(center.x, h, center.y), "yaw": look, "dist": 58.0}


# --- Место -------------------------------------------------------------------------------

func height(p: Vector2) -> float:
	var key := Vector2i(roundi(p.x / WorldGen.CELL), roundi(p.y / WorldGen.CELL))
	if edits.has(key):
		return edits[key]
	return gen.height_at(p.x, p.y)


func _dry(p: Vector2, margin := 0.5) -> bool:
	return height(p) > WorldGen.WATER_LEVEL + margin


## Место по виду пресета: ровная суша нужного края; у озера и реки — вода рядом,
## у гор — горы на горизонте, на холме — земля вокруг ниже.
func _find_site() -> void:
	var want: String = preset["site"]
	var best_score := -INF
	var best := Vector2.ZERO
	var best_axis := Vector2.RIGHT
	var best_water := Vector2.ZERO
	var found := 0
	for ring in range(0, 40):
		var r := 140.0 + ring * 70.0
		var n := maxi(8, roundi(TAU * r / 90.0))
		for k in n:
			var a := TAU * (k + 0.37 * ring) / n
			var c := Vector2(cos(a), sin(a)) * r
			var h0 := gen.height_at(c.x, c.y)
			if h0 < WorldGen.WATER_LEVEL + 1.2 or h0 > 19.0:
				continue
			if gen.mountain_amount(c.x, c.y) > 0.05 or gen.ruin_near(c.x, c.y, 75.0):
				continue
			var climate := gen.climate_biome(c.x, c.y, h0)
			if not _climate_ok(want, climate):
				continue
			# Ровность и суша вокруг середины.
			var lo := INF
			var hi := -INF
			var dry := true
			for i in 12:
				var d := Vector2(cos(TAU * i / 12.0), sin(TAU * i / 12.0))
				for rr: float in [12.0, 26.0]:
					var hh := gen.height_at(c.x + d.x * rr, c.y + d.y * rr)
					lo = minf(lo, hh)
					hi = maxf(hi, hh)
					if hh < WorldGen.WATER_LEVEL + 0.8:
						dry = false
			if not dry or hi - lo > 6.0:
				continue
			var score := -(hi - lo)
			# Вода: где она ближе всего за пределами середины.
			var water := Vector2.ZERO
			var water_count := 0
			for i in 24:
				var d := Vector2(cos(TAU * i / 24.0), sin(TAU * i / 24.0))
				for rr: float in [40.0, 55.0, 70.0]:
					if gen.height_at(c.x + d.x * rr, c.y + d.y * rr) < WorldGen.WATER_LEVEL - 0.3:
						water += d
						water_count += 1
						break
			match want:
				"lake", "river":
					if water_count < 2 or water_count > 14:
						continue
					var mask := gen.water_mask(c.x + water.normalized().x * 60.0, c.y + water.normalized().y * 60.0)
					var is_lake := mask.x >= mask.y
					if (want == "lake") != is_lake:
						score -= 3.0
					score += 6.0
				"mountain":
					var m := 0.0
					for i in 16:
						var d := Vector2(cos(TAU * i / 16.0), sin(TAU * i / 16.0))
						m = maxf(m, gen.mountain_amount(c.x + d.x * 170.0, c.y + d.y * 170.0))
					if m < 0.45:
						continue
					score += m * 6.0
					if water_count > 0:
						score -= 2.0
				"hill":
					var around := 0.0
					for i in 12:
						var d := Vector2(cos(TAU * i / 12.0), sin(TAU * i / 12.0))
						around += gen.height_at(c.x + d.x * 55.0, c.y + d.y * 55.0)
					var rise := h0 - around / 12.0
					if rise < 1.5:
						continue
					score += rise * 1.5
					if water_count > 0:
						score -= 3.0
				_:
					if water_count > 0:
						score -= 1.5
			if score > best_score:
				best_score = score
				best = c
				best_water = water.normalized() if water_count > 0 else Vector2.ZERO
			found += 1
		if found >= 24 and ring > 6:
			break
	center = Vector2(snappedf(best.x, 1.0), snappedf(best.y, 1.0))
	water_dir = best_water
	# Главная улица идёт к воде (у озера и реки), иначе — вдоль самой ровной стороны.
	if water_dir != Vector2.ZERO:
		best_axis = water_dir
	else:
		var flat := INF
		for i in 8:
			var d := Vector2(cos(PI * i / 8.0), sin(PI * i / 8.0))
			var dh := absf(gen.height_at(center.x + d.x * 40.0, center.y + d.y * 40.0) - gen.height_at(center.x - d.x * 40.0, center.y - d.y * 40.0))
			if dh < flat:
				flat = dh
				best_axis = d
	axis = best_axis.normalized()


static func _climate_ok(want: String, climate: int) -> bool:
	match want:
		"pine":
			return climate == WorldGen.Biome.PINE_FOREST
		"birch":
			return climate == WorldGen.Biome.BIRCH_GROVE
		"maple":
			return climate in [WorldGen.Biome.MAPLE_FOREST, WorldGen.Biome.OAK_FOREST]
		"tundra":
			return climate in [WorldGen.Biome.TUNDRA, WorldGen.Biome.PINE_FOREST]
		"plains", "hill":
			return climate in [WorldGen.Biome.PLAINS, WorldGen.Biome.OAK_FOREST, WorldGen.Biome.BIRCH_GROVE]
	return climate in [WorldGen.Biome.PLAINS, WorldGen.Biome.OAK_FOREST, WorldGen.Biome.BIRCH_GROVE, WorldGen.Biome.MAPLE_FOREST]


# --- Улицы -------------------------------------------------------------------------------

## Улица от точки from в сторону dir длиной до length: слегка извилистая, обрывается у воды.
func _street(from: Vector2, dir: Vector2, length: float, wiggle := 1.6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var side := Vector2(-dir.y, dir.x)
	var phase := rng.randf() * TAU
	var s := 0.0
	while s <= length:
		var p := from + dir * s + side * sin(s * 0.07 + phase) * wiggle * smoothstep(0.0, 12.0, s)
		if not _dry(p, 0.9):
			break
		pts.append(p)
		s += 1.5
	return pts


func _lay_streets() -> void:
	var side := Vector2(-axis.y, axis.x)
	var reach := 58.0 if preset["houses"].values().reduce(func(a: int, b: int) -> int: return a + b, 0) > 10 else 46.0
	# Главная улица — через площадь насквозь (к воде — до самого берега).
	for dir: Vector2 in [axis, -axis]:
		var st := _street(center + dir * plaza_r, dir, reach)
		if st.size() > 3:
			_streets.append(st)
	# Поперечная улица и две боковые параллельно главной.
	for dir: Vector2 in [side, -side]:
		var st := _street(center + dir * plaza_r, dir, reach * 0.8)
		if st.size() > 3:
			_streets.append(st)
	for k: float in [-1.0, 1.0]:
		var start := center + side * k * 24.0
		if not _dry(start, 0.9):
			continue
		for dir: Vector2 in [axis, -axis]:
			var st := _street(start, dir, reach * 0.65, 1.0)
			if st.size() > 3:
				_streets.append(st)


# --- Постройки ---------------------------------------------------------------------------

## Многоугольник пятна постройки с запасом grow вокруг.
static func footprint(id: String, pos: Vector2, yaw: float, grow := 0.0) -> PackedVector2Array:
	var r: Rect2 = Footprints.BASE.get(id, Rect2(-1, -1, 2, 2))
	r = r.grow(grow)
	var b := Basis(Vector3.UP, yaw)
	var out := PackedVector2Array()
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var w := b * Vector3(c.x, 0, c.y)
		out.append(pos + Vector2(w.x, w.z))
	return out


## Свободно ли место: не на другом здании, не на улице, на суше (настил — краем на воде).
func _free(id: String, pos: Vector2, yaw: float) -> bool:
	var poly := footprint(id, pos, yaw, 0.9)
	for other in _polys:
		if not Geometry2D.intersect_polygons(poly, other).is_empty():
			return false
	var reach := STREET_HALF + 0.6
	for st in _streets:
		for p in st:
			if Geometry2D.is_point_in_polygon(p, poly):
				return false
		for c in poly:
			for k in range(0, st.size() - 1):
				if Geometry2D.get_closest_point_to_segment(c, st[k], st[k + 1]).distance_to(c) < reach:
					return false
	if pos.distance_to(center) < plaza_r + 1.0:
		return false
	var mode: String = GameData.BUILDINGS[id].get("place", "land")
	var core := footprint(id, pos, yaw)
	if mode == "water":
		var wet := 0
		for c in core:
			if height(c) < WorldGen.WATER_LEVEL - 0.3:
				wet += 1
		return wet >= 1 and wet <= 3 and height(pos) > WorldGen.WATER_LEVEL - 4.0
	var lo := INF
	var hi := -INF
	for c in core:
		var h := height(c)
		if h < WorldGen.WATER_LEVEL + 0.5:
			return false
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return hi - lo < 4.0


## Ставит постройку: пятно занято, земля под ней ровная, деревья вокруг убираются.
func _put(id: String, pos: Vector2, yaw: float, extra := {}) -> void:
	_polys.append(footprint(id, pos, yaw, 0.9))
	_poly_ids.append(id)
	var core := footprint(id, pos, yaw)
	var y := WorldGen.WATER_LEVEL
	if GameData.BUILDINGS[id].get("place", "land") == "land":
		var sum := height(pos)
		for c in core:
			sum += height(c)
		var target := sum / 5.0
		_pad(core, target)
		y = target - 0.1
	var entry := {"id": id, "pos": Vector3(pos.x, y, pos.y), "yaw": yaw}
	entry.merge(extra)
	buildings.append(entry)
	var r: Rect2 = Footprints.BASE.get(id, Rect2(-1, -1, 2, 2))
	_clear.append([pos, r.size.length() * 0.5 + 1.8])


## Земля под пятном — на высоту target, вокруг плавно сходит к прежней.
func _pad(core: PackedVector2Array, target: float) -> void:
	var box := Rect2(core[0], Vector2.ZERO)
	for c in core:
		box = box.expand(c)
	box = box.grow(PAD_FALLOFF + 1.0)
	var cs := WorldGen.CELL
	for vz in range(floori(box.position.y / cs), ceili(box.end.y / cs) + 1):
		for vx in range(floori(box.position.x / cs), ceili(box.end.x / cs) + 1):
			var p := Vector2(vx * cs, vz * cs)
			var d := 0.0
			if not Geometry2D.is_point_in_polygon(p, core):
				d = INF
				for k in core.size():
					d = minf(d, Geometry2D.get_closest_point_to_segment(p, core[k], core[(k + 1) % core.size()]).distance_to(p))
			var w := 1.0 - smoothstep(0.8, PAD_FALLOFF, d)
			if w <= 0.0:
				continue
			var key := Vector2i(vx, vz)
			var cur := height(p)
			if cur < WorldGen.WATER_LEVEL and d > 0.8:
				continue
			edits[key] = lerpf(cur, target, w)


## Лицом к улице: здание на стороне side (±1) от улицы, идущей по dir.
static func _facing(dir: Vector2, side: float) -> float:
	var n := Vector2(-dir.y, dir.x) * side
	# Перед модели — её +Z; смотрим на улицу (против n).
	return atan2(-n.x, -n.y)


## Пробует поставить id у улицы st (на расстоянии s от начала), лицом к ней.
func _try_street(id: String, st: PackedVector2Array, s_index: int, side: float) -> bool:
	var a := st[s_index]
	var b := st[mini(s_index + 1, st.size() - 1)]
	if a.distance_to(b) < 0.01:
		b = st[maxi(s_index - 1, 0)]
		var t := a
		a = b
		b = t
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x) * side
	var yaw := _facing(dir, side)
	var r: Rect2 = Footprints.BASE.get(id, Rect2(-1, -1, 2, 2))
	var pos := a + n * (STREET_HALF + SETBACK + r.end.y)
	for nudge: float in [0.0, 1.5, 3.0]:
		var q := pos + n * nudge
		if _free(id, q, yaw):
			_put(id, q, yaw, _extra_for(id))
			return true
	return false


func _extra_for(id: String) -> Dictionary:
	if GameData.BUILDINGS[id].has("crops"):
		return {"crop": CropPatch.ORDER[rng.randi() % CropPatch.ORDER.size()], "planted": 1.0}
	return {}


func _place_plaza() -> void:
	var c: String = preset["plaza"]
	var yaw := atan2(axis.x, axis.y)
	if c != "":
		_polys.append(footprint(c, center, yaw, 0.6))
		_poly_ids.append(c)
		var h := height(center)
		var core := footprint(c, center, yaw)
		_pad(core, h)
		var entry := {"id": c, "pos": Vector3(center.x, h - 0.1, center.y), "yaw": yaw}
		buildings.append(entry)
		_clear.append([center, plaza_r + 3.0])
	_clear.append([center, plaza_r + 2.0])
	# Главные здания — по углам площади, лицом к ней.
	var lm: Array = preset["landmarks"]
	for i in lm.size():
		var id: String = lm[i]
		var ang := atan2(axis.y, axis.x) + PI * 0.25 + i * PI * 0.5
		var d := Vector2(cos(ang), sin(ang))
		var r: Rect2 = Footprints.BASE.get(id, Rect2(-1, -1, 2, 2))
		var ok := false
		for extra_r: float in [0.0, 2.0, 4.0, 6.0, 9.0]:
			var pos := center + d * (plaza_r + 1.5 + r.end.y + extra_r)
			var yaw2 := atan2(-d.x, -d.y)
			if _free(id, pos, yaw2):
				_put(id, pos, yaw2, _extra_for(id))
				ok = true
				break
		if not ok:
			_queue_later.append(id)


var _queue_later: Array[String] = []


## Дома вдоль улиц, по обе стороны, через небольшие промежутки.
func _place_houses() -> void:
	var queue: Array[String] = []
	var houses: Dictionary = preset["houses"]
	for id: String in houses:
		for k in int(houses[id]):
			queue.append(id)
	_shuffle(queue)
	queue.append_array(_queue_later)
	var shops: Array[String] = []
	for id: String in preset["workshops"]:
		shops.append(id)
	# Сначала ближе к площади — дома, на концах улиц — мастерские.
	for st in _streets:
		for side: float in [1.0, -1.0]:
			var i := 3
			while i < st.size() - 1 and not queue.is_empty():
				var id: String = queue[0]
				var r: Rect2 = Footprints.BASE.get(id, Rect2(-1, -1, 2, 2))
				if _try_street(id, st, i, side):
					queue.pop_front()
					i += ceili((r.size.x + rng.randf_range(2.0, 4.5)) / 1.5)
				else:
					i += 1
	for st in _streets:
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		for i in range(st.size() - 2, maxi(st.size() - 14, 2), -1):
			if shops.is_empty():
				break
			if _try_street(shops[0], st, i, side):
				shops.pop_front()
				side = -side
	# Что не встало у улиц — на свободные места рядом.
	for id in queue + shops:
		_place_near(id, center, 30.0, 70.0)


## На свободное место в кольце [r0, r1] вокруг точки at, повернув к ней.
func _place_near(id: String, at: Vector2, r0: float, r1: float, tries := 60) -> bool:
	for k in tries:
		var a := rng.randf() * TAU
		var r := rng.randf_range(r0, r1)
		var pos := at + Vector2(cos(a), sin(a)) * r
		var to := (at - pos).normalized()
		var yaw := atan2(to.x, to.y) + rng.randf_range(-0.3, 0.3)
		if _free(id, pos, yaw):
			_put(id, pos, yaw, _extra_for(id))
			return true
	return false


## Берег: рыбацкие хижины, мельница, маяк — лицом к воде; причалы-настилы — краем на воде.
func _place_shore() -> void:
	var shore: Dictionary = preset["shore"]
	if shore.is_empty() or water_dir == Vector2.ZERO:
		return
	# Берег вдоль воды: точки последней суши на лучах веером от середины к воде.
	var spots: Array[Array] = []
	var base := atan2(water_dir.y, water_dir.x)
	for i in 15:
		var a := base + (i - 7) * 0.13
		var d := Vector2(cos(a), sin(a))
		var last := Vector2.INF
		for s in range(10, 120, 2):
			var p := center + d * s
			if not _dry(p, 0.4):
				if last != Vector2.INF:
					spots.append([last, d])
				break
			last = p
	for id: String in shore:
		var count := int(shore[id])
		for k in count:
			if spots.is_empty():
				return
			var placed := false
			for j in spots.size():
				var idx := (j * 5 + k * 3 + id.length()) % spots.size()
				var sp: Array = spots[idx]
				var edge: Vector2 = sp[0]
				var d: Vector2 = sp[1]
				var yaw := atan2(d.x, d.y)
				var r: Rect2 = Footprints.BASE.get(id, Rect2(-1, -1, 2, 2))
				var pos: Vector2
				if id == "platform":
					pos = edge + d * 2.6
				else:
					pos = edge - d * (r.end.y + 1.2)
				for nudge: float in [0.0, -1.5, -3.0, 1.0]:
					var q := pos + d * nudge
					if _free(id, q, yaw):
						_put(id, q, yaw)
						placed = true
						break
				if placed:
					spots.remove_at(idx)
					break
			if not placed:
				break


## Хозяйство — на окраине, со стороны, противоположной воде: поля, амбары, мельницы.
func _place_farm() -> void:
	var farm: Dictionary = preset["farm"]
	var away := -water_dir if water_dir != Vector2.ZERO else Vector2(-axis.y, axis.x)
	var focus := center + away * 52.0
	var order: Array[String] = []
	for id: String in farm:
		for k in int(farm[id]):
			order.append(id)
	for id in order:
		var big := id in ["windmill", "barn", "stable", "greenhouse"]
		if not _place_near(id, focus, 4.0 if big else 2.0, 30.0 if big else 22.0, 80):
			_place_near(id, center, 40.0, 80.0, 80)


## Ограда кольцом вокруг деревни с проходами на улицах; башни по кольцу; ворота на главной.
func _place_defense() -> void:
	var ring: String = preset.get("ring", "")
	var towers := int(preset.get("towers", 0))
	if ring == "" and towers == 0:
		return
	var far := 0.0
	for e: Dictionary in buildings:
		var p: Vector3 = e["pos"]
		far = maxf(far, Vector2(p.x, p.z).distance_to(center))
	var radius := clampf(far + 7.0, 40.0, 95.0)
	# Главная улица выходит за ограду — там проход (и ворота).
	for si in mini(2, _streets.size()):
		var st: PackedVector2Array = _streets[si]
		var dir: Vector2 = (st[st.size() - 1] - st[st.size() - 2]).normalized() if st.size() > 1 else axis
		while st.size() > 0 and st[st.size() - 1].distance_to(center) < radius + 5.0:
			var next: Vector2 = st[st.size() - 1] + dir * 1.5
			if not _dry(next, 0.9):
				break
			st.append(next)
		_streets[si] = st
	var exits: Array[float] = []
	for st in _streets:
		if st.size() > 1 and st[st.size() - 1].distance_to(center) > radius - 3.0:
			var e := st[st.size() - 1] - center
			exits.append(atan2(e.y, e.x))
	var phase := rng.randf() * TAU
	if ring != "":
		var cur := PackedVector2Array()
		var n := roundi(TAU * radius / 2.0)
		for k in n + 1:
			var a := TAU * k / n
			var p := center + Vector2(cos(a), sin(a)) * (radius + sin(a * 3.0 + phase) * 2.5)
			var gap := false
			for ex in exits:
				if absf(angle_difference(a, ex)) * radius < 5.0:
					gap = true
			if gap or not _dry(p, 0.6) or _hits_building(p):
				if cur.size() > 3:
					fences.append({"type": ring, "points": cur, "seed": rng.randi() % 100000})
					_clear_line(cur, 1.6)
				cur = PackedVector2Array()
				continue
			cur.append(p)
		if cur.size() > 3:
			fences.append({"type": ring, "points": cur, "seed": rng.randi() % 100000})
			_clear_line(cur, 1.6)
	# Ворота на главной улице, башни — по кольцу между проходами.
	var gate: String = preset.get("gate", "")
	if gate != "" and not exits.is_empty():
		# Ворота — поперёк главной улицы: проезд по ней, улица под аркой не мешает.
		var a := exits[0]
		var d := Vector2(cos(a), sin(a))
		for extra: float in [1.0, 3.0, 5.0, -2.0]:
			var pos := center + d * (radius + extra)
			var yaw := atan2(d.x, d.y)
			if _free_gate(gate, pos, yaw):
				_put(gate, pos, yaw)
				break
	for k in towers:
		var a := phase + TAU * (k + 0.5) / maxf(towers, 1)
		var pos := center + Vector2(cos(a), sin(a)) * (radius - 4.5)
		var yaw := atan2(-cos(a), -sin(a))
		for nudge: float in [0.0, 0.3, -0.3, 0.6]:
			var b := a + nudge
			pos = center + Vector2(cos(b), sin(b)) * (radius - 4.5)
			if _free("watchtower", pos, yaw):
				_put("watchtower", pos, yaw)
				break


## Ворота можно ставить на улицу (она проходит под аркой) — лишь бы не на другие дома;
## факелы, на которые они попали, убираются.
func _free_gate(id: String, pos: Vector2, yaw: float) -> bool:
	var poly := footprint(id, pos, yaw, 0.5)
	var torches: Array[int] = []
	for i in _polys.size():
		if not Geometry2D.intersect_polygons(poly, _polys[i]).is_empty():
			if _poly_ids[i] != "torch":
				return false
			torches.append(i)
	for c in poly:
		if not _dry(c, 0.5):
			return false
	torches.reverse()
	for i in torches:
		var at := _polys[i][0]
		_polys.remove_at(i)
		_poly_ids.remove_at(i)
		for k in range(buildings.size() - 1, -1, -1):
			var e: Dictionary = buildings[k]
			var bp: Vector3 = e["pos"]
			if e["id"] == "torch" and Vector2(bp.x, bp.z).distance_to(at) < 1.0:
				buildings.remove_at(k)
	return true


func _hits_building(p: Vector2) -> bool:
	for poly in _polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


## Мелочи: лавочки у площади, бочки и ящики у таверны и рынка, телеги и поленницы.
func _place_decor() -> void:
	for k in 4:
		var a := atan2(axis.y, axis.x) + PI * 0.25 + k * PI * 0.5
		var d := Vector2(cos(a), sin(a))
		var pos := center + d * (plaza_r - 1.2)
		var yaw := atan2(-d.x, -d.y)
		if _free_light("bench", pos, yaw):
			_put("bench", pos, yaw)
	var signpos := center + (axis + Vector2(-axis.y, axis.x)).normalized() * (plaza_r + 1.2)
	if _free_light("signpost", signpos, 0.0):
		_put("signpost", signpos, rng.randf() * TAU)
	var near := {"tavern": ["barrels", "crates", "bench"], "market": ["crates", "cart", "barrels"], "bakery": ["woodpile", "barrels"],
		"smithy": ["woodpile", "crates"], "sawmill": ["woodpile", "cart"], "barn": ["haystack", "cart"], "stable": ["trough", "haystack"],
		"storehouse": ["crates", "cart"], "hut": ["woodpile"], "bathhouse": ["woodpile"], "wood_house": ["woodpile", "bench"]}
	var placed := 0
	for e: Dictionary in buildings.duplicate():
		var id: String = e["id"]
		if not near.has(id):
			continue
		if id in ["hut", "wood_house"] and rng.randf() < 0.55:
			continue
		var p: Vector3 = e["pos"]
		for dec: String in near[id]:
			if _place_near_light(dec, Vector2(p.x, p.z), 4.0, 7.5):
				placed += 1


## Мелочь можно ставить ближе к улице и площади (но не на них).
func _free_light(id: String, pos: Vector2, yaw: float, grow := 0.3) -> bool:
	var poly := footprint(id, pos, yaw, grow)
	for other in _polys:
		if not Geometry2D.intersect_polygons(poly, other).is_empty():
			return false
	for st in _streets:
		for c in poly:
			for k in range(0, st.size() - 1, 2):
				if Geometry2D.get_closest_point_to_segment(c, st[k], st[mini(k + 2, st.size() - 1)]).distance_to(c) < STREET_HALF + 0.1:
					return false
	for c in poly:
		if not _dry(c, 0.4):
			return false
	return true


func _place_near_light(id: String, at: Vector2, r0: float, r1: float) -> bool:
	for k in 25:
		var a := rng.randf() * TAU
		var pos := at + Vector2(cos(a), sin(a)) * rng.randf_range(r0, r1)
		var yaw := rng.randf() * TAU
		if _free_light(id, pos, yaw):
			_put(id, pos, yaw)
			return true
	return false


## Факелы вдоль улиц по очереди с обеих сторон и по углам площади.
func _place_torches() -> void:
	for k in 4:
		var a := atan2(axis.y, axis.x) + k * PI * 0.5 + PI * 0.12
		var pos := center + Vector2(cos(a), sin(a)) * (plaza_r + 0.4)
		if _free_light("torch", pos, 0.0):
			_put("torch", pos, 0.0)
	for st in _streets:
		var side := 1.0
		var since := TORCH_STEP * 0.5
		for i in range(1, st.size()):
			since += st[i].distance_to(st[i - 1])
			if since < TORCH_STEP:
				continue
			var dir := (st[i] - st[i - 1]).normalized()
			var pos := st[i] + Vector2(-dir.y, dir.x) * side * (STREET_HALF + 0.65)
			if _free_light("torch", pos, 0.0, 0.05):
				_put("torch", pos, 0.0)
				since = 0.0
				side = -side


## Яблоневый (или берёзовый) сад рядами на свободной окраине.
func _place_orchard() -> void:
	var count := int(preset.get("orchard", 0))
	if count <= 0:
		return
	var away := -water_dir if water_dir != Vector2.ZERO else -axis
	var side := Vector2(-away.y, away.x)
	var origin := center + (away + side).normalized() * 42.0
	var done := 0
	for row in 6:
		for col in 6:
			if done >= count:
				return
			var p := origin + away * row * 5.0 + side * col * 5.0 + Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
			if not _dry(p, 0.6) or _hits_building(p) or _near_street(p, 2.5):
				continue
			var tree := "tree_apple" if rng.randf() < 0.8 else "tree_oak"
			var c := Vector2i(floori(p.x / WorldGen.CHUNK_SIZE), floori(p.y / WorldGen.CHUNK_SIZE))
			var list: Array = planted.get(c, [])
			list.append({"id": tree, "x": p.x - c.x * WorldGen.CHUNK_SIZE, "z": p.y - c.y * WorldGen.CHUNK_SIZE,
				"rot": rng.randf() * TAU, "scale": rng.randf_range(0.9, 1.15), "t": 0.0})
			planted[c] = list
			_polys.append(PackedVector2Array([p + Vector2(-1, -1), p + Vector2(1, -1), p + Vector2(1, 1), p + Vector2(-1, 1)]))
			_poly_ids.append(tree)
			_clear.append([p, 2.5])
			done += 1


func _near_street(p: Vector2, reach: float) -> bool:
	for st in _streets:
		for k in range(0, st.size() - 1):
			if Geometry2D.get_closest_point_to_segment(p, st[k], st[k + 1]).distance_to(p) < reach:
				return true
	return false


## Улицы и площадь — дорожками; площадь мостится кольцами.
func _lay_paths() -> void:
	var kind: String = preset["path"]
	var layer := 0
	for st in _streets:
		var pts := st.duplicate()
		# Начало улицы — от середины площади, чтобы стыка не было видно.
		pts.insert(0, center + (st[0] - center).normalized() * (3.0 if plaza_r <= PLAZA_R else plaza_r - 0.5))
		paths.append({"type": kind, "points": pts, "width": PathSystem.WIDTH, "layer": layer})
		layer -= 1
		_clear_line(pts, 2.4)
	if plaza_r > PLAZA_R:
		return
	for r: float in [1.6, 3.0, 4.4, 5.8, 7.2]:
		var ring := PackedVector2Array()
		var n := maxi(8, roundi(TAU * r / 1.2))
		for k in n + 1:
			var a := TAU * k / n
			ring.append(center + Vector2(cos(a), sin(a)) * r)
		paths.append({"type": "stone" if kind != "brick" else "brick", "points": ring, "width": PathSystem.WIDTH, "layer": layer})
		layer -= 1


func _clear_line(pts: PackedVector2Array, radius: float) -> void:
	for k in range(0, pts.size(), 2):
		_clear.append([pts[k], radius])


static func _shuffle_static(arr: Array, r: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := r.randi() % (i + 1)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _shuffle(arr: Array) -> void:
	_shuffle_static(arr, rng)


# --- Деревья и камни на месте деревни ----------------------------------------------------

## Номера объектов мира (деревья, кусты, камни), попавших на дома, улицы и сады: их нет.
## Места объектов в чанке считаются так же, как в WorldGen.generate_chunk.
func _removed_props() -> Dictionary:
	var removed := {}
	if _clear.is_empty():
		return removed
	var grid := {}
	var box := Rect2(_clear[0][0], Vector2.ZERO)
	for c: Array in _clear:
		var p: Vector2 = c[0]
		var r: float = c[1]
		box = box.expand(p - Vector2(r, r)).expand(p + Vector2(r, r))
		var cell := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var key := cell + Vector2i(dx, dz)
				if not grid.has(key):
					grid[key] = []
				(grid[key] as Array).append(c)
	var step := WorldGen.CHUNK_SIZE / WorldGen.PROP_GRID
	var r := RandomNumberGenerator.new()
	for cz in range(floori(box.position.y / WorldGen.CHUNK_SIZE), floori(box.end.y / WorldGen.CHUNK_SIZE) + 1):
		for cx in range(floori(box.position.x / WorldGen.CHUNK_SIZE), floori(box.end.x / WorldGen.CHUNK_SIZE) + 1):
			var coord := Vector2i(cx, cz)
			var origin := Vector2(cx, cz) * WorldGen.CHUNK_SIZE
			r.seed = hash([gen.world_seed, coord.x, coord.y])
			var index := -1
			var gone := {}
			for gj in WorldGen.PROP_GRID:
				for gi in WorldGen.PROP_GRID:
					index += 1
					var jx := r.randf()
					var jz := r.randf()
					r.randf()
					r.randf()
					r.randf()
					r.randf_range(0.8, 1.2)
					var p := origin + Vector2((gi + 0.15 + jx * 0.7) * step, (gj + 0.15 + jz * 0.7) * step)
					var near: Array = grid.get(Vector2i(floori(p.x / 8.0), floori(p.y / 8.0)), [])
					for c: Array in near:
						if p.distance_to(c[0]) < float(c[1]):
							gone[index] = true
							break
			if not gone.is_empty():
				removed[coord] = gone
	return removed
