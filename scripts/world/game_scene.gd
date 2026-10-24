extends Node3D

## Корневая сцена игры. Управляет спавном игроков, террейном,
## MobileUI и делегирует правила GameMode.

@onready var players_node: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints
@onready var mobile_ui: Control = $MobileUI
@onready var pause_menu: Control = $PauseMenu
@onready var game_mode: GameMode = $GameMode

var player_scene := preload("res://scenes/shared/player.tscn")
var local_player_id: int = 1


func _ready() -> void:
	_build_lowpoly_terrain()

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

	var my_id := multiplayer.get_unique_id()
	local_player_id = my_id

	# Спавним всех уже подключённых игроков
	for id in NetworkManager.players.keys():
		_spawn_player(id)

	if not players_node.has_node(str(my_id)):
		_spawn_player(my_id)

	# Mobile UI: подключаем сигналы
	if mobile_ui:
		mobile_ui.move_input.connect(_on_mobile_move)
		mobile_ui.look_input.connect(_on_mobile_look)
		mobile_ui.shoot_input.connect(_on_mobile_shoot)
		mobile_ui.reload_input.connect(_on_mobile_reload)
		mobile_ui.interact_input.connect(_on_mobile_interact)


func _build_lowpoly_terrain() -> void:
	var terrain_mesh := MeshUtils.make_terrain(100.0, 30, 42)
	var terrain_instance := MeshInstance3D.new()
	terrain_instance.mesh = terrain_mesh
	terrain_instance.set_surface_override_material(0, MeshUtils.terrain_material())
	add_child(terrain_instance)

	# GroundBody лежит в сцене пустым: единственная коллизия земли — trimesh по мешу.
	var ground_body: StaticBody3D = $GroundBody
	var col := CollisionShape3D.new()
	var terrain_collision := terrain_mesh.create_trimesh_shape()
	terrain_collision.backface_collision = true
	col.shape = terrain_collision
	ground_body.add_child(col)


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
	player.set_multiplayer_authority(id)
	players_node.add_child(player, true)

	var spawn_pos := _get_spawn_position(id)
	player.global_position = spawn_pos
	if player.has_method("setup_spawn"):
		player.setup_spawn(spawn_pos)

	if id == multiplayer.get_unique_id():
		local_player_id = id

	# Уведомляем GameMode
	if game_mode:
		game_mode.on_player_spawn(id)


func _get_spawn_position(id: int) -> Vector3:
	# Хост назначает свободный маркер; координаты задаются в сцене.
	var slot_index: int = NetworkManager.players.get(id, {}).get("spawn_index", 0)
	assert(slot_index >= 0 and slot_index < spawn_points.get_child_count())
	return (spawn_points.get_child(slot_index) as Node3D).global_position


# --- Маршрутизация мобильного ввода ---

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
