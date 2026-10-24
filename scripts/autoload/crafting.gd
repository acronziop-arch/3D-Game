extends Node
## Очередь ремесла. Ресурсы списываются сразу при постановке в очередь,
## готовый результат появляется на складе по окончании таймера рецепта.

signal queue_changed
signal crafted(recipe_id: String)

const MAX_QUEUE := 8

var queue: Array[String] = []
## Сколько секунд уже идёт первый рецепт очереди.
var progress := 0.0


## Пустая строка — можно; иначе причина, почему нельзя.
func check(recipe_id: String) -> String:
	var recipe: Dictionary = GameData.RECIPES[recipe_id]
	if not WorldState.has_station(recipe["station"]):
		return "Нужно здание: %s" % GameData.BUILDINGS[recipe["station"]]["name"]
	if queue.size() >= MAX_QUEUE:
		return "Очередь заполнена"
	var lack := Inventory.missing(recipe["in"])
	if not lack.is_empty():
		return "Не хватает: %s" % GameData.cost_text(lack)
	return ""


func enqueue(recipe_id: String) -> String:
	var reason := check(recipe_id)
	if reason != "":
		return reason
	Inventory.spend(GameData.RECIPES[recipe_id]["in"])
	queue.append(recipe_id)
	queue_changed.emit()
	return ""


func current_fraction() -> float:
	if queue.is_empty():
		return 0.0
	return progress / float(GameData.RECIPES[queue[0]]["time"])


func _process(delta: float) -> void:
	if queue.is_empty():
		return
	progress += delta
	var recipe: Dictionary = GameData.RECIPES[queue[0]]
	if progress < recipe["time"]:
		return
	progress = 0.0
	var done: String = queue.pop_front()
	Inventory.add_all(recipe["out"])
	crafted.emit(done)
	queue_changed.emit()
