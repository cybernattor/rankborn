extends Node
class_name HealthComponent

## Компонент здоровья. Обрабатывает получение урона, смерть и регенерацию.
## Работает по сети: RPC any_peer → authority.

signal health_changed(new_health: float)
signal died(attacker_id: int)
signal life_state_changed(alive: bool)
## Локальный сигнал: приходит только на машине атакующего, когда жертва
## подтвердила, что удар был смертельным (см. _notify_kill).
signal kill_confirmed

@export var max_health: float = 100.0

var current_health: float
var is_alive: bool = true:
	set(value):
		if is_alive == value:
			return
		is_alive = value
		life_state_changed.emit(value)


func _ready() -> void:
	current_health = max_health
	is_alive = true


## Получение урона. RPC from any peer → authority.
## Используется так: `health_component.take_damage.rpc_id(authority_id, amount, attacker_id)`
@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: float, attacker_id: int = -1) -> void:
	if not is_multiplayer_authority() or not is_alive:
		return

	current_health = maxf(current_health - amount, 0.0)
	health_changed.emit(current_health)

	if current_health <= 0.0:
		is_alive = false
		died.emit(attacker_id)
		# Сообщаем атакующему, что это был смертельный удар — только у него
		# должен сработать красный kill-маркер, а не на основании локальной,
		# несинхронизированной копии is_alive (которая всегда была бы stale).
		# Стрелок мог выйти, пока летел урон, — RPC неизвестному пиру даёт ошибку.
		if attacker_id > 0 and attacker_id != get_multiplayer_authority() \
				and attacker_id in multiplayer.get_peers():
			_notify_kill.rpc_id(attacker_id)


## Вызывается жертвой (authority этого компонента) на машине атакующего.
## Именно поэтому rpc-режим "authority": проверка на стороне получателя
## гарантирует, что сообщение реально пришло от владельца этого HealthComponent.
@rpc("authority", "reliable")
func _notify_kill() -> void:
	kill_confirmed.emit()


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
