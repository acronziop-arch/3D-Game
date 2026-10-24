class_name MeshKit
extends RefCounted
## Сборщик low-poly мешей с плоским затенением: у каждого треугольника
## своя нормаль и свой цвет (цвет вершины). Через него собираются деревья,
## камни и временные модели зданий, пока нет моделей из Blender.

static var _vertex_color_material: StandardMaterial3D

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()


static func vertex_color_material() -> StandardMaterial3D:
	if _vertex_color_material == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.92
		_vertex_color_material = m
	return _vertex_color_material


## Добавляет примитив Godot (BoxMesh, CylinderMesh, SphereMesh, PrismMesh...)
## с трансформацией и цветом, пересчитывая нормали «по граням».
func add_primitive(prim: PrimitiveMesh, xform: Transform3D, color: Color) -> MeshKit:
	var arrays := prim.get_mesh_arrays()
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0, idx.size(), 3):
		var ref := xform.basis * (n[idx[i]] + n[idx[i + 1]] + n[idx[i + 2]])
		add_triangle(xform * v[idx[i]], xform * v[idx[i + 1]], xform * v[idx[i + 2]], color, ref)
	return self


## В Godot лицевая сторона треугольника — обход по часовой стрелке.
## Если задан ref_normal, порядок вершин исправляется под него.
func add_triangle(a: Vector3, b: Vector3, c: Vector3, color: Color, ref_normal := Vector3.ZERO) -> void:
	var normal := (c - a).cross(b - a)
	if normal.length_squared() < 1e-12:
		return
	normal = normal.normalized()
	if ref_normal != Vector3.ZERO and normal.dot(ref_normal) < 0.0:
		var t := b
		b = c
		c = t
		normal = -normal
	_verts.append_array([a, b, c])
	_normals.append_array([normal, normal, normal])
	_colors.append_array([color, color, color])


func is_empty() -> bool:
	return _verts.is_empty()


func get_arrays() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	return arrays


func get_vertices() -> PackedVector3Array:
	return _verts


func build(material: Material = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, get_arrays())
	mesh.surface_set_material(0, material if material else vertex_color_material())
	return mesh


# --- Короткие конструкторы примитивов -----------------------------------------

static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cylinder(bottom_radius: float, top_radius: float, height: float, segments := 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.bottom_radius = bottom_radius
	m.top_radius = top_radius
	m.height = height
	m.radial_segments = segments
	m.rings = 0
	m.cap_top = top_radius > 0.0
	return m


static func sphere(radius: float, height: float, segments := 7, rings := 4) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = segments
	m.rings = rings
	return m


## Треугольная призма (двускатная крыша). Конёк идёт вдоль оси Z.
static func prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	m.left_to_right = 0.5
	return m


static func at(pos: Vector3, rot_deg := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)) * Basis.from_scale(scale), pos)
