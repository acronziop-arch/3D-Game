class_name Doodles
extends Control
## Фон меню стройки: полупрозрачные контурные рисунки фирменным цветом —
## домики, деревья, мельница, башня, забор, холмы и солнце. Только линии, без заливки.

var color := UiStyle.BRAND_DARK
var alpha := 0.3
var line_width := 2.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)


func _draw() -> void:
	var c := Color(color, alpha)
	var h := size.y
	var w := size.x
	if w < 10.0 or h < 10.0:
		return
	# Холмы вдоль низа.
	var hills := PackedVector2Array()
	for i in 49:
		var x := w * i / 48.0
		hills.append(Vector2(x, h * (0.86 - 0.07 * sin(x / w * TAU * 2.0 + 0.6) - 0.04 * sin(x / w * TAU * 5.0))))
	draw_polyline(hills, c, line_width, true)
	# Рисунки по ширине: каждый в своей клетке, размер — от высоты панели.
	var s := h * 0.5
	var kinds := ["house", "tree", "mill", "sun", "tower", "fence", "tree", "house", "pine", "castle"]
	var step := maxf(s * 1.55, 90.0)
	var count := int(w / step)
	for i in count:
		var kind: String = kinds[i % kinds.size()]
		var base := Vector2(step * (i + 0.5), h * (0.78 + 0.05 * sin(i * 1.7)))
		var k := s * (0.75 + 0.25 * fmod(i * 0.618, 1.0))
		_doodle(kind, base, k, c)


func _doodle(kind: String, base: Vector2, k: float, c: Color) -> void:
	var lw := line_width
	match kind:
		"house":
			_poly(base, k, [Vector2(-0.4, 0), Vector2(-0.4, -0.45), Vector2(0, -0.8), Vector2(0.4, -0.45), Vector2(0.4, 0)], c)
			_poly(base, k, [Vector2(-0.1, 0), Vector2(-0.1, -0.25), Vector2(0.1, -0.25), Vector2(0.1, 0)], c)
			_poly(base, k, [Vector2(0.18, -0.4), Vector2(0.32, -0.4), Vector2(0.32, -0.28), Vector2(0.18, -0.28), Vector2(0.18, -0.4)], c)
			_poly(base, k, [Vector2(0.2, -0.6), Vector2(0.2, -0.76), Vector2(0.3, -0.76), Vector2(0.3, -0.52)], c)
		"tree":
			draw_line(base, base + Vector2(0, -0.45) * k, c, lw, true)
			draw_arc(base + Vector2(0, -0.62) * k, 0.24 * k, 0.0, TAU, 28, c, lw, true)
			draw_arc(base + Vector2(-0.16, -0.5) * k, 0.15 * k, PI * 0.5, PI * 1.6, 16, c, lw, true)
		"pine":
			draw_line(base, base + Vector2(0, -0.2) * k, c, lw, true)
			_poly(base, k, [Vector2(-0.25, -0.2), Vector2(0, -0.55), Vector2(0.25, -0.2), Vector2(-0.25, -0.2)], c)
			_poly(base, k, [Vector2(-0.19, -0.45), Vector2(0, -0.8), Vector2(0.19, -0.45)], c)
		"mill":
			_poly(base, k, [Vector2(-0.22, 0), Vector2(-0.14, -0.6), Vector2(0.14, -0.6), Vector2(0.22, 0)], c)
			_poly(base, k, [Vector2(-0.17, -0.6), Vector2(0, -0.74), Vector2(0.17, -0.6)], c)
			var hub := base + Vector2(0, -0.62) * k
			for a in 4:
				var d := Vector2.from_angle(a * PI * 0.5 + 0.4) * 0.42 * k
				draw_line(hub, hub + d, c, lw, true)
				var side := Vector2(-d.y, d.x).normalized() * 0.08 * k
				draw_line(hub + d * 0.35 + side, hub + d + side, c, lw * 0.7, true)
		"sun":
			var center := base + Vector2(0, -0.75) * k
			draw_arc(center, 0.16 * k, 0.0, TAU, 24, c, lw, true)
			for a in 8:
				var d := Vector2.from_angle(a * TAU / 8.0)
				draw_line(center + d * 0.24 * k, center + d * 0.33 * k, c, lw, true)
		"tower":
			_poly(base, k, [Vector2(-0.16, 0), Vector2(-0.16, -0.7), Vector2(-0.16, -0.78), Vector2(-0.08, -0.78), Vector2(-0.08, -0.72),
				Vector2(0.0, -0.72), Vector2(0.0, -0.78), Vector2(0.08, -0.78), Vector2(0.08, -0.72), Vector2(0.16, -0.72),
				Vector2(0.16, -0.78), Vector2(0.16, 0)], c)
			_poly(base, k, [Vector2(-0.05, 0), Vector2(-0.05, -0.16), Vector2(0.05, -0.16), Vector2(0.05, 0)], c)
		"castle":
			_poly(base, k, [Vector2(-0.45, 0), Vector2(-0.45, -0.5), Vector2(-0.3, -0.5), Vector2(-0.3, -0.36), Vector2(0.3, -0.36),
				Vector2(0.3, -0.5), Vector2(0.45, -0.5), Vector2(0.45, 0)], c)
			_poly(base, k, [Vector2(-0.48, -0.5), Vector2(-0.375, -0.66), Vector2(-0.27, -0.5)], c)
			_poly(base, k, [Vector2(0.27, -0.5), Vector2(0.375, -0.66), Vector2(0.48, -0.5)], c)
			draw_arc(base + Vector2(0, -0.1) * k, 0.1 * k, PI, TAU, 12, c, lw, true)
		"fence":
			for i in 4:
				var x := -0.36 + i * 0.24
				_poly(base, k, [Vector2(x, 0), Vector2(x, -0.32), Vector2(x + 0.04, -0.38), Vector2(x + 0.08, -0.32), Vector2(x + 0.08, 0)], c)
			draw_line(base + Vector2(-0.42, -0.12) * k, base + Vector2(0.42, -0.12) * k, c, lw, true)
			draw_line(base + Vector2(-0.42, -0.24) * k, base + Vector2(0.42, -0.24) * k, c, lw, true)


func _poly(base: Vector2, k: float, pts: Array, c: Color) -> void:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(base + p * k)
	draw_polyline(out, c, line_width, true)
