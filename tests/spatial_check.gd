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
	_check_lobby_network(network)
	network.players = {1: {"name": "Host", "spawn_index": 0}, 7: {"name": "Remote", "spawn_index": 1}}
	var world := _load_world()
	await physics_frame
	await physics_frame
	var player: CharacterBody3D = world.get_node("Players/1")
	var remote: CharacterBody3D = world.get_node("Players/7")
	# В headless курсор стоит в углу окна — целимся «стиком», чтобы направление задавал тест.
	player._mouse_aim = false
	_check(player.camera.current and not remote.camera.current)
	# Камера сверху: своё тело видно целиком, камера над игроком и смотрит вниз.
	_check(player.body_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "Своё тело не рисуется")
	_check(player.camera.global_position.y > player.global_position.y + 10.0 and player.camera.global_basis.z.y > 0.5, "Камера не сверху")
	_check(is_zero_approx(player.camera.global_rotation.y), "Камера вращается вместе с игроком")
	# Ждём, пока камера доедет до игрока (следует плавно).
	for i in 60:
		await process_frame
	var hud: CanvasLayer = player.get_node("WeaponHUD")
	var aim_on_screen: Vector2 = player.camera.unproject_position(player.aim_point)
	_check(hud.crosshair.position.distance_to(aim_on_screen) < 1.0, "Прицел HUD не в точке прицеливания")
	_check_covers(world)
	await _check_fog(world, player, remote)
	await _check_sight_and_steps(world, player, remote)
	for spawn: Marker3D in world.get_node("SpawnPoints").get_children():
		var query := PhysicsRayQueryParameters3D.create(spawn.global_position, spawn.global_position - Vector3.UP * 40.0, 1)
		var ground: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		_check(not ground.is_empty() and ground.collider == world.get_node("GroundBody"), "Маркер спавна находится под землёй")
	_check_spawn_on_ground(world, player)
	_check_graphics(world)
	_check(player.get_node("WeaponHUD") != null and not remote.has_node("WeaponHUD"))
	_check(player.get_node("Head/WeaponPivot/Rifle").get_multiplayer_authority() == 1)
	_check(remote.get_node("Head/WeaponPivot/Rifle").get_multiplayer_authority() == 7)
	_check(player.spawn_position.distance_to(remote.spawn_position) > 1.0)
	var marker: Marker3D = world.get_node("SpawnPoints/Spawn2")
	marker.position.x += 1.0
	var moved: Vector3 = world._get_spawn_position(7)
	_check(is_equal_approx(moved.x, marker.global_position.x) and is_equal_approx(moved.z, marker.global_position.z), "Точка спавна не следует за маркером")
	_check(world.get_node("SpawnPoints").get_child_count() >= network.MAX_CLIENTS + 1)
	_check(not world.has_node("TerrainSafetyFloor"))
	for wall: StaticBody3D in world.get_node("Boundaries").get_children():
		_check((wall.collision_layer & player.collision_mask) != 0)
		_check(maxf(absf(wall.position.x), absf(wall.position.z)) == 50.0)
	_check((world.get_node("KillZone").collision_mask & player.collision_layer) != 0)
	player.state_machine.set_physics_process(false)
	player.set_process(false)
	var rifle: Node3D = player.get_node("Head/WeaponPivot/Rifle")
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
	player.set_process(true)  # камера смерти живёт в _process
	player.health_component.take_damage(9999.0, 7)
	await process_frame
	_check(not player.visible and player.get_node("CollisionShape3D").disabled)
	# Экран смерти: кто убил, HUD оружия скрыт, камера падает к земле.
	_check(player.death_screen.is_shown() and "Remote" in player.death_screen.get_killer_text(), "Нет экрана смерти с ником убийцы")
	_check(not player.weapon_hud.visible, "HUD оружия виден после смерти")
	await create_timer(1.0).timeout
	_check(world.game_mode.get_score(1).deaths == 1)
	# Перед смертью смотрим вбок — после респавна взгляд должен вернуться к центру карты.
	player.rotation.y = PI * 0.5
	player._aim_direction = Vector3.RIGHT
	await create_timer(1.2).timeout
	_check(player.visible and not player.get_node("CollisionShape3D").disabled)
	_check(not player.death_screen.is_shown() and player.weapon_hud.visible, "Экран смерти не скрылся после респавна")
	var to_center: Vector3 = (player.MAP_CENTER - player.global_position) * Vector3(1, 0, 1)
	_check((-player.global_basis.z).dot(to_center.normalized()) > 0.99, "После респавна игрок смотрит не к центру карты")
	_check(player.get_aim_direction().dot(to_center.normalized()) > 0.99, "После респавна прицел не к центру карты")
	_check(player.body_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and player.health_component.is_alive)
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
	var terrain := MeshUtils.make_terrain(100.0, 60, 42)
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
	# Выстрел летит от оружия в сторону точки прицеливания и укладывается в конус разброса.
	for dir: Vector3 in [Vector3.FORWARD, Vector3.RIGHT, Vector3(-1, 0, 1).normalized()]:
		player._aim_direction = dir
		var origin: Vector3 = player.get_shot_origin()
		player.aim_point = origin + dir * 10.0
		target.global_position = origin + dir * 10.0
		target.global_basis = Basis.looking_at(dir)
		await physics_frame
		await physics_frame
		rifle._apply_bullet_spread()
		_check(rifle.raycast.global_position.is_equal_approx(origin), "Выстрел вылетает не из оружия")
		_check(rifle.raycast.get_collider() == target, "Выстрел не летит в сторону прицела")
		var shot: Vector3 = rifle.raycast.get_collision_point() - origin
		_check(shot.angle_to(dir) <= rifle.get_spread_angle() * 1.06 + 0.001, "Выстрел вне конуса разброса")
	# Прицеливание как у Foxhole: конус сводится за AIM_TIME, а не сразу; выстрел сбивает сведение.
	player.is_aiming = false
	player._update_aim_progress(0.1)
	var hip: float = rifle.get_spread_angle()
	player.is_aiming = true
	player._update_aim_progress(player.AIM_TIME * 0.25)
	var quarter: float = rifle.get_spread_angle()
	_check(quarter < hip and quarter > hip * 0.5, "Прицел сводится мгновенно, а не постепенно")
	player._update_aim_progress(player.AIM_TIME)
	_check(is_equal_approx(player.aim_progress, 1.0) and rifle.get_spread_angle() < hip * 0.25, "Сведённый прицел не сужает разброс")
	player.on_shot_fired()
	_check(player.aim_progress < 0.5, "Выстрел не сбивает сведение прицела")
	player.is_aiming = false
	player._update_aim_progress(0.1)
	_check(is_zero_approx(player.aim_progress), "Сведение остаётся после отпускания прицела")
	# Винтовка как у Foxhole: обойма 5, затвор ~1 с, три попадания на убийство.
	_check(rifle.magazine_size == 5 and rifle.fire_rate >= 1.0 and ceili(player.health_component.max_health / rifle.damage) == 3,
			"Винтовка не как у Foxhole")
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
	# Звук выстрела — в мире у дула (его слышат все, с направлением), затвор — следом;
	# прогрев эффектов в начале матча беззвучный. Слушатель — у солдата, а не у камеры.
	var sounds_before := _shot_sounds(world).size()
	rifle.prewarm_effects(player.global_position + Vector3.FORWARD * 4.0)
	_check(_shot_sounds(world).size() == sounds_before, "Прогрев эффектов играет звук выстрела")
	rifle._shoot_effects(rifle.muzzle_flash.global_position)
	var sounds := _shot_sounds(world)
	_check(sounds.size() == sounds_before + 1 and sounds.back().global_position.distance_to(rifle.muzzle_flash.global_position) < 0.01,
			"Выстрел не звучит у дула")
	await create_timer(rifle.BOLT_SOUND_DELAY + 0.1).timeout
	_check(world.get_children().any(func(n): return n is AudioStreamPlayer3D and n.stream.resource_path.ends_with("rifle_bolt.wav")),
			"Нет звука затвора")
	player.set_process(true)
	await process_frame
	await process_frame
	player.set_process(false)
	_check(player.ears.is_current() and player.ears.global_position.distance_to(player.global_position) < 2.0, "Слушатель не у солдата")
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
	rifle._spawn_impact(origin, Vector3.UP)
	_check(rifle._scorch_marks.back().mesh == scorch.mesh, "Ресурсы эффектов попадания пересоздаются на каждый выстрел")
	rifle._spawn_blood(origin, Vector3.UP)
	var blood: Node3D = world.get_child(world.get_child_count() - 1)
	_check(blood.get_node("BloodDrops") is GPUParticles3D and blood.get_node("BloodMist") is GPUParticles3D)
	var children_before := world.get_child_count()
	rifle._spawn_blood(origin, Vector3.UP, world.multiplayer.get_unique_id())
	_check(world.get_child_count() == children_before, "У жертвы брызги крови появляются перед камерой")
	_check_hud(player)
	target.queue_free()


