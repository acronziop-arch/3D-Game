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
## Сколько кадров держать каждый шаг (в первом он рисуется и компилируется).
var frames_per_step := 1

var _index := -1
var _shown: Node3D
var _wait := 0


func _process(_delta: float) -> void:
	if _wait > 0:
		_wait -= 1
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
	progress.emit(float(_index + 1) / steps.size())
	_wait = frames_per_step - 1


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
