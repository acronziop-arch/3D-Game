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

# Ресурсы, которые всегда видны в левом верхнем углу. Остальные — в списке «…».
const MAIN_RESOURCES := ["log", "plank", "stone", "stone_block", "brick", "glass"]

# --- Материалы деталей зданий ------------------------------------------------
# res — какой ресурс обязан быть в стоимости здания, если деталь из этого материала.
const MATERIALS := {
	"log": {"color": Color(0.52, 0.34, 0.2), "res": "log"},
	"log_dark": {"color": Color(0.38, 0.24, 0.14), "res": "log"},
	"plank": {"color": Color(0.8, 0.55, 0.31), "res": "plank"},
	"plank_dark": {"color": Color(0.56, 0.37, 0.22), "res": "plank"},
	"stone": {"color": Color(0.56, 0.55, 0.54), "res": "stone"},
	"stone_block": {"color": Color(0.6, 0.58, 0.58), "res": "stone_block"},
	"slate": {"color": Color(0.46, 0.46, 0.49), "res": "stone_block"},
	"clay": {"color": Color(0.72, 0.46, 0.32), "res": "clay"},
	"brick": {"color": Color(0.68, 0.34, 0.25), "res": "brick"},
	"roof_tile": {"color": Color(0.64, 0.26, 0.18), "res": "brick"},
	"glass": {"color": Color(0.38, 0.58, 0.85), "res": "glass"},
	"iron": {"color": Color(0.26, 0.27, 0.3), "res": "iron_ingot"},
	"copper": {"color": Color(0.36, 0.66, 0.58), "res": "copper_ingot"},
	"cloth": {"color": Color(0.95, 0.9, 0.8), "res": "cloth"},
	"leather": {"color": Color(0.64, 0.45, 0.28), "res": "leather"},
	"wax": {"color": Color(1.0, 0.93, 0.75), "res": "wax"},
}

