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
@onready var exit_button: Button = %ExitButton
@onready var leave_button: Button = %LeaveButton
@onready var name_input: LineEdit = %NameInput

var _found_games: Array = []
var _in_lobby: bool = false

# Adaptive layout references
var _columns_hbox: HBoxContainer
var _columns_vbox: VBoxContainer
var _create_section: PanelContainer
var _join_section: PanelContainer
var _main_vbox: VBoxContainer
var _is_mobile: bool = false


func _ready() -> void:
	_columns_hbox = $Background/Margin/MainVBox/ColumnsHBox
	_main_vbox = $Background/Margin/MainVBox
	_create_section = $Background/Margin/MainVBox/ColumnsHBox/CreateSection
	_join_section = $Background/Margin/MainVBox/ColumnsHBox/JoinSection

	# Create a VBox container for mobile layout (hidden by default)
	_columns_vbox = VBoxContainer.new()
	_columns_vbox.name = "ColumnsVBox"
	_columns_vbox.visible = false
	_main_vbox.add_child(_columns_vbox)
	_columns_vbox.add_theme_constant_override("separation", 12)

	# Connect signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	join_selected_button.pressed.connect(_on_join_selected_pressed)
	start_button.pressed.connect(_on_start_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	name_input.max_length = NetworkManager.MAX_NAME_LENGTH
	name_input.text = GameSettings.player_name
	name_input.text_changed.connect(_on_name_changed)
	found_games_list.item_selected.connect(_on_found_game_selected)
	found_games_list.item_activated.connect(_on_found_game_activated)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.match_started.connect(_on_match_started)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	LanDiscovery.games_updated.connect(_on_games_updated)
	start_button.visible = false
	start_button.disabled = true
	join_selected_button.disabled = true

	# Handle adaptive layout
	_handle_resize()
	get_viewport().size_changed.connect(_handle_resize)

	# Start LAN discovery
	var browse_err := LanDiscovery.start_browsing()
	if browse_err != OK:
		status_label.text = "Ошибка сетевого поиска (порт заблокирован?)"
		return
	_on_games_updated(LanDiscovery.get_games())


func _notification(what: int) -> void:
	# Кнопка «Назад» на Android: из лобби — выйти из лобби, иначе — как «Выход»
	# (quit_on_go_back выключен ради меню паузы в матче).
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _in_lobby:
			_on_leave_pressed()
		else:
			_on_exit_pressed()


func _exit_tree() -> void:
	if not _in_lobby:
		LanDiscovery.stop()


func _handle_resize() -> void:
	# При stretch canvas_items/expand короткая сторона viewport всегда базовая,
	# поэтому сравнивать ширину с порогом бессмысленно — смотрим на ориентацию.
	var viewport_size := get_viewport_rect().size
	var should_be_mobile := viewport_size.x < viewport_size.y

	if should_be_mobile == _is_mobile:
		return

	_is_mobile = should_be_mobile
	_apply_layout()


func _apply_layout() -> void:
	if _is_mobile:
		# Move sections to VBox for vertical stacking
		if _create_section.get_parent() == _columns_hbox:
			_columns_hbox.remove_child(_create_section)
		if _join_section.get_parent() == _columns_hbox:
			_columns_hbox.remove_child(_join_section)
		if _create_section.get_parent() != _columns_vbox:
			_columns_vbox.add_child(_create_section)
		if _join_section.get_parent() != _columns_vbox:
			_columns_vbox.add_child(_join_section)
		_columns_hbox.visible = false
		_columns_vbox.visible = true
		# Full width on mobile
		_create_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_join_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		# Move sections back to HBox for side-by-side
		if _create_section.get_parent() == _columns_vbox:
			_columns_vbox.remove_child(_create_section)
		if _join_section.get_parent() == _columns_vbox:
			_columns_vbox.remove_child(_join_section)
		if _create_section.get_parent() != _columns_hbox:
			_columns_hbox.add_child(_create_section)
		if _join_section.get_parent() != _columns_hbox:
			_columns_hbox.add_child(_join_section)
		_columns_vbox.visible = false
		_columns_hbox.visible = true


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
	if LanDiscovery._mode == "host":
		ip_label.text = "IP: %s:%d\nДрузья увидят лобби автоматически" % [lan_ip, port]
		status_label.text = "Лобби открыто. Ждём игроков..."
	else:
		ip_label.text = "IP: %s:%d\nАвтообнаружение недоступно" % [lan_ip, port]
		status_label.text = "Лобби открыто (без автопоиска)..."
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
	_return_to_browsing("Ошибка подключения. Продолжаем поиск...")


func _on_leave_pressed() -> void:
	NetworkManager.disconnect_game()
	_return_to_browsing("Вы покинули лобби. Поиск игр...")


func _on_server_disconnected() -> void:
	_return_to_browsing("Хост закрыл лобби. Поиск игр...")


func _return_to_browsing(message: String) -> void:
	_in_lobby = false
	_set_connect_ui_enabled(true)
	start_button.visible = false
	ip_label.text = ""
	player_list.clear()
	var browse_err := LanDiscovery.start_browsing()
	status_label.text = message if browse_err == OK else "Ошибка сетевого поиска (порт заблокирован?)"


func _on_name_changed(new_name: String) -> void:
	GameSettings.player_name = new_name
	GameSettings.save_settings()


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
			status_label.text = "Найдено: %d (двойной клик = войти)" % _found_games.size()
		join_selected_button.disabled = found_games_list.get_selected_items().is_empty()


func _set_connect_ui_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	join_selected_button.disabled = not enabled or found_games_list.get_selected_items().is_empty()
	found_games_list.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	# Ник меняется только вне лобби: в лобби он уже отправлен хосту.
	name_input.editable = enabled
	leave_button.visible = not enabled


# Peer id не показываем: у хоста он всегда 1, у клиентов — случайное число от ENet
# (например 222456567658), игроку это ничего не говорит. Вместо него — кто хост и кто ты.
func _update_player_list() -> void:
	player_list.clear()
	var my_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	for id in NetworkManager.players:
		var tags: Array[String] = []
		if id == 1:
			tags.append("хост")
		if id == my_id:
			tags.append("вы")
		var label: String = NetworkManager.players[id].name
		if not tags.is_empty():
			label += "  (%s)" % ", ".join(tags)
		player_list.add_item(label)


func _on_exit_pressed() -> void:
	get_tree().quit()
