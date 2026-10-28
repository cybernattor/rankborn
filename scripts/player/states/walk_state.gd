extends PlayerState
class_name WalkState

## Состояние ходьбы/спринта/движения в приседе.


func physics_update(delta: float) -> void:
	if not player.is_multiplayer_authority():
		return

	_apply_gravity(delta)

	var input_dir := _get_input_vector()

	# Если нет ввода — возвращаемся в Idle (там гасим скорость)
	if input_dir.length() < 0.1:
		transitioned.emit("IdleState")
		return

	_apply_horizontal(input_dir, GROUND_ACCEL, delta)
	player.move_and_slide()

	# Сошли с обрыва — дальше летим
	if not player.is_on_floor():
		transitioned.emit("JumpState")
		return

	# Стрельба/перезарядка
	_handle_weapon_input()
