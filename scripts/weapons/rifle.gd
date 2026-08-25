extends WeaponBase
class_name Rifle

## Винтовка — hitscan-оружие с распространением, отдачей и эффектами попаданий.

# --- Параметры распространения (spread/bloom) ---
const BLOOM_PER_SHOT := 0.01
const BLOOM_DECAY_SPEED := 2.0
const MAX_BLOOM := 0.3

const SPREAD_IDLE := 0.005
const SPREAD_WALK := 0.015
const SPREAD_RUN := 0.04
const SPREAD_ADS := 0.002
const SPREAD_ADS_FIRING := 0.005
const SPREAD_HIPFIRE_FIRING := 0.02
const SPREAD_WALK_FIRING := 0.015
const SPREAD_PER_SHOT := 0.005
const SPREAD_ADS_PER_SHOT := 0.002

const SPEED_RUN_THRESHOLD := 4.0

var bloom_accumulation: float = 0.0

# --- Ноды ---
@onready var raycast: RayCast3D = $RayCast3D
@onready var muzzle_flash: GPUParticles3D = $MuzzleFlash
@onready var muzzle_light: OmniLight3D = $MuzzleLight
@onready var reload_timer: Timer = $ReloadTimer
var rifle_mesh: MeshInstance3D

var _base_transform: Transform3D
var _recoil_recovery_speed := 12.0

var _scorch_marks: Array[MeshInstance3D] = []
const MAX_SCORCH_MARKS := 50


func _ready() -> void:
	super._ready()
	_build_lowpoly_rifle()
	reload_timer.wait_time = reload_time
	reload_timer.one_shot = true
	reload_timer.timeout.connect(_on_reload_finished)
	raycast.enabled = true
	raycast.collision_mask = 1 | 2
	muzzle_light.light_energy = 0.0
	_base_transform = transform


func _build_lowpoly_rifle() -> void:
	rifle_mesh = MeshInstance3D.new()
	rifle_mesh.mesh = MeshUtils.make_rifle()
	rifle_mesh.set_surface_override_material(0, MeshUtils.flat_material(Color(0.15, 0.15, 0.18)))
	rifle_mesh.position = Vector3(0, 0, -0.25)
	add_child(rifle_mesh)
	MeshUtils.add_outline_to_mesh(rifle_mesh, Color(0.05, 0.05, 0.08), 0.04)


func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var player := _get_player()
	if player:
		var health: HealthComponent = player.get_node_or_null("HealthComponent")
		if health and not health.is_alive:
			return

	# Проверка ввода стрельбы
	var shoot_pressed := Input.is_action_pressed("shoot")
	if player and player.get("mobile_shoot_pressed"):
		shoot_pressed = true
	if shoot_pressed and can_fire and not is_reloading:
		shoot()

	# Проверка ввода перезарядки
	var reload_pressed := Input.is_action_just_pressed("reload")
	if player and player.get("mobile_reload_triggered"):
		reload_pressed = true
		player.mobile_reload_triggered = false
	if reload_pressed and not is_reloading and current_ammo < magazine_size:
		reload()

	# Плавное восстановление позиции после отдачи
	transform = transform.interpolate_with(_base_transform, _recoil_recovery_speed * delta)

	# Затухание bloom
	if bloom_accumulation > 0.0:
		bloom_accumulation -= BLOOM_DECAY_SPEED * delta
		if bloom_accumulation < 0.0:
			bloom_accumulation = 0.0


