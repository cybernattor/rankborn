extends Node3D

## Корневая сцена игры. Управляет спавном игроков, террейном,
## MobileUI и делегирует правила GameMode.

@onready var players_node: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints
@onready var mobile_ui: Control = $MobileUI
@onready var pause_menu: Control = $PauseMenu
@onready var game_mode: GameMode = $GameMode

const TERRAIN_RESOLUTION := 60

var player_scene := preload("res://scenes/shared/player.tscn")
var local_player_id: int = 1


func _ready() -> void:
	_build_lowpoly_terrain()

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	var my_id := multiplayer.get_unique_id()
	local_player_id = my_id

	# Спавним всех уже подключённых игроков
	for id in NetworkManager.players.keys():
		_spawn_player(id)

	if not players_node.has_node(str(my_id)):
		_spawn_player(my_id)

	# Движение/стрельбу MobileUI нажимает через Input-действия сам;
	# сюда приходят только свайп камеры и кнопка паузы.
	mobile_ui.look_drag.connect(_on_mobile_look)
	mobile_ui.pause_pressed.connect(pause_menu.toggle)
	pause_menu.visibility_changed.connect(_on_pause_visibility_changed)
	_bind_local_player_ui()


func _build_lowpoly_terrain() -> void:
	# 60×60 ячеек по ~1.7 м: грани ещё видны (low-poly), но рельеф не «треугольный».
	var terrain_mesh := MeshUtils.make_terrain(100.0, TERRAIN_RESOLUTION, 42)
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


# Хост вышел — матча больше нет, возвращаемся в меню (там снова поиск игр).
func _on_server_disconnected() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


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


# --- Ввод и меню ---

func _notification(what: int) -> void:
	# Кнопка «Назад» на Android открывает/закрывает меню вместо выхода из игры.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		pause_menu.toggle()


func _get_local_player() -> Node:
	return players_node.get_node_or_null(str(local_player_id))


func _bind_local_player_ui() -> void:
	mobile_ui.player = _get_local_player()


func _on_mobile_look(delta: Vector2) -> void:
	var player := _get_local_player()
	if player:
		player.apply_touch_look(delta)


# Пауза в сетевой игре не останавливает мир — только блокирует ввод.
func _on_pause_visibility_changed() -> void:
	var player := _get_local_player()
	if player:
		player.input_blocked = pause_menu.visible
	mobile_ui.set_active(GameSettings.is_touch_device() and not pause_menu.visible)
