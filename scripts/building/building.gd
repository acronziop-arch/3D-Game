class_name Building
extends Node3D
## Здание в мире. Модель — models/buildings/<id>.glb. Стройку рисует шейдер
## building.gdshader: детали по очереди падают на место с лёгким отскоком,
## ещё не построенная часть видна как голубой полупрозрачный чертёж, вокруг
## стоят строительные леса. Пока здание строится, у него свои копии материалов
## (параметр build_progress), а готовое переходит на общие материалы.
## Время стройки — GameData.BUILDINGS[id].time (не больше 30 с).

signal completed(building: Building)

## Колёса, которые крутятся с постоянной скоростью (рад/с), а не от ветра.
const STEADY_ROTORS := {"watermill": 0.55}

static var _ghost_material: ShaderMaterial
## Высота земли в точке (x, z) — её задаёт BuildingSystem.
static var ground_height: Callable
static var _ghost_opening_material: ShaderMaterial
static var _highlight_material: StandardMaterial3D
## Поверхности мешей, которые ложатся по земле: Mesh -> Array (см. _conform).
static var _surface_cache := {}
## Леса по видам зданий: id -> Mesh.
static var _scaffold_meshes := {}
## Двор моделей (см. _yard_of): Mesh -> [] или [поверхности, [индексы, веса, точки]...].
static var _yard_cache := {}

var id := ""
## Поворот вокруг вертикали, радианы (любой угол).
var yaw := 0.0
var progress := 0.0
var is_complete := false
var footprint := Rect2()
var top_height := 0.0
## Культура на грядке и время посадки (для зданий с "crops").
var crop := ""
var planted := 0.0
## Нормаль земли для дорожек, которые ложатся по склону ("tilt").
var ground_normal := Vector3.UP

var _mesh: MeshInstance3D
## Исходный меш у построек, которые ложатся по земле (см. _conform), — для пересчёта.
var _ground_mesh: Mesh
## Исходный меш у зданий с дворовыми мелочами (см. _fit_yard), — для пересчёта.
var _yard_mesh: Mesh
var _ghost: MeshInstance3D
var _rotor: Node3D
var _rotor_mesh: MeshInstance3D
var _rotor_speed := 0.0
var _label := {}
var _dust: CPUParticles3D
var _scaffold: MeshInstance3D
var _removing := false
var _crops: CropPatch
## Огонь костра и факела: [узел, точка в модели] — ложится на землю вместе с мешем.
var _fires: Array[Array] = []
## Свои копии материалов на время стройки (у них меняется build_progress).
var _progress_materials: Array[ShaderMaterial] = []


## Прямоугольник, который здание занимает на земле (мировые XZ, с учётом поворота).
static func footprint_for(building_id: String, pos: Vector3, angle: float) -> Rect2:
	var b: AABB = ModelLibrary.building(building_id)["bounds"]
	var basis := Basis(Vector3.UP, angle)
	var rect := Rect2()
	for i in 4:
		var corner := Vector3(b.position.x if i % 2 == 0 else b.end.x, 0, b.position.z if i < 2 else b.end.z)
		var w := pos + basis * corner
		if i == 0:
			rect = Rect2(Vector2(w.x, w.z), Vector2.ZERO)
		else:
			rect = rect.expand(Vector2(w.x, w.z))
	return rect


## Повёрнутый прямоугольник здания на земле: {"c": центр, "h": полуразмеры, "a": угол}.
static func obb_for(building_id: String, pos: Vector3, angle: float, grow := 0.0) -> Dictionary:
	var b: AABB = ModelLibrary.building(building_id)["bounds"]
	var c := pos + Basis(Vector3.UP, angle) * Vector3(b.get_center().x, 0, b.get_center().z)
	var half := Vector2(b.size.x, b.size.z) * 0.5 + Vector2.ONE * grow
	return {"c": Vector2(c.x, c.z), "h": half.max(Vector2.ONE * 0.05), "a": angle}


