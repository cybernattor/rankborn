extends PlayerState
class_name WalkState

## Состояние ходьбы: игрок движется по WASD.


func physics_update(delta: float) -> void:
	if not player.is_multiplayer_authority():
		return

	_apply_gravity(delta)

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