func _shot_sounds(world: Node3D) -> Array:
	return world.get_children().filter(func(n): return n is AudioStreamPlayer3D and n.stream.resource_path.ends_with("rifle_shot.wav"))


## Игроки появляются на земле, а не в воздухе: формула высоты совпадает с
## настоящей коллизией земли, и точка спавна стоит прямо на поверхности.
func _check_spawn_on_ground(world: Node3D, player: CharacterBody3D) -> void:
	var space := world.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var points: Array[Vector2] = []
	for m: Marker3D in world.get_node("SpawnPoints").get_children():
		points.append(Vector2(m.global_position.x, m.global_position.z))
	for i in 100:
		points.append(Vector2(rng.randf_range(-49.0, 49.0), rng.randf_range(-49.0, 49.0)))
	for p in points:
		var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 40, p.y), Vector3(p.x, -40, p.y), 1)
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty() and hit.collider != world.get_node("GroundBody"):
			continue  # попали в укрытие
		var formula := MeshUtils.terrain_height_at(world.TERRAIN_SIZE, world.TERRAIN_RESOLUTION, world.TERRAIN_SEED, p.x, p.y)
		_check(not hit.is_empty() and absf(hit.position.y - formula) < 0.01, "Высота земли по формуле не совпадает с коллизией")
	var below := PhysicsRayQueryParameters3D.create(player.spawn_position + Vector3.UP, player.spawn_position - Vector3.UP * 5, 1)
	var ground: Dictionary = space.intersect_ray(below)
	_check(not ground.is_empty() and player.spawn_position.y - ground.position.y < 0.2, "Игрок появляется в воздухе")


