extends State
class_name DeadState

## Состояние смерти: игрок мёртв, не управляется, готовится к респавну.

const RESPAWN_DELAY := 2.0

var _body_mesh: MeshInstance3D
var _left_arm: MeshInstance3D
var _right_arm: MeshInstance3D


func enter(_msg: Dictionary = {}) -> void:
	# Находим меши
	_body_mesh = player.get_node_or_null("BodyMesh") as MeshInstance3D
	# Меши рук — в камере
	var camera := player.get_node_or_null("Head/Camera3D")
	if camera:
		_left_arm = camera.get_node_or_null("LeftArm") as MeshInstance3D
		_right_arm = camera.get_node_or_null("RightArm") as MeshInstance3D

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
