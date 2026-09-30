extends Node
class_name GameMode

## Базовый класс игрового режима (GameMode).
## Определяет правила игры: спавн, смерти, очки, условия победы.

signal player_spawned(player_id: int)
signal player_died(player_id: int, killer_id: int)
signal player_respawned(player_id: int)
signal score_updated

## Ссылка на GameScene (корневой узел)
var game_scene: Node3D


func _ready() -> void:
	game_scene = get_parent()


## Вызывается при спавне игрока
func on_player_spawn(player_id: int) -> void:
	player_spawned.emit(player_id)


## Вызывается при смерти игрока
func on_player_die(player_id: int, killer_id: int = -1) -> void:
	player_died.emit(player_id, killer_id)


## Жертва (authority своего HealthComponent) сообщает хосту о своей смерти.
## Только хост ведёт единый, авторитетный счёт — поэтому вызов всегда
## адресован peer 1, а не выполняется локально у отправителя.
@rpc("any_peer", "call_local", "reliable")
func report_death(victim_id: int, killer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_broadcast_death.rpc(victim_id, killer_id)


## Хост рассылает подтверждённую смерть всем (и себе, через call_local),
## чтобы GameMode/UI на каждом клиенте обновились одинаково и синхронно.
@rpc("authority", "call_local", "reliable")
func _broadcast_death(victim_id: int, killer_id: int) -> void:
	on_player_die(victim_id, killer_id)


## Вызывается при респавне игрока
func on_player_respawn(player_id: int) -> void:
	player_respawned.emit(player_id)


## Вызывается при нанесении урона
func on_player_damage(victim_id: int, attacker_id: int, damage: float) -> void:
	pass
