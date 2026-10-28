class_name StartScreen
extends CanvasLayer
## Стартовый экран: слева логотип и «Новый мир», справа — список сохранённых миров
## с превью карты. У каждого мира — «Играть» и «Удалить». Когда мир выбран
## (WorldState уже открыл или создал его), экран сообщает chosen и плавно исчезает,
## открывая экран загрузки.
##
## В браузере имя нового мира вводится в HTML-окне из web_shell.html: только по
## нажатию на настоящее поле страницы Safari показывает клавиатуру.

signal chosen

const CARD := Color("#FBF8F3")
const CARD_BORDER := Color("#E6DACB")
const ROW := Color("#FFFFFF")
const ACCENT := Color("#E8643C")
const MONTHS := ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
## Скруглённые углы у превью карты.
const PREVIEW_SHADER := """
shader_type canvas_item;
uniform float radius = 0.2;
void fragment() {
	vec2 d = abs(UV - 0.5) - (0.5 - radius);
	float dist = length(max(d, 0.0)) - radius;
	COLOR = texture(TEXTURE, UV);
	COLOR.a *= 1.0 - smoothstep(-0.012, 0.012, dist);
}
"""

var _touch := false
var _root: Control
var _margin: MarginContainer
## Логотип и список миров: рядом, а на вертикальном экране — друг под другом.
var _columns: BoxContainer
var _list: VBoxContainer
var _scroll: SmoothScroll
var _count: Label
var _empty: Control
var _modal: Control
var _toast: PanelContainer
var _toast_label: Label
var _preview_material: ShaderMaterial
## Ссылка на JS-функцию ответа, пока открыто окно браузера (иначе её соберёт сборщик мусора).
var _js_callback: JavaScriptObject
## Мир уже выбран — нажатия больше не принимаются.
var _done := false


func _ready() -> void:
	layer = 60
	_touch = Platform.is_touch
	var shader := Shader.new()
	shader.code = PREVIEW_SHADER
	_preview_material = ShaderMaterial.new()
	_preview_material.shader = shader
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UiStyle.make_theme()
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_root)
	_build_backdrop()
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_margin)
	_columns = BoxContainer.new()
	_columns.add_theme_constant_override("separation", int(_px(40, 18)))
	_columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_columns)
	_columns.add_child(_build_intro())
	_columns.add_child(_build_worlds())
	_build_toast()
	_place()
	Platform.layout_changed.connect(_place)
	_root.resized.connect(_place)
	refresh()
	# Появление — мягко, поверх экрана загрузки.
	_root.modulate.a = 0.0
	_root.create_tween().tween_property(_root, "modulate:a", 1.0, 0.35)


func _px(pc: float, touch: float) -> float:
	return touch if _touch else pc


func _place() -> void:
	var m := Platform.safe_margins() if _touch else {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	# Вертикальный экран: логотип и «Новый мир» сверху, список миров — под ними.
	var vp := _root.get_viewport_rect().size
	_columns.vertical = vp.x < vp.y
	var pad := _px(48, 14)
	_margin.add_theme_constant_override("margin_left", int(m["left"] + pad))
	_margin.add_theme_constant_override("margin_right", int(m["right"] + pad))
	_margin.add_theme_constant_override("margin_top", int(m["top"] + _px(40, 12)))
	_margin.add_theme_constant_override("margin_bottom", int(m["bottom"] + _px(40, 12)))


# --- Сборка экрана ----------------------------------------------------------------------------

## Тот же фон, что у экрана загрузки: тёплое небо и контурный пейзаж.
func _build_backdrop() -> void:
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color("#F8F3EA"))
	grad.set_color(1, Color("#E8DDCD"))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var doodles := Doodles.new()
	doodles.line_width = _px(2.6, 2.0)
	doodles.alpha = 0.3
	doodles.set_anchors_preset(Control.PRESET_FULL_RECT)
	doodles.anchor_top = 0.5
	_root.add_child(doodles)


