extends WeaponBase
class_name Rifle

## Винтовка — hitscan-оружие с распространением, отдачей и эффектами попаданий.

# --- Разброс (радианы конуса) ---
# Винтовка как у Foxhole: один осознанный выстрел, затвор ~1 с (параметры — в rifle.tscn).
# Разброс от бедра широкий; пока прицел зажат, он сводится к прицельному за
# Player.AIM_TIME (aim_progress). Выстрел сбивает сведение (Player.on_shot_fired).
const SPREAD_IDLE := 0.06
const SPREAD_WALK := 0.09
const SPREAD_RUN := 0.15
## Полностью сведённый прицел стоя и на ходу.
const SPREAD_AIMED := 0.008
const SPREAD_AIMED_MOVING := 0.03
# Накопление между выстрелами (быстрая стрельба без сведения).
const BLOOM_PER_SHOT := 0.015
const BLOOM_DECAY_SPEED := 0.5
const MAX_BLOOM := 0.06
## Дальность выстрела, м.
const RANGE := 80.0
## Запас за точкой прицела, м: цель, стоящая ровно под прицелом, поражается целиком.
const AIM_HIT_MARGIN := 0.3

# Выше скорости ходьбы (PlayerState.SPEED): бег появится вместе со спринтом.
const SPEED_RUN_THRESHOLD := PlayerState.SPEED + 0.5

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

# Меши и материалы эффектов попадания общие для всех выстрелов:
# создаются один раз, а не на каждое попадание.
static var _impact_assets: Dictionary = {}
## Материал трассера общий для всех выстрелов.
static var _tracer_material: StandardMaterial3D
const PREWARM_MARK_LIFETIME := 0.2
## Через сколько после выстрела слышен затвор (меньше fire_rate).
const BOLT_SOUND_DELAY := 0.45
## Материал поверхности для эффектов попадания: грунт, песок (мешки), камень и стены.
## Укрытия сообщают его через мета-данные «surface» (game_scene._build_covers).
enum Surface { DIRT, SAND, STONE }
## Мелкие эффекты увеличены: камера в 21 м, и частица реального размера (2–5 см) меньше
## пикселя экрана планшета — попадание просто не было видно. Как у Foxhole: читаемость
## важнее масштаба.
const FX_SCALE := 3.5
## Трассер: у винтовки его нет — в эту эпоху трассирующие клали в пулемётные ленты (каждый
## 4–5-й патрон), а не в обычные винтовочные обоймы. 0 — не рисовать; пулемёту поставить N.
@export var tracer_every: int = 0
var _shots_fired: int = 0
var _muzzle_smoke: GPUParticles3D
var _casing: GPUParticles3D
## Свист: пуля, прошедшая ближе WHIZ_RADIUS метров к голове слушателя. Если трасса
## кончается ближе WHIZ_HIT_EXCLUDE к нему — пуля попала в него, свиста нет.
const WHIZ_RADIUS := 4.0
const WHIZ_EAR_HEIGHT := 1.5
const WHIZ_HIT_EXCLUDE := 1.2


func _ready() -> void:
	super._ready()
	_build_lowpoly_rifle()
	reload_timer.wait_time = reload_time
	reload_timer.one_shot = true
	reload_timer.timeout.connect(_on_reload_finished)
	raycast.enabled = true
	raycast.collision_mask = 1 | 2
	raycast.top_level = true
	var player := _get_player() as CollisionObject3D
	if player:
		raycast.add_exception(player)
	muzzle_light.light_energy = 0.0
	muzzle_light.visible = false
	_build_muzzle_smoke()
	_build_casing()
	_base_transform = transform


