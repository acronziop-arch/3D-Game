// Рыбы: хвост и тело изгибаются волной. INSTANCE_CUSTOM: x — фаза, y — скорость.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/world.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float speed = INSTANCE_CUSTOM.y;
	float tail = smoothstep(0.15, -0.55, VERTEX.z);
	VERTEX.x += sin(TIME * (5.0 + speed * 9.0) + phase - VERTEX.z * 7.0) * 0.06 * (0.25 + tail * 1.3);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (clip_for_reflection(CAMERA_POSITION_WORLD, world_pos)) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.32;
	SPECULAR = 0.65;
}
