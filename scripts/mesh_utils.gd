class_name MeshUtils

## Амплитуда холмов, м. С камерой сверху склоны почти не читаются, а крутой склон
## делает укрытия бесполезными (стоящий выше смотрит поверх стены) — поэтому холмы
## пологие, как у Foxhole. Было 12 м, когда камера была от первого лица.
const TERRAIN_HEIGHT := 4.0
## Пороги цветов земли подобраны под амплитуду 12 м — высоту приводим к ней.
const TERRAIN_COLOR_REFERENCE := 12.0
const TERRAIN_DIRT := Color(0.55, 0.38, 0.22)
const TERRAIN_GRASS_DARK := Color(0.25, 0.50, 0.18)
const TERRAIN_GRASS_MID := Color(0.35, 0.62, 0.22)
const TERRAIN_GRASS_LIGHT := Color(0.48, 0.72, 0.30)
const TERRAIN_ROCK := Color(0.55, 0.52, 0.48)


static func make_box(size: Vector3, color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(st, Vector3.ZERO, size, color)
	return st.commit()


static func make_humanoid() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_add_box(st, Vector3(0, 0.95, 0), Vector3(0.5, 0.55, 0.3), Color(0.22, 0.38, 0.58))
	_add_box(st, Vector3(0, 1.30, 0), Vector3(0.14, 0.16, 0.14), Color(0.82, 0.68, 0.55))
	_add_box(st, Vector3(0, 1.48, 0), Vector3(0.28, 0.28, 0.28), Color(0.82, 0.68, 0.55))
	_add_box(st, Vector3(0, 1.6, 0), Vector3(0.32, 0.16, 0.32), Color(0.25, 0.32, 0.2))
	_add_box(st, Vector3(-0.31, 0.9, 0), Vector3(0.14, 0.45, 0.14), Color(0.22, 0.38, 0.58))
	_add_box(st, Vector3(0.31, 0.9, 0), Vector3(0.14, 0.45, 0.14), Color(0.22, 0.38, 0.58))
	_add_box(st, Vector3(-0.31, 0.62, 0), Vector3(0.1, 0.12, 0.1), Color(0.82, 0.68, 0.55))
	_add_box(st, Vector3(0.31, 0.62, 0), Vector3(0.1, 0.12, 0.1), Color(0.82, 0.68, 0.55))
	_add_box(st, Vector3(-0.13, 0.425, 0), Vector3(0.16, 0.5, 0.16), Color(0.2, 0.28, 0.18))
	_add_box(st, Vector3(0.13, 0.425, 0), Vector3(0.16, 0.5, 0.16), Color(0.2, 0.28, 0.18))
	_add_box(st, Vector3(-0.13, 0.10, -0.02), Vector3(0.17, 0.20, 0.22), Color(0.18, 0.15, 0.12))
	_add_box(st, Vector3(0.13, 0.10, -0.02), Vector3(0.17, 0.20, 0.22), Color(0.18, 0.15, 0.12))

	return st.commit()


static func make_rifle() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var metal := Color(0.15, 0.15, 0.18)
	var wood := Color(0.35, 0.22, 0.12)
	var dark := Color(0.1, 0.1, 0.12)

	_add_box(st, Vector3(0, 0, -0.35), Vector3(0.04, 0.04, 0.35), metal)
	_add_box(st, Vector3(0, -0.01, -0.05), Vector3(0.06, 0.07, 0.25), metal)
	_add_box(st, Vector3(0, -0.04, 0.165), Vector3(0.05, 0.04, 0.18), wood)
	_add_box(st, Vector3(0, -0.08, -0.1), Vector3(0.035, 0.1, 0.06), dark)
	_add_box(st, Vector3(0, 0.03, -0.08), Vector3(0.025, 0.025, 0.06), metal)
	_add_box(st, Vector3(0, 0, -0.52), Vector3(0.015, 0.035, 0.02), metal)

	return st.commit()


## Процедурная земля. smooth = false — плоские грани (low-poly), true — сглаженное освещение.
## Цвет задаётся в вершинах (высота + наклон + лёгкий шум яркости) и плавно
## перетекает между треугольниками: соседние грани больше не «шахматка».
static func make_terrain(size: float, resolution: int, seed_val: int, smooth: bool = false) -> ArrayMesh:
	var noise := _terrain_noise(seed_val)

	# Мелкие пятна оттенка, чтобы большие поля травы не были однотонными.
	var tint := FastNoiseLite.new()
	tint.seed = seed_val + 1
	tint.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	tint.frequency = 0.06

	var half := size / 2.0
	var step := size / resolution
	var row := resolution + 1

	var verts: Array[Vector3] = []
	for z in range(row):
		for x in range(row):
			var px := -half + x * step
			var pz := -half + z * step
			verts.append(Vector3(px, noise.get_noise_2d(px, pz) * TERRAIN_HEIGHT, pz))

	var colors: Array[Color] = []
	for z in range(row):
		for x in range(row):
			var v := verts[z * row + x]
			# Нормаль вершины по соседям сетки — для цвета склона.
			var hl := verts[z * row + maxi(x - 1, 0)].y
			var hr := verts[z * row + mini(x + 1, resolution)].y
			var hd := verts[maxi(z - 1, 0) * row + x].y
			var hu := verts[mini(z + 1, resolution) * row + x].y
			var normal := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			var color := _apply_slope(_terrain_color(v.y * TERRAIN_COLOR_REFERENCE / TERRAIN_HEIGHT), normal)
			var shade := 1.0 + tint.get_noise_2d(v.x, v.z) * 0.06
			colors.append(Color(color.r * shade, color.g * shade, color.b * shade))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0 if smooth else -1)
	for z in range(resolution):
		for x in range(resolution):
			var i := z * row + x
			for k in [i, i + 1, i + row, i + 1, i + row + 1, i + row]:
				st.set_color(colors[k])
				st.add_vertex(verts[k])
	st.generate_normals()
	return st.commit()


