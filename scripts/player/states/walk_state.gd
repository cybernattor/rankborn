extends State
class_name WalkState

## Состояние ходьбы/бега: игрок движется по WASD.

const SPEED := 5.0
const JUMP_VELOCITY := 4.5
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func physics_update(delta: float) -> void:
	if not player.is_multiplayer_authority():
		return

	# Гравитация
	if not player.is_on_floor():
		player.velocity.y -= gravity * delta

	# Прыжок
	if Input.is_action_just_pressed("ui_accept") and player.is_on_floor():
		player.velocity.y = JUMP_VELOCITY
		transitioned.emit("JumpState")
		return

	var input_dir := _get_input_vector()

	# Если нет ввода — возвращаемся в Idle
	if input_dir.length() < 0.1:
		transitioned.emit("IdleState")
		return

	# Движение
	var direction := (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	player.velocity.x = direction.x * SPEED
	player.velocity.z = direction.z * SPEED

	player.move_and_slide()

	# Стрельба/перезарядка
	_handle_weapon_input()


func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("aim"):
		player.set("is_aiming", true)
	if event.is_action_released("aim"):
		player.set("is_aiming", false)


func _get_input_vector() -> Vector2:
	if player.get("mobile_move_input") and player.mobile_move_input != Vector2.ZERO:
		return player.mobile_move_input
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _handle_weapon_input() -> void:
	var weapon_mgr = player.get_node_or_null("WeaponManager")
	if not weapon_mgr:
		return

	var shoot_pressed := Input.is_action_pressed("shoot")
	if player.get("mobile_shoot_pressed"):
		shoot_pressed = true
	if shoot_pressed and weapon_mgr.can_shoot():
		weapon_mgr.shoot()

	var reload_pressed := Input.is_action_just_pressed("reload")
	if player.get("mobile_reload_triggered"):
		reload_pressed = true
		player.mobile_reload_triggered = false
	if reload_pressed:
		weapon_mgr.reload()
