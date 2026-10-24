class_name Chunk
extends Node3D
## Квадрат мира 32×32 м: рельеф, объекты (через MultiMesh — тысячи
## деревьев рисуются дёшево), рыбы в глубоких местах и, иногда, сундук.

var coord := Vector2i.ZERO
var heights := PackedFloat32Array()
var colors := PackedColorArray()
## [{"id", "index", "pos": Vector3 (локально), "rot", "scale", "mm": id типа, "mm_i": int, "hidden": bool}]
var props: Array[Dictionary] = []
var chest: Chest
var has_water := false
var fish: FishSchool

var _terrain_mesh: MeshInstance3D
var _multimeshes := {}
var _grass: MultiMesh
var _grass_buffer := PackedFloat32Array()
var _litter: MultiMesh
var _litter_buffer := PackedFloat32Array()


func setup(chunk_coord: Vector2i, data: Dictionary) -> void:
	coord = chunk_coord
	name = "Chunk_%d_%d" % [coord.x, coord.y]
	position = Vector3(coord.x, 0, coord.y) * WorldGen.CHUNK_SIZE
	heights = data["heights"]
	colors = data["colors"]

	# Коллизий нет: мышь «попадает» в землю через ChunkManager.raycast(),
	# а это дешевле, чем строить физическую форму для каждого чанка.
	_terrain_mesh = MeshInstance3D.new()
	add_child(_terrain_mesh)
	_apply_terrain(data["terrain"])

	props.assign(data["props"])
	_build_props()
	_build_cover(data)

	if data.has("chest"):
		var c: Dictionary = data["chest"]
		chest = Chest.new()
		chest.setup(c["rarity"], coord)
		chest.position = c["pos"]
		chest.rotation.y = c["rot"]
		add_child(chest)

	has_water = data.get("has_water", false)
	if has_water and Settings.get_value("fish"):
		fish = FishSchool.new()
		add_child(fish)
		fish.setup(data["fish_spots"], coord)


func _apply_terrain(arrays: Array) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, ModelLibrary.terrain_material())
	_terrain_mesh.mesh = mesh