## Лёгкий серо-голубой дымок у дула: бездымный порох эпохи даёт короткую вспышку и струйку дыма.
## Частицы в мировых координатах — дым остаётся там, где был выстрел.
func _build_muzzle_smoke() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.15, -1.0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0.0, 0.25, 0.0)
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 1.0])
	fade.colors = PackedColorArray([Color(0.78, 0.8, 0.82, 0.45), Color(0.78, 0.8, 0.82, 0.0)])
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	pm.color_ramp = fade_tex
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.5))
	growth.add_point(Vector2(1.0, 2.0))
	var growth_tex := CurveTexture.new()
	growth_tex.curve = growth
	pm.scale_curve = growth_tex
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	var puff := SphereMesh.new()
	puff.radius = 0.07 * FX_SCALE
	puff.height = 0.14 * FX_SCALE
	puff.radial_segments = 6
	puff.rings = 3
	puff.material = mat
	_muzzle_smoke = GPUParticles3D.new()
	_muzzle_smoke.name = "MuzzleSmoke"
	_muzzle_smoke.position = muzzle_flash.position
	_muzzle_smoke.emitting = false
	_muzzle_smoke.amount = 5
	_muzzle_smoke.lifetime = 1.0
	_muzzle_smoke.one_shot = true
	_muzzle_smoke.explosiveness = 0.9
	_muzzle_smoke.visibility_aabb = AABB(Vector3(-2.0, -2.0, -3.0), Vector3(4.0, 4.0, 4.0))
	_muzzle_smoke.process_material = pm
	_muzzle_smoke.draw_pass_1 = puff
	add_child(_muzzle_smoke)


## Гильза вылетает вправо при передёргивании затвора (в момент звука затвора), а не при выстреле.
func _build_casing() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1.0, 0.8, 0.2)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.8
	pm.initial_velocity_max = 2.6
	pm.gravity = Vector3(0.0, -12.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.65, 0.25)
	mat.metallic = 0.6
	mat.roughness = 0.4
	var brass := BoxMesh.new()
	brass.size = Vector3(0.012, 0.012, 0.04) * FX_SCALE
	brass.material = mat
	_casing = GPUParticles3D.new()
	_casing.name = "Casing"
	_casing.position = Vector3(0.05, 0.03, -0.25)
	_casing.emitting = false
	_casing.amount = 1
	_casing.lifetime = 0.7
	_casing.one_shot = true
	_casing.explosiveness = 1.0
	_casing.visibility_aabb = AABB(Vector3(-3.0, -3.0, -3.0), Vector3(6.0, 6.0, 6.0))
	_casing.process_material = pm
	_casing.draw_pass_1 = brass
	add_child(_casing)


func _build_lowpoly_rifle() -> void:
	rifle_mesh = MeshInstance3D.new()
	rifle_mesh.mesh = MeshUtils.make_rifle()
	rifle_mesh.set_surface_override_material(0, MeshUtils.flat_material(Color.WHITE))
	rifle_mesh.position = Vector3(0, 0, -0.25)
	add_child(rifle_mesh)
	MeshUtils.add_outline_to_mesh(rifle_mesh, Color(0.05, 0.05, 0.08), 0.004)


func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	# Ввод стрельбы/перезарядки опрашивают стейты игрока через WeaponManager.

	# Плавное восстановление позиции после отдачи
	transform = transform.interpolate_with(_base_transform, 1.0 - exp(-_recoil_recovery_speed * delta))

	# Затухание bloom
	if bloom_accumulation > 0.0:
		bloom_accumulation -= BLOOM_DECAY_SPEED * delta
		if bloom_accumulation < 0.0:
			bloom_accumulation = 0.0


