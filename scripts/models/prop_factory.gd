class_name PropFactory
extends RefCounted
## Генераторы моделей природы: деревья, кусты, трава, камни, руды, рыбы.
## Используются инструментом tools/export_models.gd, который сохраняет их в models/*.glb.
## Каждое дерево строится из ствола, веток и отдельных «кучек» листвы — у каждой
## кучки своё зерно (UV2.y), поэтому осенью листва облетает постепенно.

const MAT := "nature"

## Сколько вариантов модели у каждого объекта.
const VARIANTS := {
	"tree_oak": 2, "tree_birch": 2, "tree_pine": 2, "tree_spruce": 2, "tree_snowpine": 2,
	"tree_maple": 2, "tree_dead": 2, "bush": 3, "grass": 2, "flowers": 2, "reeds": 2, "lily": 2,
	"rock": 3, "ore_coal": 2, "ore_copper": 2, "ore_iron": 2, "clay": 2, "sand": 2,
}

const FISH := ["perch", "carp", "trout", "koi", "pike"]


static func build(id: String, variant: int) -> ArrayMesh:
	var g := Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([id, variant])
	match id:
		"tree_oak":
			_broadleaf(g, rng, 3.0, 0.42, 5, Color(0.36, 0.26, 0.18), Color(0.28, 0.5, 0.18), Vector3(1.5, 1.1, 1.5), 4)
		"tree_maple":
			_broadleaf(g, rng, 2.6, 0.34, 6, Color(0.4, 0.29, 0.2), Color(0.44, 0.6, 0.2), Vector3(1.25, 1.05, 1.25), 5)
		"tree_birch":
			_birch(g, rng)
		"tree_pine":
			_pine(g, rng)
		"tree_spruce":
			_spruce(g, rng, false)
		"tree_snowpine":
			_spruce(g, rng, true)
		"tree_dead":
			_dead(g, rng)
		"bush":
			_bush(g, rng, variant == 2)
		"grass":
			_grass(g, rng)
		"flowers":
			_flowers(g, rng)
		"reeds":
			_reeds(g, rng)
		"lily":
			_lily(g, rng, variant == 1)
		"rock":
			_rock(g, rng, Color(0.53, 0.53, 0.54))
		"ore_coal":
			_rock(g, rng, Color(0.5, 0.5, 0.5))
			_crystals(g, rng, Color(0.13, 0.13, 0.15), 0.08)
		"ore_copper":
			_rock(g, rng, Color(0.56, 0.53, 0.5))
			_crystals(g, rng, Color(0.92, 0.5, 0.22), 0.12)
		"ore_iron":
			_rock(g, rng, Color(0.52, 0.5, 0.5))
			_crystals(g, rng, Color(0.62, 0.32, 0.26), 0.1)
		"clay":
			_clay(g, rng)
		"sand":
			_sand(g, rng)
		_:
			push_warning("Нет генератора для %s" % id)
			g.box(MAT, Vector3(0, 0.5, 0), Vector3.ONE, Color.MAGENTA)
	return g.build_mesh()


# --- Деревья ------------------------------------------------------------------------------

static func _trunk(g: Geo, rng: RandomNumberGenerator, height: float, radius: float, color: Color, segments := 3) -> Array[Vector3]:
	var points: Array[Vector3] = [Vector3.ZERO]
	var p := Vector3.ZERO
	for i in segments:
		p += Vector3(rng.randf_range(-0.18, 0.18), height / segments, rng.randf_range(-0.18, 0.18))
		points.append(p)
	g.kind = Geo.KIND_SOLID
	for i in segments:
		var r0 := radius * (1.0 - 0.55 * float(i) / segments)
		var r1 := radius * (1.0 - 0.55 * float(i + 1) / segments)
		g.rod(MAT, points[i], points[i + 1], r0, r1, 7, color.lightened(rng.randf_range(-0.04, 0.04)))
	# Корни у основания.
	for i in 4:
		var a := i * TAU / 4.0 + rng.randf() * 0.6
		var out := Vector3(cos(a), 0, sin(a))
		g.rod(MAT, Vector3(0, radius * 1.4, 0), out * radius * 2.2 + Vector3(0, -0.1, 0), radius * 0.45, 0.04, 5, color.darkened(0.08), false)
	return points


