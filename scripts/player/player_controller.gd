extends CharacterBody3D

## Контроллер игрока. Управляет камерой (мышь, геймпад, свайп), мешем тела,
## приседанием, состоянием (FSM), здоровьем (HealthComponent) и оружием (WeaponManager).
## Референсы: Head/Camera3D, HealthComponent, StateMachine, WeaponManager — дочерние ноды.
## Движение читают стейты (PlayerState) через Input-действия — у ПК, геймпада и
## мобильного UI один и тот же путь ввода.

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var state_machine: StateMachine = $StateMachine
@onready var weapon_manager: WeaponManager = $WeaponManager
@onready var health_component: HealthComponent = $HealthComponent

# Меш тела (именованный, доступен из State)
var body_mesh: MeshInstance3D

var spawn_position: Vector3 = Vector3.ZERO
## Куда смотрит игрок после спавна (центр игровой зоны).
const MAP_CENTER := Vector3.ZERO

## Ввод заблокирован меню (пауза не останавливает сетевую игру).
var input_blocked: bool = false

# Отдача камеры
var _recoil_x: float = 0.0
var _recoil_recovery := 8.0

# Прицеливание
var is_aiming: bool = false
const DEFAULT_FOV := 75.0
const AIM_FOV := 30.0
const AIM_FOV_SPEED := 12.0

# Рост: стоя / присев. Капсула, голова и меш меняются вместе,
# чтобы хитбокс совпадал с тем, что видят другие игроки.
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const STAND_HEAD_Y := 1.6
const CROUCH_HEAD_Y := 1.05
const CROUCH_TRANSITION_SPEED := 10.0

## Синхронизируется по сети (SceneReplicationConfig в player.tscn).
var is_crouching: bool = false:
	set(value):
		if is_crouching == value:
			return
		is_crouching = value
		_apply_body_height()

var _crouch_toggled: bool = false


func _ready() -> void:
	# Форма капсулы — общий SubResource сцены; у каждого игрока должна быть своя,
	# иначе приседание одного меняет хитбоксы всех.
	collision_shape.shape = collision_shape.shape.duplicate()
	_build_lowpoly_body()
	health_component.life_state_changed.connect(_on_life_state_changed)

	if is_multiplayer_authority():
		camera.current = true
		if not GameSettings.is_touch_device():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Своё тело не рисуем (камера внутри головы), но тень от него оставляем.
		body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_setup_weapon_hud()

		# Подключаем смерть → StateMachine
		health_component.died.connect(_on_died)
	else:
		camera.current = false
	_apply_body_height()
	_on_life_state_changed(health_component.is_alive)


func _build_lowpoly_body() -> void:
	var humanoid_mesh := MeshUtils.make_humanoid()
	var mat := MeshUtils.flat_material(Color.WHITE)

	body_mesh = MeshInstance3D.new()
	body_mesh.name = "BodyMesh"
	body_mesh.mesh = humanoid_mesh
	body_mesh.set_surface_override_material(0, mat)
	add_child(body_mesh)


func _setup_weapon_hud() -> void:
	var hud_scene := preload("res://scenes/ui/weapon_hud.tscn")
	var hud: CanvasLayer = hud_scene.instantiate()
	hud.name = "WeaponHUD"
	add_child(hud)
	hud.setup(weapon_manager)


func setup_spawn(pos: Vector3) -> void:
	spawn_position = pos
	global_position = pos
	face_map_center()


## После (ре)спавна смотрим к центру карты, а не туда, куда смотрел перед смертью:
## спавны стоят у края, и старый взгляд часто упирался в обрыв за границей карты.
func face_map_center() -> void:
	var to_center := MAP_CENTER - global_position
	to_center.y = 0.0
	if to_center.length_squared() > 0.01:
		rotation.y = atan2(-to_center.x, -to_center.z)
	head.rotation.x = 0.0
	_recoil_x = 0.0


## Можно ли сейчас управлять персонажем (жив и не открыто меню).
func can_control() -> bool:
	return health_component.is_alive and not input_blocked


## Текущий рост капсулы — для хитбоксов и проверки хедшота.
func get_body_height() -> float:
	return CROUCH_HEIGHT if is_crouching else STAND_HEIGHT


func apply_recoil(amount: float) -> void:
	var previous_pitch := head.rotation.x
	head.rotation.x = clampf(previous_pitch + amount, -PI / 2, PI / 2)
	_recoil_x += head.rotation.x - previous_pitch


## Поворот камеры в радианах. Чувствительность масштабируется по FOV,
## чтобы в прицеле движение на экране ощущалось так же, как от бедра.
func look(delta_radians: Vector2) -> void:
	if not is_multiplayer_authority() or not can_control():
		return
	var fov_scale := tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(DEFAULT_FOV) * 0.5)
	var pitch_sign := -1.0 if GameSettings.invert_y else 1.0
	rotate_y(-delta_radians.x * fov_scale)
	head.rotate_x(-delta_radians.y * fov_scale * pitch_sign)
	head.rotation.x = clamp(head.rotation.x, -PI / 2, PI / 2)


