class_name SmoothScroll
extends Container
## Прокрутка как на iPhone: содержимое идёт за пальцем без задержки, после
## броска плавно тормозит, а у края упруго оттягивается и мягко возвращается.
## Внутри — один дочерний Control. Кнопки внутри должны пропускать события
## (mouse_filter = PASS): тогда начало прокрутки отменяет нажатие кнопки.

## true — листается по горизонтали, иначе по вертикали.
@export var horizontal := false

## Сколько прокручено, пикселей.
var scroll := 0.0

const DEADZONE := 8.0
const RUBBER := 0.42
const FRICTION := 3.4

var _velocity := 0.0
var _pressed := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _last := 0.0
var _last_msec := 0
## Тонкая полоска-индикатор, как в iOS: видна, пока список листается.
var _bar: Panel
var _bar_alpha := 0.0
var _bar_hold := 0.0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	_bar = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.24, 0.2, 0.16, 0.42)
	sb.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("panel", sb)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.modulate.a = 0.0
	add_child(_bar, false, Node.INTERNAL_MODE_FRONT)


func content() -> Control:
	for c in get_children():
		if c is Control:
			return c
	return null


func max_scroll() -> float:
	var c := content()
	if c == null:
		return 0.0
	var m := c.get_combined_minimum_size()
	return maxf(0.0, (m.x - size.x) if horizontal else (m.y - size.y))


func _get_minimum_size() -> Vector2:
	var c := content()
	if c == null:
		return Vector2.ZERO
	var m := c.get_combined_minimum_size()
	return Vector2(0.0, m.y) if horizontal else Vector2(m.x, 0.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var c := content()
		if c == null:
			return
		var m := c.get_combined_minimum_size()
		if horizontal:
			fit_child_in_rect(c, Rect2(Vector2(-scroll, 0.0), Vector2(maxf(m.x, size.x), size.y)))
		else:
			fit_child_in_rect(c, Rect2(Vector2(0.0, -scroll), Vector2(size.x, maxf(m.y, size.y))))


func _axis(p: Vector2) -> float:
	return p.x if horizontal else p.y


func _set_scroll(value: float) -> void:
	if not is_equal_approx(value, scroll):
		scroll = value
		queue_sort()
		_bar_hold = 0.7
		_place_bar()


func _place_bar() -> void:
	var limit := max_scroll()
	if limit <= 0.0:
		_bar.visible = false
		return
	_bar.visible = true
	var length := size.x if horizontal else size.y
	var thumb := clampf(length * length / (length + limit), 28.0, length)
	# У края полоска сжимается, как в iOS.
	var over := maxf(-scroll, scroll - limit)
	if over > 0.0:
		thumb = maxf(14.0, thumb - over)
	var t := clampf(scroll / limit, 0.0, 1.0)
	var at := (length - thumb) * t
	if horizontal:
		_bar.position = Vector2(at, size.y - 5.0)
		_bar.size = Vector2(thumb, 3.0)
	else:
		_bar.position = Vector2(size.x - 5.0, at)
		_bar.size = Vector2(3.0, thumb)


## Прокрутить к началу (без анимации).
func reset() -> void:
	_velocity = 0.0
	_set_scroll(0.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_velocity = 0.0
				_press_pos = mb.position
				_last = _axis(mb.position)
				_last_msec = Time.get_ticks_msec()
			else:
				_pressed = false
				if _dragging:
					_dragging = false
					accept_event()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			var dir := -1.0 if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1.0
			if max_scroll() > 0.0:
				_velocity = 0.0
				_set_scroll(clampf(scroll + dir * 70.0 * mb.factor, 0.0, max_scroll()))
				accept_event()
	elif event is InputEventMouseMotion and _pressed:
		var mm := event as InputEventMouseMotion
		var pos := _axis(mm.position)
		if not _dragging:
			if absf(_axis(mm.position - _press_pos)) < DEADZONE or max_scroll() <= 0.0:
				return
			_dragging = true
			_last = pos
			# Кнопки под пальцем отменяют нажатие — это прокрутка, а не тап.
			propagate_notification(NOTIFICATION_SCROLL_BEGIN)
		var delta := pos - _last
		_last = pos
		var limit := max_scroll()
		if scroll < 0.0 or scroll > limit:
			delta *= RUBBER
		_set_scroll(scroll - delta)
		var now := Time.get_ticks_msec()
		var dt := maxf((now - _last_msec) / 1000.0, 1.0 / 240.0)
		_last_msec = now
		_velocity = lerpf(_velocity, -delta / dt, 0.6)
		accept_event()


func _process(delta: float) -> void:
	_bar_hold -= delta
	var want := 1.0 if _bar_hold > 0.0 or _dragging else 0.0
	if not is_equal_approx(_bar_alpha, want):
		_bar_alpha = move_toward(_bar_alpha, want, delta * (6.0 if want > 0.0 else 2.5))
		_bar.modulate.a = _bar_alpha
	if _pressed:
		# Палец стоит на месте — бросок не засчитываем.
		if Time.get_ticks_msec() - _last_msec > 90:
			_velocity = 0.0
		return
	var limit := max_scroll()
	if scroll < 0.0 or scroll > limit:
		# Упругий возврат к краю, как на iPhone.
		var target := clampf(scroll, 0.0, limit)
		_velocity *= exp(-18.0 * delta)
		var next := lerpf(scroll + _velocity * delta, target, 1.0 - exp(-12.0 * delta))
		_set_scroll(target if absf(next - target) < 0.5 else next)
	elif absf(_velocity) > 4.0:
		_set_scroll(scroll + _velocity * delta)
		_velocity *= exp(-FRICTION * delta)
		# Разогнались за край — дальше работает пружина.
		if scroll < -60.0 or scroll > limit + 60.0:
			_velocity = 0.0
	else:
		_velocity = 0.0
