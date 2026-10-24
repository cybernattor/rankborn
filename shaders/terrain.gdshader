shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================
// Шейдер террейна — неподвижный low-poly.
// Цвет граней задаётся vertex colors процедурного меша
// (высота + наклон, см. MeshUtils.make_terrain).
// ============================================================

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
