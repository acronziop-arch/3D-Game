class_name Minimap
extends Control
## Карта мира. Рисуется только разведанное: когда чанк загружается, его цвета
## (биомы, вода, рельеф) запоминаются в WorldState.explored и сохраняются вместе
## с миром. Одно общее полотно (CANVAS × CANVAS пикселей, пиксель — CELL метров)
## используют и мини-карта (слева сверху), и большая карта (MapPanel).
## Поверх полотна: здания, руины, метки игрока и стрелка камеры.

signal tapped(world_pos: Vector2)

## Пиксель полотна — 4 м: карта чёткая, но сохранение остаётся маленьким.
const CELL := 4.0
const PER_CHUNK := 8
const CANVAS := 512
const PAPER := Color("#E9E2D3")

## Общее полотно карты.
static var _img: Image
static var _tex: ImageTexture
static var _origin := Vector2i(-CANVAS / 2, -CANVAS / 2)
static var _dirty := false
static var _upload_cooldown := 0.0
static var _shader: Shader

var chunk_manager: ChunkManager
var camera_rig: CameraRig
var building_system: BuildingSystem
## Сколько метров по стороне видно.
var view_meters := 300.0
## Центр показа (мировые XZ). Мини-карта всегда следует за камерой.
var center := Vector2.ZERO
var follow_camera := true
var corner_radius := 14.0

var _view: TextureRect
## Поверх полотна: руины, здания, метки, стрелка камеры и рамка.
var _overlay: Control
var _redraw_timer := 0.0


static func ensure_canvas() -> void:
	if _img == null:
		_img = Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
		_img.fill(PAPER)
		_tex = ImageTexture.create_from_image(_img)


## Запоминает загруженный чанк: 4×4 «пикселя» по 8 м — цвет земли, вода, светотень.
static func explore(chunk: Chunk) -> void:
	ensure_canvas()
	if WorldState.explored.has(chunk.coord):
		var known: PackedByteArray = WorldState.explored[chunk.coord]
		if known.size() == PER_CHUNK * PER_CHUNK * 3:
			_paint_chunk(chunk.coord, known)
			return
	var bytes := PackedByteArray()
	bytes.resize(PER_CHUNK * PER_CHUNK * 3)
	var step := WorldGen.CHUNK_SIZE / PER_CHUNK
	for j in PER_CHUNK:
		for i in PER_CHUNK:
			var lx := (i + 0.5) * step
			var lz := (j + 0.5) * step
			var h := chunk.height_local(lx, lz)
			var c: Color
			if h < WorldGen.WATER_LEVEL:
				c = Color(0.55, 0.75, 0.86).lerp(Color(0.24, 0.45, 0.66), clampf(-h / 3.5, 0.0, 1.0))
			else:
				var k := clampi(roundi(lz / WorldGen.CELL), 0, WorldGen.RES) * (WorldGen.RES + 1) + clampi(roundi(lx / WorldGen.CELL), 0, WorldGen.RES)
				c = WorldGen.ground_color(chunk.colors[k], h, 1.0)
				# Светотень: склоны к северо-западу светлее, к юго-востоку темнее.
				var dx := chunk.height_local(minf(lx + 2.0, WorldGen.CHUNK_SIZE), lz) - chunk.height_local(maxf(lx - 2.0, 0.0), lz)
				var dz := chunk.height_local(lx, minf(lz + 2.0, WorldGen.CHUNK_SIZE)) - chunk.height_local(lx, maxf(lz - 2.0, 0.0))
				var shade := clampf(1.0 - (dx + dz) * 0.09, 0.72, 1.22)
				c = Color(c.r * shade, c.g * shade, c.b * shade).lerp(Color.WHITE, clampf((h - 12.0) / 60.0, 0.0, 0.25))
			var o := (j * PER_CHUNK + i) * 3
			bytes[o] = clampi(roundi(c.r * 255.0), 0, 255)
			bytes[o + 1] = clampi(roundi(c.g * 255.0), 0, 255)
			bytes[o + 2] = clampi(roundi(c.b * 255.0), 0, 255)
	WorldState.explored[chunk.coord] = bytes
	_paint_chunk(chunk.coord, bytes)


