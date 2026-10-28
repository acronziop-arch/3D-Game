class_name MapPanel
extends Control
## Большая карта: открывается нажатием на мини-карту. Листается пальцем или мышью,
## масштаб — щипком, колесом или кнопками «+» и «−». Нажатие на пустое место ставит
## метку (цвет и значок на выбор), нажатие на метку — изменить или удалить её.
## Окно метки — панель внизу карты: место метки остаётся видно над ней, а выбранные
## цвет и значок сразу показываются на карте. «Показать» переносит камеру к метке.

signal closed
signal markers_changed

## Сколько метров мира помещается в карту по высоте при первом открытии.
const MAP_METERS := 520.0
const MIN_METERS := 160.0
const MAX_METERS := 1800.0
const COLORS := ["#E05A4E", "#F09A3E", "#F2C94C", "#62B04E", "#4E8FD6", "#9B6BD8"]
const ICONS := ["flag", "home", "star", "castle", "tree", "pick", "heart", "camp"]
const ICON_NAMES := {"flag": "Флаг", "home": "Деревня", "star": "Звезда", "castle": "Крепость", "tree": "Лес",
	"pick": "Руда", "heart": "Любимое", "camp": "Лагерь"}
## Отступ окна метки от краёв карты — «окно в окне».
const EDITOR_INSET := 14.0

var map: Minimap
var camera_rig: CameraRig

var _panel: PanelContainer
var _editor: PanelContainer
var _hint: Label
var _here: Button
var _delete_button: Button
var _color_buttons: Array[Button] = []
var _icon_buttons: Array[Button] = []
var _icon_grid: GridContainer
var _edit_index := -1
var _edit_pos := Vector3.ZERO
var _edit_color := COLORS[0]
var _edit_icon := "flag"
var _dragging := false
var _moved := 0.0
## Пальцы на карте: индекс → точка (в координатах карты).
var _touches := {}
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO
## Жест одним пальцем: сколько он прошёл и было ли в жесте больше одного пальца.
var _touch_moved := 0.0
var _touch_multi := false
var _touch_start_msec := 0
var _pan_tween: Tween


func setup(chunk_manager: ChunkManager, rig: CameraRig, buildings: BuildingSystem) -> void:
	camera_rig = rig
	map.chunk_manager = chunk_manager
	map.camera_rig = rig
	map.building_system = buildings


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	modulate.a = 0.0
	var dim := ColorRect.new()
	dim.color = Color(0.18, 0.13, 0.09, 0.38)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.panel(22, 12))
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.add_child(UiStyle.icon_rect("map", 26))
	header.add_child(UiStyle.label("Карта", 20, UiStyle.TEXT, 800))
	var hint := UiStyle.label("Нажмите на карту, чтобы поставить метку", 12, UiStyle.MUTED, 700)
	_hint = hint
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(hint)
	var here := Button.new()
	_here = here
	here.text = "Метка здесь"
	here.icon = UiStyle.icon("marker_pin")
	here.add_theme_constant_override("icon_max_width", 20)
	here.custom_minimum_size = Vector2(0, 40)
	here.pressed.connect(func() -> void:
		var p := camera_rig.position
		_open_editor(-1, Vector3(p.x, p.y, p.z)))
	header.add_child(here)
	var back := Button.new()
	back.icon = UiStyle.icon("target")
	back.add_theme_constant_override("icon_max_width", 22)
	back.custom_minimum_size = Vector2(44, 40)
	back.tooltip_text = "К камере"
	back.pressed.connect(func() -> void: _pan_to(Vector2(camera_rig.position.x, camera_rig.position.z)))
	header.add_child(back)
	var close_btn := UiStyle.close_button()
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	box.add_child(header)
	map = Minimap.new()
	map.follow_camera = false
	map.view_meters = MAP_METERS
	map.corner_radius = 16.0
	map.mouse_filter = Control.MOUSE_FILTER_STOP
	map.gui_input.connect(_on_map_input)
	map.resized.connect(_place_editor)
	box.add_child(map)
	_build_zoom()
	_build_editor()
	Platform.layout_changed.connect(_fit)
	_fit.call_deferred()


