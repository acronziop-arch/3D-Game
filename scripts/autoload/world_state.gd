extends Node
## Всё, чем текущий мир отличается от «чистой» генерации по сиду:
## правки рельефа, срубленные деревья, открытые сундуки, здания.
## Мир бесконечный, поэтому храним только изменения, а не сам мир.

const SAVE_PATH := "user://world.save"
const SAVE_VERSION := 3

var world_seed: int = 0
## Vector2i(вершина сетки) -> высота.
var terrain_edits: Dictionary = {}
## Vector2i(чанк) -> {индекс объекта: true}.
var removed_props: Dictionary = {}
## Vector2i(чанк) -> true.
var opened_chests: Dictionary = {}
## [{"id": String, "pos": Vector3, "rot": int}]
var buildings: Array = []
## id здания -> сколько достроено (нужно для проверки мастерских).
var completed_counts: Dictionary = {}
var camera_state: Dictionary = {}


func new_world(seed_value := -1) -> void:
	world_seed = seed_value if seed_value >= 0 else randi() % 1000000
	terrain_edits.clear()
	removed_props.clear()
	opened_chests.clear()
	buildings.clear()
	completed_counts.clear()
	camera_state.clear()
	Inventory.clear()


func mark_prop_removed(chunk: Vector2i, index: int) -> void:
	if not removed_props.has(chunk):
		removed_props[chunk] = {}
	removed_props[chunk][index] = true


func removed_in_chunk(chunk: Vector2i) -> Dictionary:
	return removed_props.get(chunk, {}).duplicate()


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
	if not (data is Dictionary) or data.get("version", 0) != SAVE_VERSION:
		push_warning("Сохранение устарело или повреждено — создаём новый мир.")
		return false
	world_seed = data["seed"]
	terrain_edits = data["edits"]
	removed_props = data["removed"]
	opened_chests = data["chests"]
	buildings = data["buildings"]
	camera_state = data["camera"]
	Weather.load_state(data.get("weather", {}))
	completed_counts.clear()
	Inventory.items = data["inventory"]
	Inventory.changed.emit("")
	return true
