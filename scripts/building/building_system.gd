class_name BuildingSystem
extends Node3D
## Размещение зданий: полупрозрачный «призрак» следует за мышью (на телефоне —
## за пальцем), стоит на сетке 1 м, поворачивается на любой угол (шаг 15°,
## на ПК — R / Shift+R, Ctrl+колесо) и подсвечивается розовым или красным.
## Двери и окна в призраке выделены тёплым светлым оттенком.
## Режимы размещения (GameData.BUILDINGS[id].place):
##   land   — суша или деревянный настил; над водой показывается красный крестик;
##   water  — настил: хотя бы частью над водой; рядом с другим настилом
##            прилипает к нему краем и поворачивается так же;
##   bridge — концы моста на берегах, середина над водой.
## Уже построенное здание можно передвинуть и повернуть (start_move).
## Плитки дорожек ("snap") цепляются к соседним; в режиме «Плитки» их можно
## класть касанием или вести пальцем (paint_*), в режиме «Плавная» дорожку рисует
## PathSystem. Ограды ("group": "fence") ставятся, как обычные постройки (можно вплотную
## и внахлёст друг к другу), а в режиме «Протянуть» их ведёт пальцем FenceSystem.

signal placed(building: Building)

const MAX_UNEVENNESS := 1.6
## Шаг сетки размещения: мелкий, чтобы здание вставало точно, куда нужно.
const GRID := 0.25
const ROTATE_STEP := PI / 12.0
const PLATFORM_SIZE := 4.0
const PLATFORM_TOP := 0.8
const PLATFORM_MAX_DEPTH := 9.0
## Розовый хорошо виден на траве; «нельзя» — тёмно-красный, чтобы его не спутать с розовым.
const VALID_TINT := Color(1.0, 0.42, 0.86, 0.34)
const INVALID_TINT := Color(0.9, 0.16, 0.08, 0.38)

var chunk_manager: ChunkManager
var buildings: Array[Building] = []
var selected_id := ""
var is_valid := false
var invalid_reason := ""
## true, если призрак сухопутного здания стоит над водой.
var over_water := false
## Здание, которое сейчас передвигают (null — ставим новое).
var moving: Building
## Культура для новых грядок.
var crop_choice := "wheat"

var _ghost: Node3D
var _ghost_materials: Array[ShaderMaterial] = []
var _ghost_target := Vector3.ZERO
var _yaw := 0.0
var _ghost_yaw := 0.0
var _has_target := false
var _cross: Sprite3D
var _ghost_scale := 0.6
var _ghost_normal := Vector3.UP
## Рисование дорожки: последняя положенная плитка.
var _painting := false
var _paint_last: Building


func _ready() -> void:
	Building.ground_height = func(x: float, z: float) -> float: return chunk_manager.get_height(x, z)
	_cross = Sprite3D.new()
	_cross.texture = load("res://assets/icons/cross.png")
	_cross.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cross.no_depth_test = true
	_cross.pixel_size = 0.012
	_cross.render_priority = 5
	_cross.visible = false
	add_child(_cross)


func select(building_id: String) -> void:
	var keep_yaw := _yaw if selected_id != "" else 0.0
	cancel()
	selected_id = building_id
	_yaw = keep_yaw
	var data := ModelLibrary.building(building_id)
	_ghost = Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = data["mesh"]
	_ghost.add_child(body)
	_ghost_materials = Building.apply_ghost_materials(body, true)
	if data["rotor_mesh"]:
		var rotor := MeshInstance3D.new()
		rotor.mesh = data["rotor_mesh"]
		rotor.position = data["pivot"]
		_ghost.add_child(rotor)
		_ghost_materials.append_array(Building.apply_ghost_materials(rotor, true))
	for m in _ghost_materials:
		m.set_shader_parameter("tint", VALID_TINT)
	_ghost.visible = false
	_ghost_scale = 0.6
	_ghost.scale = Vector3.ONE * _ghost_scale
	add_child(_ghost)
	_has_target = false
	_painting = false


func cancel() -> void:
	if moving:
		# Перемещение отменено — здание остаётся, где было.
		moving.visible = true
		moving = null
	selected_id = ""
	over_water = false
	_cross.visible = false
	if _ghost:
		_ghost.queue_free()
		_ghost = null


## Поворот призрака: шаг 15° (знак — направление).
func rotate_ghost(direction := 1.0) -> void:
	_yaw = wrapf(_yaw + ROTATE_STEP * signf(direction), -PI, PI)


