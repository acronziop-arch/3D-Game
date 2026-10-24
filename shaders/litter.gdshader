// Опавшие листья на земле. INSTANCE_CUSTOM.x — зерно россыпи: летом лежат
// немногие россыпи, осенью, по мере листопада, — почти все; весной перепревают,
// под снегом не видны.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx, world_vertex_coords;

#include "res://shaders/world.gdshaderinc"

uniform float fade_end = 80.0;

varying vec3 world_pos;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float seed = INSTANCE_CUSTOM.x;
	float amount = clamp(0.2 + autumn * 0.55 + (1.0 - leaf_amount) * 0.35, 0.0, 1.0) * (1.0 - spring * 0.75);
	// Далёкие россыпи исчезают по одной, а не всем чанком сразу.
	amount *= 1.0 - smoothstep(fade_end * 0.6, fade_end, distance(origin, CAMERA_POSITION_WORLD));
	if (seed > amount || snow_cover > 0.35 + seed * 0.4) {
		VERTEX = origin;
	}
	world_pos = VERTEX;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	if (clip_for_reflection(CAMERA_POSITION_WORLD, world_pos)) {
		discard;
	}
	float rough = 0.8;
	vec3 c = apply_wet(COLOR.rgb, wetness, rough);
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
