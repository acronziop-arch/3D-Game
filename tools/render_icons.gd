extends SceneTree
## Объёмные иконки интерфейса из моделей игры (деревня, здания пресетов и т. п.).
## Рисует каждую на прозрачном фоне в 512×512 и сохраняет в OUT; затем
## tools/finish_icons.py обрезает, уменьшает до 128×128 и добавляет мягкую тень,
## как у остальных иконок. Нужна видеокарта (не --headless). Запуск из папки проекта:
##   godot --path . --script res://tools/render_icons.gd -- <папка>
##   python3 -I tools/finish_icons.py <папка> assets/icons

## Иконка: [[id здания, сдвиг, поворот], ...] — несколько зданий ставятся рядом.
const ICONS := {
	"icon_village": [["wood_house", Vector3(-2.4, 0, 0.4), 0.35], ["chapel", Vector3(2.3, 0, -1.8), -0.25], ["hut", Vector3(0.9, 0, 2.6), 0.7]],
	"icon_buildings": [["brick_house", Vector3(-1.6, 0, 0.3), 0.25], ["watchtower", Vector3(2.6, 0, -1.0), 0.0]],
	"icon_game": [["tent", Vector3.ZERO, 0.5]],
	"icon_modes": [["signpost", Vector3.ZERO, 0.6]],
	"icon_about": [["fountain", Vector3.ZERO, 0.0]],
	"preset_harbor": [["lighthouse", Vector3.ZERO, 0.4]],
	"preset_mill": [["watermill", Vector3.ZERO, -0.5]],
	"preset_outpost": [["watchtower", Vector3.ZERO, 0.3]],
	"preset_highland": [["keep", Vector3.ZERO, 0.3]],
	"preset_birches": [["gazebo", Vector3.ZERO, 0.2]],
	"preset_merchants": [["town_hall", Vector3.ZERO, 0.35]],
	"preset_farms": [["windmill", Vector3.ZERO, 0.4]],
	"preset_fortress": [["castle", Vector3.ZERO, 0.3]],
	"preset_abbey": [["church", Vector3.ZERO, 0.5]],
	"preset_north": [["bathhouse", Vector3.ZERO, 0.4]],
}

var _viewport: SubViewport
var _camera: Camera3D
var _holder: Node3D
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if not args.is_empty() else "user://icons/"
	DirAccess.make_dir_recursive_absolute(_out)
	RenderingServer.global_shader_parameter_set("texture_detail", 0.0)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(512, 512)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.88, 0.94)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.55
	sun.light_color = Color(1.0, 0.96, 0.9)
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 26.0
	_viewport.add_child(_camera)
	_holder = Node3D.new()
	_viewport.add_child(_holder)
	_run.call_deferred()


func _run() -> void:
	for name: String in ICONS:
		for c in _holder.get_children():
			c.free()
		var box := AABB()
		var first := true
		for part: Array in ICONS[name]:
			var data := ModelLibrary.building(part[0])
			var node := Node3D.new()
			node.position = part[1]
			node.rotation.y = part[2]
			_holder.add_child(node)
			var mi := MeshInstance3D.new()
			mi.mesh = data["mesh"]
			ModelLibrary.apply_building_materials(mi)
			node.add_child(mi)
			if data["rotor_mesh"]:
				var rotor := MeshInstance3D.new()
				rotor.mesh = data["rotor_mesh"]
				rotor.position = data["pivot"]
				rotor.rotation.z = 0.35
				ModelLibrary.apply_building_materials(rotor)
				node.add_child(rotor)
			var b: AABB = node.transform * (data["bounds"] as AABB)
			# Цоколь под землёй в иконке не нужен.
			b.position.y = maxf(b.position.y, -0.05)
			box = b if first else box.merge(b)
			first = false
		var center := box.get_center()
		var radius := box.size.length() * 0.5
		var dir := Vector3(0.62, 0.5, 0.95).normalized()
		_camera.look_at_from_position(center + dir * radius / sin(deg_to_rad(_camera.fov * 0.5)) * 1.02, center)
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := _viewport.get_texture().get_image()
		img.save_png(_out.path_join(name + ".png"))
		print("icon: ", name)
	quit()