## Плавный поворот на произвольный угол (колесо мыши, удержание кнопки).
func rotate_ghost_by(angle: float) -> void:
	_yaw = wrapf(_yaw + angle, -PI, PI)


## Группы, чьи постройки можно ставить вплотную и внахлёст друг к другу.
const OVERLAP_GROUPS := ["fence", "path"]


func place_mode(building_id: String) -> String:
	return GameData.BUILDINGS[building_id].get("place", "land")


## Начинает перемещение готового здания: оно прячется, вместо него — призрак.
func start_move(b: Building) -> void:
	select(b.id)
	moving = b
	_yaw = b.yaw
	b.visible = false
	_ghost.position = b.position
	_ghost.rotation.y = b.yaw
	_ghost_yaw = b.yaw
	_ghost_scale = 1.0
	_ghost.scale = Vector3.ONE
	_ghost_target = b.position
	_has_target = true


## Вызывается каждый кадр с точкой земли под мышью (или null, если мимо).
func update_ghost(hit: Variant, delta: float) -> void:
	if _ghost == null:
		return
	if hit == null:
		_ghost.visible = false
		_cross.visible = false
		return
	var p: Vector3 = hit
	var def: Dictionary = GameData.BUILDINGS[selected_id]
	if is_smooth_path():
		# Плавную дорожку рисуют пальцем — призрак плитки не нужен.
		_ghost.visible = false
		_cross.visible = false
		is_valid = false
		return
	var target := Vector3(snappedf(p.x, GRID), 0, snappedf(p.z, GRID))
	if def.has("snap"):
		# Мелкие секции ставим точнее сетки, а рядом с такой же — цепляем к её концу.
		target = Vector3(snappedf(p.x, 0.25), 0, snappedf(p.z, 0.25))
		if moving == null:
			var snapped := _snap_group(p, def["snap"])
			if snapped["snapped"]:
				target = snapped["pos"]
				_yaw = snapped["yaw"]
	if selected_id == "platform":
		var snapped := _snap_platform(p)
		target = snapped["pos"]
		if snapped["snapped"]:
			_yaw = snapped["yaw"]
	var check := _validate(target, _yaw)
	target.y = check["y"]
	is_valid = check["reason"] == ""
	invalid_reason = check["reason"]
	over_water = check.get("water", false)
	_ghost_target = target
	if not _has_target:
		_has_target = true
		_ghost.position = target
		_ghost_yaw = _yaw
	_ghost.visible = true

	var k := 1.0 - exp(-18.0 * delta)
	_ghost.position = _ghost.position.lerp(target, k)
	_ghost_yaw = lerp_angle(_ghost_yaw, _yaw, k)
	_ghost_scale = lerpf(_ghost_scale, 1.0, k)
	_ghost_normal = ground_normal(target.x, target.z) if def.get("tilt", false) else Vector3.UP
	var rot := Basis(Vector3.UP, _ghost_yaw)
	if not _ghost_normal.is_equal_approx(Vector3.UP):
		rot = Basis(Quaternion(Vector3.UP, _ghost_normal)) * rot
	_ghost.basis = rot.scaled(Vector3.ONE * _ghost_scale)
	for m in _ghost_materials:
		var tint: Color = m.get_shader_parameter("tint")
		m.set_shader_parameter("tint", tint.lerp(VALID_TINT if is_valid else INVALID_TINT, k))
	# Красный крестик: сухопутное здание над водой.
	if over_water:
		if not _cross.visible:
			_cross.visible = true
			_cross.scale = Vector3.ONE * 0.3
		var top: float = (ModelLibrary.building(selected_id)["bounds"] as AABB).end.y
		_cross.position = _ghost.position + Vector3(0, minf(top, 6.0) * 0.6 + 0.8, 0)
		_cross.scale = _cross.scale.lerp(Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.06), k)
	else:
		_cross.visible = false


