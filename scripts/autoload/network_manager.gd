extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_created()
signal connection_failed()
signal connection_succeeded()
signal match_started()
## Хост закрыл игру или связь с ним потеряна (только у клиента).
signal server_disconnected()

const DEFAULT_PORT := 7000
const MAX_CLIENTS := 6
const MAX_NAME_LENGTH := 16

var peer: ENetMultiplayerPeer
var is_host := false
var players: Dictionary = {}
var _match_in_progress := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game(port: int = DEFAULT_PORT) -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_error("Failed to create server: %s" % error_string(err))
		connection_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	players.clear()
	players[1] = {"name": sanitize_name(GameSettings.player_name, 1), "spawn_index": 0}
	var discovery_err := LanDiscovery.start_hosting(port, "Rankborn Lobby")
	if discovery_err != OK:
		push_warning("LAN discovery unavailable — lobby won't be visible in browser")
	server_created.emit()
	print("Server created on port %d" % port)


func join_game(address: String, port: int = DEFAULT_PORT) -> void:
	LanDiscovery.stop()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("Failed to connect: %s" % error_string(err))
		connection_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	is_host = false
	print("Connecting to %s:%d" % [address, port])


func disconnect_game() -> void:
	LanDiscovery.stop()
	if peer:
		peer.close()
		peer = null
	players.clear()
	is_host = false
	_match_in_progress = false
	multiplayer.multiplayer_peer = null


func get_player_id() -> int:
	return multiplayer.get_unique_id()


## Ник для показа: обрезанный, без пустых строк; запасной — «Игрок_NNNN».
static func sanitize_name(raw: String, peer_id: int) -> String:
	var clean := raw.strip_edges().left(MAX_NAME_LENGTH)
	if clean.is_empty():
		clean = "Игрок_%d" % (absi(peer_id) % 10000)
	return clean


## Адрес, который хост показывает друзьям. Сначала частные LAN-диапазоны,
## затем любой другой IPv4 (VPN, CGNAT, нестандартная сеть) — loopback только
## если других нет: 127.0.0.1 с другой машины бесполезен.
func get_lan_ip() -> String:
	var fallback := ""
	for addr in IP.get_local_addresses():
		var parts := addr.split(".")
		if parts.size() != 4:
			continue  # IPv6
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
		if parts[0] == "172" and int(parts[1]) >= 16 and int(parts[1]) <= 31:
			return addr
		if fallback.is_empty() and not addr.begins_with("127.") \
				and not addr.begins_with("169.254.") and addr != "0.0.0.0":
			fallback = addr
	return fallback if not fallback.is_empty() else "127.0.0.1"


func start_match() -> void:
	if not is_host:
		return
	LanDiscovery.stop()
	_match_in_progress = true
	_start_match.rpc()


@rpc("authority", "call_local", "reliable")
func _start_match() -> void:
	match_started.emit()


@rpc("authority", "reliable")
func _sync_player_list(list: Dictionary) -> void:
	players = list
	for id in players:
		player_connected.emit(id)
	print("Synced player list: %s" % str(players.keys()))


func _on_peer_connected(id: int) -> void:
	if not is_host:
		return
	var used_slots: Array[int] = []
	for info in players.values():
		used_slots.append(int(info.spawn_index))
	var spawn_index: int = 0
	while spawn_index in used_slots:
		spawn_index += 1
	# Настоящий ник клиент пришлёт сам (_register_name) сразу после подключения.
	players[id] = {"name": sanitize_name("", id), "spawn_index": spawn_index}
	player_connected.emit(id)
	print("Player connected: %d" % id)

	_sync_player_list.rpc(players)

	if _match_in_progress:
		_start_match.rpc_id(id)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_disconnected.emit(id)
	print("Player disconnected: %d" % id)


func _on_connected_to_server() -> void:
	var my_id := multiplayer.get_unique_id()
	_register_name.rpc_id(1, GameSettings.player_name)
	connection_succeeded.emit()
	print("Connected to server as %d" % my_id)


## Клиент сообщает хосту свой ник; хост проверяет и рассылает список всем.
@rpc("any_peer", "reliable")
func _register_name(raw_name: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	players[id].name = sanitize_name(raw_name, id)
	_sync_player_list.rpc(players)
	player_connected.emit(id)


func _on_server_disconnected() -> void:
	print("Server disconnected")
	disconnect_game()
	server_disconnected.emit()


func _on_connection_failed() -> void:
	connection_failed.emit()
	print("Connection failed")
	peer = null
	multiplayer.multiplayer_peer = null