## «+» и «−» в правом верхнем углу карты.
func _build_zoom() -> void:
	var zoom := VBoxContainer.new()
	zoom.add_theme_constant_override("separation", 6)
	zoom.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	zoom.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	zoom.offset_left = -54.0
	zoom.offset_right = -10.0
	zoom.offset_top = 10.0
	zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.add_child(zoom)
	for step: Array in [["plus", "Ближе", 1.0 / 1.6], ["minus", "Дальше", 1.6]]:
		var b := Button.new()
		b.icon = UiStyle.icon(step[0])
		b.tooltip_text = step[1]
		b.add_theme_constant_override("icon_max_width", 20)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(44, 44)
		b.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.BASE, 0.94), 14, 6, 2, UiStyle.BRAND, true))
		b.pressed.connect(func() -> void: _zoom_smooth(step[2]))
		zoom.add_child(b)


## Окно метки — внизу карты, чуть уже её. Подписей нет: цвета, значки и кнопки;
## текст только у «Показать».
func _build_editor() -> void:
	_editor = PanelContainer.new()
	_editor.add_theme_stylebox_override("panel", UiStyle.panel(18, 12))
	_editor.visible = false
	_editor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_editor.grow_vertical = Control.GROW_DIRECTION_BEGIN
	map.add_child(_editor)
	var ebox := VBoxContainer.new()
	ebox.add_theme_constant_override("separation", 8)
	_editor.add_child(ebox)
	var colors := HBoxContainer.new()
	colors.alignment = BoxContainer.ALIGNMENT_CENTER
	colors.add_theme_constant_override("separation", 8)
	for c: String in COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(36, 36)
		b.toggle_mode = true
		var sb := UiStyle.box(Color(c), 18, 0)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", UiStyle.box(Color(c), 18, 0, 4, UiStyle.TEXT))
		b.add_theme_stylebox_override("hover_pressed", UiStyle.box(Color(c), 18, 0, 4, UiStyle.TEXT))
		b.pressed.connect(func() -> void:
			_edit_color = c
			_sync_editor())
		colors.add_child(b)
		_color_buttons.append(b)
	ebox.add_child(colors)
	_icon_grid = GridContainer.new()
	_icon_grid.columns = 8
	_icon_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon_grid.add_theme_constant_override("h_separation", 6)
	_icon_grid.add_theme_constant_override("v_separation", 6)
	for id: String in ICONS:
		var b := Button.new()
		b.toggle_mode = true
		b.icon = UiStyle.icon("marker_" + id)
		b.tooltip_text = ICON_NAMES[id]
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", 24)
		b.custom_minimum_size = Vector2(42, 42)
		b.pressed.connect(func() -> void:
			_edit_icon = id
			_sync_editor())
		_icon_grid.add_child(b)
		_icon_buttons.append(b)
	ebox.add_child(_icon_grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_delete_button = _icon_only("trash", "Удалить")
	_delete_button.pressed.connect(_delete_marker)
	row.add_child(_delete_button)
	var cancel := _icon_only("close", "Отмена")
	cancel.pressed.connect(_close_editor)
	row.add_child(cancel)
	var go := Button.new()
	go.text = "Показать"
	go.icon = UiStyle.icon("target")
	go.add_theme_constant_override("icon_max_width", 20)
	go.custom_minimum_size = Vector2(0, 44)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(func() -> void:
		camera_rig.fly_to(_edit_pos)
		_close_editor()
		close())
	row.add_child(go)
	var ok := _icon_only("check", "Готово")
	ok.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.BRAND.lightened(0.35), 12, 8, 2, UiStyle.BRAND_DARK))
	ok.pressed.connect(_save_marker)
	row.add_child(ok)
	ebox.add_child(row)


static func _icon_only(icon_name: String, tip: String) -> Button:
	var b := Button.new()
	b.icon = UiStyle.icon(icon_name)
	b.tooltip_text = tip
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 22)
	b.custom_minimum_size = Vector2(52, 44)
	return b


func _fit() -> void:
	var vp := get_viewport_rect().size
	var m := Platform.safe_margins() if Platform.is_touch else {"left": 24.0, "top": 24.0, "right": 24.0, "bottom": 24.0}
	# Узкий (вертикальный) экран: заголовок без пояснения, «Метка здесь» — одним значком.
	var narrow := vp.x < vp.y
	_hint.visible = not narrow
	_here.text = "" if narrow else "Метка здесь"
	_here.tooltip_text = "Метка здесь"
	var w: float = minf(vp.x - m["left"] - m["right"] - 20.0, 980.0)
	var h: float = vp.y - m["top"] - m["bottom"] - 90.0
	map.custom_minimum_size = Vector2(w - 24.0, maxf(h, 160.0))
	_place_editor()


