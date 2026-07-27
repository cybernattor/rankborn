extends Node3D

@onready var players_node: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints
@onready var mobile_ui: Control = $MobileUI

var player_scene := preload("res://scenes/shared/player.tscn")
var local_player_id: int = 1


func _ready() -> void:
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

	var my_id := multiplayer.get_unique_id()
	local_player_id = my_id

	# Spawn everyone already known (host + early joiners).
	for id in NetworkManager.players.keys():
		_spawn_player(id)

	# Ensure local player exists even if the dict lagged.
	if not players_node.has_node(str(my_id)):
		_spawn_player(my_id)

	if mobile_ui and mobile_ui.visible:
		mobile_ui.move_input.connect(_on_mobile_move)
		mobile_ui.look_input.connect(_on_mobile_look)
		mobile_ui.shoot_input.connect(_on_mobile_shoot)
		mobile_ui.reload_input.connect(_on_mobile_reload)
		mobile_ui.interact_input.connect(_on_mobile_interact)


func _on_player_connected(id: int) -> void:
	_spawn_player(id)


func _on_player_disconnected(id: int) -> void:
	if players_node.has_node(str(id)):
		players_node.get_node(str(id)).queue_free()


func _spawn_player(id: int) -> void:
	if players_node.has_node(str(id)):
		return

	var player := player_scene.instantiate()
	player.name = str(id)
	players_node.add_child(player, true)
	player.set_multiplayer_authority(id)

	var spawn_pos := _get_spawn_position(id)
	player.global_position = spawn_pos
	if player.has_method("setup_spawn"):
		player.setup_spawn(spawn_pos)

	if id == multiplayer.get_unique_id():
		local_player_id = id


func _get_spawn_position(id: int) -> Vector3:
	if spawn_points.get_child_count() == 0:
		return Vector3(0, 1, 0)
	var spawn_index: int = absi(id) % spawn_points.get_child_count()
	return spawn_points.get_child(spawn_index).global_position


func _on_mobile_move(vec: Vector2) -> void:
	_set_input_state("mobile_move", vec)


func _on_mobile_look(vec: Vector2) -> void:
	_set_input_state("mobile_look", vec)


func _on_mobile_shoot(pressed: bool) -> void:
	_set_input_state("mobile_shoot", pressed)


func _on_mobile_reload() -> void:
	_set_input_state("mobile_reload", true)


func _on_mobile_interact() -> void:
	_set_input_state("mobile_interact", true)


func _set_input_state(action: String, value) -> void:
	if not players_node.has_node(str(local_player_id)):
		return
	var player = players_node.get_node(str(local_player_id))
	if player.has_method("_on_mobile_input"):
		player._on_mobile_input(action, value)
