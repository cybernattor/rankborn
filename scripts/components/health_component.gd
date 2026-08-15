extends Node
class_name HealthComponent

## Компонент здоровья. Обрабатывает получение урона, смерть и регенерацию.
## Работает по сети: RPC any_peer → authority.

signal health_changed(new_health: float)
signal died

@export var max_health: float = 100.0

var current_health: float
var is_alive: bool = true


func _ready() -> void:
	current_health = max_health
	is_alive = true


## Получение урона. RPC from any peer → authority.
## Используется так: `health_component.take_damage.rpc_id(authority_id, amount)`
@rpc("any_peer", "reliable")
func take_damage(amount: float) -> void:
	if not is_multiplayer_authority() or not is_alive:
		return

	current_health = maxf(current_health - amount, 0.0)
	health_changed.emit(current_health)

	if current_health <= 0.0:
		is_alive = false
		died.emit()


## Лечение (локальное, не RPC)
func heal(amount: float) -> void:
	if not is_alive:
		return
	current_health = minf(current_health + amount, max_health)
	health_changed.emit(current_health)


## Полный сброс здоровья
func reset() -> void:
	current_health = max_health
	is_alive = true
	health_changed.emit(current_health)
