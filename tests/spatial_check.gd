extends SceneTree

## Запуск: Godot --headless --path . --log-file .godot/spatial-check.log --script tests/spatial_check.gd
## Сеть: два процесса с дополнительными аргументами -- host и -- client.

var _failed: bool = false
var _deadline: int = Time.get_ticks_msec() + 25000


func _init() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline:
		push_error("Пространственная проверка не завершилась за 25 секунд")
		quit(1)
	return false


func _run() -> void:
	var network: Node = root.get_node("NetworkManager")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0] in ["host", "client"]:
		await _check_network(network, args[0])
		return
	_check_meshes()
	network.players = {1: {"name": "Host", "spawn_index": 0}, 7: {"name": "Remote", "spawn_index": 1}}
	var world := _load_world()
	await physics_frame
	await physics_frame
	var player: CharacterBody3D = world.get_node("Players/1")
	var remote: CharacterBody3D = world.get_node("Players/7")
	_check(player.camera.current and not remote.camera.current)
	_check(not player.body_mesh.visible and remote.body_mesh.visible)
	var hud: CanvasLayer = player.get_node("WeaponHUD")
	_check(hud.crosshair.global_position.is_equal_approx(root.get_visible_rect().size * 0.5), "Прицел смещён относительно центра камеры")
	for spawn: Marker3D in world.get_node("SpawnPoints").get_children():
		var query := PhysicsRayQueryParameters3D.create(spawn.global_position, spawn.global_position - Vector3.UP * 40.0, 1)
		var ground: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		_check(not ground.is_empty() and ground.collider == world.get_node("GroundBody"), "Маркер спавна находится под землёй")
	_check(player.get_node("WeaponHUD") != null and not remote.has_node("WeaponHUD"))
	_check(player.get_node("Head/Camera3D/WeaponPivot/Rifle").get_multiplayer_authority() == 1)
	_check(remote.get_node("Head/Camera3D/WeaponPivot/Rifle").get_multiplayer_authority() == 7)
	_check(player.spawn_position.distance_to(remote.spawn_position) > 1.0)
	var marker: Marker3D = world.get_node("SpawnPoints/Spawn2")
	marker.position.x += 1.0
	_check(world._get_spawn_position(7).is_equal_approx(marker.global_position))
	_check(world.get_node("SpawnPoints").get_child_count() >= network.MAX_CLIENTS + 1)
	_check(not world.has_node("TerrainSafetyFloor"))
	for wall: StaticBody3D in world.get_node("Boundaries").get_children():
		_check((wall.collision_layer & player.collision_mask) != 0)
		_check(maxf(absf(wall.position.x), absf(wall.position.z)) == 50.0)
	_check((world.get_node("KillZone").collision_mask & player.collision_layer) != 0)
	player.state_machine.set_physics_process(false)
	player.set_process(false)
	var rifle: Node3D = player.get_node("Head/Camera3D/WeaponPivot/Rifle")
	rifle.set_process(false)
	if "render" in args:
		remote.state_machine.set_physics_process(false)
		player.global_position = Vector3(0, 0, 4)
		remote.global_position = Vector3.ZERO
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/spatial-preview.png")
	player.global_position = Vector3(0, 20, 0)
	remote.global_position = Vector3(30, 20, 30)
	await _check_shots(world, player, rifle)
	player.health_component.take_damage(9999.0)
	await process_frame
	_check(not player.visible and player.get_node("CollisionShape3D").disabled)
	_check(world.game_mode.get_score(1).deaths == 1)
	await create_timer(2.2).timeout
	_check(player.visible and not player.get_node("CollisionShape3D").disabled)
	_check(not player.body_mesh.visible and player.health_component.is_alive)
	player.global_position = Vector3(0, -20, 0)
	await create_timer(0.15).timeout
	_check(not player.health_component.is_alive, "Зона смерти не обнаруживает упавшего игрока")
	if _failed:
		quit(1)
		return
	print("PASS: геометрия, камера, спавн, границы, выстрелы, эффекты, смерть и респавн")
	world.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _load_world() -> Node3D:
	var packed: PackedScene = load("res://scenes/game/game_scene.tscn")
	var world: Node3D = packed.instantiate()
	root.add_child(world)
	current_scene = world
	return world


