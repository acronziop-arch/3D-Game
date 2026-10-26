// Густая трава и цветы. Цвет экземпляра — цвет земли под пучком (у цветов — цвет
// лепестков); UV.y — высота по травинке, UV.x = 1 — лепесток.
// Ветер гонит по полю волны, осенью трава желтеет, под снегом прижимается к земле.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx, world_vertex_coords;

#include "res://shaders/world.gdshaderinc"

// Дальше fade_end пучки плавно уходят в землю — граница травы не видна.
uniform float fade_end = 70.0;
// 1 — пучок цветов: стебли зелёные, лепестки цвета экземпляра.
uniform float flower = 0.0;

varying float tip;
varying float petal;
varying vec3 world_pos;

void vertex() {
	tip = UV.y;
	petal = UV.x;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float fade = 1.0 - smoothstep(fade_end * 0.7, fade_end, distance(origin, CAMERA_POSITION_WORLD));
	float squash = clamp(1.0 - snow_cover * 1.4, 0.0, 1.0) * fade;
	// Под снегом пучок не ложится плашмя поверх сугроба, а уходит под него целиком.
	VERTEX.y = mix(origin.y - 0.05, VERTEX.y, squash);
	VERTEX.xz = mix(origin.xz, VERTEX.xz, mix(0.3, 1.0, squash));
	vec2 d = normalize(wind_dir + vec2(0.0001));
	// Волна ветра бежит по полю вдоль направления ветра.
	float wave = sin(dot(origin.xz, d) * 0.18 - wind_phase * 1.2) * 0.5 + 0.5;
	float flutter = sin(wind_phase * 2.5 + origin.x * 1.7 + origin.z * 1.3);
	float bend = tip * tip * (0.08 + wind_strength * (0.25 + wave * 0.45)) * squash;
	VERTEX.xz += d * bend + vec2(-d.y, d.x) * flutter * 0.03 * tip;
	VERTEX.y -= bend * bend * 0.35;
	world_pos = VERTEX;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	if (clip_for_reflection(CAMERA_POSITION_WORLD, world_pos)) {
		discard;
	}
	// Трава сочнее земли под ней: у корней — тень пучка, к кончикам светлее и теплее.
	vec3 g = COLOR.rgb;
	g = mix(vec3(dot(g, vec3(0.3, 0.59, 0.11))), g, 1.35);
	vec3 c = g * mix(0.6, 1.12, tip);
	c = mix(c, c * vec3(1.1, 1.06, 0.74), tip * tip * 0.55);
	if (flower > 0.5) {
		vec3 stem = vec3(0.3, 0.52, 0.2) * mix(0.7, 1.05, tip);
		c = mix(stem, COLOR.rgb, step(0.5, petal));
	}
	vec3 dry = vec3(c.g * 0.95 + c.r * 0.2, c.g * 0.82, c.b * 0.5);
	c = mix(c, dry, autumn * 0.7);
	c = mix(c, c * vec3(0.92, 1.1, 0.86), spring);
	float rough = 0.85;
	c = apply_wet(c, wetness * 0.6, rough);
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = night_specular(0.25);
	BACKLIGHT = c * 0.3;
}