func _build_props() -> void:
	var by_type := {}
	for p in props:
		var key := "%s_%d" % [p["id"], p.get("variant", 0)]
		if not by_type.has(key):
			by_type[key] = []
		by_type[key].append(p)
	for key: String in by_type:
		var list: Array = by_type[key]
		var id: String = list[0]["id"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = ModelLibrary.prop_mesh(id, list[0].get("variant", 0))
		mm.instance_count = list.size()
		for i in list.size():
			var p: Dictionary = list[i]
			p["mm"] = key
			p["mm_i"] = i
			p["hidden"] = false
			mm.set_instance_transform(i, prop_transform(p))
			mm.set_instance_color(i, _instance_tint(id, p["index"]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = ModelLibrary.foliage_material()
		if GameData.PROPS[id]["kind"] == "decor":
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = Platform.decor_distance()
			mmi.visibility_range_end_margin = 20.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
		_multimeshes[key] = mm


## Трава и опавшие листья: два MultiMesh, буферы посчитаны в рабочем потоке.
func _build_cover(data: Dictionary) -> void:
	_grass_buffer = data.get("grass", PackedFloat32Array())
	_litter_buffer = data.get("litter", PackedFloat32Array())
	if not _grass_buffer.is_empty():
		_grass = _cover_multimesh(GroundCover.grass_mesh(), _grass_buffer, GroundCover.GRASS_STRIDE, false)
		_add_cover(_grass, GroundCover.grass_material(Platform.grass_distance()), Platform.grass_distance())
	if not _litter_buffer.is_empty():
		_litter = _cover_multimesh(GroundCover.litter_mesh(), _litter_buffer, GroundCover.LITTER_STRIDE, true)
		var far := Platform.grass_distance() * 1.15
		_add_cover(_litter, GroundCover.litter_material(far), far)


static func _cover_multimesh(mesh: Mesh, buffer: PackedFloat32Array, stride: int, custom: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = buffer.size() / stride
	mm.buffer = buffer
	return mm


func _add_cover(mm: MultiMesh, material: Material, distance: float) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Пучки сами уходят в землю к distance (шейдер); чанк целиком прячется чуть дальше,
	# когда в нём точно ничего не видно (полдиагонали чанка — 23 м).
	mmi.visibility_range_end = distance + WorldGen.CHUNK_SIZE * 0.75
	add_child(mmi)


## Убирает траву и листья в прямоугольнике (мировые XZ), например под зданием.
func clear_cover(rect: Rect2) -> void:
	var local := Rect2(rect.position - Vector2(position.x, position.z), rect.size)
	if _grass and GroundCover.hide_in_rect(_grass_buffer, GroundCover.GRASS_STRIDE, local):
		_grass.buffer = _grass_buffer
	if _litter and GroundCover.hide_in_rect(_litter_buffer, GroundCover.LITTER_STRIDE, local):
		_litter.buffer = _litter_buffer


func _instance_tint(id: String, index: int) -> Color:
	var h := WorldGen.hash01(coord.x * 131 + index, coord.y, 3)
	var v := 0.9 + h * 0.2
	if id == "tree_maple":
		return Color(v, v * (0.9 + h * 0.15), v * 0.92)
	return Color(v, v, v * (0.96 + h * 0.08))


static func prop_transform(p: Dictionary) -> Transform3D:
	var s: float = p["scale"]
	return Transform3D(Basis(Vector3.UP, p["rot"]).scaled(Vector3(s, s, s)), p["pos"])


func world_prop_transform(p: Dictionary) -> Transform3D:
	return global_transform * prop_transform(p)


func set_prop_hidden(p: Dictionary, hidden: bool) -> void:
	p["hidden"] = hidden
	var mm: MultiMesh = _multimeshes[p["mm"]]
	if hidden:
		mm.set_instance_transform(p["mm_i"], Transform3D(Basis.from_scale(Vector3.ZERO), p["pos"]))
	else:
		mm.set_instance_transform(p["mm_i"], prop_transform(p))


## Навсегда убирает объект (запоминается в WorldState).
func remove_prop(p: Dictionary) -> void:
	set_prop_hidden(p, true)
	p["removed"] = true
	WorldState.mark_prop_removed(coord, p["index"])


static func is_harvestable(p: Dictionary) -> bool:
	return not p.get("removed", false) and float(GameData.PROPS[p["id"]]["time"]) > 0.0


## Ближайший объект или сундук на луче (в мировых координатах).
## Возвращает {"t": расстояние, "prop": Dictionary} или {"t", "chest": Chest}, либо {}.
func pick(from: Vector3, dir: Vector3, slack := 0.0) -> Dictionary:
	var best := {}
	var best_t := INF
	var o := from - global_position
	for p in props:
		if p["hidden"] or not is_harvestable(p):
			continue
		var def: Dictionary = GameData.PROPS[p["id"]]
		var s: float = p["scale"]
		var t := _ray_vs_column(o, dir, p["pos"], float(def["radius"]) * s * 0.75 + slack, float(def["height"]) * s)
		if t < best_t:
			best_t = t
			best = {"t": t, "prop": p, "chunk": self}
	if is_instance_valid(chest) and not chest.opened:
		var t := _ray_vs_column(o, dir, chest.position, Chest.RADIUS + slack, Chest.HEIGHT)
		if t < best_t:
			best = {"t": t, "chest": chest, "chunk": self}
	return best


## Пересечение луча с вертикальным столбом (цилиндром) — для выбора мышью.
static func _ray_vs_column(o: Vector3, d: Vector3, base: Vector3, radius: float, height: float) -> float:
	var dxz := Vector2(d.x, d.z)
	var len2 := dxz.length_squared()
	if len2 < 1e-6:
		return INF
	var rel := Vector2(base.x - o.x, base.z - o.z)
	var t_mid := rel.dot(dxz) / len2
	var closest := Vector2(o.x, o.z) + dxz * t_mid - Vector2(base.x, base.z)
	var dist2 := closest.length_squared()
	if t_mid < 0.0 or dist2 > radius * radius:
		return INF
	var t_in := t_mid - sqrt((radius * radius - dist2) / len2)
	for t in [t_in, t_mid]:
		var y: float = o.y + d.y * t
		if y >= base.y - 0.3 and y <= base.y + height + 0.3:
			return t
	return INF


## Объекты, чьи основания попадают в прямоугольник (мировые XZ).
func props_in_rect(rect: Rect2, harvestable_only: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var origin := Vector2(global_position.x, global_position.z)
	for p in props:
		if p["hidden"]:
			continue
		if harvestable_only and not is_harvestable(p):
			continue
		var pos: Vector3 = p["pos"]
		if rect.has_point(origin + Vector2(pos.x, pos.z)):
			result.append(p)
	return result


func height_local(lx: float, lz: float) -> float:
	return WorldGen.sample_height(heights, coord, lx, lz)


## i, j — от -1 до RES + 1 (с запасом вокруг чанка).
func get_vertex_height(i: int, j: int) -> float:
	return heights[WorldGen.hidx(i, j)]


func set_vertex_height(i: int, j: int, h: float) -> void:
	heights[WorldGen.hidx(i, j)] = h


## Перестраивает рельеф после выравнивания и ставит объекты на новую высоту.
func rebuild_terrain() -> void:
	_apply_terrain(WorldGen.build_terrain(heights, colors, coord))
	for p in props:
		if p.get("float", false):
			continue
		var pos: Vector3 = p["pos"]
		pos.y = height_local(pos.x, pos.z)
		p["pos"] = pos
		if not p["hidden"]:
			_multimeshes[p["mm"]].set_instance_transform(p["mm_i"], prop_transform(p))
	if is_instance_valid(chest):
		chest.position.y = height_local(chest.position.x, chest.position.z)
	if _grass:
		GroundCover.refit_heights(_grass_buffer, GroundCover.GRASS_STRIDE, height_local)
		_grass.buffer = _grass_buffer
	if _litter:
		GroundCover.refit_heights(_litter_buffer, GroundCover.LITTER_STRIDE, height_local)
		_litter.buffer = _litter_buffer
