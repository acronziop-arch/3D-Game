extends Node
## Режим игры (настройка «game_mode»):
##   normal   — обычный: ресурсы добываются, здания строятся со временем;
##   creative — творческий: ресурсы бесконечны, здания встают сразу, объекты
##              добываются мгновенно.

signal mode_changed


func _ready() -> void:
	Settings.changed.connect(func(key: String) -> void:
		if key == "game_mode":
			mode_changed.emit()
			Inventory.changed.emit(""))


func is_creative() -> bool:
	return Settings.get_value("game_mode") == "creative"
