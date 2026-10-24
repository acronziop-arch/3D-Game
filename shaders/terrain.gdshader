// Рельеф: цвет из вершин, сезонный оттенок травы, влага с лужами, снег.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/world.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = NORMAL;
}

void fragment() {
	if (clip_for_reflection(CAMERA_POSITION_WORLD, world_pos)) {
		discard;
	}
	vec3 c = COLOR.rgb;
	float green = clamp((c.g - max(c.r, c.b)) * 5.0, 0.0, 1.0);
	vec3 golden = vec3(c.g * 0.95 + c.r * 0.3, c.g * 0.82, c.b * 0.55);
	c = mix(c, golden, autumn * green * 0.8);
	c = mix(c, c * vec3(0.9, 1.1, 0.88), spring * green);
	float rough = 0.93;
	float land = step(water_level + 0.08, world_pos.y);
	float puddle = wetness * land * smoothstep(0.985, 0.998, world_normal.y)
		* smoothstep(0.56, 0.66, w_noise(world_pos.xz * 0.2));
	c = apply_wet(c, wetness * land * 0.85, rough);
	c = mix(c, c * 0.55, puddle);
	rough = mix(rough, 0.03, puddle);
	float s = snow_mask(world_pos, world_normal, snow_cover);
	c = mix(c, SNOW_COLOR, s);
	rough = mix(rough, 0.62, s);
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.3 + puddle * 0.5;
}
