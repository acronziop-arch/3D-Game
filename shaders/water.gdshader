// Low-poly вода: лёгкие волны в вершинах и плоские (гранёные) нормали.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.27, 0.62, 0.78, 0.78);
uniform vec4 crest_color : source_color = vec4(0.62, 0.86, 0.93, 0.85);
uniform float wave_height = 0.14;
uniform float wave_speed = 0.7;

varying float wave;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wave = sin(world.x * 0.33 + TIME * wave_speed) * cos(world.z * 0.27 + TIME * wave_speed * 0.8)
		+ 0.5 * sin((world.x + world.z) * 0.6 - TIME * wave_speed * 1.3);
	VERTEX.y += wave * wave_height;
}

void fragment() {
	// Нормаль грани по производным позиции, развёрнутая к камере.
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	float fresnel = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
	vec4 c = mix(water_color, crest_color, clamp(wave * 0.35 + 0.35, 0.0, 1.0) * 0.5);
	ALBEDO = c.rgb;
	ALPHA = clamp(c.a + fresnel * 0.2, 0.0, 0.95);
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
}
