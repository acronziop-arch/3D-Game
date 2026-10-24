class_name PropMeshes
extends RefCounted
## Временные low-poly модели объектов мира, собранные из примитивов.
## Когда появятся модели из Blender, достаточно вернуть их меш из get_mesh()
## (например, load("res://models/props/tree_oak.glb")) — остальной код не изменится.

static var _cache := {}


static func get_mesh(id: String) -> Mesh:
	if not _cache.has(id):
		_cache[id] = _build(id)
	return _cache[id]


static func _build(id: String) -> Mesh:
	var k := MeshKit.new()
	match id:
		"tree_oak":
			_trunk(k, 0.32, 2.6, Color(0.42, 0.28, 0.17))
			k.add_primitive(MeshKit.sphere(1.9, 3.0, 7, 4), MeshKit.at(Vector3(0, 3.9, 0)), Color(0.3, 0.55, 0.22))
			k.add_primitive(MeshKit.sphere(1.3, 2.0, 6, 3), MeshKit.at(Vector3(0.9, 4.9, 0.3)), Color(0.36, 0.62, 0.25))
			k.add_primitive(MeshKit.sphere(1.2, 1.8, 6, 3), MeshKit.at(Vector3(-0.8, 4.6, -0.6)), Color(0.27, 0.5, 0.2))
		"tree_birch":
			_trunk(k, 0.17, 3.6, Color(0.92, 0.91, 0.86))
			k.add_primitive(MeshKit.box(Vector3(0.36, 0.12, 0.36)), MeshKit.at(Vector3(0, 1.4, 0), Vector3(0, 30, 0)), Color(0.18, 0.18, 0.18))
			k.add_primitive(MeshKit.sphere(1.2, 3.0, 6, 4), MeshKit.at(Vector3(0, 4.3, 0)), Color(0.56, 0.76, 0.3))
			k.add_primitive(MeshKit.sphere(0.8, 1.8, 6, 3), MeshKit.at(Vector3(0.4, 5.6, 0.2)), Color(0.64, 0.8, 0.34))
		"tree_pine":
			_trunk(k, 0.25, 1.6, Color(0.36, 0.24, 0.15))
			_cones(k, [Color(0.16, 0.38, 0.24), Color(0.18, 0.42, 0.26), Color(0.21, 0.46, 0.28)])
		"tree_snowpine":
			_trunk(k, 0.25, 1.6, Color(0.36, 0.24, 0.15))
			_cones(k, [Color(0.17, 0.36, 0.26), Color(0.9, 0.94, 0.97), Color(0.17, 0.36, 0.26)])
			k.add_primitive(MeshKit.cylinder(0.25, 0.0, 0.7, 7), MeshKit.at(Vector3(0, 6.55, 0)), Color(0.95, 0.97, 1.0))
		"tree_maple":
			_trunk(k, 0.28, 2.4, Color(0.4, 0.27, 0.17))
			k.add_primitive(MeshKit.sphere(1.7, 2.6, 7, 4), MeshKit.at(Vector3(0, 3.6, 0)), Color(0.88, 0.42, 0.14))
			k.add_primitive(MeshKit.sphere(1.2, 1.9, 6, 3), MeshKit.at(Vector3(0.7, 4.6, -0.2)), Color(0.93, 0.62, 0.18))
			k.add_primitive(MeshKit.sphere(1.0, 1.6, 6, 3), MeshKit.at(Vector3(-0.8, 4.3, 0.5)), Color(0.78, 0.26, 0.14))
		"tree_dead":
			var bark := Color(0.45, 0.37, 0.3)
			_trunk(k, 0.22, 3.0, bark)
			k.add_primitive(MeshKit.cylinder(0.1, 0.05, 1.4, 5), MeshKit.at(Vector3(0.45, 2.4, 0), Vector3(0, 0, -45)), bark)
			k.add_primitive(MeshKit.cylinder(0.09, 0.04, 1.1, 5), MeshKit.at(Vector3(-0.35, 2.0, 0.2), Vector3(20, 0, 50)), bark)
		"rock":
			_boulder(k, Color(0.55, 0.55, 0.56))
		"ore_coal":
			_boulder(k, Color(0.5, 0.5, 0.5))
			_crystals(k, Color(0.12, 0.12, 0.13))
		"ore_copper":
			_boulder(k, Color(0.55, 0.53, 0.5))
			_crystals(k, Color(0.9, 0.52, 0.25))
		"ore_iron":
			_boulder(k, Color(0.52, 0.5, 0.5))
			_crystals(k, Color(0.66, 0.38, 0.3))
		"clay":
			k.add_primitive(MeshKit.sphere(1.1, 0.8, 7, 3), MeshKit.at(Vector3(0, 0.15, 0)), Color(0.7, 0.44, 0.3))
			k.add_primitive(MeshKit.sphere(0.6, 0.5, 6, 3), MeshKit.at(Vector3(0.9, 0.1, 0.4)), Color(0.64, 0.4, 0.28))
		"sand":
			k.add_primitive(MeshKit.cylinder(1.2, 0.2, 0.8, 7), MeshKit.at(Vector3(0, 0.35, 0)), Color(0.94, 0.85, 0.6))
		"bush":
			k.add_primitive(MeshKit.sphere(0.7, 0.9, 6, 3), MeshKit.at(Vector3(0, 0.35, 0)), Color(0.3, 0.52, 0.22))
			k.add_primitive(MeshKit.sphere(0.5, 0.7, 6, 3), MeshKit.at(Vector3(0.5, 0.3, 0.3)), Color(0.36, 0.58, 0.25))
		"grass":
			for i in 5:
				var a := i * TAU / 5.0
				var p := Vector3(cos(a), 0, sin(a)) * 0.25
				k.add_primitive(MeshKit.cylinder(0.07, 0.0, 0.5, 3), MeshKit.at(p + Vector3(0, 0.22, 0), Vector3(p.z * 40, 0, -p.x * 40)), Color(0.42, 0.66, 0.26))
		"flowers":
			var heads := [Color(0.95, 0.35, 0.35), Color(0.98, 0.85, 0.3), Color(0.95, 0.95, 0.95), Color(0.7, 0.5, 0.95)]
			for i in 4:
				var a := i * TAU / 4.0 + 0.4
				var p := Vector3(cos(a), 0, sin(a)) * 0.3
				k.add_primitive(MeshKit.cylinder(0.025, 0.025, 0.4, 3), MeshKit.at(p + Vector3(0, 0.2, 0)), Color(0.35, 0.6, 0.25))
				k.add_primitive(MeshKit.sphere(0.09, 0.12, 5, 2), MeshKit.at(p + Vector3(0, 0.42, 0)), heads[i])
		_:
			push_warning("Нет модели для объекта: %s" % id)
			k.add_primitive(MeshKit.box(Vector3.ONE), Transform3D.IDENTITY, Color.MAGENTA)
	return k.build()


