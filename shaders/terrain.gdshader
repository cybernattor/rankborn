shader_type spatial;
// Ламберт без бликов: земля матовая (roughness 0.85), блик почти не виден, а считался
// для каждого пикселя земли — а она занимает большую часть кадра.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

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
