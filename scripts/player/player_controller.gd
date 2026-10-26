extends CharacterBody3D

## Контроллер игрока. Камера сверху (IsoCamera), направление прицеливания
## (мышь — курсор, геймпад и тач — правый стик), меш тела, присед, видимость в тумане
## войны, состояние (FSM), здоровье (HealthComponent) и оружие (WeaponManager).
## Движение читают стейты (PlayerState) через Input-действия — у ПК, геймпада и
## мобильного UI один и тот же путь ввода.

@onready var head: Node3D = $Head
@onready var camera: IsoCamera = $IsoCamera
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

## HUD и экран смерти есть только у локального игрока.
var weapon_hud: CanvasLayer
var death_screen: DeathScreen

# Прицеливание: в прицеле (ADS) камера уходит дальше в сторону взгляда,
# а разброс сужается (Rifle.get_spread_angle) — зума нет, как у Foxhole.
var is_aiming: bool = false
## Точка, куда целится игрок (мир): на высоте выстрела над землёй под прицелом.
var aim_point: Vector3 = Vector3.ZERO
var _aim_direction := Vector3.FORWARD
var _aim_distance: float = STICK_AIM_DISTANCE
## Последним прицеливались мышью (иначе — стиком). Переключается тем, чем пошевелили.
var _mouse_aim: bool = true
## Высота выстрела над ногами: от груди, а не от глаз — пуля летит из оружия.
const SHOT_HEIGHT := 1.25
## Стиком (геймпад, тач) целимся на фиксированную дальность; в прицеле — дальше.
## Точка прицела должна оставаться на экране: по вертикали камера сверху видит
## примерно ±9 м от центра, и при 16 м прицел стиком «вверх» уходил за край.
const STICK_AIM_DISTANCE := 11.0
const STICK_AIM_DISTANCE_ADS := 20.0
const STICK_AIM_DEADZONE := 0.2
## Курсор ближе этого к игроку не меняет направление: иначе персонаж крутится на месте.
const MIN_MOUSE_AIM_DISTANCE := 1.0

## Туман войны: хост решил, что этого (удалённого) игрока нам не видно
## (VisibilityManager). Не рисуется и не ловит пули — иначе можно стрелять по призраку
## в последней известной позиции.
var fog_hidden: bool = false:
	set(value):
		if fog_hidden == value:
			return
		fog_hidden = value
		_update_presence()

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
		camera.target = self
		camera.current = true
		_mouse_aim = not GameSettings.is_touch_device()
		if _mouse_aim:
			# Курсор прячем и держим в окне: вместо него рисуется прицел HUD.
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
		_setup_weapon_hud()
		death_screen = DeathScreen.new()
		death_screen.name = "DeathScreen"
		add_child(death_screen)

		# Туман войны: свою позицию шлём только тем, кого назовёт хост
		# (VisibilityManager), и всегда — самому хосту.
		var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer
		sync.public_visibility = false
		sync.set_visibility_for(1, true)

		# Подключаем смерть → StateMachine
		health_component.died.connect(_on_died)
	else:
		camera.current = false
		camera.set_process(false)
		# Чужих игроков не видно, пока хост не скажет обратное (туман войны).
		fog_hidden = true
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
	weapon_hud = hud


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
		_aim_direction = to_center.normalized()
		rotation.y = atan2(-_aim_direction.x, -_aim_direction.z)
	_aim_distance = STICK_AIM_DISTANCE
	aim_point = _compute_aim_point()
	head.position.y = get_head_height()
	if is_node_ready() and camera.current:
		camera.snap()


## Можно ли сейчас управлять персонажем (жив и не открыто меню).
func can_control() -> bool:
	return health_component.is_alive and not input_blocked


## Высота головы для текущей позы (на ней висит оружие).
func get_head_height() -> float:
	return CROUCH_HEAD_Y if is_crouching else STAND_HEAD_Y


## Текущий рост капсулы — для хитбоксов и проверки хедшота.
func get_body_height() -> float:
	return CROUCH_HEIGHT if is_crouching else STAND_HEIGHT


