class_name BuildingSystem
extends Node3D
## Размещение зданий: «призрак» следует за мышью, привязан к сетке 1 м,
## поворачивается на R, подсвечивается зелёным/красным. Проверяет ресурсы,
## ровность земли, воду, деревья и соседние здания.

signal placed(building: Building)

const MAX_UNEVENNESS := 1.6
const GRID := 1.0

var chunk_manager: ChunkManager
var buildings: Array[Building] = []
var selected_id := ""
var is_valid := false
var invalid_reason := ""

var _ghost: Node3D
var _ghost_material: StandardMaterial3D
var _ghost_target := Vector3.ZERO
var _ghost_steps := 0
var _ghost_yaw := 0.0
var _has_target := false


func _ready() -> void:
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = Color(0.4, 1.0, 0.5, 0.45)


func select(building_id: String) -> void:
	cancel()
	selected_id = building_id
	_ghost = Node3D.new()
	for part in Blueprints.built_parts(building_id):
		var mi := MeshInstance3D.new()
		mi.mesh = part["mesh"]
		mi.transform = part["xform"]
		mi.material_override = _ghost_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost.add_child(mi)
	_ghost.visible = false
	_ghost.scale = Vector3.ONE * 0.6
	add_child(_ghost)
	_has_target = false


func cancel() -> void:
	selected_id = ""
	if _ghost:
		_ghost.queue_free()
		_ghost = null


func rotate_ghost() -> void:
	_ghost_steps = (_ghost_steps + 1) % 4


## Вызывается каждый кадр с точкой земли под мышью (или null, если мимо).
func update_ghost(hit: Variant, delta: float) -> void:
	if _ghost == null:
		return
	if hit == null:
		_ghost.visible = false
		return
	var p: Vector3 = hit
	var target := Vector3(snappedf(p.x, GRID), 0, snappedf(p.z, GRID))
	var check := _validate(target)
	target.y = check["y"]
	is_valid = check["reason"] == ""
	invalid_reason = check["reason"]
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
	var color := Color(0.4, 1.0, 0.5, 0.45) if is_valid else Color(1.0, 0.35, 0.3, 0.45)
	_ghost_material.albedo_color = _ghost_material.albedo_color.lerp(color, k)


func _validate(target: Vector3) -> Dictionary:
	var rect := Building.footprint_for(selected_id, target, _ghost_steps)
	var lo := INF
	var hi := -INF
	for iz in 4:
		for ix in 4:
			var x := lerpf(rect.position.x, rect.end.x, ix / 3.0)
			var z := lerpf(rect.position.y, rect.end.y, iz / 3.0)
			var h := chunk_manager.get_height(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var result := {"y": hi - 0.1, "reason": ""}
	var cost: Dictionary = GameData.BUILDINGS[selected_id]["cost"]
	if lo < WorldGen.WATER_LEVEL + 0.2:
		result["reason"] = "Нельзя строить в воде"
	elif hi - lo > MAX_UNEVENNESS:
		result["reason"] = "Слишком неровно — выровняйте землю [3]"
	elif not chunk_manager.props_in_rect(rect.grow(-0.2), true).is_empty():
		result["reason"] = "Мешают деревья или камни — добудьте их [1]"
	elif chunk_manager.has_chest_in_rect(rect):
		result["reason"] = "Здесь лежит сундук"
	elif _overlaps(rect):
		result["reason"] = "Мешает другое здание"
	elif not Inventory.has_all(cost):
		result["reason"] = "Не хватает: %s" % GameData.cost_text(Inventory.missing(cost))
	return result


func _overlaps(rect: Rect2) -> bool:
	var shrunk := rect.grow(-0.15)
	for b in buildings:
		if is_instance_valid(b) and b.footprint.intersects(shrunk):
			return true
	return false


## Пустая строка — построено; иначе причина отказа.
func try_place() -> String:
	if _ghost == null or not _has_target:
		return ""
	if not is_valid:
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
	b.setup(building_id, steps, instant)
	add_child(b)
	buildings.append(b)
	chunk_manager.clear_decor(b.footprint)
	return b


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


## Сносит здание и возвращает половину ресурсов.
func demolish(b: Building) -> Dictionary:
	var refund := {}
	var cost: Dictionary = GameData.BUILDINGS[b.id]["cost"]
	for res: String in cost:
		var n: int = floori(cost[res] * 0.5) if b.is_complete else cost[res]
		if n > 0:
			refund[res] = n
	Inventory.add_all(refund)
	buildings.erase(b)
	for i in WorldState.buildings.size():
		var e: Dictionary = WorldState.buildings[i]
		if e["id"] == b.id and e["pos"].is_equal_approx(b.position):
			WorldState.buildings.remove_at(i)
			break
	b.demolish()
	return refund