static func _leaf_cluster(g: Geo, rng: RandomNumberGenerator, center: Vector3, radii: Vector3, color: Color, kind := Geo.KIND_LEAF) -> void:
	g.kind = kind
	g.seed_value = rng.randf()
	var tint := color.lightened(rng.randf_range(-0.08, 0.1))
	g.blob(MAT, center, radii, tint, rng, 1, 0.2, 0.32, 0.06)
	g.kind = Geo.KIND_SOLID


static func _broadleaf(g: Geo, rng: RandomNumberGenerator, trunk_h: float, radius: float, branches: int,
		bark: Color, leaves: Color, cluster: Vector3, top_clusters: int) -> void:
	var total := trunk_h + cluster.y * 2.6
	g.sway_height = total
	var pts := _trunk(g, rng, trunk_h, radius, bark)
	var top := pts[pts.size() - 1]
	var tips: Array[Vector3] = []
	for i in branches:
		var a := i * TAU / branches + rng.randf_range(-0.3, 0.3)
		var start := top.lerp(pts[pts.size() - 2], rng.randf_range(0.0, 0.6))
		var up := rng.randf_range(0.55, 1.0)
		var length := rng.randf_range(1.3, 2.1)
		var tip := start + Vector3(cos(a), up, sin(a)).normalized() * length
		g.rod(MAT, start, tip, radius * 0.4, radius * 0.12, 5, bark)
		tips.append(tip)
	for tip in tips:
		_leaf_cluster(g, rng, tip + Vector3(0, 0.3, 0), cluster * rng.randf_range(0.85, 1.15), leaves)
	for i in top_clusters:
		var a := rng.randf() * TAU
		var c := top + Vector3(cos(a) * rng.randf_range(0.0, 0.9), rng.randf_range(1.0, 2.0), sin(a) * rng.randf_range(0.0, 0.9))
		_leaf_cluster(g, rng, c, cluster * rng.randf_range(0.9, 1.2), leaves)


static func _birch(g: Geo, rng: RandomNumberGenerator) -> void:
	var height := 5.4
	g.sway_height = height + 1.5
	# Белый ствол с чёрными чёрточками: красим каждую грань отдельно.
	var segs := 12
	var p := Vector3.ZERO
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
	for i in segs:
		var y0 := height * i / segs
		var y1 := height * (i + 1) / segs
		var c0 := lean * pow(y0 / height, 2.0)
		var c1 := lean * pow(y1 / height, 2.0)
		var r0 := 0.17 * (1.0 - 0.5 * y0 / height)
		var r1 := 0.17 * (1.0 - 0.5 * y1 / height)
		for k in 6:
			var a0 := TAU * k / 6.0
			var a1 := TAU * (k + 1) / 6.0
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var white := Color(0.9, 0.89, 0.84).darkened(rng.randf_range(0.0, 0.06))
			var col := Color(0.16, 0.15, 0.14) if rng.randf() < 0.16 else white
			g.quad(MAT, c0 + d0 * r0 + Vector3(0, y0, 0), c0 + d1 * r0 + Vector3(0, y0, 0),
				c1 + d1 * r1 + Vector3(0, y1, 0), c1 + d0 * r1 + Vector3(0, y1, 0), col, (d0 + d1))
	var top := lean + Vector3(0, height, 0)
	# Узкая высокая крона из повисших кучек листвы вдоль верхних двух третей ствола.
	for i in 9:
		var y := lerpf(2.2, height - 0.2, float(i) / 8.0) + rng.randf_range(-0.2, 0.2)
		var base := lean * pow(y / height, 2.0) + Vector3(0, y, 0)
		var a := i * 2.4 + rng.randf_range(-0.3, 0.3)
		var reach := lerpf(1.0, 0.45, float(i) / 8.0)
		var tip := base + Vector3(cos(a) * reach, rng.randf_range(0.2, 0.6), sin(a) * reach)
		g.rod(MAT, base, tip, 0.05, 0.02, 4, Color(0.3, 0.27, 0.24))
		_leaf_cluster(g, rng, tip + Vector3(0, -0.15, 0), Vector3(0.7, 0.95, 0.7) * rng.randf_range(0.85, 1.15) * lerpf(1.1, 0.75, float(i) / 8.0),
			Color(0.5, 0.7, 0.27))
	_leaf_cluster(g, rng, top + Vector3(0, 0.4, 0), Vector3(0.55, 0.9, 0.55), Color(0.54, 0.74, 0.29))


