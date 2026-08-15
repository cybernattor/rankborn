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

	# Прячем меши для локального игрока (first-person)
	if player.is_multiplayer_authority():
		var body := player.get_node_or_null("BodyMesh")
		if body:
			body.visible = false
		var camera := player.get_node_or_null("Head/Camera3D")
		if camera:
			var la := camera.get_node_or_null("LeftArm")
			if la: la.visible = false
			var ra := camera.get_node_or_null("RightArm")
			if ra: ra.visible = false

	# Сразу переходим в Idle
	transitioned.emit("IdleState")


func physics_update(_delta: float) -> void:
	pass