## Настил прилипает краем к соседнему, только если палец рядом со свободной
## клеткой возле него (та же сетка и поворот); иначе ставится свободно.
func _snap_platform(p: Vector3) -> Dictionary:
	var free := {"pos": Vector3(snappedf(p.x, GRID), 0, snappedf(p.z, GRID)), "snapped": false}
	var platforms: Array[Building] = []
	for b in buildings:
		if is_instance_valid(b) and b.id == "platform" and b != moving:
			platforms.append(b)
	var best := free
	var best_d := PLATFORM_SIZE * 0.85
	for b in platforms:
		if Vector2(b.position.x - p.x, b.position.z - p.z).length() > PLATFORM_SIZE * 2.0:
			continue
		var basis := Basis(Vector3.UP, b.yaw)
		for side: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var slot := b.position + basis * (side * PLATFORM_SIZE)
			slot.y = 0.0
			var d := Vector2(slot.x - p.x, slot.z - p.z).length()
			if d >= best_d or _platform_at(slot, platforms):
				continue
			best_d = d
			best = {"pos": slot, "snapped": true, "yaw": b.yaw}
	return best


static func _platform_at(slot: Vector3, platforms: Array[Building]) -> bool:
	for o in platforms:
		if Vector2(o.position.x - slot.x, o.position.z - slot.z).length() < PLATFORM_SIZE * 0.5:
			return true
	return false


## Ограды и дорожки: новая секция цепляется к ближайшему свободному концу такой же.
## Ограда — продолжение по прямой или угол 90°; дорожка — любая из четырёх сторон.
func _snap_group(p: Vector3, snap: Dictionary) -> Dictionary:
	var group: String = snap["group"]
	var length: float = snap["len"]
	var grid: bool = snap.get("grid", false)
	var best := {"snapped": false}
	var best_d := length * 0.8
	for b in buildings:
		if not is_instance_valid(b) or b == moving or not GameData.BUILDINGS[b.id].has("snap"):
			continue
		if GameData.BUILDINGS[b.id]["snap"]["group"] != group:
			continue
		var c := Vector2(b.position.x, b.position.z)
		if c.distance_to(Vector2(p.x, p.z)) > length * 2.2:
			continue
		var basis := Basis(Vector3.UP, b.yaw)
		var ax := basis * Vector3.RIGHT
		var az := basis * Vector3.BACK
		var candidates := []
		if grid:
			for d: Vector3 in [ax, -ax, az, -az]:
				candidates.append([b.position + d * length, b.yaw])
		else:
			for sgn: float in [1.0, -1.0]:
				var end := b.position + ax * sgn * length * 0.5
				candidates.append([b.position + ax * sgn * length, b.yaw])
				candidates.append([end + az * length * 0.5, b.yaw + PI * 0.5])
				candidates.append([end - az * length * 0.5, b.yaw + PI * 0.5])
		for cand: Array in candidates:
			var pos: Vector3 = cand[0]
			var d := Vector2(pos.x - p.x, pos.z - p.z).length()
			if d >= best_d or _slot_taken(pos, group):
				continue
			best_d = d
			best = {"snapped": true, "pos": Vector3(pos.x, 0, pos.z), "yaw": wrapf(cand[1], -PI, PI)}
	return best


func _slot_taken(pos: Vector3, group: String) -> bool:
	for b in buildings:
		if is_instance_valid(b) and b != moving and GameData.BUILDINGS[b.id].get("snap", {}).get("group", "") == group \
				and Vector2(b.position.x - pos.x, b.position.z - pos.z).length() < 0.6:
			return true
	return false


## Наклон земли под дорожкой (по четырём точкам вокруг).
func ground_normal(x: float, z: float) -> Vector3:
	var e := 0.9
	var hx := chunk_manager.get_height(x + e, z) - chunk_manager.get_height(x - e, z)
	var hz := chunk_manager.get_height(x, z + e) - chunk_manager.get_height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func is_path(id := selected_id) -> bool:
	return id.begins_with("path_")


## Выбрана дорожка в режиме «Плавная».
func is_smooth_path() -> bool:
	return moving == null and is_path()


## Вид дорожки для PathSystem: dirt / wood / stone / brick.
func path_type() -> String:
	return selected_id.substr(5)


## Можно ли «рисовать» выбранное плитками (дорожки в режиме «Плитки»).
func is_paintable() -> bool:
	return selected_id != "" and moving == null and GameData.BUILDINGS[selected_id].get("snap", {}).get("grid", false)


## Начало рисования дорожки: первая плитка — там, где сейчас призрак.
func paint_begin() -> String:
	_painting = true
	_paint_last = null
	return try_place()