func shoot() -> void:
	# Все пути ввода используют одну проверку, включая WeaponManager.
	var player := _get_player()
	if not is_multiplayer_authority() or not can_shoot():
		return
	if player and not player.get_node("HealthComponent").is_alive:
		return

	current_ammo -= 1
	can_fire = false
	is_firing = true
	# Фиксируем луч текущего выстрела до визуальной отдачи.
	_apply_bullet_spread()
	_shoot_effects.rpc(muzzle_flash.global_position)

	# Отдача: оружие сдвигается назад и задирается вверх
	transform = _base_transform
	translate(Vector3(0, 0, 0.035))
	rotate_x(0.01)

	# Трассер
	var muzzle_pos := muzzle_flash.global_position
	var hit_pos: Vector3
	var landed := false
	if raycast.is_colliding():
		hit_pos = raycast.get_collision_point()
	else:
		# Долетела до точки прицела, ничего не задев: ложится на землю под ней.
		hit_pos = raycast.to_global(raycast.target_position)
		if player:
			hit_pos.y = player.ground_height_at(hit_pos)
			landed = true
	_shots_fired += 1
	var draw_tracer := tracer_every > 0 and _shots_fired % tracer_every == 0
	_spawn_tracer.rpc(muzzle_pos, hit_pos, true, draw_tracer)
	if landed:
		_spawn_impact.rpc(hit_pos, Vector3.UP, true, Surface.DIRT)

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
			_spawn_blood.rpc(hit_position, hit_normal, collider.get_multiplayer_authority())
		else:
			_spawn_impact.rpc(hit_position, hit_normal, true, _surface_of(collider, hit_normal))

	# Накопление и сбитое сведение прицела
	bloom_accumulation = minf(bloom_accumulation + BLOOM_PER_SHOT, MAX_BLOOM)
	if player and player.has_method("on_shot_fired"):
		player.on_shot_fired()

	fired.emit()
	await get_tree().create_timer(fire_rate).timeout
	can_fire = true
	is_firing = false


## Луч выстрела: от оружия к точке прицеливания игрока, отклонённый в пределах конуса.
## Мир трёхмерный: высота и укрытия останавливают пулю, а не плоскость.
func _apply_bullet_spread() -> void:
	var player := _get_player()
	if not player:
		return
	var origin: Vector3 = player.get_shot_origin()
	var to_target: Vector3 = player.aim_point - origin
	if to_target.length_squared() < 0.01:
		to_target = player.get_aim_direction()
	var spread := get_spread_angle()
	var direction := to_target.normalized()
	# Отклонение по горизонтали — весь конус, по вертикали — треть: сверху ошибка
	# видна в основном вбок, а вертикальная уводила бы пули в землю или небо.
	direction = direction.rotated(Vector3.UP, randf_range(-spread, spread))
	var side := direction.cross(Vector3.UP).normalized()
	if side.length_squared() > 0.0:
		direction = direction.rotated(side, randf_range(-spread, spread) / 3.0)
	raycast.global_transform = Transform3D(Basis.IDENTITY, origin)
	# Пуля летит до точки прицела и не дальше: конус на земле и крестик показывают, где она
	# ляжет. Если ничего не задела, она падает на землю там (см. shoot).
	raycast.target_position = direction * minf(to_target.length() + AIM_HIT_MARGIN, RANGE)
	raycast.force_raycast_update()


# Разброс в радианах: одна величина для выстрела, прицела HUD и конуса на земле.
func get_spread_angle() -> float:
	var player := _get_player()
	var spread := SPREAD_IDLE
	if player:
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		var moving := speed > 1.0
		var hip := SPREAD_RUN if speed > SPEED_RUN_THRESHOLD else (SPREAD_WALK if moving else SPREAD_IDLE)
		var aimed := SPREAD_AIMED_MOVING if moving else SPREAD_AIMED
		var progress: float = player.aim_progress if "aim_progress" in player else 0.0
		spread = lerpf(hip, aimed, progress)
	return spread + bloom_accumulation


## Материал поверхности, в которую попала пуля: укрытия говорят сами, остальное — грунт
## (пологая поверхность) или камень (стена, обрыв).
func _surface_of(collider: Object, normal: Vector3) -> int:
	if collider and collider.has_meta("surface"):
		return int(collider.get_meta("surface"))
	return Surface.DIRT if normal.y > 0.7 else Surface.STONE


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
	# Рост меняется при приседании — берём текущий у самого игрока.
	var body_height: float = collider.get_body_height() if collider.has_method("get_body_height") else 1.8
	var head_threshold: float = collider.global_position.y + body_height * 0.75
	return hit_position.y > head_threshold


