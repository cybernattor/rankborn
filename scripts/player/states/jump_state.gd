extends PlayerState
class_name JumpState

## Состояние прыжка/полёта: игрок в воздухе, управление ограничено (инерция).


func physics_update(delta: float) -> void:
	if not player.is_multiplayer_authority():
		return

	_apply_gravity(delta)

	var input_dir := _get_input_vector()
	_apply_horizontal(input_dir, AIR_ACCEL, delta)
	player.move_and_slide()

	# Приземление
	if player.is_on_floor() and player.velocity.y <= 0.0:
		transitioned.emit("WalkState" if input_dir.length() > 0.1 else "IdleState")
		return

	# Стрельба в воздухе
	_handle_weapon_input()