## Палец или мышь ушли дальше: кладём плитки одна за другой по направлению движения.
func paint_to(p: Vector3) -> String:
	if not _painting or selected_id == "":
		return ""
	var length: float = GameData.BUILDINGS[selected_id]["snap"]["len"]
	if not is_instance_valid(_paint_last):
		# Первая плитка не легла (мешало что-то) — кладём, как только место подходит.
		var start := Vector3(snappedf(p.x, 0.25), 0, snappedf(p.z, 0.25))
		var first := _validate(start, _yaw)
		if first["reason"] != "":
			return ""
		start.y = first["y"]
		_ghost_target = start
		_has_target = true
		is_valid = true
		return try_place()
	for i in 6:
		if not is_instance_valid(_paint_last):
			return ""
		var from := _paint_last.position
		var d := Vector2(p.x - from.x, p.z - from.z)
		if d.length() < length * 0.98:
			return ""
		var dir := d.normalized()
		var target := Vector3(from.x + dir.x * length, 0, from.z + dir.y * length)
		_yaw = atan2(dir.x, dir.y)
		var check := _validate(target, _yaw)
		target.y = check["y"]
		_ghost_target = target
		_has_target = true
		is_valid = check["reason"] == ""
		invalid_reason = check["reason"]
		if not is_valid:
			return invalid_reason
		var reason := try_place()
		if reason != "":
			return reason
	return ""


func paint_end() -> void:
	_painting = false
	_paint_last = null


## Ограду можно протянуть пальцем любой линией (FenceSystem) — не при переносе.
func is_fence() -> bool:
	return selected_id != "" and moving == null and GameData.BUILDINGS[selected_id].has("drawn")


## Где стоит призрак (null — призрака нет или место ещё не выбрано).
func ghost_position() -> Variant:
	return _ghost_target if _ghost != null and _has_target else null


## Касается ли палец призрака здания (чтобы тянуть его): по очертанию призрака на экране
## с запасом slack (ед. интерфейса) — иначе мелкую ограду или кол издалека не ухватить.
func ghost_hit(cam: Camera3D, screen: Vector2, slack: float) -> bool:
	if _ghost == null or not _has_target:
		return false
	var b: AABB = ModelLibrary.building(selected_id)["bounds"]
	var basis := Basis(Vector3.UP, _yaw)
	var rect := Rect2()
	var seen := false
	for i in 8:
		var corner := Vector3(b.end.x if (i & 1) != 0 else b.position.x, b.end.y if (i & 2) != 0 else b.position.y,
			b.end.z if (i & 4) != 0 else b.position.z)
		var w := _ghost_target + basis * corner
		if cam.is_position_behind(w):
			continue
		var s := cam.unproject_position(w)
		rect = rect.expand(s) if seen else Rect2(s, Vector2.ZERO)
		seen = true
	return seen and rect.grow(slack).has_point(screen)


## Высота верха настила в точке (или -INF, если настила нет).
func platform_top(x: float, z: float, ignore: Building = null) -> float:
	var p := Vector2(x, z)
	for b in buildings:
		if is_instance_valid(b) and b.id == "platform" and b != ignore and Building.obb_has_point(b.obb(0.05), p):
			return PLATFORM_TOP
	return -INF


