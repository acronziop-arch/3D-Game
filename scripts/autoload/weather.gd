extends Node
## Время суток, времена года и погода — логика и плавные переходы.
## Как это выглядит (свет, небо, дождь, снег) — scripts/world/atmosphere.gd.
## Связки погоды: дождь всегда с тучами и ветром, гроза — ливень с молниями,
## метель — снег с сильным ветром и туманом. Влага и снег копятся постепенно
## и так же постепенно сходят.

signal weather_changed(id: String)
signal season_changed(index: int)

const GD := preload("res://scripts/autoload/game_data.gd")
const SEASONS := GD.SEASONS
const WEATHERS := GD.WEATHERS
const SEASON_WEIGHTS := GD.SEASON_WEIGHTS

## Часы суток (0..24) и счётчик дней.
var hour := 9.0
var day := 0
## Положение в году: 0 — начало весны, 1 — лето, 2 — осень, 3 — зима, 4 — снова весна.
var season_t := 1.3
var weather := "clear"
var weather_left := 4.0

# Сглаженные значения — то, что видно на экране прямо сейчас.
var clouds := 0.12
var overcast := 0.0
var wind := 0.18
var rain := 0.0
var snow := 0.0
var fog := 0.0
var storm := 0.0
var wind_dir := Vector2(1.0, 0.35).normalized()
var wetness := 0.0
var snow_cover := 0.0
## Лёд на озёрах: нарастает зимой, тает весной.
var ice := 0.0

var _wind_angle := 0.33

## Часы для режимов «Только день» и «Только ночь».
const DAY_HOUR := 12.5
const NIGHT_HOUR := 23.5
## За сколько секунд погода сама сменяется на новую (режим «Авто»): медленно,
## как в жизни, без ускорения.
const WEATHER_BLEND := 22.0
var _last_season := -1


func season_index() -> int:
	return int(floorf(season_t)) % 4


func season_name() -> String:
	return SEASONS[season_index()]["name"]


func weather_name() -> String:
	return WEATHERS[weather]["name"]


func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]


## 0 — глубокая ночь, 1 — день.
func daylight() -> float:
	return smoothstep(-0.12, 0.22, sin((hour - 6.0) / 12.0 * PI))


func _process(delta: float) -> void:
	var hours_per_sec := 24.0 / (float(Settings.get_value("day_minutes")) * 60.0)
	_advance_time(delta, hours_per_sec)
	_advance_season(delta, hours_per_sec)
	_advance_weather(delta, hours_per_sec)


func _advance_time(delta: float, hours_per_sec: float) -> void:
	match Settings.get_value("time_mode"):
		"day":
			hour = DAY_HOUR
		"night":
			hour = NIGHT_HOUR
		_:
			hour += delta * hours_per_sec
			if hour >= 24.0:
				hour -= 24.0
				day += 1


func _advance_season(delta: float, hours_per_sec: float) -> void:
	var mode: String = Settings.get_value("season_mode")
	if mode == "auto":
		season_t = fposmod(season_t + delta * hours_per_sec / 24.0 / float(Settings.get_value("season_days")), 4.0)
	else:
		season_t = _season_target(mode, season_t)
	if season_index() != _last_season:
		_last_season = season_index()
		season_changed.emit(_last_season)


## Середина выбранного сезона (если уже внутри него — остаёмся на месте).
func _season_target(mode: String, current: float) -> float:
	for i in SEASONS.size():
		if SEASONS[i]["id"] == mode:
			return current if int(floorf(current)) % 4 == i and fmod(current, 1.0) > 0.3 else i + 0.55
	return current


