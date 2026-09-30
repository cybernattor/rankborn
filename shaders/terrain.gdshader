shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================
// Шейдер террейна — неподвижный low-poly с подсветкой краёв.
// Использует vertex colors из процедурного меша.
// ============================================================

// Rim lighting
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float rim_power : hint_range(0.0, 4.0) = 1.5;
uniform float rim_intensity : hint_range(0.0, 1.0) = 0.3;

varying float v_height;

void vertex() {
	v_height = VERTEX.y;
}

void fragment() {
	vec3 base_color = COLOR.rgb;
	
	// Rim lighting — подсветка краёв меша
	vec3 view_dir = normalize(VIEW);
	vec3 normal = normalize(NORMAL);
	float rim = 1.0 - max(dot(view_dir, normal), 0.0);
	rim = pow(rim, rim_power);
	vec3 rim_light = rim_color.rgb * rim * rim_intensity;
	
	// Ambient occlusion по высоте (низины чуть темнее)
	float height_fade = smoothstep(-10.0, 10.0, v_height);
	float ao = mix(0.85, 1.0, height_fade);
	
	vec3 final_color = base_color * ao + rim_light;
	
	ALBEDO = final_color;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
