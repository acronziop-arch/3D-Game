class_name MapPanel
extends Control
## Большая карта: открывается нажатием на мини-карту. Листается пальцем или
## мышью; масштаб постоянный (щипок и колесо его не меняют). Нажатие на пустое место ставит метку
## (цвет и значок на выбор), нажатие на метку — изменить или удалить её.
## «Показать» переносит камеру к выбранной точке.

signal closed
signal markers_changed

## Сколько метров мира помещается в карту по высоте — масштаб постоянный.
const MAP_METERS := 520.0
const COLORS := ["#E05A4E", "#F09A3E", "#F2C94C", "#62B04E", "#4E8FD6", "#9B6BD8"]
const ICONS := ["flag", "home", "star", "castle", "tree", "pick", "heart", "camp"]
const ICON_NAMES := {"flag": "Флаг", "home": "Деревня", "star": "Звезда", "castle": "Крепость", "tree": "Лес",
	"pick": "Руда", "heart": "Любимое", "camp": "Лагерь"}

var map: Minimap
var camera_rig: CameraRig

var _panel: PanelContainer
var _editor: PanelContainer
var _editor_title: Label
var _delete_button: Button
var _color_buttons: Array[Button] = []
var _icon_buttons: Array[Button] = []
var _edit_index := -1
var _edit_pos := Vector3.ZERO
var _edit_color := COLORS[0]
var _edit_icon := "flag"
var _drag_from := Vector2.ZERO
var _dragging := false
var _moved := 0.0
var _touches := {}


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
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(hint)
	var here := Button.new()
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
	back.pressed.connect(func() -> void: map.center = Vector2(camera_rig.position.x, camera_rig.position.z))
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
	box.add_child(map)

	# Редактор метки — поверх карты.
	_editor = PanelContainer.new()
	_editor.add_theme_stylebox_override("panel", UiStyle.panel(18, 12))
	_editor.visible = false
	_editor.set_anchors_preset(Control.PRESET_CENTER)
	_editor.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_editor.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_editor)
	var ebox := VBoxContainer.new()
	ebox.add_theme_constant_override("separation", 10)
	_editor.add_child(ebox)
	_editor_title = UiStyle.label("Новая метка", 17, UiStyle.TEXT, 800)
	ebox.add_child(_editor_title)
	var colors := HBoxContainer.new()
	colors.add_theme_constant_override("separation", 8)
	for c: String in COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(40, 40)
		b.toggle_mode = true
		var sb := UiStyle.box(Color(c), 20, 0)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", UiStyle.box(Color(c), 20, 0, 4, UiStyle.TEXT))
		b.add_theme_stylebox_override("hover_pressed", UiStyle.box(Color(c), 20, 0, 4, UiStyle.TEXT))
		b.pressed.connect(func() -> void:
			_edit_color = c
			_sync_editor())
		colors.add_child(b)
		_color_buttons.append(b)
	ebox.add_child(colors)
	var icons := GridContainer.new()
	icons.columns = 4
	icons.add_theme_constant_override("h_separation", 6)
	icons.add_theme_constant_override("v_separation", 6)
	for id: String in ICONS:
		var b := Button.new()
		b.toggle_mode = true
		b.icon = UiStyle.icon("marker_" + id)
		b.text = ICON_NAMES[id]
		b.add_theme_constant_override("icon_max_width", 22)
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(110, 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			_edit_icon = id
			_sync_editor())
		icons.add_child(b)
		_icon_buttons.append(b)
	ebox.add_child(icons)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	_delete_button = Button.new()
	_delete_button.text = "Удалить"
	_delete_button.icon = UiStyle.icon("trash")
	_delete_button.add_theme_constant_override("icon_max_width", 20)
	_delete_button.add_theme_color_override("font_color", UiStyle.BAD)
	_delete_button.custom_minimum_size = Vector2(0, 44)
	_delete_button.pressed.connect(_delete_marker)
	row.add_child(_delete_button)
	var go := Button.new()
	go.text = "Показать"
	go.icon = UiStyle.icon("target")
	go.add_theme_constant_override("icon_max_width", 20)
	go.custom_minimum_size = Vector2(0, 44)
	go.pressed.connect(func() -> void:
		camera_rig.fly_to(_edit_pos)
		_editor.visible = false
		close())
	row.add_child(go)
	var cancel := Button.new()
	cancel.text = "Отмена"
	cancel.custom_minimum_size = Vector2(0, 44)
	cancel.pressed.connect(func() -> void: _editor.visible = false)
	row.add_child(cancel)
	var ok := Button.new()
	ok.text = "Готово"
	ok.icon = UiStyle.icon("check")
	ok.add_theme_constant_override("icon_max_width", 20)
	ok.custom_minimum_size = Vector2(0, 44)
	ok.pressed.connect(_save_marker)
	row.add_child(ok)
	ebox.add_child(row)
	Platform.layout_changed.connect(_fit)
	_fit.call_deferred()


