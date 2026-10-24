class_name Blueprints
extends RefCounted
## Временные модели зданий из примитивов. Каждая деталь помечена материалом
## из GameData.MATERIALS — по ним проверяется, что модель соответствует
## стоимости здания, и по ним же идёт анимация стройки (детали появляются
## снизу вверх).
##
## Когда будут готовы модели из Blender: экспортируйте каждую деталь как
## отдельный узел glTF, назовите узлы «материал_номер» (stone_block_1, glass_2…)
## и замените parts() на загрузку .glb — логика стройки останется прежней.
##
## Оси: +Z — фасад, Y — вверх, 0 — уровень земли. Фундамент уходит под землю,
## чтобы здание красиво стояло на неровном склоне.

## Вращающиеся части (крылья мельницы): pivot — ось, axis — направление, speed — град/с.
const ROTORS := {
	"windmill": {"pivot": Vector3(0, 7.6, 2.55), "axis": Vector3(0, 0, 1), "speed": 45.0},
}

static var _built := {}
static var _materials := {}


## shape: box | roof | cyl | cone | sphere.
## size: box/roof — размеры; cyl — (нижний диаметр, высота, верхний диаметр);
## cone — (диаметр, высота, -); sphere — (диаметр, высота, -).
static func _p(shape: String, mat: String, size: Vector3, pos: Vector3, rot := Vector3.ZERO, extra := {}) -> Dictionary:
	var part := {"shape": shape, "mat": mat, "size": size, "pos": pos, "rot": rot}
	part.merge(extra)
	return part


