// Деревья, кусты, трава, камни. Читает атрибуты модели:
//   COLOR.a — гибкость (0 у корня, 1 на макушке): насколько гнётся на ветру;
//   UV2.x   — тип: 0 твёрдое (ствол, камень), 1 листва, 2 хвоя, 3 трава;
//   UV2.y   — зерно кучки листвы: по нему листья желтеют и облетают не разом.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, world_vertex_coords;

#include "res://shaders/world.gdshaderinc"

uniform float sway = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying float kind;
varying float seed_v;

void vertex() {
	kind = UV2.x;
	seed_v = UV2.y;
	float flex = COLOR.a;
	vec3 origin = MODEL_MATRIX[3].xyz;
	bool leaf = kind > 0.5 && kind < 1.5;
	// Кувшинки лежат на воде — зимой они уходят под лёд.
	bool floating = abs(origin.y - water_level) < 0.08;
	if ((leaf && seed_v > leaf_amount) || (floating && ice > 0.45)) {
		VERTEX = origin;
	} else {
		float phase = dot(origin.xz, vec2(0.31, 0.17));
		float gust = 0.65 + 0.35 * sin(TIME * 0.55 + phase * 0.2) * sin(TIME * 0.21 + phase * 0.07);
		float s = wind_strength * gust * sway;
		vec2 d = normalize(wind_dir + vec2(0.0001));
		float bend = flex * s * (0.7 + 0.3 * sin(wind_phase * 1.2 + phase));
		VERTEX.xz += d * bend * 0.9;
		VERTEX.y -= bend * bend * 0.12;
		if (kind > 0.5) {
			float t = wind_phase * 3.5;
			VERTEX += vec3(sin(t + VERTEX.x * 2.1 + seed_v * 6.0),
				sin(t * 0.9 + VERTEX.z * 1.7) * 0.5,
				cos(t * 1.1 + VERTEX.y * 2.3)) * 0.03 * (0.2 + s * 1.5) * flex;
		}
	}
	// Пучки травы и папоротники под глубоким снегом уходят под сугроб.
	if (kind > 2.5) {
		VERTEX.y = mix(VERTEX.y, origin.y - 0.12, smoothstep(0.45, 0.85, snow_cover));
	}
	world_pos = VERTEX;
	world_normal = NORMAL;
}

void fragment() {
	if (clip_for_reflection(CAMERA_POSITION_WORLD, world_pos)) {
		discard;
	}
	vec3 c = COLOR.rgb;
	float rough = 0.86;
	if (kind > 0.5 && kind < 1.5) {
		// Листва: осенью каждая кучка желтеет в своё время и в свой цвет.
		vec3 fall = seed_v < 0.33 ? vec3(0.86, 0.42, 0.1) : (seed_v < 0.66 ? vec3(0.93, 0.7, 0.16) : vec3(0.74, 0.2, 0.1));
		float lum = clamp(dot(c, vec3(0.3, 0.59, 0.11)) / 0.42, 0.55, 1.3);
		float turn = smoothstep(seed_v * 0.5, seed_v * 0.5 + 0.45, autumn);
		c = mix(c, fall * lum, turn);
		c = mix(c, c * vec3(0.92, 1.12, 0.82) + vec3(0.02, 0.05, 0.0), spring);
		BACKLIGHT = c * 0.3;
	} else if (kind > 2.5) {
		vec3 dry = vec3(c.g * 0.95, c.g * 0.8, c.b * 0.5);
		c = mix(c, dry, autumn * 0.75);
		BACKLIGHT = c * 0.2;
	}
	c = apply_wet(c, wetness * 0.8, rough);
	float s = snow_mask(world_pos, world_normal, snow_cover * 1.1);
	c = mix(c, SNOW_COLOR, s);
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = night_specular(0.35);
}