static func _paint_chunk(coord: Vector2i, bytes: PackedByteArray) -> void:
	# Старые сохранения хранили 4×4 точки на чанк — растягиваем.
	var n := roundi(sqrt(bytes.size() / 3.0))
	if n != PER_CHUNK and n > 0:
		var up := PackedByteArray()
		up.resize(PER_CHUNK * PER_CHUNK * 3)
		for j in PER_CHUNK:
			for i in PER_CHUNK:
				var o := ((j * n / PER_CHUNK) * n + (i * n / PER_CHUNK)) * 3
				var t := (j * PER_CHUNK + i) * 3
				up[t] = bytes[o]
				up[t + 1] = bytes[o + 1]
				up[t + 2] = bytes[o + 2]
		bytes = up
	for j in PER_CHUNK:
		for i in PER_CHUNK:
			var px := coord.x * PER_CHUNK + i - _origin.x
			var py := coord.y * PER_CHUNK + j - _origin.y
			if px < 0 or py < 0 or px >= CANVAS or py >= CANVAS:
				continue
			var o := (j * PER_CHUNK + i) * 3
			_img.set_pixel(px, py, Color8(bytes[o], bytes[o + 1], bytes[o + 2]))
	_dirty = true


## Сдвигает полотно, если камера ушла далеко от его середины.
static func recenter_if_needed(world: Vector2) -> void:
	ensure_canvas()
	var cell := Vector2i(floori(world.x / CELL), floori(world.y / CELL))
	var rel := cell - _origin
	var margin := CANVAS / 5
	if rel.x > margin and rel.y > margin and rel.x < CANVAS - margin and rel.y < CANVAS - margin:
		return
	_origin = cell - Vector2i(CANVAS / 2, CANVAS / 2)
	_img.fill(PAPER)
	for c: Vector2i in WorldState.explored:
		_paint_chunk(c, WorldState.explored[c])


## Перерисовывает полотно из сохранения (после загрузки мира).
static func reset_canvas() -> void:
	ensure_canvas()
	_img.fill(PAPER)
	for c: Vector2i in WorldState.explored:
		_paint_chunk(c, WorldState.explored[c])


