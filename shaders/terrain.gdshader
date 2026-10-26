// Рельеф: цвет из вершин, сезонный оттенок травы, влага с лужами, снег.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/world.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = NORMAL;
}

void fragment() {
	if (clip_for_reflection(CAMERA_POSITION_WORLD, world_pos)) {
		discard;
	}
	vec3 c = COLOR.rgb;
	float green = clamp((c.g - max(c.r, c.b)) * 5.0, 0.0, 1.0);
	// Мягкие пятна оттенков: крупные (десятки метров) и мелкие — земля не выглядит пластиковой.
	float macro = w_noise(world_pos.xz * 0.045) * 0.6 + w_noise(world_pos.xz * 0.13 + 7.0) * 0.4;
	float micro = w_noise(world_pos.xz * 0.9);
	c *= 0.91 + macro * 0.15 + micro * 0.05;
	c = mix(c, c * vec3(1.06, 1.0, 0.82), green * smoothstep(0.55, 0.8, macro) * 0.5);
	vec3 golden = vec3(c.g * 0.95 + c.r * 0.3, c.g * 0.82, c.b * 0.55);
	c = mix(c, golden, autumn * green * 0.8);
	c = mix(c, c * vec3(0.9, 1.1, 0.88), spring * green);
	float rough = 0.93;
	float land = smoothstep(water_level + 0.05, water_level + 0.5, world_pos.y);
	// Лужи — в низинах ровной земли: мягкие пятна неправильной формы, которые
	// растут, пока идёт дождь, и сохнут потом. Края плавные, без обрезов.
	vec2 q = world_pos.xz * 0.16;
	q += vec2(w_noise(q * 1.7 + 3.0), w_noise(q * 1.7 - 5.0)) * 0.9;
	float basin = w_noise(q) * 0.7 + w_noise(q * 2.3 + 11.0) * 0.3;
	float flat_ground = smoothstep(0.9, 0.985, world_normal.y);
	float level = 0.74 - wetness * 0.12;
	float puddle = smoothstep(level, level + 0.05, basin) * flat_ground * land * smoothstep(0.25, 0.7, wetness);
	// Вокруг лужи земля темнее — мокрая кайма.
	float rim = smoothstep(level - 0.08, level, basin) * flat_ground * land * wetness;
	c = apply_wet(c, clamp(wetness * land * 0.8 + rim * 0.3, 0.0, 1.0), rough);
	c = mix(c, c * 0.5 + vec3(0.02, 0.025, 0.03), puddle * 0.85);
	rough = mix(rough, 0.04, puddle);
	if (puddle > 0.01 && rain > 0.01) {
		vec2 sl = (rain_drops(world_pos.xz * 2.2, TIME) + rain_drops(world_pos.xz * 2.2 + 9.7, TIME * 1.1 + 0.5)) * rain * puddle * 0.35;
		vec3 nw = normalize(vec3(-sl.x, 1.0, -sl.y));
		NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(nw, 0.0)).xyz, puddle));
	}
	float s = snow_mask(world_pos, world_normal, snow_cover);
	c = mix(c, SNOW_COLOR, s);
	rough = mix(rough, 0.62, s);
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = night_specular(0.3 + puddle * 0.45);
}