## Откуда летит выстрел (мир).
func get_shot_origin() -> Vector3:
	return global_position + Vector3.UP * (SHOT_HEIGHT * get_body_height() / STAND_HEIGHT)


## Горизонтальное направление прицеливания (единичное).
func get_aim_direction() -> Vector3:
	return _aim_direction


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_update_crouch()
	if not state_machine.current_state:
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		move_and_slide()


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	# Пошевелили мышью — снова целимся курсором (после геймпада).
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION \
			and not GameSettings.is_touch_device():
		_mouse_aim = true


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
	# Голова (и оружие на ней) плавно опускается при приседании — у всех пиров.
	head.position.y = lerpf(head.position.y, get_head_height(), 1.0 - exp(-CROUCH_TRANSITION_SPEED * delta))
	if not is_multiplayer_authority():
		return
	_update_aim()
	if can_control():
		_update_aim_direction()
		rotation.y = atan2(-_aim_direction.x, -_aim_direction.z)
	aim_point = _compute_aim_point()


## Направление прицеливания: правый стик (геймпад; на таче его нажимает MobileUI)
## или курсор мыши. Камера не вращается, поэтому стик задаёт направление в мире
## напрямую: вверх по экрану — это −Z.
func _update_aim_direction() -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() > STICK_AIM_DEADZONE:
		_mouse_aim = false
		_aim_direction = Vector3(stick.x, 0.0, stick.y).normalized()
		_aim_distance = STICK_AIM_DISTANCE_ADS if is_aiming else STICK_AIM_DISTANCE
		return
	if not _mouse_aim:
		_aim_distance = STICK_AIM_DISTANCE_ADS if is_aiming else STICK_AIM_DISTANCE
		return
	var cursor := get_viewport().get_mouse_position()
	var on_plane := camera.screen_to_plane(cursor, get_shot_origin().y)
	var to_cursor := (on_plane - global_position) * Vector3(1, 0, 1)
	if to_cursor.length() > MIN_MOUSE_AIM_DISTANCE:
		_aim_direction = to_cursor.normalized()
		_aim_distance = to_cursor.length()


func _compute_aim_point() -> Vector3:
	var point := global_position + _aim_direction * _aim_distance
	point.y = _ground_height_at(point) + SHOT_HEIGHT
	return point


# Высота земли без физики (та же формула, что у меша); вне игровой сцены — свой уровень.
func _ground_height_at(point: Vector3) -> float:
	var scene := get_tree().current_scene
	if scene and scene.has_method("ground_height_at"):
		return scene.ground_height_at(point.x, point.z)
	return global_position.y


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


# Виден и ловит пули только живой и не скрытый туманом войны.
func _update_presence() -> void:
	if not is_node_ready():
		return
	var present := health_component.is_alive and not fog_hidden
	visible = present
	collision_shape.set_deferred("disabled", not present)


func _on_life_state_changed(alive: bool) -> void:
	_update_presence()
	if not alive:
		velocity = Vector3.ZERO
		is_aiming = false
		_crouch_toggled = false
		if is_multiplayer_authority():
			is_crouching = false
	if is_multiplayer_authority():
		if weapon_hud:
			weapon_hud.visible = alive
		if alive and death_screen:
			death_screen.hide_death()


func _on_died(attacker_id: int) -> void:
	state_machine.change_state("DeadState")
	death_screen.show_death(_killer_name(attacker_id), DeadState.RESPAWN_DELAY)
	# Только сама жертва (authority своего HealthComponent, т.е. эта ветка)
	# знает о своей смерти — сообщаем хосту, чтобы GameMode/счёт/killfeed
	# обновились одинаково у всех.
	var game_mode := get_tree().current_scene.get_node_or_null("GameMode")
	if game_mode:
		game_mode.report_death.rpc_id(1, multiplayer.get_unique_id(), attacker_id)


## Ник убийцы; пусто — погиб сам (зона смерти, свой урон).
func _killer_name(attacker_id: int) -> String:
	if attacker_id <= 0 or attacker_id == get_multiplayer_authority():
		return ""
	return NetworkManager.players.get(attacker_id, {}).get("name", NetworkManager.sanitize_name("", attacker_id))
