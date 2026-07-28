extends Node3D

@onready var players_node: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints
@onready var mobile_ui: Control = $MobileUI
@onready var pause_menu: Control = $PauseMenu

var player_scene := preload("res://scenes/shared/player.tscn")
var local_player_id: int = 1
var _terrain_noise: FastNoiseLite


func _ready() -> void:
	_terrain_noise = FastNoiseLite.new()
	_terrain_noise.seed = 42
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = 0.008
	_terrain_noise.fractal_octaves = 4

	_setup_environment()
	_build_lowpoly_terrain()
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

	var my_id := multiplayer.get_unique_id()
	local_player_id = my_id

	for id in NetworkManager.players.keys():
		_spawn_player(id)

	if not players_node.has_node(str(my_id)):
		_spawn_player(my_id)

	if mobile_ui and mobile_ui.visible:
		mobile_ui.move_input.connect(_on_mobile_move)
		mobile_ui.look_input.connect(_on_mobile_look)
		mobile_ui.shoot_input.connect(_on_mobile_shoot)
		mobile_ui.reload_input.connect(_on_mobile_reload)
		mobile_ui.interact_input.connect(_on_mobile_interact)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.45)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.9)
	env.fog_density = 0.003
	env.fog_sky_affect = 0.3

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.5, 0.85)
	sky_mat.sky_horizon_color = Color(0.65, 0.75, 0.88)
	sky_mat.ground_bottom_color = Color(0.2, 0.18, 0.15)
	sky_mat.ground_horizon_color = Color(0.5, 0.55, 0.5)
	sky_mat.sun_angle_max = 40.0
	sky_mat.sun_curve = 0.15

	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky

	var world_env := $WorldEnvironment
	world_env.environment = env

	var sun := $DirectionalLight3D
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, 30, 0)


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
	col.shape = terrain_mesh.create_trimesh_shape()
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
		return Vector3(0, 5, 0)
	var spawn_index: int = absi(id) % spawn_points.get_child_count()
	var pos: Vector3 = spawn_points.get_child(spawn_index).global_position as Vector3
	var terrain_y := _terrain_noise.get_noise_2d(pos.x, pos.z) * 12.0
	pos.y = terrain_y + 2.0
	return pos


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
