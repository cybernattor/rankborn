extends CharacterBody3D

## Контроллер игрока. Управляет камерой, мешем тела, состоянием (FSM),
## здоровьем (HealthComponent) и оружием (WeaponManager).
## Референсы: Head/Camera3D, HealthComponent, StateMachine, WeaponManager — дочерние ноды.

const MOUSE_SENSITIVITY := 0.002

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var state_machine: StateMachine = $StateMachine
@onready var weapon_manager: WeaponManager = $WeaponManager
@onready var health_component: HealthComponent = $HealthComponent

# Меш тела (именованный, доступен из State)
var body_mesh: MeshInstance3D

var spawn_position: Vector3 = Vector3.ZERO

# --- Mobile input (прокси из game_scene) ---
var mobile_move_input: Vector2 = Vector2.ZERO
var mobile_look_input: Vector2 = Vector2.ZERO
var mobile_shoot_pressed: bool = false
var mobile_reload_triggered: bool = false
var mobile_interact_triggered: bool = false

# Отдача камеры
var _recoil_x: float = 0.0
var _recoil_recovery := 8.0

# Прицеливание
var is_aiming: bool = false
const DEFAULT_FOV := 75.0
const AIM_FOV := 30.0
const AIM_FOV_SPEED := 12.0


func _ready() -> void:
	_build_lowpoly_body()
	health_component.life_state_changed.connect(_on_life_state_changed)

	if is_multiplayer_authority():
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Своё тело не рисуем (камера внутри головы), но тень от него оставляем.
		body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_setup_weapon_hud()

		# Подключаем смерть → StateMachine
		health_component.died.connect(_on_died)
	else:
		camera.current = false
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


func apply_recoil(amount: float) -> void:
	var previous_pitch := head.rotation.x
	head.rotation.x = clampf(previous_pitch + amount, -PI / 2, PI / 2)
	_recoil_x += head.rotation.x - previous_pitch


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if not state_machine.current_state:
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	# Пропускаем события если игрок мёртв (DeadState активен)
	if not health_component.is_alive:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, -PI / 2, PI / 2)
	if event.is_action_pressed("aim"):
		is_aiming = true
	if event.is_action_released("aim"):
		is_aiming = false
	if event.is_action_pressed("ui_cancel"):
		var pause_menu = get_tree().current_scene.get_node_or_null("PauseMenu")
		if pause_menu:
			pause_menu.toggle()
		else:
			Input.mouse_mode = (
				Input.MOUSE_MODE_VISIBLE
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				else Input.MOUSE_MODE_CAPTURED
			)


func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

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


func _on_life_state_changed(alive: bool) -> void:
	visible = alive
	$CollisionShape3D.set_deferred("disabled", not alive)
	if not alive:
		velocity = Vector3.ZERO
		is_aiming = false
		_recoil_x = 0.0


func _on_died(attacker_id: int) -> void:
	state_machine.change_state("DeadState")
	# Только сама жертва (authority своего HealthComponent, т.е. эта ветка)
	# знает о своей смерти — сообщаем хосту, чтобы GameMode/счёт/killfeed
	# обновились одинаково у всех.
	var game_mode := get_tree().current_scene.get_node_or_null("GameMode")
	if game_mode:
		game_mode.report_death.rpc_id(1, multiplayer.get_unique_id(), attacker_id)


func _on_mobile_input(action: String, value) -> void:
	if not is_multiplayer_authority() or not health_component.is_alive:
		return
	match action:
		"mobile_move":
			mobile_move_input = value
		"mobile_look":
			mobile_look_input = value
			rotate_y(-value.x * MOUSE_SENSITIVITY * 8.0)
			head.rotate_x(-value.y * MOUSE_SENSITIVITY * 8.0)
			head.rotation.x = clamp(head.rotation.x, -PI / 2, PI / 2)
		"mobile_shoot":
			mobile_shoot_pressed = value
		"mobile_reload":
			mobile_reload_triggered = value
		"mobile_interact":
			mobile_interact_triggered = value