func _fit() -> void:
	var vp := get_viewport_rect().size
	var m := Platform.safe_margins() if Platform.is_touch else {"left": 24.0, "top": 24.0, "right": 24.0, "bottom": 24.0}
	var w: float = minf(vp.x - m["left"] - m["right"] - 20.0, 980.0)
	var h: float = vp.y - m["top"] - m["bottom"] - 90.0
	map.custom_minimum_size = Vector2(w - 24.0, maxf(h, 160.0))


func open() -> void:
	map.center = Vector2(camera_rig.position.x, camera_rig.position.z)
	_editor.visible = false
	UiStyle.fade(self, true, 0.22)


func close() -> void:
	_editor.visible = false
	UiStyle.fade(self, false, 0.18)
	closed.emit()


func is_open() -> bool:
	return get_meta("fade_target", false)


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() >= 2:
			# Двумя пальцами карту не масштабируем — только не даём это считать нажатием.
			_moved = 999.0
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_moved = 0.0
				_drag_from = mb.position
			else:
				_dragging = false
				if _moved < 10.0 and _touches.size() <= 1:
					_tap(mb.position)
	elif event is InputEventMouseMotion and _dragging and _touches.size() <= 1:
		var mm := event as InputEventMouseMotion
		_moved += mm.relative.length()
		map.center -= mm.relative * map.view_meters / maxf(map.size.y, 1.0)
	map.accept_event()


func _tap(at: Vector2) -> void:
	var world := map.map_to_world(at)
	# Попали в метку — редактируем её.
	for i in WorldState.markers.size():
		var p: Vector3 = WorldState.markers[i]["pos"]
		if map.world_to_map(Vector2(p.x, p.z)).distance_to(at) < 18.0:
			_open_editor(i, p)
			return
	var h := map.chunk_manager.get_height(world.x, world.y) if map.chunk_manager else 0.0
	_open_editor(-1, Vector3(world.x, h, world.y))


func _open_editor(index: int, pos: Vector3) -> void:
	_edit_index = index
	_edit_pos = pos
	if index >= 0:
		var m: Dictionary = WorldState.markers[index]
		_edit_color = str(m.get("color", COLORS[0]))
		_edit_icon = str(m.get("icon", "flag"))
		_editor_title.text = "Метка"
	else:
		_editor_title.text = "Новая метка"
	_delete_button.visible = index >= 0
	_sync_editor()
	_editor.visible = true
	_editor.reset_size()


func _sync_editor() -> void:
	for i in COLORS.size():
		_color_buttons[i].set_pressed_no_signal(COLORS[i] == _edit_color)
	for i in ICONS.size():
		_icon_buttons[i].set_pressed_no_signal(ICONS[i] == _edit_icon)


func _save_marker() -> void:
	var entry := {"pos": _edit_pos, "color": _edit_color, "icon": _edit_icon, "name": ICON_NAMES[_edit_icon]}
	if _edit_index >= 0:
		WorldState.markers[_edit_index] = entry
	else:
		WorldState.markers.append(entry)
	_editor.visible = false
	markers_changed.emit()
	Platform.haptic(0.3)


func _delete_marker() -> void:
	if _edit_index >= 0 and _edit_index < WorldState.markers.size():
		WorldState.markers.remove_at(_edit_index)
	_editor.visible = false
	markers_changed.emit()
