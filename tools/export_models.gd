extends SceneTree
## Генерирует все 3D-модели игры и сохраняет их в models/ как .glb.
## Запуск (из папки проекта):
##   godot --headless --path . --script res://tools/export_models.gd
## Файлы .glb можно открыть в Blender, доработать и сохранить обратно —
## игра подхватит их автоматически. Правила: материал детали называется как
## в GameData.MATERIALS («__opening» — проём окна или двери), COLOR.a — этап
## стройки (здания) или гибкость на ветру (растения), UV2 — тип поверхности.

const GD := preload("res://scripts/autoload/game_data.gd")


func _init() -> void:
	var only := OS.get_cmdline_user_args()
	# `-- --footprints` — только пересчитать пятна построек, модели не трогать.
	if "--footprints" in only:
		var footprints := {}
		for id: String in GD.BUILDINGS:
			if not GD.BUILDINGS[id].has("plant"):
				footprints[id] = _footprint(BuildingFactory.build(id)["static"])
		_save_footprints(footprints)
		print("Пятна построек: %d" % footprints.size())
		quit()
		return
	for dir in ["res://models/buildings", "res://models/props", "res://models/fish"]:
		DirAccess.make_dir_recursive_absolute(dir)
	var total := 0
	var footprints: Dictionary = Footprints.BASE.duplicate()
	for id: String in GD.BUILDINGS:
		if not only.is_empty() and not id in only:
			continue
		if GD.BUILDINGS[id].has("plant"):
			continue
		total += _export_building(id, footprints)
	_save_footprints(footprints)
	for id: String in PropFactory.VARIANTS:
		if not only.is_empty() and not id in only:
			continue
		for v in PropFactory.VARIANTS[id]:
			var root := Node3D.new()
			root.name = "%s_%d" % [id, v]
			_add_mesh(root, "Mesh", PropFactory.build(id, v))
			_save(root, "res://models/props/%s_%d.glb" % [id, v])
	for species: String in PropFactory.FISH:
		if not only.is_empty() and not species in only:
			continue
		var root := Node3D.new()
		root.name = species
		_add_mesh(root, "Mesh", PropFactory.build_fish(species))
		_save(root, "res://models/fish/%s.glb" % species)
	print("Готово. Треугольников в зданиях: %d" % total)
	quit()


func _export_building(id: String, footprints: Dictionary) -> int:
	var data := BuildingFactory.build(id)
	var g: Geo = data["static"]
	g.encode_stages()
	footprints[id] = _footprint(g)
	var root := Node3D.new()
	root.name = id
	_add_mesh(root, "Full", g.build_mesh())
	var tris := g.triangle_count()
	if data["rotor"]:
		var rotor_geo: Geo = data["rotor"]
		rotor_geo.encode_stages(1, 0.25, 0.97)
		var pivot := Node3D.new()
		pivot.name = "Rotor"
		pivot.position = data["pivot"]
		root.add_child(pivot)
		pivot.owner = root
		var mi := _add_mesh(pivot, "RotorMesh", rotor_geo.build_mesh())
		mi.owner = root
		tris += rotor_geo.triangle_count()
	_save(root, "res://models/buildings/%s.glb" % id)
	print("%-14s %6d треугольников" % [id, tris])
	return tris


## Пятно у земли: у низкой мелочи (бочки, скамья) — вся модель, у зданий — до 0.6 м.
static func _footprint(g: Geo) -> Rect2:
	return g.base_rect(INF if g.aabb().end.y < 1.6 else 0.6)


## Пятна построек у земли — в scripts/models/footprints.gd (по ним проверяется,
## не стоят ли постройки друг в друге; читать вершины из моделей в игре дорого).
func _save_footprints(footprints: Dictionary) -> void:
	var ids := footprints.keys()
	ids.sort()
	var lines := PackedStringArray()
	for id: String in ids:
		var r: Rect2 = footprints[id]
		lines.append('\t"%s": Rect2(%.3f, %.3f, %.3f, %.3f),' % [id, r.position.x, r.position.y, r.size.x, r.size.y])
	var f := FileAccess.open("res://scripts/models/footprints.gd", FileAccess.WRITE)
	f.store_string("class_name Footprints\nextends RefCounted\n## Пятна построек у земли (XZ, в координатах модели): без свесов крыш, вывесок\n" +
		"## и козырьков. Файл пишет tools/export_models.gd — руками не править.\n\nconst BASE := {\n" +
		"\n".join(lines) + "\n}\n")


