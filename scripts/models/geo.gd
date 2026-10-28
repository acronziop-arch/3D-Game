class_name Geo
extends RefCounted
## Сборщик геометрии для генерации моделей (деревья, здания, рыбы).
##
## Каждый треугольник получает:
##   * плоскую нормаль (грани видны, как в low-poly),
##   * цвет вершины (у каждого камня и доски свой оттенок),
##   * COLOR.a — «гибкость» для ветра (0 у корня, 1 на макушке),
##   * UV2 = (тип, зерно) — тип поверхности для шейдера: ствол, листва, хвоя, трава,
##     а зерно позволяет листьям опадать кучками осенью.
## Геометрия раскладывается по поверхностям-материалам (stone_block, plank…)
## и по «деталям» — из деталей потом собираются этапы анимации стройки.

const KIND_SOLID := 0.0
const KIND_LEAF := 1.0
const KIND_NEEDLE := 2.0
const KIND_PLANT := 3.0
## Материалы с волокнами (см. grain).
const WOOD := ["log", "log_dark", "plank", "plank_dark"]

## Текущая трансформация для добавляемой геометрии.
var xform := Transform3D.IDENTITY
## Текущий тип поверхности и зерно (уходят в UV2).
var kind := KIND_SOLID
var seed_value := 0.0
## Если > 0, гибкость вершины = (y / sway_height)^1.6.
var sway_height := 0.0
## Записывать ли UV2 (тип и зерно). Зданиям и рыбам не нужно — файлы меньше.
var with_uv2 := true
## Размер стекла окна: пока не ноль, UV2 = координаты точки внутри стекла 0..1
## (от нижнего левого угла) — по ним шейдер растит изморозь от рам.
var pane := Vector2.ZERO
## Пометка деталей: геометрия уходит в отдельную поверхность «материал__пометка».
## Так двери и окна («opening») можно выделить другим оттенком в превью стройки.
var tag := ""
## Направление волокон дерева у следующих деталей (в локальных осях; ноль — не задано).
## Коробки, цилиндры и плитки ставят его сами — вдоль длинной стороны или оси. Зданиям
## (with_uv2 = false) оно уходит в UV2 деревянных поверхностей: (1 + x, 1 + z) направления
## в осях модели, повёрнутого вверх (y ≥ 0), — по нему шейдер ведёт волокна досок и брёвен.
var grain := Vector3.ZERO

var _surfaces := {}
var _pieces: Array[Dictionary] = []
var _piece: Dictionary = {}
var _piece_depth := 0
var _stack: Array[Transform3D] = []


func push(t: Transform3D) -> void:
	_stack.append(xform)
	xform = xform * t


func pop() -> void:
	xform = _stack.pop_back()


# --- Детали --------------------------------------------------------------------------

## Всё, что добавлено между begin() и end(), считается одной деталью.
func begin() -> void:
	if _piece_depth == 0:
		_piece = {"ranges": {}, "min_y": INF, "max_y": -INF}
	_piece_depth += 1


func end() -> void:
	_piece_depth -= 1
	if _piece_depth == 0 and not _piece["ranges"].is_empty():
		_pieces.append(_piece)


func _surface(mat: String) -> Dictionary:
	var key := mat if tag == "" else "%s__%s" % [mat, tag]
	if not _surfaces.has(key):
		_surfaces[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(),
			"uv2": PackedVector2Array()}
	return _surfaces[key]


# --- Треугольники ---------------------------------------------------------------------

