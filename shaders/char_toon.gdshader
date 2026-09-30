shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_toon;

// ============================================================
// Тоон-шейдер для персонажей и оружия.
// Даёт стилизованное cel-shading освещение + rim light.
// ============================================================

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

uniform vec4 rim_color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform float rim_power : hint_range(0.0, 6.0) = 3.0;
uniform float rim_intensity : hint_range(0.0, 1.0) = 0.35;

// Ambient fill — минимальная освещённость чтобы тёмные цвета не сливались в чёрный
uniform float ambient_strength : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	vec3 base_color = albedo_color.rgb * COLOR.rgb;
	ALBEDO = base_color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	
	vec3 view_dir = normalize(VIEW);
	vec3 normal = normalize(NORMAL);
	float rim = 1.0 - max(dot(view_dir, normal), 0.0);
	rim = pow(rim, rim_power);
	
	vec3 rim_light = rim_color.rgb * rim * rim_intensity;
	
	// Минимальная подсветка сохраняет цвет в тени.
	EMISSION = rim_light + base_color * ambient_strength;
}
