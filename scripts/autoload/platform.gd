extends Node
## Где запущена игра: ПК, телефон или планшет — в приложении или в браузере.
## Отсюда берутся способ управления (мышь или касания), размер интерфейса,
## безопасная зона экрана (вырез, «чёлка» и полоска «домой» на iPhone) и облегчённые
## настройки графики для телефонов и браузера.
## iPhone — главный мобильный ориентир: размеры интерфейса подобраны в пунктах iOS.
##
## Проверка на ПК: `-- --phone` или `-- --tablet` включают сенсорный режим
## (мышь превращается в касания), `--notch` добавляет поля как у iPhone с вырезом.

signal layout_changed

enum Form { DESKTOP, PHONE, TABLET }

## Высота интерфейса в его единицах. На iPhone в альбомной ориентации это почти
## один пункт iOS на единицу: кнопки получаются не меньше 44 pt, текст — 13–17 pt.
const PHONE_UI_HEIGHT := 420
const TABLET_UI_HEIGHT := 640
## Отступ от краёв экрана, если вырезов нет.
const EDGE := 14.0

var form := Form.DESKTOP
## Управление касаниями (на ПК мышь при этом имитирует один палец).
var is_touch := false
var is_ios := false
var is_android := false
## Браузерная версия (WebGL 2, без потоков).
var is_web := false

var _emulated_notch := false
var _margins := {"left": EDGE, "top": EDGE, "right": EDGE, "bottom": EDGE}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	is_ios = OS.has_feature("ios")
	is_android = OS.has_feature("android")
	is_web = OS.has_feature("web")
	# Safari на iPad представляется macOS — узнаём его по сенсорному экрану.
	var web_mobile := OS.has_feature("web_ios") or OS.has_feature("web_android") \
		or (OS.has_feature("web_macos") and DisplayServer.is_touchscreen_available())
	if OS.has_feature("mobile") or is_ios or is_android or web_mobile:
		form = Form.TABLET if _looks_like_tablet() else Form.PHONE
	if "--phone" in args:
		form = Form.PHONE
	elif "--tablet" in args:
		form = Form.TABLET
	is_touch = form != Form.DESKTOP or "--touch" in args
	_emulated_notch = "--notch" in args


func _ready() -> void:
	if is_touch and not (OS.has_feature("mobile") or is_web):
		# Проверка на ПК: мышь работает как один палец.
		Input.emulate_touch_from_mouse = true
	if is_mobile():
		# 60 кадров хватает с запасом, а iPhone с ProMotion не греется на 120 Гц.
		Engine.max_fps = 60
	get_tree().root.size_changed.connect(_update_layout)
	_update_layout()


func is_mobile() -> bool:
	return form != Form.DESKTOP


func is_phone() -> bool:
	return form == Form.PHONE


## Планшет — iPad по модели, иначе — если экран не вытянутый (4:3, 3:2) или большой.
static func _looks_like_tablet() -> bool:
	if OS.has_feature("ios"):
		return OS.get_model_name().begins_with("iPad")
	# Safari на iPhone честно называет iOS, а на iPad — macOS.
	if OS.has_feature("web_ios"):
		return false
	if OS.has_feature("web_macos"):
		return true
	var size := Vector2(DisplayServer.screen_get_size())
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	var ratio := maxf(size.x, size.y) / maxf(minf(size.x, size.y), 1.0)
	# В браузере DPI выдуман, поэтому там судим только по пропорциям экрана.
	var dpi := 0.0 if OS.has_feature("web") else float(DisplayServer.screen_get_dpi())
	var diagonal := size.length() / dpi if dpi > 0.0 else 0.0
	return ratio < 1.6 or diagonal > 7.5


## Уровень качества графики для «Авто» при запуске. Браузер получает те же уровни,
## что и приложение; если кадры не успевают, main.gd понижает уровень на ходу.
func auto_quality() -> String:
	if is_mobile():
		return "medium"
	return "high" if is_web else "ultra"


# --- Интерфейс --------------------------------------------------------------------------------------

func _update_layout() -> void:
	var root := get_tree().root
	if is_mobile():
		var window := Vector2(root.size)
		var target := PHONE_UI_HEIGHT if is_phone() else TABLET_UI_HEIGHT
		var aspect := maxf(window.x / maxf(window.y, 1.0), 1.0)
		root.content_scale_size = Vector2i(roundi(target * aspect), target)
	_margins = _safe_margins()
	layout_changed.emit()


## Сколько единиц интерфейса на один пиксель экрана.
func ui_scale() -> float:
	var root := get_tree().root
	var visible := root.get_visible_rect().size
	return visible.y / maxf(float(root.size.y), 1.0)


