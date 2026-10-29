extends CharacterBody3D

## Контроллер игрока. Камера сверху (IsoCamera), направление прицеливания
## (мышь — курсор, геймпад и тач — правый стик), меш тела, присед, видимость в тумане
## войны, состояние (FSM), здоровье (HealthComponent) и оружие (WeaponManager).
## Движение читают стейты (PlayerState) через Input-действия — у ПК, геймпада и
## мобильного UI один и тот же путь ввода.

@onready var head: Node3D = $Head
@onready var camera: IsoCamera = $IsoCamera
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var state_machine: StateMachine = $StateMachine
@onready var weapon_manager: WeaponManager = $WeaponManager
@onready var health_component: HealthComponent = $HealthComponent

# Меш тела (именованный, доступен из State)
var body_mesh: MeshInstance3D

var spawn_position: Vector3 = Vector3.ZERO
## Куда смотрит игрок после спавна (центр игровой зоны).
const MAP_CENTER := Vector3.ZERO

## Ввод заблокирован меню (пауза не останавливает сетевую игру).
var input_blocked: bool = false

## HUD и экран смерти есть только у локального игрока.
var weapon_hud: CanvasLayer
var death_screen: DeathScreen
var ears: AudioListener3D
const EARS_HEIGHT := 1.6

# Прицеливание как у Foxhole: зума нет. Пока прицел зажат, конус разброса
# сужается за AIM_TIME (aim_progress 0 → 1, Rifle.get_spread_angle), камера уходит
# дальше в сторону взгляда, а солдат идёт медленно (PlayerState). Выстрел сбивает
# прицел — после него снова надо довести.
var is_aiming: bool = false
var aim_progress: float = 0.0
## Сведение прицела заморожено: на таче стик уже отпущен, выстрел ждёт готовности затвора.
## Конус не сужается дальше — выстрел уходит с тем разбросом, который игрок видел при отпускании.
var aim_frozen: bool = false
const AIM_TIME := 0.8
## На ходу прицел сводится медленнее.
const AIM_MOVING_RATE := 0.4
const AIM_MOVING_SPEED := 1.0
## Какая доля сведения остаётся после выстрела.
const AIM_SHOT_KEEP := 0.35
## Точка, куда целится игрок (мир): на высоте выстрела над землёй под прицелом.
var aim_point: Vector3 = Vector3.ZERO
## Куда прицел реально «достаёт»: aim_point, обрезанный первым укрытием или склоном на
## пути выстрела. По нему рисуются прицел HUD и конус — раньше они проходили сквозь
## стены и показывали точку, в которую пуля попасть не могла.
var sight_point: Vector3 = Vector3.ZERO
## Слой мира (земля и укрытия) — то, что останавливает пулю, кроме игроков.
const SIGHT_BLOCKING_MASK := 1
var _aim_direction := Vector3.FORWARD
var _aim_distance: float = STICK_AIM_DISTANCE
## Стик прицела отклонён с прошлого кадра: первое отклонение ставит прицел сразу, дальше поворот плавный.
var _stick_aim_active: bool = false
## Последним прицеливались мышью (иначе — стиком). Переключается тем, чем пошевелили.
var _mouse_aim: bool = true
## Высота выстрела над ногами: от груди, а не от глаз — пуля летит из оружия.
const SHOT_HEIGHT := 1.25
## Стиком (геймпад, тач) дальность прицела задаёт отклонение: чуть — близко, до края —
## STICK_AIM_DISTANCE (в прицеле дальше). Точка прицела должна оставаться на экране:
## по вертикали камера сверху видит примерно ±9 м от центра.
const STICK_AIM_MIN_DISTANCE := 4.0
const STICK_AIM_DISTANCE := 11.0
const STICK_AIM_DISTANCE_ADS := 15.0
const STICK_AIM_DEADZONE := 0.2
## Поворот прицела стиком — плавный и с пределом скорости: мгновенный поворот за стиком
## дёргал прицел от дрожи пальца и был слишком быстрым. В прицеле — медленнее и точнее.
## Мышь точна сама по себе, её не сглаживаем.
## Первый вариант (6 и 2.2 рад/с) на плейтесте показался слишком медленным.
const STICK_TURN_SMOOTHING := 20.0
const STICK_TURN_SPEED := 11.0
const STICK_TURN_SPEED_ADS := 4.5
const STICK_DISTANCE_SMOOTHING := 8.0
## Мёртвая зона курсора вокруг солдата — в пикселях экрана, а не в метрах: при 1 м
## (≈90 px на экране) прицел «застревал» на полсекунды, пока курсор проходил через
## солдата, и потом прыгал. Несколько пикселей хватает, чтобы он не крутился волчком.
const MOUSE_AIM_DEADZONE_PX := 6.0
## Ближе этого точка прицела не подходит: конус и выстрел вырождаются в точку.
const MIN_AIM_DISTANCE := 0.5

