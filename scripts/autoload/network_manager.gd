extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_created()
signal connection_failed()
signal connection_succeeded()
signal match_started()

const DEFAULT_PORT := 7000
const MAX_CLIENTS := 6

var peer: ENetMultiplayerPeer
var is_host := false
var players: Dictionary = {}
var _match_in_progress := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)


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
	players[1] = {"name": "Host"}
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


func get_player_name() -> String:
	return "Player_%d" % multiplayer.get_unique_id()


func get_lan_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
		var parts := addr.split(".")
		if parts.size() == 4 and parts[0] == "172":
			var second := int(parts[1])
			if second >= 16 and second <= 31:
				return addr
	return "127.0.0.1"


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
	player_connected.emit(multiplayer.get_unique_id())
	print("Synced player list: %s" % str(players.keys()))


@rpc("authority", "reliable")
func _register_player(id: int, player_name: String) -> void:
	players[id] = {"name": player_name}
	player_connected.emit(id)
	print("Registered remote player: %d" % id)


func _on_peer_connected(id: int) -> void:
	players[id] = {"name": "Player_%d" % id}
	player_connected.emit(id)
	print("Player connected: %d" % id)

	if is_host:
		_sync_player_list.rpc_id(id, players)
		for peer_id in players.keys():
			if peer_id != id and peer_id != 1:
				_register_player.rpc_id(peer_id, id, "Player_%d" % id)

	if _match_in_progress:
		_start_match.rpc_id(id)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_disconnected.emit(id)
	print("Player disconnected: %d" % id)


func _on_connected_to_server() -> void:
	var my_id := multiplayer.get_unique_id()
	players[my_id] = {"name": "Player_%d" % my_id}
	connection_succeeded.emit()
	print("Connected to server as %d" % my_id)


func _on_connection_failed() -> void:
	connection_failed.emit()
	print("Connection failed")
	peer = null
	multiplayer.multiplayer_peer = null
