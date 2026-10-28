// Вода в постройках (фонтан, корыта, жёлоб мельницы): полупрозрачная, сквозь неё видно дно.
//   * гладь: рябь кругами от середины постройки (там бьют струи) и мелкая зыбь;
//   * струи и падающая вода (крутые грани): пенистые полосы бегут вниз;
//   * блики солнца и отражение неба сильнее под острым углом.
// Стройка — как у building.gdshader (COLOR.a — этап детали).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/world.gdshaderinc"

uniform float build_progress = 1.0;
uniform vec3 deep_color : source_color = vec3(0.1, 0.33, 0.42);
uniform vec3 shallow_color : source_color = vec3(0.36, 0.7, 0.74);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 0.98);

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 obj_pos;
varying vec3 center;

void vertex() {
	obj_pos = VERTEX;
	center = MODEL_MATRIX[3].xyz;
	if (build_progress < 0.999) {
		float t = clamp((build_progress - COLOR.a) * 12.0, 0.0, 1.0);
		if (t <= 0.0) {
			VERTEX = vec3(0.0);
		} else {
			float k = t - 1.0;
			float e = 1.0 + 2.70158 * k * k * k + 1.70158 * k * k;
			VERTEX.y += (1.0 - e) * 1.8;
		}
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (clip_for_reflection(CAMERA_POSITION_WORLD, world_pos)) {
		discard;
	}
	vec3 n = normalize(world_normal);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float flat_k = smoothstep(0.55, 0.85, n.y);
	float t = TIME;
	float h;
	float foam;
	if (flat_k > 0.5) {
		// Гладь: кольца от середины (туда падают струи) и зыбь от ветра.
		vec2 d = world_pos.xz - center.xz;
		float r = length(d);
		float rings = sin(r * 16.0 - t * 5.0) * 0.5 + sin(r * 27.0 - t * 8.3 + 1.3) * 0.25;
		float chop = w_noise(world_pos.xz * 5.0 + vec2(t * 0.7, t * 0.45)) + w_noise(world_pos.xz * 9.0 - vec2(t * 0.5, t * 0.8)) * 0.5;
		h = rings * 0.6 + chop * 0.8;
		// Пена там, где струи бьют в воду: пятна, которые бурлят и расходятся.
		float bubbling = w_noise(world_pos.xz * 7.0 + vec2(0.0, t * 1.7)) * w_noise(world_pos.xz * 13.0 - vec2(t * 1.3, 0.0));
		foam = smoothstep(0.35, 0.7, bubbling) * 0.55;
	} else {
		// Падающая вода: продольные струйки бегут вниз, внизу — белая пена.
		vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), n) + vec3(0.0001));
		float u = dot(world_pos, side);
		float streaks = w_noise(vec2(u * 14.0, world_pos.y * 3.0 + t * 3.2)) * 0.7 + w_noise(vec2(u * 31.0, world_pos.y * 6.0 + t * 5.0)) * 0.3;
		h = streaks * 1.4;
		foam = smoothstep(0.55, 0.85, streaks) * 0.8;
	}
	NORMAL = w_bump(NORMAL, VERTEX, h, 0.05);
	float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
	vec3 sky = mix(vec3(0.72, 0.84, 0.94), vec3(0.06, 0.09, 0.17), night);
	vec3 c = mix(shallow_color, deep_color, 0.35 + 0.3 * flat_k);
	c = mix(c, sky, 0.18 + fres * 0.5);
	c = mix(c, foam_color * mix(1.0, 0.25, night), foam);
	// Зимой гладь затягивает льдом.
	float iced = smoothstep(0.45, 0.85, ice) * flat_k;
	c = mix(c, vec3(0.8, 0.88, 0.93), iced);
	ALBEDO = c;
	ROUGHNESS = mix(0.04, 0.35, foam + iced * 0.4);
	SPECULAR = night_specular(0.8);
	ALPHA = clamp(mix(0.55, 0.85, 1.0 - flat_k) + fres * 0.3 + foam * 0.4 + iced, 0.0, 0.96);
}
