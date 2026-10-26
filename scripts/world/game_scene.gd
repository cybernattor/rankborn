extends Node3D

## Корневая сцена игры. Управляет спавном игроков, террейном,
## MobileUI и делегирует правила GameMode.

@onready var players_node: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints
@onready var mobile_ui: Control = $UILayer/MobileUI
@onready var pause_menu: Control = $UILayer/PauseMenu
@onready var game_mode: GameMode = $GameMode

const TERRAIN_SIZE := 100.0
const TERRAIN_RESOLUTION := 60
const TERRAIN_SEED := 42
## Зазор между ногами и землёй при спавне: капсула не должна начинать внутри склона.
const SPAWN_CLEARANCE := 0.1
## Затемнение в начале матча: под ним проходит рывок загрузки и прогрев эффектов.
const FADE_IN_HOLD := 0.3
const FADE_IN_TIME := 0.5
## На каком расстоянии перед игроком прогревать эффекты (должны попасть в кадр).
const PREWARM_DISTANCE := 4.0

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
	_fade_in_with_prewarm()


func _build_lowpoly_terrain() -> void:
	# 60×60 ячеек по ~1.7 м: грани ещё видны (low-poly), но рельеф не «треугольный».
	var terrain_mesh := MeshUtils.make_terrain(TERRAIN_SIZE, TERRAIN_RESOLUTION, TERRAIN_SEED)
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


func _fade_in_with_prewarm() -> void:
	var fade := ColorRect.new()
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	$UILayer.add_child(fade)
	var player := _get_local_player()
	if player:
		var weapon = player.weapon_manager.get_current_weapon()
		if weapon and weapon.has_method("prewarm_effects"):
			var forward: Vector3 = -player.global_transform.basis.z
			var at: Vector3 = player.global_position + forward * PREWARM_DISTANCE
			at.y = MeshUtils.terrain_height_at(TERRAIN_SIZE, TERRAIN_RESOLUTION, TERRAIN_SEED, at.x, at.z)
			weapon.prewarm_effects(at)
	var tween := create_tween()
	tween.tween_interval(FADE_IN_HOLD)
	tween.tween_property(fade, "modulate:a", 0.0, FADE_IN_TIME)
	tween.tween_callback(fade.queue_free)


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
	# Хост назначает свободный маркер; маркер задаёт только место на карте (x, z),
	# высоту берём с поверхности земли — иначе игроки появлялись в 4–13 м
	# над склонами и падали с неба.
	var slot_index: int = NetworkManager.players.get(id, {}).get("spawn_index", 0)
	assert(slot_index >= 0 and slot_index < spawn_points.get_child_count())
	var marker := (spawn_points.get_child(slot_index) as Node3D).global_position
	var ground := MeshUtils.terrain_height_at(TERRAIN_SIZE, TERRAIN_RESOLUTION, TERRAIN_SEED, marker.x, marker.z)
	return Vector3(marker.x, ground + SPAWN_CLEARANCE, marker.z)


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
