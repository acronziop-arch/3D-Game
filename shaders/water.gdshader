// Вода — главная красота игры.
//   * отражения: отдельная камера снимает мир «из-под воды» (scripts/world/water.gd);
//   * блики солнца: очень гладкая поверхность и бегущая рябь;
//   * преломление: дно и рыбы видны сквозь воду и слегка «плывут»;
//   * глубина: чем толще слой воды, тем сильнее бирюзово-синий цвет;
//   * каустики: световая сетка на дне на мелководье;
//   * пена у берега и круги от капель во время дождя.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/world.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform sampler2D reflection_tex : source_color, filter_linear, repeat_disable;
uniform float reflection_enabled = 1.0;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D caustic_tex : filter_linear_mipmap, repeat_enable;

uniform vec3 shallow_color : source_color = vec3(0.32, 0.72, 0.7);
uniform vec3 deep_color : source_color = vec3(0.06, 0.24, 0.36);
uniform vec3 foam_color : source_color = vec3(0.96, 0.98, 1.0);
uniform float clarity = 0.3;
uniform float refraction = 0.035;
uniform vec3 sky_fallback : source_color = vec3(0.6, 0.75, 0.88);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = 0.03 + wind_strength * 0.09;
	float t = TIME;
	VERTEX.y += (sin(world_pos.x * 0.55 + t * 1.3) * cos(world_pos.z * 0.47 + t * 1.05)
		+ 0.5 * sin((world_pos.x - world_pos.z) * 0.9 + t * 1.9)) * w;
}

// Круги от капель: в каждой клетке своя капля со своим временем.
vec2 drops(vec2 p, float t) {
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

float caustics(vec2 p, float t) {
	float a = texture(caustic_tex, p * 0.09 + vec2(t * 0.011, t * 0.007)).r;
	float b = texture(caustic_tex, p * 0.11 - vec2(t * 0.009, -t * 0.012)).r;
	return pow(clamp(1.0 - abs(a - b) * 3.2, 0.0, 1.0), 6.0);
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
	// 1. Нормаль: два слоя ряби бегут по ветру, сверху — капли дождя.
	vec2 wd = normalize(wind_dir + vec2(0.0001));
	float speed = 0.015 + wind_strength * 0.05;
	vec2 p = world_pos.xz;
	vec3 na = texture(ripple_a, p * 0.06 + wd * TIME * speed).rgb * 2.0 - 1.0;
	vec3 nb = texture(ripple_b, p * 0.15 - vec2(wd.y, -wd.x) * TIME * speed * 1.3).rgb * 2.0 - 1.0;
	vec2 slope = (na.xy * 0.6 + nb.xy * 0.4) * (0.22 + wind_strength * 0.75);
	if (rain > 0.01) {
		slope += (drops(p * 1.6, TIME) + drops(p * 1.6 + 17.3, TIME * 1.07 + 0.37)) * rain * 0.9;
	}
	vec3 nw = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// 2. Что под водой и как глубоко.
	float water_dist = -VERTEX.z;
	vec3 ground_view = view_from_depth(SCREEN_UV, texture(depth_tex, SCREEN_UV).r, INV_PROJECTION_MATRIX);
	float thickness = max(-ground_view.z - water_dist, 0.0);
	vec2 ruv = SCREEN_UV + slope * refraction * clamp(thickness * 0.6, 0.0, 1.0);
	vec3 refr_view = view_from_depth(ruv, texture(depth_tex, ruv).r, INV_PROJECTION_MATRIX);
	if (-refr_view.z < water_dist) {
		ruv = SCREEN_UV;
		refr_view = ground_view;
	}
	vec3 ground_world = (INV_VIEW_MATRIX * vec4(refr_view, 1.0)).xyz;
	float depth_v = max(world_pos.y - ground_world.y, 0.0);
	thickness = max(-refr_view.z - water_dist, 0.0);

	vec3 under = textureLod(screen_tex, ruv, 0.0).rgb;
	float light = (1.0 - night) * (1.0 - rain * 0.6);
	under += vec3(0.85, 0.95, 0.9) * caustics(ground_world.xz, TIME) * exp(-depth_v * 0.45) * light * 0.45;
	vec3 tint = mix(shallow_color, deep_color, smoothstep(0.2, 4.5, depth_v)) * mix(0.25, 1.0, 1.0 - night * 0.8);
	float absorb = 1.0 - exp(-thickness * clarity);
	under = mix(under * mix(vec3(1.0), shallow_color * 1.35, 0.35), tint, absorb);

	// 3. Отражение и френель.
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(nw, view_dir), 0.0, 1.0), 5.0);
	vec2 refl_uv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + slope * 0.06;
	vec3 refl = mix(sky_fallback * mix(1.0, 0.12, night), texture(reflection_tex, refl_uv).rgb, reflection_enabled);
	// Отражения чуть сильнее физических: вода — главная красота, её видно сверху.
	vec3 col = mix(under, refl, clamp(0.14 + fres * 1.3, 0.0, 0.95));

	// 4. Пена у берега: тонкая полоса, дышит со временем.
	float foam_band = smoothstep(0.5, 0.0, depth_v) * smoothstep(0.0, 0.06, depth_v);
	float foam = foam_band * smoothstep(0.35, 0.75, w_noise(p * 2.2 + TIME * 0.35) * 0.6 + w_noise(p * 5.0 - TIME * 0.2) * 0.4);
	col = mix(col, foam_color * mix(1.0, 0.3, night), foam * 0.75);

	// Освещение Godot добавит только солнечные блики — цвет уже собран вручную.
	ALBEDO = vec3(0.0);
	EMISSION = col;
	ROUGHNESS = mix(0.035, 0.12, rain) + foam * 0.5;
	SPECULAR = mix(0.55, 0.35, reflection_enabled);
	ALPHA = smoothstep(0.0, 0.12, thickness);
}
