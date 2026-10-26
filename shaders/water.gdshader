// Вода — главная красота игры.
//   * течение: реки текут вдоль русла (карта течения flow_map от WorldGen), озёра стоят;
//   * ветер гонит мелкую рябь по своему направлению и рисует порывы-«кошачьи лапки»;
//   * дождь — круги от капель, снег — тающие снежинки; зимой озёра (не реки) замерзают;
//   * отражения: отдельная камера снимает мир «из-под воды» (scripts/world/water.gd);
//   * преломление: дно и рыбы видны сквозь воду и слегка «плывут»;
//   * глубина: чем толще слой воды, тем сильнее бирюзово-синий цвет;
//   * пена — тонкая и освещённая солнцем, поэтому ночью вода не светится.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/world.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform sampler2D reflection_tex : source_color, filter_linear, repeat_disable;
uniform float reflection_enabled = 1.0;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D caustic_tex : filter_linear_mipmap, repeat_enable;
// Карта течения (RGBA8): rg — направление и сила, b — стоячая вода, a — данные есть.
uniform sampler2D flow_map : filter_linear, repeat_enable;
uniform float flow_world_size = 1024.0;

uniform vec3 shallow_color : source_color = vec3(0.32, 0.72, 0.7);
uniform vec3 deep_color : source_color = vec3(0.06, 0.24, 0.36);
uniform vec3 foam_color : source_color = vec3(0.93, 0.96, 0.98);
uniform vec3 ice_color : source_color = vec3(0.78, 0.87, 0.92);
uniform float clarity = 0.3;
uniform float refraction = 0.035;
uniform vec3 sky_fallback : source_color = vec3(0.6, 0.75, 0.88);

varying vec3 world_pos;
varying float v_still;

vec4 flow_info(vec2 p) {
	vec4 info = textureLod(flow_map, p / flow_world_size, 0.0);
	// Где карты нет — считаем воду стоячей.
	return vec4((info.rg * 2.0 - 1.0) * info.a, mix(1.0, info.b, info.a), info.a);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 info = flow_info(world_pos.xz);
	v_still = info.z;
	vec2 wd = normalize(wind_dir + vec2(0.0001));
	// Волны бегут по ветру. Стоячая вода в штиль почти не колышется; лёд не двигается.
	float a = dot(world_pos.xz, wd);
	float b = dot(world_pos.xz, vec2(-wd.y, wd.x));
	float frozen = smoothstep(0.4, 0.8, ice) * v_still;
	float w = (0.008 + wind_strength * 0.075 + (1.0 - v_still) * 0.02) * (1.0 - frozen);
	VERTEX.y += (sin(a * 0.55 - wind_phase * 1.25) * cos(b * 0.31 + wind_phase * 0.35)
		+ 0.45 * sin(a * 1.1 - wind_phase * 1.9 + b * 0.2)) * w;
}

// Снежинки садятся на воду и тают: светлые точки, которые быстро гаснут.
float flakes(vec2 p, float t) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = w_hash(cell + 11.0);
	float life = fract(t * 0.7 + h);
	vec2 center = (vec2(w_hash(cell + 1.7), w_hash(cell + 9.3)) - 0.5) * 0.7;
	return smoothstep(0.07, 0.02, length(f - center)) * (1.0 - life) * step(0.55, h);
}

float caustics(vec2 p, float t) {
	float a = texture(caustic_tex, p * 0.09 + vec2(t * 0.011, t * 0.007)).r;
	float b = texture(caustic_tex, p * 0.11 - vec2(t * 0.009, -t * 0.012)).r;
	return pow(clamp(1.0 - abs(a - b) * 3.2, 0.0, 1.0), 6.0);
}

// Трещины во льду: тонкие линии по границам ячеек шума.
float ice_cracks(vec2 p) {
	float n1 = w_noise(p * 0.55);
	float n2 = w_noise(p * 1.3 + 7.0);
	float l1 = smoothstep(0.035, 0.0, abs(n1 - 0.5));
	float l2 = smoothstep(0.025, 0.0, abs(n2 - 0.5)) * 0.6;
	return max(l1, l2);
}

