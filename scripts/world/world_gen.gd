class_name WorldGen
extends RefCounted
## Генератор бесконечного мира. Всё детерминировано сидом: один и тот же чанк
## всегда получается одинаковым, поэтому мир не хранится — хранятся только
## изменения игрока (WorldState).
##
## generate_chunk() вызывается из рабочих потоков: здесь можно только читать
## шумы и переданные копии данных, но не трогать узлы сцены.

const GameDataScript := preload("res://scripts/autoload/game_data.gd")

const CHUNK_SIZE := 32.0
## Клеток на сторону чанка. Мелкая сетка — плавные берега и русла без «ступенек».
const RES := 24
const CELL := CHUNK_SIZE / RES
## Ширина массива высот с запасом в одну вершину вокруг чанка (для гладких нормалей).
const EXT := RES + 3
## Шаг грубой сетки, на которой смешиваются цвета биомов (переходы ~30 м).
const BLEND_STEP := 8.0
const WATER_LEVEL := 0.0
## Клеток карты течения на сторону чанка (по 4 м).
const FLOW_RES := 8
const PROP_GRID := 10
const CHEST_CHANCE := 0.05
const ROCK_COLOR := Color(0.52, 0.51, 0.49)
const BANK_COLOR := Color(0.6, 0.5, 0.36)
const BED_COLOR := Color(0.6, 0.56, 0.42)
const DEEP_BED_COLOR := Color(0.36, 0.36, 0.31)
const SAND_COLOR := Color(0.86, 0.8, 0.6)
const SNOW_COLOR := Color(0.95, 0.97, 1.0)
## Глубже этого под водой живут рыбы.
const FISH_DEPTH := 1.2

## Морей нет: суша всегда выше воды, вода — только в озёрах и реках.
enum Biome { LAKE, RIVER, SHORE, PLAINS, OAK_FOREST, BIRCH_GROVE, PINE_FOREST, MAPLE_FOREST, DESERT, TUNDRA, MOUNTAIN, SNOW, JUNGLE }

## Руины старых поселений — редкая локация. Мир поделён на клетки RUIN_CELL м,
## в части клеток стоит одно разрушенное поселение радиусом до RUIN_RADIUS м.
const RUIN_CELL := 192.0
const RUIN_CHANCE := 0.24
const RUIN_RADIUS := 22.0
const RUIN_KINDS := {"ruin_house": 3.0, "ruin_wall": 4.0, "ruin_column": 2.0, "rubble": 3.0}
## Индексы особых объектов в чанке: руины и посаженные игроком деревья
## (обычные объекты нумеруются от 0 до PROP_GRID²).
const RUIN_INDEX := 200000
const PLANTED_INDEX := 100000

## density — доля мест, где что-то растёт; props — веса объектов.
const BIOMES := {
	Biome.LAKE: {"name": "Озеро", "ground": Color(0.6, 0.56, 0.42), "density": 0.5, "props": {"lily": 6.0, "reeds": 4.0}},
	Biome.RIVER: {"name": "Река", "ground": Color(0.56, 0.54, 0.46), "density": 0.35, "props": {"reeds": 5.0, "lily": 1.5}},
	Biome.SHORE: {"name": "Берег", "ground": Color(0.86, 0.8, 0.6), "density": 0.32,
		"props": {"reeds": 6.0, "sand": 4.0, "clay": 4.0, "rock": 1.5, "grass": 4.0}},
	Biome.PLAINS: {"name": "Равнины", "ground": Color(0.55, 0.74, 0.33), "density": 0.4,
		"props": {"grass": 14.0, "flowers": 22.0, "bush": 10.0, "tree_oak": 3.0, "tree_birch": 2.0, "tree_apple": 1.2, "rock": 2.5, "clay": 1.0}},
	Biome.OAK_FOREST: {"name": "Дубрава", "ground": Color(0.41, 0.6, 0.26), "density": 0.66,
		"props": {"tree_oak": 46.0, "tree_birch": 5.0, "bush": 28.0, "grass": 8.0, "flowers": 4.0, "rock": 3.0}},
	Biome.BIRCH_GROVE: {"name": "Берёзовая роща", "ground": Color(0.52, 0.71, 0.31), "density": 0.6,
		"props": {"tree_birch": 46.0, "tree_oak": 4.0, "grass": 10.0, "flowers": 12.0, "bush": 16.0, "rock": 2.0}},
	Biome.PINE_FOREST: {"name": "Хвойный лес", "ground": Color(0.34, 0.5, 0.3), "density": 0.66,
		"props": {"tree_pine": 28.0, "tree_spruce": 26.0, "rock": 6.0, "bush": 13.0, "grass": 4.0, "ore_coal": 1.5, "ore_iron": 0.8}},
	Biome.MAPLE_FOREST: {"name": "Кленовый лес", "ground": Color(0.5, 0.64, 0.28), "density": 0.62,
		"props": {"tree_maple": 44.0, "tree_birch": 8.0, "tree_oak": 4.0, "bush": 20.0, "grass": 5.0, "rock": 3.0}},
	Biome.DESERT: {"name": "Пустыня", "ground": Color(0.92, 0.79, 0.53), "density": 0.2,
		"props": {"cactus": 12.0, "sand": 8.0, "tree_dead": 2.0, "rock": 4.0, "ore_copper": 1.5, "clay": 1.0}},
	Biome.TUNDRA: {"name": "Тундра", "ground": Color(0.87, 0.91, 0.93), "density": 0.25,
		"props": {"tree_snowpine": 20.0, "rock": 6.0, "ore_iron": 1.2, "ore_coal": 1.2}},
	Biome.MOUNTAIN: {"name": "Горы", "ground": Color(0.53, 0.52, 0.5), "density": 0.22,
		"props": {"rock": 22.0, "ore_coal": 6.0, "ore_iron": 5.0, "ore_copper": 4.0, "tree_spruce": 4.0}},
	Biome.SNOW: {"name": "Снежные вершины", "ground": Color(0.95, 0.97, 1.0), "density": 0.08,
		"props": {"rock": 10.0, "ore_iron": 3.0}},
	Biome.JUNGLE: {"name": "Джунгли", "ground": Color(0.27, 0.5, 0.2), "density": 0.86,
		"props": {"tree_jungle": 44.0, "fern": 24.0, "bush": 16.0, "tree_maple": 3.0, "flowers": 4.0, "rock": 2.0}},
}