func reload() -> void:
	if not is_multiplayer_authority() or is_reloading or current_ammo >= magazine_size:
		return
	is_reloading = true
	reload_timer.start()
	_reload_effects.rpc(global_position)


func _on_reload_finished() -> void:
	current_ammo = magazine_size
	is_reloading = false
	reloaded.emit()


## Вспышка, звук выстрела и затвора — у всех пиров (call_local). Позиция приходит
## в вызове: у стрелка, скрытого туманом войны, позиция не синхронизируется, и звук
## иначе шёл бы из последнего известного места. Прогрев эффектов — без звука.
@rpc("call_local", "unreliable")
func _shoot_effects(origin: Vector3, with_sound: bool = true) -> void:
	if with_sound:
		SFXManager.play_shot_at(origin)
		# Затвор передёргивают после выстрела, пока винтовка ещё «в цикле» (fire_rate).
		get_tree().create_timer(BOLT_SOUND_DELAY).timeout.connect(func():
			SFXManager.play_bolt_at(origin, _sound_anchor())
			if is_instance_valid(self) and is_inside_tree():
				_casing.restart()
		)
	if muzzle_flash:
		muzzle_flash.restart()
	_muzzle_smoke.restart()
	# Источник света включаем только на время вспышки: свет с нулевой яркостью
	# всё равно обрабатывается рендером. На низкой/средней графике вспышки света нет.
	if not GameSettings.dynamic_lights_enabled():
		return
	muzzle_light.light_energy = 1.5
	muzzle_light.visible = true
	get_tree().create_timer(0.04).timeout.connect(func():
		muzzle_light.light_energy = 0.0
		muzzle_light.visible = false
	)


## Звук перезарядки у всех пиров: позиция приходит в вызове, как и у выстрела.
@rpc("call_local", "unreliable")
func _reload_effects(origin: Vector3) -> void:
	SFXManager.play_reload_at(origin, _sound_anchor())


# Длинные звуки (затвор, перезарядка) едут вместе с винтовкой — убежал, звук не остался
# позади. Но у стрелка, скрытого туманом войны, позиция не синхронизируется: такой звук
# стоит в точке, где начался (иначе он шёл бы из последнего известного места).
func _sound_anchor() -> Node3D:
	if not is_inside_tree():
		return null
	var player := _get_player()
	if player and "fog_hidden" in player and player.fog_hidden:
		return null
	return self


## Один раз показать все эффекты выстрела перед камерой в начале матча (под затемнением):
## шейдер материала компилируется при первой отрисовке, и без прогрева первый выстрел,
## первое попадание и первая кровь давали заметный рывок кадра, особенно на телефонах.
func prewarm_effects(at: Vector3) -> void:
	_shoot_effects(muzzle_flash.global_position, false)
	for surface in Surface.values():
		_spawn_impact(at, Vector3.UP, false, surface)
	_spawn_impact(at + Vector3.UP * 0.5, Vector3.BACK, false, Surface.STONE)
	_spawn_tracer(muzzle_flash.global_position, at, false, tracer_every > 0)
	_casing.restart()
	_spawn_blood(at + Vector3.UP, Vector3.UP, 0, false)
	# Следы пуль от прогрева убираем, как только они отрисовались.
	var marks := _scorch_marks.slice(-2)
	get_tree().create_timer(PREWARM_MARK_LIFETIME).timeout.connect(func():
		for mark in marks:
			_scorch_marks.erase(mark)
			if is_instance_valid(mark):
				mark.queue_free()
	)


