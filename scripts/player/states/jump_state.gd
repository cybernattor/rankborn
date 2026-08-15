extends State
class_name JumpState

## Состояние прыжка/полёта: игрок в воздухе.

const SPEED := 5.0
const JUMP_VELOCITY := 4.5
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func enter(_msg: Dictionary = {}) -> void:
	# Если ещё не прыгнули — задаём импульс
	if player.is_on_floor():
		player.velocity.y = JUMP_VELOCITY


func physics_update(delta: float) -> void:
	if not player.is_multiplayer_authority():
		return

	# Гравитация
	if not player.is_on_floor():
		player.velocity.y -= gravity * delta

	# Управление в воздухе (ограниченное)
	var input_dir := _get_input_vector()
	if input_dir.length() > 0.1:
		var direction := (player.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		player.velocity.x = direction.x * SPEED * 0.7
		player.velocity.z = direction.z * SPEED * 0.7
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, SPEED * 0.3)
		player.velocity.z = move_toward(player.velocity.z, 0, SPEED * 0.3)

	player.move_and_slide()

	# Приземление
	if player.is_on_floor():
		var input_len := _get_input_vector().length()
		if input_len > 0.1:
			transitioned.emit("WalkState")
		else:
			transitioned.emit("IdleState")
		return

	# Стрельба в воздухе
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