var world_seed: int
var _continent: FastNoiseLite
var _hills: FastNoiseLite
var _ridges: FastNoiseLite
var _mountain_mask: FastNoiseLite
var _temperature: FastNoiseLite
var _moisture: FastNoiseLite
var _forest: FastNoiseLite
var _lakes: FastNoiseLite
var _rivers: FastNoiseLite
var _warp: FastNoiseLite


func _init(seed_value: int) -> void:
	world_seed = seed_value
	_continent = _make_noise(seed_value, 0.0011, 4)
	_hills = _make_noise(seed_value + 1, 0.012, 3)
	_ridges = _make_noise(seed_value + 2, 0.0034, 3, FastNoiseLite.FRACTAL_RIDGED)
	_mountain_mask = _make_noise(seed_value + 3, 0.0011, 3)
	_temperature = _make_noise(seed_value + 4, 0.0008, 3)
	_moisture = _make_noise(seed_value + 5, 0.001, 3)
	_forest = _make_noise(seed_value + 6, 0.018, 2)
	_lakes = _make_noise(seed_value + 7, 0.0042, 2)
	_rivers = _make_noise(seed_value + 8, 0.0016, 2)
	_warp = _make_noise(seed_value + 9, 0.006, 2)


static func _make_noise(s: int, frequency: float, octaves: int, fractal := FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n


# --- Рельеф и биомы ------------------------------------------------------------

## Насколько точка внутри озера (x) и реки (y), 0..1, и насколько она в пологой
## речной долине (z) и на берегу озера (w). Озёра и реки сходят на нет в горах.
func water_mask(x: float, z: float) -> Vector4:
	var mountains := mountain_amount(x, z)
	var fade := 1.0 - smoothstep(0.1, 0.55, mountains)
	var l := _lakes.get_noise_2d(x, z)
	var lake := smoothstep(0.3, 0.42, l) * fade
	var shore := smoothstep(0.18, 0.36, l) * fade
	var r := absf(_river_noise(x, z))
	var river := (1.0 - smoothstep(0.015, 0.05, r)) * fade
	var valley := (1.0 - smoothstep(0.03, 0.16, r)) * fade
	return Vector4(lake, river, valley, shore)


## Течение воды: x, y — направление и сила (до 1) вдоль русла реки, z — 1 в стоячей
## воде (озёра и всё, что выкопано вне русла). Направление — вдоль линий уровня
## шума рек, поэтому вода течёт по руслу, а не в берег.
func water_flow(x: float, z: float) -> Vector3:
	var mountains := mountain_amount(x, z)
	var fade := 1.0 - smoothstep(0.1, 0.55, mountains)
	var lake := smoothstep(0.26, 0.4, _lakes.get_noise_2d(x, z)) * fade
	var n := _river_noise(x, z)
	var river := (1.0 - smoothstep(0.02, 0.06, absf(n))) * fade * (1.0 - lake)
	if river < 0.02:
		return Vector3(0.0, 0.0, 1.0)
	var e := 1.5
	var g := Vector2(_river_noise(x + e, z) - _river_noise(x - e, z), _river_noise(x, z + e) - _river_noise(x, z - e))
	if g.length_squared() < 1e-12:
		return Vector3(0.0, 0.0, 1.0)
	var dir := Vector2(-g.y, g.x).normalized()
	# У берегов течение слабее, чем на стремнине.
	var speed := smoothstep(0.0, 0.8, river)
	return Vector3(dir.x * speed, dir.y * speed, 1.0 - speed)


func _river_noise(x: float, z: float) -> float:
	var wx := x + _warp.get_noise_2d(x, z) * 70.0
	var wz := z + _warp.get_noise_2d(x + 300.0, z - 300.0) * 70.0
	return _rivers.get_noise_2d(wx, wz)


## Карта течения чанка для шейдера воды: FLOW_RES × FLOW_RES клеток, RGBA8
## (направление x, y со сдвигом 0.5; стоячесть; 1 — данные есть).
func flow_block(coord: Vector2i) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(FLOW_RES * FLOW_RES * 4)
	var cell := CHUNK_SIZE / FLOW_RES
	for j in FLOW_RES:
		for i in FLOW_RES:
			var f := water_flow(coord.x * CHUNK_SIZE + (i + 0.5) * cell, coord.y * CHUNK_SIZE + (j + 0.5) * cell)
			var o := (j * FLOW_RES + i) * 4
			bytes[o] = clampi(roundi((f.x * 0.5 + 0.5) * 255.0), 0, 255)
			bytes[o + 1] = clampi(roundi((f.y * 0.5 + 0.5) * 255.0), 0, 255)
			bytes[o + 2] = clampi(roundi(f.z * 255.0), 0, 255)
			bytes[o + 3] = 255
	return bytes


static func _has_water(heights: PackedFloat32Array) -> bool:
	for h in heights:
		if h < WATER_LEVEL + 0.3:
			return true
	return false


## 0 — равнина, 1 — сердце гор. Гор стало меньше: только там, где шум высокий.
func mountain_amount(x: float, z: float) -> float:
	return smoothstep(0.2, 0.5, _mountain_mask.get_noise_2d(x, z))


func height_at(x: float, z: float) -> float:
	var c := _continent.get_noise_2d(x, z)
	# Пологая суша, которая никогда не опускается ниже воды сама по себе.
	var h := 5.5 + c * 9.0
	h += _hills.get_noise_2d(x, z) * (1.3 + clampf(c + 0.2, 0.0, 1.0) * 5.0)
	h = maxf(h, 2.2 + _hills.get_noise_2d(x * 2.0, z * 2.0) * 0.6)
	var m := mountain_amount(x, z)
	if m > 0.0:
		# Горы реже и мягче: гребни смешаны с плавными холмами, вершины скруглены.
		var ridge := clampf((_ridges.get_noise_2d(x, z) + 0.6) / 1.6, 0.0, 1.0)
		var dome := (_hills.get_noise_2d(x * 0.3 + 91.0, z * 0.3 - 47.0) + 1.0) * 0.5
		var r := lerpf(dome, ridge, 0.45)
		r = r * r * (3.0 - 2.0 * r)
		h += m * (5.0 + r * 32.0)
	var w := water_mask(x, z)
	if w.z > 0.0:
		# Широкая пологая долина: берега спускаются к руслу без обрывов.
		var bank := 1.4 + (1.0 - w.z) * 2.5
		h = lerpf(h, minf(h, bank), smoothstep(0.0, 1.0, w.z))
		h = lerpf(h, -2.6, smoothstep(0.3, 1.0, w.y))
	if w.w > 0.0:
		var deep := smoothstep(0.42, 0.62, _lakes.get_noise_2d(x, z))
		h = lerpf(h, minf(h, 1.4 + (1.0 - w.w) * 2.0), w.w)
		h = lerpf(h, -1.6 - deep * 3.5, smoothstep(0.2, 1.0, w.x))
	return h


func biome_at(x: float, z: float, h: float) -> int:
	if h < WATER_LEVEL - 0.15:
		var w := water_mask(x, z)
		return Biome.LAKE if w.x >= w.y else Biome.RIVER
	if h > 36.0:
		return Biome.SNOW
	if h > 21.0:
		return Biome.MOUNTAIN
	var climate := climate_biome(x, z, h)
	if h < WATER_LEVEL + 0.9:
		return Biome.TUNDRA if climate == Biome.TUNDRA else Biome.SHORE
	return climate


## Биом только по климату (температура и влажность), без воды и гор.
func climate_biome(x: float, z: float, h := 0.0) -> int:
	var t := _temperature.get_noise_2d(x, z) * 1.6 - maxf(h - 12.0, 0.0) * 0.012
	var m := _moisture.get_noise_2d(x, z) * 1.6
	if t > 0.32 and m < 0.0:
		return Biome.DESERT
	if t > 0.26 and m > 0.18:
		return Biome.JUNGLE
	if t < -0.38:
		return Biome.TUNDRA
	if t < -0.12:
		return Biome.PINE_FOREST
	if m < -0.15:
		return Biome.PLAINS
	if m > 0.25:
		return Biome.MAPLE_FOREST if t > 0.12 else Biome.OAK_FOREST
	return Biome.BIRCH_GROVE if t < 0.08 else Biome.OAK_FOREST


func biome_name(biome: int) -> String:
	return BIOMES[biome]["name"]


## Ищет у начала координат ровное место на равнине или опушке, лучше — у воды.
func find_spawn() -> Vector3:
	var good := [Biome.PLAINS, Biome.OAK_FOREST, Biome.BIRCH_GROVE, Biome.MAPLE_FOREST]
	var fallback := Vector3.INF
	for r in range(0, 4000, 24):
		for k in 12:
			var a := k * TAU / 12.0
			var p := Vector2(cos(a), sin(a)) * r
			var h := height_at(p.x, p.y)
			if h < 2.0 or h > 14.0 or not (biome_at(p.x, p.y, h) in good):
				continue
			var flat := absf(height_at(p.x + 12.0, p.y) - h) + absf(height_at(p.x, p.y + 12.0) - h)
			if flat > 2.0:
				continue
			if fallback == Vector3.INF:
				fallback = Vector3(p.x, h, p.y)
			for k2 in 8:
				var a2 := k2 * TAU / 8.0
				var q := p + Vector2(cos(a2), sin(a2)) * 40.0
				if height_at(q.x, q.y) < WATER_LEVEL - 0.5:
					return Vector3(p.x, h, p.y)
		if fallback != Vector3.INF and r > 600:
			return fallback
	return fallback if fallback != Vector3.INF else Vector3(0.0, maxf(height_at(0.0, 0.0), WATER_LEVEL), 0.0)


# --- Генерация чанка (рабочий поток) ---------------------------------------------

## cover_density — густота травы 0..1 (из настроек).
## extra — правки игрока для этого чанка:
##   "cover": {Vector2i клетка 2 м: "mow" | "grass" | "tall" | "flowers"} — скошено / посеяно;
##   "planted": [{"id", "x", "z" (локально), "rot", "scale", "t" (время посадки)}];
##   "keep_cleared": true — на выровненной земле ничего не вырастает заново.
func generate_chunk(coord: Vector2i, edits: Dictionary, removed: Dictionary, chest_opened: bool, out: Dictionary,
		cover_density := 1.0, extra := {}) -> void:
	# Высоты с запасом в одну вершину вокруг — по ним считаются гладкие нормали на краях.
	var heights := PackedFloat32Array()
	heights.resize(EXT * EXT)
	for j in range(-1, RES + 2):
		for i in range(-1, RES + 2):
			var key := Vector2i(coord.x * RES + i, coord.y * RES + j)
			heights[hidx(i, j)] = edits[key] if edits.has(key) else height_at(key.x * CELL, key.y * CELL)
	out["heights"] = heights
	out["colors"] = climate_colors(coord)
	out["terrain"] = build_terrain(heights, out["colors"], coord)
	if heights.size() > 0 and _has_water(heights):
		out["flow"] = flow_block(coord)
	var keep_cleared: bool = extra.get("keep_cleared", false)

	var origin := Vector2(coord.x, coord.y) * CHUNK_SIZE
	var site := ruin_site(Vector2i(floori(origin.x / RUIN_CELL), floori(origin.y / RUIN_CELL)))
	var chest_pos := Vector3.INF
	var chest_rng := RandomNumberGenerator.new()
	chest_rng.seed = hash([world_seed, coord.x, coord.y, "chest"])
	var chest_roll := chest_rng.randf()
	var chest_local := Vector2(chest_rng.randf_range(4.0, CHUNK_SIZE - 4.0), chest_rng.randf_range(4.0, CHUNK_SIZE - 4.0))
	var chest_bonus := 0.0
	if not site.is_empty():
		var c: Vector2 = site["center"] - origin
		if c.x >= 0.0 and c.y >= 0.0 and c.x < CHUNK_SIZE and c.y < CHUNK_SIZE:
			# В центре руин всегда лежит сундук получше.
			chest_roll = 0.0
			chest_local = (c + Vector2(3.0, 2.5)).clamp(Vector2.ONE * 2.0, Vector2.ONE * (CHUNK_SIZE - 2.0))
			chest_bonus = 900.0
	if not chest_opened and chest_roll < CHEST_CHANCE:
		var h := sample_height(heights, coord, chest_local.x, chest_local.y)
		if h > WATER_LEVEL + 0.3:
			chest_pos = Vector3(chest_local.x, h, chest_local.y)
			var distance := (origin + chest_local).length() + chest_bonus
			out["chest"] = {"pos": chest_pos, "rot": chest_rng.randf() * TAU,
				"rarity": roll_chest_rarity(chest_rng.randf(), distance)}

	var props: Array[Dictionary] = []
	# Руины этого поселения, попавшие в чанк.
	var ruin_spots: Array[Vector2] = []
	if not site.is_empty():
		var items: Array = site["items"]
		for k in items.size():
			var item: Dictionary = items[k]
			ruin_spots.append(item["pos"])
			var local: Vector2 = item["pos"] - origin
			if local.x < 0.0 or local.y < 0.0 or local.x >= CHUNK_SIZE or local.y >= CHUNK_SIZE:
				continue
			if removed.has(RUIN_INDEX + k):
				continue
			var h := sample_height(heights, coord, local.x, local.y)
			props.append({"id": item["id"], "index": RUIN_INDEX + k, "pos": Vector3(local.x, h - 0.15, local.y), "rot": item["rot"],
				"scale": item["scale"], "variant": k % PropFactory.VARIANTS.get(item["id"], 1), "float": false})

	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, coord.x, coord.y])
	var step := CHUNK_SIZE / PROP_GRID
	var index := -1
	for gj in PROP_GRID:
		for gi in PROP_GRID:
			index += 1
			# Одинаковое число бросков на каждое место — индексы объектов стабильны,
			# по ним WorldState помнит, что уже срублено.
			var jx := rng.randf()
			var jz := rng.randf()
			var roll := rng.randf()
			var pick := rng.randf()
			var rot := rng.randf() * TAU
			var scale := rng.randf_range(0.8, 1.2)
			if removed.has(index):
				continue
			var lx := (gi + 0.15 + jx * 0.7) * step
			var lz := (gj + 0.15 + jz * 0.7) * step
			if chest_pos != Vector3.INF and Vector2(lx - chest_pos.x, lz - chest_pos.z).length() < 2.5:
				continue
			if keep_cleared and _is_edited(edits, coord, lx, lz):
				continue
			var world := origin + Vector2(lx, lz)
			if _near_any(ruin_spots, world, 4.0):
				continue
			var h := sample_height(heights, coord, lx, lz)
			# На границе биомов деревья перемешиваются: биом берётся со сдвигом до 9 м.
			var biome := biome_at(world.x + sin(rot) * 9.0, world.y + cos(rot) * 9.0, h)
			# Но на самих горах и в пустыне растёт только своё — никаких кустов на скалах.
			var here := biome_at(world.x, world.y, h)
			if here in [Biome.MOUNTAIN, Biome.SNOW, Biome.DESERT] and here != biome:
				biome = here
			var def: Dictionary = BIOMES[biome]
			var forest := _forest.get_noise_2d(world.x, world.y)
			var density := float(def["density"]) * clampf(0.45 + forest * 1.6, 0.15, 1.4)
			if not site.is_empty() and (site["center"] as Vector2).distance_to(world) < RUIN_RADIUS:
				density *= 0.35
			if roll > density:
				continue
			var prop_id := _pick_weighted(def["props"], pick)
			if prop_id == "":
				continue
			var pdef: Dictionary = GameDataScript.PROPS[prop_id]
			var place: String = pdef.get("place", "land")
			var y := h
			match place:
				"float":
					if h > WATER_LEVEL - 0.5 or h < WATER_LEVEL - 2.2:
						continue
					y = WATER_LEVEL + 0.01
				"shallow":
					if h > WATER_LEVEL + 0.5 or h < WATER_LEVEL - 0.7:
						continue
				_:
					if h < WATER_LEVEL + 0.25:
						continue
			if pdef.has("max_height") and h > float(pdef["max_height"]):
				continue
			var slope := _slope(heights, coord, lx, lz)
			if pdef["kind"] == "tree" and slope > 0.75:
				continue
			if pdef["kind"] in ["bush", "decor"] and place == "land" and slope > 0.6:
				continue
			var variants: int = PropFactory.VARIANTS.get(prop_id, 1)
			props.append({"id": prop_id, "index": index, "pos": Vector3(lx, y, lz), "rot": rot, "scale": scale,
				"variant": int(jx * 997.0 + jz * 131.0) % variants, "float": place == "float"})
	# Деревья, посаженные игроком.
	var planted: Array = extra.get("planted", [])
	for k in planted.size():
		if removed.has(PLANTED_INDEX + k):
			continue
		var entry: Dictionary = planted[k]
		var lx: float = entry["x"]
		var lz: float = entry["z"]
		props.append({"id": entry["id"], "index": PLANTED_INDEX + k, "pos": Vector3(lx, sample_height(heights, coord, lx, lz), lz),
			"rot": entry["rot"], "scale": entry["scale"], "variant": k % PropFactory.VARIANTS.get(entry["id"], 1), "float": false,
			"planted_at": entry["t"]})
	out["props"] = props

	# Места для рыб — глубокие клетки; стаи плавают между ними.
	var fish_spots: Array[Vector3] = []
	for j in range(0, RES, 2):
		for i in range(0, RES, 2):
			var hc := (heights[hidx(i, j)] + heights[hidx(i + 2, j)] + heights[hidx(i, j + 2)] + heights[hidx(i + 2, j + 2)]) * 0.25
			if hc < WATER_LEVEL - FISH_DEPTH:
				fish_spots.append(Vector3((i + 1.0) * CELL, hc, (j + 1.0) * CELL))
	out["fish_spots"] = fish_spots
	out["has_water"] = not fish_spots.is_empty()
	var cleared_edits: Dictionary = edits if keep_cleared else {}
	# Дальним чанкам трава не нужна (её там не видно): ChunkManager досоздаст её,
	# когда камера подойдёт ближе.
	if cover_density > 0.0:
		_scatter_cover(coord, heights, out["colors"], cover_density, out, extra.get("cover", {}), cleared_edits)
	else:
		out["cover_skipped"] = true