## То же по пятну у земли (без свесов крыш, козырьков и вывесок).
static func base_obb_for(building_id: String, pos: Vector3, angle: float, grow := 0.0) -> Dictionary:
	var r: Rect2 = ModelLibrary.building(building_id)["base"]
	var c := pos + Basis(Vector3.UP, angle) * Vector3(r.get_center().x, 0, r.get_center().y)
	var half := r.size * 0.5 + Vector2.ONE * grow
	return {"c": Vector2(c.x, c.z), "h": half.max(Vector2.ONE * 0.05), "a": angle}


static func _obb_axes(o: Dictionary) -> Array[Vector2]:
	var a: float = o["a"]
	# Поворот вокруг Y на угол a: локальная X — (cos, -sin), локальная Z — (sin, cos) в плоскости XZ.
	return [Vector2(cos(a), -sin(a)), Vector2(sin(a), cos(a))]


static func obb_has_point(o: Dictionary, p: Vector2) -> bool:
	var axes := _obb_axes(o)
	var d: Vector2 = p - o["c"]
	var h: Vector2 = o["h"]
	return absf(d.dot(axes[0])) <= h.x and absf(d.dot(axes[1])) <= h.y


## Пересекаются ли два повёрнутых прямоугольника (теорема о разделяющей оси).
static func obb_overlap(a: Dictionary, b: Dictionary) -> bool:
	var axes_a := _obb_axes(a)
	var axes_b := _obb_axes(b)
	var d: Vector2 = b["c"] - a["c"]
	var ha: Vector2 = a["h"]
	var hb: Vector2 = b["h"]
	for axis: Vector2 in axes_a + axes_b:
		var ra := absf(axes_a[0].dot(axis)) * ha.x + absf(axes_a[1].dot(axis)) * ha.y
		var rb := absf(axes_b[0].dot(axis)) * hb.x + absf(axes_b[1].dot(axis)) * hb.y
		if absf(d.dot(axis)) > ra + rb:
			return false
	return true


## Точки-пробы внутри повёрнутого прямоугольника (n × n).
static func obb_samples(o: Dictionary, n: int) -> Array[Vector2]:
	var axes := _obb_axes(o)
	var h: Vector2 = o["h"]
	var result: Array[Vector2] = []
	for iz in n:
		for ix in n:
			var u := lerpf(-h.x, h.x, ix / float(n - 1))
			var v := lerpf(-h.y, h.y, iz / float(n - 1))
			result.append(o["c"] + axes[0] * u + axes[1] * v)
	return result


func obb(grow := 0.0) -> Dictionary:
	return obb_for(id, position, yaw, grow)


static func ghost_material(opening := false) -> ShaderMaterial:
	if _ghost_material == null:
		_ghost_material = ShaderMaterial.new()
		_ghost_material.shader = load("res://shaders/ghost.gdshader")
		# Чертёж рисуется после воды, иначе вода «срезает» его у берега.
		# Перед цветом — проход глубины (приоритет ниже — рисуется раньше).
		_ghost_material.render_priority = 3
		var depth := ShaderMaterial.new()
		depth.shader = load("res://shaders/ghost_depth.gdshader")
		depth.render_priority = 2
		_ghost_material.next_pass = depth
		_ghost_opening_material = _ghost_material.duplicate()
		_ghost_opening_material.set_shader_parameter("highlight", 1.0)
	return _ghost_opening_material if opening else _ghost_material


## Ставит на меш чертёж: двери и окна — светлым тёплым оттенком.
## Возвращает созданные копии материалов (чтобы менять им цвет и прогресс).
static func apply_ghost_materials(mi: MeshInstance3D, own_copies: bool) -> Array[ShaderMaterial]:
	var made: Array[ShaderMaterial] = []
	for i in mi.mesh.get_surface_count():
		var m := ghost_material(ModelLibrary.surface_tag(mi.mesh, i) == "opening")
		if own_copies:
			m = m.duplicate()
			m.next_pass = m.next_pass.duplicate()
			made.append(m)
		mi.set_surface_override_material(i, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return made


static func highlight_material() -> StandardMaterial3D:
	if _highlight_material == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.3, 0.25, 0.35)
		_highlight_material = m
	return _highlight_material


