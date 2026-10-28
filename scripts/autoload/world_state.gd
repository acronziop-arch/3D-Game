extends Node
## Всё, чем текущий мир отличается от «чистой» генерации по сиду:
## правки рельефа, срубленные деревья, открытые сундуки, здания.
## Мир бесконечный, поэтому храним только изменения, а не сам мир.
##
## Миров может быть несколько: у каждого своё имя и свой файл в user://worlds/,
## список с именами и датами — в user://worlds/index.dat.

const WORLDS_DIR := "user://worlds/"
const INDEX_PATH := "user://worlds/index.dat"
## Старое единственное сохранение — переносится в список миров при первом запуске.
const LEGACY_PATH := "user://world.save"
const SAVE_VERSION := 4
## Превью — PREVIEW_CELLS клеток карты (по 4 м) вокруг камеры.
const PREVIEW_CELLS := 48
const BUILDING_DOT := Color("#5A4636")
const NAME_IDEAS := ["Тихая долина", "Солнечный холм", "Речная гавань", "Сосновый край", "Ясная поляна",
	"Медовый луг", "Каменный брод", "Северная застава", "Ольховка", "Зелёный дол", "Лисья опушка", "Ветряная гряда"]

## Открытый мир: id и имя (пусто — мир ещё не выбран, показывается стартовый экран).
var world_id := ""
var world_name := ""
var world_seed: int = 0
## Vector2i(вершина сетки) -> высота.
var terrain_edits: Dictionary = {}
## Vector2i(чанк) -> {индекс объекта: true}.
var removed_props: Dictionary = {}
## Vector2i(чанк) -> true.
var opened_chests: Dictionary = {}
## [{"id": String, "pos": Vector3, "yaw": float}]
var buildings: Array = []
## Покров земли, изменённый игроком: Vector2i(клетка 2 м) -> "mow" | "grass" | "tall" | "flowers".
var cover_edits: Dictionary = {}
## Посаженные деревья: Vector2i(чанк) -> [{"id", "x", "z", "rot", "scale", "t"}].
var planted: Dictionary = {}
## Метки игрока: [{"pos": Vector3, "color": Color, "icon": String, "name": String}].
var markers: Array = []
## Плавные дорожки (см. PathSystem).
var paths: Array = []
## Разведанные клетки карты (Vector2i клетки карты -> цвет).
var explored: Dictionary = {}
## id здания -> сколько достроено (нужно для проверки мастерских).
var completed_counts: Dictionary = {}
var camera_state: Dictionary = {}


func new_world(seed_value := -1) -> void:
	world_seed = seed_value if seed_value >= 0 else randi() % 1000000
	terrain_edits.clear()
	removed_props.clear()
	opened_chests.clear()
	buildings.clear()
	cover_edits.clear()
	planted.clear()
	markers.clear()
	paths.clear()
	explored.clear()
	completed_counts.clear()
	camera_state.clear()
	Inventory.clear()
	Crafting.clear()


func mark_prop_removed(chunk: Vector2i, index: int) -> void:
	if not removed_props.has(chunk):
		removed_props[chunk] = {}
	removed_props[chunk][index] = true


func removed_in_chunk(chunk: Vector2i) -> Dictionary:
	return removed_props.get(chunk, {}).duplicate()


## Правки покрова в клетках чанка.
func cover_edits_for_chunk(chunk: Vector2i) -> Dictionary:
	var result := {}
	if cover_edits.is_empty():
		return result
	var per := int(WorldGen.CHUNK_SIZE / 2.0)
	for j in per:
		for i in per:
			var cell := Vector2i(chunk.x * per + i, chunk.y * per + j)
			if cover_edits.has(cell):
				result[cell] = cover_edits[cell]
	return result


func planted_in_chunk(chunk: Vector2i) -> Array:
	return planted.get(chunk, []).duplicate(true)


func has_station(building_id: String) -> bool:
	return completed_counts.get(building_id, 0) > 0


func register_completed(building_id: String) -> void:
	completed_counts[building_id] = completed_counts.get(building_id, 0) + 1