func _validate(target: Vector3, angle: float) -> Dictionary:
	var mode := place_mode(selected_id)
	var box := Building.obb_for(selected_id, target, angle)
	var cost: Dictionary = GameData.BUILDINGS[selected_id]["cost"]
	var result := {"y": 0.0, "reason": ""}
	if GameData.BUILDINGS[selected_id].has("plant"):
		result["y"] = chunk_manager.get_height(target.x, target.z)
		result["reason"] = chunk_manager.can_plant_tree(target)
		return result
	match mode:
		"water":
			var wet := 0
			var deepest := INF
			var samples := Building.obb_samples(box, 3)
			for sp in samples:
				var h := chunk_manager.get_height(sp.x, sp.y)
				deepest = minf(deepest, h)
				if h < WorldGen.WATER_LEVEL - 0.15:
					wet += 1
			result["y"] = WorldGen.WATER_LEVEL
			# Постройка на сваях (хижина, склад) — серединой над водой, настил — хоть краем.
			var pier := selected_id != "platform"
			var other := _overlaps(Building.obb_for(selected_id, target, angle, -0.25), mode)
			if wet < 1:
				result["reason"] = "%s ставится на воду" % GameData.BUILDINGS[selected_id]["name"] if pier \
					else "Настил ставится на воду — хотя бы краем"
			elif pier and chunk_manager.get_height(target.x, target.z) > WorldGen.WATER_LEVEL - 0.15:
				result["reason"] = "Сдвиньте дальше от берега — середина должна быть над водой"
			elif deepest < WorldGen.WATER_LEVEL - PLATFORM_MAX_DEPTH:
				result["reason"] = "Слишком глубоко для свай"
			elif other:
				result["reason"] = "Здесь уже есть настил" if other.id == "platform" else "Мешает другое здание"
		"bridge":
			var basis := Basis(Vector3.UP, angle)
			var a := target + basis * Vector3(0, 0, 6.6)
			var b := target + basis * Vector3(0, 0, -6.6)
			var ha := chunk_manager.get_height(a.x, a.z)
			var hb := chunk_manager.get_height(b.x, b.z)
			var hm := chunk_manager.get_height(target.x, target.z)
			result["y"] = maxf(maxf(ha, hb) - 0.35, WorldGen.WATER_LEVEL + 0.2)
			if ha < WorldGen.WATER_LEVEL + 0.2 or hb < WorldGen.WATER_LEVEL + 0.2:
				result["reason"] = "Оба конца моста должны стоять на берегу"
			elif hm > WorldGen.WATER_LEVEL - 0.2:
				result["reason"] = "Мост строится над водой — поверните его поперёк реки" + _key("R")
			elif absf(ha - hb) > 1.4:
				result["reason"] = "Берега на разной высоте"
		_:
			var under := _ground_under(selected_id, target, angle, moving)
			var lo: float = under["lo"]
			var hi: float = under["hi"]
			var any_platform: bool = under["platform"]
			if under["water"]:
				result["water"] = true
				result["reason"] = "Настил должен быть под всем зданием — добавьте блоков" if any_platform \
					else "Здесь вода — сначала постройте деревянный настил"
			result["y"] = _land_y(selected_id, target, under)
			var def: Dictionary = GameData.BUILDINGS[selected_id]
			if result["reason"] == "" and any_platform and def.get("ground_only", false):
				result["reason"] = "Копать можно только землю — не на настиле"
			elif result["reason"] == "" and hi - lo > MAX_UNEVENNESS:
				result["reason"] = "Слишком неровно — выровняйте землю" + _key("3")
	if result["reason"] == "":
		var shrunk := Building.obb_for(selected_id, target, angle, -0.2)
		if _props_inside(shrunk):
			result["reason"] = "Мешают деревья или камни — добудьте их" + _key("1")
		elif chunk_manager.has_chest_in_rect(Building.footprint_for(selected_id, target, angle)):
			result["reason"] = "Здесь лежит сундук"
		elif (mode != "water" or selected_id != "platform") and _blocked(target, angle, -0.45 if GameData.BUILDINGS[selected_id].has("snap") else -0.15):
			result["reason"] = "Мешает другое здание"
		elif moving == null and not Inventory.has_all(cost):
			result["reason"] = "Не хватает: %s" % Rich.cost(Inventory.missing(cost), 16)
	return result


## Земля под «пятном» стен (свесы крыши могут нависать над водой — их не считаем):
## {"lo", "hi" — нижняя и верхняя точки, "platform" — стоит на настиле, "water" — где-то вода}.
func _ground_under(id: String, target: Vector3, angle: float, ignore: Building) -> Dictionary:
	var out := {"lo": INF, "hi": -INF, "platform": false, "water": false}
	for sp in Building.obb_samples(Building.obb_for(id, target, angle, -0.35), 4):
		var h := chunk_manager.get_height(sp.x, sp.y)
		var top := platform_top(sp.x, sp.y, ignore)
		if top > -INF:
			out["platform"] = true
			h = top
		elif h < WorldGen.WATER_LEVEL + 0.2:
			out["water"] = true
		out["lo"] = minf(out["lo"], h)
		out["hi"] = maxf(out["hi"], h)
	return out


## Высота здания на суше: по самой высокой точке под стенами (цоколь уходит в землю),
## на настиле — по настилу, плитка дорожки — по середине, вдоль склона.
func _land_y(id: String, target: Vector3, under: Dictionary) -> float:
	if under["platform"]:
		return PLATFORM_TOP if under["hi"] <= PLATFORM_TOP + 0.01 else under["hi"] - 0.1
	if GameData.BUILDINGS[id].get("tilt", false):
		return chunk_manager.get_height(target.x, target.z) - 0.02
	return under["hi"] - 0.1


