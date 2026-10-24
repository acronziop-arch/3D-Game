extends Node
## Все игровые данные в одном месте: ресурсы, добываемые объекты, рецепты,
## здания и сундуки. Меняйте баланс здесь — код подхватит изменения.
##
## Главное правило ресурсов: здание выглядит ровно из того, из чего построено.
## Каждая деталь модели помечена материалом (MATERIALS), а материал привязан
## к ресурсу. tests/validate_data.gd проверяет, что все материалы модели есть
## в стоимости здания — так «деревянная» церковь не получит каменных стен.

const MAX_ACTION_TIME := 30.0

# --- Ресурсы -----------------------------------------------------------------
# group: raw — добывается в мире, animal — только из сундуков,
#        processed — делается в мастерских из других ресурсов.
const RESOURCES := {
	"log": {"name": "Брёвна", "group": "raw", "color": Color(0.55, 0.36, 0.2)},
	"stone": {"name": "Камень", "group": "raw", "color": Color(0.6, 0.6, 0.62)},
	"clay": {"name": "Глина", "group": "raw", "color": Color(0.72, 0.45, 0.32)},
	"sand": {"name": "Песок", "group": "raw", "color": Color(0.93, 0.84, 0.6)},
	"coal": {"name": "Уголь", "group": "raw", "color": Color(0.2, 0.2, 0.22)},
	"copper_ore": {"name": "Медная руда", "group": "raw", "color": Color(0.85, 0.52, 0.3)},
	"iron_ore": {"name": "Железная руда", "group": "raw", "color": Color(0.62, 0.42, 0.36)},
	"hide": {"name": "Шкуры", "group": "animal", "color": Color(0.66, 0.48, 0.32)},
	"wool": {"name": "Шерсть", "group": "animal", "color": Color(0.94, 0.92, 0.86)},
	"wax": {"name": "Воск", "group": "animal", "color": Color(0.98, 0.84, 0.45)},
	"plank": {"name": "Доски", "group": "processed", "color": Color(0.8, 0.62, 0.4)},
	"stone_block": {"name": "Тёсаный камень", "group": "processed", "color": Color(0.78, 0.76, 0.72)},
	"brick": {"name": "Кирпич", "group": "processed", "color": Color(0.7, 0.32, 0.24)},
	"glass": {"name": "Стекло", "group": "processed", "color": Color(0.62, 0.86, 0.95)},
	"iron_ingot": {"name": "Железо", "group": "processed", "color": Color(0.45, 0.47, 0.5)},
	"copper_ingot": {"name": "Медь", "group": "processed", "color": Color(0.88, 0.55, 0.3)},
	"leather": {"name": "Кожа", "group": "processed", "color": Color(0.58, 0.38, 0.22)},
	"cloth": {"name": "Ткань", "group": "processed", "color": Color(0.9, 0.86, 0.78)},
}

# --- Материалы деталей зданий ------------------------------------------------
# res — какой ресурс обязан быть в стоимости здания, если деталь из этого материала.
const MATERIALS := {
	"log": {"color": Color(0.46, 0.3, 0.17), "res": "log"},
	"log_dark": {"color": Color(0.33, 0.21, 0.12), "res": "log"},
	"plank": {"color": Color(0.74, 0.55, 0.34), "res": "plank"},
	"plank_dark": {"color": Color(0.48, 0.32, 0.2), "res": "plank"},
	"stone": {"color": Color(0.56, 0.56, 0.57), "res": "stone"},
	"stone_block": {"color": Color(0.7, 0.68, 0.63), "res": "stone_block"},
	"clay": {"color": Color(0.7, 0.44, 0.3), "res": "clay"},
	"brick": {"color": Color(0.66, 0.3, 0.22), "res": "brick"},
	"roof_tile": {"color": Color(0.58, 0.2, 0.15), "res": "brick"},
	"glass": {"color": Color(0.62, 0.86, 0.96), "res": "glass"},
	"iron": {"color": Color(0.27, 0.28, 0.31), "res": "iron_ingot"},
	"copper": {"color": Color(0.36, 0.66, 0.58), "res": "copper_ingot"},
	"cloth": {"color": Color(0.94, 0.9, 0.82), "res": "cloth"},
	"leather": {"color": Color(0.62, 0.43, 0.27), "res": "leather"},
	"wax": {"color": Color(1.0, 0.92, 0.7), "res": "wax"},
}

