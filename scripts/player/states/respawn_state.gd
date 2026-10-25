extends State
class_name RespawnState

## Состояние респавна: восстанавливает игрока и переходит в IdleState.

func enter(_msg: Dictionary = {}) -> void:
	if not player.is_multiplayer_authority():
		return

	# Сначала переносим на точку спавна, потом «оживляем»: иначе другие игроки
	# могли увидеть ожившее тело на месте смерти (после зоны смерти — под картой).
	player.global_position = player.spawn_position
	player.face_map_center()
	var health: HealthComponent = player.get_node_or_null("HealthComponent")
	if health:
		health.reset()

	player.velocity = Vector3.ZERO
	player.visible = true

	# Сразу переходим в Idle
	transitioned.emit("IdleState")


func physics_update(_delta: float) -> void:
	pass