func _build_intro() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_stretch_ratio = 0.78
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(_px(12, 6)))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo_holder := Control.new()
	logo_holder.custom_minimum_size = Vector2.ONE * _px(104, 60)
	logo_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(logo_holder)
	var logo := TextureRect.new()
	logo.texture = load("res://icon.png") if ResourceLoader.exists("res://icon.png") else null
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_holder.add_child(logo)
	logo.pivot_offset = logo_holder.custom_minimum_size * 0.5
	var bob := logo.create_tween().set_loops()
	bob.tween_property(logo, "position:y", -7.0, 1.2).set_trans(Tween.TRANS_SINE)
	bob.parallel().tween_property(logo, "rotation", deg_to_rad(2.0), 1.2).set_trans(Tween.TRANS_SINE)
	bob.tween_property(logo, "position:y", 0.0, 1.2).set_trans(Tween.TRANS_SINE)
	bob.parallel().tween_property(logo, "rotation", deg_to_rad(-2.0), 1.2).set_trans(Tween.TRANS_SINE)
	var title := UiStyle.label(GameData.GAME_NAME, int(_px(52, 34)), UiStyle.TEXT, 900)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color.WHITE)
	title.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(title)
	var sub := UiStyle.label("Стройте свою деревню в бесконечном мире", int(_px(17, 13)), UiStyle.BRAND_DARK, 800)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = _px(14, 4)
	box.add_child(gap)
	var create := _big_button("Новый мир", "plus", true)
	create.pressed.connect(_on_new)
	box.add_child(create)
	var note := UiStyle.label("Миры хранятся на этом устройстве.",
		int(_px(13, 11)), UiStyle.MUTED, 700)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = _px(320, 230)
	note.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(note)
	return box


func _big_button(text: String, icon_name: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = UiStyle.icon(icon_name)
	b.add_theme_constant_override("icon_max_width", int(_px(28, 24)))
	b.add_theme_constant_override("h_separation", 10)
	b.add_theme_font_size_override("font_size", int(_px(19, 16)))
	b.add_theme_font_override("font", UiStyle.font(900))
	b.custom_minimum_size = Vector2(_px(300, 230), _px(56, 46))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if primary:
		_style_primary(b, 16)
	else:
		b.add_theme_stylebox_override("normal", UiStyle.box(CARD, 16, 10, 2, CARD_BORDER))
		b.add_theme_stylebox_override("hover", UiStyle.box(Color.WHITE, 16, 10, 2, UiStyle.BRAND))
		b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.SURFACE_HOVER, 16, 10, 2, UiStyle.BRAND))
	return b


## Оранжевая кнопка главного действия: белый текст, тёмный «бортик» снизу.
func _style_primary(b: Button, radius: int) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var bg := ACCENT
		if state == "hover":
			bg = ACCENT.lightened(0.08)
		elif state.contains("pressed"):
			bg = ACCENT.darkened(0.08)
		var sb := UiStyle.box(bg, radius, 8)
		sb.border_width_bottom = 0 if state.contains("pressed") else 3
		sb.border_color = ACCENT.darkened(0.25)
		b.add_theme_stylebox_override(state, sb)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color.WHITE)


func _build_worlds() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.22
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", UiStyle.box(CARD, 24, int(_px(18, 10)), 2, CARD_BORDER, true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(_px(12, 8)))
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	head.add_child(UiStyle.icon_rect("map", int(_px(32, 26))))
	var title := UiStyle.label("Ваши миры", int(_px(22, 18)), UiStyle.TEXT, 900)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count = UiStyle.label("", int(_px(15, 13)), UiStyle.MUTED, 800)
	head.add_child(_count)
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(holder)
	_scroll = SmoothScroll.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_right", 6)
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", int(_px(10, 8)))
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_child(_list)
	# Пустой список: подсказка, с чего начать.
	var empty := VBoxContainer.new()
	empty.set_anchors_preset(Control.PRESET_FULL_RECT)
	empty.alignment = BoxContainer.ALIGNMENT_CENTER
	empty.add_theme_constant_override("separation", 6)
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UiStyle.icon_rect("marker_tree", int(_px(72, 52)))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	empty.add_child(ic)
	var t := UiStyle.label("Миров пока нет", int(_px(20, 17)), UiStyle.TEXT, 900)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.add_child(t)
	var s := UiStyle.label("Нажмите «Новый мир» — и в путь!", int(_px(15, 13)), UiStyle.MUTED, 700)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.add_child(s)
	holder.add_child(empty)
	_empty = empty
	return panel


## Перечитывает список миров.
func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var worlds := WorldState.list_worlds()
	for w: Dictionary in worlds:
		_list.add_child(_world_row(w))
	_empty.visible = worlds.is_empty()
	_count.text = str(worlds.size()) if worlds.size() > 0 else ""
	_scroll.reset()