## Укрытия стоят на земле (не висят над склоном) и останавливают выстрелы и взгляд.
func _check_covers(world: Node3D) -> void:
	var covers: Array[Node] = world.get_node("Covers").get_children()
	_check(covers.size() >= 8, "Мало укрытий")
	for cover: StaticBody3D in covers:
		_check(cover.collision_layer == 1, "Укрытие не на слое мира")
		var box: BoxShape3D = cover.get_child(0).shape
		var bottom: float = cover.global_position.y - box.size.y * 0.5
		for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
			var p: Vector3 = cover.global_transform * (corner * box.size * 0.5 * Vector3(1, 0, 1))
			_check(world.ground_height_at(p.x, p.z) >= bottom, "Укрытие висит над землёй")


## Туман войны: хост считает видимость; спрятанный за стеной или далёкий игрок
## не рисуется и не ловит пули.
func _check_fog(world: Node3D, player: CharacterBody3D, remote: CharacterBody3D) -> void:
	var manager: Node = world.get_node("VisibilityManager")
	var place := func(body: Node3D, x: float, z: float) -> void:
		body.global_position = Vector3(x, world.ground_height_at(x, z) + 0.05, z)
	# Стена 6 × 2.2 м в центре карты вдоль оси X.
	place.call(player, 0.0, -4.0)
	place.call(remote, 0.0, 4.0)
	await physics_frame
	_check(not manager.can_see(player, remote), "Стена не закрывает видимость")
	manager.apply_visibility(manager.compute_visibility()[1])
	_check(remote.fog_hidden and not remote.visible, "Спрятанный за стеной игрок виден")
	await physics_frame
	_check(remote.collision_shape.disabled, "Спрятанный игрок ловит пули")
	place.call(remote, 10.0, 4.0)
	await physics_frame
	_check(manager.can_see(player, remote), "Игрок сбоку от стены не виден")
	manager.apply_visibility(manager.compute_visibility()[1])
	_check(not remote.fog_hidden and remote.visible, "Видимый игрок спрятан")
	place.call(remote, 0.0, -4.0 - manager.VIEW_RANGE - 2.0)
	await physics_frame
	_check(not manager.can_see(player, remote), "Видно дальше дальности обзора")
	# Стоящего видно поверх мешков с песком, присевшего — нет.
	place.call(player, -16.0, 11.0)
	place.call(remote, -16.0, 17.0)
	await physics_frame
	_check(manager.can_see(player, remote), "Стоящего не видно поверх мешков")
	player.is_crouching = true
	remote.is_crouching = true
	await physics_frame
	_check(not manager.can_see(player, remote), "Присевших видно сквозь мешки")
	player.is_crouching = false
	remote.is_crouching = false
	player.global_position = player.spawn_position
	remote.global_position = remote.spawn_position
	await physics_frame
	await physics_frame


