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

## Укрытия прототипа камеры сверху (фаза 1.5 roadmap): стены, камни, мешки с песком.
## pos — центр на карте (x, z), size — размеры, rot — поворот вокруг вертикали, градусы.
## Мешки ниже роста стоя: за ними прячутся в приседе. Спавны (±20, ±30) свободны.
const COVER_WALL := Color(0.52, 0.47, 0.40)
const COVER_ROCK := Color(0.50, 0.50, 0.52)
const COVER_SANDBAG := Color(0.66, 0.58, 0.40)
const COVERS := [
	{"pos": Vector2(0, 0), "size": Vector3(6, 2.2, 0.6), "rot": 0.0, "color": COVER_WALL},
	{"pos": Vector2(-10, 8), "size": Vector3(5, 2.2, 0.6), "rot": 30.0, "color": COVER_WALL},
	{"pos": Vector2(12, -6), "size": Vector3(0.6, 2.2, 5), "rot": 0.0, "color": COVER_WALL},
	{"pos": Vector2(-6, -12), "size": Vector3(4, 2.2, 0.6), "rot": -15.0, "color": COVER_WALL},
	{"pos": Vector2(8, 10), "size": Vector3(2.2, 1.6, 2.0), "rot": 20.0, "color": COVER_ROCK},
	{"pos": Vector2(-14, -4), "size": Vector3(2.0, 1.8, 2.4), "rot": -35.0, "color": COVER_ROCK},
	{"pos": Vector2(4, -18), "size": Vector3(2.6, 1.5, 1.8), "rot": 50.0, "color": COVER_ROCK},
	{"pos": Vector2(-4, 18), "size": Vector3(2.0, 1.7, 2.0), "rot": 10.0, "color": COVER_ROCK},
	{"pos": Vector2(-16, 14), "size": Vector3(7, 1.25, 0.8), "rot": 0.0, "color": COVER_SANDBAG},
	{"pos": Vector2(16, -14), "size": Vector3(7, 1.25, 0.8), "rot": 90.0, "color": COVER_SANDBAG},
	{"pos": Vector2(14, 14), "size": Vector3(6, 1.25, 0.8), "rot": -45.0, "color": COVER_SANDBAG},
]
## На сколько укрытие уходит в землю под самым низким углом: на склоне не висит в воздухе.
## Высота укрытия (size.y) отсчитывается от самого высокого угла — со стороны склона
## оно не ниже заявленного, иначе стоящий выше по склону смотрит поверх.
const COVER_SINK := 0.3

var player_scene := preload("res://scenes/shared/player.tscn")
var local_player_id: int = 1


func _ready() -> void:
	_build_lowpoly_terrain()
	_build_covers()

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

	# Движение, прицел и стрельбу MobileUI нажимает через Input-действия сам;
	# сюда приходит только кнопка паузы.
	mobile_ui.pause_pressed.connect(pause_menu.toggle)
	pause_menu.visibility_changed.connect(_on_pause_visibility_changed)
	_bind_local_player_ui()
	var visibility := VisibilityManager.new()
	visibility.name = "VisibilityManager"
	add_child(visibility)
	_apply_graphics()
	GameSettings.changed.connect(_apply_graphics)
	var auto_quality := AutoQuality.new()
	auto_quality.name = "AutoQuality"
	add_child(auto_quality)
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


## Высота земли в точке (x, z) — та же формула, что у меша; без физики.
func ground_height_at(x: float, z: float) -> float:
	return MeshUtils.terrain_height_at(TERRAIN_SIZE, TERRAIN_RESOLUTION, TERRAIN_SEED, x, z)


func _apply_graphics() -> void:
	GameSettings.apply_graphics(get_viewport(), $DirectionalLight3D)


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
			at.y = ground_height_at(at.x, at.z)
			weapon.prewarm_effects(at)
	var tween := create_tween()
	tween.tween_interval(FADE_IN_HOLD)
	tween.tween_property(fade, "modulate:a", 0.0, FADE_IN_TIME)
	tween.tween_callback(fade.queue_free)


func _build_covers() -> void:
	var covers := Node3D.new()
	covers.name = "Covers"
	add_child(covers)
	for spec: Dictionary in COVERS:
		var size: Vector3 = spec.size
		var basis := Basis(Vector3.UP, deg_to_rad(spec.rot))
		var low := INF
		var high := -INF
		for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
			var p: Vector3 = Vector3(spec.pos.x, 0, spec.pos.y) + basis * (corner * size * 0.5)
			var h := ground_height_at(p.x, p.z)
			low = minf(low, h)
			high = maxf(high, h)
		var bottom := low - COVER_SINK
		var top := high + size.y
		size.y = top - bottom
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.transform = Transform3D(basis, Vector3(spec.pos.x, (bottom + top) * 0.5, spec.pos.y))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		mesh.mesh = MeshUtils.make_box(size, spec.color)
		mesh.set_surface_override_material(0, MeshUtils.flat_material(Color.WHITE))
		body.add_child(mesh)
		covers.add_child(body)


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
	var ground := ground_height_at(marker.x, marker.z)
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


# Пауза в сетевой игре не останавливает мир — только блокирует ввод.
func _on_pause_visibility_changed() -> void:
	var player := _get_local_player()
	if player:
		player.input_blocked = pause_menu.visible
	mobile_ui.set_active(GameSettings.is_touch_device() and not pause_menu.visible)