## Туман войны: хост решил, что этого (удалённого) игрока нам не видно
## (VisibilityManager). Не рисуется и не ловит пули — иначе можно стрелять по призраку
## в последней известной позиции.
var fog_hidden: bool = false:
	set(value):
		if fog_hidden == value:
			return
		fog_hidden = value
		_update_presence()

# Рост: стоя / присев. Капсула, голова и меш меняются вместе,
# чтобы хитбокс совпадал с тем, что видят другие игроки.
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const STAND_HEAD_Y := 1.6
const CROUCH_HEAD_Y := 1.05
const CROUCH_TRANSITION_SPEED := 10.0

## Перелезание через низкое укрытие (VaultState, Foxhole: пробел). Мешки с песком
## перелезаются, стены (2.2 м над любой точкой под ними) — нет. Предел — от земли под
## ногами: высота укрытий отсчитывается от верхнего угла, и на склоне мешки местами
## выше своих 1.25 м (до ~1.55).
var is_vaulting: bool = false
## Перед солдатом есть через что перелезть — для подсветки кнопки VAULT на таче.
var vault_available: bool = false
const VAULT_MAX_HEIGHT := 1.7
const VAULT_MIN_HEIGHT := 0.3
## Как далеко перед собой ищем укрытие и какой толщины оно может быть.
const VAULT_REACH := 1.1
const VAULT_MAX_DEPTH := 1.2
const VAULT_PROBE_HEIGHT := 0.5
## Отступ места приземления от дальней стороны укрытия (радиус капсулы + запас).
const VAULT_LANDING_GAP := 0.6

## Синхронизируется по сети (SceneReplicationConfig в player.tscn).
var is_crouching: bool = false:
	set(value):
		if is_crouching == value:
			return
		is_crouching = value
		_apply_body_height()

var _crouch_toggled: bool = false


func _ready() -> void:
	# Форма капсулы — общий SubResource сцены; у каждого игрока должна быть своя,
	# иначе приседание одного меняет хитбоксы всех.
	collision_shape.shape = collision_shape.shape.duplicate()
	_build_lowpoly_body()
	health_component.life_state_changed.connect(_on_life_state_changed)

	if is_multiplayer_authority():
		camera.target = self
		camera.current = true
		_mouse_aim = not GameSettings.is_touch_device()
		if _mouse_aim:
			# Курсор прячем и держим в окне: вместо него рисуется прицел HUD.
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
		_setup_weapon_hud()
		death_screen = DeathScreen.new()
		death_screen.name = "DeathScreen"
		add_child(death_screen)
		var damage_hud := DamageHud.new()
		damage_hud.name = "DamageHud"
		add_child(damage_hud)
		damage_hud.setup(self, health_component)
		# «Уши» у солдата: камера висит в 20 м над ним, и от неё всё звучало бы
		# тихо и одинаково. Ориентация — как у камеры, чтобы лево/право совпадали с экраном.
		ears = AudioListener3D.new()
		ears.name = "Ears"
		ears.top_level = true
		add_child(ears)
		ears.make_current()
		var aim_cone := AimCone.new()
		aim_cone.name = "AimCone"
		aim_cone.player = self
		add_child(aim_cone)

		# Туман войны: свою позицию шлём только тем, кого назовёт хост
		# (VisibilityManager), и всегда — самому хосту.
		var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer
		sync.public_visibility = false
		sync.set_visibility_for(1, true)

		# Подключаем смерть → StateMachine
		health_component.died.connect(_on_died)
	else:
		camera.current = false
		camera.set_process(false)
		# Чужих игроков не видно, пока хост не скажет обратное (туман войны).
		fog_hidden = true
	_apply_body_height()
	_on_life_state_changed(health_component.is_alive)