func unregister_completed(building_id: String) -> void:
	completed_counts[building_id] = maxi(completed_counts.get(building_id, 0) - 1, 0)


func save_game() -> bool:
	if world_id == "":
		return false
	DirAccess.make_dir_recursive_absolute(WORLDS_DIR)
	var file := FileAccess.open(_path(world_id), FileAccess.WRITE)
	if file == null:
		push_warning("Не удалось сохранить: %s" % error_string(FileAccess.get_open_error()))
		return false
	_touch_index(world_id, {"name": world_name, "seed": world_seed, "played": Time.get_unix_time_from_system(),
		"buildings": buildings.size()})
	_save_preview(world_id, explored, camera_state.get("pos", Vector3.ZERO), buildings)
	file.store_var({
		"version": SAVE_VERSION,
		"seed": world_seed,
		"edits": terrain_edits,
		"removed": removed_props,
		"chests": opened_chests,
		"buildings": buildings,
		"cover": cover_edits,
		"planted": planted,
		"markers": markers,
		"paths": paths,
		"explored": explored,
		"crafting": Crafting.save_state(),
		"inventory": Inventory.items,
		"camera": camera_state,
		"weather": Weather.save_state(),
	})
	return true


func load_game() -> bool:
	if world_id == "" or not FileAccess.file_exists(_path(world_id)):
		return false
	var file := FileAccess.open(_path(world_id), FileAccess.READ)
	if file == null:
		return false
	var data: Variant = file.get_var()
	# Версия 3 читается тоже: новые поля у неё просто пустые.
	if not (data is Dictionary) or not int(data.get("version", 0)) in [3, SAVE_VERSION]:
		push_warning("Сохранение устарело или повреждено — создаём новый мир.")
		return false
	world_seed = data["seed"]
	terrain_edits = data["edits"]
	removed_props = data["removed"]
	opened_chests = data["chests"]
	buildings = data["buildings"]
	cover_edits = data.get("cover", {})
	planted = data.get("planted", {})
	markers = data.get("markers", [])
	paths = data.get("paths", [])
	explored = data.get("explored", {})
	camera_state = data["camera"]
	Crafting.load_state(data.get("crafting", {}))
	Weather.load_state(data.get("weather", {}))
	completed_counts.clear()
	Inventory.items = data["inventory"]
	Inventory.changed.emit("")
	return true


# --- Список миров ----------------------------------------------------------------------------------

func _path(id: String) -> String:
	return WORLDS_DIR + id + ".save"


## Картинка-превью мира для стартового экрана (кусок карты вокруг камеры).
func preview_path(id: String) -> String:
	return WORLDS_DIR + id + ".png"


## Разведанная карта вокруг точки и здания тёмными точками — как на мини-карте.
func _save_preview(id: String, explored_cells: Dictionary, center: Vector3, building_list: Array) -> void:
	var n := PREVIEW_CELLS
	var per := Minimap.PER_CHUNK
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Minimap.PAPER)
	var c0 := Vector2i(floori(center.x / Minimap.CELL) - n / 2, floori(center.z / Minimap.CELL) - n / 2)
	for cz in range(floori(float(c0.y) / per), floori(float(c0.y + n - 1) / per) + 1):
		for cx in range(floori(float(c0.x) / per), floori(float(c0.x + n - 1) / per) + 1):
			var bytes: PackedByteArray = explored_cells.get(Vector2i(cx, cz), PackedByteArray())
			if bytes.size() != per * per * 3:
				continue
			for j in per:
				for i in per:
					var px := cx * per + i - c0.x
					var py := cz * per + j - c0.y
					if px >= 0 and py >= 0 and px < n and py < n:
						var o := (j * per + i) * 3
						img.set_pixel(px, py, Color8(bytes[o], bytes[o + 1], bytes[o + 2]))
	img.resize(n * 2, n * 2, Image.INTERPOLATE_NEAREST)
	for b: Dictionary in building_list:
		var p: Vector3 = b.get("pos", Vector3.ZERO)
		var px := int((p.x / Minimap.CELL - c0.x) * 2.0)
		var py := int((p.z / Minimap.CELL - c0.y) * 2.0)
		if px >= 1 and py >= 1 and px < n * 2 - 2 and py < n * 2 - 2:
			img.fill_rect(Rect2i(px - 1, py - 1, 3, 3), BUILDING_DOT)
	img.save_png(preview_path(id))


