shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 grass_color_base : source_color = vec4(0.15, 0.42, 0.1, 1.0);
uniform vec4 grass_color_tip : source_color = vec4(0.35, 0.65, 0.15, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.25, 0.18, 0.08, 1.0);

uniform float grass_height : hint_range(0.0, 2.0) = 0.4;
uniform float grass_density : hint_range(1.0, 100.0) = 40.0;
uniform float blade_width : hint_range(0.01, 0.3) = 0.08;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.3;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.5;
uniform float grass_cutoff : hint_range(0.0, 1.0) = 0.55;

varying float grass_blend;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	float cell_x = floor(UV.x * grass_density);
	float cell_y = floor(UV.y * grass_density);
	vec2 cell = vec2(cell_x, cell_y);

	float r = hash(cell);
	vec2 offset = vec2(hash(cell + 0.1), hash(cell + 0.2)) - 0.5;
	vec2 local_uv = fract(UV * grass_density) - 0.5;

	float dist = length(local_uv - offset * blade_width);
	float blade = 1.0 - smoothstep(0.0, blade_width, dist);

	float height_var = 0.6 + 0.4 * hash(cell + 0.3);
	float h = grass_height * height_var * blade;

	float wind_offset = TIME * wind_speed + cell_x * 0.5 + cell_y * 0.3;
	float wind = sin(wind_offset) * wind_strength;
	wind += sin(wind_offset * 2.3 + 1.7) * wind_strength * 0.4;

	float height_factor = UV.y;
	VERTEX.y += h * height_factor;
	VERTEX.x += wind * h * height_factor * height_factor;

	grass_blend = blade * height_factor;
}

void fragment() {
	float n = noise(UV * grass_density * 0.5 + TIME * 0.02);
	float n2 = noise(UV * grass_density * 1.5 - TIME * 0.01);

	vec3 g_base = grass_color_base.rgb;
	vec3 g_tip = grass_color_tip.rgb;
	vec3 base_col = mix(g_base, g_tip, grass_blend);

	base_col = mix(base_col, base_col * (0.85 + 0.3 * n), 0.4);
	base_col = mix(base_col, base_col * (0.9 + 0.2 * n2), 0.3);

	base_col = mix(dirt_color.rgb, base_col, smoothstep(0.0, 0.15, grass_blend));

	float ao = mix(0.5, 1.0, grass_blend);
	base_col *= ao;

	ALBEDO = base_col;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = 0.05;
}