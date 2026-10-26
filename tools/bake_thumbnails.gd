extends SceneTree
## Снимает миниатюры всех зданий для меню стройки в assets/thumbs/<id>.png.
## Нужна видеокарта (не --headless). Запуск из папки проекта:
##   godot --path . --script res://tools/bake_thumbnails.gd
## После смены моделей (tools/export_models.gd) — запустить ещё раз.

const GD := preload("res://scripts/autoload/game_data.gd")
const OUT := "res://assets/thumbs/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var thumbs := Thumbnails.new()
	thumbs.size = Vector2i(288, 216)
	root.add_child(thumbs)
	var left := {"n": GD.BUILDINGS.size()}
	thumbs.thumbnail_ready.connect(func(id: String, tex: Texture2D) -> void:
		var img := tex.get_image()
		img.save_png(OUT + id + ".png")
		print("%-18s %s" % [id, img.get_size()])
		left["n"] -= 1
		if left["n"] <= 0:
			quit())
	thumbs.request.call_deferred(GD.BUILDINGS.keys(), true)
