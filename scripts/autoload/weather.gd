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

var _wind_angle := 0.33
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
			hour = _approach_hour(hour, 12.5, delta)
		"night":
			hour = _approach_hour(hour, 23.5, delta)
		_:
			hour += delta * hours_per_sec
			if hour >= 24.0:
				hour -= 24.0
				day += 1


## Плавно «прокручивает» часы к нужному времени, чтобы свет не прыгал.
static func _approach_hour(h: float, target: float, delta: float) -> float:
	var diff := fposmod(target - h, 24.0)
	if diff < 0.01:
		return target
	return fposmod(h + minf(diff, delta * 3.0), 24.0)


func _advance_season(delta: float, hours_per_sec: float) -> void:
	var mode: String = Settings.get_value("season_mode")
	if mode == "auto":
		season_t = fposmod(season_t + delta * hours_per_sec / 24.0 / float(Settings.get_value("season_days")), 4.0)
	else:
		var index := 0
		for i in SEASONS.size():
			if SEASONS[i]["id"] == mode:
				index = i
		var target := index + 0.55
		var diff := fposmod(target - season_t, 4.0)
		if diff > 0.005:
			season_t = fposmod(season_t + minf(diff, delta * 0.25), 4.0)
	if season_index() != _last_season:
		_last_season = season_index()
		season_changed.emit(_last_season)


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
	var k := 1.0 - exp(-delta / 6.0)
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
	return {"hour": hour, "day": day, "season_t": season_t, "weather": weather, "snow_cover": snow_cover, "wetness": wetness}


func load_state(state: Dictionary) -> void:
	hour = state.get("hour", hour)
	day = state.get("day", day)
	season_t = state.get("season_t", season_t)
	weather = state.get("weather", weather)
	snow_cover = state.get("snow_cover", snow_cover)
	wetness = state.get("wetness", wetness)