static func parts(id: String) -> Array[Dictionary]:
	var p: Array[Dictionary] = []
	match id:
		"sawmill":
			p.append(_p("box", "stone", Vector3(6.4, 1.8, 4.4), Vector3(0, -0.6, 0)))
			for x in [-2.8, 2.8]:
				for z in [-1.8, 1.8]:
					p.append(_p("cyl", "log", Vector3(0.4, 3.2, 0.36), Vector3(x, 1.9, z)))
			p.append(_p("roof", "log", Vector3(5.2, 1.4, 7.0), Vector3(0, 4.2, 0), Vector3(0, 90, 0)))
			p.append(_p("box", "log_dark", Vector3(3.2, 0.8, 1.0), Vector3(0, 0.7, -0.6)))
			for i in 3:
				p.append(_p("cyl", "log", Vector3(0.5, 4.2, 0.5), Vector3(0, 0.55 + (0.42 if i == 2 else 0.0), 1.2 + (0.25 if i == 2 else i * 0.5)), Vector3(0, 0, 90)))
		"stonemason":
			p.append(_p("box", "stone", Vector3(5.4, 1.8, 4.4), Vector3(0, -0.6, 0)))
			p.append(_p("box", "plank", Vector3(5.0, 2.8, 0.2), Vector3(0, 1.7, -2.0)))
			for x in [-2.4, 2.4]:
				p.append(_p("box", "plank", Vector3(0.2, 2.8, 4.0), Vector3(x, 1.7, 0)))
				p.append(_p("cyl", "log", Vector3(0.35, 3.0, 0.3), Vector3(x, 1.8, 2.0)))
			p.append(_p("roof", "plank_dark", Vector3(5.0, 1.3, 6.0), Vector3(0, 3.95, 0), Vector3(0, 90, 0)))
			p.append(_p("box", "stone", Vector3(0.8, 0.6, 0.8), Vector3(1.2, 0.6, 2.8)))
			p.append(_p("box", "stone", Vector3(0.8, 0.6, 0.8), Vector3(2.1, 0.6, 2.9), Vector3(0, 20, 0)))
			p.append(_p("box", "stone", Vector3(0.7, 0.5, 0.7), Vector3(1.6, 1.15, 2.85), Vector3(0, 40, 0)))
		"kiln":
			p.append(_p("cyl", "stone", Vector3(4.4, 2.4, 4.4), Vector3(0, -0.6, 0)))
			p.append(_p("cyl", "clay", Vector3(3.6, 2.2, 2.8), Vector3(0, 1.7, 0)))
			p.append(_p("cone", "clay", Vector3(2.8, 1.6, 0), Vector3(0, 3.6, 0)))
			p.append(_p("cyl", "clay", Vector3(0.7, 1.2, 0.55), Vector3(0, 4.3, 0)))
			p.append(_p("box", "stone", Vector3(1.0, 1.0, 0.5), Vector3(0, 1.1, 1.55)))
			for z in [-1.2, 1.2]:
				p.append(_p("box", "plank", Vector3(0.25, 2.6, 0.25), Vector3(3.2, 1.6, z)))
			p.append(_p("roof", "plank_dark", Vector3(2.2, 0.8, 3.2), Vector3(3.2, 3.3, 0)))
		"tannery":
			p.append(_p("box", "log", Vector3(5.2, 1.6, 4.0), Vector3(0, -0.5, 0)))
			p.append(_p("box", "plank", Vector3(4.6, 2.4, 3.4), Vector3(0, 1.5, -0.2)))
			p.append(_p("roof", "plank_dark", Vector3(4.2, 1.4, 5.4), Vector3(0, 3.4, -0.2), Vector3(0, 90, 0)))
			for x in [-1.3, 1.3]:
				p.append(_p("cyl", "plank", Vector3(1.1, 0.8, 1.2), Vector3(x, 0.7, 2.6)))
			p.append(_p("box", "plank_dark", Vector3(1.0, 1.8, 0.1), Vector3(0, 1.2, 1.52)))
		"weaver":
			p.append(_p("box", "stone", Vector3(5.2, 1.8, 4.6), Vector3(0, -0.6, 0)))
			p.append(_p("box", "plank", Vector3(4.8, 2.6, 4.2), Vector3(0, 1.6, 0)))
			p.append(_p("roof", "plank_dark", Vector3(4.8, 1.6, 5.6), Vector3(0, 3.7, 0), Vector3(0, 90, 0)))
			p.append(_p("box", "plank_dark", Vector3(1.0, 1.8, 0.1), Vector3(0, 1.2, 2.12)))
			for x in [-1.5, 1.5]:
				p.append(_p("box", "plank_dark", Vector3(0.8, 0.7, 0.08), Vector3(x, 1.9, 2.12)))
		"glassworks":
			p.append(_p("box", "stone_block", Vector3(6.4, 1.8, 5.0), Vector3(0, -0.6, 0)))
			p.append(_p("box", "brick", Vector3(6.0, 3.0, 4.6), Vector3(0, 1.8, 0)))
			p.append(_p("roof", "plank_dark", Vector3(5.2, 1.6, 6.6), Vector3(0, 4.1, 0), Vector3(0, 90, 0)))
			p.append(_p("box", "brick", Vector3(0.9, 3.4, 0.9), Vector3(1.9, 4.6, -1.2)))
			p.append(_p("box", "plank_dark", Vector3(1.2, 2.0, 0.1), Vector3(-1.2, 1.3, 2.32)))
			p.append(_p("cyl", "brick", Vector3(1.8, 1.2, 1.2), Vector3(1.6, 0.9, 2.9)))
		"smithy":
			p.append(_p("box", "stone_block", Vector3(6.0, 1.8, 4.6), Vector3(0, -0.6, 0)))
			p.append(_p("box", "stone_block", Vector3(5.6, 1.2, 4.2), Vector3(0, 0.9, 0)))
			p.append(_p("box", "plank", Vector3(5.6, 1.6, 4.2), Vector3(0, 2.3, 0)))
			p.append(_p("roof", "plank_dark", Vector3(5.0, 1.6, 6.2), Vector3(0, 3.9, 0), Vector3(0, 90, 0)))
			p.append(_p("box", "brick", Vector3(1.0, 3.8, 1.0), Vector3(-2.0, 4.1, -1.1)))
			p.append(_p("box", "brick", Vector3(1.4, 1.0, 1.0), Vector3(1.5, 0.8, 2.8)))
			p.append(_p("box", "leather", Vector3(0.8, 0.4, 0.6), Vector3(0.3, 0.8, 2.8), Vector3(0, 0, 10)))
			p.append(_p("box", "plank_dark", Vector3(1.1, 2.0, 0.1), Vector3(-1.0, 1.3, 2.12)))
		"hut":
			p.append(_p("box", "log", Vector3(4.2, 1.6, 3.6), Vector3(0, -0.5, 0)))
			for i in 4:
				for z in [-1.5, 1.5]:
					p.append(_p("cyl", "log", Vector3(0.5, 3.9, 0.5), Vector3(0, 0.55 + i * 0.48, z), Vector3(0, 0, 90)))
				for x in [-1.75, 1.75]:
					p.append(_p("cyl", "log", Vector3(0.5, 3.3, 0.5), Vector3(x, 0.79 + i * 0.48, 0), Vector3(90, 0, 0)))
			p.append(_p("roof", "log_dark", Vector3(4.6, 1.6, 4.4), Vector3(0, 3.2, 0)))
			p.append(_p("box", "log_dark", Vector3(0.9, 1.6, 0.1), Vector3(0, 1.1, 1.78)))
		"wood_house":
			p.append(_p("box", "stone", Vector3(5.0, 1.8, 4.0), Vector3(0, -0.6, 0)))
			p.append(_p("box", "plank", Vector3(4.6, 2.6, 3.6), Vector3(0, 1.6, 0)))
			for x in [-2.3, 2.3]:
				for z in [-1.8, 1.8]:
					p.append(_p("cyl", "log", Vector3(0.36, 2.8, 0.36), Vector3(x, 1.7, z)))
			p.append(_p("roof", "plank_dark", Vector3(4.4, 1.8, 5.4), Vector3(0, 3.8, 0), Vector3(0, 90, 0)))
			p.append(_p("box", "plank_dark", Vector3(1.0, 1.8, 0.1), Vector3(0, 1.2, 1.82)))
			for x in [-1.4, 1.4]:
				p.append(_p("box", "plank_dark", Vector3(0.7, 0.7, 0.08), Vector3(x, 1.9, 1.82)))
			p.append(_p("box", "stone", Vector3(0.6, 1.6, 0.6), Vector3(1.4, 4.4, -0.6)))
		"stone_house":
			p.append(_p("box", "stone_block", Vector3(5.4, 1.8, 4.4), Vector3(0, -0.6, 0)))
			p.append(_p("box", "stone_block", Vector3(5.0, 3.0, 4.0), Vector3(0, 1.8, 0)))
			p.append(_p("roof", "plank_dark", Vector3(4.8, 1.8, 5.8), Vector3(0, 4.2, 0), Vector3(0, 90, 0)))
			p.append(_p("box", "plank", Vector3(1.0, 2.0, 0.1), Vector3(0, 1.3, 2.02)))
			for x in [-1.5, 1.5]:
				p.append(_p("box", "glass", Vector3(0.8, 0.8, 0.08), Vector3(x, 2.0, 2.02)))
			p.append(_p("box", "stone_block", Vector3(0.7, 1.8, 0.7), Vector3(-1.5, 4.8, -0.8)))
		"brick_house":
			p.append(_p("box", "stone_block", Vector3(5.6, 1.8, 4.6), Vector3(0, -0.6, 0)))
			p.append(_p("box", "brick", Vector3(5.2, 4.6, 4.2), Vector3(0, 2.6, 0)))
			p.append(_p("box", "stone_block", Vector3(5.4, 0.25, 4.4), Vector3(0, 2.6, 0)))
			p.append(_p("roof", "roof_tile", Vector3(5.0, 2.0, 6.0), Vector3(0, 5.9, 0), Vector3(0, 90, 0)))
			p.append(_p("box", "plank", Vector3(1.0, 2.0, 0.1), Vector3(0, 1.3, 2.12)))
			for x in [-1.6, 1.6]:
				p.append(_p("box", "glass", Vector3(0.8, 0.9, 0.08), Vector3(x, 1.6, 2.12)))
			for x in [-1.6, 0.0, 1.6]:
				p.append(_p("box", "glass", Vector3(0.8, 0.9, 0.08), Vector3(x, 3.7, 2.12)))
			p.append(_p("box", "brick", Vector3(0.7, 2.0, 0.7), Vector3(1.6, 6.6, -1.0)))
		"barn":
			p.append(_p("box", "stone", Vector3(7.0, 1.8, 5.0), Vector3(0, -0.6, 0)))
			p.append(_p("box", "plank", Vector3(6.6, 3.4, 4.6), Vector3(0, 2.0, 0)))
			for x in [-3.3, 3.3]:
				for z in [-2.3, 2.3]:
					p.append(_p("cyl", "log", Vector3(0.4, 3.6, 0.4), Vector3(x, 2.1, z)))
			p.append(_p("roof", "plank_dark", Vector3(5.6, 2.4, 7.4), Vector3(0, 4.9, 0), Vector3(0, 90, 0)))
			p.append(_p("box", "plank_dark", Vector3(2.2, 2.6, 0.1), Vector3(0, 1.6, 2.32)))
			for a in [40.0, -40.0]:
				p.append(_p("cyl", "log", Vector3(0.14, 3.2, 0.14), Vector3(0, 1.6, 2.4), Vector3(0, 0, a)))
		"tent":
			p.append(_p("cyl", "log", Vector3(0.16, 4.0, 0.12), Vector3(0, 1.8, 0)))
			p.append(_p("cone", "leather", Vector3(3.8, 3.2, 0), Vector3(0, 1.5, 0), Vector3.ZERO, {"seg": 6}))
			for i in 3:
				var a := i * TAU / 3.0
				p.append(_p("cyl", "log", Vector3(0.1, 0.6, 0.06), Vector3(cos(a) * 2.2, 0.2, sin(a) * 2.2)))
		"well":
			p.append(_p("cyl", "stone", Vector3(2.4, 1.6, 2.4), Vector3(0, -0.3, 0)))
			p.append(_p("cyl", "stone", Vector3(2.2, 0.7, 2.2), Vector3(0, 0.85, 0)))
			for x in [-0.95, 0.95]:
				p.append(_p("box", "plank", Vector3(0.2, 2.4, 0.2), Vector3(x, 1.7, 0)))
			p.append(_p("cyl", "iron", Vector3(0.16, 2.0, 0.16), Vector3(0, 2.3, 0), Vector3(0, 0, 90)))
			p.append(_p("cyl", "iron", Vector3(0.4, 0.4, 0.45), Vector3(0, 1.6, 0)))
			p.append(_p("roof", "plank_dark", Vector3(1.8, 0.9, 2.6), Vector3(0, 3.35, 0), Vector3(0, 90, 0)))
		"market":
			p.append(_p("box", "plank", Vector3(3.8, 1.0, 2.8), Vector3(0, -0.3, 0)))
			p.append(_p("box", "plank", Vector3(3.2, 1.0, 0.9), Vector3(0, 0.7, 0.8)))
			for x in [-1.6, 1.6]:
				for z in [-1.2, 1.2]:
					p.append(_p("cyl", "log", Vector3(0.16, 2.6, 0.14), Vector3(x, 1.5, z)))
			p.append(_p("roof", "cloth", Vector3(3.2, 0.7, 4.0), Vector3(0, 3.15, 0), Vector3(0, 90, 0)))
			for x in [-0.9, 0.0, 0.9]:
				p.append(_p("box", "plank_dark", Vector3(0.6, 0.45, 0.5), Vector3(x, 1.43, 0.8), Vector3(0, x * 20.0, 0)))
		"chapel":
			p.append(_p("box", "log", Vector3(4.4, 1.8, 6.4), Vector3(0, -0.6, 0)))
			p.append(_p("box", "plank", Vector3(4.0, 3.2, 6.0), Vector3(0, 1.9, 0)))
			p.append(_p("roof", "plank_dark", Vector3(4.6, 2.4, 6.6), Vector3(0, 4.7, 0)))
			p.append(_p("box", "plank", Vector3(1.5, 3.0, 1.5), Vector3(0, 5.0, 2.3)))
			p.append(_p("cone", "plank_dark", Vector3(2.0, 2.4, 0), Vector3(0, 7.7, 2.3), Vector3(0, 45, 0), {"seg": 4}))
			p.append(_p("box", "plank", Vector3(0.12, 1.0, 0.12), Vector3(0, 9.3, 2.3)))
			p.append(_p("box", "plank", Vector3(0.6, 0.12, 0.12), Vector3(0, 9.5, 2.3)))
			p.append(_p("box", "plank_dark", Vector3(1.2, 2.2, 0.1), Vector3(0, 1.4, 3.02)))
			for z in [-1.5, 0.5]:
				for x in [-2.02, 2.02]:
					p.append(_p("box", "plank_dark", Vector3(0.08, 1.2, 0.6), Vector3(x, 2.2, z)))
			for x in [-0.95, 0.95]:
				p.append(_p("cyl", "wax", Vector3(0.14, 0.45, 0.12), Vector3(x, 0.55, 3.3)))
		"church":
			p.append(_p("box", "stone_block", Vector3(6.4, 1.8, 10.4), Vector3(0, -0.6, 0)))
			p.append(_p("box", "stone_block", Vector3(6.0, 4.6, 8.0), Vector3(0, 2.6, -1.0)))
			p.append(_p("roof", "plank_dark", Vector3(6.6, 3.0, 8.6), Vector3(0, 6.4, -1.0)))
			p.append(_p("cyl", "stone_block", Vector3(4.4, 4.0, 4.4), Vector3(0, 2.3, -5.0)))
			p.append(_p("cone", "copper", Vector3(4.7, 1.8, 0), Vector3(0, 5.2, -5.0)))
			p.append(_p("box", "stone_block", Vector3(3.0, 9.0, 3.0), Vector3(0, 4.8, 4.2)))
			p.append(_p("box", "stone_block", Vector3(3.3, 0.4, 3.3), Vector3(0, 9.45, 4.2)))
			p.append(_p("cyl", "stone_block", Vector3(1.8, 0.8, 1.8), Vector3(0, 10.05, 4.2)))
			p.append(_p("sphere", "copper", Vector3(2.4, 2.4, 0), Vector3(0, 11.5, 4.2)))
			p.append(_p("cone", "copper", Vector3(0.9, 1.6, 0), Vector3(0, 13.1, 4.2)))
			p.append(_p("box", "copper", Vector3(0.12, 1.3, 0.12), Vector3(0, 14.4, 4.2)))
			p.append(_p("box", "copper", Vector3(0.7, 0.12, 0.12), Vector3(0, 14.6, 4.2)))
			for z in [-3.5, -1.0, 1.5]:
				for x in [-3.02, 3.02]:
					p.append(_p("box", "glass", Vector3(0.1, 2.0, 0.8), Vector3(x, 2.8, z - 1.0)))
			p.append(_p("cyl", "glass", Vector3(1.0, 0.1, 1.0), Vector3(0, 6.6, 5.72), Vector3(90, 0, 0)))
			p.append(_p("box", "plank", Vector3(1.4, 2.4, 0.1), Vector3(0, 1.5, 5.72)))
			for x in [-1.1, 1.1]:
				p.append(_p("cyl", "wax", Vector3(0.14, 0.5, 0.12), Vector3(x, 0.55, 6.0)))
		"windmill":
			p.append(_p("cyl", "stone_block", Vector3(4.8, 1.8, 4.8), Vector3(0, -0.6, 0)))
			p.append(_p("cyl", "stone_block", Vector3(4.2, 4.0, 3.6), Vector3(0, 2.3, 0)))
			p.append(_p("cyl", "plank", Vector3(3.6, 3.0, 3.0), Vector3(0, 5.8, 0)))
			p.append(_p("cone", "plank_dark", Vector3(3.7, 2.0, 0), Vector3(0, 8.3, 0)))
			p.append(_p("box", "plank_dark", Vector3(0.9, 1.8, 0.12), Vector3(0, 1.2, 2.0)))
			p.append(_p("cyl", "log", Vector3(0.32, 1.6, 0.32), Vector3(0, 7.6, 1.8), Vector3(90, 0, 0)))
			var pivot: Vector3 = ROTORS["windmill"]["pivot"]
			for i in 4:
				var a := i * TAU / 4.0 + PI / 4.0
				var dir := Vector3(cos(a), sin(a), 0)
				var side := Vector3(-sin(a), cos(a), 0)
				var rz := rad_to_deg(a) - 90.0
				p.append(_p("box", "plank", Vector3(0.2, 5.4, 0.14), pivot + dir * 2.8, Vector3(0, 0, rz), {"group": "rotor"}))
				p.append(_p("box", "cloth", Vector3(1.1, 4.4, 0.05), pivot + dir * 3.1 + side * 0.65 + Vector3(0, 0, -0.06), Vector3(0, 0, rz), {"group": "rotor"}))
		"cannon":
			p.append(_p("box", "plank", Vector3(0.9, 0.5, 2.0), Vector3(0, 0.75, -0.2)))
			for x in [-0.6, 0.6]:
				p.append(_p("cyl", "plank_dark", Vector3(1.2, 0.18, 1.2), Vector3(x, 0.6, 0.2), Vector3(0, 0, 90), {"seg": 10}))
			p.append(_p("cyl", "log", Vector3(0.15, 1.5, 0.15), Vector3(0, 0.6, 0.2), Vector3(0, 0, 90)))
			p.append(_p("cyl", "iron", Vector3(0.62, 2.6, 0.42), Vector3(0, 1.25, 0.35), Vector3(80, 0, 0), {"seg": 10}))
			for b in [Vector3(0.9, 0.15, -1.0), Vector3(1.2, 0.15, -1.0), Vector3(1.05, 0.38, -1.0)]:
				p.append(_p("sphere", "iron", Vector3(0.3, 0.3, 0), b))
		"watchtower":
			p.append(_p("box", "stone_block", Vector3(3.6, 1.8, 3.6), Vector3(0, -0.6, 0)))
			p.append(_p("box", "stone_block", Vector3(3.2, 6.0, 3.2), Vector3(0, 3.3, 0)))
			p.append(_p("box", "plank", Vector3(4.2, 0.3, 4.2), Vector3(0, 6.45, 0)))
			for x in [-1.9, 1.9]:
				for z in [-1.9, 1.9]:
					p.append(_p("cyl", "log", Vector3(0.22, 2.2, 0.2), Vector3(x, 7.7, z)))
			for z in [-2.0, 2.0]:
				p.append(_p("box", "plank", Vector3(4.0, 0.6, 0.1), Vector3(0, 6.9, z)))
			for x in [-2.0, 2.0]:
				p.append(_p("box", "plank", Vector3(0.1, 0.6, 4.0), Vector3(x, 6.9, 0)))
			p.append(_p("cone", "plank_dark", Vector3(6.0, 2.0, 0), Vector3(0, 9.7, 0), Vector3(0, 45, 0), {"seg": 4}))
			p.append(_p("box", "plank_dark", Vector3(1.0, 1.9, 0.1), Vector3(0, 1.25, 1.62)))
			p.append(_p("box", "plank_dark", Vector3(0.4, 0.8, 0.08), Vector3(0, 4.0, 1.62)))
		"palisade":
			p.append(_p("cyl", "log", Vector3(0.18, 3.8, 0.18), Vector3(0, 1.0, -0.22), Vector3(0, 0, 90)))
			for i in 5:
				var x := -1.6 + i * 0.8
				p.append(_p("cyl", "log", Vector3(0.38, 2.4, 0.38), Vector3(x, 0.7, 0)))
				p.append(_p("cone", "log", Vector3(0.38, 0.5, 0), Vector3(x, 2.15, 0)))
		_:
			push_warning("Нет чертежа здания: %s" % id)
			p.append(_p("box", "plank", Vector3(2, 2, 2), Vector3(0, 1, 0)))
	return p


