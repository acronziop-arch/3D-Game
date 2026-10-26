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
// Мороз: зима и снег. Стёкла покрываются изморозью.
global uniform float frost;
// 1 — за окнами видны комнаты (высокое качество графики), 0 — простое стекло.
global uniform float interiors;
// Лёд на озёрах (0..1): копится зимой и сходит весной.
global uniform float ice;
// Сила снегопада прямо сейчас.
global uniform float snowfall;
// Фаза покачивания на ветру: растёт тем быстрее, чем сильнее ветер. Смена ветра
// меняет скорость, а не перескакивает фазу — поэтому ничего не «проматывается».
global uniform float wind_phase;
// Сколько ветер унёс рябь на воде, м (копится по направлению ветра).
global uniform vec2 wind_drift;

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

// Круги от капель дождя (наклон поверхности): в каждой клетке своя капля со своим временем.
vec2 rain_drops(vec2 p, float t) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = w_hash(cell);
	float life = fract(t * 1.2 + h);
	vec2 center = (vec2(w_hash(cell + 3.1), w_hash(cell + 7.7)) - 0.5) * 0.6;
	vec2 d = f - center;
	float r = length(d);
	float radius = life * 0.45;
	float ring = sin((r - radius) * 55.0) * smoothstep(0.08, 0.0, abs(r - radius)) * (1.0 - life);
	return d / max(r, 0.001) * ring;
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

// Блеск поверхности ночью почти пропадает: иначе крутые склоны у воды под косым
// взглядом отражают ночное небо и светятся сиреневыми пятнами, как фонари.
float night_specular(float s) {
	return s * mix(1.0, 0.12, night);
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
