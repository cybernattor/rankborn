shader_type spatial;
render_mode blend_mix, depth_draw_alpha, cull_back, diffuse_toon, specular_schlick_ggx;

// ============================================================
// Вода — стилизованная low-poly с анимированными волнами.
// 2-3 синусоиды, наложенные друг на друга.
// ============================================================

uniform vec4 shallow_color : source_color = vec4(0.12, 0.45, 0.55, 0.75);
uniform vec4 deep_color : source_color = vec4(0.05, 0.25, 0.40, 0.85);
uniform float wave_height : hint_range(0.0, 2.0) = 0.3;
uniform float wave_speed : hint_range(0.0, 3.0) = 1.2;
uniform float wave_frequency : hint_range(0.1, 3.0) = 0.6;
uniform float specular_intensity : hint_range(0.0, 2.0) = 0.8;
uniform float fresnel_power : hint_range(0.0, 6.0) = 2.5;

varying float v_wave_height;

void vertex() {
	vec2 world_pos = VERTEX.xz;
	
	// Три синусоиды для анимированных волн
	float t = TIME * wave_speed;
	float wave1 = sin(world_pos.x * wave_frequency + world_pos.y * wave_frequency * 0.8 + t * 1.0);
	float wave2 = sin(world_pos.x * wave_frequency * 1.7 + world_pos.y * wave_frequency * 0.5 + t * 1.4 + 2.0);
	float wave3 = sin(world_pos.x * wave_frequency * 0.4 + world_pos.y * wave_frequency * 1.2 + t * 0.7 + 4.5);
	
	float wave = (wave1 * 0.5 + wave2 * 0.3 + wave3 * 0.2) * wave_height;
	v_wave_height = wave;
	
	VERTEX.y += wave;
}

void fragment() {
	vec3 view_dir = normalize(VIEW);
	vec3 normal = normalize(NORMAL);
	
	// Fresnel — больше отражений на краях
	float fresnel = pow(1.0 - max(dot(view_dir, normal), 0.0), fresnel_power);
	
	// Смешивание глубокого и мелкого цвета
	float depth_factor = 0.5 + 0.5 * v_wave_height / max(wave_height, 0.01);
	vec3 water_col = mix(deep_color.rgb, shallow_color.rgb, depth_factor);
	
	// Альфа с учётом fresnel
	float alpha = mix(deep_color.a, shallow_color.a, depth_factor);
	alpha = mix(alpha, 1.0, fresnel * 0.5);
	
	ALBEDO = water_col;
	ALPHA = alpha;
	ROUGHNESS = 0.2;
	METALLIC = 0.0;
	SPECULAR = specular_intensity;
	EMISSION = water_col * 0.05;
}