## Прицел не проходит сквозь стены; шаги слышны на ходу и не слышны в приседе и издалека;
## индикатор «тебя видят» следует списку от хоста.
func _check_sight_and_steps(world: Node3D, player: CharacterBody3D, remote: CharacterBody3D) -> void:
	var manager: Node = world.get_node("VisibilityManager")
	var place := func(body: Node3D, x: float, z: float) -> void:
		body.global_position = Vector3(x, world.ground_height_at(x, z) + 0.05, z)
	# Стена 6 × 2.2 м в центре вдоль оси X: целимся сквозь неё.
	place.call(player, 0.0, -4.0)
	await physics_frame
	player._aim_direction = Vector3.BACK
	player.aim_point = player.get_shot_origin() + Vector3.BACK * 10.0
	var sight: Vector3 = player._compute_sight_point()
	_check(sight.z < 0.0 and sight.z > -1.0, "Прицел проходит сквозь стену: %s" % sight)
	player.aim_point = player.get_shot_origin() + Vector3.LEFT * 5.0
	_check(player._compute_sight_point().is_equal_approx(player.aim_point), "Прицел обрезан без препятствия")
	# Шаги: идёт — слышно, присел (медленно) — тихо, далеко — не слышно.
	place.call(player, -10.0, 26.0)
	place.call(remote, -14.0, 26.0)
	await physics_frame
	var walk := func(speed: float, seconds: float) -> int:
		var before := _sounds(world, "step.wav").size()
		manager._last_position.clear()
		manager._speed.clear()
		var frames := int(seconds * 60.0)
		for i in frames:
			remote.global_position += Vector3.FORWARD * speed / 60.0
			manager._update_steps(1.0 / 60.0)
		return _sounds(world, "step.wav").size() - before
	_check(walk.call(5.0, 1.5) >= 3, "Шагов не слышно на ходу")
	_check(walk.call(2.5, 1.5) == 0, "Шаги слышны в приседе")
	place.call(remote, -10.0 - manager.HEARING_RANGE - 5.0, 26.0)
	await physics_frame
	_check(walk.call(5.0, 1.5) == 0, "Шаги слышны дальше радиуса слышимости")
	# Индикатор видимости.
	manager.apply_visibility([7])
	_check(manager.is_seen, "Пир не знает, что его видят")
	manager.apply_visibility([])
	_check(not manager.is_seen, "Пир не знает, что он скрыт")
	player.global_position = player.spawn_position
	remote.global_position = remote.spawn_position
	await physics_frame
	await physics_frame