static func _pine(g: Geo, rng: RandomNumberGenerator) -> void:
	var height := 6.2
	g.sway_height = height + 1.6
	var pts := _trunk(g, rng, height, 0.27, Color(0.5, 0.3, 0.18), 4)
	var top := pts[pts.size() - 1]
	var needles := Color(0.19, 0.36, 0.22)
	# Крона-«зонтик»: ярусы плоских хвойных подушек на коротких ветках.
	for i in 8:
		var t := float(i) / 7.0
		var y := lerpf(height * 0.55, height + 0.3, t)
		var a := i * 2.3 + rng.randf_range(-0.3, 0.3)
		var base := Vector3(top.x * y / height, minf(y, height), top.z * y / height)
		var reach := lerpf(1.6, 0.4, t)
		var tip := base + Vector3(cos(a) * reach, rng.randf_range(0.1, 0.4), sin(a) * reach)
		g.rod(MAT, base, tip, 0.09, 0.04, 4, Color(0.42, 0.26, 0.16))
		_leaf_cluster(g, rng, tip + Vector3(0, 0.15, 0), Vector3(1.15, 0.5, 1.15) * lerpf(1.1, 0.75, t) * rng.randf_range(0.85, 1.1),
			needles.lightened(t * 0.06), Geo.KIND_NEEDLE)
	_leaf_cluster(g, rng, top + Vector3(0, 0.7, 0), Vector3(0.8, 0.55, 0.8), needles.lightened(0.06), Geo.KIND_NEEDLE)


static func _spruce(g: Geo, rng: RandomNumberGenerator, snowy: bool) -> void:
	var height := rng.randf_range(6.5, 7.5)
	g.sway_height = height
	g.kind = Geo.KIND_SOLID
	g.rod(MAT, Vector3.ZERO, Vector3(0, height * 0.9, 0), 0.26, 0.06, 6, Color(0.36, 0.24, 0.16))
	var layers := 6
	for i in layers:
		var t := float(i) / layers
		var y := 1.0 + t * (height - 1.6)
		var radius := lerpf(2.0, 0.55, t) * rng.randf_range(0.92, 1.08)
		var h := lerpf(1.8, 1.2, t)
		_skirt(g, rng, Vector3(0, y, 0), radius, h, Color(0.16, 0.34, 0.24).lightened(t * 0.08), snowy)
	g.kind = Geo.KIND_NEEDLE
	g.seed_value = rng.randf()
	g.cylinder(MAT, Vector3(0, height - 0.6, 0), 0.4, 0.0, 1.0, 6, Color(0.2, 0.4, 0.27))
	g.kind = Geo.KIND_SOLID


## «Юбка» ели: конус с рваным, свисающим нижним краем.
static func _skirt(g: Geo, rng: RandomNumberGenerator, base: Vector3, radius: float, height: float, color: Color, snowy: bool) -> void:
	g.kind = Geo.KIND_NEEDLE
	g.seed_value = rng.randf()
	var n := 9
	var ring: Array[Vector3] = []
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.12, 0.12)
		var r := radius * rng.randf_range(0.85, 1.12)
		ring.append(base + Vector3(cos(a) * r, rng.randf_range(-0.35, 0.0), sin(a) * r))
	var apex := base + Vector3(0, height, 0)
	var inner := base + Vector3(0, height * 0.25, 0)
	g.begin()
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var out := ((a + b) * 0.5 - base)
		var top_col := color.lightened(rng.randf_range(-0.05, 0.08))
		if snowy and rng.randf() < 0.55:
			top_col = Color(0.93, 0.95, 0.98).darkened(rng.randf_range(0.0, 0.05))
		g.tri(MAT, a, b, apex, top_col, out + Vector3(0, radius, 0))
		g.tri(MAT, a, b, inner, color.darkened(0.35), -out + Vector3(0, -radius, 0))
	g.end()
	g.kind = Geo.KIND_SOLID


