class_name MeshUtils


static func make_box(size: Vector3, color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(st, Vector3.ZERO, size, color)
	return st.commit()


static func make_humanoid() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_add_box(st, Vector3(0, 0.95, 0), Vector3(0.5, 0.55, 0.3), Color(0.22, 0.38, 0.58))
	_add_box(st, Vector3(0, 1.48, 0), Vector3(0.28, 0.28, 0.28), Color(0.82, 0.68, 0.55))
	_add_box(st, Vector3(0, 1.6, 0), Vector3(0.32, 0.16, 0.32), Color(0.25, 0.32, 0.2))
	_add_box(st, Vector3(-0.38, 0.9, 0), Vector3(0.14, 0.45, 0.14), Color(0.22, 0.38, 0.58))
	_add_box(st, Vector3(0.38, 0.9, 0), Vector3(0.14, 0.45, 0.14), Color(0.22, 0.38, 0.58))
	_add_box(st, Vector3(-0.38, 0.62, 0), Vector3(0.1, 0.12, 0.1), Color(0.82, 0.68, 0.55))
	_add_box(st, Vector3(0.38, 0.62, 0), Vector3(0.1, 0.12, 0.1), Color(0.82, 0.68, 0.55))
	_add_box(st, Vector3(-0.13, 0.42, 0), Vector3(0.16, 0.5, 0.16), Color(0.2, 0.28, 0.18))
	_add_box(st, Vector3(0.13, 0.42, 0), Vector3(0.16, 0.5, 0.16), Color(0.2, 0.28, 0.18))
	_add_box(st, Vector3(-0.13, 0.12, -0.02), Vector3(0.17, 0.14, 0.22), Color(0.18, 0.15, 0.12))
	_add_box(st, Vector3(0.13, 0.12, -0.02), Vector3(0.17, 0.14, 0.22), Color(0.18, 0.15, 0.12))

	st.generate_normals()
	return st.commit()


static func make_rifle() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var metal := Color(0.15, 0.15, 0.18)
	var wood := Color(0.35, 0.22, 0.12)
	var dark := Color(0.1, 0.1, 0.12)

	_add_box(st, Vector3(0, 0, -0.35), Vector3(0.04, 0.04, 0.35), metal)
	_add_box(st, Vector3(0, -0.01, -0.05), Vector3(0.06, 0.07, 0.25), metal)
	_add_box(st, Vector3(0, -0.04, 0.18), Vector3(0.05, 0.04, 0.18), wood)
	_add_box(st, Vector3(0, -0.08, -0.1), Vector3(0.035, 0.1, 0.06), dark)
	_add_box(st, Vector3(0, 0.03, -0.08), Vector3(0.025, 0.025, 0.06), metal)
	_add_box(st, Vector3(0, 0, -0.52), Vector3(0.015, 0.035, 0.02), metal)

	st.generate_normals()
	return st.commit()


static func make_terrain(size: float, resolution: int, seed_val: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.008
	noise.fractal_octaves = 4

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := size / 2.0
	var step := size / resolution

	var verts: Array[Vector3] = []
	for z in range(resolution + 1):
		for x in range(resolution + 1):
			var px := -half + x * step
			var pz := -half + z * step
			var py := noise.get_noise_2d(px, pz) * 12.0
			verts.append(Vector3(px, py, pz))

	var dirt := Color(0.55, 0.38, 0.22)
	var grass_dark := Color(0.25, 0.50, 0.18)
	var grass_mid := Color(0.35, 0.62, 0.22)
	var grass_light := Color(0.48, 0.72, 0.30)
	var rock := Color(0.55, 0.52, 0.48)

	for z in range(resolution):
		for x in range(resolution):
			var i := z * (resolution + 1) + x
			var v0 := verts[i]
			var v1 := verts[i + 1]
			var v2 := verts[i + resolution + 1]
			var v3 := verts[i + resolution + 2]

			var avg_h1 := (v0.y + v1.y + v2.y) / 3.0
			var avg_h2 := (v1.y + v2.y + v3.y) / 3.0
			var c1 := _terrain_color(avg_h1, dirt, grass_dark, grass_mid, grass_light, rock)
			var c2 := _terrain_color(avg_h2, dirt, grass_dark, grass_mid, grass_light, rock)

			st.set_color(c1)
			st.add_vertex(v0)
			st.set_color(c1)
			st.add_vertex(v1)
			st.set_color(c1)
			st.add_vertex(v2)

			st.set_color(c2)
			st.add_vertex(v1)
			st.set_color(c2)
			st.add_vertex(v3)
			st.set_color(c2)
			st.add_vertex(v2)

	st.generate_normals()
	return st.commit()


static func _terrain_color(h: float, dirt: Color, g_dark: Color, g_mid: Color, g_light: Color, rock: Color) -> Color:
	if h < -4.0:
		return dirt
	elif h < 0.0:
		return dirt.lerp(g_dark, (h + 4.0) / 4.0)
	elif h < 3.0:
		return g_dark.lerp(g_mid, h / 3.0)
	elif h < 6.0:
		return g_mid.lerp(g_light, (h - 3.0) / 3.0)
	else:
		return g_light.lerp(rock, clamp((h - 6.0) / 6.0, 0.0, 1.0))


static func flat_material(color: Color, rough: float = 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = 0.0
	mat.flat_shading = true
	return mat


static func terrain_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.flat_shading = true
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
		st.add_vertex(center + face[1])
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(center + face[2])

		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(center + face[0])
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(center + face[2])
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(center + face[3])
