class_name ScreenDrops
extends ColorRect
## Капли дождя и снежинки на «объективе»: в дождь на экране собираются капли —
## больше по краям, меньше в середине; они преломляют картинку, иногда сползают
## вниз и быстро высыхают. В снегопад так же садятся и тают снежинки.
## Рисуется поверх мира, но под интерфейсом.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float rain_amount = 0.0;
uniform float snow_amount = 0.0;
uniform float aspect = 1.78;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 base = vec2(uv.x * aspect, uv.y);
	vec2 offset = vec2(0.0);
	float wet = 0.0;
	float shine = 0.0;
	float rim = 0.0;
	float flakes = 0.0;
	float trails = 0.0;
	// По краям экрана капель и снежинок больше, в середине — меньше, но тоже есть.
	float side = smoothstep(0.18, 0.48, abs(uv.x - 0.5)) + smoothstep(0.3, 0.5, abs(uv.y - 0.5)) * 0.5;
	float crowd = mix(0.55, 1.9, clamp(side, 0.0, 1.0));
	for (int layer = 0; layer < 3; layer++) {
		float fl = float(layer);
		float scale = 3.0 + fl * 2.4;
		vec2 q = base * scale + fl * 17.3;
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		float h = h21(cell + fl * 3.7);
		// Капли: у каждой своя короткая жизнь — быстро садится, лежит, иногда сползает и высыхает.
		if (h < rain_amount * (0.3 - fl * 0.08) * crowd) {
			float life = fract(TIME * (0.11 + h21(cell + 9.1) * 0.12) + h * 11.0);
			vec2 c0 = (vec2(h21(cell + 1.3), h21(cell + 2.7)) - 0.5) * 0.5;
			vec2 c = c0;
			float slides = step(0.5, h21(cell + 4.1));
			c.y += slides * smoothstep(0.3, 1.0, life) * 0.5;
			float r = mix(0.11, 0.22, h21(cell + 5.5)) * (1.0 - life * 0.3);
			vec2 d = (f - c) * vec2(1.0, 0.85 + slides * 0.25 * life);
			// Край капли чуть неровный — не идеальный пузырь.
			float a = atan(d.y, d.x);
			float dist = length(d) * (1.0 + 0.07 * sin(a * 3.0 + h * 40.0) + 0.04 * sin(a * 5.0 + h * 13.0));
			float fade = (1.0 - smoothstep(0.82, 1.0, life)) * smoothstep(0.0, 0.015, life);
			float m = smoothstep(r, r * 0.78, dist) * fade;
			// Капля — линза: картинка в ней перевёрнута, сжата и чуть размыта.
			offset += -d / scale * 1.9 * m;
			wet = max(wet, m);
			rim = max(rim, smoothstep(r * 0.55, r * 0.95, dist) * m);
			// Блик сверху и светлый серп снизу — как у настоящей капли на стекле.
			shine += smoothstep(r * 0.2, 0.0, length(d - vec2(-0.3, -0.42) * r)) * m;
			shine += smoothstep(r * 0.55, r * 0.92, dist) * clamp(d.y / r, 0.0, 1.0) * m * 0.3;
			// Сползшая капля оставляет за собой мокрый след.
			float trail = slides * smoothstep(r * 0.45, r * 0.1, abs(f.x - c.x)) * step(c0.y, f.y) * step(f.y, c.y - r * 0.5);
			trails = max(trails, trail * fade * 0.9);
		}
		// Снежинки: быстро садятся, белеют и тают.
		if (h > 1.0 - snow_amount * (0.45 - fl * 0.1) * crowd) {
			float life = fract(TIME * (0.16 + h21(cell + 7.3) * 0.1) + h * 5.0);
			vec2 c = (vec2(h21(cell + 6.1), h21(cell + 8.9)) - 0.5) * 0.6;
			vec2 d = f - c;
			float a = atan(d.y, d.x);
			float arms = 0.72 + 0.28 * cos(a * 6.0);
			float r = mix(0.07, 0.15, h21(cell + 3.3)) * (1.0 - life * 0.5);
			float m = smoothstep(r * arms, r * arms * 0.35, length(d)) * (1.0 - smoothstep(0.6, 1.0, life)) * smoothstep(0.0, 0.03, life);
			flakes = max(flakes, m);
		}
	}
	vec3 col = textureLod(screen_tex, uv + offset, 1.0 + wet * 0.8 + trails * 1.2).rgb;
	col = col * (1.0 - rim * 0.3) * (1.0 + wet * 0.06) + vec3(shine * 0.6);
	col = mix(col, vec3(0.97, 0.98, 1.0), flakes * 0.92);
	COLOR = vec4(col, max(max(wet, trails * 0.7), flakes * 0.95));
}
"""

var _material: ShaderMaterial


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	material = _material
	visible = false


func _process(_delta: float) -> void:
	var rain := clampf(Weather.rain, 0.0, 1.0)
	var snow := clampf(Weather.snow, 0.0, 1.0)
	visible = rain > 0.05 or snow > 0.05
	if not visible:
		return
	var screen := get_viewport_rect().size
	_material.set_shader_parameter("aspect", screen.x / maxf(screen.y, 1.0))
	_material.set_shader_parameter("rain_amount", rain)
	_material.set_shader_parameter("snow_amount", snow)