@rpc("call_local", "unreliable")
func _spawn_impact(pos: Vector3, normal: Vector3, with_sound: bool = true, surface: int = -1) -> void:
	var root := get_tree().current_scene
	if not root:
		return
	if surface < 0:
		surface = Surface.DIRT if normal.y > 0.7 else Surface.STONE
	if with_sound:
		SFXManager.play_impact_at(pos, surface != Surface.STONE)
	var assets := _get_impact_assets(surface)

	# Грунт и песок вздымают комья и пыль, а не искры: искры бывают только на камне и металле.
	if surface == Surface.STONE:
		_emit_burst(root, pos + normal * 0.05, normal, assets.spark_mesh, 4, 0.3, 30.0, 4.0, 8.0, -12.0, 0.5)
	else:
		_emit_burst(root, pos + normal * 0.05, normal, assets.clod_mesh, 6 if surface == Surface.DIRT else 4,
				0.5, 40.0, 2.0, 4.5, -14.0, 0.7)
	var puff_amount := 3 if surface == Surface.STONE else (5 if surface == Surface.DIRT else 7)
	_emit_burst(root, pos + normal * 0.04, normal, assets.dust_mesh, puff_amount,
			0.5 if surface == Surface.STONE else 0.7, 65.0, 0.8, 2.2, -3.0, 0.9, 2.0, 5.0)

	# --- След от пули: воронка в грунте, тёмный след в песке, светлая выбоина в камне ---
	var scorch := MeshInstance3D.new()
	scorch.mesh = assets.scorch_mesh
	scorch.position = pos + normal * 0.003
	root.add_child(scorch)
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

	get_tree().create_timer(30.0).timeout.connect(func():
		if is_instance_valid(scorch):
			_scorch_marks.erase(scorch)
			scorch.queue_free()
	)


