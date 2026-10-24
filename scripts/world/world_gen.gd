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
const RES := 16
const CELL := CHUNK_SIZE / RES
const WATER_LEVEL := 0.0
const PROP_GRID := 10
const CHEST_CHANCE := 0.05
const ROCK_COLOR := Color(0.5, 0.49, 0.47)
const BED_COLOR := Color(0.55, 0.52, 0.4)
## Глубже этого под водой живут рыбы.
const FISH_DEPTH := 1.2

## Морей нет: суша всегда выше воды, вода — только в озёрах и реках.
enum Biome { LAKE, RIVER, SHORE, PLAINS, OAK_FOREST, BIRCH_GROVE, PINE_FOREST, MAPLE_FOREST, DESERT, TUNDRA, MOUNTAIN, SNOW }

## density — доля мест, где что-то растёт; props — веса объектов.
const BIOMES := {
	Biome.LAKE: {"name": "Озеро", "ground": Color(0.6, 0.56, 0.42), "density": 0.5, "props": {"lily": 6.0, "reeds": 4.0}},
	Biome.RIVER: {"name": "Река", "ground": Color(0.56, 0.54, 0.46), "density": 0.35, "props": {"reeds": 5.0, "lily": 1.5}},
	Biome.SHORE: {"name": "Берег", "ground": Color(0.86, 0.8, 0.6), "density": 0.32,
		"props": {"reeds": 6.0, "sand": 4.0, "clay": 4.0, "rock": 1.5, "grass": 4.0}},
	Biome.PLAINS: {"name": "Равнины", "ground": Color(0.55, 0.74, 0.33), "density": 0.45,
		"props": {"grass": 40.0, "flowers": 20.0, "bush": 9.0, "tree_oak": 3.0, "tree_birch": 2.0, "rock": 2.5, "clay": 1.0}},
	Biome.OAK_FOREST: {"name": "Дубрава", "ground": Color(0.41, 0.6, 0.26), "density": 0.62,
		"props": {"tree_oak": 46.0, "tree_birch": 5.0, "bush": 16.0, "grass": 16.0, "flowers": 4.0, "rock": 3.0}},
	Biome.BIRCH_GROVE: {"name": "Берёзовая роща", "ground": Color(0.52, 0.71, 0.31), "density": 0.56,
		"props": {"tree_birch": 46.0, "tree_oak": 4.0, "grass": 22.0, "flowers": 12.0, "bush": 7.0, "rock": 2.0}},
	Biome.PINE_FOREST: {"name": "Хвойный лес", "ground": Color(0.34, 0.5, 0.3), "density": 0.62,
		"props": {"tree_pine": 28.0, "tree_spruce": 26.0, "rock": 6.0, "bush": 5.0, "grass": 8.0, "ore_coal": 1.5, "ore_iron": 0.8}},
	Biome.MAPLE_FOREST: {"name": "Кленовый лес", "ground": Color(0.5, 0.64, 0.28), "density": 0.58,
		"props": {"tree_maple": 44.0, "tree_birch": 8.0, "tree_oak": 4.0, "bush": 9.0, "grass": 10.0, "rock": 3.0}},
	Biome.DESERT: {"name": "Пустыня", "ground": Color(0.92, 0.79, 0.53), "density": 0.14,
		"props": {"sand": 10.0, "tree_dead": 3.0, "rock": 4.0, "ore_copper": 1.5, "clay": 1.0}},
	Biome.TUNDRA: {"name": "Тундра", "ground": Color(0.87, 0.91, 0.93), "density": 0.25,
		"props": {"tree_snowpine": 20.0, "rock": 6.0, "ore_iron": 1.2, "ore_coal": 1.2}},
	Biome.MOUNTAIN: {"name": "Горы", "ground": Color(0.53, 0.52, 0.5), "density": 0.22,
		"props": {"rock": 22.0, "ore_coal": 6.0, "ore_iron": 5.0, "ore_copper": 4.0, "tree_spruce": 4.0}},
	Biome.SNOW: {"name": "Снежные вершины", "ground": Color(0.95, 0.97, 1.0), "density": 0.08,
		"props": {"rock": 10.0, "ore_iron": 3.0}},
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
	_ridges = _make_noise(seed_value + 2, 0.0045, 5, FastNoiseLite.FRACTAL_RIDGED)
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
	var mountains := smoothstep(0.08, 0.42, _mountain_mask.get_noise_2d(x, z))
	var fade := 1.0 - smoothstep(0.1, 0.55, mountains)
	var l := _lakes.get_noise_2d(x, z)
	var lake := smoothstep(0.3, 0.42, l) * fade
	var shore := smoothstep(0.18, 0.36, l) * fade
	var wx := x + _warp.get_noise_2d(x, z) * 70.0
	var wz := z + _warp.get_noise_2d(x + 300.0, z - 300.0) * 70.0
	var r := absf(_rivers.get_noise_2d(wx, wz))
	var river := (1.0 - smoothstep(0.015, 0.05, r)) * fade
	var valley := (1.0 - smoothstep(0.03, 0.16, r)) * fade
	return Vector4(lake, river, valley, shore)


func height_at(x: float, z: float) -> float:
	var c := _continent.get_noise_2d(x, z)
	# Пологая суша, которая никогда не опускается ниже воды сама по себе.
	var h := 5.5 + c * 9.0
	h += _hills.get_noise_2d(x, z) * (1.3 + clampf(c + 0.2, 0.0, 1.0) * 5.0)
	h = maxf(h, 2.2 + _hills.get_noise_2d(x * 2.0, z * 2.0) * 0.6)
	var m := smoothstep(0.08, 0.42, _mountain_mask.get_noise_2d(x, z))
	if m > 0.0:
		var r := (_ridges.get_noise_2d(x, z) + 0.6) / 1.6
		h += m * (8.0 + r * r * 70.0)
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
	var t := _temperature.get_noise_2d(x, z) * 1.6 - maxf(h - 12.0, 0.0) * 0.012
	var m := _moisture.get_noise_2d(x, z) * 1.6
	if h > 46.0:
		return Biome.SNOW
	if h > 26.0:
		return Biome.MOUNTAIN
	if h < WATER_LEVEL + 0.9:
		return Biome.SHORE if t > -0.35 else Biome.TUNDRA
	if t > 0.32 and m < 0.0:
		return Biome.DESERT
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

func generate_chunk(coord: Vector2i, edits: Dictionary, removed: Dictionary, chest_opened: bool, out: Dictionary) -> void:
	var n := RES + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var colors := PackedColorArray()
	colors.resize(n * n)
	var biomes := PackedByteArray()
	biomes.resize(n * n)
	for j in n:
		for i in n:
			var key := Vector2i(coord.x * RES + i, coord.y * RES + j)
			var wx := key.x * CELL
			var wz := key.y * CELL
			var h: float = edits[key] if edits.has(key) else height_at(wx, wz)
			var biome := biome_at(wx, wz, h)
			var ground: Color = BIOMES[biome]["ground"]
			var tint := 1.0 + (hash01(key.x, key.y, world_seed) - 0.5) * 0.08
			heights[j * n + i] = h
			biomes[j * n + i] = biome
			colors[j * n + i] = Color(ground.r * tint, ground.g * tint, ground.b * tint)

	out["heights"] = heights
	out["colors"] = colors
	out["terrain"] = build_terrain(heights, colors, coord)

	var origin := Vector2(coord.x, coord.y) * CHUNK_SIZE
	var chest_pos := Vector3.INF
	var chest_rng := RandomNumberGenerator.new()
	chest_rng.seed = hash([world_seed, coord.x, coord.y, "chest"])
	if not chest_opened and chest_rng.randf() < CHEST_CHANCE:
		var lx := chest_rng.randf_range(4.0, CHUNK_SIZE - 4.0)
		var lz := chest_rng.randf_range(4.0, CHUNK_SIZE - 4.0)
		var h := sample_height(heights, coord, lx, lz)
		if h > WATER_LEVEL + 0.3:
			chest_pos = Vector3(lx, h, lz)
			var distance := (origin + Vector2(lx, lz)).length()
			out["chest"] = {"pos": chest_pos, "rot": chest_rng.randf() * TAU,
				"rarity": roll_chest_rarity(chest_rng.randf(), distance)}

	var props: Array[Dictionary] = []
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
			var h := sample_height(heights, coord, lx, lz)
			var biome: int = biomes[roundi(lz / CELL) * n + roundi(lx / CELL)]
			var def: Dictionary = BIOMES[biome]
			var forest := _forest.get_noise_2d(origin.x + lx, origin.y + lz)
			if roll > float(def["density"]) * clampf(0.45 + forest * 1.6, 0.15, 1.4):
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
			if pdef["kind"] == "tree" and _slope(heights, coord, lx, lz) > 0.75:
				continue
			var variants: int = PropFactory.VARIANTS.get(prop_id, 1)
			props.append({"id": prop_id, "index": index, "pos": Vector3(lx, y, lz), "rot": rot, "scale": scale,
				"variant": int(jx * 997.0 + jz * 131.0) % variants, "float": place == "float"})
	out["props"] = props

	# Места для рыб — глубокие клетки; стаи плавают между ними.
	var fish_spots: Array[Vector3] = []
	for j in RES:
		for i in RES:
			var hc := (heights[j * n + i] + heights[j * n + i + 1] + heights[(j + 1) * n + i] + heights[(j + 1) * n + i + 1]) * 0.25
			if hc < WATER_LEVEL - FISH_DEPTH:
				fish_spots.append(Vector3((i + 0.5) * CELL, hc, (j + 0.5) * CELL))
	out["fish_spots"] = fish_spots
	out["has_water"] = not fish_spots.is_empty()


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

## Строит плоско-затенённый меш рельефа (массивы для ArrayMesh). Диагональ
## каждой клетки выбирается псевдослучайно — сетка не выглядит «по линейке».
static func build_terrain(heights: PackedFloat32Array, colors: PackedColorArray, coord: Vector2i) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var n := RES + 1
	for j in RES:
		for i in RES:
			var k := j * n + i
			var p00 := Vector3(i * CELL, heights[k], j * CELL)
			var p10 := Vector3((i + 1) * CELL, heights[k + 1], j * CELL)
			var p01 := Vector3(i * CELL, heights[k + n], (j + 1) * CELL)
			var p11 := Vector3((i + 1) * CELL, heights[k + n + 1], (j + 1) * CELL)
			var vx := coord.x * RES + i
			var vz := coord.y * RES + j
			if cell_flip(vx, vz):
				_terrain_face(verts, normals, cols, p00, p10, p01, (colors[k] + colors[k + 1] + colors[k + n]) / 3.0, vx * 2, vz)
				_terrain_face(verts, normals, cols, p10, p11, p01, (colors[k + 1] + colors[k + n + 1] + colors[k + n]) / 3.0, vx * 2 + 1, vz)
			else:
				_terrain_face(verts, normals, cols, p00, p10, p11, (colors[k] + colors[k + 1] + colors[k + n + 1]) / 3.0, vx * 2, vz)
				_terrain_face(verts, normals, cols, p00, p11, p01, (colors[k] + colors[k + n + 1] + colors[k + n]) / 3.0, vx * 2 + 1, vz)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	return arrays


static func _terrain_face(verts: PackedVector3Array, normals: PackedVector3Array, cols: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, color: Color, hx: int, hz: int) -> void:
	# В Godot лицевая сторона — обход по часовой стрелке: нормаль = (c - a) × (b - a).
	var normal := (c - a).cross(b - a).normalized()
	if normal.y < 0.0:
		var t := b
		b = c
		c = t
		normal = -normal
	var avg_h := (a.y + b.y + c.y) / 3.0
	if normal.y < 0.8 and avg_h > WATER_LEVEL + 0.5:
		color = color.lerp(ROCK_COLOR, clampf((0.8 - normal.y) * 5.0, 0.0, 1.0))
	if avg_h < WATER_LEVEL:
		color = color.lerp(BED_COLOR, clampf(-avg_h * 0.3, 0.3, 0.8))
	var jitter := 1.0 + (hash01(hx, hz, 7) - 0.5) * 0.07
	var col := Color(color.r * jitter, color.g * jitter, color.b * jitter)
	verts.append_array([a, b, c])
	normals.append_array([normal, normal, normal])
	cols.append_array([col, col, col])


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
	var n := RES + 1
	var fx := clampf(lx / CELL, 0.0, RES - 0.0001)
	var fz := clampf(lz / CELL, 0.0, RES - 0.0001)
	var i := int(fx)
	var j := int(fz)
	var k := j * n + i
	return interp_cell(heights[k], heights[k + 1], heights[k + n], heights[k + n + 1],
		fx - i, fz - j, cell_flip(coord.x * RES + i, coord.y * RES + j))


static func hash01(x: int, y: int, s: int) -> float:
	var h := x * 374761393 + y * 668265263 + s * 982451653
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0