func _world_row(w: Dictionary) -> Control:
	var id: String = w["id"]
	var title: String = w.get("name", "Мир")
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_stylebox_override("panel", UiStyle.box(ROW, 18, int(_px(10, 7)), 2, CARD_BORDER))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(_px(14, 10)))
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(h)
	h.add_child(_preview(id))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 0 if _touch else 2)
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(info)
	var name_label := UiStyle.label(title, int(_px(19, 16)), UiStyle.TEXT, 900)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	name_label.custom_minimum_size.x = 60
	info.add_child(name_label)
	var built := int(w.get("buildings", 0))
	var when := _when(float(w.get("played", w.get("created", 0.0))))
	var count := "%d %s" % [built, _plural(built, ["постройка", "постройки", "построек"])] if built > 0 else "без построек"
	# На телефоне строка узкая — дата и постройки в две строки.
	for line: String in ([when, count] if _touch else [when + " · " + count]):
		var sub := UiStyle.label(line, int(_px(14, 12)), UiStyle.MUTED, 700)
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub.clip_text = true
		sub.custom_minimum_size.x = 60
		info.add_child(sub)
	var side := _px(46, 40)
	var play := Button.new()
	play.text = "Играть"
	play.add_theme_font_override("font", UiStyle.font(900))
	play.add_theme_font_size_override("font_size", int(_px(17, 15)))
	play.custom_minimum_size = Vector2(_px(112, 88), side)
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	play.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_primary(play, 14)
	play.pressed.connect(_play.bind(id))
	h.add_child(play)
	var remove := _icon_button("trash", "Удалить", side)
	remove.pressed.connect(_ask_delete.bind(id, title))
	h.add_child(remove)
	return row


func _icon_button(icon_name: String, tip: String, side: float) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(side, side)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = tip
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.add_theme_stylebox_override("normal", UiStyle.box(CARD, 12, 6, 2, CARD_BORDER))
	b.add_theme_stylebox_override("hover", UiStyle.box(Color.WHITE, 12, 6, 2, UiStyle.BRAND))
	b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.SURFACE_HOVER, 12, 6, 2, UiStyle.BRAND))
	var ic := UiStyle.icon_rect(icon_name, int(side * 0.62))
	ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ic.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ic.grow_vertical = Control.GROW_DIRECTION_BOTH
	b.add_child(ic)
	return b


## Кусок карты мира со зданиями; у мира без сохранённой карты — значок.
func _preview(id: String) -> Control:
	var side := _px(68, 54)
	var path := WorldState.preview_path(id)
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img and not img.is_empty():
			var r := TextureRect.new()
			r.texture = ImageTexture.create_from_image(img)
			r.custom_minimum_size = Vector2(side, side)
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_SCALE
			r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.material = _preview_material
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return r
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(side, side)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", UiStyle.box(Minimap.PAPER, int(side * 0.2), 8))
	badge.add_child(UiStyle.icon_rect("icon_village", int(side * 0.6)))
	return badge


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", UiStyle.box(Color(UiStyle.TEXT, 0.92), 14, 12))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_bottom = -_px(28, 14)
	_toast.modulate.a = 0.0
	_root.add_child(_toast)
	_toast_label = UiStyle.label("", int(_px(16, 14)), Color.WHITE, 800)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)


func _say(text: String, bad := false) -> void:
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", Color("#FFB4A8") if bad else Color.WHITE)
	if _toast.has_meta("tween"):
		(_toast.get_meta("tween") as Tween).kill()
	var tw := _toast.create_tween()
	_toast.set_meta("tween", tw)
	tw.tween_property(_toast, "modulate:a", 1.0, 0.18)
	tw.tween_interval(3.0)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)


# --- Действия ---------------------------------------------------------------------------------

func _play(id: String) -> void:
	if _done or _modal:
		return
	if WorldState.open_world(id):
		_finish()
	else:
		_say("Не удалось открыть мир — файл повреждён", true)


func _create(title: String) -> void:
	if _done:
		return
	WorldState.create_world(title)
	_finish()


## Мир выбран: экран загрузки уже под нами — исчезаем и начинаем строить мир.
func _finish() -> void:
	_done = true
	chosen.emit()
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)


func _on_new() -> void:
	if _done or _modal:
		return
	var js: Variant = _web()
	if js:
		_js_callback = JavaScriptBridge.create_callback(func(args: Array) -> void:
			var title := _js_text(args)
			if title != "":
				_create.call_deferred(title))
		js.askName("Новый мир", "Как назовём мир? Имя будет видно в списке миров.", WorldState.suggest_name(), "Создать", _js_callback)
		return
	var field := LineEdit.new()
	field.text = WorldState.suggest_name()
	field.max_length = 40
	field.select_all_on_focus = true
	field.custom_minimum_size.y = _px(48, 44)
	field.add_theme_font_size_override("font_size", int(_px(18, 16)))
	field.add_theme_font_override("font", UiStyle.font(800))
	field.add_theme_stylebox_override("normal", UiStyle.box(Color.WHITE, 12, 10, 2, CARD_BORDER))
	field.add_theme_stylebox_override("focus", UiStyle.box(Color(0, 0, 0, 0), 12, 10, 2, ACCENT))
	field.add_theme_color_override("font_color", UiStyle.TEXT)
	var accept := func() -> void:
		if field.text.strip_edges() != "":
			_close_modal()
			_create(field.text)
	field.text_submitted.connect(func(_t: String) -> void: accept.call())
	_open_modal("Новый мир", "Как назовём мир? Имя будет видно в списке миров.", [field],
		[["Отмена", false, _close_modal], ["Создать", true, accept]])
	field.grab_focus.call_deferred()


