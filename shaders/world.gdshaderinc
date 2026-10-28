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
// Текстуры: 0 — «мультик» (мягкие пятна цвета), 1 — «реализм» (волокна, кора, зерно камня,
// листочки и рельеф на свету). Задаёт настройка «Текстуры» (main.gd).
global uniform float texture_detail;

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

// --- Текстуры поверхностей ---------------------------------------------------------------
// Узоры считаются по точке на поверхности (м), без картинок: дерево, кора, камень, листва.
// detail — сила мелких подробностей (texture_detail, гаснет вдали, чтобы не рябило);
// h — высота мелкого рельефа, по ней w_bump наклоняет нормаль.

float w_hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float w_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(w_hash3(i), w_hash3(i + vec3(1.0, 0.0, 0.0)), u.x),
		mix(w_hash3(i + vec3(0.0, 1.0, 0.0)), w_hash3(i + vec3(1.0, 1.0, 0.0)), u.x), u.y);
	float b = mix(mix(w_hash3(i + vec3(0.0, 0.0, 1.0)), w_hash3(i + vec3(1.0, 0.0, 1.0)), u.x),
		mix(w_hash3(i + vec3(0.0, 1.0, 1.0)), w_hash3(i + vec3(1.0, 1.0, 1.0)), u.x), u.y);
	return mix(a, b, u.z);
}

float w_fbm3(vec3 p) {
	return (w_noise3(p) * 0.57 + w_noise3(p * 2.03 + 1.7) * 0.29 + w_noise3(p * 4.11 + 3.1) * 0.14);
}

// Ячейки (шум Ворли) на плоскости: x — расстояние до центра ближайшей ячейки (у края
// ячейки — около 0.5…0.7), y — случайное число ячейки (у каждого листочка свой оттенок).
vec2 w_cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = vec2(w_hash(i + o), w_hash(i + o + 17.3));
			vec2 r = o + h - f;
			float d = dot(r, r);
			if (d < best) {
				best = d;
				id = h.x;
			}
		}
	}
	return vec2(sqrt(best), id);
}

// Плоскость для узора на грани: та из трёх, к которой грань ближе всего (грани плоские —
// у каждой своя проекция, швы совпадают с рёбрами).
vec2 w_face_uv(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.x > a.y && a.x > a.z) {
		return p.zy;
	}
	return a.y > a.z ? p.xz : p.xy;
}

// Мелкий рельеф: нормаль (в осях камеры) наклоняется по высоте h на экране (Микельсен).
vec3 w_bump(vec3 n, vec3 view_pos, float h, float strength) {
	vec3 dpdx = dFdx(view_pos);
	vec3 dpdy = dFdy(view_pos);
	float dhdx = dFdx(h) * strength;
	float dhdy = dFdy(h) * strength;
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * n - grad);
}

// Дерево: волокна вдоль g (ноль — вдоль грани по горизонтали), годичные полосы поперёк,
// изредка сучки; торцы светлее. n — нормаль грани в тех же осях, что и p.
vec3 w_wood(vec3 c, vec3 p, vec3 g, vec3 n, float detail, inout float rough, out float h) {
	if (dot(g, g) < 0.01) {
		g = abs(n.y) > 0.7 ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), n) + vec3(0.0001));
	}
	vec3 across_dir = normalize(cross(g, n) + vec3(0.0001));
	float along = dot(p, g);
	float across = dot(p, across_dir);
	float end_grain = smoothstep(0.75, 0.95, abs(dot(g, n)));
	float warp = w_noise(vec2(along * 0.45, across * 2.5)) * 2.0;
	// «Мультик»: мягкие продольные полосы.
	float soft = w_noise(vec2(along * 0.6, across * 5.0 + warp));
	vec3 col = c * (0.93 + 0.13 * soft);
	h = 0.0;
	if (detail > 0.01) {
		float fibers = w_noise(vec2(along * 1.6, across * 46.0 + warp * 4.0));
		float rings = 0.5 + 0.5 * sin(across * 26.0 + warp * 5.0 + w_noise(vec2(along * 3.0, across * 9.0)) * 2.0);
		float lines = smoothstep(0.78, 1.0, rings);
		// Сучок: тёмное пятнышко с кольцами вокруг.
		vec2 kp = vec2(along * 1.3, across * 3.2);
		vec2 kc = floor(kp);
		vec2 ko = kc + vec2(w_hash(kc), w_hash(kc + 4.1)) * 0.6 + 0.2;
		float kd = length((kp - ko) * vec2(1.0, 0.55));
		float knot = smoothstep(0.11, 0.03, kd) * step(0.93, w_hash(kc + 9.7));
		float real = (0.84 + 0.22 * fibers) * (1.0 - lines * 0.14) * (1.0 - knot * 0.3);
		// Торец — пиленое дерево: светлее, с мелкими кольцами.
		float cut = 1.08 + 0.08 * sin(length(p.xz) * 40.0 + warp * 3.0);
		real = mix(real, cut, end_grain);
		col = mix(col, c * real, detail);
		rough = mix(rough, rough + (fibers - 0.5) * 0.12 + lines * 0.06, detail);
		h = (fibers * 0.6 - lines * 0.5 - knot) * (1.0 - end_grain);
	}
	return col;
}