func shoot() -> void:
	if current_ammo <= 0:
		SFXManager.play_empty()
		return

	current_ammo -= 1
	can_fire = false
	is_firing = true
	SFXManager.play_shoot()
	_shoot_effects.rpc()

	# Отдача: оружие сдвигается назад и задирается вверх
	_base_transform = transform
	translate(Vector3(0, 0, -0.035))
	rotate_x(-0.01)

	# Отдача камеры
	var player := _get_player()
	if player and player.has_method("apply_recoil"):
		player.apply_recoil(randf_range(0.008, 0.015))

	# Вспышка дула
	muzzle_light.light_energy = 1.5
	get_tree().create_timer(0.04).timeout.connect(func():
		muzzle_light.light_energy = 0.0
	)

	# Применение разброса
	_apply_bullet_spread()

	# Трассер
	var muzzle_pos := raycast.global_position
	var hit_pos := raycast.get_collision_point() if raycast.is_colliding() else raycast.global_position + raycast.target_position.normalized() * 100.0
	_spawn_tracer.rpc(muzzle_pos, hit_pos)

	# Hitscan-попадание
	if raycast.is_colliding():
		var collider := raycast.get_collider()
		var hit_position := raycast.get_collision_point()
		var hit_normal := raycast.get_collision_normal()

		if collider and collider.has_node("HealthComponent"):
			var health: HealthComponent = collider.get_node("HealthComponent")
			if health and health.is_alive:
				var distance := raycast.global_position.distance_to(hit_position)
				var final_damage := _get_damage_with_falloff(distance)

				var is_headshot := _check_headshot(collider, hit_position)
				if is_headshot:
					final_damage *= headshot_multiplier

				var shooter_id := multiplayer.get_unique_id()
				health.take_damage.rpc_id(collider.get_multiplayer_authority(), final_damage, shooter_id)
				# Попадание подтверждаем сразу (белый/жёлтый маркер).
				# Факт убийства узнаём только асинхронно от самой жертвы
				# через kill_confirmed — только у неё есть актуальный is_alive.
				hit_confirmed.emit(is_headshot, false)
				if not health.kill_confirmed.is_connected(_on_kill_confirmed):
					health.kill_confirmed.connect(_on_kill_confirmed, CONNECT_ONE_SHOT)
			_spawn_blood.rpc(hit_position, hit_normal)
		else:
			_spawn_impact.rpc(hit_position, hit_normal)

	# Накопление bloom
	bloom_accumulation = minf(bloom_accumulation + BLOOM_PER_SHOT, MAX_BLOOM)

	fired.emit()
	await get_tree().create_timer(fire_rate).timeout
	can_fire = true
	is_firing = false


func _apply_bullet_spread() -> void:
	var player := _get_player()
	var spread := SPREAD_IDLE

	if player:
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		var aiming: bool = player.get("is_aiming") if "is_aiming" in player else false

		if aiming:
			spread = SPREAD_ADS_FIRING if is_firing else SPREAD_ADS
		else:
			if speed > SPEED_RUN_THRESHOLD:
				spread = SPREAD_RUN
			elif speed > 1.0:
				spread = SPREAD_WALK_FIRING if is_firing else SPREAD_WALK
			else:
				spread = SPREAD_HIPFIRE_FIRING if is_firing else SPREAD_IDLE

	spread += bloom_accumulation * 0.5

	var offset := Vector2(
		randf_range(-spread, spread),
		randf_range(-spread, spread)
	)
	raycast.target_position = Vector3(offset.x, offset.y, -100)


func _get_damage_with_falloff(distance: float) -> float:
	if distance <= 30.0:
		return damage
	elif distance <= 60.0:
		return damage * 0.7
	else:
		return damage * 0.5


func _check_headshot(collider: Node, hit_position: Vector3) -> bool:
	if not collider is CharacterBody3D:
		return false
	var capsule_height: float = 1.8
	var head_threshold: float = collider.global_position.y + capsule_height * 0.75
	return hit_position.y > head_threshold


func reload() -> void:
	is_reloading = true
	reload_timer.start()


func _on_reload_finished() -> void:
	current_ammo = magazine_size
	is_reloading = false
	reloaded.emit()


@rpc("call_local", "reliable")
func _shoot_effects() -> void:
	if muzzle_flash:
		muzzle_flash.restart()