## Попадает ли точка (локально в чанке) на выровненную игроком землю.
static func _is_edited(edits: Dictionary, coord: Vector2i, lx: float, lz: float) -> bool:
	if edits.is_empty():
		return false
	return edits.has(Vector2i(coord.x * RES + roundi(lx / CELL), coord.y * RES + roundi(lz / CELL)))


static func _near_any(points: Array[Vector2], p: Vector2, radius: float) -> bool:
	for q in points:
		if q.distance_squared_to(p) < radius * radius:
			return true
	return false


## Поселение-руины в клетке мира (или пустой словарь, если там его нет):
## {"center": Vector2, "items": [{"id", "pos": Vector2, "rot", "scale"}]}.
## Поселения стоят только на ровной суше — не в горах и не у воды.
func ruin_site(cell: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, cell.x, cell.y, "ruin"])
	if rng.randf() > RUIN_CHANCE:
		return {}
	var center := (Vector2(cell) + Vector2(rng.randf_range(0.25, 0.75), rng.randf_range(0.25, 0.75))) * RUIN_CELL
	var h := height_at(center.x, center.y)
	if h < 2.0 or h > 18.0 or mountain_amount(center.x, center.y) > 0.02:
		return {}
	var w := water_mask(center.x, center.y)
	if w.z > 0.15 or w.w > 0.15:
		return {}
	for k in 8:
		var a := k * TAU / 8.0
		var p := center + Vector2(cos(a), sin(a)) * (RUIN_RADIUS - 4.0)
		if absf(height_at(p.x, p.y) - h) > 3.0 or water_mask(p.x, p.y).z > 0.3:
			return {}
	var items := []
	if rng.randf() < 0.6:
		items.append({"id": "ruin_tower", "pos": center, "rot": rng.randf() * TAU, "scale": rng.randf_range(0.9, 1.1)})
	var count := rng.randi_range(4, 7)
	for k in count:
		var a := k * TAU / count + rng.randf_range(-0.3, 0.3)
		var r := rng.randf_range(7.0, RUIN_RADIUS - 3.0)
		var id := _pick_weighted(RUIN_KINDS, rng.randf())
		items.append({"id": id, "pos": center + Vector2(cos(a), sin(a)) * r, "rot": rng.randf() * TAU,
			"scale": rng.randf_range(0.85, 1.1)})
	return {"center": center, "items": items}


