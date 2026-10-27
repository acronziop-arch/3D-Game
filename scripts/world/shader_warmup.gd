class_name ShaderWarmup
extends Node3D
## Подготовка графики перед показом мира. Шейдер компилируется, когда его впервые
## рисуют, — в браузере (особенно Safari на iPhone) это долго, и если всё рисуется
## в первом же кадре, страница надолго «замирает». Здесь каждый вид материала
## показывается перед камерой (под экраном загрузки) в своём кадре — по одному.

signal progress(fraction: float)
signal finished

## Шаги: Callable, возвращающий узел для показа (или null — шаг без узла).
var steps: Array[Callable] = []
## Освещение мира в разное время суток (день, сумерки, ночь): днём светит солнце с тенями,
## в сумерках — ещё и луна, ночью — только луна. Для каждого такого сочетания у материала
## свой вариант шейдера, поэтому узел шага показывается по кадру при каждом освещении.
var light_setups: Array[Callable] = []

var _index := -1
var _shown: Node3D
## Сколько вариантов освещения текущий узел уже показал.
var _lit := 0


func _process(_delta: float) -> void:
	if is_instance_valid(_shown) and _lit < light_setups.size():
		light_setups[_lit].call()
		_lit += 1
		return
	if is_instance_valid(_shown):
		_shown.queue_free()
		_shown = null
	_index += 1
	if _index >= steps.size():
		set_process(false)
		finished.emit()
		return
	var node: Variant = steps[_index].call()
	if node is Node3D:
		_shown = node
		add_child(_shown)
		var cam := get_viewport().get_camera_3d()
		if cam:
			# Чуть впереди камеры, лицом к ней: попадает и в кадр, и в карту теней.
			_shown.global_transform = cam.global_transform.translated_local(Vector3(0, 0, -6.0))
		# Рядом — огонёк, как от факела или костра ночью: освещённый им материал рисуется
		# другим вариантом шейдера, и этот вариант тоже должен собраться заранее.
		var light := OmniLight3D.new()
		light.omni_range = 4.0
		light.position = Vector3(0.5, 0.4, 1.2)
		_shown.add_child(light)
		_lit = 0
		if not light_setups.is_empty():
			light_setups[0].call()
			_lit = 1
	progress.emit(float(_index + 1) / steps.size())


# --- Готовые заготовки шагов ------------------------------------------------------------------

## Плоскость с материалом (обычная сетка).
static func quad(material: Material, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	mi.mesh = q
	mi.material_override = material
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Частицы CPUParticles3D с материалом (как искры над сундуком).
static func cpu_particles(material: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 2
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	q.material = material
	p.mesh = q
	p.emitting = true
	return p


## Один экземпляр MultiMesh в том же формате, что и у трав и деревьев.
static func multimesh(material: Material, colors := true, custom := false, shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = custom
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	mm.mesh = q
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	if colors:
		mm.set_instance_color(0, Color.WHITE)
	if custom:
		mm.set_instance_custom_data(0, Color(0, 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