@rpc("call_local", "reliable")
func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var root := get_tree().current_scene
	if not root:
		return

	var is_ground := normal.y > 0.7

	# --- Искры ---
	var sparks := GPUParticles3D.new()
	var spark_pm := ParticleProcessMaterial.new()
	spark_pm.direction = -normal
	spark_pm.spread = 45.0 if is_ground else 30.0
	spark_pm.initial_velocity_min = 3.0 if is_ground else 5.0
	spark_pm.initial_velocity_max = 6.0 if is_ground else 10.0
	spark_pm.gravity = Vector3(0, -12.0, 0)
	spark_pm.scale_min = 0.6
	spark_pm.scale_max = 1.4
	spark_pm.damping_min = 1.0
	spark_pm.damping_max = 3.0
	sparks.process_material = spark_pm
	sparks.amount = 8 if is_ground else 12
	sparks.lifetime = 0.35
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.emitting = true
	sparks.position = pos + normal * 0.05

	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.025, 0.025, 0.025)
	sparks.draw_pass_1 = spark_mesh

	var spark_mat := StandardMaterial3D.new()
	spark_mat.albedo_color = Color(1.0, 0.85, 0.3) if is_ground else Color(1.0, 0.9, 0.6)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.8, 0.2) if is_ground else Color(1.0, 0.9, 0.5)
	spark_mat.emission_energy_multiplier = 8.0 if is_ground else 12.0
	sparks.draw_pass_1.material = spark_mat

	root.add_child(sparks)
	get_tree().create_timer(0.5).timeout.connect(func():
		if is_instance_valid(sparks):
			sparks.queue_free()
	)

	# --- Пылевое облако ---
	var dust := GPUParticles3D.new()
	var dust_pm := ParticleProcessMaterial.new()
	dust_pm.direction = -normal
	dust_pm.spread = 70.0 if is_ground else 50.0
	dust_pm.initial_velocity_min = 0.8 if is_ground else 1.2
	dust_pm.initial_velocity_max = 2.0 if is_ground else 3.0
	dust_pm.gravity = Vector3(0, -3.0, 0)
	dust_pm.scale_min = 0.5
	dust_pm.scale_max = 1.5
	dust_pm.damping_min = 2.0
	dust_pm.damping_max = 5.0
	dust.process_material = dust_pm
	dust.amount = 5 if is_ground else 3
	dust.lifetime = 0.6 if is_ground else 0.4
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.emitting = true
	dust.position = pos + normal * 0.04

	var dust_mesh := BoxMesh.new()
	dust_mesh.size = Vector3(0.04, 0.04, 0.04)
	dust.draw_pass_1 = dust_mesh

	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color = Color(0.92, 0.87, 0.78) if is_ground else Color(0.82, 0.80, 0.76)
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.albedo_color.a = 0.5
	dust_mat.roughness = 1.0
	dust.draw_pass_1.material = dust_mat

	root.add_child(dust)
	get_tree().create_timer(0.8).timeout.connect(func():
		if is_instance_valid(dust):
			dust.queue_free()
	)

	# --- След от пули (scorch) ---
	var scorch := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var scorch_mat := StandardMaterial3D.new()
	scorch_mat.albedo_color = Color(0.55, 0.48, 0.38)
	scorch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scorch_mat.albedo_color.a = 0.4
	scorch_mat.roughness = 1.0
	scorch_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = scorch_mat
	scorch.mesh = quad
	scorch.position = pos + normal * 0.003
	if normal.length_squared() > 0.01:
		var up := Vector3.UP
		if absf(normal.dot(up)) > 0.99:
			up = Vector3.FORWARD
		scorch.look_at(scorch.position - normal, up)

	_scorch_marks.append(scorch)
	if _scorch_marks.size() > MAX_SCORCH_MARKS:
		var oldest = _scorch_marks[0]
		_scorch_marks.remove_at(0)
		if is_instance_valid(oldest):
			oldest.queue_free()

	root.add_child(scorch)
	get_tree().create_timer(30.0).timeout.connect(func():
		if is_instance_valid(scorch):
			_scorch_marks.erase(scorch)
			scorch.queue_free()
	)

	# --- Вспышка света на стене ---
	if not is_ground:
		var flash := OmniLight3D.new()
		flash.light_color = Color(1.0, 0.92, 0.7)
		flash.light_energy = 0.5
		flash.omni_range = 1.5
		flash.omni_attenuation = 2.0
		flash.position = pos + normal * 0.1
		root.add_child(flash)
		get_tree().create_timer(0.08).timeout.connect(func():
			if is_instance_valid(flash):
				flash.queue_free()
		)


@rpc("call_local", "unreliable")
func _spawn_tracer(muzzle_pos: Vector3, hit_pos: Vector3) -> void:
	var root := get_tree().current_scene
	if not root:
		return

	var length := muzzle_pos.distance_to(hit_pos)
	if length < 0.1:
		return

	var tracer_mat := StandardMaterial3D.new()
	tracer_mat.albedo_color = Color(1.0, 0.7, 0.1, 0.9)
	tracer_mat.emission_enabled = true
	tracer_mat.emission = Color(1.0, 0.6, 0.1)
	tracer_mat.emission_energy_multiplier = 12.0
	tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(0.015, 0.015, length)
	tracer_mesh.material = tracer_mat

	var tracer := MeshInstance3D.new()
	tracer.mesh = tracer_mesh
	tracer.position = (muzzle_pos + hit_pos) / 2.0
	tracer.look_at(hit_pos, Vector3.UP)

	root.add_child(tracer)
	get_tree().create_timer(0.08).timeout.connect(func():
		if is_instance_valid(tracer):
			tracer.queue_free()
	)


@rpc("call_local", "reliable")
func _spawn_blood(pos: Vector3, normal: Vector3) -> void:
	var root := get_tree().current_scene
	if not root:
		return

	var blood_scene := preload("res://scenes/effects/blood_splash.tscn")
	var blood := blood_scene.instantiate()
	blood.position = pos + normal * 0.02
	root.add_child(blood)

	var blood_drops = blood.get_node_or_null("BloodDrops")
	if blood_drops:
		blood_drops.restart()
	var blood_mist = blood.get_node_or_null("BloodMist")
	if blood_mist:
		blood_mist.restart()

	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(blood):
			blood.queue_free()
	)


func _get_player() -> Node:
	var node: Node = self
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


func _on_kill_confirmed() -> void:
	hit_confirmed.emit(false, true)