## Готовые детали: [{"mesh": ArrayMesh, "xform": Transform3D, "mat": String, "group": String}].
static func built_parts(id: String) -> Array:
	if _built.has(id):
		return _built[id]
	var result := []
	for part in parts(id):
		var mat_id: String = part["mat"]
		var kit := MeshKit.new()
		var color: Color = GameData.MATERIALS[mat_id]["color"]
		var size: Vector3 = part["size"]
		var seg: int = part.get("seg", 8)
		var prim: PrimitiveMesh
		match part["shape"]:
			"box":
				prim = MeshKit.box(size)
			"roof":
				prim = MeshKit.prism(size)
			"cyl":
				prim = MeshKit.cylinder(size.x * 0.5, size.z * 0.5, size.y, seg)
			"cone":
				prim = MeshKit.cylinder(size.x * 0.5, 0.0, size.y, seg)
			"sphere":
				prim = MeshKit.sphere(size.x * 0.5, size.y, seg, 4)
		kit.add_primitive(prim, Transform3D.IDENTITY, color)
		result.append({
			"mesh": kit.build(material(mat_id)),
			"xform": MeshKit.at(part["pos"], part["rot"]),
			"mat": mat_id,
			"group": part.get("group", ""),
		})
	# Стройка идёт снизу вверх: сортируем по нижней точке детали.
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _bottom(a) < _bottom(b))
	_built[id] = result
	return result


