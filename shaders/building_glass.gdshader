// Прозрачное стекло (теплица): видно, что внутри; блики и отражение неба под острым
// углом, капли в дождь, снег ложится на верхние стёкла. Видно с обеих сторон.
// Стройка — как у building.gdshader (COLOR.a — этап детали).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/world.gdshaderinc"

uniform float build_progress = 1.0;
uniform vec3 tint : source_color = vec3(0.82, 0.93, 0.96);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
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
	if (dot(n, v) < 0.0) {
		n = -n;
	}
	float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.5);
	vec3 sky = mix(vec3(0.78, 0.87, 0.95), vec3(0.06, 0.09, 0.17), night);
	vec3 c = mix(tint, sky, fres * 0.7);
	float a = 0.12 + fres * 0.5;
	// Чуть запылённое стекло и разводы — по низу больше.
	float dust = w_noise(world_pos.xz * 3.0 + world_pos.y * 2.0) * 0.06;
	c = mix(c, vec3(0.8, 0.78, 0.7), dust);
	a += dust;
	if (rain > 0.02) {
		float drops = smoothstep(0.82, 0.95, w_noise(vec2(dot(world_pos.xz, vec2(0.7, 0.7)) * 22.0, world_pos.y * 9.0 + TIME * 0.6)));
		c = mix(c, vec3(0.95), drops * rain * 0.5);
		a += drops * rain * 0.25;
	}
	float s = snow_mask(world_pos, n, snow_cover);
	c = mix(c, SNOW_COLOR, s);
	a = mix(a, 0.95, s);
	ALBEDO = c;
	ROUGHNESS = mix(0.03, 0.6, s);
	SPECULAR = night_specular(0.9);
	ALPHA = clamp(a, 0.0, 0.97);
}
