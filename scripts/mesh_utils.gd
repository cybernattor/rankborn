class_name MeshUtils


static func make_box(size: Vector3, color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(st, Vector3.ZERO, size, color)
	return st.commit()


static func make_humanoid() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var torso_size := Vector3(0.5, 0.55, 0.3)
	var torso_pos := Vector3(0, 0.95, 0)
	var torso_col := Color(0.22, 0.38, 0.58)
	_add_box(st, torso_pos, torso_size, torso_col)

	var head_size := Vector3(0.28, 0.28, 0.28)
	var head_pos := Vector3(0, 1.48, 0)
	var head_col := Color(0.82, 0.68, 0.55)
	_add_box(st, head_pos, head_size, head_col)

	var helmet_size := Vector3(0.32, 0.16, 0.32)
	var helmet_pos := Vector3(0, 1.6, 0)
	var helmet_col := Color(0.25, 0.32, 0.2)
	_add_box(st, helmet_pos, helmet_size, helmet_col)

	var arm_size := Vector3(0.14, 0.45, 0.14)
	var arm_col := Color(0.22, 0.38, 0.58)
	_add_box(st, Vector3(-0.38, 0.9, 0), arm_size, arm_col)
	_add_box(st, Vector3(0.38, 0.9, 0), arm_size, arm_col)

	var hand_size := Vector3(0.1, 0.12, 0.1)
	var hand_col := Color(0.82, 0.68, 0.55)
	_add_box(st, Vector3(-0.38, 0.62, 0), hand_size, hand_col)
	_add_box(st, Vector3(0.38, 0.62, 0), hand_size, hand_col)

	var leg_size := Vector3(0.16, 0.5, 0.16)
	var leg_col := Color(0.2, 0.28, 0.18)
	_add_box(st, Vector3(-0.13, 0.42, 0), leg_size, leg_col)
	_add_box(st, Vector3(0.13, 0.42, 0), leg_size, leg_col)

	var boot_size := Vector3(0.17, 0.14, 0.22)
	var boot_col := Color(0.18, 0.15, 0.12)
	_add_box(st, Vector3(-0.13, 0.12, -0.02), boot_size, boot_col)
	_add_box(st, Vector3(0.13, 0.12, -0.02), boot_size, boot_col)

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

	return st.commit()


static func make_terrain(size: float, resolution: int, height: float, seed_val: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var half := size / 2.0
	var step := size / resolution

	var verts: Array[Vector3] = []
	for z in range(resolution + 1):
		for x in range(resolution + 1):
			var px := -half + x * step
			var pz := -half + z * step
			var py := rng.randf_range(-height, height)
			verts.append(Vector3(px, py, pz))

	for z in range(resolution):
		for x in range(resolution):
			var i := z * (resolution + 1) + x
			var v0 := verts[i]
			var v1 := verts[i + 1]
			var v2 := verts[i + resolution + 1]
			var v3 := verts[i + resolution + 2]

			var green := Color(
				rng.randf_range(0.18, 0.38),
				rng.randf_range(0.42, 0.62),
				rng.randf_range(0.12, 0.22)
			)
			var green2 := Color(
				rng.randf_range(0.15, 0.35),
				rng.randf_range(0.38, 0.58),
				rng.randf_range(0.1, 0.2)
			)

			st.set_color(green)
			st.add_vertex(v0)
			st.set_color(green)
			st.add_vertex(v2)
			st.set_color(green)
			st.add_vertex(v1)

			st.set_color(green2)
			st.add_vertex(v1)
			st.set_color(green2)
			st.add_vertex(v2)
			st.set_color(green2)
			st.add_vertex(v3)

	return st.commit()


static func flat_material(color: Color, rough: float = 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = 0.0
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
