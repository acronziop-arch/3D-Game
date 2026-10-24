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
const SEABED_COLOR := Color(0.62, 0.6, 0.46)

enum Biome { WATER, BEACH, PLAINS, OAK_FOREST, BIRCH_GROVE, PINE_FOREST, AUTUMN_FOREST, DESERT, TUNDRA, MOUNTAIN, SNOW }

## density — доля мест, где что-то растёт; props — веса объектов.
const BIOMES := {
	Biome.WATER: {"name": "Водоём", "ground": Color(0.74, 0.7, 0.52), "density": 0.0, "props": {}},
	Biome.BEACH: {"name": "Берег", "ground": Color(0.93, 0.86, 0.62), "density": 0.2,
		"props": {"sand": 6.0, "clay": 4.0, "rock": 1.5, "grass": 3.0}},
	Biome.PLAINS: {"name": "Равнины", "ground": Color(0.57, 0.76, 0.34), "density": 0.4,
		"props": {"grass": 40.0, "flowers": 22.0, "bush": 8.0, "tree_oak": 3.0, "tree_birch": 2.0, "rock": 2.5, "clay": 1.0}},
	Biome.OAK_FOREST: {"name": "Дубрава", "ground": Color(0.42, 0.62, 0.27), "density": 0.62,
		"props": {"tree_oak": 48.0, "tree_birch": 5.0, "bush": 14.0, "grass": 16.0, "flowers": 4.0, "rock": 3.0}},
	Biome.BIRCH_GROVE: {"name": "Берёзовая роща", "ground": Color(0.53, 0.73, 0.32), "density": 0.55,
		"props": {"tree_birch": 48.0, "tree_oak": 4.0, "grass": 22.0, "flowers": 12.0, "bush": 6.0, "rock": 2.0}},
	Biome.PINE_FOREST: {"name": "Хвойный лес", "ground": Color(0.33, 0.52, 0.31), "density": 0.62,
		"props": {"tree_pine": 55.0, "rock": 6.0, "bush": 5.0, "grass": 8.0, "ore_coal": 1.5, "ore_iron": 0.8}},
	Biome.AUTUMN_FOREST: {"name": "Осенний лес", "ground": Color(0.64, 0.6, 0.3), "density": 0.58,
		"props": {"tree_maple": 45.0, "tree_birch": 8.0, "tree_oak": 4.0, "bush": 8.0, "grass": 10.0, "rock": 3.0}},
	Biome.DESERT: {"name": "Пустыня", "ground": Color(0.92, 0.79, 0.53), "density": 0.14,
		"props": {"sand": 10.0, "tree_dead": 3.0, "rock": 4.0, "ore_copper": 1.5, "clay": 1.0}},
	Biome.TUNDRA: {"name": "Тундра", "ground": Color(0.87, 0.91, 0.93), "density": 0.25,
		"props": {"tree_snowpine": 20.0, "rock": 6.0, "ore_iron": 1.2, "ore_coal": 1.2}},
	Biome.MOUNTAIN: {"name": "Горы", "ground": Color(0.53, 0.52, 0.5), "density": 0.22,
		"props": {"rock": 22.0, "ore_coal": 6.0, "ore_iron": 5.0, "ore_copper": 4.0, "tree_pine": 4.0}},
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


func _init(seed_value: int) -> void:
	world_seed = seed_value
	_continent = _make_noise(seed_value, 0.0011, 4)
	_hills = _make_noise(seed_value + 1, 0.012, 3)
	_ridges = _make_noise(seed_value + 2, 0.0045, 5, FastNoiseLite.FRACTAL_RIDGED)
	_mountain_mask = _make_noise(seed_value + 3, 0.0011, 3)
	_temperature = _make_noise(seed_value + 4, 0.0008, 3)
	_moisture = _make_noise(seed_value + 5, 0.001, 3)
	_forest = _make_noise(seed_value + 6, 0.018, 2)


static func _make_noise(s: int, frequency: float, octaves: int, fractal := FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n


# --- Рельеф и биомы ------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	var c := _continent.get_noise_2d(x, z)
	# Широкие пологие равнины чуть выше воды, в низинах — озёра и моря.
	var h := 4.0 + c * 22.0
	h += _hills.get_noise_2d(x, z) * (1.5 + clampf(c, 0.0, 1.0) * 6.0)
	var m := smoothstep(0.08, 0.42, _mountain_mask.get_noise_2d(x, z))
	if m > 0.0:
		var r := (_ridges.get_noise_2d(x, z) + 0.6) / 1.6
		h += m * (8.0 + r * r * 70.0)
	return h


func biome_at(x: float, z: float, h: float) -> int:
	if h < WATER_LEVEL - 0.15:
		return Biome.WATER
	var t := _temperature.get_noise_2d(x, z) * 1.6 - maxf(h - 12.0, 0.0) * 0.012
	var m := _moisture.get_noise_2d(x, z) * 1.6
	if h > 46.0:
		return Biome.SNOW
	if h > 26.0:
		return Biome.MOUNTAIN
	if h < WATER_LEVEL + 1.3:
		return Biome.BEACH if t > -0.35 else Biome.TUNDRA
	if t > 0.32 and m < 0.0:
		return Biome.DESERT
	if t < -0.38:
		return Biome.TUNDRA
	if t < -0.12:
		return Biome.PINE_FOREST
	if m < -0.15:
		return Biome.PLAINS
	if m > 0.25:
		return Biome.AUTUMN_FOREST if t > 0.12 else Biome.OAK_FOREST
	return Biome.BIRCH_GROVE if t < 0.08 else Biome.OAK_FOREST


func biome_name(biome: int) -> String:
	return BIOMES[biome]["name"]


## Ищет у начала координат ровное место на равнине или опушке.
func find_spawn() -> Vector3:
	var good := [Biome.PLAINS, Biome.OAK_FOREST, Biome.BIRCH_GROVE, Biome.AUTUMN_FOREST]
	for r in range(0, 4000, 24):
		for k in 12:
			var a := k * TAU / 12.0
			var p := Vector2(cos(a), sin(a)) * r
			var h := height_at(p.x, p.y)
			if h < 2.0 or h > 14.0 or not (biome_at(p.x, p.y, h) in good):
				continue
			var flat := absf(height_at(p.x + 12.0, p.y) - h) + absf(height_at(p.x, p.y + 12.0) - h)
			if flat < 2.0:
				return Vector3(p.x, h, p.y)
	return Vector3(0.0, maxf(height_at(0.0, 0.0), WATER_LEVEL), 0.0)


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
	out["terrain"] = build_terrain(heights, colors, coord).get_arrays()

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
			if h < WATER_LEVEL + 0.25:
				continue
			var biome: int = biomes[roundi(lz / CELL) * n + roundi(lx / CELL)]
			var def: Dictionary = BIOMES[biome]
			var forest := _forest.get_noise_2d(origin.x + lx, origin.y + lz)
			if roll > float(def["density"]) * clampf(0.45 + forest * 1.6, 0.15, 1.4):
				continue
			var prop_id := _pick_weighted(def["props"], pick)
			if prop_id == "":
				continue
			var pdef: Dictionary = GameDataScript.PROPS[prop_id]
			if pdef.has("max_height") and h > float(pdef["max_height"]):
				continue
			if pdef["kind"] == "tree" and _slope(heights, coord, lx, lz) > 0.75:
				continue
			props.append({"id": prop_id, "index": index, "pos": Vector3(lx, h, lz), "rot": rot, "scale": scale})
	out["props"] = props


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

## Строит плоско-затенённый меш рельефа. Диагональ каждой клетки выбирается
## псевдослучайно — сетка не выглядит «по линейке».
static func build_terrain(heights: PackedFloat32Array, colors: PackedColorArray, coord: Vector2i) -> MeshKit:
	var kit := MeshKit.new()
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
				_terrain_face(kit, p00, p10, p01, (colors[k] + colors[k + 1] + colors[k + n]) / 3.0, vx * 2, vz)
				_terrain_face(kit, p10, p11, p01, (colors[k + 1] + colors[k + n + 1] + colors[k + n]) / 3.0, vx * 2 + 1, vz)
			else:
				_terrain_face(kit, p00, p10, p11, (colors[k] + colors[k + 1] + colors[k + n + 1]) / 3.0, vx * 2, vz)
				_terrain_face(kit, p00, p11, p01, (colors[k] + colors[k + n + 1] + colors[k + n]) / 3.0, vx * 2 + 1, vz)
	return kit


static func _terrain_face(kit: MeshKit, a: Vector3, b: Vector3, c: Vector3, color: Color, hx: int, hz: int) -> void:
	var normal := (c - a).cross(b - a).normalized()
	var up := absf(normal.y)
	var avg_h := (a.y + b.y + c.y) / 3.0
	if up < 0.8 and avg_h > WATER_LEVEL + 0.5:
		color = color.lerp(ROCK_COLOR, clampf((0.8 - up) * 5.0, 0.0, 1.0))
	if avg_h < WATER_LEVEL:
		color = color.lerp(SEABED_COLOR, clampf(-avg_h * 0.3, 0.3, 0.8))
	var jitter := 1.0 + (hash01(hx, hz, 7) - 0.5) * 0.07
	kit.add_triangle(a, b, c, Color(color.r * jitter, color.g * jitter, color.b * jitter), Vector3.UP)


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