## Глубина цоколя: на сильно разрытой земле здание уходит в склон, а не висит над ямой.
const SETTLE_DEPTH := 1.1


## Землю под зданиями выровняли (вызывается во время мазка, несколько раз в секунду):
## здания встают на новую поверхность сразу — не висят в воздухе и не тонут в насыпи.
func reground_area(rect: Rect2) -> void:
	for b in buildings:
		if not is_instance_valid(b) or b == moving or not b.footprint.intersects(rect):
			continue
		var def: Dictionary = GameData.BUILDINGS[b.id]
		var y := b.position.y
		match place_mode(b.id):
			"water":
				continue
			"bridge":
				var basis := Basis(Vector3.UP, b.yaw)
				var a := b.position + basis * Vector3(0, 0, 6.6)
				var e := b.position + basis * Vector3(0, 0, -6.6)
				y = maxf(maxf(chunk_manager.get_height(a.x, a.z), chunk_manager.get_height(e.x, e.z)) - 0.35,
					WorldGen.WATER_LEVEL + 0.2)
			_:
				var under := _ground_under(b.id, b.position, b.yaw, b)
				y = _land_y(b.id, b.position, under)
				if not under["platform"] and not def.get("tilt", false):
					y = minf(y, under["lo"] + SETTLE_DEPTH)
		var tilt: bool = def.get("tilt", false) and place_mode(b.id) == "land"
		var normal := ground_normal(b.position.x, b.position.z) if tilt else b.ground_normal
		if normal.y < 0.5:
			normal = b.ground_normal
		# Высота та же — но меш, который лежит по земле, всё равно укладываем заново.
		if absf(y - b.position.y) < 0.004 and normal.is_equal_approx(b.ground_normal) and not b.follows_ground():
			continue
		var entry: Variant = _save_entry(b)
		b.position.y = y
		if tilt:
			b.ground_normal = normal
			b.basis = Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, b.yaw)
		b.refit_ground()
		if entry:
			entry["pos"] = b.position
			if tilt:
				entry["normal"] = normal


## Подсказка клавиши — только на ПК.
static func _key(k: String) -> String:
	return "" if Platform.using_touch else " [%s]" % k


func _props_inside(box: Dictionary) -> bool:
	var h: Vector2 = box["h"]
	var r := h.length()
	var rect := Rect2(box["c"] - Vector2(r, r), Vector2(r, r) * 2.0)
	for p in chunk_manager.props_in_rect(rect, true):
		if not GameData.blocks_building(p["id"]):
			continue
		var chunk: Chunk = p["chunk"]
		var pos: Vector3 = chunk.to_global(p["pos"])
		if Building.obb_has_point(box, Vector2(pos.x, pos.z)):
			return true
	return false


## Куда сдвинуть призрак после постройки, чтобы следующая не легла на только что
## поставленную: ближайшее свободное место справа от неё (как видит камера), слева,
## дальше или ближе. right — направление «вправо» на экране.
func free_spot_near(p: Vector3, right: Vector3) -> Vector3:
	right = Vector3(right.x, 0, right.z).normalized()
	if right == Vector3.ZERO:
		right = Vector3.RIGHT
	var fwd := Vector3(-right.z, 0, right.x)
	var r: Rect2 = ModelLibrary.building(selected_id)["base"]
	var step := maxf(r.size.x, r.size.y) + 0.4
	for k: float in [1.0, 2.0]:
		for dir: Vector3 in [right, -right, fwd, -fwd]:
			var t := p + dir * step * k
			t = Vector3(snappedf(t.x, GRID), 0, snappedf(t.z, GRID))
			var check := _validate(t, _yaw)
			# Нехватка ресурсов — не помеха месту.
			if check["reason"] == "" or check["reason"].begins_with("Не хватает"):
				t.y = check["y"]
				return t
	var t := p + right * step
	t.y = chunk_manager.get_height(t.x, t.z)
	return t