## Треугольник в локальных координатах (с учётом xform). ref — желаемое направление
## нормали: по нему исправляется порядок вершин (в Godot лицевая сторона — по часовой).
func tri(mat: String, a: Vector3, b: Vector3, c: Vector3, color: Color, ref := Vector3.ZERO) -> void:
	var local := [a, b, c]
	a = xform * a
	b = xform * b
	c = xform * c
	if ref != Vector3.ZERO:
		ref = xform.basis * ref
	var normal := (c - a).cross(b - a)
	if normal.length_squared() < 1e-14:
		return
	normal = normal.normalized()
	if ref != Vector3.ZERO and normal.dot(ref) < 0.0:
		var t := b
		b = c
		c = t
		normal = -normal
		local = [local[0], local[2], local[1]]
	begin()
	var s := _surface(mat)
	var key := mat if tag == "" else "%s__%s" % [mat, tag]
	var start: int = s["v"].size()
	if pane != Vector2.ZERO:
		s["pane"] = true
	var fiber := Vector2.ZERO
	if pane == Vector2.ZERO and not with_uv2 and grain != Vector3.ZERO and mat in WOOD:
		var d := (xform.basis * grain).normalized()
		if d.y < 0.0:
			d = -d
		fiber = Vector2(1.0 + d.x, 1.0 + d.z)
		s["grain"] = true
	for i in 3:
		var v: Vector3 = [a, b, c][i]
		s["v"].append(v)
		s["n"].append(normal)
		var alpha := 0.0
		if sway_height > 0.0:
			alpha = pow(clampf(v.y / sway_height, 0.0, 1.0), 1.6)
		s["c"].append(Color(color.r, color.g, color.b, alpha))
		if pane != Vector2.ZERO:
			var lp: Vector3 = local[i]
			s["uv2"].append(Vector2(lp.x / pane.x + 0.5, lp.y / pane.y + 0.5))
		elif fiber != Vector2.ZERO:
			s["uv2"].append(fiber)
		else:
			s["uv2"].append(Vector2(kind, seed_value))
		_piece["min_y"] = minf(_piece["min_y"], v.y)
		_piece["max_y"] = maxf(_piece["max_y"], v.y)
	var r: Array = _piece["ranges"].get(key, [start, start])
	_piece["ranges"][key] = [r[0], start + 3]
	end()


func quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, ref := Vector3.ZERO) -> void:
	if ref == Vector3.ZERO:
		ref = (b - a).cross(c - a)
		ref = -ref
	begin()
	tri(mat, a, b, c, color, ref)
	tri(mat, a, c, d, color, ref)
	end()


# --- Примитивы -------------------------------------------------------------------------

## Коробка со скошенными рёбрами (bevel) — «игрушечный» вид, как на референсах.
func box(mat: String, center: Vector3, size: Vector3, color: Color, bevel := 0.0, basis := Basis.IDENTITY) -> void:
	push(Transform3D(basis, center))
	var outer_grain := grain
	grain = Vector3.RIGHT if size.x >= size.y and size.x >= size.z else (Vector3.UP if size.y >= size.z else Vector3.BACK)
	begin()
	var h := size * 0.5
	bevel = minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var e := h - Vector3.ONE * bevel
	if bevel <= 0.0:
		for axis in 3:
			for s: float in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[axis] = s
				var u := Vector3.ZERO
				var w := Vector3.ZERO
				u[(axis + 1) % 3] = h[(axis + 1) % 3]
				w[(axis + 2) % 3] = h[(axis + 2) % 3]
				var c := n * h[axis]
				quad(mat, c - u - w, c + u - w, c + u + w, c - u + w, color, n)
	else:
		# Вершина грани `axis` в углу (sx, sy, sz).
		var fv := func(axis: int, sg: Vector3) -> Vector3:
			var p := Vector3(sg.x * e.x, sg.y * e.y, sg.z * e.z)
			p[axis] = sg[axis] * h[axis]
			return p
		for axis in 3:
			var a1 := (axis + 1) % 3
			var a2 := (axis + 2) % 3
			for s: float in [-1.0, 1.0]:
				var corners: Array[Vector3] = []
				for k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
					var sg := Vector3.ZERO
					sg[axis] = s
					sg[a1] = k[0]
					sg[a2] = k[1]
					corners.append(fv.call(axis, sg))
				var n := Vector3.ZERO
				n[axis] = s
				quad(mat, corners[0], corners[1], corners[2], corners[3], color, n)
			# Фаски вдоль оси `axis` (между гранями a1 и a2).
			for s1: float in [-1.0, 1.0]:
				for s2: float in [-1.0, 1.0]:
					var lo := Vector3.ZERO
					var hi := Vector3.ZERO
					lo[a1] = s1
					lo[a2] = s2
					lo[axis] = -1
					hi[a1] = s1
					hi[a2] = s2
					hi[axis] = 1
					var ref := Vector3.ZERO
					ref[a1] = s1
					ref[a2] = s2
					quad(mat, fv.call(a1, lo), fv.call(a1, hi), fv.call(a2, hi), fv.call(a2, lo), color.darkened(0.04), ref)
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var sg := Vector3(sx, sy, sz)
					tri(mat, fv.call(0, sg), fv.call(1, sg), fv.call(2, sg), color.darkened(0.06), sg)
	end()
	grain = outer_grain
	pop()


