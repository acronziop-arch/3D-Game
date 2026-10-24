extends Node
## Регистрирует действия ввода по умолчанию.
## Используются физические клавиши, поэтому WASD работает и на русской раскладке.
## Если действие уже задано в Project Settings → Input Map, оно не перезаписывается.

const KEYS := {
	"cam_forward": [KEY_W, KEY_UP],
	"cam_back": [KEY_S, KEY_DOWN],
	"cam_left": [KEY_A, KEY_LEFT],
	"cam_right": [KEY_D, KEY_RIGHT],
	"cam_rotate_left": [KEY_Q],
	"cam_rotate_right": [KEY_E],
	"cam_fast": [KEY_SHIFT],
	"tool_harvest": [KEY_1],
	"tool_build": [KEY_2],
	"tool_flatten": [KEY_3],
	"tool_demolish": [KEY_4],
	"toggle_crafting": [KEY_C],
	"rotate_building": [KEY_R],
	"brush_bigger": [KEY_BRACKETRIGHT, KEY_EQUAL],
	"brush_smaller": [KEY_BRACKETLEFT, KEY_MINUS],
	"cancel": [KEY_ESCAPE],
	"quick_save": [KEY_F5],
}


func _init() -> void:
	for action: String in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
