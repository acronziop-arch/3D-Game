// Язычок пламени: плоскость, всегда повёрнутая к камере вокруг вертикали.
// Форма — капля, верх «съедается» бегущим вверх шумом, поэтому языки
// рвутся и пляшут. Внутри — почти белое ядро, к краям — оранжевый и красный.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec3 color_core : source_color = vec3(1.0, 0.93, 0.62);
uniform vec3 color_mid : source_color = vec3(1.0, 0.56, 0.12);
uniform vec3 color_edge : source_color = vec3(0.85, 0.18, 0.04);
uniform float seed = 0.0;
uniform float speed = 1.3;
uniform float intensity = 1.0;
// 0 — днём, 1 — ночью (ночью пламя ярче и светится сильнее).
uniform float darkness = 0.0;

void vertex() {
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz));
	vec3 fwd = cross(right, vec3(0.0, 1.0, 0.0));
	mat4 bill = mat4(vec4(right, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
	bill = bill * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bill;
}

void fragment() {
	float y = 1.0 - UV.y;
	float x = UV.x - 0.5;
	float t = TIME * speed;
	float n1 = texture(noise_tex, vec2(UV.x * 0.9 + seed, UV.y * 0.7 + t)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 2.1 - seed * 1.7, UV.y * 1.6 + t * 1.8)).r;
	float n = n1 * 0.62 + n2 * 0.38;
	// Пламя колышется сильнее к верху.
	float wobble = (n1 - 0.5) * 0.42 * y + sin(t * 2.3 + seed * 6.0 + y * 4.0) * 0.03 * y;
	float w = 0.44 * pow(max(1.0 - y, 0.0), 0.6) * smoothstep(-0.05, 0.16, y);
	float d = abs(x + wobble) / max(w, 0.001);
	float body = 1.0 - smoothstep(0.45, 1.0, d);
	// Верх рвётся на языки.
	float tongues = smoothstep(y * 1.25 - 0.12, y * 1.25 + 0.22, n);
	float a = clamp(body * tongues, 0.0, 1.0);
	float heat = clamp(a * (1.35 - y * 0.9) * (1.0 - d * 0.45), 0.0, 1.0);
	vec3 col = mix(color_edge, color_mid, smoothstep(0.1, 0.5, heat));
	col = mix(col, color_core, smoothstep(0.55, 0.95, heat));
	// Пламя рисуется с прозрачностью (а не сложением): так оно видно и днём.
	// Ядро ярче единицы — ночью его подхватывает свечение (glow).
	float k = intensity * mix(1.0, 1.5, darkness);
	ALBEDO = col * k * (0.8 + heat * 0.9);
	ALPHA = clamp(a * (0.55 + heat * 0.7), 0.0, 1.0) * smoothstep(0.02, 0.2, a);
}