## Копия меша, у которой низ «лёг» на землю: каждая вершина сдвинута на разницу
## высоты земли под ней и под центром. Высокие части (верх факела) не сдвигаются,
## а ограды и частокол сдвигаются целиком: колья не растягиваются, жерди идут по склону.
func _conform(mesh: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	var xf := global_transform
	var rigid: bool = GameData.BUILDINGS[id].get("group", "") == "fence"
	# Исходные поверхности читаем один раз на вид постройки: при выравнивании земли
	# здания укладываются заново много раз в секунду. Длинные грани заранее делятся:
	# земля огорода и жерди ограды изгибаются по земле, а не висят над ней углами.
	if not _surface_cache.has(mesh):
		var surfaces := []
		for i in mesh.get_surface_count():
			surfaces.append(_subdivide(mesh.surface_get_arrays(i), CONFORM_EDGE))
		_surface_cache[mesh] = surfaces
	var cached: Array = _surface_cache[mesh]
	for i in mesh.get_surface_count():
		var arrays: Array = (cached[i] as Array).duplicate()
		# Своя копия вершин: массивы в кэше общие у всех построек этого вида, и без копии
		# каждая укладка сдвигала бы их снова — костры всплывали, колья частокола ломались.
		var verts := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		for k in verts.size():
			var v := verts[k]
			var w := xf * v
			var dh: float = ground_height.call(w.x, w.z) - global_position.y
			verts[k] = v + Vector3(0, dh * (1.0 if rigid else 1.0 - smoothstep(1.0, 1.8, v.y)), 0)
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(i, mesh.surface_get_material(i))
	return out


## Длиннее этого (м) грани постройки, которая ложится по земле, делятся пополам.
const CONFORM_EDGE := 0.9


## Делит треугольники, пока все их рёбра не станут короче max_edge: середина длинного
## ребра — новая вершина (общая у соседних треугольников, так что щелей нет).
static func _subdivide(arrays: Array, max_edge: float) -> Array:
	for k in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		if typeof(arrays[k]) != TYPE_NIL:
			return arrays
	var out := arrays.duplicate()
	var verts := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var has_normal := typeof(arrays[Mesh.ARRAY_NORMAL]) != TYPE_NIL
	var has_tangent := typeof(arrays[Mesh.ARRAY_TANGENT]) != TYPE_NIL
	var has_color := typeof(arrays[Mesh.ARRAY_COLOR]) != TYPE_NIL
	var has_uv := typeof(arrays[Mesh.ARRAY_TEX_UV]) != TYPE_NIL
	var has_uv2 := typeof(arrays[Mesh.ARRAY_TEX_UV2]) != TYPE_NIL
	var normals := (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate() if has_normal else PackedVector3Array()
	var tangents := (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).duplicate() if has_tangent else PackedFloat32Array()
	var colors := (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate() if has_color else PackedColorArray()
	var uvs := (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).duplicate() if has_uv else PackedVector2Array()
	var uv2s := (arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).duplicate() if has_uv2 else PackedVector2Array()
	var src_index := PackedInt32Array()
	if typeof(arrays[Mesh.ARRAY_INDEX]) != TYPE_NIL:
		src_index = arrays[Mesh.ARRAY_INDEX]
	else:
		src_index.resize(verts.size())
		for i in verts.size():
			src_index[i] = i
	var limit := max_edge * max_edge
	var mids := {}
	var index := PackedInt32Array()
	var stack: Array[Vector3i] = []
	for t in range(0, src_index.size() - 2, 3):
		stack.push_back(Vector3i(src_index[t], src_index[t + 1], src_index[t + 2]))
		while not stack.is_empty():
			var tri: Vector3i = stack.pop_back()
			var ab := verts[tri.x].distance_squared_to(verts[tri.y])
			var bc := verts[tri.y].distance_squared_to(verts[tri.z])
			var ca := verts[tri.z].distance_squared_to(verts[tri.x])
			var longest := maxf(ab, maxf(bc, ca))
			# Защита от разрастания: не больше 60 000 вершин на поверхность.
			if longest <= limit or verts.size() > 60000:
				index.append(tri.x)
				index.append(tri.y)
				index.append(tri.z)
				continue
			# Поворачиваем треугольник так, чтобы длинное ребро было первым (a–b); обход тот же.
			if bc == longest:
				tri = Vector3i(tri.y, tri.z, tri.x)
			elif ca == longest:
				tri = Vector3i(tri.z, tri.x, tri.y)
			var key := Vector2i(mini(tri.x, tri.y), maxi(tri.x, tri.y))
			var m: int = mids.get(key, -1)
			if m < 0:
				var a := key.x
				var b := key.y
				m = verts.size()
				verts.append((verts[a] + verts[b]) * 0.5)
				if has_normal:
					var n := normals[a] + normals[b]
					normals.append(n.normalized() if n.length_squared() > 0.000001 else normals[a])
				if has_tangent:
					var tv := Vector3(tangents[a * 4] + tangents[b * 4], tangents[a * 4 + 1] + tangents[b * 4 + 1],
						tangents[a * 4 + 2] + tangents[b * 4 + 2])
					tv = tv.normalized() if tv.length_squared() > 0.000001 else Vector3(tangents[a * 4], tangents[a * 4 + 1], tangents[a * 4 + 2])
					tangents.append_array(PackedFloat32Array([tv.x, tv.y, tv.z, tangents[a * 4 + 3]]))
				if has_color:
					colors.append(colors[a].lerp(colors[b], 0.5))
				if has_uv:
					uvs.append((uvs[a] + uvs[b]) * 0.5)
				if has_uv2:
					uv2s.append((uv2s[a] + uv2s[b]) * 0.5)
				mids[key] = m
			stack.push_back(Vector3i(tri.x, m, tri.z))
			stack.push_back(Vector3i(m, tri.y, tri.z))
	out[Mesh.ARRAY_VERTEX] = verts
	if has_normal:
		out[Mesh.ARRAY_NORMAL] = normals
	if has_tangent:
		out[Mesh.ARRAY_TANGENT] = tangents
	if has_color:
		out[Mesh.ARRAY_COLOR] = colors
	if has_uv:
		out[Mesh.ARRAY_TEX_UV] = uvs
	if has_uv2:
		out[Mesh.ARRAY_TEX_UV2] = uv2s
	out[Mesh.ARRAY_INDEX] = index
	return out


## Снова уложить по земле — после переноса, поворота или выравнивания земли рядом.
func refit_ground() -> void:
	if not is_inside_tree():
		return
	if _ground_mesh:
		_mesh.mesh = _conform(_ground_mesh)
	elif _yard_mesh:
		_mesh.mesh = _fit_yard(_yard_mesh)
	else:
		return
	if _ghost:
		_ghost.mesh = _mesh.mesh
	_fit_extras()


## Меш следует за землёй (его надо укладывать заново, когда земля рядом меняется).
func follows_ground() -> bool:
	return _ground_mesh != null or _yard_mesh != null


## Двор модели: поверхности с пометкой «yard» (Geo.tag) — бревна у лесопилки, бочки у
## таверны, камни у каменотёсни. Считается один раз на вид здания; пустой — двора нет.
static func _yard_of(mesh: Mesh) -> Array:
	if _yard_cache.has(mesh):
		return _yard_cache[mesh]
	var all := []
	var parts := []
	var any := false
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		all.append(arrays)
		var idx := PackedInt32Array()
		var weights := PackedFloat32Array()
		var points := PackedVector3Array()
		if ModelLibrary.surface_tag(mesh, i) == "yard":
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for k in verts.size():
				idx.append(k)
				weights.append(1.0)
				points.append(verts[k])
			any = true
		parts.append([idx, weights, points])
	var result := [all, parts] if any else []
	_yard_cache[mesh] = result
	return result


## Дворовые мелочи опускаются на землю под собой (поднимать их не нужно: здание
## стоит по самой высокой точке под стенами). Опускать нечего — общий меш.
func _fit_yard(mesh: Mesh) -> Mesh:
	var yard := _yard_of(mesh)
	if yard.is_empty():
		return mesh
	var xf := global_transform
	var y0 := global_position.y
	# На настиле над водой земля под двором — дно: мелочи стоят на настиле.
	if float(ground_height.call(global_position.x, global_position.z)) < WorldGen.WATER_LEVEL + 0.2:
		return mesh
	var drops := []
	var any := false
	for part: Array in yard[1]:
		var weights: PackedFloat32Array = part[1]
		var points: PackedVector3Array = part[2]
		var d := PackedFloat32Array()
		d.resize(points.size())
		for k in points.size():
			var w := xf * points[k]
			var ground := maxf(float(ground_height.call(w.x, w.z)), WorldGen.WATER_LEVEL + 0.2)
			var drop: float = minf(ground - y0, 0.0) * weights[k]
			d[k] = drop
			if drop < -0.03:
				any = true
		drops.append(d)
	if not any:
		return mesh
	var out := ArrayMesh.new()
	var all: Array = yard[0]
	for i in all.size():
		var arrays: Array = (all[i] as Array).duplicate()
		var verts := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		var idx: PackedInt32Array = (yard[1][i] as Array)[0]
		var d: PackedFloat32Array = drops[i]
		for k in idx.size():
			verts[idx[k]] = verts[idx[k]] + Vector3(0, d[k], 0)
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(i, mesh.surface_get_material(i))
	return out


## Насколько поднять (или опустить) точку модели p, чтобы она легла на землю.
func _ground_lift(p: Vector3) -> float:
	var w := global_transform * p
	return ground_height.call(w.x, w.z) - global_position.y


## Огонь и посадки ложатся на землю вместе с мешем: пламя костра — к углям (верх
## факела не сдвигается), растения — на гряды огорода.
func _fit_extras() -> void:
	if _ground_mesh == null or not is_inside_tree():
		return
	for f: Array in _fires:
		var base: Vector3 = f[1]
		(f[0] as Node3D).position = base + Vector3(0, _ground_lift(base) * (1.0 - smoothstep(1.0, 1.8, base.y)), 0)
	if _crops:
		_crops.lift_to(_ground_lift)


func setup(building_id: String, angle: float, instant: bool) -> void:
	id = building_id
	yaw = angle
	rotation.y = angle
	_apply_tilt()
	footprint = footprint_for(id, position, angle)
	var data := ModelLibrary.building(id)
	top_height = (data["bounds"] as AABB).end.y
	name = "%s_%d" % [id, get_instance_id()]

	_mesh = MeshInstance3D.new()
	var def: Dictionary = GameData.BUILDINGS[id]
	# Мелочь на земле (костёр, ограда, скамья) ложится по неровностям: брёвна и камни не висят в воздухе.
	var mesh: Mesh = data["mesh"]
	if def.get("conform", false) and ground_height.is_valid():
		_ground_mesh = mesh
		mesh = _conform(mesh)
	elif ground_height.is_valid() and def.get("place", "land") == "land" and not def.get("tilt", false) \
			and not def.has("plant") and not _yard_of(mesh).is_empty():
		# Бочки, бревна и камни у стен не висят над склоном.
		_yard_mesh = mesh
		mesh = _fit_yard(mesh)
	_mesh.mesh = mesh
	add_child(_mesh)
	if data["rotor_mesh"]:
		_rotor = Node3D.new()
		_rotor.position = data["pivot"]
		add_child(_rotor)
		_rotor_mesh = MeshInstance3D.new()
		_rotor_mesh.mesh = data["rotor_mesh"]
		_rotor.add_child(_rotor_mesh)

	if instant or GameMode.is_creative() or def.get("light", false) and def["time"] <= 0.6:
		ModelLibrary.apply_building_materials(_mesh)
		if _rotor_mesh:
			ModelLibrary.apply_building_materials(_rotor_mesh)
		progress = 1.0
		_finish(not instant)
		return

	_use_progress_materials(_mesh)
	if _rotor_mesh:
		_use_progress_materials(_rotor_mesh)
	_ghost = MeshInstance3D.new()
	_ghost.mesh = mesh
	add_child(_ghost)
	_progress_materials.append_array(apply_ghost_materials(_ghost, true))
	_set_progress(0.0)

	var b: AABB = data["bounds"]
	# Мелочь (факел, ограда, грядка) строится без лесов и подписи.
	if def.get("light", false):
		return
	_scaffold = _make_scaffold(b)
	add_child(_scaffold)
	_scaffold.position.y = -b.end.y
	_scaffold.create_tween().tween_property(_scaffold, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if WorldLabels.instance:
		_label = WorldLabels.instance.track(self, Vector3(0, top_height + 0.8, 0), "", true)

	_dust = CPUParticles3D.new()
	_dust.amount = 24
	_dust.lifetime = 1.2
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(b.size.x * 0.5, 0.2, b.size.z * 0.5)
	_dust.position = Vector3(b.get_center().x, 0.3, b.get_center().z)
	_dust.direction = Vector3.UP
	_dust.spread = 40.0
	_dust.gravity = Vector3(0, 0.4, 0)
	_dust.initial_velocity_min = 0.3
	_dust.initial_velocity_max = 0.9
	var puff := SphereMesh.new()
	puff.radius = 0.16
	puff.height = 0.32
	puff.radial_segments = 5
	puff.rings = 3
	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color = Color(0.85, 0.8, 0.7)
	dust_mat.roughness = 1.0
	puff.material = dust_mat
	_dust.mesh = puff
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0))
	_dust.scale_amount_curve = curve
	add_child(_dust)
	_update_label()


## Дорожка ложится по склону: «верх» здания смотрит по нормали земли.
func _apply_tilt() -> void:
	if not GameData.BUILDINGS[id].get("tilt", false) or ground_normal.is_equal_approx(Vector3.UP):
		return
	var n := ground_normal.normalized()
	if n.y < 0.5:
		return
	basis = Basis(Quaternion(Vector3.UP, n)) * Basis(Vector3.UP, yaw)


## Сменить культуру на грядке (сажается заново).
func set_crop(crop_id: String) -> void:
	crop = crop_id
	planted = Time.get_unix_time_from_system()
	if _crops:
		_crops.setup(crop, planted, GameData.BUILDINGS[id]["crops"], GameData.BUILDINGS[id].get("crop_top", 0.2))


func has_crops() -> bool:
	return GameData.BUILDINGS[id].has("crops")


func _add_extras() -> void:
	var def: Dictionary = GameData.BUILDINGS[id]
	for f: Array in def.get("fire", []):
		var fire := Fire.new()
		fire.size = f[1]
		fire.position = f[0]
		add_child(fire)
		_fires.append([fire, f[0]])
	if def.has("crops"):
		if crop == "":
			crop = "wheat"
		if planted <= 0.0:
			planted = Time.get_unix_time_from_system()
		_crops = CropPatch.new()
		add_child(_crops)
		_crops.setup(crop, planted, def["crops"], def.get("crop_top", 0.2))
	_fit_extras()


## Свои копии материалов для меша (общие материалы держат build_progress = 1).
func _use_progress_materials(mi: MeshInstance3D) -> void:
	for i in mi.mesh.get_surface_count():
		var m := ModelLibrary.building_material(ModelLibrary._surface_material_name(mi.mesh, i)).duplicate() as ShaderMaterial
		mi.set_surface_override_material(i, m)
		_progress_materials.append(m)


## Строительные леса: стойки по периметру, настилы и раскосы из жердей.
## Меш свой у каждого вида здания — собирается один раз.
func _make_scaffold(b: AABB) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if not _scaffold_meshes.has(id):
		_scaffold_meshes[id] = _scaffold_mesh(b)
	mi.mesh = _scaffold_meshes[id]
	mi.material_override = ModelLibrary.building_material("log")
	return mi


func _scaffold_mesh(b: AABB) -> Mesh:
	var g := Geo.new()
	g.with_uv2 = false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var pad := 0.35
	var x0 := b.position.x - pad
	var x1 := b.end.x + pad
	var z0 := b.position.z - pad
	var z1 := b.end.z + pad
	var height := clampf(b.end.y * 0.8, 1.6, 9.0)
	var wood := Color(0.62, 0.45, 0.28)
	var posts: Array[Vector3] = []
	for side in 4:
		var a := Vector3(x0, 0, z0) if side == 0 else (Vector3(x1, 0, z0) if side == 1 else (Vector3(x1, 0, z1) if side == 2 else Vector3(x0, 0, z1)))
		var c := Vector3(x1, 0, z0) if side == 0 else (Vector3(x1, 0, z1) if side == 1 else (Vector3(x0, 0, z1) if side == 2 else Vector3(x0, 0, z0)))
		var count := maxi(1, ceili(a.distance_to(c) / 2.2))
		for i in count:
			posts.append(a.lerp(c, float(i) / count))
		for level in range(1, int(height / 1.4) + 1):
			var y := level * 1.4
			g.rod("log", a + Vector3(0, y, 0), c + Vector3(0, y, 0), 0.04, 0.04, 4, wood.darkened(rng.randf_range(0.0, 0.15)), false)
		g.rod("log", a + Vector3(0, 0.2, 0), c + Vector3(0, height * 0.9, 0), 0.03, 0.03, 4, wood.darkened(0.2), false)
	for p in posts:
		g.rod("log", p + Vector3(0, -0.2, 0), p + Vector3(0, height, 0), 0.05, 0.045, 5, wood.lightened(rng.randf_range(-0.05, 0.08)))
	return g.build_mesh()


func build_time() -> float:
	return GameData.BUILDINGS[id]["time"]


func _set_progress(value: float) -> void:
	for m in _progress_materials:
		m.set_shader_parameter("build_progress", value)
		if m.next_pass:
			(m.next_pass as ShaderMaterial).set_shader_parameter("build_progress", value)


func _process(delta: float) -> void:
	if _rotor:
		# Крылья мельницы: чем сильнее ветер, тем быстрее; водяное колесо крутится ровно.
		var target := float(STEADY_ROTORS.get(id, 0.35 + Weather.wind * 1.8)) if is_complete else 0.0
		_rotor_speed = lerpf(_rotor_speed, target, 1.0 - exp(-0.6 * delta))
		_rotor.rotate_object_local(Vector3.BACK, _rotor_speed * delta)
	if is_complete or _removing:
		return
	progress = minf(progress + delta / build_time(), 1.0)
	_set_progress(progress)
	_update_label()
	if progress >= 1.0:
		_finish(true)


func _update_label() -> void:
	if not _label.is_empty():
		(_label["label"] as Label).text = "%s  %d%%" % [GameData.BUILDINGS[id]["name"], roundi(progress * 100.0)]
		(_label["bar"] as ProgressBar).value = progress


func _finish(animate: bool) -> void:
	is_complete = true
	WorldState.register_completed(id)
	# Готовое здание переходит на общие материалы.
	_progress_materials.clear()
	ModelLibrary.apply_building_materials(_mesh)
	if _rotor_mesh:
		ModelLibrary.apply_building_materials(_rotor_mesh)
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if not _label.is_empty() and WorldLabels.instance:
		WorldLabels.instance.untrack(_label)
		_label = {}
	if _scaffold:
		var sc := _scaffold
		_scaffold = null
		var tw := sc.create_tween()
		tw.tween_property(sc, "position:y", -top_height * 1.1, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(sc.queue_free)
	_add_extras()
	if animate:
		if _dust:
			_dust.emitting = false
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3(1.06, 0.92, 1.06), 0.12).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_mesh, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		Fx.burst(get_parent(), global_position + Vector3(0, 0.5, 0), Color(0.9, 0.85, 0.7), 24, 0.25)
	completed.emit(self)


func set_highlight(on: bool) -> void:
	_mesh.material_overlay = highlight_material() if on else null
	if _rotor_mesh:
		_rotor_mesh.material_overlay = highlight_material() if on else null


## Плавно «разбирает» здание сверху вниз и удаляет узел.
func demolish() -> void:
	if _removing:
		return
	_removing = true
	if is_complete:
		WorldState.unregister_completed(id)
	set_highlight(false)
	if not _label.is_empty() and WorldLabels.instance:
		WorldLabels.instance.untrack(_label)
		_label = {}
	if _progress_materials.is_empty():
		_use_progress_materials(_mesh)
		if _rotor_mesh:
			_use_progress_materials(_rotor_mesh)
	var tw := create_tween()
	tw.tween_method(_set_progress, progress, 0.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
	if _scaffold:
		_scaffold.queue_free()
	Fx.burst(get_parent(), global_position + Vector3(0, 0.5, 0), Color(0.75, 0.7, 0.6), 30, 0.3)