## Высота поверхности земли в точке (x, z) — ровно та, что у меша make_terrain
## с теми же параметрами (та же сетка и та же разбивка на треугольники).
## Не зависит от физики, поэтому годится сразу после построения мира и
## даёт одинаковый результат у всех пиров.
static func terrain_height_at(size: float, resolution: int, seed_val: int, x: float, z: float) -> float:
	var noise := _terrain_noise(seed_val)
	var half := size / 2.0
	var step := size / resolution
	var fx := clampf((x + half) / step, 0.0, resolution - 0.0001)
	var fz := clampf((z + half) / step, 0.0, resolution - 0.0001)
	var gx := int(fx)
	var gz := int(fz)
	var u := fx - gx
	var v := fz - gz
	var h00 := noise.get_noise_2d(-half + gx * step, -half + gz * step) * TERRAIN_HEIGHT
	var h10 := noise.get_noise_2d(-half + (gx + 1) * step, -half + gz * step) * TERRAIN_HEIGHT
	var h01 := noise.get_noise_2d(-half + gx * step, -half + (gz + 1) * step) * TERRAIN_HEIGHT
	var h11 := noise.get_noise_2d(-half + (gx + 1) * step, -half + (gz + 1) * step) * TERRAIN_HEIGHT
	# Ячейка делится диагональю (1,0)–(0,1), как в make_terrain.
	if u + v <= 1.0:
		return h00 + (h10 - h00) * u + (h01 - h00) * v
	return h11 + (h01 - h11) * (1.0 - u) + (h10 - h11) * (1.0 - v)


static func _terrain_noise(seed_val: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.008
	noise.fractal_octaves = 4
	return noise


static func _terrain_color(h: float) -> Color:
	if h < -4.0:
		return TERRAIN_DIRT
	elif h < 0.0:
		return TERRAIN_DIRT.lerp(TERRAIN_GRASS_DARK, (h + 4.0) / 4.0)
	elif h < 3.0:
		return TERRAIN_GRASS_DARK.lerp(TERRAIN_GRASS_MID, h / 3.0)
	elif h < 6.0:
		return TERRAIN_GRASS_MID.lerp(TERRAIN_GRASS_LIGHT, (h - 3.0) / 3.0)
	else:
		return TERRAIN_GRASS_LIGHT.lerp(TERRAIN_ROCK, clamp((h - 6.0) / 6.0, 0.0, 1.0))


static func _apply_slope(color: Color, face_normal: Vector3) -> Color:
	# 1.0 — горизонтальная грань, 0.0 — вертикальная.
	var flatness := absf(face_normal.normalized().y)
	return color.lerp(TERRAIN_ROCK, 1.0 - smoothstep(0.7, 0.85, flatness))


static func flat_material(color: Color, rough: float = 0.9) -> ShaderMaterial:
	# Тоон-шейдер с rim lighting для low-poly стиля
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/char_toon.gdshader")
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("roughness", rough)
	mat.set_shader_parameter("metallic", 0.0)
	return mat


static func outline_material(color: Color = Color(0.05, 0.05, 0.08), width: float = 0.07) -> ShaderMaterial:
	# Outline-шейдер (inverted hull) для обводки
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/char_outline.gdshader")
	mat.set_shader_parameter("outline_color", color)
	mat.set_shader_parameter("outline_width", width)
	return mat


static func add_outline_to_mesh(mesh_instance: MeshInstance3D, color: Color = Color(0.05, 0.05, 0.08), width: float = 0.07) -> MeshInstance3D:
	# Создаёт дочерний MeshInstance3D с outline шейдером (inverted hull)
	var outline := MeshInstance3D.new()
	# Общие нормали в углах замыкают оболочку без разрывов между гранями.
	var outline_surface := SurfaceTool.new()
	outline_surface.create_from(mesh_instance.mesh, 0)
	outline_surface.generate_normals()
	outline.mesh = outline_surface.commit()
	outline.set_surface_override_material(0, outline_material(color, width))
	outline.name = mesh_instance.name + "Outline"
	mesh_instance.add_child(outline)
	return outline


static func terrain_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/terrain.gdshader")
	return mat


static func _add_box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var hx := size.x / 2.0
	var hy := size.y / 2.0
	var hz := size.z / 2.0

	var faces := [
		[Vector3(-hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, -hy, -hz), Vector3(0, 0, -1)],
		[Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, -hy, hz), Vector3(0, 0, 1)],
		[Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(hx, hy, -hz), Vector3(0, 1, 0)],
		[Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz), Vector3(-hx, -hy, -hz), Vector3(0, -1, 0)],
		[Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz), Vector3(1, 0, 0)],
		[Vector3(-hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, hy, -hz), Vector3(-hx, -hy, -hz), Vector3(-1, 0, 0)],
	]

	for face in faces:
		var normal: Vector3 = face[4]
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(center + face[0])
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(center + face[2])
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(center + face[1])

		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(center + face[0])
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(center + face[3])
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(center + face[2])