## Есть ли рядом с точкой руины (для подписи «Руины» и карты).
func ruin_near(x: float, z: float, radius := RUIN_RADIUS + 6.0) -> bool:
	var site := ruin_site(Vector2i(floori(x / RUIN_CELL), floori(z / RUIN_CELL)))
	return not site.is_empty() and (site["center"] as Vector2).distance_to(Vector2(x, z)) < radius


## Насколько густая трава в биоме (0 — нет), лежат ли там опавшие листья,
## растёт ли высокая трава и бывают ли поляны цветов.
const COVER := {
	Biome.PLAINS: [1.0, false, true, true], Biome.BIRCH_GROVE: [0.85, true, true, true],
	Biome.OAK_FOREST: [0.7, true, false, true], Biome.MAPLE_FOREST: [0.7, true, false, true],
	Biome.PINE_FOREST: [0.5, false, false, false], Biome.JUNGLE: [1.0, true, true, true],
	Biome.SHORE: [0.25, false, true, false], Biome.TUNDRA: [0.15, false, false, false],
}
const DEFAULT_GREEN := Color(0.45, 0.66, 0.28)


## Трава, высокая трава, цветы и листья на земле. Правки игрока (cover_edits)
## важнее природы: скошенное пусто, посеянное растёт даже в пустыне.
func _scatter_cover(coord: Vector2i, heights: PackedFloat32Array, colors: PackedColorArray, density: float, out: Dictionary,
		cover_edits := {}, cleared := {}) -> void:
	var stride := GroundCover.GRASS_STRIDE
	var grass := PackedFloat32Array()
	var tall := PackedFloat32Array()
	var flowers := PackedFloat32Array()
	var litter := PackedFloat32Array()
	var n_grass := 0
	var n_tall := 0
	var n_flowers := 0
	var n_litter := 0
	var origin := Vector2(coord.x, coord.y) * CHUNK_SIZE
	# Биом на грубой сетке 8 м — дёшево и достаточно точно для травы.
	var biomes := PackedByteArray()
	biomes.resize(25)
	for gz in 5:
		for gx in 5:
			biomes[gz * 5 + gx] = climate_biome(origin.x + gx * 8.0, origin.y + gz * 8.0)
	# По вершинам сетки — один раз на чанк: крутизна склона и цвет земли
	# (раньше это считалось для каждого пучка — тысячи раз).
	var vn := RES + 1
	var vslope := PackedFloat32Array()
	vslope.resize(vn * vn)
	var vground := PackedColorArray()
	vground.resize(vn * vn)
	for j in vn:
		for i in vn:
			var dx := heights[hidx(i + 1, j)] - heights[hidx(i - 1, j)]
			var dz := heights[hidx(i, j + 1)] - heights[hidx(i, j - 1)]
			vslope[j * vn + i] = Vector2(dx, dz).length() / (2.0 * CELL)
			vground[j * vn + i] = ground_color(colors[j * vn + i], heights[hidx(i, j)], 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, coord.x, coord.y, "cover"])
	density = clampf(density, 0.05, 1.0)
	# Шаг сетки сильно зависит от густоты: 100% — пучок на каждые ~0.6 м.
	var cells := int(CHUNK_SIZE / lerpf(2.2, 0.62, density))
	var step := CHUNK_SIZE / cells
	grass.resize(cells * cells * stride)
	for gj in cells:
		for gi in cells:
			# Все случайные числа клетки берём сразу: если клетку скосили или
			# выровняли, остальной покров чанка остаётся ровно таким же, как был.
			var lx := (gi + rng.randf()) * step
			var lz := (gj + rng.randf()) * step
			var angle := rng.randf() * TAU
			var scale := rng.randf_range(0.75, 1.3)
			var roll := rng.randf()
			var tint := rng.randf_range(0.93, 1.07)
			var odd_petal := rng.randf()
			var odd_pick := rng.randi()
			var world := origin + Vector2(lx, lz)
			var edit: String = cover_edits.get(Vector2i(floori(world.x / 2.0), floori(world.y / 2.0)), "") if not cover_edits.is_empty() else ""
			if edit == "mow":
				continue
			if edit == "" and not cleared.is_empty() and _is_edited(cleared, coord, lx, lz):
				continue
			var info: Array = COVER.get(biomes[roundi(lz / 8.0) * 5 + roundi(lx / 8.0)], [0.0, false, false, false])
			if edit == "" and roll > float(info[0]):
				continue
			var k := clampi(roundi(lz / CELL), 0, RES) * vn + clampi(roundi(lx / CELL), 0, RES)
			if vslope[k] > (0.7 if edit != "" else 0.55):
				continue
			var h := sample_height(heights, coord, lx, lz)
			if h < WATER_LEVEL + (0.3 if edit != "" else 0.6):
				continue
			var ground := vground[k]
			if ground.g - maxf(ground.r, ground.b) < 0.06:
				if edit == "":
					continue
				ground = DEFAULT_GREEN
			var col := Color(ground.r * tint, ground.g * tint, ground.b * tint)
			var kind := edit
			if kind == "":
				kind = "grass"
				# Поляны высокой травы и цветов — пятнами по шуму.
				if info[2] and _forest.get_noise_2d(world.x * 2.3 + 500.0, world.y * 2.3) > 0.22:
					kind = "tall"
				elif info[3] and _forest.get_noise_2d(world.x * 3.1 - 800.0, world.y * 3.1) > 0.3 and roll < float(info[0]) * 0.6:
					kind = "flowers"
			match kind:
				"tall":
					n_tall = GroundCover.put_instance(tall, n_tall, stride, Vector3(lx, h, lz), angle, scale, col)
				"flowers":
					# Поляна одного цвета: цвет зависит от клетки 10 м.
					var patch := hash(Vector2i(floori(world.x / 10.0), floori(world.y / 10.0)) + Vector2i(world_seed, 7))
					var petal: Color = GroundCover.FLOWER_COLORS[absi(patch) % GroundCover.FLOWER_COLORS.size()]
					if odd_petal < 0.2:
						petal = GroundCover.FLOWER_COLORS[odd_pick % GroundCover.FLOWER_COLORS.size()]
					n_flowers = GroundCover.put_instance(flowers, n_flowers, stride, Vector3(lx, h, lz), angle, scale * 0.9, petal)
					# Под цветами — немного обычной травы.
					n_grass = GroundCover.put_instance(grass, n_grass, stride, Vector3(lx + 0.3, h, lz - 0.2), angle + 1.0, scale * 0.8, col)
				_:
					n_grass = GroundCover.put_instance(grass, n_grass, stride, Vector3(lx, h, lz), angle, scale, col)
	# Опавшие листья — в лиственных лесах.
	var lstride := GroundCover.LITTER_STRIDE
	var lcells := 10
	var lstep := CHUNK_SIZE / lcells
	for gj in lcells:
		for gi in lcells:
			var lx := (gi + rng.randf()) * lstep
			var lz := (gj + rng.randf()) * lstep
			var angle := rng.randf() * TAU
			var litter_seed := rng.randf()
			var litter_scale := rng.randf_range(0.8, 1.3)
			var info: Array = COVER.get(biomes[roundi(lz / 8.0) * 5 + roundi(lx / 8.0)], [0.0, false, false, false])
			if not info[1]:
				continue
			var k := clampi(roundi(lz / CELL), 0, RES) * vn + clampi(roundi(lx / CELL), 0, RES)
			if vslope[k] > 0.5:
				continue
			var h := sample_height(heights, coord, lx, lz)
			if h < WATER_LEVEL + 0.5:
				continue
			if not cleared.is_empty() and _is_edited(cleared, coord, lx, lz):
				continue
			n_litter = GroundCover.put_instance(litter, n_litter, lstride, Vector3(lx, h, lz), angle, litter_scale, Color.WHITE, litter_seed)
	grass.resize(n_grass * stride)
	tall.resize(n_tall * stride)
	flowers.resize(n_flowers * stride)
	litter.resize(n_litter * lstride)
	out["grass"] = grass
	out["tall"] = tall
	out["flowers"] = flowers
	out["litter"] = litter