func _build_lowpoly_body() -> void:
	var humanoid_mesh := MeshUtils.make_humanoid()
	var mat := MeshUtils.flat_material(Color.WHITE)

	body_mesh = MeshInstance3D.new()
	body_mesh.name = "BodyMesh"
	body_mesh.mesh = humanoid_mesh
	body_mesh.set_surface_override_material(0, mat)
	add_child(body_mesh)


func _setup_weapon_hud() -> void:
	var hud_scene := preload("res://scenes/ui/weapon_hud.tscn")
	var hud: CanvasLayer = hud_scene.instantiate()
	hud.name = "WeaponHUD"
	add_child(hud)
	hud.setup(weapon_manager)
	weapon_hud = hud


func setup_spawn(pos: Vector3) -> void:
	spawn_position = pos
	global_position = pos
	face_map_center()


## После (ре)спавна смотрим к центру карты, а не туда, куда смотрел перед смертью:
## спавны стоят у края, и старый взгляд часто упирался в обрыв за границей карты.
func face_map_center() -> void:
	var to_center := MAP_CENTER - global_position
	to_center.y = 0.0
	if to_center.length_squared() > 0.01:
		_aim_direction = to_center.normalized()
		rotation.y = atan2(-_aim_direction.x, -_aim_direction.z)
	_aim_distance = STICK_AIM_DISTANCE
	aim_point = _compute_aim_point()
	sight_point = _compute_sight_point()
	head.position.y = get_head_height()
	if is_node_ready() and camera.current:
		camera.snap()


## Можно ли сейчас управлять персонажем (жив и не открыто меню).
func can_control() -> bool:
	return health_component.is_alive and not input_blocked


## Высота головы для текущей позы (на ней висит оружие).
func get_head_height() -> float:
	return CROUCH_HEAD_Y if is_crouching else STAND_HEAD_Y


## Текущий рост капсулы — для хитбоксов и проверки хедшота.
func get_body_height() -> float:
	return CROUCH_HEIGHT if is_crouching else STAND_HEIGHT


## Откуда летит выстрел (мир).
func get_shot_origin() -> Vector3:
	return global_position + Vector3.UP * (SHOT_HEIGHT * get_body_height() / STAND_HEIGHT)


## Целимся мышью (курсором), а не стиком.
func uses_mouse_aim() -> bool:
	return _mouse_aim


## Горизонтальное направление прицеливания (единичное).
func get_aim_direction() -> Vector3:
	return _aim_direction


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_update_crouch()
	if not state_machine.current_state:
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		move_and_slide()


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	# Пошевелили мышью — снова целимся курсором (после геймпада).
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION \
			and not GameSettings.is_touch_device():
		_mouse_aim = true


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	# Меню открывается и во время смерти.
	if event.is_action_pressed("pause"):
		var pause_menu = get_tree().current_scene.get_node_or_null("UILayer/PauseMenu")
		if pause_menu:
			pause_menu.toggle()
		return
	if not can_control():
		return
	if event.is_action_pressed("weapon_next"):
		weapon_manager.next_weapon()
	elif event.is_action_pressed("weapon_prev"):
		weapon_manager.prev_weapon()


func _process(delta: float) -> void:
	# Голова (и оружие на ней) плавно опускается при приседании — у всех пиров.
	head.position.y = lerpf(head.position.y, get_head_height(), 1.0 - exp(-CROUCH_TRANSITION_SPEED * delta))
	if not is_multiplayer_authority():
		return
	ears.global_transform = Transform3D(camera.global_basis, global_position + Vector3.UP * EARS_HEIGHT)
	_update_aim()
	_update_aim_progress(delta)
	if can_control():
		_update_aim_direction(delta)
		rotation.y = atan2(-_aim_direction.x, -_aim_direction.z)
	aim_point = _compute_aim_point()
	sight_point = _compute_sight_point()
	vault_available = can_control() and not is_vaulting and not find_vault(_vault_direction()).is_empty()


