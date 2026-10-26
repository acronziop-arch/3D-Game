extends SceneTree
## Проверка игровых данных. Запуск:
##   godot --headless --path . --script res://tests/validate_data.gd
## Ловит ошибки баланса раньше, чем их заметит игрок:
##   * любое действие (добыча, ремесло, стройка, сундук) — не дольше 30 с;
##   * модель здания состоит только из материалов, которые есть в его стоимости;
##   * все ресурсы откуда-то берутся и все здания можно построить по цепочке.

const GD := preload("res://scripts/autoload/game_data.gd")

var _errors: PackedStringArray = []


func _init() -> void:
	_check_times()
	_check_references()
	_check_material_rule()
	_check_icons()
	_check_sources()
	_check_progression()
	_check_determinism()
	if _errors.is_empty():
		print("OK: данные игры согласованы (%d зданий, %d рецептов, %d объектов)" % [GD.BUILDINGS.size(), GD.RECIPES.size(), GD.PROPS.size()])
		quit(0)
	else:
		for e in _errors:
			printerr("ОШИБКА: ", e)
		quit(1)


func _fail(text: String) -> void:
	_errors.append(text)


func _check_times() -> void:
	for id: String in GD.BUILDINGS:
		if GD.BUILDINGS[id]["time"] > GD.MAX_ACTION_TIME:
			_fail("стройка %s дольше 30 с" % id)
	for id: String in GD.PROPS:
		if GD.PROPS[id]["time"] > GD.MAX_ACTION_TIME:
			_fail("добыча %s дольше 30 с" % id)
	for id: String in GD.RECIPES:
		if GD.RECIPES[id]["time"] > GD.MAX_ACTION_TIME:
			_fail("рецепт %s дольше 30 с" % id)
	for id: String in GD.CHESTS:
		if GD.CHESTS[id]["open_time"] > GD.MAX_ACTION_TIME:
			_fail("сундук %s открывается дольше 30 с" % id)


func _check_references() -> void:
	for id: String in GD.BUILDINGS:
		for res: String in GD.BUILDINGS[id]["cost"]:
			if not GD.RESOURCES.has(res):
				_fail("здание %s: неизвестный ресурс %s" % [id, res])
		if not GD.BUILDING_CATEGORIES.has(GD.BUILDINGS[id]["category"]):
			_fail("здание %s: неизвестная категория" % id)
	for id: String in GD.RECIPES:
		var r: Dictionary = GD.RECIPES[id]
		if not GD.BUILDINGS.has(r["station"]):
			_fail("рецепт %s: нет здания %s" % [id, r["station"]])
		for res: String in r["in"].keys() + r["out"].keys():
			if not GD.RESOURCES.has(res):
				_fail("рецепт %s: неизвестный ресурс %s" % [id, res])
	for id: String in GD.PROPS:
		for res: String in GD.PROPS[id].get("drops", {}):
			if not GD.RESOURCES.has(res):
				_fail("объект %s: неизвестный ресурс %s" % [id, res])
	for biome: int in WorldGen.BIOMES:
		for prop: String in WorldGen.BIOMES[biome]["props"]:
			if not GD.PROPS.has(prop):
				_fail("биом %d: неизвестный объект %s" % [biome, prop])
	for mat: String in GD.MATERIALS:
		var res: String = GD.MATERIALS[mat]["res"]
		if res != "" and not GD.RESOURCES.has(res):
			_fail("материал %s: неизвестный ресурс" % mat)