func _sounds(world: Node3D, file: String) -> Array:
	return world.get_children().filter(func(n): return n is AudioStreamPlayer3D and n.stream.resource_path.ends_with(file))


## Пресеты графики применяются к окну и солнцу и переключаются на лету.
func _check_graphics(world: Node3D) -> void:
	var settings: Node = root.get_node("GameSettings")
	var sun: DirectionalLight3D = world.get_node("DirectionalLight3D")
	var saved: int = settings.graphics_quality
	_check(settings.default_quality() == settings.Quality.HIGH, "На ПК графика по умолчанию не высокая")
	settings.graphics_quality = settings.Quality.LOW
	settings.changed.emit()
	_check(not sun.shadow_enabled and root.scaling_3d_scale < 1.0 and root.msaa_3d == Viewport.MSAA_DISABLED \
			and not settings.dynamic_lights_enabled(), "Низкая графика не применилась")
	settings.graphics_quality = settings.Quality.HIGH
	settings.changed.emit()
	_check(sun.shadow_enabled and is_equal_approx(root.scaling_3d_scale, 1.0) \
			and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS \
			and settings.dynamic_lights_enabled(), "Высокая графика не применилась")
	# «Авто»: медленные кадры снижают пресет на ступень, быстрые — нет.
	var saved_auto: int = settings.auto_quality_level
	settings.graphics_quality = settings.Quality.HIGH
	settings.set_quality_choice(settings.QUALITY_AUTO)
	_check(settings.is_auto_quality() and settings.get_quality() == settings.Quality.HIGH, "«Авто» на ПК начинает не с высокой")
	# Без типа AutoQuality: скрипт теста компилируется раньше автозагрузок, а класс ссылается на GameSettings.
	var auto_quality: Node = world.get_node("AutoQuality")
	for i in 600:
		auto_quality.add_frame(1.0 / 60.0)
	_check(settings.get_quality() == settings.Quality.HIGH, "«Авто» снизило графику при 60 FPS")
	# Снижает по ступени, с паузой на замер после каждой смены.
	var steps: Array[int] = []
	for i in 600:
		auto_quality.add_frame(1.0 / 20.0)
		if steps.is_empty() or steps.back() != settings.get_quality():
			steps.append(settings.get_quality())
	_check(steps == [settings.Quality.HIGH, settings.Quality.MEDIUM, settings.Quality.LOW] and not sun.shadow_enabled,
			"«Авто» не снижает графику по ступени при 20 FPS: %s" % [steps])
	settings.graphics_quality = saved
	settings.auto_quality_level = saved_auto
	settings.save_settings()


func _check_hud(player: CharacterBody3D) -> void:
	var hud: CanvasLayer = player.get_node("WeaponHUD")
	# Просадка FPS (кадр 0.2 с) с прицеливанием туда-обратно: прицел не должен улететь.
	player.is_aiming = true
	var ads_spread: float = hud._calculate_spread()
	player.is_aiming = false
	var hip_spread: float = hud._calculate_spread()
	for i in 8:
		player.is_aiming = i % 2 == 0
		hud._update_crosshair_spread(0.2)
	player.is_aiming = false
	_check(hud._current_spread >= minf(ads_spread, hip_spread) - 0.5 and hud._current_spread <= maxf(ads_spread, hip_spread) + 0.5,
			"Разброс прицела расходится при низком FPS")
	_check(not hud.has_node("UILayer/ScopeOverlay"), "Осталась оптика от первого лица")


