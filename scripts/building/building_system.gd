class_name BuildingSystem
extends Node3D
## Размещение зданий: полупрозрачный «призрак» следует за мышью (на телефоне —
## за пальцем), стоит на сетке 1 м, поворачивается на R и подсвечивается зелёным
## или красным.
## Режимы размещения (GameData.BUILDINGS[id].place):
##   land   — суша или деревянный настил; над водой показывается красный крестик;
##   water  — только на воде (настил), сетка 4 м, чтобы блоки стыковались;
##   bridge — концы моста на берегах, середина над водой.

signal placed(building: Building)

const MAX_UNEVENNESS := 1.6
const GRID := 1.0
const PLATFORM_GRID := 4.0
const PLATFORM_TOP := 0.8
const VALID_TINT := Color(0.45, 1.0, 0.6, 0.3)
const INVALID_TINT := Color(1.0, 0.35, 0.3, 0.32)

var chunk_manager: ChunkManager
var buildings: Array[Building] = []
## Клетки 4×4 м, покрытые настилом: Vector2i -> высота верха настила.
var platforms := {}
var selected_id := ""
var is_valid := false
var invalid_reason := ""
## true, если призрак сухопутного здания стоит над водой.
var over_water := false

var _ghost: Node3D
var _ghost_material: ShaderMaterial
var _ghost_target := Vector3.ZERO
var _ghost_steps := 0
var _ghost_yaw := 0.0
var _has_target := false
var _cross: Sprite3D


func _ready() -> void:
	_ghost_material = Building.ghost_material().duplicate()
	_ghost_material.set_shader_parameter("tint", VALID_TINT)
	_cross = Sprite3D.new()
	_cross.texture = load("res://assets/icons/cross.svg")
	_cross.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cross.no_depth_test = true
	_cross.pixel_size = 0.012
	_cross.render_priority = 5
	_cross.visible = false
	add_child(_cross)


func select(building_id: String) -> void:
	cancel()
	selected_id = building_id
	var data := ModelLibrary.building(building_id)
	_ghost = Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = data["mesh"]
	body.material_override = _ghost_material
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.add_child(body)
	if data["rotor_mesh"]:
		var rotor := MeshInstance3D.new()
		rotor.mesh = data["rotor_mesh"]
		rotor.position = data["pivot"]
		rotor.material_override = _ghost_material
		_ghost.add_child(rotor)
	_ghost.visible = false
	_ghost.scale = Vector3.ONE * 0.6
	add_child(_ghost)
	_has_target = false


func cancel() -> void:
	selected_id = ""
	over_water = false
	_cross.visible = false
	if _ghost:
		_ghost.queue_free()
		_ghost = null


func rotate_ghost() -> void:
	_ghost_steps = (_ghost_steps + 1) % 4


func place_mode(building_id: String) -> String:
	return GameData.BUILDINGS[building_id].get("place", "land")


## Вызывается каждый кадр с точкой земли под мышью (или null, если мимо).
func update_ghost(hit: Variant, delta: float) -> void:
	if _ghost == null:
		return
	if hit == null:
		_ghost.visible = false
		_cross.visible = false
		return
	var p: Vector3 = hit
	var target := Vector3(snappedf(p.x, GRID), 0, snappedf(p.z, GRID))
	if place_mode(selected_id) == "water":
		target = Vector3(floorf(p.x / PLATFORM_GRID) * PLATFORM_GRID + PLATFORM_GRID * 0.5, 0,
			floorf(p.z / PLATFORM_GRID) * PLATFORM_GRID + PLATFORM_GRID * 0.5)
	var check := _validate(target)
	target.y = check["y"]
	is_valid = check["reason"] == ""
	invalid_reason = check["reason"]
	over_water = check.get("water", false)
	_ghost_target = target
	if not _has_target:
		_has_target = true
		_ghost.position = target
		_ghost_yaw = _ghost_steps * PI * 0.5
	_ghost.visible = true

	var k := 1.0 - exp(-18.0 * delta)
	_ghost.position = _ghost.position.lerp(target, k)
	_ghost_yaw = lerp_angle(_ghost_yaw, _ghost_steps * PI * 0.5, k)
	_ghost.rotation.y = _ghost_yaw
	_ghost.scale = _ghost.scale.lerp(Vector3.ONE, k)
	var tint: Color = _ghost_material.get_shader_parameter("tint")
	_ghost_material.set_shader_parameter("tint", tint.lerp(VALID_TINT if is_valid else INVALID_TINT, k))
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