# --- Объекты мира, которые можно добыть -------------------------------------
# time — секунд на добычу (не больше MAX_ACTION_TIME), drops — что выпадает.
# Объекты с time = 0 — просто декор (трава, цветы), их нельзя добыть.
const PROPS := {
	"tree_oak": {"name": "Дуб", "kind": "tree", "time": 7.0, "drops": {"log": 5}, "radius": 1.6, "height": 6.5},
	"tree_birch": {"name": "Берёза", "kind": "tree", "time": 4.0, "drops": {"log": 3}, "radius": 1.1, "height": 6.0},
	"tree_pine": {"name": "Сосна", "kind": "tree", "time": 5.0, "drops": {"log": 4}, "radius": 1.3, "height": 7.0},
	"tree_snowpine": {"name": "Ель в снегу", "kind": "tree", "time": 6.0, "drops": {"log": 4}, "radius": 1.3, "height": 6.5},
	"tree_maple": {"name": "Клён", "kind": "tree", "time": 6.0, "drops": {"log": 4}, "radius": 1.5, "height": 6.0},
	"tree_dead": {"name": "Сухое дерево", "kind": "tree", "time": 3.0, "drops": {"log": 2}, "radius": 0.8, "height": 4.0},
	"rock": {"name": "Валун", "kind": "rock", "time": 6.0, "drops": {"stone": 4}, "radius": 1.2, "height": 1.4},
	"clay": {"name": "Залежь глины", "kind": "mound", "time": 5.0, "drops": {"clay": 3}, "radius": 1.1, "height": 0.6, "max_height": 5.0},
	"sand": {"name": "Песчаная куча", "kind": "mound", "time": 3.0, "drops": {"sand": 4}, "radius": 1.1, "height": 0.8},
	"ore_coal": {"name": "Угольная жила", "kind": "rock", "time": 9.0, "drops": {"coal": 3}, "radius": 1.2, "height": 1.4},
	"ore_copper": {"name": "Медная жила", "kind": "rock", "time": 12.0, "drops": {"copper_ore": 3}, "radius": 1.2, "height": 1.4},
	"ore_iron": {"name": "Железная жила", "kind": "rock", "time": 15.0, "drops": {"iron_ore": 3}, "radius": 1.2, "height": 1.4},
	"bush": {"name": "Куст", "kind": "decor", "time": 0.0},
	"grass": {"name": "Трава", "kind": "decor", "time": 0.0},
	"flowers": {"name": "Цветы", "kind": "decor", "time": 0.0},
}

# --- Рецепты мастерских ------------------------------------------------------
# station — здание, которое должно быть построено, чтобы рецепт был доступен.
const RECIPES := {
	"plank": {"name": "Доски", "in": {"log": 2}, "out": {"plank": 4}, "time": 4.0, "station": "sawmill"},
	"stone_block": {"name": "Тёсаный камень", "in": {"stone": 3}, "out": {"stone_block": 2}, "time": 6.0, "station": "stonemason"},
	"brick": {"name": "Кирпич", "in": {"clay": 3, "coal": 1}, "out": {"brick": 4}, "time": 8.0, "station": "kiln"},
	"charcoal": {"name": "Древесный уголь", "in": {"log": 3}, "out": {"coal": 2}, "time": 8.0, "station": "kiln"},
	"glass": {"name": "Стекло", "in": {"sand": 4, "coal": 1}, "out": {"glass": 2}, "time": 10.0, "station": "glassworks"},
	"iron_ingot": {"name": "Железо", "in": {"iron_ore": 2, "coal": 1}, "out": {"iron_ingot": 1}, "time": 12.0, "station": "smithy"},
	"copper_ingot": {"name": "Медь", "in": {"copper_ore": 2, "coal": 1}, "out": {"copper_ingot": 1}, "time": 10.0, "station": "smithy"},
	"leather": {"name": "Кожа", "in": {"hide": 2}, "out": {"leather": 1}, "time": 8.0, "station": "tannery"},
	"cloth": {"name": "Ткань", "in": {"wool": 3}, "out": {"cloth": 1}, "time": 9.0, "station": "weaver"},
}

