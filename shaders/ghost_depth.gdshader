// Первый проход чертежа: только глубина, без цвета. Второй (ghost.gdshader)
// рисует лишь ближние к камере грани — внутренние стены и балки не просвечивают.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always, blend_mix;

uniform float build_progress = 0.0;

void vertex() {
	if (COLOR.a < build_progress) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