## Рисовать ли прицел и конус разброса. На таче их держит только стик прицела: иначе конус
## и крестик висят в последнем направлении, и непонятно, целишься ты или нет. С мышью и
## геймпадом они всегда на виду (курсор и так показывает, куда смотришь).
func show_aim_indicators() -> bool:
	return is_aiming or not GameSettings.is_touch_device()


## Направление прицеливания: правый стик (геймпад; на таче его нажимает MobileUI)
## или курсор мыши. Камера не вращается, поэтому стик задаёт направление в мире
## напрямую: вверх по экрану — это −Z.
func _update_aim_direction(delta: float) -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() > STICK_AIM_DEADZONE:
		_mouse_aim = false
		var target := Vector3(stick.x, 0.0, stick.y).normalized()
		var reach := inverse_lerp(STICK_AIM_DEADZONE, 1.0, minf(stick.length(), 1.0))
		var far := STICK_AIM_DISTANCE_ADS if is_aiming else STICK_AIM_DISTANCE
		var distance := lerpf(STICK_AIM_MIN_DISTANCE, far, reach)
		if not _stick_aim_active:
			# Потянул стик — прицел сразу в той стороне, а не плывёт от прошлого направления
			# (на таче иначе после паузы приходилось ждать, пока он доползёт).
			_stick_aim_active = true
			_aim_direction = target
			_aim_distance = distance
			return
		var angle := _aim_direction.signed_angle_to(target, Vector3.UP)
		var max_turn := (STICK_TURN_SPEED_ADS if is_aiming else STICK_TURN_SPEED) * delta
		var turn := clampf(angle * (1.0 - exp(-STICK_TURN_SMOOTHING * delta)), -max_turn, max_turn)
		_aim_direction = _aim_direction.rotated(Vector3.UP, turn).normalized()
		_aim_distance = lerpf(_aim_distance, distance, 1.0 - exp(-STICK_DISTANCE_SMOOTHING * delta))
		return
	_stick_aim_active = false
	# Стик отпущен. На таче и геймпаде солдат смотрит по ходу движения (иначе он «залипал»
	# в старом направлении: бег боком, спринт не включается, FIRE стреляет не туда).
	# Пока выстрел ждёт затвор (aim ещё нажат), направление держим — он уйдёт туда, куда целились.
	if not _mouse_aim:
		_face_movement(delta)
		return
	var cursor := get_viewport().get_mouse_position()
	# Прицел лежит на земле, поэтому и мёртвая зона — вокруг ног солдата на экране.
	if cursor.distance_to(camera.unproject_position(global_position)) <= MOUSE_AIM_DEADZONE_PX:
		return
	var on_plane := _cursor_on_ground(cursor)
	var to_cursor := (on_plane - global_position) * Vector3(1, 0, 1)
	if to_cursor.length_squared() > 0.000001:
		_aim_direction = to_cursor.normalized()
		_aim_distance = maxf(to_cursor.length(), MIN_AIM_DISTANCE)


## Плавно поворачивает прицел по направлению ходьбы; стоим — остаётся как был.
func _face_movement(delta: float) -> void:
	if is_aiming or aim_frozen:
		return
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if move.length() < 0.1:
		return
	var target := Vector3(move.x, 0.0, move.y).normalized()
	var angle := _aim_direction.signed_angle_to(target, Vector3.UP)
	var max_turn := STICK_TURN_SPEED * delta
	var turn := clampf(angle * (1.0 - exp(-STICK_TURN_SMOOTHING * delta)), -max_turn, max_turn)
	_aim_direction = _aim_direction.rotated(Vector3.UP, turn).normalized()
	_aim_distance = lerpf(_aim_distance, STICK_AIM_DISTANCE, 1.0 - exp(-STICK_DISTANCE_SMOOTHING * delta))


## Игрок сейчас целится стиком: он зажат или выстрел ещё ждёт затвор. Камера сдвигается
## вперёд только тогда — иначе солдат вечно стоял сбоку экрана.
func has_aim_input() -> bool:
	return _stick_aim_active or is_aiming