## Окно метки — по ширине карты без отступов; значки — одним рядом, если влезают,
## иначе двумя рядами поровну.
func _place_editor() -> void:
	if _editor == null or _icon_grid == null:
		return
	var inner := map.size.x - EDITOR_INSET * 2.0 - 24.0
	var fit := clampi(floori((inner + 6.0) / 48.0), 2, ICONS.size())
	var rows := ceili(float(ICONS.size()) / fit)
	_icon_grid.columns = ceili(float(ICONS.size()) / rows)
	var h := _editor.get_combined_minimum_size().y
	_editor.offset_left = EDITOR_INSET
	_editor.offset_right = -EDITOR_INSET
	_editor.offset_bottom = -EDITOR_INSET
	_editor.offset_top = -EDITOR_INSET - h


func open() -> void:
	map.center = Vector2(camera_rig.position.x, camera_rig.position.z)
	_close_editor()
	UiStyle.fade(self, true, 0.22)


func close() -> void:
	_close_editor()
	_touches.clear()
	UiStyle.fade(self, false, 0.18)
	closed.emit()


func is_open() -> bool:
	return get_meta("fade_target", false)


# --- Листание и масштаб ----------------------------------------------------------------

## Мышь: тянуть — листать, колесо — масштаб, щелчок — метка. Касания разбираются
## отдельно (_touch_event): мышиные копии касаний здесь не нужны — из-за них карта
## после щипка «перепрыгивала» к месту, где отпустили палец.
func _on_map_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_event(event)
	elif Platform.is_touch_copy(event):
		pass
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_moved = 0.0
			else:
				_dragging = false
				if _moved < 10.0:
					_tap(mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.0 / 1.15, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.15, mb.position)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_moved += mm.relative.length()
		_stop_pan()
		map.center -= mm.relative * map.view_meters / maxf(map.size.y, 1.0)
	elif event is InputEventMagnifyGesture:
		_zoom_at(1.0 / (event as InputEventMagnifyGesture).factor, (event as InputEventMagnifyGesture).position)
	map.accept_event()


## Палец отпустили где угодно (даже не над картой) — он больше не участвует в жесте.
## Иначе «забытый» палец превращал следующее касание в щипок вокруг старой точки.
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventScreenTouch):
		return
	var t := event as InputEventScreenTouch
	if not t.pressed and _touches.has(t.index) and not map.get_global_rect().has_point(t.position):
		_touches.erase(t.index)
		_touch_count_changed()


## Один палец листает, два — щипок (масштаб и сдвиг), короткое касание — метка.
func _touch_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _touches.is_empty():
				_touch_moved = 0.0
				_touch_multi = false
				_touch_start_msec = Time.get_ticks_msec()
			_touches[t.index] = t.position
			_touch_multi = _touch_multi or _touches.size() > 1
			_touch_count_changed()
		elif _touches.has(t.index):
			_touches.erase(t.index)
			if _touches.is_empty() and not _touch_multi and _touch_moved < 12.0 \
					and Time.get_ticks_msec() - _touch_start_msec < 600:
				_tap(t.position)
			_touch_count_changed()
	else:
		var d := event as InputEventScreenDrag
		if not _touches.has(d.index):
			return
		var prev: Vector2 = _touches[d.index]
		_touches[d.index] = d.position
		_touch_moved += (d.position - prev).length()
		_stop_pan()
		if _touches.size() >= 2:
			_pinch()
		else:
			map.center -= (d.position - prev) * map.view_meters / maxf(map.size.y, 1.0)


## Сколько пальцев изменилось — щипок начинается заново от их нынешних точек (без скачка).
func _touch_count_changed() -> void:
	if _touches.size() >= 2:
		_start_pinch()


func _pinch_pair() -> Array[Vector2]:
	var keys := _touches.keys()
	keys.sort()
	return [_touches[keys[0]], _touches[keys[1]]]


func _start_pinch() -> void:
	var p := _pinch_pair()
	_pinch_dist = maxf(p[0].distance_to(p[1]), 1.0)
	_pinch_mid = (p[0] + p[1]) * 0.5


