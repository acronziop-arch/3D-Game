extends Node
## Очередь ремесла. Ресурсы списываются сразу при постановке в очередь,
## готовый результат появляется на складе по окончании таймера рецепта.
## Ремесло идёт само, даже когда окно ремесла закрыто, и сохраняется вместе с миром.
## Мастерская должна быть недалеко от камеры (STATION_RANGE): если отлететь,
## новые рецепты не принимаются, а текущий ждёт, пока вы вернётесь.
## В творческом режиме всё готово сразу.

signal queue_changed
signal crafted(recipe_id: String)

const MAX_QUEUE := 24
## Дальше этого (м) от ближайшей мастерской рецепты недоступны.
const STATION_RANGE := 120.0

var queue: Array[String] = []
## Сколько секунд уже идёт первый рецепт очереди.
var progress := 0.0
## Расстояние от камеры до ближайшей готовой мастерской (задаёт main.gd).
var station_distance: Callable = func(_station: String) -> float: return 0.0


## Пустая строка — можно; иначе причина, почему нельзя.
func check(recipe_id: String) -> String:
	var recipe: Dictionary = GameData.RECIPES[recipe_id]
	var station: String = recipe["station"]
	if not WorldState.has_station(station) and not GameMode.is_creative():
		return "Нужно здание: %s" % GameData.BUILDINGS[station]["name"]
	var far := far_reason(station)
	if far != "":
		return far
	if queue.size() >= MAX_QUEUE:
		return "Очередь заполнена"
	var lack := Inventory.missing(recipe["in"])
	if not lack.is_empty():
		return "Не хватает: %s" % GameData.cost_text(lack)
	return ""


## Пустая строка — мастерская рядом; иначе «слишком далеко».
func far_reason(station: String) -> String:
	if GameMode.is_creative():
		return ""
	var d: float = station_distance.call(station)
	if d > STATION_RANGE:
		return "%s слишком далеко (%d м)" % [GameData.BUILDINGS[station]["name"], roundi(d)]
	return ""


func enqueue(recipe_id: String) -> String:
	var reason := check(recipe_id)
	if reason != "":
		return reason
	Inventory.spend(GameData.RECIPES[recipe_id]["in"])
	queue.append(recipe_id)
	queue_changed.emit()
	return ""


## Очередь, сжатая в группы: [{"id", "count"}] — одинаковые рецепты подряд в одну.
func grouped() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in queue:
		if not result.is_empty() and result[-1]["id"] == id:
			result[-1]["count"] += 1
		else:
			result.append({"id": id, "count": 1})
	return result


func current_fraction() -> float:
	if queue.is_empty():
		return 0.0
	return clampf(progress / _time_of(queue[0]), 0.0, 1.0)


## Ждёт ли первый рецепт, потому что мастерская далеко.
func is_paused() -> bool:
	return not queue.is_empty() and far_reason(GameData.RECIPES[queue[0]]["station"]) != ""


func _time_of(recipe_id: String) -> float:
	return 0.2 if GameMode.is_creative() else float(GameData.RECIPES[recipe_id]["time"])


func _process(delta: float) -> void:
	if queue.is_empty() or is_paused():
		return
	progress += delta
	var id := queue[0]
	if progress < _time_of(id):
		return
	progress = 0.0
	queue.pop_front()
	Inventory.add_all(GameData.RECIPES[id]["out"])
	crafted.emit(id)
	queue_changed.emit()


func clear() -> void:
	queue.clear()
	progress = 0.0
	queue_changed.emit()


func save_state() -> Dictionary:
	return {"queue": Array(queue), "progress": progress}


func load_state(state: Dictionary) -> void:
	queue.clear()
	for id: String in state.get("queue", []):
		if GameData.RECIPES.has(id):
			queue.append(id)
	progress = float(state.get("progress", 0.0))
	queue_changed.emit()