## Попадает ли луч в призрак здания (чтобы тянуть его пальцем).
func ghost_hit(from: Vector3, dir: Vector3) -> bool:
	if _ghost == null or not _has_target:
		return false
	var rect := Building.footprint_for(selected_id, _ghost_target, _ghost_steps).grow(1.0)
	var top: float = (ModelLibrary.building(selected_id)["bounds"] as AABB).end.y
	var box := AABB(Vector3(rect.position.x, _ghost_target.y - 1.0, rect.position.y), Vector3(rect.size.x, top + 1.5, rect.size.y))
	return box.intersects_ray(from, dir) != null


func platform_top(x: float, z: float) -> float:
	var cell := Vector2i(floori(x / PLATFORM_GRID), floori(z / PLATFORM_GRID))
	return platforms.get(cell, -INF)


func _validate(target: Vector3) -> Dictionary:
	var mode := place_mode(selected_id)
	var rect := Building.footprint_for(selected_id, target, _ghost_steps)
	var cost: Dictionary = GameData.BUILDINGS[selected_id]["cost"]
	var result := {"y": 0.0, "reason": ""}
	match mode:
		"water":
			var lo := INF
			var center := chunk_manager.get_height(target.x, target.z)
			for s in _samples(rect, 3):
				lo = minf(lo, chunk_manager.get_height(s.x, s.y))
			result["y"] = WorldGen.WATER_LEVEL
			if center > WorldGen.WATER_LEVEL - 0.3:
				result["reason"] = "Настил ставится на воду"
			elif lo < WorldGen.WATER_LEVEL - 6.0:
				result["reason"] = "Слишком глубоко для свай"
			elif platforms.has(Vector2i(floori(target.x / PLATFORM_GRID), floori(target.z / PLATFORM_GRID))):
				result["reason"] = "Здесь уже есть настил"
		"bridge":
			var yaw := Basis(Vector3.UP, _ghost_steps * PI * 0.5)
			var a := target + yaw * Vector3(0, 0, 6.6)
			var b := target + yaw * Vector3(0, 0, -6.6)
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
			var lo := INF
			var hi := -INF
			var any_platform := false
			# Свесы крыши могут нависать над водой — проверяем только «пятно» стен.
			for s in _samples(rect.grow(-0.35), 4):
				var h := chunk_manager.get_height(s.x, s.y)
				var top := platform_top(s.x, s.y)
				if top > -INF:
					any_platform = true
					h = top
				elif h < WorldGen.WATER_LEVEL + 0.2:
					result["water"] = true
				lo = minf(lo, h)
				hi = maxf(hi, h)
			if result.get("water", false):
				result["reason"] = "Настил должен быть под всем зданием — добавьте блоков" if any_platform \
					else "Здесь вода — сначала постройте деревянный настил"
			result["y"] = PLATFORM_TOP if any_platform and hi <= PLATFORM_TOP + 0.01 else hi - 0.1
			if result["reason"] == "" and hi - lo > MAX_UNEVENNESS:
				result["reason"] = "Слишком неровно — выровняйте землю" + _key("3")
	if result["reason"] == "":
		if not chunk_manager.props_in_rect(rect.grow(-0.2), true).is_empty():
			result["reason"] = "Мешают деревья или камни — добудьте их" + _key("1")
		elif chunk_manager.has_chest_in_rect(rect):
			result["reason"] = "Здесь лежит сундук"
		elif _overlaps(rect, mode):
			result["reason"] = "Мешает другое здание"
		elif not Inventory.has_all(cost):
			result["reason"] = "Не хватает: %s" % GameData.cost_text(Inventory.missing(cost))
	return result


