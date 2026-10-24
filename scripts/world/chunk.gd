class_name Chunk
extends Node3D
## Квадрат мира 32×32 м: рельеф, объекты (через MultiMesh — тысячи
## деревьев рисуются дёшево) и, иногда, сундук.

const DECOR_VISIBLE_DISTANCE := 110.0

var coord := Vector2i.ZERO
var heights := PackedFloat32Array()
var colors := PackedColorArray()
## [{"id", "index", "pos": Vector3 (локально), "rot", "scale", "mm": id типа, "mm_i": int, "hidden": bool}]
var props: Array[Dictionary] = []
var chest: Chest

var _terrain_mesh: MeshInstance3D
var _multimeshes := {}


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

	if data.has("chest"):
		var c: Dictionary = data["chest"]
		chest = Chest.new()
		chest.setup(c["rarity"], coord)
		chest.position = c["pos"]
		chest.rotation.y = c["rot"]
		add_child(chest)


func _apply_terrain(arrays: Array) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, MeshKit.vertex_color_material())
	_terrain_mesh.mesh = mesh


func _build_props() -> void:
	var by_type := {}
	for p in props:
		if not by_type.has(p["id"]):
			by_type[p["id"]] = []
		by_type[p["id"]].append(p)
	for id: String in by_type:
		var list: Array = by_type[id]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = PropMeshes.get_mesh(id)
		mm.instance_count = list.size()
		for i in list.size():
			var p: Dictionary = list[i]
			p["mm"] = id
			p["mm_i"] = i
			p["hidden"] = false
			mm.set_instance_transform(i, prop_transform(p))
			mm.set_instance_color(i, _instance_tint(id, p["index"]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if GameData.PROPS[id]["kind"] == "decor":
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = DECOR_VISIBLE_DISTANCE
			mmi.visibility_range_end_margin = 20.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
		_multimeshes[id] = mm


func _instance_tint(id: String, index: int) -> Color:
	var h := WorldGen.hash01(coord.x * 131 + index, coord.y, 3)
	var v := 0.88 + h * 0.24
	if id == "tree_maple":
		return Color(v, v * (0.85 + h * 0.3), v * 0.9)
	return Color(v, v, v)


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
func pick(from: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	var o := from - global_position
	for p in props:
		if p["hidden"] or not is_harvestable(p):
			continue
		var def: Dictionary = GameData.PROPS[p["id"]]
		var s: float = p["scale"]
		var t := _ray_vs_column(o, dir, p["pos"], float(def["radius"]) * s * 0.75, float(def["height"]) * s)
		if t < best_t:
			best_t = t
			best = {"t": t, "prop": p, "chunk": self}
	if is_instance_valid(chest) and not chest.opened:
		var t := _ray_vs_column(o, dir, chest.position, Chest.RADIUS, Chest.HEIGHT)
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


func get_vertex_height(i: int, j: int) -> float:
	return heights[j * (WorldGen.RES + 1) + i]


func set_vertex_height(i: int, j: int, h: float) -> void:
	heights[j * (WorldGen.RES + 1) + i] = h


## Перестраивает рельеф после выравнивания и ставит объекты на новую высоту.
func rebuild_terrain() -> void:
	_apply_terrain(WorldGen.build_terrain(heights, colors, coord).get_arrays())
	for p in props:
		var pos: Vector3 = p["pos"]
		pos.y = height_local(pos.x, pos.z)
		p["pos"] = pos
		if not p["hidden"]:
			_multimeshes[p["mm"]].set_instance_transform(p["mm_i"], prop_transform(p))
	if is_instance_valid(chest):
		chest.position.y = height_local(chest.position.x, chest.position.z)
