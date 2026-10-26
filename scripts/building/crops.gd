class_name CropPatch
extends Node3D
## Посадки на грядке или в огороде (только украшение). Растения стоят рядами
## в прямоугольниках гряд и растут несколько минут от ростков до урожая.
## Рис растёт в воде: гряда под ним залита.

const CROPS := {
	"wheat": {"name": "Пшеница", "icon": "crop_wheat", "step": 0.24},
	"rice": {"name": "Рис", "icon": "crop_rice", "step": 0.3},
	"cabbage": {"name": "Капуста", "icon": "crop_cabbage", "step": 0.46},
	"carrot": {"name": "Морковь", "icon": "crop_carrot", "step": 0.24},
	"pumpkin": {"name": "Тыква", "icon": "crop_pumpkin", "step": 0.8},
	"sunflower": {"name": "Подсолнух", "icon": "crop_sunflower", "step": 0.5},
}
const ORDER := ["wheat", "rice", "cabbage", "carrot", "pumpkin", "sunflower"]
## Секунд от посадки до спелого урожая.
const GROW_TIME := 240.0

static var _meshes := {}
static var _water_mat: StandardMaterial3D

var crop := "wheat"
## Время посадки (unix).
var planted := 0.0

var _mm: MultiMesh
var _base: Array[Transform3D] = []
var _timer := 0.0
var _done := false


static func next_crop(current: String) -> String:
	return ORDER[(ORDER.find(current) + 1) % ORDER.size()]


## rects — гряды в локальных координатах здания, top — высота земли гряды.
func setup(crop_id: String, planted_time: float, rects: Array, top: float) -> void:
	crop = crop_id if CROPS.has(crop_id) else "wheat"
	planted = planted_time
	for c in get_children():
		c.queue_free()
	_base.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([crop, rects.size()])
	var step: float = CROPS[crop]["step"]
	for r: Rect2 in rects:
		var nx := maxi(1, floori(r.size.x / step))
		var nz := maxi(1, floori(r.size.y / step))
		for j in nz:
			for i in nx:
				var p := Vector3(r.position.x + (i + 0.5) * r.size.x / nx + rng.randf_range(-0.04, 0.04), top,
					r.position.y + (j + 0.5) * r.size.y / nz + rng.randf_range(-0.04, 0.04))
				var s := rng.randf_range(0.85, 1.12)
				_base.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
		if crop == "rice":
			var water := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = r.size
			water.mesh = plane
			water.position = Vector3(r.get_center().x, top + 0.05, r.get_center().y)
			water.material_override = _rice_water()
			water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(water)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = plant_mesh(crop)
	_mm.instance_count = _base.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = ModelLibrary.foliage_material()
	add_child(mmi)
	_done = false
	_apply_growth()


func growth() -> float:
	return clampf((Time.get_unix_time_from_system() - planted) / GROW_TIME, 0.0, 1.0)


func _apply_growth() -> void:
	var g := growth()
	var k := lerpf(0.18, 1.0, smoothstep(0.0, 1.0, g))
	for i in _base.size():
		var t := _base[i]
		_mm.set_instance_transform(i, Transform3D(t.basis.scaled(Vector3(k, k, k)), t.origin))
	_done = g >= 1.0


func _process(delta: float) -> void:
	if _done or _mm == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	_apply_growth()


static func _rice_water() -> StandardMaterial3D:
	if _water_mat == null:
		_water_mat = StandardMaterial3D.new()
		_water_mat.albedo_color = Color(0.36, 0.5, 0.52, 0.82)
		_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_mat.roughness = 0.05
		_water_mat.metallic_specular = 0.8
	return _water_mat