## Миры, последние сыгранные — первыми: [{"id", "name", "seed", "created", "played", "buildings"}].
func list_worlds() -> Array:
	_migrate_legacy()
	var index := _read_index()
	var out: Array = []
	for id: String in index:
		if FileAccess.file_exists(_path(id)):
			var entry: Dictionary = index[id].duplicate()
			entry["id"] = id
			out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("played", 0.0) > b.get("played", 0.0))
	return out


## Новый мир с именем; сразу сохраняется и становится открытым.
func create_world(title: String, seed_value := -1) -> void:
	new_world(seed_value)
	world_id = _new_id()
	world_name = _unique_name(_clean_name(title))
	_touch_index(world_id, {"name": world_name, "seed": world_seed, "created": Time.get_unix_time_from_system()})
	save_game()


## Открывает сохранённый мир. false — файл повреждён или не найден.
func open_world(id: String) -> bool:
	var index := _read_index()
	if not index.has(id):
		return false
	world_id = id
	world_name = index[id].get("name", "Мир")
	if not load_game():
		world_id = ""
		return false
	return true


## Закрывает мир (после этого показывается стартовый экран).
func close_world() -> void:
	world_id = ""
	world_name = ""


func delete_world(id: String) -> void:
	var index := _read_index()
	index.erase(id)
	_write_index(index)
	for path in [_path(id), preview_path(id)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if id == world_id:
		close_world()


func rename_world(id: String, title: String) -> void:
	_touch_index(id, {"name": _clean_name(title)})
	if id == world_id:
		world_name = _clean_name(title)


## Имя для нового мира, которого ещё нет в списке.
func suggest_name() -> String:
	var taken := _taken_names()
	var ideas: Array = NAME_IDEAS.duplicate()
	ideas.shuffle()
	for title: String in ideas:
		if not taken.has(title):
			return title
	return _unique_name("Новый мир")


func _taken_names() -> Dictionary:
	var taken := {}
	for entry: Dictionary in _read_index().values():
		taken[entry.get("name", "")] = true
	return taken


## Имя, которого ещё нет в списке: «Деревня», «Деревня 2», «Деревня 3»…
func _unique_name(title: String) -> String:
	var taken := _taken_names()
	if not taken.has(title):
		return title
	# «Деревня 2» занята — следующая «Деревня 3», а не «Деревня 2 2».
	var m := RegEx.create_from_string("^(.*\\S) (\\d+)$").search(title)
	var base := m.get_string(1) if m else title
	var n := 2
	while taken.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


static func _clean_name(title: String) -> String:
	var t := title.strip_edges().replace("\n", " ")
	if t == "":
		t = "Мой мир"
	return t.left(40)


func _new_id() -> String:
	return "w%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 100000]


func _read_index() -> Dictionary:
	if not FileAccess.file_exists(INDEX_PATH):
		return {}
	var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = file.get_var()
	return data if data is Dictionary else {}


func _write_index(index: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(WORLDS_DIR)
	var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if file:
		file.store_var(index)


func _touch_index(id: String, fields: Dictionary) -> void:
	var index := _read_index()
	var entry: Dictionary = index.get(id, {})
	entry.merge(fields, true)
	index[id] = entry
	_write_index(index)


## Сохранение из прошлых версий (один мир) становится «Моим миром» в списке.
func _migrate_legacy() -> void:
	if not FileAccess.file_exists(LEGACY_PATH):
		return
	DirAccess.make_dir_recursive_absolute(WORLDS_DIR)
	var id := _new_id()
	if DirAccess.rename_absolute(LEGACY_PATH, _path(id)) == OK:
		var now := Time.get_unix_time_from_system()
		_touch_index(id, {"name": "Мой мир", "created": now, "played": now})