## Выпуклая плитка на поверхности: камень кладки, доска обшивки, черепица.
## center — точка на поверхности, normal — наружу, up — «вверх» плитки.
func tile(mat: String, center: Vector3, normal: Vector3, up: Vector3, w: float, h: float, depth: float, bevel: float, color: Color) -> void:
	normal = normal.normalized()
	up = (up - normal * up.dot(normal)).normalized()
	var right := up.cross(normal).normalized()
	var outer_grain := grain
	grain = right if w >= h else up
	bevel = minf(bevel, minf(w, h) * 0.45)
	var bw := w * 0.5
	var bh := h * 0.5
	var tw := bw - bevel
	var th := bh - bevel
	var top := center + normal * depth
	var b0 := center - right * bw - up * bh
	var b1 := center + right * bw - up * bh
	var b2 := center + right * bw + up * bh
	var b3 := center - right * bw + up * bh
	var t0 := top - right * tw - up * th
	var t1 := top + right * tw - up * th
	var t2 := top + right * tw + up * th
	var t3 := top - right * tw + up * th
	begin()
	quad(mat, t0, t1, t2, t3, color, normal)
	var side := color.darkened(0.05)
	quad(mat, b0, b1, t1, t0, side, normal - up)
	quad(mat, b1, b2, t2, t1, side, normal + right)
	quad(mat, b2, b3, t3, t2, side, normal + up)
	quad(mat, b3, b0, t0, t3, side, normal - right)
	end()
	grain = outer_grain


