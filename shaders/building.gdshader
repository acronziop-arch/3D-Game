// Здания. COLOR.a — этап стройки детали (0 — фундамент, 1 — последняя деталь).
// build_progress (у каждого здания свой) собирает дом: детали «прилетают» сверху
// на своё место по очереди, снизу вверх.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/world.gdshaderinc"

uniform float roughness_base = 0.85;
uniform float metallic_base = 0.0;
uniform float specular_base = 0.5;
uniform float porosity = 1.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_day = 0.0;
uniform float emission_night = 0.0;
uniform float flutter = 0.0;
instance uniform float build_progress = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	if (build_progress < 0.999) {
		float t = clamp((build_progress - COLOR.a) * 14.0, 0.0, 1.0);
		if (t <= 0.0) {
			VERTEX = vec3(0.0);
		} else {
			float e = 1.0 - pow(1.0 - t, 3.0);
			VERTEX.y += (1.0 - e) * 2.4;
		}
	}
	if (flutter > 0.0) {
		float t = TIME * (4.0 + wind_strength * 7.0);
		VERTEX += NORMAL * sin(t + VERTEX.x * 2.3 + VERTEX.y * 1.7 + VERTEX.z * 1.9) * 0.035 * (0.2 + wind_strength) * flutter;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (clip_for_reflection(CAMERA_POSITION_WORLD, world_pos)) {
		discard;
	}
	vec3 c = COLOR.rgb;
	float rough = roughness_base;
	c = apply_wet(c, wetness * porosity, rough);
	float s = snow_mask(world_pos, world_normal, snow_cover);
	c = mix(c, SNOW_COLOR, s);
	rough = mix(rough, 0.6, s);
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metallic_base * (1.0 - s);
	SPECULAR = specular_base;
	EMISSION = emission_color * (emission_day + emission_night * night) * (1.0 - s);
}