func _check_meshes() -> void:
	for mesh: ArrayMesh in [MeshUtils.make_box(Vector3.ONE, Color.WHITE), MeshUtils.make_humanoid(), MeshUtils.make_rifle()]:
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(0, vertices.size(), 3):
			var normal := (vertices[i + 2] - vertices[i]).cross(vertices[i + 1] - vertices[i]).normalized()
			_check(normal.dot(normals[i]) > 0.99, "Порядок вершин не совпадает с нормалью")
	var humanoid := MeshUtils.make_humanoid()
	_check(is_zero_approx(humanoid.get_aabb().position.y), "Подошвы должны касаться земли")
	var vertices: PackedVector3Array = humanoid.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var parts: Array[AABB] = []
	for i in range(0, vertices.size(), 36):
		var bounds := AABB(vertices[i], Vector3.ZERO)
		for j in range(i, i + 36):
			bounds = bounds.expand(vertices[j])
		parts.append(bounds.grow(0.0001))
	var connected: Array[int] = [0]
	for i in connected:
		for j in range(parts.size()):
			if j not in connected and parts[i].intersects(parts[j]):
				connected.append(j)
	_check(connected.size() == parts.size(), "Части персонажа висят отдельно")
	var terrain := MeshUtils.make_terrain(100.0, 30, 42)
	var terrain_vertices: PackedVector3Array = terrain.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var faces := terrain.create_trimesh_shape().get_faces()
	_check(faces.size() == terrain_vertices.size())
	for i in range(faces.size()):
		_check(faces[i].distance_to(terrain_vertices[i]) < 0.001, "Коллизия отличается от меша земли")


func _check_shots(world: Node3D, player: CharacterBody3D, rifle: Node3D) -> void:
	var target := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 1)
	shape.shape = box
	target.add_child(shape)
	world.add_child(target)
	for yaw in [0.0, PI / 2.0, PI]:
		player.rotation.y = yaw
		player.head.rotation.x = 0.0
		target.global_position = player.camera.global_position - player.camera.global_basis.z * 10.0
		await physics_frame
		await physics_frame
		rifle._apply_bullet_spread()
		_check(rifle.raycast.global_position.is_equal_approx(player.camera.global_position))
		_check(rifle.raycast.get_collider() == target, "Выстрел должен следовать камере")
		var projected: Vector2 = player.camera.unproject_position(rifle.raycast.get_collision_point())
		var center := root.get_visible_rect().size * 0.5
		var radius: float = tan(rifle.get_spread_angle()) * center.y / tan(deg_to_rad(player.camera.fov) * 0.5)
		_check(absf(projected.x - center.x) <= radius + 1.0 and absf(projected.y - center.y) <= radius + 1.0)
	var tip: Vector3 = rifle.rifle_mesh.position + Vector3(0, 0, rifle.rifle_mesh.mesh.get_aabb().position.z)
	_check(tip.is_equal_approx(rifle.muzzle_flash.position))
	var outline: MeshInstance3D = rifle.rifle_mesh.get_child(0)
	var outline_arrays := outline.mesh.surface_get_arrays(0)
	var outline_vertices: PackedVector3Array = outline_arrays[Mesh.ARRAY_VERTEX]
	var outline_normals: PackedVector3Array = outline_arrays[Mesh.ARRAY_NORMAL]
	var corners: Dictionary = {}
	for i in range(outline_vertices.size()):
		if corners.has(outline_vertices[i]):
			_check(corners[outline_vertices[i]].is_equal_approx(outline_normals[i]), "Обводка разрывается в углах")
		corners[outline_vertices[i]] = outline_normals[i]
	var base: Transform3D = rifle.transform
	for i in range(3):
		rifle.can_fire = true
		rifle.shoot()
		_check(rifle._base_transform.is_equal_approx(base), "Базовая позиция отдачи дрейфует")
		var ammo: int = rifle.current_ammo
		rifle.shoot()
		_check(rifle.current_ammo == ammo, "Повторный вызов обходит задержку выстрела")
		rifle._process(0.1)
		rifle.current_ammo = 30
	for i in range(120):
		rifle._process(1.0 / 60.0)
	_check(rifle.transform.is_equal_approx(base))
	var origin := Vector3(0, 20, 0)
	for direction in [Vector3.RIGHT, Vector3.UP, Vector3.DOWN]:
		rifle._spawn_tracer(origin, origin + direction * 10.0)
		var tracer: MeshInstance3D = world.get_child(world.get_child_count() - 1)
		_check((-tracer.global_basis.z).dot(direction) > 0.999)
	rifle._spawn_impact(origin, Vector3.UP)
	var scorch: MeshInstance3D = rifle._scorch_marks.back()
	_check(scorch.global_basis.z.dot(Vector3.UP) > 0.999)
	rifle._spawn_blood(origin, Vector3.UP)
	var blood: Node3D = world.get_child(world.get_child_count() - 1)
	_check(blood.get_node("BloodDrops") is GPUParticles3D and blood.get_node("BloodMist") is GPUParticles3D)
	target.queue_free()