func _advance_weather(delta: float, hours_per_sec: float) -> void:
	var mode: String = Settings.get_value("weather_mode")
	if mode != "auto" and WEATHERS.has(mode):
		_set_weather(mode)
	else:
		weather_left -= delta * hours_per_sec
		if weather_left <= 0.0:
			weather_left = randf_range(2.0, 6.0)
			_set_weather(_pick_weather())
	var target: Dictionary = WEATHERS[weather]
	var k := 1.0 - exp(-delta / WEATHER_BLEND)
	clouds = lerpf(clouds, target["clouds"], k)
	overcast = lerpf(overcast, target["overcast"], k)
	wind = lerpf(wind, target["wind"], k)
	rain = lerpf(rain, target["rain"], k)
	snow = lerpf(snow, target["snow"], k)
	fog = lerpf(fog, target["fog"], k)
	storm = lerpf(storm, target["storm"], k)
	# Ветер медленно меняет направление.
	_wind_angle += sin(Time.get_ticks_msec() * 0.00007) * delta * 0.03
	wind_dir = Vector2(cos(_wind_angle), sin(_wind_angle))
	# Влага копится под дождём и сохнет потом; снег так же копится и тает не зимой.
	wetness = move_toward(wetness, 1.0 if rain > 0.15 else 0.0, delta * (rain / 25.0 if rain > 0.15 else (0.5 + daylight()) / 110.0))
	var keep_snow := winter_amount() * 0.75
	var snow_target := 1.0 if snow > 0.15 else keep_snow
	var snow_rate := snow / 45.0 if snow > 0.15 else 1.0 / 80.0
	snow_cover = move_toward(snow_cover, snow_target, delta * snow_rate)
	ice = move_toward(ice, _ice_target(), delta / 90.0)


## Озёра замерзают зимой (и немного — под толстым снегом).
func _ice_target() -> float:
	return clampf(winter_amount() * 1.2 + snow_cover * 0.35 - 0.2, 0.0, 1.0)


## Мгновенно приводит мир к выбранным в настройках времени, сезону и погоде.
## Смену прячет шторка в интерфейсе (WorldWipe), поэтому ничего не «проматывается».
func snap_to_settings() -> void:
	match Settings.get_value("time_mode"):
		"day":
			hour = DAY_HOUR
		"night":
			hour = NIGHT_HOUR
	var season_mode: String = Settings.get_value("season_mode")
	if season_mode != "auto":
		season_t = _season_target(season_mode, season_t)
	var mode: String = Settings.get_value("weather_mode")
	if mode != "auto" and WEATHERS.has(mode):
		_set_weather(mode)
	var target: Dictionary = WEATHERS[weather]
	clouds = target["clouds"]
	overcast = target["overcast"]
	wind = target["wind"]
	rain = target["rain"]
	snow = target["snow"]
	fog = target["fog"]
	storm = target["storm"]
	wetness = 0.8 if rain > 0.15 else minf(wetness, 0.25)
	if snow > 0.15:
		snow_cover = 0.9
	else:
		snow_cover = winter_amount() * 0.75
	ice = _ice_target()


func _set_weather(id: String) -> void:
	if weather == id:
		return
	weather = id
	weather_changed.emit(id)


func _pick_weather() -> String:
	var table: Dictionary = SEASON_WEIGHTS[season_index()]
	var total := 0.0
	for id: String in table:
		total += table[id]
	var r := randf() * total
	for id: String in table:
		r -= table[id]
		if r <= 0.0:
			return id
	return "clear"


# --- Сезонные кривые (0..1) для шейдеров --------------------------------------------

## Сколько листвы на деревьях: весной отрастает, поздней осенью облетает.
func leaf_amount() -> float:
	var s := season_t
	if s < 0.45:
		return smoothstep(0.0, 0.45, s)
	if s < 2.45:
		return 1.0
	if s < 3.05:
		return 1.0 - smoothstep(2.45, 3.05, s)
	return 0.0


## Насколько листва и трава пожелтели.
func autumn_amount() -> float:
	return smoothstep(1.75, 2.4, season_t) * (1.0 - smoothstep(3.75, 3.99, season_t))


func spring_amount() -> float:
	return 1.0 - smoothstep(0.25, 0.95, season_t) if season_t < 1.0 else 0.0


func winter_amount() -> float:
	return smoothstep(2.95, 3.15, season_t) * (1.0 - smoothstep(3.8, 3.97, season_t))


func save_state() -> Dictionary:
	return {"hour": hour, "day": day, "season_t": season_t, "weather": weather, "snow_cover": snow_cover, "wetness": wetness,
		"ice": ice}


func load_state(state: Dictionary) -> void:
	hour = state.get("hour", hour)
	day = state.get("day", day)
	season_t = state.get("season_t", season_t)
	weather = state.get("weather", weather)
	snow_cover = state.get("snow_cover", snow_cover)
	wetness = state.get("wetness", wetness)
	ice = state.get("ice", _ice_target())
