class_name WorldWipe
extends CanvasLayer
## Смена времени суток, сезона или погоды из настроек: по экрану из левого
## верхнего угла в правый нижний проходит косая чёрная полоса, и за ней мир уже
## другой. Под полосой — снимок экрана «до», поэтому ничего не проматывается.

const DURATION := 1.1

var _rect: TextureRect
var _material: ShaderMaterial
var _tween: Tween


func _init() -> void:
	layer = 120
	_rect = TextureRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float progress = 0.0;
uniform float aspect = 1.78;

void fragment() {
	// 0 — левый верхний угол, 1 — правый нижний; линия под 45° в пикселях.
	float d = (UV.x * aspect + UV.y) / (aspect + 1.0);
	float band = 0.09;
	float edge = mix(-band * 1.6, 1.0 + band * 1.6, progress);
	float x = d - edge;
	vec4 old = texture(TEXTURE, UV);
	// Впереди полосы — снимок «до», на полосе — чёрный, позади — уже новый мир.
	float black = smoothstep(band, band * 0.35, abs(x));
	float keep_old = smoothstep(-band * 0.2, band * 0.6, x);
	COLOR = vec4(mix(old.rgb, vec3(0.02, 0.018, 0.016), black), max(keep_old, black));
}
"""
	_material = ShaderMaterial.new()
	_material.shader = shader
	_rect.material = _material
	add_child(_rect)


func is_playing() -> bool:
	return _rect.visible


## Снимает экран, вызывает apply (мир меняется сразу) и проводит полосу.
func play(apply: Callable) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		apply.call()
		return
	if _tween:
		_tween.kill()
	_rect.texture = ImageTexture.create_from_image(img)
	var size := Vector2(img.get_size())
	_material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	_material.set_shader_parameter("progress", 0.0)
	_rect.visible = true
	apply.call()
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void: _material.set_shader_parameter("progress", v), 0.0, 1.0, DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func() -> void:
		_rect.visible = false
		_rect.texture = null)