# --- Здания ------------------------------------------------------------------
# Внешний вид каждого здания описан в scripts/building/blueprints.gd.
const BUILDING_CATEGORIES := {
	"production": "Мастерские",
	"housing": "Жильё",
	"special": "Особые",
	"defense": "Оборона",
}

const BUILDINGS := {
	# Мастерские: открывают рецепты. Порядок — это и есть дерево развития.
	"sawmill": {"name": "Лесопилка", "category": "production", "time": 8.0,
		"cost": {"log": 10, "stone": 4}, "desc": "Распиливает брёвна на доски."},
	"stonemason": {"name": "Каменотёсня", "category": "production", "time": 10.0,
		"cost": {"plank": 8, "stone": 10, "log": 4}, "desc": "Обтёсывает камень в блоки."},
	"kiln": {"name": "Печь для обжига", "category": "production", "time": 12.0,
		"cost": {"stone": 14, "clay": 6, "plank": 4}, "desc": "Обжигает кирпич и выжигает древесный уголь."},
	"tannery": {"name": "Дубильня", "category": "production", "time": 10.0,
		"cost": {"plank": 8, "log": 6}, "desc": "Выделывает кожу из шкур."},
	"weaver": {"name": "Ткацкая", "category": "production", "time": 12.0,
		"cost": {"plank": 12, "stone": 6}, "desc": "Ткёт ткань из шерсти."},
	"glassworks": {"name": "Стекловарня", "category": "production", "time": 16.0,
		"cost": {"brick": 12, "stone_block": 6, "plank": 6}, "desc": "Варит стекло из песка."},
	"smithy": {"name": "Кузница", "category": "production", "time": 18.0,
		"cost": {"stone_block": 10, "brick": 8, "plank": 8, "leather": 2}, "desc": "Плавит железо и медь."},
	# Жильё
	"hut": {"name": "Хижина", "category": "housing", "time": 6.0,
		"cost": {"log": 12}, "desc": "Простой сруб из брёвен."},
	"wood_house": {"name": "Деревянный дом", "category": "housing", "time": 12.0,
		"cost": {"plank": 16, "log": 6, "stone": 4}, "desc": "Дощатый дом на каменном основании."},
	"stone_house": {"name": "Каменный дом", "category": "housing", "time": 18.0,
		"cost": {"stone_block": 16, "plank": 8, "glass": 2}, "desc": "Крепкий дом из тёсаного камня."},
	"brick_house": {"name": "Кирпичный дом", "category": "housing", "time": 20.0,
		"cost": {"brick": 20, "stone_block": 4, "plank": 6, "glass": 4}, "desc": "Дом под черепичной крышей."},
	"barn": {"name": "Амбар", "category": "housing", "time": 15.0,
		"cost": {"plank": 18, "log": 8, "stone": 4}, "desc": "Большой амбар для запасов."},
	"tent": {"name": "Шатёр", "category": "housing", "time": 6.0,
		"cost": {"leather": 6, "log": 4}, "desc": "Кожаный шатёр на жердях."},
	# Особые
	"well": {"name": "Колодец", "category": "special", "time": 6.0,
		"cost": {"stone": 8, "plank": 4, "iron_ingot": 1}, "desc": "Каменный колодец с воротом."},
	"market": {"name": "Торговая лавка", "category": "special", "time": 8.0,
		"cost": {"plank": 8, "log": 2, "cloth": 3}, "desc": "Прилавок под тканевым навесом."},
	"chapel": {"name": "Деревянная часовня", "category": "special", "time": 20.0,
		"cost": {"log": 16, "plank": 20, "wax": 2}, "desc": "Целиком деревянная часовня."},
	"church": {"name": "Каменная церковь", "category": "special", "time": 30.0,
		"cost": {"stone_block": 30, "plank": 12, "glass": 8, "copper_ingot": 4, "wax": 4},
		"desc": "Каменный храм с медным куполом и витражами."},
	"windmill": {"name": "Ветряная мельница", "category": "special", "time": 25.0,
		"cost": {"stone_block": 10, "plank": 20, "log": 4, "cloth": 6}, "desc": "Мельница с тканевыми крыльями."},
	# Оборона
	"cannon": {"name": "Пушка", "category": "defense", "time": 12.0,
		"cost": {"iron_ingot": 6, "plank": 4, "log": 2}, "desc": "Чугунная пушка на лафете."},
	"watchtower": {"name": "Сторожевая башня", "category": "defense", "time": 20.0,
		"cost": {"stone_block": 20, "plank": 8, "log": 6}, "desc": "Каменная башня с деревянным верхом."},
	"palisade": {"name": "Частокол", "category": "defense", "time": 2.0,
		"cost": {"log": 3}, "desc": "Секция забора из заострённых брёвен."},
}

