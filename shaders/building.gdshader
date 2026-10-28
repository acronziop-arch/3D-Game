// Здания. COLOR.a — этап стройки детали (0 — фундамент, 1 — последняя деталь).
// build_progress собирает дом: детали по очереди падают сверху на своё место
// с лёгким отскоком и тёплой вспышкой. У строящегося здания свои копии
// материалов (у общих build_progress = 1), поэтому стройка видна и в браузере.
// Стекло (glass = 1): небо и блик солнца в окне, капли в дождь, изморозь зимой.
// Во время дождя по стенам сбегают струйки воды.
// surface — узор материала (см. world.gdshaderinc): 1 дерево (волокна вдоль UV2 —
// см. Geo.grain), 2 камень, 3 обожжённая глина. Узор привязан к модели, а не к миру.
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
// 1 — за проёмом (стекло или открытое окно) видна комната.
uniform float interior = 0.0;
uniform float build_progress = 1.0;
uniform float surface = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying float landing;
varying vec3 obj_pos;
varying vec3 obj_normal;
varying vec3 grain_dir;

void vertex() {
	landing = 0.0;
	// Узор — по точке модели (сдвинутой на место здания, чтобы одинаковые дома различались).
	obj_pos = VERTEX + MODEL_MATRIX[3].xyz * vec3(0.37, 0.0, 0.53);
	obj_normal = NORMAL;
	grain_dir = vec3(0.0);
	if (surface > 0.5 && surface < 1.5 && (UV2.x > 0.001 || UV2.y > 0.001)) {
		vec2 e = UV2 - 1.0;
		grain_dir = vec3(e.x, sqrt(max(1.0 - dot(e, e), 0.0)), e.y);
	}
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

// Комната за окном без лишней геометрии (interior mapping): луч взгляда продолжается
// внутрь здания и упирается в пол, потолок, стены или стол воображаемой комнаты.
// uv — точка на стекле (0..1), rd — луч в осях окна (x вдоль стены, y вверх, z внутрь),
// seed — своё у каждого окна: цвет стен, картина, стол.
vec3 room_color(vec2 uv, vec3 rd, float seed) {
	const float D = 0.95;
	// Окно — середина передней стены: комната шире и выше проёма.
	vec3 p = vec3(0.2 + uv.x * 0.6, 0.16 + uv.y * 0.62, 0.0);
	rd.z = max(rd.z, 0.08);
	vec3 safe = vec3(abs(rd.x) < 1e-4 ? 1e-4 : rd.x, abs(rd.y) < 1e-4 ? 1e-4 : rd.y, rd.z);
	float tx = ((safe.x > 0.0 ? 1.0 : 0.0) - p.x) / safe.x;
	float ty = ((safe.y > 0.0 ? 1.0 : 0.0) - p.y) / safe.y;
	float tz = D / safe.z;
	float t = min(tx, min(ty, tz));
	vec3 hp = p + rd * t;
	float h1 = fract(seed * 7.13);
	float h2 = fract(seed * 13.7);
	vec3 plaster = mix(vec3(0.86, 0.78, 0.64), vec3(0.74, 0.62, 0.5), h1);
	plaster = mix(plaster, vec3(0.66, 0.74, 0.7), step(0.82, h2) * 0.6);
	vec3 wood = vec3(0.5, 0.33, 0.2);
	vec3 col;
	float shade;
	if (t == ty) {
		if (rd.y < 0.0) {
			// Дощатый пол с половиком.
			float plank = smoothstep(0.02, 0.06, abs(fract(hp.x * 7.0) - 0.5) * 2.0);
			col = wood * (0.8 + 0.2 * plank) * (0.92 + 0.08 * w_hash(vec2(floor(hp.x * 7.0), 2.0)));
			vec2 rug = abs(hp.xz - vec2(0.5, D * 0.55)) - vec2(0.24, 0.22);
			if (max(rug.x, rug.y) < 0.0) {
				col = mix(vec3(0.62, 0.22, 0.18), vec3(0.78, 0.6, 0.3), step(max(rug.x, rug.y), -0.05) * step(-0.07, max(rug.x, rug.y)));
			}
			shade = 0.85;
		} else {
			// Потолок с балками.
			float beam = step(0.72, fract(hp.z * 3.2));
			col = mix(plaster * 0.9, wood * 0.8, beam);
			shade = 0.55;
		}
	} else if (t == tx) {
		// Боковая стена: снизу деревянная панель.
		col = mix(wood * 0.95, plaster, step(0.3, hp.y));
		shade = 0.72;
	} else {
		// Задняя стена: картина или полка, у пола — шкаф.
		col = mix(wood * 0.95, plaster, step(0.28, hp.y));
		vec2 pic = abs(hp.xy - vec2(0.5 + (h2 - 0.5) * 0.3, 0.6)) - vec2(0.13, 0.1);
		if (max(pic.x, pic.y) < 0.0) {
			vec3 art = mix(vec3(0.3, 0.5, 0.35), vec3(0.35, 0.45, 0.7), h1) * (0.8 + 0.3 * step(0.5, hp.y - 0.55 + hp.x * 0.3));
			col = max(pic.x, pic.y) > -0.025 ? vec3(0.42, 0.28, 0.12) : art;
		}
		vec2 cab = abs(hp.xy - vec2(h1 < 0.5 ? 0.14 : 0.86, 0.26)) - vec2(0.1, 0.26);
		if (max(cab.x, cab.y) < 0.0) {
			col = wood * (0.7 + 0.15 * step(0.3, fract(hp.y * 4.0)));
		}
		shade = 0.95;
	}
	// Стол посреди комнаты (луч против коробки).
	vec3 bmin = vec3(0.34, 0.0, D * 0.42);
	vec3 bmax = vec3(0.66, 0.3, D * 0.7);
	vec3 t0 = (bmin - p) / safe;
	vec3 t1 = (bmax - p) / safe;
	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);
	float tn = max(max(tmin.x, tmin.y), tmin.z);
	float tf = min(min(tmax.x, tmax.y), tmax.z);
	if (tn < tf && tn > 0.0 && tn < t) {
		bool top = tn == tmin.y;
		col = wood * (top ? 1.05 : 0.7);
		shade = top ? 0.9 : 0.7;
		hp = p + rd * tn;
	}
	// Вглубь комнаты темнее.
	return col * shade * mix(1.0, 0.6, clamp(hp.z / D, 0.0, 1.0));
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
	// Комната за проёмом (на высоком качестве): только на лицевой стороне стекла.
	bool has_room = interior > 0.5 && interiors > 0.5 && (UV2.x > 0.0001 || UV2.y > 0.0001) && abs(n.y) < 0.3;
	vec3 room = vec3(0.0);
	if (has_room) {
		// Старое стекло чуть волнистое — комната за ним немного «плывёт».
		vec2 wobble = (vec2(w_noise(plane * 6.0), w_noise(plane * 6.0 + 7.3)) - 0.5) * 0.035 * glass;
		vec3 rd = -v;
		vec3 rt = vec3(dot(rd, side), rd.y, dot(rd, -n));
		float seed = fract(dot(COLOR.rgb, vec3(17.31, 31.7, 7.93)) + dot(floor(MODEL_MATRIX[3].xz), vec2(0.37, 0.71)));
		room = room_color(clamp(UV2 + wobble, 0.0, 1.0), rt, seed);
		// Днём в комнате сумрачно; вечером горит тёплый свет.
		vec3 lamp = vec3(1.0, 0.72, 0.42);
		room *= mix(0.92, 0.16, night);
		emit = room * lamp * night * 4.2;
	}

	if (glass > 0.5) {
		// Небо в стекле: светлее к горизонту, ночью тёмно-синее.
		vec3 r = reflect(-v, n);
		float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.5);
		vec3 sky_day = mix(vec3(0.8, 0.87, 0.93), vec3(0.4, 0.58, 0.86), clamp(r.y * 1.4, 0.0, 1.0));
		vec3 sky = mix(sky_day, vec3(0.05, 0.08, 0.16), night);
		// Полоса блика скользит по стеклу, когда камера движется.
		float band = dot(plane, vec2(0.7, 0.55)) * 1.7 + dot(v, side) * 2.4;
		float gleam = smoothstep(0.86, 1.0, sin(band)) * (1.0 - night * 0.75);
		if (has_room) {
			// Сквозь стекло видна комната, поверх — отражение неба (сильнее под острым углом).
			c = mix(room, sky, 0.1 + fres * 0.55) + vec3(gleam) * 0.45;
		} else {
			c = mix(c * 0.5, sky, 0.38 + fres * 0.5) + vec3(gleam) * 0.5;
		}
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
	} else if (has_room) {
		// Открытое окно без стекла — комната видна прямо.
		c = room;
		rough = 0.9;
		wet_k = 0.0;
	} else if (porosity > 0.0) {
		if (surface > 0.5) {
			// Узор материала; мелкие подробности гаснут вдали (иначе рябит).
			float detail = texture_detail * (1.0 - smoothstep(30.0, 85.0, length(VERTEX)));
			float h = 0.0;
			vec3 on = normalize(obj_normal);
			if (surface < 1.5) {
				c = w_wood(c, obj_pos, grain_dir, on, detail, rough, h);
			} else if (surface < 2.5) {
				c = w_stone(c, obj_pos, n, detail, rough, h);
			} else {
				c = w_clay(c, obj_pos, detail, rough, h);
			}
			if (detail > 0.01) {
				NORMAL = w_bump(NORMAL, VERTEX, h, 0.012 * detail);
			}
		}
		// Дождь на стенах: мокрые дорожки, по ним сбегают капли, а на шершавой
		// поверхности висят бусины воды с бликами.
		float vertical = 1.0 - smoothstep(0.35, 0.65, abs(n.y));
		float flow = max(rain, wetness * 0.45) * vertical;
		if (flow > 0.01) {
			float u = plane.x * 6.0;
			float h = w_hash(vec2(floor(u), 9.1));
			float line = (1.0 - smoothstep(0.04, 0.15, abs(fract(u) - 0.5))) * step(0.45, h);
			float runs = smoothstep(0.8, 1.0, fract(plane.y * 0.9 + TIME * (0.35 + h * 0.6) + h * 13.0));
			float streak = clamp(line * (0.5 + runs * 1.2) * flow, 0.0, 1.0);
			c *= 1.0 - streak * 0.35;
			rough = mix(rough, 0.1, streak);
			spec = mix(spec, 1.0, streak * 0.7);
			vec2 spark;
			float bead = glass_drops(plane * 0.7, spark) * flow;
			c = mix(c, c * 0.6, bead * 0.7);
			c += vec3(smoothstep(0.07, 0.0, length(spark))) * bead * 0.55;
			rough = mix(rough, 0.08, bead);
			spec = mix(spec, 1.0, bead);
		}
		// На крышах и карнизах — всплески падающих капель.
		float up = smoothstep(0.3, 0.6, n.y);
		if (rain > 0.05 && up > 0.0) {
			vec2 q = world_pos.xz * 3.0 + n.xz * 2.0;
			float splash = length(rain_drops(q, TIME * 1.3) + rain_drops(q + 5.3, TIME * 1.1 + 0.4));
			c += vec3(0.5) * clamp(splash, 0.0, 1.0) * rain * up * 0.45;
			rough = mix(rough, 0.15, rain * up * 0.6);
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
