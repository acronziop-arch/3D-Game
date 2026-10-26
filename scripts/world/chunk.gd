class_name Chunk
extends Node3D
## Квадрат мира 32×32 м: рельеф, объекты (через MultiMesh — тысячи
## деревьев рисуются дёшево), трава, цветы и листья на земле, рыбы в глубоких
## местах и, иногда, сундук. Посаженные игроком деревья растут на глазах.

## За сколько секунд саженец вырастает во взрослое дерево.
const GROW_TIME := 150.0
## Слои покрова: буфер из генератора, меш, шаг буфера, есть ли свои данные.
const COVER_LAYERS := ["grass", "tall", "flowers", "litter"]

var coord := Vector2i.ZERO
var heights := PackedFloat32Array()
var colors := PackedColorArray()
## [{"id", "index", "pos": Vector3 (локально), "rot", "scale", "mm": id типа, "mm_i": int, "hidden": bool}]
var props: Array[Dictionary] = []
var chest: Chest
var has_water := false
## Карта течения воды (см. WorldGen.flow_block); пусто — воды в чанке нет.
var flow := PackedByteArray()
var fish: FishSchool

var _terrain_mesh: MeshInstance3D
var _multimeshes := {}
var _prop_nodes: Array[Node] = []
## слой -> {"mm": MultiMesh, "buffer": PackedFloat32Array, "stride": int, "node": MultiMeshInstance3D}
var _cover := {}
## Растущие деревья (посаженные игроком).
var _growing: Array[Dictionary] = []
var _grow_timer := 0.0


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
	flow = data.get("flow", PackedByteArray())
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
	for n in _prop_nodes:
		n.queue_free()
	_prop_nodes.clear()
	_multimeshes.clear()
	_growing.clear()
	var by_type := {}
	for p in props:
		if p.get("removed", false):
			continue
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
			p["hidden"] = p.get("hidden", false)
			if p.has("planted_at") and not p["hidden"]:
				_growing.append(p)
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), p["pos"]) if p["hidden"] else prop_transform(p))
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
		_prop_nodes.append(mmi)
		_multimeshes[key] = mm


## Добавляет посаженное игроком дерево (и перестраивает объекты чанка).
func add_planted(p: Dictionary) -> void:
	props.append(p)
	_build_props()


## Сколько вырос саженец: 0.18 → 1 за GROW_TIME секунд (даже пока игра закрыта).
static func growth(p: Dictionary) -> float:
	if not p.has("planted_at"):
		return 1.0
	var age := Time.get_unix_time_from_system() - float(p["planted_at"])
	return lerpf(0.18, 1.0, smoothstep(0.0, GROW_TIME, age))


func _process(delta: float) -> void:
	if _growing.is_empty():
		return
	_grow_timer -= delta
	if _grow_timer > 0.0:
		return
	_grow_timer = 0.5
	for i in range(_growing.size() - 1, -1, -1):
		var p: Dictionary = _growing[i]
		if p.get("removed", false) or p["hidden"]:
			_growing.remove_at(i)
			continue
		_multimeshes[p["mm"]].set_instance_transform(p["mm_i"], prop_transform(p))
		if growth(p) >= 1.0:
			_growing.remove_at(i)


## Трава, высокая трава, цветы и опавшие листья: по MultiMesh на слой.
func _build_cover(data: Dictionary) -> void:
	for layer: String in COVER_LAYERS:
		if _cover.has(layer):
			(_cover[layer]["node"] as Node).queue_free()
			_cover.erase(layer)
		var buffer: PackedFloat32Array = data.get(layer, PackedFloat32Array())
		if buffer.is_empty():
			continue
		var stride := GroundCover.LITTER_STRIDE if layer == "litter" else GroundCover.GRASS_STRIDE
		var mesh: Mesh
		var material: Material
		var far := float(Settings.get_value("grass_distance"))
		match layer:
			"grass":
				mesh = GroundCover.grass_mesh()
				material = GroundCover.grass_material(far)
			"tall":
				mesh = GroundCover.tall_grass_mesh()
				material = GroundCover.grass_material(far)
			"flowers":
				mesh = GroundCover.flower_mesh()
				material = GroundCover.flower_material(far)
			_:
				far *= 1.15
				mesh = GroundCover.litter_mesh()
				material = GroundCover.litter_material(far)
		var mm := _cover_multimesh(mesh, buffer, stride, layer == "litter")
		var node := _add_cover(mm, material, far)
		_cover[layer] = {"mm": mm, "buffer": buffer, "stride": stride, "node": node}


## Новая дальность травы: чанк прячет покров, когда в нём уже ничего не видно.
func refit_cover_distance(far: float) -> void:
	for layer: String in _cover:
		var d := far * (1.15 if layer == "litter" else 1.0)
		(_cover[layer]["node"] as GeometryInstance3D).visibility_range_end = d + WorldGen.CHUNK_SIZE * 0.75


## Пересчитывает покров (после покоса, посева или смены густоты травы).
func rebuild_cover(data: Dictionary) -> void:
	_build_cover(data)


static func _cover_multimesh(mesh: Mesh, buffer: PackedFloat32Array, stride: int, custom: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = buffer.size() / stride
	mm.buffer = buffer
	return mm


func _add_cover(mm: MultiMesh, material: Material, distance: float) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Пучки сами уходят в землю к distance (шейдер); чанк целиком прячется чуть дальше,
	# когда в нём точно ничего не видно (полдиагонали чанка — 23 м).
	mmi.visibility_range_end = distance + WorldGen.CHUNK_SIZE * 0.75
	add_child(mmi)
	return mmi


## Убирает траву, цветы и листья в прямоугольнике (мировые XZ), например под зданием.
func clear_cover(rect: Rect2) -> void:
	var local := Rect2(rect.position - Vector2(position.x, position.z), rect.size)
	for layer: String in _cover:
		var c: Dictionary = _cover[layer]
		var buffer: PackedFloat32Array = c["buffer"]
		if GroundCover.hide_in_rect(buffer, c["stride"], local):
			c["buffer"] = buffer
			(c["mm"] as MultiMesh).buffer = buffer


func _instance_tint(id: String, index: int) -> Color:
	var h := WorldGen.hash01(coord.x * 131 + index, coord.y, 3)
	var v := 0.9 + h * 0.2
	if id == "tree_maple":
		return Color(v, v * (0.9 + h * 0.15), v * 0.92)
	return Color(v, v, v * (0.96 + h * 0.08))


static func prop_transform(p: Dictionary) -> Transform3D:
	var s: float = p["scale"] * growth(p)
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
	for layer: String in _cover:
		var c: Dictionary = _cover[layer]
		var buffer: PackedFloat32Array = c["buffer"]
		GroundCover.refit_heights(buffer, c["stride"], height_local)
		c["buffer"] = buffer
		(c["mm"] as MultiMesh).buffer = buffer
