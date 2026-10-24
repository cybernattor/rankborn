extends PlayerState
class_name IdleState

## Состояние покоя: игрок стоит на месте, ждёт ввода.


func physics_update(delta: float) -> void:
	if not player.is_multiplayer_authority():
		return

	_apply_gravity(delta)

	# Прыжок
	if Input.is_action_just_pressed("ui_accept") and player.is_on_floor():
		player.velocity.y = JUMP_VELOCITY
		transitioned.emit("JumpState")

	# Движение — если есть ввод, переходим в Walk
	var input_dir := _get_input_vector()
	if input_dir.length() > 0.1:
		transitioned.emit("WalkState")
		return

	# Гасим горизонтальную скорость
	player.velocity.x = move_toward(player.velocity.x, 0, SPEED)
	player.velocity.z = move_toward(player.velocity.z, 0, SPEED)

	player.move_and_slide()

	# Стрельба/перезарядка
	_handle_weapon_input()
