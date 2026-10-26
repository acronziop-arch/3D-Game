// Плавная дорожка, проложенная пальцем или мышью: лента по земле.
// UV — (поперёк, м: от −w/2 до w/2; вдоль, м), UV2 — (сколько до начала, сколько до конца, м).
// Узор рисует шейдер: утоптанная земля, доски, булыжник или кирпич. Концы скруглены.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://shaders/world.gdshaderinc"

// 0 — земля, 1 — доски, 2 — булыжник, 3 — кирпич.
uniform int kind = 0;
uniform float width = 1.6;
uniform float highlight = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = NORMAL;
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// Ячейки: x — до центра ближайшей, y — до границы с соседней, z — оттенок ячейки.
vec3 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 best = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g) * 0.75 + 0.125;
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				best = i + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d1, d2 - d1, w_hash(best));
}

void fragment() {
	if (clip_for_reflection(CAMERA_POSITION_WORLD, world_pos)) {
		discard;
	}
	float across = UV.x;
	float along = UV.y;
	float half_w = width * 0.5;
	// Скруглённые концы: внутри «капсулы» вокруг средней линии.
	float d = abs(across);
	if (UV2.x < half_w) {
		d = length(vec2(across, half_w - UV2.x));
	} else if (UV2.y < half_w) {
		d = length(vec2(across, half_w - UV2.y));
	}
	float wobble = (w_noise(world_pos.xz * 2.6) - 0.5) * (kind == 0 ? 0.26 : 0.05);
	float inside = half_w + wobble - d;
	if (inside < 0.0) {
		discard;
	}
	float rim = 1.0 - smoothstep(0.0, 0.2, inside);
	vec3 c;
	float rough = 0.9;
	if (kind == 0) {
		// Утоптанная земля: пятна, колеи и мелкие камешки; к краю — темнее и зеленее.
		float n = w_noise(world_pos.xz * 2.4) * 0.6 + w_noise(world_pos.xz * 9.0) * 0.4;
		c = vec3(0.57, 0.44, 0.31) * (0.82 + n * 0.32);
		float rt = (abs(across) - width * 0.22) / 0.09;
		float rut = exp(-rt * rt);
		c *= 1.0 - rut * 0.12;
		vec3 pb = cells(world_pos.xz * 6.0);
		if (pb.z > 0.72 && pb.x < 0.18) {
			c = mix(c, vec3(0.68, 0.66, 0.62), smoothstep(0.18, 0.1, pb.x));
		}
		c = mix(c, c * vec3(0.78, 0.86, 0.66), rim * 0.7);
	} else if (kind == 1) {
		// Доски поперёк дорожки, по краям — продольные лаги.
		float plank = floor(along / 0.3);
		float fp = fract(along / 0.3);
		float tint = w_hash(vec2(plank, 3.1));
		c = vec3(0.74, 0.51, 0.3) * (0.82 + tint * 0.28);
		c *= 1.0 + sin(across * 26.0 + w_noise(vec2(across * 3.0, plank)) * 6.0) * 0.035;
		float gap = smoothstep(0.0, 0.06, fp) * smoothstep(1.0, 0.94, fp);
		c *= mix(0.32, 1.0, gap);
		float nail = smoothstep(0.035, 0.02, length(vec2(abs(across) - half_w * 0.72, (fp - 0.5) * 0.3)));
		c = mix(c, vec3(0.2, 0.2, 0.22), nail * 0.8);
		if (abs(across) > half_w - 0.13) {
			c = vec3(0.52, 0.34, 0.2) * (0.9 + w_noise(vec2(along * 2.0, sign(across))) * 0.2);
		}
		rough = 0.8;
	} else if (kind == 2) {
		// Булыжник: округлые камни в земле, по краям — бордюр из камней покрупнее.
		vec3 v = abs(across) > half_w - 0.2 ? cells(vec2(across * 2.0, along * 1.4) + 13.0) : cells(vec2(across, along) * 3.0);
		vec3 stone = mix(vec3(0.5, 0.49, 0.47), vec3(0.68, 0.66, 0.62), v.z);
		stone *= 0.82 + 0.3 * smoothstep(0.55, 0.0, v.x);
		c = mix(vec3(0.33, 0.27, 0.2), stone, smoothstep(0.03, 0.09, v.y));
		rough = 0.75;
	} else {
		// Кирпич: ряды поперёк дорожки со сдвигом, по краям — кирпич на ребро вдоль.
		vec2 b;
		vec2 size;
		if (abs(across) > half_w - 0.15) {
			size = vec2(0.13, 0.26);
			b = vec2(across, along) / size;
		} else {
			size = vec2(0.26, 0.13);
			b = vec2(across, along) / size;
			b.x += 0.5 * mod(floor(b.y), 2.0);
		}
		vec2 f = fract(b);
		vec2 m = min(f, 1.0 - f) * size;
		float mortar = smoothstep(0.006, 0.014, min(m.x, m.y));
		float tint = w_hash(floor(b) + 7.3);
		vec3 brick = vec3(0.68, 0.33, 0.24) * (0.82 + tint * 0.3);
		c = mix(vec3(0.62, 0.58, 0.52), brick, mortar);
		rough = 0.78;
	}
	c = apply_wet(c, wetness * 0.85, rough);
	float s = snow_mask(world_pos, world_normal, snow_cover) * 0.75;
	c = mix(c, SNOW_COLOR, s);
	c = mix(c, vec3(1.0, 0.45, 0.35), highlight * 0.4);
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
