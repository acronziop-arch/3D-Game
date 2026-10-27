class_name Notices
extends VBoxContainer
## Сообщения игроку: стопка плашек сверху по центру. Новое сообщение встаёт
## сверху и не закрывает прежние; одинаковое — не дублируется, а продлевается.
## Все плашки появляются, держатся и исчезают одинаково, переносят длинный
## текст и не выходят за края экрана.

const SHOW_TIME := 2.8
const FADE_IN := 0.2
const FADE_OUT := 0.25
const MAX_VISIBLE := 3

## Ширина плашки не больше этой (её задаёт HUD по размеру экрана).
var max_width := 560.0
var font_size := 16

var _notes: Array[Dictionary] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 6)


func show_text(text: String) -> void:
	for n in _notes:
		if n["text"] == text and not n["closing"]:
			n["left"] = SHOW_TIME
			_pulse(n["panel"])
			return
	while _live_count() >= MAX_VISIBLE:
		_close(_oldest())
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(UiStyle.BASE, 0.97), 18, 10, 2, UiStyle.BRAND, true))
	# Сообщение с разметкой: значки ресурсов вместо названий, красная причина отказа.
	var label := Rich.label(font_size)
	Rich.fit(label, text, max_width - 24.0)
	panel.add_child(label)
	add_child(panel)
	move_child(panel, 0)
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, FADE_IN)
	_notes.append({"text": text, "panel": panel, "left": SHOW_TIME, "closing": false})


## Короткий текст — в одну строку по своей ширине; длинный — переносится по max_w.
static func fit_label(label: Label, text: String, max_w: float) -> void:
	var w := fit_width(label, text, INF)
	if w <= max_w:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size.x = 0.0
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = max_w


## Ширина метки: по тексту, но не шире max_w (дальше текст переносится).
static func fit_width(label: Label, text: String, max_w: float) -> float:
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	var w := 0.0
	for line in text.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	return minf(ceilf(w) + 4.0, max_w)


func _live_count() -> int:
	var n := 0
	for note in _notes:
		if not note["closing"]:
			n += 1
	return n


func _oldest() -> Dictionary:
	for note in _notes:
		if not note["closing"]:
			return note
	return {}


func _pulse(panel: Control) -> void:
	panel.pivot_offset = panel.size * 0.5
	var tw := panel.create_tween()
	tw.tween_property(panel, "scale", Vector2.ONE * 1.04, 0.08)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.12)


func _close(note: Dictionary) -> void:
	if note.is_empty() or note["closing"]:
		return
	note["closing"] = true
	var panel: Control = note["panel"]
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(func() -> void:
		_notes.erase(note)
		panel.queue_free())


func _process(delta: float) -> void:
	for note in _notes.duplicate():
		if note["closing"]:
			continue
		note["left"] -= delta
		if note["left"] <= 0.0:
			_close(note)
