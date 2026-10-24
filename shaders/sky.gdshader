// Небо: смена дня и ночи, закат, солнце, луна, звёзды и облака.
// Параметры задаёт Atmosphere (scripts/world/atmosphere.gd).
shader_type sky;

uniform vec3 day_top : source_color = vec3(0.3, 0.53, 0.84);
uniform vec3 day_horizon : source_color = vec3(0.74, 0.85, 0.93);
uniform vec3 night_top : source_color = vec3(0.015, 0.03, 0.08);
uniform vec3 night_horizon : source_color = vec3(0.07, 0.11, 0.2);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.52, 0.28);
uniform float daylight = 1.0;
uniform float sunset = 0.0;
uniform float overcast = 0.0;
uniform float cloud_coverage = 0.3;
uniform float cloud_darkness = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform float flash = 0.0;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;

float s_hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 top = mix(night_top, day_top, daylight);
	vec3 hor = mix(night_horizon, day_horizon, daylight);
	vec3 col = mix(hor, top, smoothstep(0.0, 0.6, max(h, 0.0)));
	float sun_dot = LIGHT0_ENABLED ? dot(d, LIGHT0_DIRECTION) : -1.0;
	col += sunset_color * sunset * pow(max(sun_dot, 0.0), 4.0) * (1.0 - smoothstep(0.0, 0.45, h)) * 0.9;
	vec3 gray = vec3(dot(col, vec3(0.3, 0.59, 0.11)));
	col = mix(col, gray * 0.92, overcast * 0.8);
	if (h < 0.0) {
		col = mix(hor, hor * 0.55, smoothstep(0.0, -0.4, h));
	}
	float clear = 1.0 - overcast;
	if (LIGHT0_ENABLED) {
		col += LIGHT0_COLOR * smoothstep(0.99945, 0.99975, sun_dot) * 8.0 * clear;
		col += LIGHT0_COLOR * pow(max(sun_dot, 0.0), 300.0) * 0.6 * clear;
	}
	if (LIGHT1_ENABLED) {
		float md = dot(d, LIGHT1_DIRECTION);
		col += vec3(0.88, 0.9, 1.0) * smoothstep(0.9992, 0.9996, md) * 2.0 * (1.0 - daylight) * clear;
		col += vec3(0.3, 0.35, 0.5) * pow(max(md, 0.0), 80.0) * 0.25 * (1.0 - daylight) * clear;
	}
	if (h > 0.0) {
		vec3 cell = floor(d * 260.0);
		float star = step(0.9965, s_hash(cell)) * s_hash(cell + 1.7);
		float twinkle = 0.6 + 0.4 * sin(TIME * 2.0 + s_hash(cell) * 50.0);
		col += vec3(star * twinkle) * (1.0 - daylight) * clear * smoothstep(0.0, 0.2, h) * 1.6;

		vec2 uv = d.xz / (h + 0.15) * 0.22 + cloud_offset;
		float n = texture(cloud_noise, uv).r * 0.65 + texture(cloud_noise, uv * 2.4 + cloud_offset * 0.6).r * 0.35;
		float edge = 1.0 - cloud_coverage;
		float cov = smoothstep(edge - 0.18, edge + 0.22, n) * smoothstep(0.0, 0.15, h);
		vec3 lit = mix(vec3(0.97, 0.97, 1.0), vec3(1.0, 0.74, 0.55), sunset) * mix(0.12, 1.0, daylight);
		vec3 dark = mix(lit * 0.72, vec3(0.32, 0.34, 0.39) * mix(0.15, 1.0, daylight), cloud_darkness);
		vec3 cloud = mix(lit, dark, smoothstep(0.35, 1.0, n));
		if (LIGHT0_ENABLED) {
			cloud += LIGHT0_COLOR * pow(max(sun_dot, 0.0), 12.0) * 0.35 * daylight * (1.0 - cloud_darkness);
		}
		col = mix(col, cloud, cov * 0.94);
	}
	col += vec3(0.75, 0.8, 1.0) * flash;
	COLOR = col;
}