## Свайп по экрану (пиксели) от MobileUI.
func apply_touch_look(delta_pixels: Vector2) -> void:
	look(delta_pixels * GameSettings.touch_sensitivity)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_update_crouch()
	if not state_machine.current_state:
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		move_and_slide()


# Мышь обрабатываем в _input, а не в _unhandled_input: элементы HUD под
# захваченным курсором (он всегда в центре экрана) не должны съедать обзор.
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and event.device != InputEvent.DEVICE_ID_EMULATION:
		# screen_relative не зависит от растяжения окна (stretch).
		look(event.screen_relative * GameSettings.mouse_sensitivity)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	# Меню открывается и во время смерти.
	if event.is_action_pressed("pause"):
		var pause_menu = get_tree().current_scene.get_node_or_null("UILayer/PauseMenu")
		if pause_menu:
			pause_menu.toggle()
		return
	if not can_control():
		return
	if event.is_action_pressed("weapon_next"):
		weapon_manager.next_weapon()
	elif event.is_action_pressed("weapon_prev"):
		weapon_manager.prev_weapon()


func _process(delta: float) -> void:
	# Голова плавно опускается при приседании — у всех пиров, чтобы оружие
	# удалённого игрока было на правильной высоте.
	var head_target := CROUCH_HEAD_Y if is_crouching else STAND_HEAD_Y
	head.position.y = lerpf(head.position.y, head_target, 1.0 - exp(-CROUCH_TRANSITION_SPEED * delta))

	if not is_multiplayer_authority():
		return

	# Геймпад: правый стик
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick != Vector2.ZERO:
		look(stick * GameSettings.gamepad_look_speed * delta)

	_update_aim()

	# Восстановление отдачи камеры
	if _recoil_x != 0.0:
		var step := _recoil_x * (1.0 - exp(-_recoil_recovery * delta))
		head.rotation.x -= step
		head.rotation.x = clamp(head.rotation.x, -PI / 2, PI / 2)
		_recoil_x -= step
		if abs(_recoil_x) < 0.0001:
			_recoil_x = 0.0

	# Плавная смена FOV при прицеливании
	var target_fov := AIM_FOV if is_aiming else DEFAULT_FOV
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-AIM_FOV_SPEED * delta))


func _update_aim() -> void:
	if not can_control():
		is_aiming = false
		return
	if GameSettings.uses_aim_toggle():
		if Input.is_action_just_pressed("aim"):
			is_aiming = not is_aiming
	else:
		is_aiming = Input.is_action_pressed("aim")


func _update_crouch() -> void:
	if not can_control():
		_crouch_toggled = false
		if is_crouching and _can_stand_up():
			is_crouching = false
		return
	var wants_crouch: bool
	if GameSettings.uses_crouch_toggle():
		if Input.is_action_just_pressed("crouch"):
			_crouch_toggled = not _crouch_toggled
		wants_crouch = _crouch_toggled
	else:
		wants_crouch = Input.is_action_pressed("crouch")
	if wants_crouch:
		is_crouching = true
	elif is_crouching and _can_stand_up():
		is_crouching = false


## Прыжок из приседа сначала поднимает игрока (если есть место).
func stand_up() -> bool:
	if not is_crouching:
		return true
	if not _can_stand_up():
		return false
	_crouch_toggled = false
	is_crouching = false
	return true


func _can_stand_up() -> bool:
	# Проверяем только объём над присевшей капсулой: полная капсула
	# задевала бы склон под ногами, и на неровной земле встать было бы нельзя.
	var cylinder := CylinderShape3D.new()
	cylinder.radius = (collision_shape.shape as CapsuleShape3D).radius
	cylinder.height = STAND_HEIGHT - CROUCH_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = cylinder
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (CROUCH_HEIGHT + cylinder.height * 0.5))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _apply_body_height() -> void:
	if not is_node_ready():
		return
	var height := get_body_height()
	var capsule := collision_shape.shape as CapsuleShape3D
	capsule.height = height
	collision_shape.position.y = height * 0.5
	# Временно, до анимаций: меш сжимается по высоте вместе с хитбоксом.
	body_mesh.scale.y = height / STAND_HEIGHT


func _on_life_state_changed(alive: bool) -> void:
	visible = alive
	collision_shape.set_deferred("disabled", not alive)
	if not alive:
		velocity = Vector3.ZERO
		is_aiming = false
		_recoil_x = 0.0
		_crouch_toggled = false
		if is_multiplayer_authority():
			is_crouching = false


func _on_died(attacker_id: int) -> void:
	state_machine.change_state("DeadState")
	# Только сама жертва (authority своего HealthComponent, т.е. эта ветка)
	# знает о своей смерти — сообщаем хосту, чтобы GameMode/счёт/killfeed
	# обновились одинаково у всех.
	var game_mode := get_tree().current_scene.get_node_or_null("GameMode")
	if game_mode:
		game_mode.report_death.rpc_id(1, multiplayer.get_unique_id(), attacker_id)