static func roll_chest_rarity(r: float, distance: float) -> String:
	var bonus := 1.0 + distance / 600.0
	var weights: Array[float] = []
	var total := 0.0
	for i in GameDataScript.CHEST_RARITIES.size():
		var id: String = GameDataScript.CHEST_RARITIES[i]
		var w: float = GameDataScript.CHESTS[id]["weight"] * pow(bonus, i * 0.6)
		weights.append(w)
		total += w
	r *= total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return GameDataScript.CHEST_RARITIES[i]
	return GameDataScript.CHEST_RARITIES[0]


static func _pick_weighted(table: Dictionary, r: float) -> String:
	var total := 0.0
	for id: String in table:
		total += table[id]
	r *= total
	for id: String in table:
		r -= table[id]
		if r <= 0.0:
			return id
	return ""


static func _slope(heights: PackedFloat32Array, coord: Vector2i, lx: float, lz: float) -> float:
	var dx := sample_height(heights, coord, lx + 1.0, lz) - sample_height(heights, coord, lx - 1.0, lz)
	var dz := sample_height(heights, coord, lx, lz + 1.0) - sample_height(heights, coord, lx, lz - 1.0)
	return Vector2(dx, dz).length() * 0.5


# --- Сетка рельефа -----------------------------------------------------------------

