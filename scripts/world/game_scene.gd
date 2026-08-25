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
var _terrain_noise: FastNoiseLite


func _ready() -> void:
	_terrain_noise = FastNoiseLite.new()
	_terrain_noise.seed = 42
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = 0.008
	_terrain_noise.fractal_octaves = 4

	_build_lowpoly_terrain()

	var sun := $DirectionalLight3D
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, 30, 0)

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
	if mobile_ui and mobile_ui.visible:
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

	var ground_body := get_node_or_null("GroundBody")
	if not ground_body:
		ground_body = StaticBody3D.new()
		ground_body.name = "GroundBody"
		add_child(ground_body)

	for child in ground_body.get_children():
		if child is CollisionShape3D:
			child.queue_free()

	var col := CollisionShape3D.new()
	var terrain_collision := terrain_mesh.create_trimesh_shape()
	terrain_collision.backface_collision = true
	col.shape = terrain_collision
	ground_body.add_child(col)

	var safety_floor := StaticBody3D.new()
	safety_floor.name = "TerrainSafetyFloor"
	var safety_collision := CollisionShape3D.new()
	var safety_shape := BoxShape3D.new()
	safety_shape.size = Vector3(100.0, 2.0, 100.0)
	safety_collision.shape = safety_shape
	safety_floor.position = Vector3(0.0, -14.0, 0.0)
	safety_floor.add_child(safety_collision)
	add_child(safety_floor)


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
	_propagate_authority(player, id)

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
	# Identical deterministic slots are used by host and every client.
	# This avoids race-dependent or overlapping spawns during peer sync.
	var spawn_slots := [
		Vector2(-38.0, -38.0),
		Vector2(38.0, -38.0),
		Vector2(-38.0, 38.0),
		Vector2(38.0, 38.0),
		Vector2(0.0, -46.0),
		Vector2(0.0, 46.0),
	]
	var slot_index := posmod(id - 1, spawn_slots.size())
	var slot: Vector2 = spawn_slots[slot_index]
	var terrain_y := _terrain_noise.get_noise_2d(slot.x, slot.y) * 12.0
	return Vector3(slot.x, terrain_y + 2.4, slot.y)
# --- Mobile input routing ---

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


func _propagate_authority(node: Node, authority_id: int) -> void:
	for child in node.get_children():
		child.set_multiplayer_authority(authority_id)
		_propagate_authority(child, authority_id)
