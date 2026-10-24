extends State
class_name PlayerState

## Общая база для стейтов движения (Idle/Walk/Jump):
## гравитация, вектор ввода (клавиатура или мобильный джойстик) и оружие.

const SPEED := 5.0
const JUMP_VELOCITY := 4.5
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _apply_gravity(delta: float) -> void:
	if not player.is_on_floor():
		player.velocity.y -= gravity * delta


func _get_input_vector() -> Vector2:
	if player.get("mobile_move_input") and player.mobile_move_input != Vector2.ZERO:
		return player.mobile_move_input
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


# Единственная точка опроса стрельбы/перезарядки — через WeaponManager.
func _handle_weapon_input() -> void:
	var weapon_mgr: WeaponManager = player.get_node_or_null("WeaponManager")
	if not weapon_mgr:
		return

	var shoot_pressed := Input.is_action_pressed("shoot")
	if player.get("mobile_shoot_pressed"):
		shoot_pressed = true
	if shoot_pressed and weapon_mgr.can_shoot():
		weapon_mgr.shoot()

	var reload_pressed := Input.is_action_just_pressed("reload")
	if player.get("mobile_reload_triggered"):
		reload_pressed = true
		player.mobile_reload_triggered = false
	if reload_pressed:
		weapon_mgr.reload()
