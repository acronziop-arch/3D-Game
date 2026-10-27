class_name Rich
extends RefCounted
## Разметка подсказок и сообщений (BBCode для RichTextLabel): жирный заголовок,
## значки вместо названий ресурсов, клавиши в плашках, причины отказа красным
## со значком. Так информация читается с одного взгляда, а не одной строкой.

const SEP := "    "


static func icon(icon_name: String, size := 18) -> String:
	return "[img=%dx%d]res://assets/icons/%s.png[/img]" % [size, size, icon_name]


static func title(text: String) -> String:
	return "[b]%s[/b]" % text


static func muted(text: String) -> String:
	return "[color=#%s]%s[/color]" % [UiStyle.MUTED.to_html(false), text]


static func good(text: String) -> String:
	return "[color=#%s]%s[/color]" % [UiStyle.GOOD.to_html(false), text]


## Причина отказа: красным, со значком-предупреждением.
static func bad(text: String, size := 16) -> String:
	return "%s [color=#%s]%s[/color]" % [icon("warning", size), UiStyle.BAD.to_html(false), text]


## Клавиша или жест в плашке: «ЛКМ», «R».
static func key(text: String) -> String:
	return "[bgcolor=#%s][color=#%s] %s [/color][/bgcolor]" % [UiStyle.SURFACE_HOVER.to_html(false), UiStyle.TEXT.to_html(false), text]


## Время действия со значком часов.
static func time(seconds: float, size := 16) -> String:
	if seconds <= 0.0:
		return "%s %s" % [icon("timer", size), "сразу"]
	return "%s %d с" % [icon("timer", size), ceili(seconds)]


## Ресурсы значками: [иконка] 16  [иконка] 6. Недостающее — красным.
static func cost(items: Dictionary, size := 18, check_inventory := false) -> String:
	if items.is_empty():
		return muted("бесплатно")
	var parts: PackedStringArray = []
	for id: String in items:
		var n := str(items[id])
		if check_inventory and Inventory.count(id) < int(items[id]):
			n = "[color=#%s]%s[/color]" % [UiStyle.BAD.to_html(false), n]
		parts.append("%s %s" % [icon(id, size), n])
	return "  ".join(parts)


## Текст без разметки — для подсказок-всплывашек и замеров.
static func plain(text: String) -> String:
	var re := RegEx.create_from_string("\\[[^\\]]*\\]")
	return re.sub(text, "", true).replace("res://assets/icons/", "")


## Метка с разметкой: размер по содержимому, по центру, без прокрутки.
static func label(size := 15, color := UiStyle.TEXT, weight := 700) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("normal_font", UiStyle.font(weight))
	l.add_theme_font_override("bold_font", UiStyle.font(900))
	l.add_theme_font_size_override("normal_font_size", size)
	l.add_theme_font_size_override("bold_font_size", size + 1)
	l.add_theme_color_override("default_color", color)
	l.add_theme_constant_override("line_separation", 4)
	return l


## Ставит текст и подгоняет ширину: короткий — одной строкой, длинный — переносится по max_w.
static func fit(l: RichTextLabel, text: String, max_w: float, centered := true) -> void:
	l.text = ("[center]%s[/center]" % text) if centered else text
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size.x = 0.0
	var w := _measure(l, text)
	if w > max_w:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = max_w
	else:
		l.custom_minimum_size.x = w


## Ширина самой длинной строки: текст по шрифту плюс значки.
static func _measure(l: RichTextLabel, text: String) -> float:
	var font := l.get_theme_font("bold_font")
	var size := l.get_theme_font_size("normal_font_size")
	var w := 0.0
	for line in text.split("\n"):
		var icons := line.count("[img=")
		var icon_w := 0.0
		var re := RegEx.create_from_string("\\[img=(\\d+)x\\d+\\]")
		for m in re.search_all(line):
			icon_w += float(m.get_string(1)) + 2.0
		var bare := RegEx.create_from_string("\\[img[^\\]]*\\][^\\[]*\\[/img\\]").sub(line, "", true)
		bare = RegEx.create_from_string("\\[[^\\]]*\\]").sub(bare, "", true)
		w = maxf(w, font.get_string_size(bare, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + icon_w + icons * 2.0)
	return ceilf(w) + 8.0
