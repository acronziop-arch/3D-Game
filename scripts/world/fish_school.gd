class_name FishSchool
extends Node3D
## Рыбы одного чанка. Плавают от одного глубокого места к другому, плавно
## поворачивают, иногда ускоряются. Рисуются через MultiMesh (по виду на сетку),
## хвост машет в шейдере fish.gdshader.

const SPECIES_WEIGHTS := {"perch": 4.0, "carp": 4.0, "trout": 3.0, "pike": 1.5, "koi": 0.6}
const UPDATE_DISTANCE := 110.0

var _spots: Array[Vector3] = []
var _fish: Array[Dictionary] = []
var _multimeshes := {}
var _rng := RandomNumberGenerator.new()


func setup(spots: Array, chunk_coord: Vector2i) -> void:
	visible = Settings.get_value("fish")
	_spots.assign(spots)
	_rng.seed = hash([WorldState.world_seed, chunk_coord.x, chunk_coord.y, "fish"])
	var count := mini(2 + _spots.size() / 10, 9)
	var by_species := {}
	for i in count:
		var species := _pick_species()
		var spot := _spots[_rng.randi() % _spots.size()]
		var fish := {"species": species, "pos": _depth_point(spot), "vel": Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)),
			"target": _new_target(), "speed": _rng.randf_range(0.6, 1.3), "size": _rng.randf_range(1.2, 1.7)}
		if not by_species.has(species):
			by_species[species] = []
		by_species[species].append(fish)
		_fish.append(fish)
	for species: String in by_species:
		var list: Array = by_species[species]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = ModelLibrary.fish_mesh(species)
		mm.instance_count = list.size()
		for i in list.size():
			list[i]["mm_i"] = i
			mm.set_instance_custom_data(i, Color(_rng.randf(), list[i]["speed"], 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = ModelLibrary.fish_material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_multimeshes[species] = mm
	_update(0.0)


func _pick_species() -> String:
	var total := 0.0
	for s: String in SPECIES_WEIGHTS:
		total += SPECIES_WEIGHTS[s]
	var r := _rng.randf() * total
	for s: String in SPECIES_WEIGHTS:
		r -= SPECIES_WEIGHTS[s]
		if r <= 0.0:
			return s
	return "carp"


## Точка между дном и поверхностью (в локальных координатах чанка).
func _depth_point(spot: Vector3) -> Vector3:
	var bottom := spot.y + 0.35
	var top := WorldGen.WATER_LEVEL - 0.6
	var jitter := Vector3(_rng.randf_range(-0.8, 0.8), 0, _rng.randf_range(-0.8, 0.8))
	return Vector3(spot.x, lerpf(bottom, top, _rng.randf_range(0.3, 0.85)), spot.z) + jitter


func _new_target() -> Vector3:
	return _depth_point(_spots[_rng.randi() % _spots.size()])


func _process(delta: float) -> void:
	# Настройка «Рыбы» действует сразу, без перезапуска.
	visible = Settings.get_value("fish")
	if not visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(global_position + Vector3(16, 0, 16)) > UPDATE_DISTANCE:
		return
	_update(delta)


func _update(delta: float) -> void:
	for f in _fish:
		var pos: Vector3 = f["pos"]
		var target: Vector3 = f["target"]
		var to_target := target - pos
		if to_target.length() < 0.8 or _rng.randf() < delta * 0.05:
			f["target"] = _new_target()
			f["speed"] = _rng.randf_range(0.5, 1.4)
		var desired := to_target.normalized() * float(f["speed"])
		var vel: Vector3 = f["vel"]
		vel = vel.lerp(desired, 1.0 - exp(-1.3 * delta))
		pos += vel * delta
		f["vel"] = vel
		f["pos"] = pos
		var dir := Vector3(vel.x, clampf(vel.y, -0.4, 0.4), vel.z)
		if Vector2(dir.x, dir.z).length() < 0.05:
			dir = Vector3(0.0, 0.0, 1.0)
		var basis := Basis.looking_at(-dir.normalized(), Vector3.UP).scaled(Vector3.ONE * float(f["size"]))
		_multimeshes[f["species"]].set_instance_transform(f["mm_i"], Transform3D(basis, pos))