# --- Объекты мира, которые можно добыть -------------------------------------
# time — секунд на добычу (не больше MAX_ACTION_TIME), drops — что выпадает.
# Объекты с time = 0 — просто декор (трава, цветы, кусты), их нельзя добыть.
# place: "land" (по умолчанию), "shallow" — мелководье у берега, "float" — на воде.
const PROPS := {
	"tree_oak": {"name": "Дуб", "kind": "tree", "time": 7.0, "drops": {"log": 5}, "radius": 1.7, "height": 7.0},
	"tree_birch": {"name": "Берёза", "kind": "tree", "time": 4.0, "drops": {"log": 3}, "radius": 1.2, "height": 7.0},
	"tree_pine": {"name": "Сосна", "kind": "tree", "time": 5.0, "drops": {"log": 4}, "radius": 1.4, "height": 7.6},
	"tree_spruce": {"name": "Ель", "kind": "tree", "time": 5.0, "drops": {"log": 4}, "radius": 1.6, "height": 7.2},
	"tree_snowpine": {"name": "Ель в снегу", "kind": "tree", "time": 6.0, "drops": {"log": 4}, "radius": 1.6, "height": 7.2},
	"tree_maple": {"name": "Клён", "kind": "tree", "time": 6.0, "drops": {"log": 4}, "radius": 1.6, "height": 6.5},
	"tree_dead": {"name": "Сухое дерево", "kind": "tree", "time": 3.0, "drops": {"log": 2}, "radius": 0.9, "height": 4.5},
	"rock": {"name": "Валун", "kind": "rock", "time": 6.0, "drops": {"stone": 4}, "radius": 1.3, "height": 1.3},
	"clay": {"name": "Залежь глины", "kind": "mound", "time": 5.0, "drops": {"clay": 3}, "radius": 1.2, "height": 0.6, "max_height": 5.0},
	"sand": {"name": "Песчаная куча", "kind": "mound", "time": 3.0, "drops": {"sand": 4}, "radius": 1.2, "height": 0.7},
	"ore_coal": {"name": "Угольная жила", "kind": "rock", "time": 9.0, "drops": {"coal": 3}, "radius": 1.3, "height": 1.4},
	"ore_copper": {"name": "Медная жила", "kind": "rock", "time": 12.0, "drops": {"copper_ore": 3}, "radius": 1.3, "height": 1.4},
	"ore_iron": {"name": "Железная жила", "kind": "rock", "time": 15.0, "drops": {"iron_ore": 3}, "radius": 1.3, "height": 1.4},
	"bush": {"name": "Куст", "kind": "decor", "time": 0.0},
	"grass": {"name": "Трава", "kind": "decor", "time": 0.0},
	"flowers": {"name": "Цветы", "kind": "decor", "time": 0.0},
	"reeds": {"name": "Камыш", "kind": "decor", "time": 0.0, "place": "shallow"},
	"lily": {"name": "Кувшинки", "kind": "decor", "time": 0.0, "place": "float"},
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
# Внешний вид каждого здания — модель models/buildings/<id>.glb
# (её создаёт tools/export_models.gd из scripts/models/building_factory.gd).
# place: "land" — только на суше или на настиле, "water" — только на воде,
#        "bridge" — концы на берегах, середина над водой.
const BUILDING_CATEGORIES := {
	"production": "Мастерские",
	"housing": "Жильё",
	"special": "Особые",
	"defense": "Оборона",
	"water": "На воде",
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
		"cost": {"plank": 16, "log": 6, "stone": 4}, "desc": "Дощатый дом со ставнями на каменном цоколе."},
	"stone_house": {"name": "Каменный дом", "category": "housing", "time": 18.0,
		"cost": {"stone_block": 16, "plank": 8, "glass": 2}, "desc": "Крепкий дом из тёсаного камня."},
	"brick_house": {"name": "Кирпичный дом", "category": "housing", "time": 20.0,
		"cost": {"brick": 20, "stone_block": 4, "plank": 6, "glass": 4}, "desc": "Двухэтажный дом под черепицей."},
	"barn": {"name": "Амбар", "category": "housing", "time": 15.0,
		"cost": {"plank": 18, "log": 8, "stone": 4}, "desc": "Большой амбар для запасов."},
	"tent": {"name": "Шатёр", "category": "housing", "time": 6.0,
		"cost": {"leather": 6, "log": 4}, "desc": "Кожаный шатёр на жердях."},
	# Особые
	"well": {"name": "Колодец", "category": "special", "time": 6.0,
		"cost": {"stone": 8, "plank": 4, "iron_ingot": 1}, "desc": "Каменный колодец с воротом."},
	"market": {"name": "Торговая лавка", "category": "special", "time": 8.0,
		"cost": {"plank": 8, "log": 2, "cloth": 3}, "desc": "Прилавок под полосатым навесом."},
	"chapel": {"name": "Деревянная часовня", "category": "special", "time": 20.0,
		"cost": {"log": 16, "plank": 20, "wax": 2}, "desc": "Целиком деревянная часовня со звонницей."},
	"church": {"name": "Каменная церковь", "category": "special", "time": 30.0,
		"cost": {"stone_block": 30, "plank": 12, "glass": 8, "copper_ingot": 4, "wax": 4},
		"desc": "Храм с медными куполами и витражами."},
	"windmill": {"name": "Ветряная мельница", "category": "special", "time": 25.0,
		"cost": {"stone_block": 12, "plank": 20, "log": 4, "cloth": 6, "glass": 2},
		"desc": "Каменная мельница. Крылья крутятся быстрее на ветру."},
	# Оборона
	"cannon": {"name": "Пушка", "category": "defense", "time": 12.0,
		"cost": {"iron_ingot": 6, "plank": 4, "log": 2}, "desc": "Чугунная пушка на лафете."},
	"watchtower": {"name": "Сторожевая башня", "category": "defense", "time": 20.0,
		"cost": {"stone_block": 20, "plank": 8, "log": 6}, "desc": "Каменная башня с деревянной площадкой."},
	"palisade": {"name": "Частокол", "category": "defense", "time": 2.0,
		"cost": {"log": 3}, "desc": "Секция забора из заострённых брёвен."},
	"keep": {"name": "Крепость", "category": "defense", "time": 30.0,
		"cost": {"stone_block": 40, "plank": 6, "glass": 6}, "desc": "Двухэтажная каменная крепость с зубцами."},
	# На воде
	"platform": {"name": "Деревянный настил", "category": "water", "time": 4.0, "place": "water",
		"cost": {"plank": 6, "log": 4}, "desc": "Блок 4×4 м на сваях. На нём можно строить, как на суше."},
	"bridge_wood": {"name": "Деревянный мост", "category": "water", "time": 10.0, "place": "bridge",
		"cost": {"plank": 14, "log": 8}, "desc": "Мост длиной 14 м: концы ставятся на берега."},
	"bridge_stone": {"name": "Каменный мост", "category": "water", "time": 18.0, "place": "bridge",
		"cost": {"stone_block": 24, "stone": 8}, "desc": "Арочный каменный мост длиной 14 м."},
}