## Точка земли под курсором. Луч камеры пересекается с самим рельефом, а не с плоскостью
## на высоте груди: иначе на склоне прицел съезжал от курсора на высоту холма.
## Высота земли зависит от точки — несколько итераций сходятся (склон положе камеры).
func _cursor_on_ground(cursor: Vector2) -> Vector3:
	var point := camera.screen_to_plane(cursor, global_position.y)
	for i in 4:
		point = camera.screen_to_plane(cursor, ground_height_at(point))
	return point


## Точка на земле под прицелом: там стоят крестик HUD и конец конуса, сюда ложится пуля,
## если ничего не задела. Считается от sight_point, то есть останавливается у укрытия.
## Сам aim_point на высоте груди — это высота полёта пули.
func get_aim_ground() -> Vector3:
	return Vector3(sight_point.x, ground_height_at(sight_point), sight_point.z)


func _vault_direction() -> Vector3:
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return Vector3(move.x, 0, move.y) if move.length() > 0.1 else _aim_direction


## Маршрут перелезания в сторону direction: {"landing": точка за укрытием, "top": высота
## его верха} или пусто, если перелезать не через что (нет укрытия, оно выше человека,
## слишком толстое или за ним некуда встать).
func find_vault(direction: Vector3) -> Dictionary:
	var dir := (direction * Vector3(1, 0, 1)).normalized()
	if dir == Vector3.ZERO or not is_on_floor() or not is_inside_tree():
		return {}
	var space := get_world_3d().direct_space_state
	var feet := global_position
	var ray := func(from: Vector3, to: Vector3) -> Dictionary:
		return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, SIGHT_BLOCKING_MASK, [get_rid()]))
	# Укрытие на уровне колен прямо перед собой.
	var knee := feet + Vector3.UP * VAULT_PROBE_HEIGHT
	var face: Dictionary = ray.call(knee, knee + dir * VAULT_REACH)
	if face.is_empty() or face.normal.y > 0.7:
		return {}  # ничего нет или это пологий склон, а не укрытие
	# Над ним на высоте выше человека должно быть свободно — иначе это стена.
	var high := feet + Vector3.UP * (VAULT_MAX_HEIGHT + 0.1)
	if not ray.call(high, high + dir * (VAULT_REACH + VAULT_MAX_DEPTH)).is_empty():
		return {}
	# Верх укрытия.
	var above: Vector3 = face.position + dir * 0.15
	var top: Dictionary = ray.call(Vector3(above.x, high.y, above.z), Vector3(above.x, feet.y, above.z))
	if top.is_empty():
		return {}
	var height: float = top.position.y - feet.y
	if height < VAULT_MIN_HEIGHT or height > VAULT_MAX_HEIGHT:
		return {}
	# Дальняя сторона: луч навстречу с той стороны. Если он начинается внутри укрытия
	# (толще VAULT_MAX_DEPTH), попадания не будет — перелезать некуда.
	var probe_y: float = knee.y
	var far_start: Vector3 = face.position + dir * (VAULT_MAX_DEPTH + VAULT_LANDING_GAP)
	far_start.y = probe_y
	var back: Dictionary = ray.call(far_start, Vector3(face.position.x, probe_y, face.position.z))
	if back.is_empty():
		return {}
	var landing: Vector3 = back.position + dir * VAULT_LANDING_GAP
	landing.y = ground_height_at(landing) + 0.05
	# Место приземления свободно.
	var shape := PhysicsShapeQueryParameters3D.new()
	shape.shape = collision_shape.shape
	shape.transform = Transform3D(Basis.IDENTITY, landing + Vector3.UP * (get_body_height() * 0.5 + 0.05))
	shape.collision_mask = collision_mask
	shape.exclude = [get_rid()]
	if not space.intersect_shape(shape, 1).is_empty():
		return {}
	return {"landing": landing, "top": top.position.y}