## Цилиндр вдоль локальной оси Y от base вверх на height.
func cylinder(mat: String, base: Vector3, r0: float, r1: float, height: float, segments: int, color: Color,
		cap_top := true, cap_bottom := false, angle_offset := 0.0, basis := Basis.IDENTITY) -> void:
	push(Transform3D(basis, base))
	var outer_grain := grain
	grain = Vector3.UP
	begin()
	var top := Vector3(0, height, 0)
	for i in segments:
		var a0 := angle_offset + TAU * i / segments
		var a1 := angle_offset + TAU * (i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var mid := (d0 + d1).normalized()
		var p0 := d0 * r0
		var p1 := d1 * r0
		var q0 := top + d0 * r1
		var q1 := top + d1 * r1
		var ref := mid * height + Vector3(0, r0 - r1, 0)
		if r1 > 0.0001:
			quad(mat, p0, p1, q1, q0, color, ref)
		else:
			tri(mat, p0, p1, top, color, ref)
		if cap_top and r1 > 0.0001:
			tri(mat, top, q0, q1, color, Vector3.UP)
		if cap_bottom:
			tri(mat, Vector3.ZERO, p0, p1, color.darkened(0.2), Vector3.DOWN)
	end()
	grain = outer_grain
	pop()


## Цилиндр между двумя точками (ветки, жерди, брёвна).
func rod(mat: String, from: Vector3, to: Vector3, r0: float, r1: float, segments: int, color: Color, caps := true) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.0001:
		return
	var y := dir / length
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	cylinder(mat, from, r0, r1, length, segments, color, caps, caps, 0.0, Basis(x, y, z))


## Цельная изогнутая «труба» через точки: стволы без зазоров и колец на стыках.
## radii — радиус в каждой точке. Кольца ориентированы по среднему направлению
## соседних отрезков, соседние кольца соединены — швов нет.
func tube(mat: String, points: Array[Vector3], radii: Array[float], segments: int, color: Color, cap_top := false,
		color_jitter := 0.0, rng: RandomNumberGenerator = null) -> void:
	if points.size() < 2:
		return
	begin()
	var rings: Array = []
	var prev_x := Vector3.ZERO
	for i in points.size():
		var dir: Vector3
		if i == 0:
			dir = points[1] - points[0]
		elif i == points.size() - 1:
			dir = points[i] - points[i - 1]
		else:
			dir = (points[i + 1] - points[i - 1])
		dir = dir.normalized()
		var x := prev_x if prev_x != Vector3.ZERO else dir.cross(Vector3.FORWARD if absf(dir.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT)
		x = (x - dir * x.dot(dir)).normalized()
		prev_x = x
		var z := x.cross(dir)
		var ring: Array[Vector3] = []
		for k in segments:
			var a := TAU * k / segments
			ring.append(points[i] + (x * cos(a) + z * sin(a)) * radii[i])
		rings.append(ring)
	for i in points.size() - 1:
		var r0: Array[Vector3] = rings[i]
		var r1: Array[Vector3] = rings[i + 1]
		var c := color
		if rng and color_jitter > 0.0:
			c = color.lightened(rng.randf_range(-color_jitter, color_jitter))
		for k in segments:
			var k1 := (k + 1) % segments
			var out := ((r0[k] + r0[k1]) * 0.5 - points[i])
			quad(mat, r0[k], r0[k1], r1[k1], r1[k], c, out)
	if cap_top:
		var last: Array[Vector3] = rings[rings.size() - 1]
		var tip := points[points.size() - 1]
		for k in segments:
			tri(mat, tip, last[k], last[(k + 1) % segments], color.darkened(0.1), points[points.size() - 1] - points[points.size() - 2])
	end()


## Бугристая сфера (икосфера с шумом): кроны, кусты, валуны.
## shade — насколько темнее нижние грани (имитация затенения).
func blob(mat: String, center: Vector3, radii: Vector3, color: Color, rng: RandomNumberGenerator,
		subdiv := 1, noise := 0.18, shade := 0.25, jitter := 0.05) -> void:
	var verts := _icosphere(subdiv)
	var displaced: Array[Vector3] = []
	for v in verts["v"]:
		var vv: Vector3 = v
		var k := 1.0 + rng.randf_range(-noise, noise)
		displaced.append(Vector3(vv.x * radii.x, vv.y * radii.y, vv.z * radii.z) * k)
	begin()
	for f in verts["f"]:
		var a: Vector3 = displaced[f[0]]
		var b: Vector3 = displaced[f[1]]
		var c: Vector3 = displaced[f[2]]
		var n := ((a + b + c) / 3.0).normalized()
		var light := 1.0 - shade * clampf(0.5 - n.y * 0.5, 0.0, 1.0) * 1.4
		light *= 1.0 + rng.randf_range(-jitter, jitter)
		tri(mat, center + a, center + b, center + c, Color(color.r * light, color.g * light, color.b * light), n)
	end()


static var _ico_cache := {}


static func _icosphere(subdiv: int) -> Dictionary:
	if _ico_cache.has(subdiv):
		return _ico_cache[subdiv]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = []
	for p in [[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
			[t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]]:
		v.append(Vector3(p[0], p[1], p[2]).normalized())
	var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for s in subdiv:
		var mids := {}
		var nf := []
		var mid := func(i: int, j: int) -> int:
			var key := Vector2i(mini(i, j), maxi(i, j))
			if not mids.has(key):
				v.append(((v[i] + v[j]) * 0.5).normalized())
				mids[key] = v.size() - 1
			return mids[key]
		for tri_idx in f:
			var a: int = mid.call(tri_idx[0], tri_idx[1])
			var b: int = mid.call(tri_idx[1], tri_idx[2])
			var c: int = mid.call(tri_idx[2], tri_idx[0])
			nf.append_array([[tri_idx[0], a, c], [tri_idx[1], b, a], [tri_idx[2], c, b], [a, b, c]])
		f = nf
	_ico_cache[subdiv] = {"v": v, "f": f}
	return _ico_cache[subdiv]


## Двускатный фронтон: треугольник шириной w (по X), высотой h, толщиной t (по Z).
func gable(mat: String, base_center: Vector3, w: float, h: float, t: float, color: Color) -> void:
	var hw := w * 0.5
	var ht := t * 0.5
	begin()
	for s: float in [-1.0, 1.0]:
		var z := ht * s
		tri(mat, base_center + Vector3(-hw, 0, z), base_center + Vector3(hw, 0, z), base_center + Vector3(0, h, z), color, Vector3(0, 0, s))
	for s: float in [-1.0, 1.0]:
		var a := base_center + Vector3(hw * s, 0, -ht)
		var b := base_center + Vector3(hw * s, 0, ht)
		var c := base_center + Vector3(0, h, ht)
		var d := base_center + Vector3(0, h, -ht)
		quad(mat, a, b, c, d, color, Vector3(s * h, hw, 0))
	end()


# --- Сборка мешей ---------------------------------------------------------------------------

func is_empty() -> bool:
	return _surfaces.is_empty()


func aabb() -> AABB:
	var box := AABB()
	var first := true
	for mat: String in _surfaces:
		for v: Vector3 in _surfaces[mat]["v"]:
			if first:
				box = AABB(v, Vector3.ZERO)
				first = false
			else:
				box = box.expand(v)
	return box


## Пятно модели у земли (XZ): по вершинам не выше max_y. Свесы крыш, вывески и козырьки
## сюда не входят — по пятну проверяется, не стоят ли постройки друг в друге.
func base_rect(max_y: float) -> Rect2:
	var rect := Rect2()
	var first := true
	for mat: String in _surfaces:
		for v: Vector3 in _surfaces[mat]["v"]:
			if v.y > max_y:
				continue
			var p := Vector2(v.x, v.z)
			if first:
				rect = Rect2(p, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(p)
	if first:
		var box := aabb()
		return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	return rect


static func _material_stub(mat: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	return m


func _arrays(s: Dictionary, from: int, to: int) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = s["v"].slice(from, to)
	arrays[Mesh.ARRAY_NORMAL] = s["n"].slice(from, to)
	arrays[Mesh.ARRAY_COLOR] = s["c"].slice(from, to)
	if with_uv2 or s.get("pane", false) or s.get("grain", false):
		arrays[Mesh.ARRAY_TEX_UV2] = s["uv2"].slice(from, to)
	return arrays


## Один меш со всей геометрией: по поверхности на материал.
## Одинаковые вершины склеиваются (индексный буфер) — файлы получаются меньше.
func build_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var mats := _surfaces.keys()
	mats.sort()
	for mat: String in mats:
		var s: Dictionary = _surfaces[mat]
		var st := SurfaceTool.new()
		st.create_from_arrays(_arrays(s, 0, s["v"].size()))
		st.index()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material_stub(mat))
	return mesh


## Записывает в COLOR.a каждой детали «этап стройки» 0..1: чем ниже деталь, тем
## раньше она появляется. Шейдер здания по этому числу собирает дом снизу вверх.
func encode_stages(max_stages := 40, min_band := 0.25, override := -1.0) -> void:
	if _pieces.is_empty():
		return
	var lo := INF
	var hi := -INF
	for p in _pieces:
		lo = minf(lo, p["min_y"])
		hi = maxf(hi, p["min_y"])
	var band := maxf(min_band, (hi - lo) / max_stages + 0.0001)
	var bands := floori((hi - lo) / band) + 1
	for p in _pieces:
		var stage := override
		if stage < 0.0:
			stage = (floorf((p["min_y"] - lo) / band) + 0.5) / bands
		for mat: String in p["ranges"]:
			var r: Array = p["ranges"][mat]
			var colors: PackedColorArray = _surfaces[mat]["c"]
			for i in range(r[0], r[1]):
				colors[i].a = stage
			_surfaces[mat]["c"] = colors


## Равномерно масштабирует всю геометрию (нормали при этом не меняются).
func scale_all(k: float) -> void:
	for key: String in _surfaces:
		var verts: PackedVector3Array = _surfaces[key]["v"]
		for i in verts.size():
			verts[i] *= k
		_surfaces[key]["v"] = verts
	for p in _pieces:
		p["min_y"] *= k
		p["max_y"] *= k


func triangle_count() -> int:
	var n := 0
	for mat: String in _surfaces:
		n += _surfaces[mat]["v"].size() / 3
	return n