func _ready() -> void:
	ensure_canvas()
	clip_contents = true
	_view = TextureRect.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var atlas := AtlasTexture.new()
	atlas.atlas = _tex
	_view.texture = atlas
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type canvas_item;
// Скруглённые углы карты и мягкая тень по краю. Маска считается по положению
// внутри блока (UV у куска полотна — это координаты всего полотна).
uniform vec2 size = vec2(100.0);
uniform float radius = 14.0;
varying vec2 local;
void vertex() {
	local = VERTEX;
}
void fragment() {
	vec2 p = local;
	vec2 q = abs(p - size * 0.5) - (size * 0.5 - vec2(radius));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	vec4 c = texture(TEXTURE, UV);
	float edge = smoothstep(-6.0, 0.0, d);
	c.rgb *= 1.0 - edge * 0.12;
	c.a *= 1.0 - smoothstep(-1.0, 0.5, d);
	COLOR = c;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	_view.material = mat
	add_child(_view)
	move_child(_view, 0)
	# Значки рисуются отдельным слоем поверх полотна (иначе полотно их закрывает).
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _process(delta: float) -> void:
	if camera_rig == null:
		return
	var cam := Vector2(camera_rig.position.x, camera_rig.position.z)
	recenter_if_needed(cam)
	if follow_camera:
		center = cam
	# Полотно 512×512 отправляется видеокарте не чаще 4 раз в секунду: новые чанки
	# при полёте появляются почти каждый кадр, а мегабайт на кадр — заметная нагрузка.
	_upload_cooldown -= delta
	if _dirty and _upload_cooldown <= 0.0:
		_tex.update(_img)
		_dirty = false
		_upload_cooldown = 0.25
	var atlas := _view.texture as AtlasTexture
	var px := (center / CELL) - Vector2(_origin)
	var span := view_meters / CELL
	var aspect := size.x / maxf(size.y, 1.0)
	atlas.region = Rect2(px - Vector2(span * aspect, span) * 0.5, Vector2(span * aspect, span))
	(_view.material as ShaderMaterial).set_shader_parameter("size", size)
	(_view.material as ShaderMaterial).set_shader_parameter("radius", corner_radius)
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 0.1 if Platform.is_mobile() else 0.05
		_overlay.queue_redraw()


## Мировые XZ → точка на карте.
func world_to_map(p: Vector2) -> Vector2:
	var k := size.y / view_meters
	return size * 0.5 + (p - center) * k


func map_to_world(p: Vector2) -> Vector2:
	var k := size.y / view_meters
	return center + (p - size * 0.5) / k


func _draw_overlay() -> void:
	if camera_rig == null:
		return
	var ci := _overlay
	var k := size.y / view_meters
	var rect := Rect2(Vector2.ZERO, size).grow(-2.0)
	# Руины в разведанной части — коричневые «развалины».
	if chunk_manager and chunk_manager.gen:
		var half := Vector2(size.x, size.y) * 0.5 / k
		var c0 := Vector2i(floori((center.x - half.x) / WorldGen.RUIN_CELL), floori((center.y - half.y) / WorldGen.RUIN_CELL))
		var c1 := Vector2i(floori((center.x + half.x) / WorldGen.RUIN_CELL), floori((center.y + half.y) / WorldGen.RUIN_CELL))
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var site := chunk_manager.gen.ruin_site(Vector2i(cx, cz))
				if site.is_empty():
					continue
				var sc: Vector2 = site["center"]
				if not WorldState.explored.has(ChunkManager.chunk_of(sc.x, sc.y)):
					continue
				var mp := world_to_map(sc)
				if rect.has_point(mp):
					_draw_ruin(ci, mp, maxf(4.0, WorldGen.RUIN_RADIUS * k * 0.35))
	# Здания.
	if building_system:
		for b in building_system.buildings:
			if not is_instance_valid(b):
				continue
			var mp := world_to_map(Vector2(b.position.x, b.position.z))
			if not rect.has_point(mp):
				continue
			var s := clampf(maxf(b.footprint.size.x, b.footprint.size.y) * k, 3.0, 14.0)
			ci.draw_rect(Rect2(mp - Vector2(s, s) * 0.5, Vector2(s, s)), Color("#8C5A3C"))
			ci.draw_rect(Rect2(mp - Vector2(s, s) * 0.5, Vector2(s, s)), Color("#3E342B"), false, 1.0)
	# Метки игрока: дальние прижимаются к краю карты, чтобы было видно, где они.
	var small := size.y < 200.0
	var pad := corner_radius * 0.6 + (9.0 if small else 13.0)
	for m: Dictionary in WorldState.markers:
		var p: Vector3 = m["pos"]
		var mp := world_to_map(Vector2(p.x, p.z))
		mp = mp.clamp(Vector2(pad, pad), size - Vector2(pad, pad))
		draw_marker(ci, mp, m, 0.7 if small else 1.0)
	# Камера: стрелка по направлению взгляда.
	var cam := world_to_map(Vector2(camera_rig.position.x, camera_rig.position.z))
	var yaw := camera_rig.rotation.y
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	var tip := cam + fwd * 9.0
	var pts := PackedVector2Array([tip, cam - fwd * 5.0 + side * 6.0, cam - fwd * 2.0, cam - fwd * 5.0 - side * 6.0])
	ci.draw_colored_polygon(pts, Color("#3E342B"))
	ci.draw_polyline(pts + PackedVector2Array([tip]), Color.WHITE, 1.5, true)
	# Рамка по тому же скруглению, что и маска карты.
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_corner_radius_all(roundi(corner_radius))
	frame.set_border_width_all(2)
	frame.border_color = UiStyle.BRAND
	frame.anti_aliasing = true
	ci.draw_style_box(frame, Rect2(Vector2.ZERO, size))


static func _marker_color(m: Dictionary) -> Color:
	var c: Variant = m.get("color", Color("#E05A4E"))
	return c if c is Color else Color(str(c))


## Метка на карте: цветной кружок с белой обводкой и значком.
static func draw_marker(ci: CanvasItem, at: Vector2, m: Dictionary, scale := 1.0) -> void:
	var r := 11.0 * scale
	ci.draw_circle(at + Vector2(0, 1.5), r + 1.5, Color(0, 0, 0, 0.18))
	ci.draw_circle(at, r + 1.5, Color.WHITE)
	ci.draw_circle(at, r, _marker_color(m))
	var icon := UiStyle.icon("marker_" + str(m.get("icon", "flag")))
	if icon:
		var s := r * 1.4
		ci.draw_texture_rect(icon, Rect2(at - Vector2(s, s) * 0.5, Vector2(s, s)), false)


static func _draw_ruin(ci: CanvasItem, at: Vector2, r: float) -> void:
	for i in 3:
		var a := i * 2.1 + 0.4
		var p := at + Vector2(cos(a), sin(a)) * r * 0.6
		ci.draw_rect(Rect2(p - Vector2(r * 0.35, r * 0.25), Vector2(r * 0.7, r * 0.5)), Color("#8A7A66"))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(map_to_world((event as InputEventMouseButton).position))
		accept_event()