## Один разовый всплеск частиц: пыль, комья или искры. Освобождается сам.
func _emit_burst(root: Node, at: Vector3, normal: Vector3, mesh: Mesh, amount: int, lifetime: float,
		spread: float, speed_min: float, speed_max: float, gravity_y: float, free_after: float,
		damping_min: float = 1.0, damping_max: float = 3.0) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.direction = normal
	pm.spread = spread
	pm.initial_velocity_min = speed_min
	pm.initial_velocity_max = speed_max
	pm.gravity = Vector3(0.0, gravity_y, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.damping_min = damping_min
	pm.damping_max = damping_max
	var burst := GPUParticles3D.new()
	burst.process_material = pm
	burst.amount = amount
	burst.lifetime = lifetime
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.emitting = true
	burst.position = at
	burst.draw_pass_1 = mesh
	root.add_child(burst)
	get_tree().create_timer(free_after + lifetime).timeout.connect(func():
		if is_instance_valid(burst):
			burst.queue_free()
	)


@rpc("call_local", "unreliable")
func _spawn_tracer(muzzle_pos: Vector3, hit_pos: Vector3, with_sound: bool = true, draw: bool = true) -> void:
	var root := get_tree().current_scene
	if not root:
		return

	var length := muzzle_pos.distance_to(hit_pos)
	if length < 0.1:
		return
	if with_sound:
		_play_whiz(muzzle_pos, hit_pos)
	if not draw:
		return

	if not _tracer_material:
		_tracer_material = StandardMaterial3D.new()
		_tracer_material.albedo_color = Color(1.0, 0.7, 0.1, 0.9)
		_tracer_material.emission_enabled = true
		_tracer_material.emission = Color(1.0, 0.6, 0.1)
		_tracer_material.emission_energy_multiplier = 12.0
		_tracer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(0.015, 0.015, length)
	tracer_mesh.material = _tracer_material

	var tracer := MeshInstance3D.new()
	tracer.mesh = tracer_mesh
	tracer.position = (muzzle_pos + hit_pos) / 2.0
	root.add_child(tracer)
	var direction := (hit_pos - muzzle_pos).normalized()
	var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	tracer.look_at(hit_pos, up)
	get_tree().create_timer(0.08).timeout.connect(func():
		if is_instance_valid(tracer):
			tracer.queue_free()
	)


## Свист пули, пролетевшей рядом с нашим солдатом. Своих выстрелов не свистим, и если
## пуля попала в нас самих — об этом говорят шлепок и вспышка урона, а не пролёт.
func _play_whiz(from: Vector3, to: Vector3) -> void:
	var own := get_tree().current_scene.get_node_or_null("Players/%d" % multiplayer.get_unique_id()) as Node3D
	if own == null or own == _get_player():
		return
	var ear := own.global_position + Vector3.UP * WHIZ_EAR_HEIGHT
	var closest := Geometry3D.get_closest_point_to_segment(ear, from, to)
	var distance := closest.distance_to(ear)
	if distance > WHIZ_RADIUS or to.distance_to(ear) < WHIZ_HIT_EXCLUDE:
		return
	SFXManager.play_whiz_at(closest)


@rpc("call_local", "unreliable")
func _spawn_blood(pos: Vector3, normal: Vector3, victim_id: int = 0, with_sound: bool = true) -> void:
	if with_sound:
		SFXManager.play_hit_flesh_at(pos)
	# У самой жертвы брызги появлялись в полуметре от камеры и закрывали
	# экран огромными кубами — о попадании ей сообщает эффект урона на экране.
	if victim_id == multiplayer.get_unique_id():
		return
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


static func _get_impact_assets(surface: int) -> Dictionary:
	if _impact_assets.has(surface):
		return _impact_assets[surface]

	var assets := {}
	if surface == Surface.STONE:
		var spark_mat := StandardMaterial3D.new()
		spark_mat.albedo_color = Color(1.0, 0.9, 0.6)
		spark_mat.emission_enabled = true
		spark_mat.emission = Color(1.0, 0.85, 0.45)
		spark_mat.emission_energy_multiplier = 4.0
		var spark_mesh := BoxMesh.new()
		spark_mesh.size = Vector3(0.015, 0.015, 0.015) * FX_SCALE
		spark_mesh.material = spark_mat
		assets["spark_mesh"] = spark_mesh
	else:
		var clod_mat := StandardMaterial3D.new()
		clod_mat.albedo_color = Color(0.30, 0.23, 0.16) if surface == Surface.DIRT else Color(0.74, 0.66, 0.48)
		clod_mat.roughness = 1.0
		var clod_mesh := BoxMesh.new()
		clod_mesh.size = Vector3(0.035, 0.035, 0.035) * FX_SCALE
		clod_mesh.material = clod_mat
		assets["clod_mesh"] = clod_mesh

	var dust_mat := StandardMaterial3D.new()
	match surface:
		Surface.DIRT:
			dust_mat.albedo_color = Color(0.55, 0.47, 0.36, 0.5)
		Surface.SAND:
			dust_mat.albedo_color = Color(0.82, 0.74, 0.55, 0.5)
		_:
			dust_mat.albedo_color = Color(0.72, 0.72, 0.72, 0.45)
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.roughness = 1.0
	var dust_mesh := BoxMesh.new()
	dust_mesh.size = (Vector3(0.05, 0.05, 0.05) if surface == Surface.SAND else Vector3(0.04, 0.04, 0.04)) * FX_SCALE
	dust_mesh.material = dust_mat
	assets["dust_mesh"] = dust_mesh

	var scorch_mat := StandardMaterial3D.new()
	match surface:
		Surface.DIRT:
			scorch_mat.albedo_color = Color(0.28, 0.22, 0.16, 0.5)
		Surface.SAND:
			scorch_mat.albedo_color = Color(0.50, 0.43, 0.30, 0.4)
		_:
			scorch_mat.albedo_color = Color(0.80, 0.80, 0.80, 0.5)
	scorch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scorch_mat.roughness = 1.0
	scorch_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var scorch_mesh := QuadMesh.new()
	scorch_mesh.size = Vector2(0.05, 0.05) * FX_SCALE
	scorch_mesh.material = scorch_mat
	assets["scorch_mesh"] = scorch_mesh

	_impact_assets[surface] = assets
	return assets


func _get_player() -> Node:
	var node: Node = self
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


func _on_kill_confirmed() -> void:
	hit_confirmed.emit(false, true)