static func _dead(g: Geo, rng: RandomNumberGenerator) -> void:
	g.sway_height = 5.0
	var bark := Color(0.46, 0.39, 0.33)
	var pts := _trunk(g, rng, 3.6, 0.24, bark, 4)
	for i in 5:
		var base := pts[rng.randi_range(2, pts.size() - 1)]
		var a := rng.randf() * TAU
		var tip := base + Vector3(cos(a) * 1.2, rng.randf_range(0.3, 1.0), sin(a) * 1.2)
		g.rod(MAT, base, tip, 0.09, 0.02, 4, bark)
		var a2 := a + rng.randf_range(-1.0, 1.0)
		g.rod(MAT, tip, tip + Vector3(cos(a2) * 0.6, 0.5, sin(a2) * 0.6), 0.04, 0.01, 3, bark)


# --- Кусты и травы ---------------------------------------------------------------------------

static func _bush(g: Geo, rng: RandomNumberGenerator, berries: bool) -> void:
	g.sway_height = 1.4
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var c := Vector3(cos(a) * rng.randf_range(0.0, 0.6), rng.randf_range(0.35, 0.6), sin(a) * rng.randf_range(0.0, 0.6))
		_leaf_cluster(g, rng, c, Vector3(0.6, 0.48, 0.6) * rng.randf_range(0.8, 1.2), Color(0.27, 0.48, 0.2))
	if berries:
		for i in 9:
			var a := rng.randf() * TAU
			var c := Vector3(cos(a) * 0.7, rng.randf_range(0.4, 0.9), sin(a) * 0.7)
			g.kind = Geo.KIND_LEAF
			g.seed_value = rng.randf()
			g.blob(MAT, c, Vector3.ONE * 0.08, Color(0.78, 0.12, 0.15), rng, 0, 0.05, 0.2)
	g.kind = Geo.KIND_SOLID


static func _grass(g: Geo, rng: RandomNumberGenerator) -> void:
	g.sway_height = 0.7
	g.kind = Geo.KIND_PLANT
	for i in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.35)
		var base := Vector3(cos(a) * r, 0, sin(a) * r)
		var tip := base + Vector3(cos(a) * 0.15, rng.randf_range(0.4, 0.7), sin(a) * 0.15)
		g.rod(MAT, base, tip, 0.05, 0.0, 3, Color(0.4, 0.62, 0.24).lightened(rng.randf_range(-0.1, 0.1)), false)
	g.kind = Geo.KIND_SOLID


static func _flowers(g: Geo, rng: RandomNumberGenerator) -> void:
	g.sway_height = 0.6
	var palette := [Color(0.95, 0.32, 0.35), Color(0.98, 0.84, 0.28), Color(0.96, 0.96, 0.96), Color(0.66, 0.48, 0.95), Color(0.98, 0.55, 0.75)]
	for i in 5:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.4)
		var h := rng.randf_range(0.3, 0.5)
		g.kind = Geo.KIND_PLANT
		g.rod(MAT, base, base + Vector3(0, h, 0), 0.025, 0.02, 3, Color(0.33, 0.56, 0.22), false)
		g.kind = Geo.KIND_LEAF
		g.seed_value = rng.randf()
		var head := base + Vector3(0, h + 0.04, 0)
		g.blob(MAT, head, Vector3(0.11, 0.05, 0.11), palette[rng.randi() % palette.size()], rng, 0, 0.08, 0.1)
		g.blob(MAT, head + Vector3(0, 0.03, 0), Vector3(0.04, 0.03, 0.04), Color(0.98, 0.8, 0.2), rng, 0, 0.0, 0.0)
	g.kind = Geo.KIND_SOLID


static func _reeds(g: Geo, rng: RandomNumberGenerator) -> void:
	g.sway_height = 2.0
	g.kind = Geo.KIND_PLANT
	for i in 8:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.45) + Vector3(0, -0.6, 0)
		var tip := base + Vector3(cos(a) * 0.2, rng.randf_range(1.6, 2.3), sin(a) * 0.2)
		g.rod(MAT, base, tip, 0.04, 0.0, 3, Color(0.42, 0.56, 0.26).lightened(rng.randf_range(-0.08, 0.08)), false)
		if i < 3:
			g.rod(MAT, tip.lerp(base, 0.28), tip.lerp(base, 0.12), 0.07, 0.07, 5, Color(0.42, 0.27, 0.16))
	g.kind = Geo.KIND_SOLID


