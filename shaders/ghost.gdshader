// Полупрозрачный «чертёж»: превью размещения и ещё не построенные детали.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;

uniform vec4 tint : source_color = vec4(0.6, 0.85, 1.0, 0.22);
instance uniform float build_progress = 0.0;

void vertex() {
	if (COLOR.a < build_progress) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * (0.55 + rim * 0.9);
}