## Мешает ли другая постройка на суше. Сталкиваются пятна у земли (без свесов крыш,
## козырьков и вывесок): мелочь встаёт вплотную к стенам и друг к другу. Два высоких
## здания сравниваются целиком — иначе их крыши вошли бы одна в другую.
func _blocked(target: Vector3, angle: float, shrink: float) -> bool:
	var group: String = GameData.BUILDINGS[selected_id].get("group", "")
	var tall := _is_tall(selected_id)
	var base := Building.base_obb_for(selected_id, target, angle, shrink)
	var full := Building.obb_for(selected_id, target, angle, shrink)
	for b in buildings:
		if not is_instance_valid(b) or b == moving or b.id == "platform":
			continue
		if group in OVERLAP_GROUPS and GameData.BUILDINGS[b.id].get("group", "") == group:
			continue
		if tall and _is_tall(b.id):
			if Building.obb_overlap(full, b.obb()):
				return true
		elif Building.obb_overlap(base, Building.base_obb_for(b.id, b.position, b.yaw)):
			return true
	return false


static func _is_tall(id: String) -> bool:
	return (ModelLibrary.building(id)["bounds"] as AABB).end.y > 2.2


## Постройка, с которой пересекается box (или null).
func _overlaps(box: Dictionary, mode: String) -> Building:
	var group: String = GameData.BUILDINGS[selected_id].get("group", "") if selected_id != "" else ""
	for b in buildings:
		if not is_instance_valid(b) or b == moving:
			continue
		# Секции оград (и плитки дорожек) могут касаться и пересекаться концами под любым
		# углом. Декор — нет: бочки, лавки и стога не ставятся друг в друга.
		if group in OVERLAP_GROUPS and GameData.BUILDINGS[b.id].get("group", "") == group:
			continue
		# Здания можно ставить на настил — он им не мешает (и настилы — друг другу, если не внахлёст).
		if b.id == "platform" and mode == "land":
			continue
		# На воде мешают только настилы и постройки на сваях — дома на настиле нет.
		if mode == "water" and b.id != "platform" and place_mode(b.id) != "water":
			continue
		if Building.obb_overlap(box, b.obb()):
			return b
	return null


## Пустая строка — построено (или передвинуто); иначе причина отказа.
func try_place() -> String:
	if _ghost == null or not _has_target:
		return ""
	if not is_valid:
		if over_water:
			_cross.scale = Vector3.ONE * 1.6
		return invalid_reason
	if moving:
		_finish_move()
		return ""
	var def: Dictionary = GameData.BUILDINGS[selected_id]
	if def.has("plant"):
		# Саженец — не здание: в мире растёт настоящее дерево.
		var reason := chunk_manager.plant_tree(_ghost_target, def["plant"])
		if reason == "":
			_ghost_scale = 0.85
			Fx.burst(self, _ghost_target + Vector3(0, 0.3, 0), Color(0.5, 0.75, 0.35), 10, 0.12)
		return reason
	if not Inventory.spend(def["cost"]):
		return "Не хватает ресурсов"
	var extra := {}
	if def.get("tilt", false):
		extra["normal"] = ground_normal(_ghost_target.x, _ghost_target.z)
	if def.has("crops"):
		extra["crop"] = crop_choice
		extra["planted"] = Time.get_unix_time_from_system()
	var b := spawn(selected_id, _ghost_target, _yaw, false, extra)
	var entry := {"id": b.id, "pos": b.position, "yaw": b.yaw}
	entry.merge(extra)
	WorldState.buildings.append(entry)
	_paint_last = b
	# Призрак «отпрыгивает», давая понять, что здание поставлено.
	_ghost_scale = 0.85
	placed.emit(b)
	return ""


