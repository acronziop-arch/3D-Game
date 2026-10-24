// Общие параметры погоды и функции для всех шейдеров мира.
// Значения задаёт Atmosphere (scripts/world/atmosphere.gd) через глобальные
// параметры шейдеров (Project Settings → Shader Globals).

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wetness;
global uniform float snow_cover;
global uniform float leaf_amount;
global uniform float autumn;
global uniform float spring;
global uniform float night;
global uniform float rain;
global uniform float water_level;

const vec3 SNOW_COLOR = vec3(0.92, 0.94, 0.97);

float w_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float w_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(w_hash(i), w_hash(i + vec2(1.0, 0.0)), u.x),
		mix(w_hash(i + vec2(0.0, 1.0)), w_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Снег ложится на верхние грани пятнами и растёт вместе с snow_cover.
float snow_mask(vec3 world_pos, vec3 world_normal, float amount) {
	if (amount <= 0.001) {
		return 0.0;
	}
	float n = w_noise(world_pos.xz * 1.3) * 0.6 + w_noise(world_pos.xz * 0.27 + 3.1) * 0.4;
	float slope = smoothstep(0.25, 0.72, world_normal.y);
	float cover = clamp(amount * 1.25, 0.0, 1.25);
	float above_water = step(water_level + 0.05, world_pos.y);
	return clamp((slope * cover - (1.0 - n) * 0.5) * 3.0, 0.0, 1.0) * above_water;
}

// Мокрая поверхность темнее и глаже.
vec3 apply_wet(vec3 albedo, float wet, inout float roughness) {
	roughness = mix(roughness, 0.22, wet);
	return albedo * mix(1.0, 0.62, wet);
}

// Камера отражений стоит под водой: всё, что ниже воды, ей рисовать не нужно.
bool clip_for_reflection(vec3 camera_pos, vec3 world_pos) {
	return camera_pos.y < water_level - 0.01 && world_pos.y < water_level;
}
