extends PlayerState
class_name JumpState

## Состояние прыжка/полёта: игрок в воздухе.


func enter(_msg: Dictionary = {}) -> void:
	# Если ещё не прыгнули — задаём импульс
	if player.is_on_floor():
		player.velocity.y = JUMP_VELOCITY


func physics_update(delta: float) -> void:
	if not player.is_multiplayer_authority():
		return

	_apply_gravity(delta)

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
		if input_dir.length() > 0.1:
			transitioned.emit("WalkState")
		else:
			transitioned.emit("IdleState")
		return

	# Стрельба в воздухе
	_handle_weapon_input()
