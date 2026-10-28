extends PlayerState
class_name IdleState

## Состояние покоя: игрок стоит на месте (тормозит по инерции), ждёт ввода.


func physics_update(delta: float) -> void:
	if not player.is_multiplayer_authority():
		return

	_apply_gravity(delta)
	if _try_vault():
		return

	# Движение — если есть ввод, переходим в Walk
	if _get_input_vector().length() > 0.1:
		transitioned.emit("WalkState")
		return

	_apply_horizontal(Vector2.ZERO, GROUND_DECEL, delta)
	player.move_and_slide()

	# Стрельба/перезарядка
	_handle_weapon_input()