## Туман войны по сети: спрятавшийся за стеной не рисуется у другого и не шлёт ему
## свою позицию; хосту позиции приходят всегда — он считает видимость.
func _check_network_fog(world: Node3D, own: CharacterBody3D, remote: CharacterBody3D, mode: String) -> void:
	await _wait_until(func(): return not remote.fog_hidden)
	# Расходимся по разные стороны центральной стены (6 × 2.2 м вдоль оси X).
	_place(world, own, Vector2(0.0, -4.0 if mode == "host" else 4.0))
	await _wait_until(func(): return remote.fog_hidden)
	await physics_frame  # коллизия отключается отложенно
	_check(not remote.visible and remote.collision_shape.disabled, "Спрятанный за стеной игрок виден")
	var seen_at: Vector3 = remote.global_position
	await create_timer(0.4).timeout
	# Оба сдвигаются вдоль стены, оставаясь за ней.
	_place(world, own, Vector2(1.5, own.global_position.z))
	await create_timer(1.0).timeout
	if mode == "client":
		_check(remote.global_position.is_equal_approx(seen_at), "Хост шлёт свою позицию тому, кто его не видит")
	else:
		_check(not remote.global_position.is_equal_approx(seen_at), "Хост не получает позицию скрытого игрока")
	# Снова на открытое место — видят друг друга.
	_place(world, own, Vector2(-4.0 if mode == "host" else 4.0, 8.0))
	await _wait_until(func(): return not remote.fog_hidden)
	_check(remote.visible, "Вышедший из-за стены игрок не появился")


func _place(world: Node3D, body: CharacterBody3D, xz: Vector2) -> void:
	body.velocity = Vector3.ZERO
	body.global_position = Vector3(xz.x, world.ground_height_at(xz.x, xz.y) + 0.05, xz.y)


func _wait_until(condition: Callable) -> void:
	while not condition.call():
		await process_frame


func _check_lobby_network(network: Node) -> void:
	_check(network.sanitize_name("  ", 12345) == "Игрок_2345")
	_check(network.sanitize_name("  Очень-длинный-ник-бойца  ", 1).length() == network.MAX_NAME_LENGTH)
	var has_external := false
	for addr in IP.get_local_addresses():
		if addr.split(".").size() == 4 and not addr.begins_with("127.") and not addr.begins_with("169.254."):
			has_external = true
	if has_external:
		_check(not network.get_lan_ip().begins_with("127."), "Хост показывает друзьям 127.0.0.1")
	# Одно лобби приходит по LAN и по loopback — в списке одна строка с LAN-адресом.
	var discovery: Node = root.get_node("LanDiscovery")
	discovery._found.clear()
	var announce := {"host_id": "abc", "port": 7000, "name": "Лобби", "players": 2, "max_players": 6}
	discovery._register_game(announce, "192.168.1.5")
	discovery._register_game(announce, "127.0.0.1")
	var games: Array = discovery.get_games()
	_check(games.size() == 1 and games[0].ip == "192.168.1.5", "Одно лобби показывается дважды")
	discovery._found.clear()