## Модель одного растения (общая на все гряды с этой культурой).
static func plant_mesh(id: String) -> Mesh:
	if _meshes.has(id):
		return _meshes[id]
	var g := Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var m := PropFactory.MAT
	match id:
		"wheat":
			g.sway_height = 0.9
			g.kind = Geo.KIND_PLANT
			for i in 6:
				var a := rng.randf() * TAU
				var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.06)
				var tip := base + Vector3(cos(a) * 0.08, rng.randf_range(0.75, 0.95), sin(a) * 0.08)
				g.rod(m, base, tip, 0.012, 0.008, 4, Color(0.66, 0.66, 0.3))
				g.blob(m, tip + Vector3(0, 0.07, 0), Vector3(0.025, 0.09, 0.025), Color(0.9, 0.76, 0.38), rng, 0, 0.2, 0.1)
		"rice":
			g.sway_height = 0.7
			g.kind = Geo.KIND_PLANT
			for i in 7:
				var a := TAU * i / 7.0 + rng.randf_range(-0.2, 0.2)
				var out := Vector3(cos(a), 0, sin(a))
				var mid := out * 0.1 + Vector3(0, 0.4, 0)
				var tip := out * 0.24 + Vector3(0, rng.randf_range(0.55, 0.7), 0)
				g.rod(m, Vector3.ZERO, mid, 0.014, 0.011, 4, Color(0.38, 0.62, 0.26))
				g.rod(m, mid, tip, 0.011, 0.004, 4, Color(0.45, 0.7, 0.3))
				if i % 2 == 0:
					g.blob(m, tip - Vector3(0, 0.08, 0), Vector3(0.02, 0.07, 0.02), Color(0.86, 0.82, 0.5), rng, 0, 0.2, 0.1)
		"cabbage":
			g.sway_height = 0.5
			g.blob(m, Vector3(0, 0.17, 0), Vector3(0.15, 0.14, 0.15), Color(0.72, 0.86, 0.52), rng, 1, 0.12, 0.2)
			g.kind = Geo.KIND_PLANT
			for i in 6:
				var a := TAU * i / 6.0
				g.blob(m, Vector3(cos(a) * 0.15, 0.1, sin(a) * 0.15), Vector3(0.13, 0.04, 0.1), Color(0.44, 0.66, 0.34), rng, 0, 0.2, 0.15)
		"carrot":
			g.sway_height = 0.4
			g.cylinder(m, Vector3(0, -0.02, 0), 0.035, 0.03, 0.06, 6, Color(0.95, 0.5, 0.16))
			g.kind = Geo.KIND_PLANT
			for i in 7:
				var a := TAU * i / 7.0
				var tip := Vector3(cos(a) * 0.12, rng.randf_range(0.25, 0.36), sin(a) * 0.12)
				g.rod(m, Vector3(0, 0.03, 0), tip, 0.008, 0.004, 3, Color(0.36, 0.62, 0.24))
				g.blob(m, tip, Vector3(0.04, 0.03, 0.04), Color(0.4, 0.68, 0.28), rng, 0, 0.3, 0.1)
		"pumpkin":
			g.sway_height = 0.6
			var orange := Color(0.95, 0.52, 0.14)
			for k in 8:
				var a := TAU * k / 8.0
				g.blob(m, Vector3(cos(a) * 0.12, 0.18, sin(a) * 0.12), Vector3(0.13, 0.17, 0.13), orange.darkened(0.06 * (k % 2)), rng, 1, 0.05, 0.25)
			g.cylinder(m, Vector3(0, 0.32, 0), 0.03, 0.02, 0.1, 5, Color(0.42, 0.5, 0.2))
			g.kind = Geo.KIND_PLANT
			for i in 4:
				var a := TAU * i / 4.0 + 0.4
				g.blob(m, Vector3(cos(a) * 0.36, 0.05, sin(a) * 0.36), Vector3(0.17, 0.03, 0.15), Color(0.34, 0.56, 0.24), rng, 0, 0.25, 0.15)
		"sunflower":
			g.sway_height = 1.7
			g.kind = Geo.KIND_PLANT
			g.rod(m, Vector3.ZERO, Vector3(0.04, 1.55, 0.02), 0.03, 0.022, 5, Color(0.4, 0.58, 0.24))
			for i in 4:
				var a := TAU * i / 4.0 + 0.5
				var y := 0.4 + i * 0.28
				g.blob(m, Vector3(cos(a) * 0.14, y, sin(a) * 0.14), Vector3(0.14, 0.03, 0.1), Color(0.38, 0.62, 0.26), rng, 0, 0.2, 0.15)
			g.kind = Geo.KIND_SOLID
			var head := Vector3(0.05, 1.62, 0.1)
			var facing := Basis(Vector3.RIGHT, deg_to_rad(65.0))
			g.cylinder(m, head, 0.13, 0.12, 0.05, 10, Color(0.36, 0.22, 0.12), true, true, 0.0, facing)
			for k in 12:
				var a := TAU * k / 12.0
				var petal := facing * Vector3(cos(a) * 0.19, 0.03, sin(a) * 0.19)
				g.blob(m, head + petal, (facing * Vector3(0.07, 0.015, 0.035)).abs() + Vector3.ONE * 0.012, Color(0.98, 0.78, 0.16), rng, 0, 0.1, 0.05)
	var mesh := g.build_mesh()
	_meshes[id] = mesh
	return mesh