# --- Погода и времена года ------------------------------------------------------
# Значения 0..1: облака, серость неба, ветер, дождь, снег, туман, гроза.
# Связки задаются прямо здесь: дождь всегда с тучами и ветром, гроза — ливень
# с молниями, метель — снег с ураганным ветром и туманом.
const SEASONS := [
	{"id": "spring", "name": "Весна"},
	{"id": "summer", "name": "Лето"},
	{"id": "autumn", "name": "Осень"},
	{"id": "winter", "name": "Зима"},
]

const WEATHERS := {
	"clear": {"name": "Ясно", "clouds": 0.12, "overcast": 0.0, "wind": 0.18, "rain": 0.0, "snow": 0.0, "fog": 0.0, "storm": 0.0},
	"cloudy": {"name": "Облачно", "clouds": 0.55, "overcast": 0.15, "wind": 0.32, "rain": 0.0, "snow": 0.0, "fog": 0.0, "storm": 0.0},
	"overcast": {"name": "Пасмурно", "clouds": 0.9, "overcast": 0.6, "wind": 0.3, "rain": 0.0, "snow": 0.0, "fog": 0.15, "storm": 0.0},
	"windy": {"name": "Ветрено", "clouds": 0.4, "overcast": 0.1, "wind": 0.92, "rain": 0.0, "snow": 0.0, "fog": 0.0, "storm": 0.0},
	"rain": {"name": "Дождь", "clouds": 0.88, "overcast": 0.65, "wind": 0.4, "rain": 0.65, "snow": 0.0, "fog": 0.25, "storm": 0.0},
	"storm": {"name": "Гроза", "clouds": 1.0, "overcast": 0.92, "wind": 0.95, "rain": 1.0, "snow": 0.0, "fog": 0.35, "storm": 1.0},
	"snow": {"name": "Снегопад", "clouds": 0.85, "overcast": 0.55, "wind": 0.25, "rain": 0.0, "snow": 0.7, "fog": 0.3, "storm": 0.0},
	"blizzard": {"name": "Метель", "clouds": 1.0, "overcast": 0.8, "wind": 1.0, "rain": 0.0, "snow": 1.0, "fog": 0.65, "storm": 0.0},
	"fog": {"name": "Туман", "clouds": 0.5, "overcast": 0.45, "wind": 0.05, "rain": 0.0, "snow": 0.0, "fog": 1.0, "storm": 0.0},
}

## Насколько часто бывает погода в каждом сезоне (режим «Авто»).
const SEASON_WEIGHTS := [
	{"clear": 3.0, "cloudy": 3.0, "rain": 3.0, "windy": 1.0, "fog": 1.5, "storm": 0.8, "overcast": 1.0},
	{"clear": 5.0, "cloudy": 2.5, "storm": 1.5, "rain": 1.0, "windy": 1.0},
	{"cloudy": 3.0, "overcast": 2.0, "rain": 3.0, "windy": 2.0, "fog": 2.0, "storm": 0.5, "clear": 1.5},
	{"clear": 2.0, "overcast": 2.0, "snow": 4.0, "blizzard": 1.5, "fog": 1.0, "cloudy": 1.0},
]

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