// Кора: продольные борозды и пластинки вдоль ствола (ось — вверх).
vec3 w_bark(vec3 c, vec3 p, vec3 n, float detail, inout float rough, out float h) {
	vec3 across_dir = normalize(cross(vec3(0.0, 1.0, 0.0), n) + vec3(0.0001));
	float across = dot(p, across_dir);
	float furrows = w_noise(vec2(across * 7.0, p.y * 1.1));
	vec3 col = c * (0.9 + 0.16 * smoothstep(0.25, 0.75, furrows));
	h = 0.0;
	if (detail > 0.01) {
		float plates = w_noise(vec2(across * 4.0 + 3.0, p.y * 3.2));
		float fine = w_noise(vec2(across * 30.0, p.y * 6.0));
		float deep = smoothstep(0.5, 0.18, furrows);
		float real = mix(1.06, 0.58, deep) * (0.88 + 0.2 * plates) * (0.92 + 0.14 * fine);
		// Мох и лишайник с северо-западной стороны.
		float moss = smoothstep(0.55, 0.85, w_noise(vec2(across * 2.0, p.y * 1.5) + 7.0)) * smoothstep(0.2, -0.6, n.x + n.z * 0.6);
		vec3 tinted = mix(c * real, vec3(0.32, 0.4, 0.18) * real, moss * 0.55);
		col = mix(col, tinted, detail);
		rough = mix(rough, 0.95, detail * deep);
		h = furrows * 0.8 + plates * 0.3 + fine * 0.15;
	}
	return col;
}

// Камень: пятна, зерно, вкрапления и тонкие трещины; на верхних гранях — лишайник.
vec3 w_stone(vec3 c, vec3 p, vec3 n, float detail, inout float rough, out float h) {
	float mottle = w_fbm3(p * 1.3);
	vec3 col = c * (0.9 + 0.2 * mottle);
	h = 0.0;
	if (detail > 0.01) {
		float grain = w_noise3(p * 16.0);
		float speck = smoothstep(0.78, 0.86, w_noise3(p * 41.0 + 2.0));
		float ridge = 1.0 - abs(w_noise3(p * 1.9 + mottle * 1.2) * 2.0 - 1.0);
		float crack = smoothstep(0.972, 0.996, ridge) * 0.55;
		vec3 tint = mix(vec3(0.96, 1.0, 1.04), vec3(1.05, 1.0, 0.93), w_noise3(p * 0.7 + 5.0));
		vec3 real = c * tint * (0.82 + 0.3 * mottle) * (0.9 + 0.2 * grain) * (1.0 - crack * 0.45) + vec3(speck * 0.05);
		float lichen = smoothstep(0.62, 0.8, w_fbm3(p * 0.9 + 11.0)) * smoothstep(0.35, 0.85, n.y);
		real = mix(real, vec3(0.5, 0.55, 0.32) * (0.8 + 0.3 * grain), lichen * 0.5);
		col = mix(col, real, detail);
		rough = mix(rough, rough + (grain - 0.5) * 0.18, detail);
		h = mottle * 0.5 + grain * 0.35 - crack * 0.6;
	}
	return col;
}

// Обожжённая глина (кирпич, черепица): мелкая пористость и неровный обжиг.
vec3 w_clay(vec3 c, vec3 p, float detail, inout float rough, out float h) {
	float burn = w_fbm3(p * 2.2);
	vec3 col = c * (0.93 + 0.14 * burn);
	h = 0.0;
	if (detail > 0.01) {
		float pores = w_noise3(p * 34.0);
		col = mix(col, c * (0.84 + 0.26 * burn) * (0.93 + 0.12 * pores), detail);
		h = pores * 0.4 + burn * 0.3;
	}
	return col;
}

// Листва и хвоя: пучки темнее внутри кроны и светлее сверху; на «реализме» листва —
// мелкие листочки-ячейки (у каждого свой оттенок, между ними тени), хвоя — штрихи иголок.
vec3 w_leaves(vec3 c, vec3 p, vec3 n, float needle, float detail, out float h) {
	float clumps = w_fbm3(p * 1.6);
	float top = smoothstep(-0.4, 0.9, n.y);
	vec3 col = c * (0.88 + 0.16 * clumps) * mix(0.92, 1.07, top);
	h = 0.0;
	if (detail > 0.01) {
		vec3 real;
		if (needle > 0.5) {
			// Иголки: тонкие штрихи сверху вниз, кое-где светлые кончики.
			vec3 across_dir = normalize(cross(vec3(0.0, 1.0, 0.0), n) + vec3(0.0001));
			float u = dot(p, across_dir);
			float strokes = w_noise(vec2(u * 34.0, p.y * 5.0 + w_noise(vec2(u * 3.0, p.y)) * 2.0));
			float tips = smoothstep(0.75, 0.95, w_noise(vec2(u * 20.0, p.y * 9.0)));
			real = c * (0.8 + 0.3 * strokes) * (0.86 + 0.24 * clumps) * mix(0.86, 1.1, top) + vec3(0.04, 0.06, 0.02) * tips;
			h = strokes * 0.7 + clumps * 0.3;
		} else {
			vec2 cell = w_cells(w_face_uv(p, n) * 12.0 + vec2(w_noise3(p * 3.0)) * 0.5);
			float edge = smoothstep(0.4, 0.8, cell.x);
			vec3 hue = mix(vec3(0.95, 1.0, 0.9), vec3(1.07, 1.05, 0.86), cell.y);
			real = c * hue * (0.84 + 0.26 * clumps) * mix(0.88, 1.1, top) * (1.0 - edge * 0.2) * (1.0 + (1.0 - cell.x) * 0.06);
			h = (1.0 - edge) * 0.6 + clumps * 0.3;
		}
		col = mix(col, real, detail);
	}
	return col;
}