func _check_network(network: Node, mode: String) -> void:
	if mode == "host":
		network.host_game(17000)
	else:
		network.join_game("127.0.0.1", 17000)
	while network.players.size() < 2:
		await process_frame
	_deadline = Time.get_ticks_msec() + 15000
	var ids: Array = network.players.keys()
	_check(network.players[ids[0]].spawn_index != network.players[ids[1]].spawn_index)
	var world := _load_world()
	await create_timer(0.5).timeout
	var own_id := world.multiplayer.get_unique_id()
	var own: CharacterBody3D = world.get_node("Players/%d" % own_id)
	var remote_id: int = ids[0] if ids[0] != own_id else ids[1]
	var remote: CharacterBody3D = world.get_node("Players/%d" % remote_id)
	_check(own.camera.current and not remote.camera.current)
	_check(not own.body_mesh.visible and remote.body_mesh.visible)
	_check(own.spawn_position.distance_to(remote.spawn_position) > 1.0)
	if mode == "host":
		own.health_component.take_damage(9999.0, remote_id)
	else:
		while remote.health_component.is_alive:
			await process_frame
		await process_frame
		_check(not remote.visible and remote.get_node("CollisionShape3D").disabled)
		while not remote.health_component.is_alive:
			await process_frame
		await process_frame
		_check(remote.visible and not remote.get_node("CollisionShape3D").disabled)
		own.health_component.take_damage(9999.0, remote_id)
	if mode == "host":
		while remote.health_component.is_alive:
			await process_frame
		await process_frame
		_check(not remote.visible and remote.get_node("CollisionShape3D").disabled)
		while not remote.health_component.is_alive:
			await process_frame
		await process_frame
		_check(remote.visible and not remote.get_node("CollisionShape3D").disabled)
		_check(world.game_mode.get_score(1).deaths == 1)
		_check(world.game_mode.get_score(remote_id).deaths == 1)
	else:
		while not own.health_component.is_alive:
			await process_frame
	await create_timer(0.3).timeout
	if _failed:
		quit(1)
		return
	print("PASS: сеть %s — своя камера, уникальный спавн, смерть и респавн обоих игроков" % mode)
	network.disconnect_game()
	world.free()
	quit(1 if _failed else 0)


func _check(condition: bool, message: String = "Нарушено пространственное условие") -> void:
	if not condition:
		_failed = true
		push_error(message)
