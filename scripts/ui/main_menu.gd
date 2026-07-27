extends Control

@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var start_button: Button = %StartButton
@onready var address_input: LineEdit = %AddressInput
@onready var port_input: LineEdit = %PortInput
@onready var status_label: Label = %StatusLabel
@onready var ip_label: Label = %IpLabel
@onready var player_list: ItemList = %PlayerList


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.match_started.connect(_on_match_started)
	start_button.visible = false
	start_button.disabled = true


func _on_host_pressed() -> void:
	var port := int(port_input.text) if port_input.text != "" else NetworkManager.DEFAULT_PORT
	NetworkManager.host_game(port)


func _on_join_pressed() -> void:
	var address := address_input.text if address_input.text != "" else "127.0.0.1"
	var port := int(port_input.text) if port_input.text != "" else NetworkManager.DEFAULT_PORT
	NetworkManager.join_game(address, port)


func _on_start_pressed() -> void:
	NetworkManager.start_match()


func _on_server_created() -> void:
	var lan_ip := NetworkManager.get_lan_ip()
	var port := int(port_input.text) if port_input.text != "" else NetworkManager.DEFAULT_PORT
	ip_label.text = "Ваш IP для друзей: %s\nПорт: %d (UDP)" % [lan_ip, port]
	status_label.text = "Лобби открыто. Ждём игроков..."
	host_button.disabled = true
	join_button.disabled = true
	start_button.visible = true
	start_button.disabled = false
	_update_player_list()


func _on_connection_succeeded() -> void:
	status_label.text = "В лобби. Ждём старта хоста..."
	host_button.disabled = true
	join_button.disabled = true
	start_button.visible = false
	_update_player_list()


func _on_connection_failed() -> void:
	status_label.text = "Ошибка подключения"
	host_button.disabled = false
	join_button.disabled = false


func _on_player_connected(_id: int) -> void:
	_update_player_list()


func _on_player_disconnected(_id: int) -> void:
	_update_player_list()


func _on_match_started() -> void:
	get_tree().change_scene_to_file("res://scenes/game/game_scene.tscn")


func _update_player_list() -> void:
	player_list.clear()
	for id in NetworkManager.players:
		var label: String = "%s (%d)" % [NetworkManager.players[id].name, id]
		player_list.add_item(label)