static func _lily(g: Geo, rng: RandomNumberGenerator, flower: bool) -> void:
	g.kind = Geo.KIND_PLANT
	for i in 3:
		var a := rng.randf() * TAU
		var c := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.2, 0.7)
		var r := rng.randf_range(0.28, 0.42)
		var notch := rng.randf() * TAU
		g.begin()
		for k in 10:
			var a0 := notch + 0.4 + (TAU - 0.5) * k / 10.0
			var a1 := notch + 0.4 + (TAU - 0.5) * (k + 1) / 10.0
			g.tri(MAT, c + Vector3(0, 0.02, 0), c + Vector3(cos(a0) * r, 0.02, sin(a0) * r), c + Vector3(cos(a1) * r, 0.02, sin(a1) * r),
				Color(0.28, 0.52, 0.22).lightened(rng.randf_range(-0.05, 0.08)), Vector3.UP)
		g.end()
	if flower:
		g.kind = Geo.KIND_LEAF
		g.seed_value = rng.randf()
		g.blob(MAT, Vector3(0.1, 0.1, 0.1), Vector3(0.14, 0.08, 0.14), Color(0.98, 0.72, 0.82), rng, 1, 0.2, 0.1)
		g.blob(MAT, Vector3(0.1, 0.15, 0.1), Vector3(0.05, 0.04, 0.05), Color(1.0, 0.85, 0.3), rng, 0, 0.0, 0.0)
	g.kind = Geo.KIND_SOLID


# --- Камни и залежи ------------------------------------------------------------------------------

static func _rock(g: Geo, rng: RandomNumberGenerator, color: Color) -> void:
	g.blob(MAT, Vector3(0, 0.45, 0), Vector3(1.15, 0.8, 0.95) * rng.randf_range(0.9, 1.1), color, rng, 1, 0.22, 0.35, 0.08)
	g.blob(MAT, Vector3(0.95, 0.2, 0.4), Vector3(0.55, 0.42, 0.5), color.darkened(0.06), rng, 1, 0.2, 0.35, 0.08)
	if rng.randf() < 0.6:
		g.blob(MAT, Vector3(-0.7, 0.12, -0.6), Vector3(0.35, 0.25, 0.3), color.lightened(0.04), rng, 0, 0.15, 0.3)


static func _crystals(g: Geo, rng: RandomNumberGenerator, color: Color, glow: float) -> void:
	for i in 6:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a) * rng.randf_range(0.3, 0.75), rng.randf_range(0.5, 0.95), sin(a) * rng.randf_range(0.3, 0.6))
		var dir := (base - Vector3(0, 0.2, 0)).normalized()
		var length := rng.randf_range(0.35, 0.6)
		var c := color.lightened(rng.randf_range(-0.05, glow))
		g.rod(MAT, base - dir * 0.15, base + dir * length * 0.6, 0.1, 0.1, 5, c, false)
		g.rod(MAT, base + dir * length * 0.6, base + dir * length, 0.1, 0.0, 5, c.lightened(0.1), false)


static func _clay(g: Geo, rng: RandomNumberGenerator) -> void:
	var col := Color(0.7, 0.44, 0.31)
	for i in 3:
		var a := rng.randf() * TAU
		var c := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.7) + Vector3(0, 0.1, 0)
		g.blob(MAT, c, Vector3(0.75, 0.4, 0.7) * rng.randf_range(0.7, 1.1), col.lightened(rng.randf_range(-0.06, 0.06)), rng, 1, 0.18, 0.3)


static func _sand(g: Geo, rng: RandomNumberGenerator) -> void:
	g.blob(MAT, Vector3(0, 0.05, 0), Vector3(1.3, 0.55, 1.2), Color(0.93, 0.84, 0.6), rng, 1, 0.12, 0.25, 0.04)
	for i in 4:
		var a := rng.randf() * TAU
		g.blob(MAT, Vector3(cos(a) * 1.3, 0.05, sin(a) * 1.3), Vector3.ONE * 0.12, Color(0.62, 0.6, 0.56), rng, 0, 0.1, 0.2)


# --- Рыбы ------------------------------------------------------------------------------------------