func _finish_move() -> void:
	var b := moving
	var entry: Variant = _save_entry(b)
	b.position = _ghost_target
	b.yaw = _yaw
	b.rotation.y = _yaw
	if GameData.BUILDINGS[b.id].get("tilt", false):
		b.ground_normal = ground_normal(b.position.x, b.position.z)
		b.basis = Basis(Quaternion(Vector3.UP, b.ground_normal)) * Basis(Vector3.UP, _yaw)
		if entry:
			entry["normal"] = b.ground_normal
	b.footprint = Building.footprint_for(b.id, b.position, b.yaw)
	b.visible = true
	b.refit_ground()
	if entry:
		entry["pos"] = b.position
		entry["yaw"] = b.yaw
	chunk_manager.clear_decor(b.footprint)
	moving = null
	cancel()
	var tw := b.create_tween()
	b.scale = Vector3(1.05, 0.9, 1.05)
	tw.tween_property(b, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _save_entry(b: Building) -> Variant:
	for e: Dictionary in WorldState.buildings:
		if e["id"] == b.id and (e["pos"] as Vector3).is_equal_approx(b.position):
			return e
	return null


## Поворачивает готовое здание на месте на шаг 15°, если ему ничего не мешает.
func rotate_building(b: Building, direction := 1.0) -> String:
	var angle := wrapf(b.yaw + ROTATE_STEP * signf(direction), -PI, PI)
	var prev_selected := selected_id
	selected_id = b.id
	moving = b
	var check := _validate(b.position, angle)
	moving = null
	selected_id = prev_selected
	if check["reason"] != "" and not check["reason"].begins_with("Не хватает"):
		return check["reason"]
	var entry: Variant = _save_entry(b)
	b.yaw = angle
	b.footprint = Building.footprint_for(b.id, b.position, angle)
	var tw := b.create_tween()
	tw.tween_property(b, "rotation:y", b.rotation.y + angle_difference(b.rotation.y, angle), 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(b.refit_ground)
	if entry:
		entry["yaw"] = angle
	chunk_manager.clear_decor(b.footprint)
	return ""


## extra — сохранённые подробности: "normal" (наклон дорожки), "crop" и "planted" (грядки).
func spawn(building_id: String, pos: Vector3, angle: float, instant: bool, extra := {}) -> Building:
	var b := Building.new()
	b.position = pos
	b.ground_normal = extra.get("normal", Vector3.UP)
	b.crop = extra.get("crop", "")
	b.planted = extra.get("planted", 0.0)
	add_child(b)
	b.setup(building_id, angle, instant)
	buildings.append(b)
	chunk_manager.clear_decor(b.footprint)
	return b


## Чанк загрузился заново — под зданиями снова убираем траву и листья.
func on_chunk_loaded(chunk: Chunk) -> void:
	var area := Rect2(chunk.position.x, chunk.position.z, WorldGen.CHUNK_SIZE, WorldGen.CHUNK_SIZE)
	for b in buildings:
		if is_instance_valid(b) and b.footprint.intersects(area):
			chunk.clear_cover(b.footprint)
			# Земля под костром или скамьёй могла быть ещё не загружена — укладываем заново.
			b.refit_ground()


func restore_from_save() -> void:
	for entry: Dictionary in WorldState.buildings:
		# Старые сохранения хранили поворот шагами по 90°.
		if not entry.has("yaw"):
			entry["yaw"] = float(entry.get("rot", 0)) * PI * 0.5
		if not GameData.BUILDINGS.has(entry["id"]):
			continue
		spawn(entry["id"], entry["pos"], entry["yaw"], true, entry)


## Здание под лучом мыши или пальца.
func pick(from: Vector3, dir: Vector3) -> Building:
	var best: Building = null
	var best_t := INF
	for b in buildings:
		if not is_instance_valid(b) or not b.visible:
			continue
		var box := AABB(Vector3(b.footprint.position.x, b.position.y - 0.5, b.footprint.position.y),
			Vector3(b.footprint.size.x, b.top_height + 0.5, b.footprint.size.y))
		var hit: Variant = box.intersects_ray(from, dir)
		if hit != null:
			var t := from.distance_to(hit)
			if t < best_t:
				best_t = t
				best = b
	return best


## Сменить культуру на грядке (по кругу) и запомнить в сохранении.
func cycle_crop(b: Building) -> String:
	var next := CropPatch.next_crop(b.crop if b.crop != "" else "wheat")
	b.set_crop(next)
	var entry: Variant = _save_entry(b)
	if entry:
		entry["crop"] = b.crop
		entry["planted"] = b.planted
	crop_choice = next
	return next


## Пустая строка — можно снести; иначе причина.
func can_demolish(b: Building) -> String:
	if b.id == "platform":
		for other in buildings:
			if other != b and is_instance_valid(other) and place_mode(other.id) != "water" \
					and Building.obb_overlap(other.obb(-0.2), b.obb()):
				return "Сначала снесите здание на настиле"
	return ""


## Сносит здание и возвращает половину ресурсов (или всё, если оно не достроено).
func demolish(b: Building) -> Dictionary:
	var refund := {}
	if not GameMode.is_creative():
		var cost: Dictionary = GameData.BUILDINGS[b.id]["cost"]
		for res: String in cost:
			var n: int = floori(cost[res] * 0.5) if b.is_complete else cost[res]
			if n > 0:
				refund[res] = n
		Inventory.add_all(refund)
	buildings.erase(b)
	var entry: Variant = _save_entry(b)
	if entry != null:
		WorldState.buildings.erase(entry)
	b.demolish()
	return refund