## Поля безопасной зоны в единицах интерфейса: {left, top, right, bottom}.
func safe_margins() -> Dictionary:
	return _margins


func _safe_margins() -> Dictionary:
	var m := {"left": EDGE, "top": EDGE, "right": EDGE, "bottom": EDGE}
	if not is_mobile():
		return m
	var k := ui_scale()
	if _emulated_notch:
		# Как у iPhone с вырезом в альбомной ориентации: 47 pt по бокам, 21 pt снизу.
		var visible := get_tree().root.get_visible_rect().size
		var pt := visible.y / 390.0
		m["left"] = 47.0 * pt
		m["right"] = 47.0 * pt
		m["bottom"] = maxf(EDGE, 21.0 * pt)
		return m
	# В браузере холст занимает весь экран (viewport-fit=cover), а вырез и полоску
	# «домой» сообщает CSS: env(safe-area-inset-*), в CSS-пикселях.
	if is_web:
		return _web_safe_margins(m)
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return m
	# Ограничиваем поля: странные значения не должны увести панели за край экрана.
	var visible := get_tree().root.get_visible_rect().size
	m["left"] = clampf(safe.position.x * k, EDGE, visible.x * 0.12)
	m["top"] = clampf(safe.position.y * k, EDGE, visible.y * 0.15)
	m["right"] = clampf((screen.x - safe.end.x) * k, EDGE, visible.x * 0.12)
	m["bottom"] = clampf((screen.y - safe.end.y) * k, EDGE, visible.y * 0.15)
	return m


const _SAFE_AREA_JS := """(function () {
	var d = document.getElementById('safe-probe');
	if (!d) {
		d = document.createElement('div');
		d.id = 'safe-probe';
		d.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;pointer-events:none;'
			+ 'padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
		document.body.appendChild(d);
	}
	var s = getComputedStyle(d);
	return [s.paddingLeft, s.paddingTop, s.paddingRight, s.paddingBottom].map(function (v) { return parseFloat(v) || 0; })
		.concat([window.innerHeight]).join(',');
})()"""


func _web_safe_margins(m: Dictionary) -> Dictionary:
	var raw: Variant = JavaScriptBridge.eval(_SAFE_AREA_JS)
	if not (raw is String):
		return m
	var v := (raw as String).split_floats(",")
	if v.size() < 5 or v[4] <= 0.0:
		return m
	var visible := get_tree().root.get_visible_rect().size
	# Единиц интерфейса на один CSS-пиксель.
	var k := visible.y / v[4]
	m["left"] = clampf(maxf(EDGE, v[0] * k), EDGE, visible.x * 0.12)
	m["top"] = clampf(maxf(EDGE, v[1] * k), EDGE, visible.y * 0.15)
	m["right"] = clampf(maxf(EDGE, v[2] * k), EDGE, visible.x * 0.12)
	m["bottom"] = clampf(maxf(EDGE, v[3] * k), EDGE, visible.y * 0.15)
	return m


## Лёгкий отклик вибрацией (на iPhone — Taptic Engine).
func haptic(strength := 0.5) -> void:
	if is_mobile() and Settings.get_value("haptics"):
		Input.vibrate_handheld(int(lerpf(12.0, 40.0, strength)), clampf(strength, 0.1, 1.0))


# --- Графика --------------------------------------------------------------------------------------

## Доля капель дождя и снежинок.
func particle_scale() -> float:
	return [0.35, 0.55, 0.8, 1.0][Settings.quality_level()]


## Разрешение отражений на воде относительно окна (в пикселях).
func reflection_scale() -> float:
	return [0.3, 0.35, 0.45, 0.5][Settings.quality_level()]


## Дальность мелочи (папоротник, тростник, цветы), м. На телефоне ближе: дальше
## 60–80 м этих мелочей на маленьком экране не разглядеть.
func decor_distance() -> float:
	var grass := float(Settings.get_value("grass_distance"))
	return maxf(45.0, grass * 0.8) if is_mobile() else maxf(70.0, grass * 1.4)


## Дальность прорисовки в чанках. На телефоне — не больше 7 (224 м): дальше
## туман, а каждый лишний круг чанков — сотни объектов и вызовов отрисовки.
func view_radius() -> int:
	var r := int(Settings.get_value("view_distance"))
	return mini(r, 7) if is_mobile() else r


## Дальность кустов, мелких камней и руды, м: дальше они меньше пикселя-двух.
func detail_distance() -> float:
	return maxf(90.0 if is_mobile() else 110.0, float(Settings.get_value("grass_distance")) * (1.2 if is_mobile() else 1.6))


## С какого расстояния, м, деревья и камни чанка рисуются упрощённо (общими областями).
func prop_lod_distance() -> float:
	return 90.0 if is_mobile() else 120.0
