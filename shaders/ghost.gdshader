// Полупрозрачный «чертёж»: превью размещения и ещё не построенные детали.
// highlight = 1 — двери и окна: они светлее и теплее, чтобы сразу было видно фасад.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;

uniform vec4 tint : source_color = vec4(0.6, 0.85, 1.0, 0.22);
uniform float highlight = 0.0;
uniform float build_progress = 0.0;

void vertex() {
	if (COLOR.a < build_progress) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 col = mix(tint.rgb, vec3(1.0, 0.93, 0.62), highlight * 0.85);
	ALBEDO = col;
	ALPHA = clamp(tint.a * (0.55 + rim * 0.9) + highlight * 0.22, 0.0, 1.0);
}
