extends Node

## LAN lobby discovery via UDP query/response.
## Clients broadcast a discover ping; hosts reply with lobby info.

signal games_updated(games: Array)

const DISCOVERY_PORT := 7001
const PROTOCOL_ID := "rankborn"
const BROADCAST_ADDR := "255.255.255.255"
const QUERY_INTERVAL := 1.5
const GAME_TIMEOUT := 4.0

var _udp := PacketPeerUDP.new()
var _mode: String = "" # "", "host", "browse"
var _game_port: int = NetworkManager.DEFAULT_PORT
var _game_name: String = "Rankborn"
var _query_timer: float = 0.0
## key "ip:port" -> Dictionary
var _found: Dictionary = {}


func _process(delta: float) -> void:
	if _mode.is_empty():
		return
	_poll_packets()
	if _mode == "browse":
		_query_timer += delta
		if _query_timer >= QUERY_INTERVAL:
			_query_timer = 0.0
			_send_discover()
		_expire_stale_games()


func start_browsing() -> Error:
	stop()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	var err := _udp.bind(0)
	if err != OK:
		push_warning("LAN browse bind failed: %s" % error_string(err))
		return err
	_mode = "browse"
	_query_timer = QUERY_INTERVAL
	_found.clear()
	games_updated.emit([])
	return OK


func start_hosting(game_port: int, game_name: String = "Rankborn") -> Error:
	stop()
	_game_port = game_port
	_game_name = game_name
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(DISCOVERY_PORT)
	if err != OK:
		push_warning("LAN host announce bind failed on %d: %s" % [DISCOVERY_PORT, error_string(err)])
		return err
	_mode = "host"
	print("LAN discovery hosting on UDP %d" % DISCOVERY_PORT)
	return OK


func stop() -> void:
	_mode = ""
	_found.clear()
	if _udp.is_bound():
		_udp.close()


func get_games() -> Array:
	var list: Array = []
	for key in _found:
		list.append(_found[key])
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return list


func _send_discover() -> void:
	var payload := {
		"protocol": PROTOCOL_ID,
		"type": "discover",
	}
	var bytes := JSON.stringify(payload).to_utf8_buffer()
	_udp.set_dest_address(BROADCAST_ADDR, DISCOVERY_PORT)
	_udp.put_packet(bytes)
	# Same-machine second instance / loopback fallback.
	_udp.set_dest_address("127.0.0.1", DISCOVERY_PORT)
	_udp.put_packet(bytes)


func _poll_packets() -> void:
	while _udp.get_available_packet_count() > 0:
		var bytes := _udp.get_packet()
		var from_ip := _udp.get_packet_ip()
		var from_port := _udp.get_packet_port()
		var text := bytes.get_string_from_utf8()
		var data = JSON.parse_string(text)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		if str(data.get("protocol", "")) != PROTOCOL_ID:
			continue
		var packet_type: String = str(data.get("type", ""))
		if _mode == "host" and packet_type == "discover":
			_reply_announce(from_ip, from_port)
		elif _mode == "browse" and packet_type == "announce":
			_register_game(data, from_ip)


func _reply_announce(to_ip: String, to_port: int) -> void:
	if to_ip.is_empty() or to_port <= 0:
		return
	var payload := {
		"protocol": PROTOCOL_ID,
		"type": "announce",
		"name": _game_name,
		"port": _game_port,
		"players": NetworkManager.players.size(),
		"max_players": NetworkManager.MAX_CLIENTS,
	}
	var bytes := JSON.stringify(payload).to_utf8_buffer()
	_udp.set_dest_address(to_ip, to_port)
	_udp.put_packet(bytes)


func _register_game(data: Dictionary, from_ip: String) -> void:
	var port := int(data.get("port", NetworkManager.DEFAULT_PORT))
	if port <= 0:
		return
	# Prefer address from UDP peer; fall back to payload if present.
	var ip := from_ip
	if ip.is_empty() or ip == "0.0.0.0":
		ip = str(data.get("ip", ""))
	if ip.is_empty():
		return
	# Ignore our own lobby announce if somehow received.
	if NetworkManager.is_host and ip == NetworkManager.get_lan_ip() and port == _game_port:
		return

	var key := "%s:%d" % [ip, port]
	var entry := {
		"key": key,
		"ip": ip,
		"port": port,
		"name": str(data.get("name", "Rankborn")),
		"players": int(data.get("players", 1)),
		"max_players": int(data.get("max_players", NetworkManager.MAX_CLIENTS)),
		"last_seen": Time.get_ticks_msec() / 1000.0,
	}
	var changed := not _found.has(key)
	if not changed:
		var prev: Dictionary = _found[key]
		changed = (
			prev.get("players") != entry.players
			or prev.get("name") != entry.name
		)
	_found[key] = entry
	if changed:
		games_updated.emit(get_games())


func _expire_stale_games() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var removed := false
	for key in _found.keys():
		var entry: Dictionary = _found[key]
		if now - float(entry.get("last_seen", 0.0)) > GAME_TIMEOUT:
			_found.erase(key)
			removed = true
	if removed:
		games_updated.emit(get_games())
