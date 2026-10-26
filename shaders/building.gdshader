// Здания. COLOR.a — этап стройки детали (0 — фундамент, 1 — последняя деталь).
// build_progress собирает дом: детали по очереди падают сверху на своё место
// с лёгким отскоком и тёплой вспышкой. У строящегося здания свои копии
// материалов (у общих build_progress = 1), поэтому стройка видна и в браузере.
// Стекло (glass = 1): небо и блик солнца в окне, капли в дождь, изморозь зимой.
// Во время дождя по стенам сбегают струйки воды.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

#include "res://shaders/world.gdshaderinc"

uniform float roughness_base = 0.85;
uniform float metallic_base = 0.0;
uniform float specular_base = 0.5;
uniform float porosity = 1.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_day = 0.0;
uniform float emission_night = 0.0;
uniform float flutter = 0.0;
uniform float glass = 0.0;
uniform float build_progress = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying float landing;

void vertex() {
	landing = 0.0;
	if (build_progress < 0.999) {
		float t = clamp((build_progress - COLOR.a) * 12.0, 0.0, 1.0);
		if (t <= 0.0) {
			VERTEX = vec3(0.0);
		} else {
			// Падение с отскоком (easeOutBack): деталь чуть проседает и встаёт на место.
			float k = t - 1.0;
			float e = 1.0 + 2.70158 * k * k * k + 1.70158 * k * k;
			VERTEX.y += (1.0 - e) * 1.8;
			landing = 1.0 - t;
		}
	}
	if (flutter > 0.0) {
		float t = wind_phase * 4.0;
		VERTEX += NORMAL * sin(t + VERTEX.x * 2.3 + VERTEX.y * 1.7 + VERTEX.z * 1.9) * 0.035 * (0.2 + wind_strength) * flutter;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Капли на стекле: одни висят бусинами, другие сбегают вниз по своим дорожкам.
float glass_drops(vec2 plane, out vec2 spark) {
	vec2 q = plane * vec2(13.0, 8.0);
	float lane = w_hash(vec2(floor(q.x), 1.3));
	q.y += step(0.72, lane) * TIME * (0.5 + lane * 0.8);
	vec2 cell = floor(q);
	vec2 f = fract(q) - 0.5;
	float h = w_hash(cell);
	vec2 off = (vec2(w_hash(cell + 3.1), w_hash(cell + 5.7)) - 0.5) * 0.5;
	float d = length((f - off) * vec2(1.0, 0.8));
	spark = f - off + vec2(0.06, -0.07);
	return smoothstep(0.08 + h * 0.2, 0.03, d) * step(0.4, h);
}

void fragment() {
	if (clip_for_reflection(CAMERA_POSITION_WORLD, world_pos)) {
		discard;
	}
	vec3 c = COLOR.rgb;
	// Чуть насыщеннее — домики выглядят «игрушечными», но без перебора.
	c = mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, 1.15);
	float rough = roughness_base;
	float spec = specular_base;
	vec3 emit = emission_color * (emission_day + emission_night * night);
	vec3 n = normalize(world_normal);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), n) + vec3(0.0001, 0.0, 0.0001));
	vec2 plane = vec2(dot(world_pos, side), world_pos.y);
	float wet_k = porosity;

	if (glass > 0.5) {
		// Небо в стекле: светлее к горизонту, ночью тёмно-синее.
		vec3 r = reflect(-v, n);
		float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.5);
		vec3 sky_day = mix(vec3(0.8, 0.87, 0.93), vec3(0.4, 0.58, 0.86), clamp(r.y * 1.4, 0.0, 1.0));
		vec3 sky = mix(sky_day, vec3(0.05, 0.08, 0.16), night);
		// Полоса блика скользит по стеклу, когда камера движется.
		float band = dot(plane, vec2(0.7, 0.55)) * 1.7 + dot(v, side) * 2.4;
		float gleam = smoothstep(0.86, 1.0, sin(band)) * (1.0 - night * 0.75);
		c = mix(c * 0.5, sky, 0.38 + fres * 0.5) + vec3(gleam) * 0.5;
		rough = 0.04;
		spec = 1.0;
		float wet_glass = max(rain, wetness * 0.5);
		if (wet_glass > 0.01) {
			vec2 spark;
			float drop = glass_drops(plane, spark) * wet_glass;
			c = mix(c, c * 0.55 + sky * 0.2, drop);
			c += vec3(smoothstep(0.06, 0.0, length(spark))) * drop * 0.7;
		}
		// Изморозь зимой: перистый узор растёт от рам к середине стёкол (снизу —
		// раньше), середина остаётся прозрачной; стекло слегка запотевает.
		if (frost > 0.01) {
			float pattern = w_noise(plane * 9.0) * 0.6 + w_noise(plane * 24.0) * 0.4;
			float m;
			if (UV2.x > 0.0001 || UV2.y > 0.0001) {
				// Окно с крестом рамы — четыре стекла, у каждого свои края.
				vec2 sp = fract(clamp(UV2, 0.0, 1.0) * 2.0);
				float edge = min(min(sp.x, 1.0 - sp.x), 1.0 - sp.y);
				edge = min(edge, sp.y * 0.55) * 0.5;
				float reach = frost * 0.13 + (pattern - 0.5) * 0.09;
				m = smoothstep(reach, reach - 0.05, edge);
				// Кристаллы-«перья» на кромке узора.
				float fern = smoothstep(0.62, 0.95, w_noise(plane * vec2(46.0, 17.0) + pattern * 4.0));
				m = max(m, fern * smoothstep(reach + 0.08, reach, edge));
				m = clamp(m * min(frost * 1.6, 1.0), 0.0, 0.94) + frost * 0.12;
			} else {
				m = clamp(smoothstep(0.78, 0.2, pattern - frost * 0.5) * frost * 1.3, 0.0, 0.85);
			}
			// Чистая середина стекла темнее (за ней комната), изморозь — белая и зернистая.
			vec3 frost_col = vec3(0.93, 0.96, 1.0) * (0.84 + 0.16 * w_noise(plane * vec2(52.0, 21.0)));
			c = mix(c * (1.0 - frost * 0.22), frost_col, m);
			c += vec3(smoothstep(0.9, 1.0, w_noise(plane * 70.0))) * m * 0.3 * (1.0 - night);
			rough = mix(rough, 0.55, m);
			emit *= 1.0 - m * 0.4;
		}
		wet_k = 0.0;
	} else if (porosity > 0.0) {
		// Струйки дождя на стенах: тёмные мокрые дорожки и бегущие по ним капли.
		float vertical = 1.0 - smoothstep(0.35, 0.65, abs(n.y));
		float flow = max(rain, wetness * 0.45) * vertical;
		if (flow > 0.01) {
			float u = plane.x * 6.0;
			float h = w_hash(vec2(floor(u), 9.1));
			float line = (1.0 - smoothstep(0.04, 0.15, abs(fract(u) - 0.5))) * step(0.5, h);
			float runs = smoothstep(0.82, 1.0, fract(plane.y * 0.9 + TIME * (0.35 + h * 0.6) + h * 13.0));
			float streak = clamp(line * (0.45 + runs) * flow, 0.0, 1.0);
			c *= 1.0 - streak * 0.3;
			rough = mix(rough, 0.12, streak);
			spec = mix(spec, 0.9, streak * 0.6);
		}
	}
	c = apply_wet(c, wetness * wet_k, rough);
	float s = snow_mask(world_pos, n, snow_cover);
	c = mix(c, SNOW_COLOR, s);
	rough = mix(rough, 0.6, s);
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metallic_base * (1.0 - s);
	SPECULAR = glass > 0.5 ? spec : night_specular(spec);
	// Мягкий контровой свет по краям и тёплая вспышка у только что поставленных деталей.
	float rim = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
	EMISSION = emit * (1.0 - s) + c * rim * 0.1 * (1.0 - night * 0.8) + vec3(1.0, 0.82, 0.55) * landing * 0.7;
}