## Цвет «осколков» при добыче.
static func burst_color(id: String) -> Color:
	match id:
		"ore_coal":
			return Color(0.15, 0.15, 0.16)
		"ore_copper":
			return Color(0.9, 0.52, 0.25)
		"ore_iron":
			return Color(0.66, 0.4, 0.32)
		"clay":
			return Color(0.7, 0.44, 0.3)
		"sand":
			return Color(0.94, 0.85, 0.6)
	return Color(0.55, 0.55, 0.56)


static func _trunk(k: MeshKit, radius: float, height: float, color: Color) -> void:
	k.add_primitive(MeshKit.cylinder(radius, radius * 0.7, height, 6), MeshKit.at(Vector3(0, height * 0.5, 0)), color)


static func _cones(k: MeshKit, colors: Array) -> void:
	var y := 1.6
	var r := 1.9
	for c: Color in colors:
		k.add_primitive(MeshKit.cylinder(r, 0.0, 2.6, 7), MeshKit.at(Vector3(0, y + 1.0, 0)), c)
		y += 1.45
		r *= 0.74


static func _boulder(k: MeshKit, color: Color) -> void:
	k.add_primitive(MeshKit.sphere(1.0, 1.5, 6, 3), MeshKit.at(Vector3(0, 0.5, 0), Vector3(0, 0, 8), Vector3(1.2, 1.0, 1.0)), color)
	k.add_primitive(MeshKit.sphere(0.6, 0.9, 5, 3), MeshKit.at(Vector3(0.9, 0.25, 0.5)), color.darkened(0.08))


static func _crystals(k: MeshKit, color: Color) -> void:
	var spots := [Vector3(0.3, 1.0, 0.5), Vector3(-0.5, 0.8, 0.4), Vector3(0.6, 0.7, -0.5), Vector3(-0.2, 1.1, -0.4), Vector3(1.0, 0.45, 0.6)]
	for i in spots.size():
		var rot := Vector3(25.0 * (i % 3 - 1), i * 50.0, 20.0 * ((i + 1) % 3 - 1))
		k.add_primitive(MeshKit.box(Vector3(0.28, 0.32, 0.28)), MeshKit.at(spots[i], rot), color)
