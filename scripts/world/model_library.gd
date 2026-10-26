class_name ModelLibrary
extends RefCounted
## Загружает модели из models/*.glb и раздаёт общие материалы.
## Если файла нет (например, модель ещё не экспортирована), модель генерируется
## на лету тем же кодом, что и в tools/export_models.gd.

const BUILDING_MATERIALS := {
	"glass": {"roughness_base": 0.06, "specular_base": 0.8, "porosity": 0.0, "glass": 1.0,
		"emission_color": Color(1.0, 0.72, 0.38), "emission_night": 1.8},
	"opening": {"roughness_base": 0.95, "specular_base": 0.1, "porosity": 0.0,
		"emission_color": Color(1.0, 0.66, 0.32), "emission_night": 0.9},
	"wax": {"roughness_base": 0.6, "emission_color": Color(1.0, 0.78, 0.45), "emission_day": 0.35, "emission_night": 2.4},
	"iron": {"roughness_base": 0.42, "metallic_base": 0.6, "porosity": 0.3},
	"copper": {"roughness_base": 0.45, "metallic_base": 0.4, "porosity": 0.3},
	"cloth": {"roughness_base": 0.95, "flutter": 1.0},
	"leather": {"roughness_base": 0.8, "flutter": 0.4},
	"slate": {"roughness_base": 0.7},
	"roof_tile": {"roughness_base": 0.75},
}

static var _meshes := {}
static var _buildings := {}
static var _materials := {}
static var _terrain_material: ShaderMaterial
static var _foliage_material: ShaderMaterial
static var _fish_material: ShaderMaterial


static func terrain_material() -> ShaderMaterial:
	if _terrain_material == null:
		_terrain_material = ShaderMaterial.new()
		_terrain_material.shader = load("res://shaders/terrain.gdshader")
	return _terrain_material


static func foliage_material() -> ShaderMaterial:
	if _foliage_material == null:
		_foliage_material = ShaderMaterial.new()
		_foliage_material.shader = load("res://shaders/foliage.gdshader")
	return _foliage_material


static func fish_material() -> ShaderMaterial:
	if _fish_material == null:
		_fish_material = ShaderMaterial.new()
		_fish_material.shader = load("res://shaders/fish.gdshader")
	return _fish_material


## Материал здания по имени материала детали (stone_block, glass…).
static func building_material(mat_id: String) -> ShaderMaterial:
	if _materials.has(mat_id):
		return _materials[mat_id]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/building.gdshader")
	var params: Dictionary = BUILDING_MATERIALS.get(mat_id, {})
	for key: String in params:
		m.set_shader_parameter(key, params[key])
	_materials[mat_id] = m
	return m


static func _first_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	var node := scene.instantiate()
	var found: Mesh = null
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		found = mi.mesh
		break
	node.free()
	return found


static func prop_mesh(id: String, variant: int) -> Mesh:
	var key := "%s_%d" % [id, variant]
	if not _meshes.has(key):
		var mesh := _first_mesh("res://models/props/%s.glb" % key)
		_meshes[key] = mesh if mesh else PropFactory.build(id, variant)
	return _meshes[key]


static func fish_mesh(species: String) -> Mesh:
	var key := "fish_" + species
	if not _meshes.has(key):
		var mesh := _first_mesh("res://models/fish/%s.glb" % species)
		_meshes[key] = mesh if mesh else PropFactory.build_fish(species)
	return _meshes[key]


## {"mesh": Mesh, "rotor_mesh": Mesh или null, "pivot": Vector3, "bounds": AABB, "materials": Array[String]}
static func building(id: String) -> Dictionary:
	if _buildings.has(id):
		return _buildings[id]
	var data := {"mesh": null, "rotor_mesh": null, "pivot": Vector3.ZERO}
	var path := "res://models/buildings/%s.glb" % id
	if ResourceLoader.exists(path):
		var node: Node = (load(path) as PackedScene).instantiate()
		var full := node.find_child("Full", true, false) as MeshInstance3D
		if full:
			data["mesh"] = full.mesh
		var rotor := node.find_child("Rotor", true, false) as Node3D
		if rotor:
			data["pivot"] = rotor.position
			for mi: MeshInstance3D in rotor.find_children("*", "MeshInstance3D", true, false):
				data["rotor_mesh"] = mi.mesh
		node.free()
	if data["mesh"] == null:
		var built := BuildingFactory.build(id)
		var g: Geo = built["static"]
		g.encode_stages()
		data["mesh"] = g.build_mesh()
		if built["rotor"]:
			var rg: Geo = built["rotor"]
			rg.encode_stages(1, 0.25, 0.97)
			data["rotor_mesh"] = rg.build_mesh()
			data["pivot"] = built["pivot"]
	var mesh: Mesh = data["mesh"]
	var box := mesh.get_aabb()
	var mats: Array[String] = []
	for i in mesh.get_surface_count():
		mats.append(_surface_material_name(mesh, i))
	if data["rotor_mesh"]:
		var rm: Mesh = data["rotor_mesh"]
		box = box.merge(AABB(rm.get_aabb().position + data["pivot"], rm.get_aabb().size))
		for i in rm.get_surface_count():
			var n := _surface_material_name(rm, i)
			if not mats.has(n):
				mats.append(n)
	data["bounds"] = box
	data["materials"] = mats
	_buildings[id] = data
	return data


## Имя поверхности без хвостовых цифр: экспорт glTF делает имена уникальными
## (log, log2…), а Blender добавляет «.001». Вид «материал__пометка».
static func _surface_key(mesh: Mesh, surface: int) -> String:
	var m := mesh.surface_get_material(surface)
	if m == null:
		return ""
	var n := m.resource_name
	while n.length() > 0 and n[-1] in "0123456789":
		n = n.left(-1)
	return n.trim_suffix(".")


## Материал поверхности (stone_block, glass…) без пометки.
static func _surface_material_name(mesh: Mesh, surface: int) -> String:
	return _surface_key(mesh, surface).get_slice("__", 0)


## Пометка поверхности: «opening» — двери и окна, иначе пусто.
static func surface_tag(mesh: Mesh, surface: int) -> String:
	var key := _surface_key(mesh, surface)
	return key.get_slice("__", 1) if "__" in key else ""


## Ставит материалы зданий на все поверхности меша.
static func apply_building_materials(mi: MeshInstance3D) -> void:
	for i in mi.mesh.get_surface_count():
		mi.set_surface_override_material(i, building_material(_surface_material_name(mi.mesh, i)))
