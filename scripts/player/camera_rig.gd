class_name CameraRig
extends Node3D
## Камера «взгляд сверху» как в Townscaper / Islanders: персонажа нет.
## Все движения сглажены экспоненциально — камера никогда не дёргается.
##   WASD / стрелки — движение, Shift — быстрее, Q/E — поворот,
##   колесо — приближение, ПКМ (зажать) — вращение, СКМ (зажать) — перетаскивание.

@export var min_distance := 9.0
@export var max_distance := 150.0
@export var pan_speed := 0.9
@export var rotate_speed := 1.8
@export var smoothing := 9.0

var chunk_manager: ChunkManager

var _target := Vector3.ZERO
var _yaw := deg_to_rad(45.0)
var _target_yaw := _yaw
var _distance := 45.0
var _target_distance := 45.0
var _tilt_offset := 0.0
var _target_tilt_offset := 0.0
var _rotating := false
var _panning := false
var _drag_moved := 0.0

@onready var _pitch: Node3D = $Pitch
@onready var camera: Camera3D = $Pitch/Camera3D


func teleport(pos: Vector3) -> void:
	_target = pos
	position = pos


func get_state() -> Dictionary:
	return {"pos": _target, "yaw": _target_yaw, "dist": _target_distance}


func set_state(state: Dictionary) -> void:
	teleport(state.get("pos", Vector3.ZERO))
	_yaw = state.get("yaw", _yaw)
	_target_yaw = _yaw
	_distance = state.get("dist", _distance)
	_target_distance = _distance


## true, если правая кнопка была просто щелчком, а не вращением камеры.
func was_right_click() -> bool:
	return _drag_moved < 6.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if not mb.shift_pressed:
					_target_distance = maxf(min_distance, _target_distance * 0.88)
			MOUSE_BUTTON_WHEEL_DOWN:
				if not mb.shift_pressed:
					_target_distance = minf(max_distance, _target_distance * 1.14)
			MOUSE_BUTTON_RIGHT:
				_rotating = mb.pressed
				if mb.pressed:
					_drag_moved = 0.0
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rotating:
			_drag_moved += mm.relative.length()
			_target_yaw -= mm.relative.x * 0.006
			_target_tilt_offset = clampf(_target_tilt_offset + mm.relative.y * 0.003, -0.35, 0.35)
		elif _panning:
			var k := _target_distance * 0.0022
			_target += _flat_basis() * Vector3(-mm.relative.x * k, 0, -mm.relative.y * k)


func _flat_basis() -> Basis:
	return Basis(Vector3.UP, _target_yaw)


func _process(delta: float) -> void:
	var input := Input.get_vector("cam_left", "cam_right", "cam_forward", "cam_back")
	var speed := pan_speed * (12.0 + _target_distance) * (2.5 if Input.is_action_pressed("cam_fast") else 1.0)
	_target += _flat_basis() * Vector3(input.x, 0, input.y) * speed * delta
	_target_yaw += (Input.get_action_strength("cam_rotate_left") - Input.get_action_strength("cam_rotate_right")) * rotate_speed * delta

	if chunk_manager:
		_target.y = maxf(chunk_manager.get_height(_target.x, _target.z), WorldGen.WATER_LEVEL)
		chunk_manager.focus = _target

	var k := 1.0 - exp(-smoothing * delta)
	position = position.lerp(_target, k)
	_yaw = lerp_angle(_yaw, _target_yaw, k)
	_distance = lerpf(_distance, _target_distance, k)
	_tilt_offset = lerpf(_tilt_offset, _target_tilt_offset, k)
	rotation.y = _yaw

	# Вблизи смотрим более полого, издалека — сверху: так приятнее рассматривать постройки.
	var zoom := inverse_lerp(min_distance, max_distance, _distance)
	_pitch.rotation.x = clampf(-lerpf(0.42, 1.05, zoom) - _tilt_offset, -1.35, -0.2)
	camera.position = Vector3(0, 0, _distance)

	# Не даём камере уйти под землю (например, за горой).
	if chunk_manager:
		var cam := camera.global_position
		var ground := maxf(chunk_manager.get_height(cam.x, cam.z), WorldGen.WATER_LEVEL) + 2.0
		if cam.y < ground:
			_target_tilt_offset = minf(_target_tilt_offset + delta * 1.5, 0.35)