func _ask_delete(id: String, title: String) -> void:
	if _done or _modal:
		return
	_open_modal("Удалить «%s»?" % title, "Все постройки, ресурсы и карта этого мира пропадут. Отменить это нельзя.", [],
		[["Отмена", false, _close_modal], ["Удалить", true, func() -> void:
			_close_modal()
			WorldState.delete_world(id)
			refresh()
			_say("Мир «%s» удалён" % title)]], true)


# --- Окно поверх списка (ввод имени, удаление) -----------------------------------

## buttons: [[текст, главная?, Callable]]. danger — главная кнопка красная.
func _open_modal(title: String, text: String, content: Array, buttons: Array, danger := false) -> void:
	_modal = Control.new()
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0.18, 0.13, 0.09, 0.42)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_modal())
	_modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _touch:
		# Клавиатура телефона закрывает низ экрана — окно повыше.
		center.anchor_bottom = 0.62
	_modal.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box(CARD, 22, int(_px(20, 14)), 2, CARD_BORDER, true))
	center.add_child(card)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = _px(440, 380)
	box.add_theme_constant_override("separation", int(_px(12, 8)))
	card.add_child(box)
	box.add_child(UiStyle.label(title, int(_px(22, 18)), UiStyle.TEXT, 900))
	var desc := UiStyle.label(text, int(_px(15, 13)), UiStyle.MUTED, 700)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 200
	box.add_child(desc)
	for c: Control in content:
		box.add_child(c)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for spec: Array in buttons:
		var b := Button.new()
		b.text = spec[0]
		b.add_theme_font_override("font", UiStyle.font(900))
		b.custom_minimum_size.y = _px(48, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if spec[1]:
			_style_primary(b, 14)
			if danger:
				for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
					var sb := (b.get_theme_stylebox(state) as StyleBoxFlat).duplicate() as StyleBoxFlat
					sb.bg_color = UiStyle.BAD.lightened(0.06 if state == "hover" else 0.0)
					sb.border_color = UiStyle.BAD.darkened(0.25)
					b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(spec[2])
		row.add_child(b)
	_modal.modulate.a = 0.0
	_modal.create_tween().tween_property(_modal, "modulate:a", 1.0, 0.16)


func _close_modal() -> void:
	if _modal:
		_modal.queue_free()
		_modal = null


func _unhandled_input(event: InputEvent) -> void:
	if _modal and event.is_action_pressed("cancel"):
		_close_modal()
		get_viewport().set_input_as_handled()


# --- Помощники ----------------------------------------------------------------------------------

## window.everstead из web_shell.html (null — не браузер). Без типа: его методы — из JS.
func _web() -> Variant:
	if not OS.has_feature("web"):
		return null
	return JavaScriptBridge.get_interface("everstead")


static func _js_text(args: Array) -> String:
	if args.is_empty() or args[0] == null:
		return ""
	return str(args[0]).strip_edges()


## «сегодня в 14:32», «вчера в 9:05», «27 окт» (другой год — с годом).
static func _when(unix: float) -> String:
	if unix <= 0.0:
		return "новый"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var local := int(unix) + bias
	var now := int(Time.get_unix_time_from_system()) + bias
	var t := Time.get_datetime_dict_from_unix_time(local)
	var day := floori(local / 86400.0)
	var today := floori(now / 86400.0)
	var hm := "%d:%02d" % [t["hour"], t["minute"]]
	if day == today:
		return "сегодня в " + hm
	if day == today - 1:
		return "вчера в " + hm
	var s := "%d %s" % [t["day"], MONTHS[int(t["month"]) - 1]]
	if t["year"] != Time.get_datetime_dict_from_unix_time(now)["year"]:
		s += " %d" % t["year"]
	return s


static func _plural(n: int, forms: Array) -> String:
	var m10 := n % 10
	var m100 := n % 100
	if m10 == 1 and m100 != 11:
		return forms[0]
	if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14):
		return forms[1]
	return forms[2]
