extends State
class_name RespawnState

## Состояние респавна: восстанавливает игрока и переходит в IdleState.

func enter(_msg: Dictionary = {}) -> void:
	if not player.is_multiplayer_authority():
		return

	# Восстанавливаем здоровье
	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health:
		health.reset()

	# Позиция спавна
	var spawn_pos: Variant = player.get("spawn_position")
	if spawn_pos != null:
		player.global_position = spawn_pos

	player.velocity = Vector3.ZERO
	player.visible = true

	# Сразу переходим в Idle
	transitioned.emit("IdleState")


func physics_update(_delta: float) -> void:
	pass
