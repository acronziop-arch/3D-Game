class_name ScreenDrops
extends ColorRect
## Капли дождя и снежинки на «объективе»: в дождь на экране появляются редкие
## капли — они преломляют картинку, иногда сползают вниз и высыхают; в снегопад
## садятся снежинки и тают. Рисуется поверх мира, но под интерфейсом.

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
	for (int layer = 0; layer < 2; layer++) {
		float fl = float(layer);
		vec2 q = base * (3.2 + fl * 2.6) + fl * 17.3;
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		float h = h21(cell + fl * 3.7);
		// Капли: редкие, у каждой своя жизнь — появилась, полежала, сползла, высохла.
		if (h < rain_amount * (0.16 - fl * 0.06)) {
			float life = fract(TIME * (0.05 + h21(cell + 9.1) * 0.06) + h * 11.0);
			vec2 c0 = (vec2(h21(cell + 1.3), h21(cell + 2.7)) - 0.5) * 0.5;
			vec2 c = c0;
			float slides = step(0.55, h21(cell + 4.1));
			c.y += slides * smoothstep(0.35, 1.0, life) * 0.45;
			float r = mix(0.08, 0.16, h21(cell + 5.5)) * (1.0 - life * 0.35);
			vec2 d = (f - c) * vec2(1.0, 0.85 + slides * 0.2 * life);
			// Край капли чуть неровный — не идеальный пузырь.
			float a = atan(d.y, d.x);
			float dist = length(d) * (1.0 + 0.07 * sin(a * 3.0 + h * 40.0) + 0.04 * sin(a * 5.0 + h * 13.0));
			float fade = (1.0 - smoothstep(0.75, 1.0, life)) * smoothstep(0.0, 0.04, life);
			float m = smoothstep(r, r * 0.8, dist) * fade;
			// Капля — линза: картинка в ней перевёрнута, сжата и чуть размыта.
			offset += -d / (3.2 + fl * 2.6) * 1.3 * m;
			wet = max(wet, m);
			rim = max(rim, smoothstep(r * 0.62, r * 0.96, dist) * m);
			// Светлый серп снизу и маленький блик сверху — как у настоящей капли на стекле.
			shine += smoothstep(r * 0.16, 0.0, length(d - vec2(-0.3, -0.42) * r)) * m * 0.7;
			shine += smoothstep(r * 0.55, r * 0.92, dist) * clamp(d.y / r, 0.0, 1.0) * m * 0.18;
			// Сползшая капля оставляет за собой мокрый след.
			float trail = slides * smoothstep(r * 0.45, r * 0.1, abs(f.x - c.x)) * step(c0.y, f.y) * step(f.y, c.y - r * 0.5);
			trails = max(trails, trail * fade * 0.8);
		}
		// Снежинки: садятся, белеют и тают.
		if (h > 1.0 - snow_amount * (0.3 - fl * 0.1)) {
			float life = fract(TIME * (0.08 + h21(cell + 7.3) * 0.05) + h * 5.0);
			vec2 c = (vec2(h21(cell + 6.1), h21(cell + 8.9)) - 0.5) * 0.6;
			vec2 d = f - c;
			float a = atan(d.y, d.x);
			float arms = 0.75 + 0.25 * cos(a * 6.0);
			float r = mix(0.05, 0.11, h21(cell + 3.3)) * (1.0 - life * 0.6);
			float m = smoothstep(r * arms, r * arms * 0.4, length(d)) * (1.0 - smoothstep(0.55, 1.0, life));
			flakes = max(flakes, m);
		}
	}
	vec3 col = textureLod(screen_tex, uv + offset, 1.0 + wet * 0.8 + trails * 1.2).rgb;
	col = col * (1.0 - rim * 0.16) * (1.0 + wet * 0.04) + vec3(shine * 0.5);
	col = mix(col, vec3(0.96, 0.97, 1.0), flakes * 0.85);
	COLOR = vec4(col, max(max(wet, trails * 0.6), flakes * 0.9));
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