static func _bottom(part: Dictionary) -> float:
	var box: AABB = part["xform"] * part["mesh"].get_aabb()
	return box.position.y + (100.0 if part["group"] != "" else 0.0)


## Габариты здания (без учёта поворота).
static func bounds(id: String) -> AABB:
	var box := AABB()
	var first := true
	for part in built_parts(id):
		var b: AABB = part["xform"] * part["mesh"].get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func materials_used(id: String) -> Array[String]:
	var result: Array[String] = []
	for part in parts(id):
		if not result.has(part["mat"]):
			result.append(part["mat"])
	return result


static func material(mat_id: String) -> StandardMaterial3D:
	if _materials.has(mat_id):
		return _materials[mat_id]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	match mat_id:
		"glass":
			m.roughness = 0.12
			m.metallic_specular = 0.9
			m.emission_enabled = true
			m.emission = Color(0.45, 0.65, 0.75)
			m.emission_energy_multiplier = 0.35
		"iron":
			m.metallic = 0.55
			m.roughness = 0.45
		"copper":
			m.metallic = 0.35
			m.roughness = 0.5
		"wax":
			m.emission_enabled = true
			m.emission = Color(1.0, 0.8, 0.45)
			m.emission_energy_multiplier = 1.5
	_materials[mat_id] = m
	return m