vec3 view_from_depth(vec2 uv, float depth, mat4 inv_proj) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec4 info = flow_info(p);
	vec2 flow = info.xy;
	float still = info.z;
	float flowing = 1.0 - still;
	vec2 wd = normalize(wind_dir + vec2(0.0001));

	// 1. Нормаль.
	// Ветровая рябь сносится по ветру (wind_drift копится на процессоре — смена
	// погоды меняет скорость, а не перескакивает).
	vec2 drift = p - wind_drift;
	vec3 na = texture(ripple_a, drift * 0.06).rgb * 2.0 - 1.0;
	vec3 nb = texture(ripple_b, (p - wind_drift * 1.3) * 0.15 + vec2(0.31, 0.77)).rgb * 2.0 - 1.0;
	// Порывы: пятна ряби бегут по воде вместе с ветром.
	float gust = smoothstep(0.42, 0.78, w_noise((p - wind_drift * 3.0) * 0.035));
	float wind_amp = (0.05 + wind_strength * (0.55 + gust * 0.6)) * mix(1.0, 0.7, flowing);
	vec2 slope = (na.xy * 0.6 + nb.xy * 0.4) * wind_amp;
	// Течение реки: две фазы карты течения, сменяющие друг друга без рывков.
	if (flowing > 0.01) {
		float period = 2.6;
		float ph0 = fract(TIME / period);
		float ph1 = fract(TIME / period + 0.5);
		float wgt = abs(ph0 * 2.0 - 1.0);
		vec2 fl = flow * 1.6;
		vec3 f0 = texture(ripple_b, (p - fl * ph0 * period) * 0.13).rgb * 2.0 - 1.0;
		vec3 f1 = texture(ripple_b, (p - fl * ph1 * period) * 0.13 + vec2(0.5, 0.21)).rgb * 2.0 - 1.0;
		slope += mix(f0.xy, f1.xy, wgt) * 0.32 * flowing;
	}
	if (rain > 0.01) {
		slope += (rain_drops(p * 1.6, TIME) + rain_drops(p * 1.6 + 17.3, TIME * 1.07 + 0.37)) * rain * 0.9;
	}

	// 2. Что под водой и как глубоко.
	float water_dist = -VERTEX.z;
	vec3 ground_view = view_from_depth(SCREEN_UV, texture(depth_tex, SCREEN_UV).r, INV_PROJECTION_MATRIX);
	float thickness0 = max(-ground_view.z - water_dist, 0.0);
	vec3 ground_world0 = (INV_VIEW_MATRIX * vec4(ground_view, 1.0)).xyz;
	float depth0 = max(world_pos.y - ground_world0.y, 0.0);

	// Лёд: только стоячая вода; сначала у берегов, потом и посередине.
	float freeze = smoothstep(0.05, 0.85, ice) * still;
	float ice_edge = freeze * 1.5 - 0.15 - depth0 * 0.12 + (w_noise(p * 0.4) - 0.5) * 0.25;
	float ice_amt = smoothstep(0.0, 0.08, ice_edge);
	slope *= 1.0 - ice_amt;

	vec3 nw = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	vec2 ruv = SCREEN_UV + slope * refraction * clamp(thickness0 * 0.6, 0.0, 1.0);
	vec3 refr_view = view_from_depth(ruv, texture(depth_tex, ruv).r, INV_PROJECTION_MATRIX);
	if (-refr_view.z < water_dist) {
		ruv = SCREEN_UV;
		refr_view = ground_view;
	}
	vec3 ground_world = (INV_VIEW_MATRIX * vec4(refr_view, 1.0)).xyz;
	float depth_v = max(world_pos.y - ground_world.y, 0.0);
	float thickness = max(-refr_view.z - water_dist, 0.0);

	vec3 under = textureLod(screen_tex, ruv, 0.0).rgb;
	float light = (1.0 - night) * (1.0 - rain * 0.6);
	under += vec3(0.85, 0.95, 0.9) * caustics(ground_world.xz, TIME) * exp(-depth_v * 0.45) * light * 0.4 * (1.0 - ice_amt);
	vec3 tint = mix(shallow_color, deep_color, smoothstep(0.2, 4.5, depth_v)) * mix(0.25, 1.0, 1.0 - night * 0.8);
	// Под дождём и в снегопад вода мутнее и темнее.
	tint *= 1.0 - (rain + snowfall) * 0.15;
	float absorb = 1.0 - exp(-thickness * clarity * (1.0 + rain * 0.5));
	under = mix(under * mix(vec3(1.0), shallow_color * 1.35, 0.35), tint, absorb);

	// 3. Отражение и френель. Искажение отражения меньше вблизи — иначе при
	// сильном приближении картинка «прыгает».
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(nw, view_dir), 0.0, 1.0), 5.0);
	float near_k = clamp(water_dist / 40.0, 0.25, 1.0);
	vec2 refl_uv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + slope * 0.05 * near_k;
	vec3 refl = mix(sky_fallback * mix(1.0, 0.12, night), texture(reflection_tex, refl_uv).rgb, reflection_enabled);
	// В дождь и порывы отражение размыто и слабее.
	float refl_k = clamp(0.12 + fres * 1.25, 0.0, 0.92) * (1.0 - rain * 0.25);
	vec3 col = mix(under, refl, refl_k);

	// 4. Снежинки тают на поверхности.
	float snow_dots = 0.0;
	if (snowfall > 0.01) {
		snow_dots = (flakes(p * 2.3, TIME) + flakes(p * 2.3 + 5.1, TIME * 1.13 + 0.4)) * snowfall * (1.0 - ice_amt);
	}

	// 5. Пена: тонкая полоса у самого берега, рвётся на клочки. Освещается солнцем
	// (ALBEDO), а не светится сама — ночью она тёмная, как и всё вокруг.
	float foam_band = smoothstep(0.28, 0.0, depth_v) * smoothstep(0.0, 0.05, depth_v);
	float foam = foam_band * smoothstep(0.45, 0.8, w_noise(p * 2.2 + TIME * 0.25) * 0.6 + w_noise(p * 5.0 - TIME * 0.15) * 0.4);
	foam = max(foam * 0.55, snow_dots * 0.6) * (1.0 - ice_amt);

	// 6. Лёд: матовый, с трещинами, под снегом — белый.
	vec3 ice_col = ice_color * (0.9 + w_noise(p * 0.25) * 0.15);
	ice_col = mix(ice_col, ice_col * 0.62, ice_cracks(p) * 0.7);
	ice_col = mix(ice_col, mix(under, ice_col, 0.6), smoothstep(0.3, 0.0, ice_edge) * 0.5);
	float ice_snow = clamp(snow_cover * 1.3 - 0.2, 0.0, 1.0) * (0.6 + w_noise(p * 0.6) * 0.4);
	ice_col = mix(ice_col, SNOW_COLOR, ice_snow);

	vec3 lit = mix(foam_color * foam, ice_col, ice_amt);
	float lit_k = max(foam, ice_amt);
	ALBEDO = lit;
	EMISSION = col * (1.0 - lit_k);
	ROUGHNESS = mix(mix(0.07, 0.16, rain) + wind_strength * 0.04, 0.55, lit_k);
	SPECULAR = mix(mix(0.42, 0.3, reflection_enabled), 0.25, lit_k);
	ALPHA = max(smoothstep(0.0, 0.12, thickness), ice_amt);
}
