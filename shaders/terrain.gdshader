shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================
// Шейдер террейна — стилизованный low-poly с анимацией травы,
// улучшенным смешиванием цветов по высоте и rim lighting.
// Использует vertex colors из процедурного меша.
// ============================================================

// Цвета для смешивания (как в MeshUtils._terrain_color)
uniform vec4 dirt_color : source_color = vec4(0.55, 0.38, 0.22, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.25, 0.50, 0.18, 1.0);
uniform vec4 grass_mid : source_color = vec4(0.35, 0.62, 0.22, 1.0);
uniform vec4 grass_light : source_color = vec4(0.48, 0.72, 0.30, 1.0);
uniform vec4 rock_color : source_color = vec4(0.55, 0.52, 0.48, 1.0);

// Параметры анимации травы
uniform float grass_wave_strength : hint_range(0.0, 1.0) = 0.25;
uniform float grass_wave_speed : hint_range(0.0, 3.0) = 0.8;
uniform float grass_wave_frequency : hint_range(0.1, 2.0) = 0.5;

// Rim lighting
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float rim_power : hint_range(0.0, 4.0) = 1.5;
uniform float rim_intensity : hint_range(0.0, 1.0) = 0.3;

// Шум для анимации травы
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

varying float v_grass_factor;
varying float v_height;

void vertex() {
	v_height = VERTEX.y;
	
	// Определяем "травянистость" участка по вертексному цвету
	// Трава имеет высокий G/(R+B) коэффициент
	vec3 col = COLOR.rgb;
	float g_ratio = col.g / max(col.r + col.b, 0.001);
	v_grass_factor = smoothstep(0.8, 1.4, g_ratio);
	
	// Анимация травы — волна на вершинах с высоким grass_factor
	if (v_grass_factor > 0.01) {
		vec2 world_xz = VERTEX.xz;
		float wave = sin(TIME * grass_wave_speed + world_xz.x * grass_wave_frequency + world_xz.y * grass_wave_frequency * 0.7);
		wave += sin(TIME * grass_wave_speed * 1.5 + world_xz.x * grass_wave_frequency * 1.3 + world_xz.y * grass_wave_frequency * 0.9) * 0.5;
		wave *= 0.5;
		
		float sway = wave * grass_wave_strength * v_grass_factor;
		VERTEX.x += sway;
		VERTEX.z += sway * 0.6;
	}
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
