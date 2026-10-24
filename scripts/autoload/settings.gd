extends Node
## Настройки игрока. Хранятся в user://settings.cfg и не зависят от сохранения мира.

signal changed(key: String)

const PATH := "user://settings.cfg"
const DEFAULTS := {
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
	"reflections": true,
	"shadows": true,
	"view_distance": 7,
	"fish": true,
	## Густота травы и листьев на земле, 0..1.
	"grass": 1.0,
	## Разрешение 3D-картинки относительно экрана (на телефоне меньше — ради плавности).
	"render_scale": 1.0,
	## Вибрация при действиях (телефоны).
	"haptics": true,
}

var values := {}


func _ready() -> void:
	values = DEFAULTS.duplicate()
	# На телефоне часть значений по умолчанию легче (дальность, разрешение, трава).
	values.merge(Platform.setting_defaults(), true)
	var defaults := values.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key: String in DEFAULTS:
			values[key] = cfg.get_value("settings", key, defaults[key])


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if values.get(key) == value:
		return
	values[key] = value
	var cfg := ConfigFile.new()
	for k: String in values:
		cfg.set_value("settings", k, values[k])
	cfg.save(PATH)
	changed.emit(key)
