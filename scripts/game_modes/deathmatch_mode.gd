extends GameMode
class_name DeathmatchMode

## Режим Deathmatch: каждый сам за себя, игра до N фрагов.

signal killfeed_entry(killer_name: String, victim_name: String, weapon_name: String)

@export var frag_limit: int = 20

## Таблица счёта: peer_id → { kills, deaths, name }
var scores: Dictionary = {}


func _ready() -> void:
	super._ready()
	# Подключаемся к сигналам GameMode
	player_died.connect(on_player_die)


func on_player_spawn(player_id: int) -> void:
	super.on_player_spawn(player_id)
	# Инициализируем запись в таблице, если новая
	if not scores.has(player_id):
		var player_name: String = NetworkManager.players.get(player_id, {}).get("name", "Player %d" % player_id)
		scores[player_id] = {
			"kills": 0,
			"deaths": 0,
			"name": player_name
		}


func on_player_die(player_id: int, killer_id: int = -1) -> void:
	super.on_player_die(player_id, killer_id)

	# Обновляем счёт
	var entry: Dictionary = scores.get(player_id, { "kills": 0, "deaths": 0, "name": "?" })
	if entry:
		entry.deaths += 1

	if killer_id != -1 and killer_id != player_id:
		var killer_entry: Dictionary = scores.get(killer_id, { "kills": 0, "deaths": 0, "name": "?" })
		if killer_entry:
			killer_entry.kills += 1
			killfeed_entry.emit(killer_entry.name, entry.get("name", "?"), "Rifle")
	elif killer_id == player_id:
		# Самоубийство
		killfeed_entry.emit("World", entry.get("name", "?"), "")

	score_updated.emit()


func get_score(player_id: int) -> Dictionary:
	return scores.get(player_id, { "kills": 0, "deaths": 0, "name": "?" })


func get_leaderboard() -> Array:
	## Возвращает отсортированный список игроков по убийствам.
	var list: Array = []
	for pid in scores:
		list.append({
			"id": pid,
			"kills": scores[pid].kills,
			"deaths": scores[pid].deaths,
			"name": scores[pid].name
		})
	list.sort_custom(func(a, b): return a.kills > b.kills)
	return list


func has_winner() -> bool:
	for pid in scores:
		if scores[pid].kills >= frag_limit:
			return true
	return false


func get_winner() -> Dictionary:
	var best_id: int = -1
	var best_kills: int = -1
	for pid in scores:
		if scores[pid].kills > best_kills:
			best_kills = scores[pid].kills
			best_id = pid
	if best_id != -1 and best_kills >= frag_limit:
		return { "id": best_id, "kills": best_kills, "name": scores[best_id].name }
	return {}