## Подсказка клавиши — только на ПК.
static func _key(k: String) -> String:
	return "" if Platform.is_touch else " [%s]" % k


static func _samples(rect: Rect2, n: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for iz in n:
		for ix in n:
			result.append(Vector2(lerpf(rect.position.x + 0.2, rect.end.x - 0.2, ix / float(n - 1)),
				lerpf(rect.position.y + 0.2, rect.end.y - 0.2, iz / float(n - 1))))
	return result


func _overlaps(rect: Rect2, mode: String) -> bool:
	var shrunk := rect.grow(-0.15)
	for b in buildings:
		if not is_instance_valid(b):
			continue
		# Здания можно ставить на настил — он им не мешает.
		if b.id == "platform" and mode == "land":
			continue
		if b.footprint.intersects(shrunk):
			return true
	return false


## Пустая строка — построено; иначе причина отказа.
func try_place() -> String:
	if _ghost == null or not _has_target:
		return ""
	if not is_valid:
		if over_water:
			_cross.scale = Vector3.ONE * 1.6
		return invalid_reason
	if not Inventory.spend(GameData.BUILDINGS[selected_id]["cost"]):
		return "Не хватает ресурсов"
	var b := spawn(selected_id, _ghost_target, _ghost_steps, false)
	WorldState.buildings.append({"id": b.id, "pos": b.position, "rot": b.rot_steps})
	# Призрак «отпрыгивает», давая понять, что здание поставлено.
	_ghost.scale = Vector3.ONE * 0.85
	placed.emit(b)
	return ""


func spawn(building_id: String, pos: Vector3, steps: int, instant: bool) -> Building:
	var b := Building.new()
	b.position = pos
	add_child(b)
	b.setup(building_id, steps, instant)
	buildings.append(b)
	chunk_manager.clear_decor(b.footprint)
	if building_id == "platform":
		platforms[Vector2i(floori(pos.x / PLATFORM_GRID), floori(pos.z / PLATFORM_GRID))] = PLATFORM_TOP
	return b


## Чанк загрузился заново — под зданиями снова убираем траву и листья.
func on_chunk_loaded(chunk: Chunk) -> void:
	var area := Rect2(chunk.position.x, chunk.position.z, WorldGen.CHUNK_SIZE, WorldGen.CHUNK_SIZE)
	for b in buildings:
		if is_instance_valid(b) and b.footprint.intersects(area):
			chunk.clear_cover(b.footprint)


func restore_from_save() -> void:
	for entry: Dictionary in WorldState.buildings:
		spawn(entry["id"], entry["pos"], entry["rot"], true)


## Здание под лучом мыши (для сноса).
func pick(from: Vector3, dir: Vector3) -> Building:
	var best: Building = null
	var best_t := INF
	for b in buildings:
		if not is_instance_valid(b):
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


## Пустая строка — можно снести; иначе причина.
func can_demolish(b: Building) -> String:
	if b.id == "platform":
		for other in buildings:
			if other != b and is_instance_valid(other) and other.id != "platform" and other.footprint.intersects(b.footprint.grow(-0.2)):
				return "Сначала снесите здание на настиле"
	return ""


## Сносит здание и возвращает половину ресурсов (или всё, если оно не достроено).
func demolish(b: Building) -> Dictionary:
	var refund := {}
	var cost: Dictionary = GameData.BUILDINGS[b.id]["cost"]
	for res: String in cost:
		var n: int = floori(cost[res] * 0.5) if b.is_complete else cost[res]
		if n > 0:
			refund[res] = n
	Inventory.add_all(refund)
	buildings.erase(b)
	if b.id == "platform":
		platforms.erase(Vector2i(floori(b.position.x / PLATFORM_GRID), floori(b.position.z / PLATFORM_GRID)))
	for i in WorldState.buildings.size():
		var e: Dictionary = WorldState.buildings[i]
		if e["id"] == b.id and e["pos"].is_equal_approx(b.position):
			WorldState.buildings.remove_at(i)
			break
	b.demolish()
	return refund
