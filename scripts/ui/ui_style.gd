class_name UiStyle
extends RefCounted
## Цвета, шрифты, иконки и стили интерфейса.
## BASE (#F5F3EF) — подложки панелей; BRAND (#C9B8A6) — фирменный цвет:
## только обводки, выделение и акценты, а не всё подряд.

const BASE := Color("#F5F3EF")
const BRAND := Color("#C9B8A6")
const BRAND_DARK := Color("#8C7A68")
const TEXT := Color("#3E342B")
const MUTED := Color("#8A7D70")
const BAD := Color("#C4554A")
const GOOD := Color("#5E8C4A")
const SURFACE := Color("#EDE8E1")
const SURFACE_HOVER := Color("#E6DED3")

const FONT_FILE := preload("res://assets/fonts/Nunito.ttf")

static var _fonts := {}
static var _icons := {}


## Nunito нужной толщины (шрифт переменный: 200–1000).
static func font(weight := 600) -> FontVariation:
	if not _fonts.has(weight):
		var f := FontVariation.new()
		f.base_font = FONT_FILE
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[weight] = f
	return _fonts[weight]


static func icon(icon_name: String) -> Texture2D:
	if not _icons.has(icon_name):
		var path := "res://assets/icons/%s.png" % icon_name
		_icons[icon_name] = load(path) if ResourceLoader.exists(path) else null
	return _icons[icon_name]


static func box(bg: Color, radius := 14, margin := 12, border := 0, border_color := BRAND, shadow := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_color
	if shadow:
		sb.shadow_color = Color(0.24, 0.18, 0.12, 0.16)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 3)
	return sb


## Панель-подложка: светлая, с тонкой фирменной обводкой и мягкой тенью.
static func panel(radius := 16, margin := 12) -> StyleBoxFlat:
	return box(Color(BASE, 0.97), radius, margin, 2, BRAND, true)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	t.set_stylebox("normal", "Button", box(SURFACE, 12, 8))
	t.set_stylebox("hover", "Button", box(SURFACE_HOVER, 12, 8, 2, BRAND))
	t.set_stylebox("pressed", "Button", box(BRAND, 12, 8, 2, BRAND_DARK))
	t.set_stylebox("hover_pressed", "Button", box(BRAND.lightened(0.08), 12, 8, 2, BRAND_DARK))
	t.set_stylebox("disabled", "Button", box(Color(SURFACE, 0.6), 12, 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.7))
	t.set_color("icon_normal_color", "Button", Color.WHITE)
	t.set_color("icon_disabled_color", "Button", Color(1, 1, 1, 0.45))
	t.set_stylebox("background", "ProgressBar", box(SURFACE, 6, 0))
	t.set_stylebox("fill", "ProgressBar", box(BRAND_DARK, 6, 0))
	t.set_stylebox("slider", "HSlider", box(SURFACE, 4, 3))
	t.set_stylebox("grabber_area", "HSlider", box(BRAND, 4, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(BRAND_DARK, 4, 3))
	t.set_stylebox("panel", "TooltipPanel", box(Color(BASE, 0.98), 10, 8, 2, BRAND))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", font(600))
	t.set_stylebox("normal", "CheckButton", box(Color(0, 0, 0, 0), 10, 6))
	t.set_stylebox("hover", "CheckButton", box(SURFACE_HOVER, 10, 6))
	t.set_stylebox("pressed", "CheckButton", box(Color(0, 0, 0, 0), 10, 6))
	t.set_stylebox("hover_pressed", "CheckButton", box(SURFACE_HOVER, 10, 6))
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "CheckButton", TEXT)
	return t


static func label(text: String, size := 16, color := TEXT, weight := 600) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font(weight))
	return l


static func icon_rect(icon_name: String, size := 28) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(icon_name)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Ряд «иконка + число» для стоимости; недостающее — красным.
static func cost_row(cost: Dictionary, size := 18, check_inventory := true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id: String in cost:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 2)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(icon_rect(id, size))
		var enough := not check_inventory or Inventory.count(id) >= int(cost[id])
		item.add_child(label(str(cost[id]), size - 3, TEXT if enough else BAD, 800))
		item.tooltip_text = GameData.res_name(id)
		row.add_child(item)
	return row


## Кнопка-крестик закрытия: крестик ровно по центру квадратной кнопки.
static func close_button(side := 44.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(side, side)
	b.tooltip_text = "Закрыть"
	var ic := icon_rect("close", int(side * 0.42))
	ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ic.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ic.grow_vertical = Control.GROW_DIRECTION_BOTH
	b.add_child(ic)
	return b


## Плавное появление/исчезновение (с лёгким масштабом).
## Как fade, но сразу, без анимации.
static func fade_now(c: Control, shown: bool) -> void:
	c.set_meta("fade_seq", int(c.get_meta("fade_seq", 0)) + 1)
	if c.has_meta("fade_tween"):
		(c.get_meta("fade_tween") as Tween).kill()
		c.remove_meta("fade_tween")
	c.set_meta("fade_target", shown)
	c.visible = shown
	c.modulate.a = 1.0 if shown else 0.0
	c.scale = Vector2.ONE


## Плавно показывает или прячет окно. Без масштабирования: при нём буквы на каждом кадре
## по-разному ложатся на пиксели и текст «дрожит». Сначала окно пару кадров почти
## прозрачное — в них раскладывается и впервые рисуется содержимое (самые тяжёлые кадры),
## и только потом начинается проявление: иначе анимация перескакивала бы через начало.
static func fade(c: Control, shown: bool, duration := 0.18) -> void:
	if c.get_meta("fade_target", c.visible) == shown:
		return
	c.set_meta("fade_target", shown)
	var seq: int = c.get_meta("fade_seq", 0) + 1
	c.set_meta("fade_seq", seq)
	if c.has_meta("fade_tween"):
		(c.get_meta("fade_tween") as Tween).kill()
		c.remove_meta("fade_tween")
	c.scale = Vector2.ONE
	if not shown:
		var out := c.create_tween()
		c.set_meta("fade_tween", out)
		out.tween_property(c, "modulate:a", 0.0, duration * 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		out.tween_callback(c.hide)
		return
	if not c.visible and c.is_inside_tree():
		c.modulate.a = 0.01
		c.visible = true
		var tree := c.get_tree()
		await tree.process_frame
		await tree.process_frame
		# Пока ждали, окно могли закрыть (или открыть заново).
		if not is_instance_valid(c) or c.get_meta("fade_seq", 0) != seq:
			return
	c.visible = true
	var tw := c.create_tween()
	c.set_meta("fade_tween", tw)
	tw.tween_property(c, "modulate:a", 1.0, duration * 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
