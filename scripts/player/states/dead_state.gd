extends State
class_name DeadState

## Состояние смерти: игрок мёртв, не управляется, готовится к респавну.

const RESPAWN_DELAY := 2.0


func enter(_msg: Dictionary = {}) -> void:
	# Прячем модельку
	player.visible = false

	# Запускаем таймер респавна (только у авторитетного)
	if player.is_multiplayer_authority():
		_respawn_timer()


func exit() -> void:
	player.visible = true


func physics_update(_delta: float) -> void:
	# В смерти ничего не делаем
	player.velocity = Vector3.ZERO


func _respawn_timer() -> void:
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	transitioned.emit("RespawnState")