func _add_mesh(parent: Node, node_name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	parent.add_child(mi)
	mi.owner = parent if parent.owner == null else parent.owner
	return mi


func _save(root: Node, path: String) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	if err != OK:
		push_error("Не удалось сохранить %s: %s" % [path, error_string(err)])
	root.free()
	_compact_glb(path)


## Уменьшает .glb примерно вдвое: убирает касательные (они не нужны — у моделей
## нет текстур) и хранит цвет вершин в 4 байтах вместо 16.
func _compact_glb(path: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	var json_len := bytes.decode_u32(12)
	var json: Dictionary = JSON.parse_string(bytes.slice(20, 20 + json_len).get_string_from_utf8())
	var bin_start := 20 + json_len + 8
	var bin := bytes.slice(bin_start, bin_start + bytes.decode_u32(20 + json_len))
	var used := {}
	var colors := {}
	for mesh: Dictionary in json.get("meshes", []):
		for prim: Dictionary in mesh["primitives"]:
			prim["attributes"].erase("TANGENT")
			for key: String in prim["attributes"]:
				used[int(prim["attributes"][key])] = true
				if key == "COLOR_0":
					colors[int(prim["attributes"][key])] = true
			if prim.has("indices"):
				used[int(prim["indices"])] = true
	var comp_size := {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
	var type_count := {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
	var out := PackedByteArray()
	var views := []
	var accessors := []
	var remap := {}
	var old_accessors: Array = json["accessors"]
	for i in old_accessors.size():
		if not used.has(i):
			continue
		var acc: Dictionary = old_accessors[i]
		var view: Dictionary = json["bufferViews"][int(acc["bufferView"])]
		var n: int = type_count[acc["type"]]
		var size: int = comp_size[int(acc["componentType"])]
		var count := int(acc["count"])
		var start := int(view.get("byteOffset", 0)) + int(acc.get("byteOffset", 0))
		var stride := int(view.get("byteStride", n * size))
		var data := PackedByteArray()
		if colors.has(i) and int(acc["componentType"]) == 5126:
			data.resize(count * 4)
			for k in count:
				for c in 4:
					var value := bin.decode_float(start + k * stride + c * 4) if c < n else 1.0
					data[k * 4 + c] = clampi(roundi(value * 255.0), 0, 255)
			acc["componentType"] = 5121
			acc["normalized"] = true
			acc["type"] = "VEC4"
			acc.erase("min")
			acc.erase("max")
		else:
			for k in count:
				data.append_array(bin.slice(start + k * stride, start + k * stride + n * size))
		while out.size() % 4 != 0:
			out.append(0)
		var new_view := {"buffer": 0, "byteOffset": out.size(), "byteLength": data.size()}
		if view.has("target"):
			new_view["target"] = view["target"]
		out.append_array(data)
		views.append(new_view)
		acc["bufferView"] = views.size() - 1
		acc.erase("byteOffset")
		remap[i] = accessors.size()
		accessors.append(acc)
	for mesh: Dictionary in json.get("meshes", []):
		for prim: Dictionary in mesh["primitives"]:
			for key: String in prim["attributes"]:
				prim["attributes"][key] = remap[int(prim["attributes"][key])]
			if prim.has("indices"):
				prim["indices"] = remap[int(prim["indices"])]
	while out.size() % 4 != 0:
		out.append(0)
	json["accessors"] = accessors
	json["bufferViews"] = views
	json["buffers"] = [{"byteLength": out.size()}]
	var text := JSON.stringify(json).to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(32)
	var glb := PackedByteArray()
	glb.resize(12)
	glb.encode_u32(0, 0x46546C67)
	glb.encode_u32(4, 2)
	glb.encode_u32(8, 12 + 8 + text.size() + 8 + out.size())
	var header := PackedByteArray()
	header.resize(8)
	header.encode_u32(0, text.size())
	header.encode_u32(4, 0x4E4F534A)
	glb.append_array(header)
	glb.append_array(text)
	header.encode_u32(0, out.size())
	header.encode_u32(4, 0x004E4942)
	glb.append_array(header)
	glb.append_array(out)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(glb)
