extends PlayerState
class_name VaultState

## Перелезание через низкое укрытие, как в Foxhole (пробел / VAULT): свободного прыжка
## нет, но через мешки с песком можно перебраться — медленно и на виду. Пока лезет,
## солдат не стреляет. Маршрут (куда приземлиться, высоту верха) находит
## Player.find_vault(); здесь — только движение по дуге.

const VAULT_TIME := 0.6
## Насколько выше верха укрытия проходит дуга.
const ARC_CLEARANCE := 0.25

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _peak := 0.0
var _progress := 0.0


func enter(msg: Dictionary = {}) -> void:
	_from = player.global_position
	_to = msg.get("landing", _from)
	_peak = msg.get("top", _from.y) + ARC_CLEARANCE
	_progress = 0.0
	player.velocity = Vector3.ZERO
	player.is_vaulting = true
	# Сквозь укрытие проходим по дуге сами, без столкновений.
	player.collision_shape.disabled = true


func exit() -> void:
	player.is_vaulting = false
	player.collision_shape.disabled = not player.health_component.is_alive


func physics_update(delta: float) -> void:
	if not player.is_multiplayer_authority():
		return
	_progress = minf(_progress + delta / VAULT_TIME, 1.0)
	var point := _from.lerp(_to, _progress)
	# Парабола: на середине пути — над верхом укрытия.
	var mid_y := (_from.y + _to.y) * 0.5
	point.y += 4.0 * _progress * (1.0 - _progress) * maxf(_peak - mid_y, 0.0)
	player.global_position = point
	if _progress >= 1.0:
		transitioned.emit("IdleState")
