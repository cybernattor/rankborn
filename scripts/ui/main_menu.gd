extends Control

@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var join_selected_button: Button = %JoinSelectedButton
@onready var start_button: Button = %StartButton
@onready var address_input: LineEdit = %AddressInput
@onready var port_input: LineEdit = %PortInput
@onready var status_label: Label = %StatusLabel
@onready var ip_label: Label = %IpLabel
@onready var player_list: ItemList = %PlayerList
@onready var found_games_list: ItemList = %FoundGamesList

var _found_games: Array = []
var _in_lobby: bool = false


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	join_selected_button.pressed.connect(_on_join_selected_pressed)
	start_button.pressed.connect(_on_start_pressed)
	found_games_list.item_selected.connect(_on_found_game_selected)
	found_games_list.item_activated.connect(_on_found_game_activated)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.match_started.connect(_on_match_started)
	LanDiscovery.games_updated.connect(_on_games_updated)
	start_button.visible = false
	start_button.disabled = true
	join_selected_button.disabled = true
	LanDiscovery.start_browsing()
	_on_games_updated(LanDiscovery.get_games())


func _exit_tree() -> void:
	if not _in_lobby:
		LanDiscovery.stop()


func _on_host_pressed() -> void:
	var port := int(port_input.text) if port_input.text != "" else NetworkManager.DEFAULT_PORT
	NetworkManager.host_game(port)


func _on_join_pressed() -> void:
	var address := address_input.text if address_input.text != "" else "127.0.0.1"
	var port := int(port_input.text) if port_input.text != "" else NetworkManager.DEFAULT_PORT
	status_label.text = "Подключение к %s:%d..." % [address, port]
	NetworkManager.join_game(address, port)


func _on_join_selected_pressed() -> void:
	var selected := found_games_list.get_selected_items()
	if selected.is_empty():
		return
	_join_found_game(selected[0])


func _on_found_game_selected(_index: int) -> void:
	join_selected_button.disabled = _in_lobby or found_games_list.get_selected_items().is_empty()


func _on_found_game_activated(index: int) -> void:
	if _in_lobby:
		return
	_join_found_game(index)


func _join_found_game(index: int) -> void:
	if index < 0 or index >= _found_games.size():
		return
	var game: Dictionary = _found_games[index]
	var address := str(game.get("ip", ""))
	var port := int(game.get("port", NetworkManager.DEFAULT_PORT))
	if address.is_empty():
		return
	address_input.text = address
	port_input.text = str(port)
	status_label.text = "Подключение к %s:%d..." % [address, port]
	NetworkManager.join_game(address, port)


func _on_start_pressed() -> void:
	NetworkManager.start_match()


func _on_server_created() -> void:
	_in_lobby = true
	var lan_ip := NetworkManager.get_lan_ip()
	var port := int(port_input.text) if port_input.text != "" else NetworkManager.DEFAULT_PORT
	ip_label.text = "Ваш IP: %s  |  порт %d\nДрузья увидят лобби в списке автоматически" % [lan_ip, port]
	status_label.text = "Лобби открыто. Ждём игроков..."
	_set_connect_ui_enabled(false)
	start_button.visible = true
	start_button.disabled = false
	_update_player_list()


func _on_connection_succeeded() -> void:
	_in_lobby = true
	status_label.text = "В лобби. Ждём старта хоста..."
	_set_connect_ui_enabled(false)
	start_button.visible = false
	_update_player_list()


func _on_connection_failed() -> void:
	_in_lobby = false
	status_label.text = "Ошибка подключения. Продолжаем поиск..."
	_set_connect_ui_enabled(true)
	LanDiscovery.start_browsing()


func _on_player_connected(_id: int) -> void:
	_update_player_list()


func _on_player_disconnected(_id: int) -> void:
	_update_player_list()


func _on_match_started() -> void:
	get_tree().change_scene_to_file("res://scenes/game/game_scene.tscn")


func _on_games_updated(games: Array) -> void:
	_found_games = games
	var selected_key := ""
	var selected := found_games_list.get_selected_items()
	if not selected.is_empty() and selected[0] < _found_games.size():
		selected_key = str(_found_games[selected[0]].get("key", ""))

	found_games_list.clear()
	for game in _found_games:
		var line := "%s  —  %s:%d  (%d/%d)" % [
			str(game.get("name", "Rankborn")),
			str(game.get("ip", "?")),
			int(game.get("port", 0)),
			int(game.get("players", 0)),
			int(game.get("max_players", NetworkManager.MAX_CLIENTS)),
		]
		found_games_list.add_item(line)

	if not selected_key.is_empty():
		for i in range(_found_games.size()):
			if str(_found_games[i].get("key", "")) == selected_key:
				found_games_list.select(i)
				break

	if not _in_lobby:
		if _found_games.is_empty():
			status_label.text = "Поиск игр в локалке..."
		else:
			status_label.text = "Найдено игр: %d (двойной клик = войти)" % _found_games.size()
		join_selected_button.disabled = found_games_list.get_selected_items().is_empty()


func _set_connect_ui_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	join_selected_button.disabled = not enabled or found_games_list.get_selected_items().is_empty()
	found_games_list.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func _update_player_list() -> void:
	player_list.clear()
	for id in NetworkManager.players:
		var label: String = "%s (%d)" % [NetworkManager.players[id].name, id]
		player_list.add_item(label)
