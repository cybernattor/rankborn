shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_front, unshaded;

// ============================================================
// Outline-шейдер (inverted hull).
// Рендерится на front-face culling, вершины вытягиваются
// вдоль нормалей — создаёт обводку вокруг модели.
// ============================================================

uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.08, 1.0);
uniform float outline_width : hint_range(0.001, 0.5) = 0.07;

void vertex() {
	// Вытягиваем вершину вдоль нормали
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
