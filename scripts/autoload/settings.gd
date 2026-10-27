extends Node
## Настройки игрока. Хранятся в user://settings.cfg и не зависят от сохранения мира.
##
## Качество графики: «Авто» при запуске подбирает уровень под устройство (Platform)
## и понижает его, если игра не успевает рисовать кадры (см. main.gd). Уровень —
## это набор значений (разрешение, тени, трава, дальность, отражения); если игрок
## меняет любое из них вручную, качество становится «Своё».

signal changed(key: String)

const PATH := "user://settings.cfg"
const DEFAULTS := {
	## normal — обычная игра, creative — творческий режим (см. GameMode).
	"game_mode": "normal",
	## auto — сутки идут сами; day — всегда день; night — всегда ночь.
	"time_mode": "auto",
	## Длина суток в реальных минутах.
	"day_minutes": 12.0,
	## auto или id погоды из Weather.WEATHERS (тогда погода не меняется).
	"weather_mode": "auto",
	## auto или spring / summer / autumn / winter.
	"season_mode": "auto",
	## Сколько суток длится один сезон в режиме auto.
	"season_days": 3.0,
	## auto, один из QUALITY_LEVELS или custom (значения ниже выставлены вручную).
	"quality": "auto",
	"reflections": true,
	## off / low / medium / high — у high мягкие тени с размытыми краями.
	"shadow_quality": "medium",
	"view_distance": 7,
	"fish": true,
	## Густота травы и цветов, 0..1 (1 — пучок на каждые 0,6 м).
	"grass": 0.8,
	## Дальность травы, м.
	"grass_distance": 70.0,
	## Разрешение 3D-картинки относительно экрана.
	"render_scale": 1.0,
	## Вибрация при действиях (телефоны).
	"haptics": true,
	## Не выращивать заново деревья и траву там, где игрок выровнял землю.
	"keep_cleared": true,
	## Браузер: auto — многопоточная сборка, если браузер её позволяет; off — обычная.
	## Само значение хранит страница (localStorage) — оно нужно ещё до запуска движка.
	"web_threads": "auto",
}

const QUALITY_LEVELS := ["low", "medium", "high", "ultra"]
const QUALITY_NAMES := {"low": "Низкое", "medium": "Среднее", "high": "Высокое", "ultra": "Максимум"}
const QUALITY_PRESETS := {
	"low": {"render_scale": 0.5, "shadow_quality": "off", "grass": 0.3, "grass_distance": 35.0,
		"view_distance": 4, "reflections": false},
	"medium": {"render_scale": 0.75, "shadow_quality": "low", "grass": 0.55, "grass_distance": 50.0,
		"view_distance": 5, "reflections": true},
	"high": {"render_scale": 0.9, "shadow_quality": "medium", "grass": 0.8, "grass_distance": 70.0,
		"view_distance": 7, "reflections": true},
	"ultra": {"render_scale": 1.0, "shadow_quality": "high", "grass": 1.0, "grass_distance": 100.0,
		"view_distance": 9, "reflections": true},
}

var values := {}
## Уровень, который сейчас выбран автоматически (при quality = auto).
var auto_level := ""
var _applying := false


func _ready() -> void:
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key: String in DEFAULTS:
			values[key] = cfg.get_value("settings", key, DEFAULTS[key])
		# Старые настройки: тени были просто «вкл/выкл».
		if cfg.has_section_key("settings", "shadows") and not cfg.has_section_key("settings", "shadow_quality"):
			values["shadow_quality"] = "medium" if cfg.get_value("settings", "shadows") else "off"
	var quality: String = values["quality"]
	if quality == "auto":
		auto_level = Platform.auto_quality()
		_apply_preset(auto_level, false)
	elif QUALITY_PRESETS.has(quality):
		_apply_preset(quality, false)


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if values.get(key) == value:
		return
	values[key] = value
	if key == "quality":
		if value == "auto":
			auto_level = Platform.auto_quality()
			_apply_preset(auto_level, true)
		elif QUALITY_PRESETS.has(value):
			_apply_preset(value, true)
	elif not _applying and QUALITY_PRESETS["low"].has(key) and values["quality"] != "custom":
		# Значение поменяли руками — это уже не готовый уровень.
		values["quality"] = "custom"
		changed.emit("quality")
	_save()
	changed.emit(key)


## Уровень качества, на который ориентируются мелочи (частицы, отражения).
func quality_level() -> int:
	var q: String = values["quality"]
	if q == "auto":
		q = auto_level
	var i := QUALITY_LEVELS.find(q)
	return i if i >= 0 else 2


## Авто: на ступень ниже, если игра не успевает. Возвращает новый уровень или "".
func lower_auto_quality() -> String:
	if values["quality"] != "auto":
		return ""
	var i := QUALITY_LEVELS.find(auto_level)
	if i <= 0:
		return ""
	auto_level = QUALITY_LEVELS[i - 1]
	_apply_preset(auto_level, true)
	_save()
	return auto_level


func _apply_preset(level: String, notify: bool) -> void:
	var preset: Dictionary = QUALITY_PRESETS[level]
	_applying = true
	for key: String in preset:
		if values.get(key) != preset[key]:
			values[key] = preset[key]
			if notify:
				changed.emit(key)
	_applying = false


func _save() -> void:
	var cfg := ConfigFile.new()
	for k: String in values:
		cfg.set_value("settings", k, values[k])
	cfg.save(PATH)