func _check_network(network: Node, mode: String) -> void:
	var settings: Node = root.get_node("GameSettings")
	settings.player_name = "Хост" if mode == "host" else "Клиент"
	var disconnected := [false]
	network.server_disconnected.connect(func(): disconnected[0] = true)
	if mode == "host":
		network.host_game(17000)
	else:
		network.join_game("127.0.0.1", 17000)
	while network.players.size() < 2:
		await process_frame
	_deadline = Time.get_ticks_msec() + 30000
	var ids: Array = network.players.keys()
	# Ник клиента приходит хосту отдельным RPC и рассылается всем.
	while network.players.values().filter(func(p): return p.name == "Клиент").is_empty():
		await process_frame
	_check(network.players[1].name == "Хост", "Ник хоста не виден в лобби")
	_check(network.players[ids[0]].spawn_index != network.players[ids[1]].spawn_index)
	var world := _load_world()
	await create_timer(0.5).timeout
	var own_id := world.multiplayer.get_unique_id()
	var own: CharacterBody3D = world.get_node("Players/%d" % own_id)
	var remote_id: int = ids[0] if ids[0] != own_id else ids[1]
	var remote: CharacterBody3D = world.get_node("Players/%d" % remote_id)
	_check(own.camera.current and not remote.camera.current)
	_check(own.spawn_position.distance_to(remote.spawn_position) > 1.0)
	# Спавны в 40 м друг от друга — дальше дальности обзора: туман войны прячет соседа.
	_check(remote.fog_hidden, "Игрок за пределами обзора виден")
	# Сходимся на открытом месте южнее центральной стены — друг друга видно.
	var spot := Vector2(-4.0 if mode == "host" else 4.0, 8.0)
	_place(world, own, spot)
	await _wait_until(func(): return not remote.fog_hidden)
	_check(remote.visible, "Видимый по туману игрок не рисуется")
	# Присед хоста виден клиенту, и капсула меняется только у присевшего.
	if mode == "host":
		Input.action_press("crouch")
		await create_timer(0.3).timeout
		Input.action_release("crouch")
	else:
		while not remote.is_crouching:
			await process_frame
		await process_frame
		_check(is_equal_approx(remote.collision_shape.shape.height, remote.CROUCH_HEIGHT), "Присед не синхронизируется по сети")
		_check(is_equal_approx(own.collision_shape.shape.height, own.STAND_HEIGHT), "Присед одного игрока меняет капсулу другого")
	if mode == "host":
		own.health_component.take_damage(9999.0, remote_id)
		# После респавна (на далёком спавне) возвращаемся, иначе клиент нас не увидит.
		while own.health_component.is_alive:
			await process_frame
		while not own.health_component.is_alive:
			await process_frame
		await process_frame
		_place(world, own, spot)
	else:
		while remote.health_component.is_alive:
			await process_frame
		await process_frame
		_check(not remote.visible and remote.get_node("CollisionShape3D").disabled)
		while not remote.health_component.is_alive:
			await process_frame
		# Ожив на далёком спавне, он вернётся к месту встречи — тогда снова виден.
		await _wait_until(func(): return not remote.fog_hidden)
		await physics_frame
		_check(remote.visible and not remote.get_node("CollisionShape3D").disabled)
		own.health_component.take_damage(9999.0, remote_id)
	if mode == "host":
		while remote.health_component.is_alive:
			await process_frame
		await process_frame
		_check(not remote.visible and remote.get_node("CollisionShape3D").disabled)
		while not remote.health_component.is_alive:
			await process_frame
		# Ожив на далёком спавне, он вернётся к месту встречи — тогда снова виден.
		await _wait_until(func(): return not remote.fog_hidden)
		await physics_frame
		_check(remote.visible and not remote.get_node("CollisionShape3D").disabled)
		_check(world.game_mode.get_score(1).deaths == 1)
		_check(world.game_mode.get_score(remote_id).deaths == 1)
	else:
		while not own.health_component.is_alive:
			await process_frame
		await process_frame
		_place(world, own, spot)
	await create_timer(0.3).timeout
	await _check_network_fog(world, own, remote, mode)
	if _failed:
		quit(1)
		return
	if mode == "host":
		await create_timer(0.5).timeout
		network.disconnect_game()
	else:
		# Хост вышел — клиент узнаёт об этом и очищает сеть.
		while not disconnected[0]:
			await process_frame
		_check(network.players.is_empty() and network.peer == null, "Клиент не замечает ухода хоста")
	if _failed:
		quit(1)
		return
	print("PASS: сеть %s — ники, своя камера, уникальный спавн, смерть, респавн и уход хоста" % mode)
	if is_instance_valid(world):
		world.free()
	quit(0)


func _check(condition: bool, message: String = "Нарушено пространственное условие") -> void:
	if not condition:
		_failed = true
		push_error(message)
