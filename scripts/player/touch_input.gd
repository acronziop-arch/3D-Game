class_name TouchInput
extends Node
## Управление касаниями (телефон, планшет):
##   нажать — действие инструмента (добыть, поставить здание, выбрать для сноса);
##   тянуть одним пальцем — двигать камеру; в режиме «Ровнять» — выравнивать землю,
##     в стройке — тянуть призрак здания, если палец начал движение на нём;
##   жест, начатый в мире, продолжается и над интерфейсом — до отпускания пальца;
##   два пальца: щипок — приближение, поворот — вращение, сдвиг — перемещение,
##     оба пальца вверх-вниз — наклон камеры;
##   три быстрых касания двумя пальцами — спрятать или вернуть интерфейс.
## Касания, начатые поверх интерфейса, сюда не доходят: их забирают кнопки и панели.

signal hide_ui_requested

## Насколько палец может сдвинуться, чтобы касание ещё считалось нажатием (ед. интерфейса).
const TAP_SLOP := 12.0
const TAP_MSEC := 400
## Сколько нужно сдвинуть два пальца, чтобы понять жест: наклон или остальное.
const MULTI_DECIDE := 14.0
## Касание двумя пальцами: не дольше и не чаще, чем через столько мс.
const TWO_TAP_MSEC := 320
const TWO_TAP_GAP := 450

enum Mode { NONE, PENDING, PAN, TOOL_DRAG, MULTI, TILT, AFTER_MULTI }

var camera_rig: CameraRig
var interaction: Interaction

var _touches := {}
var _order: Array[int] = []
var _mode := Mode.NONE
var _start_pos := Vector2.ZERO
var _start_msec := 0
var _multi_decided := false
var _multi_start_mid := Vector2.ZERO
var _multi_start_dist := 0.0
var _gesture_touches := 0
var _gesture_moved := false
var _two_taps := 0
var _last_two_tap := 0
var _last_mid := Vector2.ZERO
var _last_dist := 0.0
var _last_angle := 0.0


## Палец, начавший жест в мире, ведёт его до конца и над кнопками и панелями: иначе камера
## или линия ограды обрывались, стоило пальцу задеть интерфейс (его забирал себе Control).
func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag and _touches.has((event as InputEventScreenDrag).index):
		_on_drag(event as InputEventScreenDrag)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and not event.pressed and _touches.has((event as InputEventScreenTouch).index):
		_on_touch(event as InputEventScreenTouch)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
		get_viewport().set_input_as_handled()


func _on_touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		_touches[t.index] = t.position
		if not t.index in _order:
			_order.append(t.index)
		_gesture_touches = maxi(_gesture_touches, _touches.size())
		if _touches.size() == 1:
			_mode = Mode.PENDING
			_start_pos = t.position
			_start_msec = Time.get_ticks_msec()
			_gesture_touches = 1
			_gesture_moved = false
			camera_rig.touch_begin()
		elif _touches.size() == 2:
			if _mode == Mode.TOOL_DRAG:
				interaction.touch_drag_end()
			if _mode != Mode.PENDING:
				_gesture_moved = true
			_mode = Mode.MULTI
			_multi_decided = false
			_reset_multi()
			_multi_start_mid = _last_mid
			_multi_start_dist = _last_dist
		return
	if not _touches.has(t.index):
		return
	_touches.erase(t.index)
	_order.erase(t.index)
	match _mode:
		Mode.PENDING:
			if _touches.is_empty() and (t.position - _start_pos).length() < TAP_SLOP \
					and Time.get_ticks_msec() - _start_msec < TAP_MSEC:
				interaction.touch_tap(t.position)
		Mode.TOOL_DRAG:
			interaction.touch_drag_end()
		Mode.MULTI, Mode.TILT:
			# Один палец остался: им можно продолжить двигать камеру, но не нажимать.
			if _touches.size() == 1:
				_mode = Mode.AFTER_MULTI
			elif _touches.size() >= 2:
				_reset_multi()
	if _touches.is_empty():
		camera_rig.touch_end(_mode == Mode.PAN or _mode == Mode.AFTER_MULTI)
		if _gesture_touches == 2 and not _gesture_moved:
			_on_two_finger_tap()
		_mode = Mode.NONE


## Три быстрых касания двумя пальцами подряд прячут (и возвращают) интерфейс.
func _on_two_finger_tap() -> void:
	var now := Time.get_ticks_msec()
	if now - _start_msec > TWO_TAP_MSEC:
		_two_taps = 0
		return
	_two_taps = _two_taps + 1 if now - _last_two_tap < TWO_TAP_GAP else 1
	_last_two_tap = now
	if _two_taps >= 3:
		_two_taps = 0
		hide_ui_requested.emit()


func _on_drag(d: InputEventScreenDrag) -> void:
	if not _touches.has(d.index):
		return
	var prev: Vector2 = _touches[d.index]
	_touches[d.index] = d.position
	match _mode:
		Mode.PENDING:
			if (d.position - _start_pos).length() > TAP_SLOP:
				_gesture_moved = true
				if interaction.touch_drag_begin(_start_pos):
					_mode = Mode.TOOL_DRAG
					interaction.touch_drag(d.position)
				else:
					_mode = Mode.PAN
					camera_rig.touch_pan(_start_pos, d.position)
		Mode.PAN, Mode.AFTER_MULTI:
			camera_rig.touch_pan(prev, d.position)
		Mode.TOOL_DRAG:
			interaction.touch_drag(d.position)
		Mode.MULTI, Mode.TILT:
			if d.index in _order.slice(0, 2):
				_update_multi()


func _pair() -> Array[Vector2]:
	return [_touches[_order[0]], _touches[_order[1]]]


func _reset_multi() -> void:
	var p := _pair()
	_last_mid = (p[0] + p[1]) * 0.5
	_last_dist = maxf(p[0].distance_to(p[1]), 1.0)
	_last_angle = (p[1] - p[0]).angle()


func _update_multi() -> void:
	var p := _pair()
	var mid := (p[0] + p[1]) * 0.5
	var dist := maxf(p[0].distance_to(p[1]), 1.0)
	var angle := (p[1] - p[0]).angle()
	if not _multi_decided:
		# Пока жест не понятен, камеру не трогаем — иначе наклон начинается с приближения.
		var moved := mid - _multi_start_mid
		var pinch := absf(dist - _multi_start_dist)
		if moved.length() > TAP_SLOP or pinch > TAP_SLOP:
			_gesture_moved = true
		if maxf(moved.length(), pinch) < MULTI_DECIDE:
			return
		_multi_decided = true
		# Оба пальца идут вверх или вниз, а расстояние между ними меняется меньше —
		# это наклон, иначе щипок, поворот и сдвиг.
		var vertical := absf(moved.y) > absf(moved.x) * 1.4
		_mode = Mode.TILT if vertical and absf(moved.y) > pinch * 1.3 else Mode.MULTI
		_last_mid = _multi_start_mid
		_last_dist = _multi_start_dist
	if _mode == Mode.TILT:
		camera_rig.touch_tilt(mid.y - _last_mid.y)
	else:
		camera_rig.touch_pan(_last_mid, mid)
		camera_rig.touch_zoom(_last_dist / dist)
		camera_rig.touch_rotate(angle_difference(_last_angle, angle))
	_last_mid = mid
	_last_dist = dist
	_last_angle = angle