static func hidx(i: int, j: int) -> int:
	return (j + 1) * EXT + (i + 1)


## Цвет почвы по климату для каждой вершины чанка. Считается на грубой сетке
## (шаг 8 м), размывается и плавно интерполируется — биомы перетекают друг
## в друга на десятках метров, без резкой границы и «лесенки» треугольников.
func climate_colors(coord: Vector2i) -> PackedColorArray:
	var base := Vector2i(floori(coord.x * CHUNK_SIZE / BLEND_STEP), floori(coord.y * CHUNK_SIZE / BLEND_STEP))
	var w := 12
	var raw := PackedColorArray()
	raw.resize(w * w)
	for gz in w:
		for gx in w:
			var b := climate_biome((base.x + gx - 3) * BLEND_STEP, (base.y + gz - 3) * BLEND_STEP)
			raw[gz * w + gx] = BIOMES[b]["ground"]
	# Размытие 5×5 с весами 1-4-6-4-1.
	var kernel := [1.0, 4.0, 6.0, 4.0, 1.0]
	var blurred := PackedColorArray()
	blurred.resize(w * w)
	for gz in range(2, w - 2):
		for gx in range(2, w - 2):
			var acc := Color(0, 0, 0)
			var total := 0.0
			for dz in 5:
				for dx in 5:
					var k: float = kernel[dz] * kernel[dx]
					acc += raw[(gz + dz - 2) * w + gx + dx - 2] * k
					total += k
			blurred[gz * w + gx] = acc / total
	var colors := PackedColorArray()
	colors.resize((RES + 1) * (RES + 1))
	for j in RES + 1:
		for i in RES + 1:
			var fx := (coord.x * CHUNK_SIZE + i * CELL) / BLEND_STEP - base.x + 3.0
			var fz := (coord.y * CHUNK_SIZE + j * CELL) / BLEND_STEP - base.y + 3.0
			var gx := floori(fx)
			var gz := floori(fz)
			var tx := smoothstep(0.0, 1.0, fx - gx)
			var tz := smoothstep(0.0, 1.0, fz - gz)
			var c0 := blurred[gz * w + gx].lerp(blurred[gz * w + gx + 1], tx)
			var c1 := blurred[(gz + 1) * w + gx].lerp(blurred[(gz + 1) * w + gx + 1], tx)
			colors[j * (RES + 1) + i] = c0.lerp(c1, tz)
	return colors


