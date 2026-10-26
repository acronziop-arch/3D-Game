// Кольцо-«стакан» вокруг цели: яркое у земли и тающее кверху — его видно
// даже в траве и издалека. Рисуется поверх воды и призраков.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

#include "res://shaders/world.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.95, 0.7, 0.85);
uniform float band_height = 0.5;

varying float rise;

void vertex() {
	rise = clamp(VERTEX.y / band_height + 0.5, 0.0, 1.0);
}

void fragment() {
	// Ночью кольцо приглушено, чтобы не светилось, как лампа.
	ALBEDO = color.rgb * mix(1.0, 0.55, night);
	ALPHA = color.a * pow(1.0 - rise, 1.6);
}