# --- Сундуки -----------------------------------------------------------------
# Животные ресурсы появляются только здесь. Чем дальше от старта, тем чаще
# попадаются редкие сундуки (см. WorldGen.roll_chest_rarity).
const CHEST_RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]

const CHESTS := {
	"common": {"name": "Обычный сундук", "weight": 60.0, "color": Color(0.85, 0.85, 0.8), "open_time": 1.5,
		"loot": [["hide", 1, 2, 0.8], ["wool", 1, 3, 0.8], ["wax", 1, 1, 0.3], ["log", 2, 5, 0.5]]},
	"uncommon": {"name": "Необычный сундук", "weight": 25.0, "color": Color(0.4, 0.9, 0.4), "open_time": 2.0,
		"loot": [["hide", 2, 3, 1.0], ["wool", 2, 4, 1.0], ["wax", 1, 2, 0.6], ["coal", 2, 4, 0.4]]},
	"rare": {"name": "Редкий сундук", "weight": 10.0, "color": Color(0.35, 0.6, 1.0), "open_time": 2.5,
		"loot": [["hide", 3, 5, 1.0], ["wool", 3, 6, 1.0], ["wax", 2, 3, 0.8], ["iron_ingot", 1, 2, 0.5]]},
	"epic": {"name": "Эпический сундук", "weight": 4.0, "color": Color(0.72, 0.4, 1.0), "open_time": 3.0,
		"loot": [["hide", 5, 8, 1.0], ["wool", 5, 8, 1.0], ["wax", 3, 5, 1.0], ["glass", 2, 4, 0.6]]},
	"legendary": {"name": "Легендарный сундук", "weight": 1.0, "color": Color(1.0, 0.78, 0.25), "open_time": 3.5,
		"loot": [["hide", 8, 12, 1.0], ["wool", 8, 12, 1.0], ["wax", 5, 8, 1.0], ["copper_ingot", 3, 5, 0.8]]},
}


func res_name(id: String) -> String:
	return RESOURCES[id]["name"] if RESOURCES.has(id) else id


func res_color(id: String) -> Color:
	return RESOURCES[id]["color"] if RESOURCES.has(id) else Color.WHITE


## "4 Доски, 2 Камень"
func cost_text(cost: Dictionary, separator := ", ") -> String:
	var parts: PackedStringArray = []
	for id: String in cost:
		parts.append("%d %s" % [cost[id], res_name(id)])
	return separator.join(parts)


func recipes_for_station(station: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in RECIPES:
		if RECIPES[id]["station"] == station:
			result.append(id)
	return result


func roll_chest_loot(rarity: String, rng: RandomNumberGenerator) -> Dictionary:
	var loot := {}
	for entry: Array in CHESTS[rarity]["loot"]:
		if rng.randf() <= float(entry[3]):
			loot[entry[0]] = rng.randi_range(entry[1], entry[2])
	if loot.is_empty():
		var first: Array = CHESTS[rarity]["loot"][0]
		loot[first[0]] = first[1]
	return loot