## Итоговый цвет вершины: климат + плавные полосы берега, дна, гор, снега и склонов.
static func ground_color(climate: Color, h: float, up: float) -> Color:
	var c := climate
	var pale := clampf((climate.b - 0.7) * 4.0, 0.0, 1.0)
	c = c.lerp(SAND_COLOR, smoothstep(1.5, 0.3, h) * 0.85 * (1.0 - pale))
	c = c.lerp(ROCK_COLOR, smoothstep(20.0, 32.0, h) * 0.85)
	c = c.lerp(SNOW_COLOR, smoothstep(40.0, 52.0, h))
	if h > WATER_LEVEL + 0.3:
		# Крутой склон — камень, а у самой воды — тёплый земляной обрыв, а не серо-лиловая скала.
		var cliff := ROCK_COLOR.lerp(BANK_COLOR, smoothstep(3.5, 1.0, h))
		c = c.lerp(cliff, smoothstep(0.9, 0.68, up) * (1.0 - smoothstep(40.0, 52.0, h) * 0.6))
	var bed := BED_COLOR.lerp(DEEP_BED_COLOR, smoothstep(-0.6, -3.5, h))
	return c.lerp(bed, smoothstep(0.25, -0.9, h))


## Меш рельефа с гладкими нормалями и цветами по вершинам (индексный).
static func build_terrain(heights: PackedFloat32Array, colors: PackedColorArray, coord: Vector2i) -> Array:
	var n := RES + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	cols.resize(n * n)
	for j in n:
		for i in n:
			var h := heights[hidx(i, j)]
			var normal := Vector3(heights[hidx(i - 1, j)] - heights[hidx(i + 1, j)], 2.0 * CELL,
				heights[hidx(i, j - 1)] - heights[hidx(i, j + 1)]).normalized()
			var k := j * n + i
			verts[k] = Vector3(i * CELL, h, j * CELL)
			normals[k] = normal
			cols[k] = ground_color(colors[k], h, normal.y)
	var indices := PackedInt32Array()
	indices.resize(RES * RES * 6)
	var t := 0
	for j in RES:
		for i in RES:
			var k := j * n + i
			# Лицевая сторона в Godot — обход по часовой стрелке (если смотреть сверху).
			if cell_flip(coord.x * RES + i, coord.y * RES + j):
				indices[t] = k
				indices[t + 1] = k + 1
				indices[t + 2] = k + n
				indices[t + 3] = k + 1
				indices[t + 4] = k + n + 1
				indices[t + 5] = k + n
			else:
				indices[t] = k
				indices[t + 1] = k + 1
				indices[t + 2] = k + n + 1
				indices[t + 3] = k
				indices[t + 4] = k + n + 1
				indices[t + 5] = k + n
			t += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


static func cell_flip(vx: int, vz: int) -> bool:
	return hash01(vx, vz, 13) > 0.5


## Высота внутри клетки по тем же треугольникам, что и в меше,
## чтобы деревья и здания стояли ровно на поверхности.
static func interp_cell(h00: float, h10: float, h01: float, h11: float, tx: float, tz: float, flip: bool) -> float:
	if flip:
		if tx + tz <= 1.0:
			return h00 + (h10 - h00) * tx + (h01 - h00) * tz
		return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)
	if tx >= tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


static func sample_height(heights: PackedFloat32Array, coord: Vector2i, lx: float, lz: float) -> float:
	var fx := clampf(lx / CELL, 0.0, RES - 0.0001)
	var fz := clampf(lz / CELL, 0.0, RES - 0.0001)
	var i := int(fx)
	var j := int(fz)
	return interp_cell(heights[hidx(i, j)], heights[hidx(i + 1, j)], heights[hidx(i, j + 1)], heights[hidx(i + 1, j + 1)],
		fx - i, fz - j, cell_flip(coord.x * RES + i, coord.y * RES + j))


static func hash01(x: int, y: int, s: int) -> float:
	var h := x * 374761393 + y * 668265263 + s * 982451653
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0
