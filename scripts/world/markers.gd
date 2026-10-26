class_name Markers
extends Node3D
## Метки игрока в мире: столбик с цветным флажком и плашка со значком над ним —
## их видно издалека, чтобы находить свои деревни. Те же метки — на карте.

var chunk_manager: ChunkManager

var _nodes: Array[Node3D] = []
var _labels: Array[Dictionary] = []


func refresh() -> void:
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	if WorldLabels.instance:
		for e in _labels:
			WorldLabels.instance.untrack(e)
	_labels.clear()
	for m: Dictionary in WorldState.markers:
		var root := Node3D.new()
		add_child(root)
		var p: Vector3 = m["pos"]
		if chunk_manager:
			p.y = maxf(chunk_manager.get_height(p.x, p.z), WorldGen.WATER_LEVEL)
		root.global_position = p
		var color := Color(str(m.get("color", "#E05A4E")))
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.09
		cyl.height = 4.2
		cyl.radial_segments = 6
		pole.mesh = cyl
		pole.position.y = 2.1
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.45, 0.32, 0.2)
		wood.roughness = 0.9
		pole.material_override = wood
		root.add_child(pole)
		var flag := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(1.3, 0.9, 0.05)
		prism.left_to_right = 0.0
		flag.mesh = prism
		flag.rotation.z = -PI * 0.5
		flag.position = Vector3(0.48, 3.7, 0)
		var cloth := StandardMaterial3D.new()
		cloth.albedo_color = color
		cloth.roughness = 0.8
		cloth.emission_enabled = true
		cloth.emission = color * 0.35
		flag.material_override = cloth
		root.add_child(flag)
		var tw := flag.create_tween().set_loops()
		tw.tween_property(flag, "rotation:y", 0.25, 1.3).set_trans(Tween.TRANS_SINE)
		tw.tween_property(flag, "rotation:y", -0.25, 1.3).set_trans(Tween.TRANS_SINE)
		_nodes.append(root)
		if WorldLabels.instance:
			_labels.append(WorldLabels.instance.track(root, Vector3(0, 4.9, 0), str(m.get("name", "Метка")), false,
				UiStyle.icon("marker_" + str(m.get("icon", "flag"))), color, 600.0))
