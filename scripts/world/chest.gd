class_name Chest
extends Node3D
## Сундук: единственный источник животных ресурсов (шкуры, шерсть, воск).
## Редкость видна по цвету окантовки и свечения.

const RADIUS := 0.8
const HEIGHT := 1.0

var rarity := "common"
var coord := Vector2i.ZERO
var opened := false

var _lid: Node3D
var _light: OmniLight3D
var _time := 0.0
var _shake := 0.0


func setup(chest_rarity: String, chunk_coord: Vector2i) -> void:
	rarity = chest_rarity
	coord = chunk_coord
	var def: Dictionary = GameData.CHESTS[rarity]
	var trim: Color = def["color"]
	var wood := Color(0.55, 0.35, 0.2)

	var body := MeshKit.new()
	body.add_primitive(MeshKit.box(Vector3(1.0, 0.55, 0.7)), MeshKit.at(Vector3(0, 0.28, 0)), wood)
	for x in [-0.36, 0.36]:
		body.add_primitive(MeshKit.box(Vector3(0.1, 0.57, 0.72)), MeshKit.at(Vector3(x, 0.28, 0)), trim)
	var body_mesh := MeshInstance3D.new()
	body_mesh.mesh = body.build()
	add_child(body_mesh)

	# Крышка вращается вокруг заднего верхнего ребра.
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.55, -0.35)
	add_child(_lid)
	var lid := MeshKit.new()
	lid.add_primitive(MeshKit.box(Vector3(1.02, 0.24, 0.72)), MeshKit.at(Vector3(0, 0.12, 0.35)), wood.lightened(0.08))
	for x in [-0.36, 0.36]:
		lid.add_primitive(MeshKit.box(Vector3(0.1, 0.26, 0.74)), MeshKit.at(Vector3(x, 0.12, 0.35)), trim)
	lid.add_primitive(MeshKit.box(Vector3(0.16, 0.2, 0.06)), MeshKit.at(Vector3(0, 0.0, 0.73)), trim.darkened(0.2))
	var lid_mesh := MeshInstance3D.new()
	lid_mesh.mesh = lid.build()
	_lid.add_child(lid_mesh)

	_light = OmniLight3D.new()
	_light.light_color = trim
	_light.omni_range = 4.5
	_light.light_energy = 1.0
	_light.position = Vector3(0, 1.0, 0)
	add_child(_light)

	var sparkles := CPUParticles3D.new()
	sparkles.amount = 8 + GameData.CHEST_RARITIES.find(rarity) * 4
	sparkles.lifetime = 1.6
	sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparkles.emission_sphere_radius = 0.6
	sparkles.direction = Vector3.UP
	sparkles.spread = 15.0
	sparkles.gravity = Vector3(0, 0.6, 0)
	sparkles.initial_velocity_min = 0.2
	sparkles.initial_velocity_max = 0.5
	sparkles.scale_amount_min = 0.5
	sparkles.scale_amount_max = 1.0
	sparkles.position = Vector3(0, 0.6, 0)
	var dot := SphereMesh.new()
	dot.radius = 0.035
	dot.height = 0.07
	dot.radial_segments = 4
	dot.rings = 2
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = trim.lightened(0.3)
	dot.material = glow
	sparkles.mesh = dot
	add_child(sparkles)


func _process(delta: float) -> void:
	_time += delta
	if not opened:
		_light.light_energy = 0.8 + sin(_time * 2.4) * 0.3
	if _shake > 0.0:
		rotation.z = sin(_time * 40.0) * 0.04 * _shake
		_lid.rotation.x = -absf(sin(_time * 18.0)) * 0.12 * _shake


## Открытие идёт через очередь действий, как добыча: прогресс 0..1.
func set_progress(fraction: float) -> void:
	_shake = fraction


func cancel_progress() -> void:
	_shake = 0.0
	rotation.z = 0.0
	_lid.rotation.x = 0.0


## Открывает сундук, возвращает добычу и плавно исчезает.
func open() -> Dictionary:
	opened = true
	cancel_progress()
	WorldState.opened_chests[coord] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldState.world_seed, coord.x, coord.y, "loot"])
	var loot := GameData.roll_chest_loot(rarity, rng)
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", deg_to_rad(-115.0), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_light, "light_energy", 3.0, 0.3)
	tw.tween_interval(1.4)
	tw.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_light, "light_energy", 0.0, 0.45)
	tw.tween_callback(queue_free)
	return loot
