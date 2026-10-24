extends Node
## Склад игрока. Один общий на весь мир: людей нет, переносить ресурсы некому.

## id ресурса ("" — изменилось всё сразу, например после загрузки).
signal changed(res_id: String)

## id ресурса -> количество.
var items: Dictionary = {}


func count(res_id: String) -> int:
	return items.get(res_id, 0)


func add(res_id: String, amount: int) -> void:
	if amount <= 0:
		return
	items[res_id] = count(res_id) + amount
	changed.emit(res_id)


func add_all(resources: Dictionary) -> void:
	for id: String in resources:
		add(id, resources[id])


func has_all(cost: Dictionary) -> bool:
	for id: String in cost:
		if count(id) < cost[id]:
			return false
	return true


## Чего не хватает: {id: сколько ещё нужно}.
func missing(cost: Dictionary) -> Dictionary:
	var result := {}
	for id: String in cost:
		var lack: int = cost[id] - count(id)
		if lack > 0:
			result[id] = lack
	return result


func spend(cost: Dictionary) -> bool:
	if not has_all(cost):
		return false
	for id: String in cost:
		items[id] = count(id) - cost[id]
		changed.emit(id)
	return true


func clear() -> void:
	items.clear()
	changed.emit("")
