extends Node
## Всё, чем текущий мир отличается от «чистой» генерации по сиду:
## правки рельефа, срубленные деревья, открытые сундуки, здания.
## Мир бесконечный, поэтому храним только изменения, а не сам мир.

const SAVE_PATH := "user://world.save"
const SAVE_VERSION := 4

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
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Не удалось сохранить: %s" % error_string(FileAccess.get_open_error()))
		return false
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
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
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
