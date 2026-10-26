extends State
class_name PlayerState

## Общая база для стейтов движения (Idle/Walk/Jump):
## гравитация, ускорение, вектор ввода и оружие.
## Весь ввод — через Input-действия: клавиатура, геймпад и MobileUI
## (он нажимает те же действия через Input.action_press).

const SPEED := 5.0
const SPRINT_SPEED := 7.5
const CROUCH_SPEED := 2.5
## С прицелом идут медленно, как в Foxhole.
const AIM_SPEED := 2.2
const JUMP_VELOCITY := 4.5
const GROUND_ACCEL := 45.0
const GROUND_DECEL := 55.0
const AIR_ACCEL := 8.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _apply_gravity(delta: float) -> void:
	if not player.is_on_floor():
		player.velocity.y -= gravity * delta


## Аналоговый ввод движения, длина ≤ 1 (стик/джойстик сохраняет силу отклонения).
func _get_input_vector() -> Vector2:
	if not player.can_control():
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _wants_jump() -> bool:
	return player.can_control() and Input.is_action_just_pressed("jump") and player.is_on_floor()


## Спринт — только примерно туда, куда смотришь, не в прицеле и не в приседе:
## пятиться и бежать боком на полной скорости нельзя.
const SPRINT_MAX_ANGLE_COS := 0.5


func _move_speed(input_dir: Vector2) -> float:
	if player.is_aiming:
		return minf(AIM_SPEED, CROUCH_SPEED) if player.is_crouching else AIM_SPEED
	if player.is_crouching:
		return CROUCH_SPEED
	if Input.is_action_pressed("sprint") and input_dir.length() > 0.5 and not player.is_aiming:
		var facing: Vector3 = player.get_aim_direction()
		if Vector2(facing.x, facing.z).dot(input_dir.normalized()) >= SPRINT_MAX_ANGLE_COS:
			return SPRINT_SPEED
	return SPEED


## Камера сверху не вращается, поэтому движение — в осях мира: «вверх» по экрану
## и стику — это −Z, независимо от того, куда смотрит персонаж.
func _apply_horizontal(input_dir: Vector2, accel: float, delta: float) -> void:
	var direction := Vector3(input_dir.x, 0, input_dir.y)
	var target := direction * _move_speed(input_dir)
	player.velocity.x = move_toward(player.velocity.x, target.x, accel * delta)
	player.velocity.z = move_toward(player.velocity.z, target.z, accel * delta)


## Прыжок из приседа сначала встаёт; возвращает true, если прыгнули.
func _try_jump() -> bool:
	if not _wants_jump():
		return false
	if player.is_crouching:
		player.stand_up()
		return false
	player.velocity.y = JUMP_VELOCITY
	transitioned.emit("JumpState")
	return true


# Единственная точка опроса стрельбы/перезарядки — через WeaponManager.
func _handle_weapon_input() -> void:
	if not player.can_control():
		return
	var weapon_mgr: WeaponManager = player.get_node_or_null("WeaponManager")
	if not weapon_mgr:
		return
	if Input.is_action_pressed("shoot") and weapon_mgr.can_shoot():
		weapon_mgr.shoot()
	if Input.is_action_just_pressed("reload"):
		weapon_mgr.reload()