## Рыба вдоль оси +Z (голова спереди). Хвост машет в шейдере fish.gdshader.
static func build_fish(species: String) -> ArrayMesh:
	var g := Geo.new()
	g.with_uv2 = false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(species)
	var radii := Vector3(0.08, 0.13, 0.3)
	var fin := Color(0.85, 0.35, 0.2)
	var body: Callable
	match species:
		"perch":
			fin = Color(0.9, 0.38, 0.18)
			body = func(p: Vector3) -> Color:
				var base := Color(0.5, 0.58, 0.28) if p.y > -0.02 else Color(0.85, 0.82, 0.62)
				return base.darkened(0.45) if fmod(p.z + 1.0, 0.14) < 0.05 and p.y > -0.03 else base
		"carp":
			radii = Vector3(0.09, 0.15, 0.28)
			fin = Color(0.72, 0.5, 0.25)
			body = func(p: Vector3) -> Color:
				return Color(0.8, 0.62, 0.3) if p.y > -0.03 else Color(0.92, 0.82, 0.55)
		"trout":
			radii = Vector3(0.07, 0.11, 0.34)
			fin = Color(0.62, 0.6, 0.58)
			body = func(p: Vector3) -> Color:
				if absf(p.y) < 0.025:
					return Color(0.9, 0.48, 0.55)
				var c := Color(0.55, 0.62, 0.62) if p.y > 0.0 else Color(0.9, 0.9, 0.88)
				return c.darkened(0.5) if fmod(absf(p.x * 37.0 + p.z * 23.0), 1.0) < 0.12 and p.y > 0.0 else c
		"koi":
			radii = Vector3(0.08, 0.12, 0.32)
			fin = Color(0.98, 0.95, 0.92)
			body = func(p: Vector3) -> Color:
				var spot := sin(p.z * 22.0) + sin(p.x * 30.0 + p.y * 12.0)
				return Color(0.98, 0.45, 0.12) if spot > 0.3 else Color(0.98, 0.96, 0.93)
		"pike":
			radii = Vector3(0.06, 0.08, 0.5)
			fin = Color(0.5, 0.52, 0.3)
			body = func(p: Vector3) -> Color:
				var c := Color(0.36, 0.46, 0.26) if p.y > -0.02 else Color(0.85, 0.85, 0.7)
				return c.lightened(0.35) if fmod(absf(p.x * 41.0 + p.z * 17.0), 1.0) < 0.15 and p.y > -0.02 else c
	# Тело: икосфера, раскрашенная по точкам поверхности.
	var ico := Geo._icosphere(2)
	g.begin()
	for f in ico["f"]:
		var pts: Array[Vector3] = []
		for idx: int in f:
			var v: Vector3 = ico["v"][idx]
			var p := Vector3(v.x * radii.x, v.y * radii.y, v.z * radii.z)
			# Голова чуть тупее, к хвосту тело сужается.
			if p.z < 0.0:
				var k := 1.0 + p.z / radii.z * 0.55
				p.x *= k
				p.y *= k
			pts.append(p)
		var center := (pts[0] + pts[1] + pts[2]) / 3.0
		g.tri("fish", pts[0], pts[1], pts[2], body.call(center), center)
	g.end()
	# Хвост, спинной и брюшные плавники — двусторонние треугольники.
	var tail_root := Vector3(0, 0, -radii.z * 0.92)
	var tail_top := Vector3(0, radii.y * 1.2, -radii.z * 1.45)
	var tail_bottom := Vector3(0, -radii.y * 1.1, -radii.z * 1.4)
	var tail_mid := Vector3(0, 0, -radii.z * 1.2)
	for s: float in [-1.0, 1.0]:
		g.tri("fish", tail_root, tail_top, tail_mid, fin, Vector3(s, 0, 0))
		g.tri("fish", tail_root, tail_mid, tail_bottom, fin.darkened(0.1), Vector3(s, 0, 0))
		g.tri("fish", Vector3(0, radii.y * 0.85, radii.z * 0.25), Vector3(0, radii.y * 1.45, -radii.z * 0.1),
			Vector3(0, radii.y * 0.75, -radii.z * 0.45), fin, Vector3(s, 0, 0))
		g.tri("fish", Vector3(radii.x * 0.8 * s, -radii.y * 0.4, radii.z * 0.35), Vector3(radii.x * 1.6 * s, -radii.y * 0.9, radii.z * 0.05),
			Vector3(radii.x * 0.8 * s, -radii.y * 0.5, radii.z * 0.1), fin, Vector3(0, -1, 0))
		g.blob("fish", Vector3(radii.x * 0.62 * s, radii.y * 0.25, radii.z * 0.72), Vector3.ONE * 0.022, Color(0.05, 0.05, 0.06), rng, 0, 0.0, 0.0)
	return g.build_mesh()