## Главное правило: из чего выглядит — из того и построено.
## Материалы берутся прямо из моделей models/buildings/*.glb.
func _check_material_rule() -> void:
	for id: String in GD.BUILDINGS:
		if GD.BUILDINGS[id].has("plant"):
			if not GD.PROPS.has(GD.BUILDINGS[id]["plant"]):
				_fail("саженец %s: неизвестное дерево" % id)
			continue
		if not ResourceLoader.exists("res://models/buildings/%s.glb" % id):
			_fail("нет модели models/buildings/%s.glb — запустите tools/export_models.gd" % id)
		var cost: Dictionary = GD.BUILDINGS[id]["cost"]
		for mat: String in ModelLibrary.building(id)["materials"]:
			if not GD.MATERIALS.has(mat):
				_fail("здание %s: неизвестный материал %s" % [id, mat])
				continue
			var res: String = GD.MATERIALS[mat]["res"]
			# Пустой ресурс — проём окна: из воздуха, стоимость не нужна.
			if res != "" and not cost.has(res):
				_fail("здание %s: на модели есть «%s», но в стоимости нет «%s»" % [id, mat, GD.RESOURCES[res]["name"]])
		if not GD.BUILDING_CATEGORIES.has(GD.BUILDINGS[id]["category"]):
			_fail("здание %s: неизвестная категория" % id)
		if not GD.BUILDINGS[id].get("place", "land") in ["land", "water", "bridge"]:
			_fail("здание %s: неизвестный режим размещения" % id)


func _check_icons() -> void:
	var names: Array = GD.RESOURCES.keys()
	for w: String in GD.WEATHERS:
		names.append("weather_" + w)
	for s: Dictionary in GD.SEASONS:
		names.append("season_" + s["id"])
	for c: String in GD.BUILDING_CATEGORIES:
		names.append("cat_" + c)
	for n: String in names:
		if not ResourceLoader.exists("res://assets/icons/%s.svg" % n):
			_fail("нет иконки assets/icons/%s.svg — запустите tools/make_icons.py" % n)


func _check_sources() -> void:
	for res: String in GD.RESOURCES:
		var group: String = GD.RESOURCES[res]["group"]
		var found := false
		match group:
			"raw":
				for p: String in GD.PROPS:
					found = found or GD.PROPS[p].get("drops", {}).has(res)
			"animal":
				for c: String in GD.CHESTS:
					for entry: Array in GD.CHESTS[c]["loot"]:
						found = found or entry[0] == res
			"processed":
				for r: String in GD.RECIPES:
					found = found or GD.RECIPES[r]["out"].has(res)
		if not found:
			_fail("ресурс %s (%s) ниоткуда не берётся" % [res, group])
		if group == "animal":
			for p: String in GD.PROPS:
				if GD.PROPS[p].get("drops", {}).has(res):
					_fail("животный ресурс %s выпадает из объекта %s — должен только из сундуков" % [res, p])


## Пошагово «играем»: что можно построить, имея добываемое сырьё и сундуки.
func _check_progression() -> void:
	var have := {}
	for res: String in GD.RESOURCES:
		if GD.RESOURCES[res]["group"] != "processed":
			have[res] = true
	var built := {}
	var changed := true
	while changed:
		changed = false
		for id: String in GD.BUILDINGS:
			if built.has(id):
				continue
			var ok := true
			for res: String in GD.BUILDINGS[id]["cost"]:
				ok = ok and have.has(res)
			if ok:
				built[id] = true
				changed = true
		for r: String in GD.RECIPES:
			var recipe: Dictionary = GD.RECIPES[r]
			if not built.has(recipe["station"]):
				continue
			var ok := true
			for res: String in recipe["in"]:
				ok = ok and have.has(res)
			if ok:
				for res: String in recipe["out"]:
					if not have.has(res):
						have[res] = true
						changed = true
	for id: String in GD.BUILDINGS:
		if not built.has(id):
			_fail("здание %s невозможно построить: не хватает цепочки ресурсов" % id)


func _check_determinism() -> void:
	var gen := WorldGen.new(12345)
	var a := {}
	var b := {}
	gen.generate_chunk(Vector2i(3, -2), {}, {}, false, a)
	gen.generate_chunk(Vector2i(3, -2), {}, {}, false, b)
	if a["heights"] != b["heights"] or a["props"].size() != b["props"].size():
		_fail("генерация чанка недетерминирована")
