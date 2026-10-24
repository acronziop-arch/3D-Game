class_name TouchInput
extends Node
## Управление касаниями (телефон, планшет):
##   нажать — действие инструмента (добыть, поставить здание, выбрать для сноса);
##   тянуть одним пальцем — двигать камеру; в режиме «Ровнять» — выравнивать землю,
##     в стройке — тянуть призрак здания, если палец начал движение на нём;
##   два пальца: щипок — приближение, поворот — вращение, сдвиг — перемещение,
##     оба пальца вверх-вниз — наклон камеры.
## Касания поверх интерфейса сюда не доходят: их забирают кнопки и панели.

## Насколько палец может сдвинуться, чтобы касание ещё считалось нажатием (ед. интерфейса).
const TAP_SLOP := 12.0
const TAP_MSEC := 400
## Сколько нужно сдвинуть два пальца, чтобы понять жест: наклон или остальное.
const MULTI_DECIDE := 10.0

enum Mode { NONE, PENDING, PAN, TOOL_DRAG, MULTI, TILT, AFTER_MULTI }

var camera_rig: CameraRig
var interaction: Interaction

var _touches := {}
var _order: Array[int] = []
var _mode := Mode.NONE
var _start_pos := Vector2.ZERO
var _start_msec := 0
var _multi_decided := false
var _multi_accum := Vector2.ZERO
var _multi_start_dist := 0.0
var _last_mid := Vector2.ZERO
var _last_dist := 0.0
var _last_angle := 0.0


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
		if _touches.size() == 1:
			_mode = Mode.PENDING
			_start_pos = t.position
			_start_msec = Time.get_ticks_msec()
			camera_rig.touch_begin()
		elif _touches.size() == 2:
			if _mode == Mode.TOOL_DRAG:
				interaction.touch_drag_end()
			_mode = Mode.MULTI
			_multi_decided = false
			_multi_accum = Vector2.ZERO
			_reset_multi()
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
		_mode = Mode.NONE


func _on_drag(d: InputEventScreenDrag) -> void:
	if not _touches.has(d.index):
		return
	var prev: Vector2 = _touches[d.index]
	_touches[d.index] = d.position
	match _mode:
		Mode.PENDING:
			if (d.position - _start_pos).length() > TAP_SLOP:
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
				_update_multi(d.relative)


func _pair() -> Array[Vector2]:
	return [_touches[_order[0]], _touches[_order[1]]]


func _reset_multi() -> void:
	var p := _pair()
	_last_mid = (p[0] + p[1]) * 0.5
	_last_dist = maxf(p[0].distance_to(p[1]), 1.0)
	_last_angle = (p[1] - p[0]).angle()


func _update_multi(relative: Vector2) -> void:
	var p := _pair()
	var mid := (p[0] + p[1]) * 0.5
	var dist := maxf(p[0].distance_to(p[1]), 1.0)
	var angle := (p[1] - p[0]).angle()
	if not _multi_decided:
		# Оба пальца ровно вверх или вниз, расстояние почти не меняется — это наклон.
		_multi_accum += relative
		if _multi_accum.length() > MULTI_DECIDE:
			_multi_decided = true
			var vertical := absf(_multi_accum.y) > absf(_multi_accum.x) * 2.0
			var steady := absf(dist - _multi_start_dist) < MULTI_DECIDE * 0.8
			_mode = Mode.TILT if vertical and steady else Mode.MULTI
	if _mode == Mode.TILT:
		camera_rig.touch_tilt(mid.y - _last_mid.y)
	else:
		camera_rig.touch_pan(_last_mid, mid)
		camera_rig.touch_zoom(_last_dist / dist)
		camera_rig.touch_rotate(angle_difference(_last_angle, angle))
	_last_mid = mid
	_last_dist = dist
	_last_angle = angle