func _pinch() -> void:
	var p := _pinch_pair()
	var dist := maxf(p[0].distance_to(p[1]), 1.0)
	var mid := (p[0] + p[1]) * 0.5
	_zoom_at(_pinch_dist / dist, mid)
	map.center -= (mid - _pinch_mid) * map.view_meters / maxf(map.size.y, 1.0)
	_pinch_dist = dist
	_pinch_mid = mid


## Масштаб вокруг точки карты focus: точка мира под ней остаётся на месте.
func _zoom_at(factor: float, focus: Vector2) -> void:
	var v0 := map.view_meters
	var v1 := clampf(v0 * factor, MIN_METERS, MAX_METERS)
	if is_equal_approx(v0, v1):
		return
	var world := map.map_to_world(focus)
	map.view_meters = v1
	map.center = world - (focus - map.size * 0.5) * v1 / maxf(map.size.y, 1.0)


## Кнопки «+» и «−»: плавно, вокруг середины карты.
func _zoom_smooth(factor: float) -> void:
	var target := clampf(map.view_meters * factor, MIN_METERS, MAX_METERS)
	create_tween().tween_property(map, "view_meters", target, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _pan_to(world: Vector2) -> void:
	_stop_pan()
	_pan_tween = create_tween()
	_pan_tween.tween_property(map, "center", world, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _stop_pan() -> void:
	if _pan_tween and _pan_tween.is_valid():
		_pan_tween.kill()


# --- Метки -----------------------------------------------------------------------------

func _tap(at: Vector2) -> void:
	var world := map.map_to_world(at)
	# Попали в метку — правим её.
	for i in WorldState.markers.size():
		var p: Vector3 = WorldState.markers[i]["pos"]
		if map.world_to_map(Vector2(p.x, p.z)).distance_to(at) < 18.0:
			_open_editor(i, p)
			return
	var h := map.chunk_manager.get_height(world.x, world.y) if map.chunk_manager else 0.0
	if _editor.visible and _edit_index < 0:
		# Новая метка ещё не поставлена — нажатие просто переносит её.
		_edit_pos = Vector3(world.x, h, world.y)
		_sync_editor()
		return
	_open_editor(-1, Vector3(world.x, h, world.y))


func _open_editor(index: int, pos: Vector3) -> void:
	_edit_index = index
	_edit_pos = pos
	if index >= 0:
		var m: Dictionary = WorldState.markers[index]
		_edit_color = str(m.get("color", COLORS[0]))
		_edit_icon = str(m.get("icon", "flag"))
	_delete_button.visible = index >= 0
	_editor.visible = true
	_sync_editor()
	_place_editor()
	# Место метки — посередине свободной части карты над окном.
	var free_h := map.size.y + _editor.offset_top
	var k := map.view_meters / maxf(map.size.y, 1.0)
	_pan_to(Vector2(pos.x, pos.z) - Vector2(0.0, free_h * 0.5 - map.size.y * 0.5) * k)


func _close_editor() -> void:
	if _editor:
		_editor.visible = false
	map.preview = {}
	map.edit_index = -1


## Кнопки отражают выбор, а метка на карте сразу показывает его.
func _sync_editor() -> void:
	for i in COLORS.size():
		_color_buttons[i].set_pressed_no_signal(COLORS[i] == _edit_color)
	for i in ICONS.size():
		_icon_buttons[i].set_pressed_no_signal(ICONS[i] == _edit_icon)
	map.preview = {"pos": _edit_pos, "color": _edit_color, "icon": _edit_icon}
	map.edit_index = _edit_index


func _save_marker() -> void:
	var entry := {"pos": _edit_pos, "color": _edit_color, "icon": _edit_icon, "name": ICON_NAMES[_edit_icon]}
	if _edit_index >= 0 and _edit_index < WorldState.markers.size():
		WorldState.markers[_edit_index] = entry
	else:
		WorldState.markers.append(entry)
	_close_editor()
	markers_changed.emit()
	Platform.haptic(0.3)


func _delete_marker() -> void:
	if _edit_index >= 0 and _edit_index < WorldState.markers.size():
		WorldState.markers.remove_at(_edit_index)
	_close_editor()
	markers_changed.emit()