func _compute_sight_point() -> Vector3:
	if not is_inside_tree():
		return aim_point
	var query := PhysicsRayQueryParameters3D.create(get_shot_origin(), aim_point, SIGHT_BLOCKING_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else aim_point


func _compute_aim_point() -> Vector3:
	var point := global_position + _aim_direction * _aim_distance
	point.y = ground_height_at(point) + SHOT_HEIGHT
	return point


## Высота земли без физики (та же формула, что у меша); вне игровой сцены — свой уровень.
func ground_height_at(point: Vector3) -> float:
	var scene := get_tree().current_scene
	if scene and scene.has_method("ground_height_at"):
		return scene.ground_height_at(point.x, point.z)
	return global_position.y


func _update_aim_progress(delta: float) -> void:
	if not is_aiming:
		aim_progress = 0.0
		aim_frozen = false
		return
	if aim_frozen:
		return
	var moving := Vector2(velocity.x, velocity.z).length() > AIM_MOVING_SPEED
	var rate := (AIM_MOVING_RATE if moving else 1.0) / AIM_TIME
	aim_progress = minf(aim_progress + rate * delta, 1.0)


## Выстрел сбивает сведение прицела (вызывает Rifle).
func on_shot_fired() -> void:
	aim_progress *= AIM_SHOT_KEEP


func _update_aim() -> void:
	if not can_control():
		is_aiming = false
		return
	if GameSettings.uses_aim_toggle():
		if Input.is_action_just_pressed("aim"):
			is_aiming = not is_aiming
	else:
		is_aiming = Input.is_action_pressed("aim")


func _update_crouch() -> void:
	if not can_control():
		_crouch_toggled = false
		if is_crouching and _can_stand_up():
			is_crouching = false
		return
	var wants_crouch: bool
	if GameSettings.uses_crouch_toggle():
		if Input.is_action_just_pressed("crouch"):
			_crouch_toggled = not _crouch_toggled
		wants_crouch = _crouch_toggled
	else:
		wants_crouch = Input.is_action_pressed("crouch")
	if wants_crouch:
		is_crouching = true
	elif is_crouching and _can_stand_up():
		is_crouching = false


func _can_stand_up() -> bool:
	# Проверяем только объём над присевшей капсулой: полная капсула
	# задевала бы склон под ногами, и на неровной земле встать было бы нельзя.
	var cylinder := CylinderShape3D.new()
	cylinder.radius = (collision_shape.shape as CapsuleShape3D).radius
	cylinder.height = STAND_HEIGHT - CROUCH_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = cylinder
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (CROUCH_HEIGHT + cylinder.height * 0.5))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _apply_body_height() -> void:
	if not is_node_ready():
		return
	var height := get_body_height()
	var capsule := collision_shape.shape as CapsuleShape3D
	capsule.height = height
	collision_shape.position.y = height * 0.5
	# Временно, до анимаций: меш сжимается по высоте вместе с хитбоксом.
	body_mesh.scale.y = height / STAND_HEIGHT


# Виден и ловит пули только живой и не скрытый туманом войны.
func _update_presence() -> void:
	if not is_node_ready():
		return
	var present := health_component.is_alive and not fog_hidden
	visible = present
	collision_shape.set_deferred("disabled", not present)


func _on_life_state_changed(alive: bool) -> void:
	_update_presence()
	if not alive:
		velocity = Vector3.ZERO
		is_aiming = false
		_crouch_toggled = false
		if is_multiplayer_authority():
			is_crouching = false
	if is_multiplayer_authority():
		if weapon_hud:
			weapon_hud.visible = alive
		if alive and death_screen:
			death_screen.hide_death()


func _on_died(attacker_id: int) -> void:
	state_machine.change_state("DeadState")
	death_screen.show_death(_killer_name(attacker_id), DeadState.RESPAWN_DELAY)
	# Только сама жертва (authority своего HealthComponent, т.е. эта ветка)
	# знает о своей смерти — сообщаем хосту, чтобы GameMode/счёт/killfeed
	# обновились одинаково у всех.
	var game_mode := get_tree().current_scene.get_node_or_null("GameMode")
	if game_mode:
		game_mode.report_death.rpc_id(1, multiplayer.get_unique_id(), attacker_id)


## Ник убийцы; пусто — погиб сам (зона смерти, свой урон).
func _killer_name(attacker_id: int) -> String:
	if attacker_id <= 0 or attacker_id == get_multiplayer_authority():
		return ""
	return NetworkManager.players.get(attacker_id, {}).get("name", NetworkManager.sanitize_name("", attacker_id))
