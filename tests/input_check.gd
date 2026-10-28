extends SceneTree

## Проверка управления ПК, геймпада и сенсорного UI с камерой сверху.
## Нужен настоящий DisplayServer (в --headless GUI не получает события):
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/input_check.gd

var _failed: bool = false
var _deadline: int = Time.get_ticks_msec() + 40000
var world: Node3D
var player: CharacterBody3D
var ui: Control
var pause_menu: Control


func _init() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline:
		push_error("Проверка ввода не завершилась за 40 секунд")
		quit(1)
	return false


func _run() -> void:
	# Пользовательский settings.cfg не должен влиять на проверку.
	var settings: Node = root.get_node("GameSettings")
	settings.aim_toggle = false
	settings.crouch_toggle = false
	root.get_node("NetworkManager").players = {1: {"name": "Host", "spawn_index": 0}}
	world = load("res://scenes/game/game_scene.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	player = world.get_node("Players/1")
	ui = world.get_node("UILayer/MobileUI")
	pause_menu = world.get_node("UILayer/PauseMenu")
	await _wait_landed()
	await _check_aim()
	await _check_movement()
	await _check_crouch()
	await _check_pause()
	settings.force_touch = true
	ui.set_active(true)
	await _check_touch()
	await _check_menu_touch()
	if _failed:
		quit(1)
		return
	print("PASS: прицел мышью и стиком, движение, присед, пауза, сенсорное управление")
	quit(0)


func _wait_landed() -> void:
	for i in 240:
		await physics_frame
		if player.is_on_floor():
			return
	_check(false, "Игрок не приземлился после спавна")


## Курсор в точку экрана (как настоящая мышь: событие движения в позиции).
func _mouse_to(pos: Vector2) -> void:
	# Позицию курсора игра читает у окна — двигаем настоящий указатель, а событие
	# движения говорит игре, что целимся мышью (а не стиком).
	Input.warp_mouse(pos)
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = Vector2(1, 0)
	e.screen_relative = Vector2(1, 0)
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await process_frame
	await process_frame


func _stick(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _player_on_screen() -> Vector2:
	return player.camera.unproject_position(player.global_position + Vector3.UP * player.SHOT_HEIGHT)


## Персонаж смотрит туда же, куда целится.
func _facing() -> Vector3:
	return -player.global_basis.z


func _check_aim() -> void:
	_check(Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN, "Курсор не спрятан и не удержан в окне")
	# Курсор справа от персонажа — целится вправо (камера не вращается: вправо по экрану = +X).
	await _mouse_to(_player_on_screen() + Vector2(220, 0))
	_check(player.get_aim_direction().dot(Vector3.RIGHT) > 0.95, "Курсор справа не поворачивает прицел вправо")
	_check(_facing().dot(player.get_aim_direction()) > 0.99, "Персонаж не смотрит туда, куда целится")
	var hud: CanvasLayer = player.get_node("WeaponHUD")
	await process_frame
	_check(hud.crosshair.position.distance_to(player.camera.unproject_position(player.aim_point)) < 1.0, "Прицел HUD не в точке прицеливания")
	# Курсор выше по экрану — целится в −Z.
	await _mouse_to(_player_on_screen() + Vector2(0, -200))
	_check(player.get_aim_direction().dot(Vector3.FORWARD) > 0.95, "Курсор сверху не поворачивает прицел вперёд")
	# Курсор, проведённый через солдата, сразу разворачивает прицел: раньше вокруг него
	# была мёртвая зона в 1 м (≈90 px), и прицел «застревал» на полсекунды.
	await _mouse_to(_player_on_screen() + Vector2(20, 0))
	_check(player.get_aim_direction().dot(Vector3.RIGHT) > 0.95, "Курсор рядом с солдатом не поворачивает прицел")
	await _mouse_to(_player_on_screen() + Vector2(-20, 0))
	_check(player.get_aim_direction().dot(Vector3.LEFT) > 0.95, "Прицел застревает, когда курсор проходит через солдата")
	# Правый стик геймпада задаёт направление и перехватывает прицел у мыши.
	# Поворот стиком плавный: не скачком за один кадр (дрожь пальца дёргала прицел),
	# но и не вязкий — за полсекунды доходит.
	var before: Vector3 = player.get_aim_direction()
	_stick(JOY_AXIS_RIGHT_X, 1.0)
	await process_frame
	await process_frame
	_check(player.get_aim_direction().angle_to(Vector3.RIGHT) > 0.2 or before.angle_to(Vector3.RIGHT) < 0.2,
			"Стик поворачивает прицел скачком")
	await create_timer(0.5).timeout
	_check(player.get_aim_direction().dot(Vector3.RIGHT) > 0.95, "Правый стик не задаёт направление прицела")
	_stick(JOY_AXIS_RIGHT_X, 0.0)
	await process_frame
	_check(player.get_aim_direction().dot(Vector3.RIGHT) > 0.95, "Отпущенный стик сбрасывает направление")
	# Пошевелили мышью — снова целимся курсором.
	await _mouse_to(_player_on_screen() + Vector2(-220, 0))
	_check(player.get_aim_direction().dot(Vector3.LEFT) > 0.95, "Мышь не возвращает себе прицел после стика")
	# Прицеливание сдвигает камеру дальше в сторону взгляда.
	var focus_hip: Vector3 = player.camera._desired_focus()
	Input.action_press("aim")
	await process_frame
	await process_frame
	var focus_ads: Vector3 = player.camera._desired_focus()
	Input.action_release("aim")
	await process_frame
	_check(focus_ads.distance_to(player.global_position) > focus_hip.distance_to(player.global_position) + 1.0,
			"Прицеливание не сдвигает камеру в сторону взгляда")


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	for i in frames:
		await physics_frame


func _horizontal_velocity() -> Vector3:
	return Vector3(player.velocity.x, 0.0, player.velocity.z)


func _horizontal_speed() -> float:
	return _horizontal_velocity().length()


## Целимся «стиком» в заданную сторону: курсор мыши в тесте стоит на месте.
func _aim_towards(direction: Vector3) -> void:
	player._mouse_aim = false
	player._aim_direction = direction


func _check_movement() -> void:
	# Смотрим вправо, идём «вверх» по экрану: движение в осях мира, а не персонажа.
	_aim_towards(Vector3.RIGHT)
	await _hold("move_forward", 2)
	_check(_horizontal_speed() < PlayerState.SPEED, "Нет разгона: скорость выставляется мгновенно")
	await _hold("move_forward", 30)
	_check(is_equal_approx(_horizontal_speed(), PlayerState.SPEED), "Ходьба не выходит на скорость")
	_check(_horizontal_velocity().normalized().dot(Vector3.FORWARD) > 0.99, "Движение зависит от того, куда смотрит персонаж")
	# Спринт — только туда, куда смотришь.
	await _hold("sprint", 30)
	_check(is_equal_approx(_horizontal_speed(), PlayerState.SPEED), "Спринт боком работает")
	_aim_towards(Vector3.FORWARD)
	await _hold("sprint", 30)
	_check(is_equal_approx(_horizontal_speed(), PlayerState.SPRINT_SPEED), "Спринт не работает")
	Input.action_release("sprint")
	# С зажатым прицелом идут медленно, как в Foxhole.
	await _hold("aim", 40)
	_check(is_equal_approx(_horizontal_speed(), PlayerState.AIM_SPEED), "С прицелом солдат не замедляется")
	Input.action_release("aim")
	Input.action_release("move_forward")
	await physics_frame
	await physics_frame
	_check(_horizontal_speed() > 0.0, "Нет торможения по инерции")
	for i in 30:
		await physics_frame
	_check(is_zero_approx(_horizontal_speed()), "Игрок не останавливается")
	_check(not InputMap.has_action("jump"), "Прыжок вернулся: им перескакивают укрытия")
	_check(InputMap.has_action("vault"), "Нет перелезания (пробел)")


func _check_crouch() -> void:
	await _hold("crouch", 20)
	_check(player.is_crouching and is_equal_approx(player.collision_shape.shape.height, player.CROUCH_HEIGHT), "Присед не уменьшает капсулу")
	_check(player.head.position.y < player.STAND_HEAD_Y - 0.3, "Голова не опускается при приседе")
	_check(player.get_shot_origin().y < player.global_position.y + player.SHOT_HEIGHT - 0.2, "В приседе стреляем с высоты стоя")
	# Потолок над головой: встать нельзя.
	var ceiling := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 0.2, 3)
	shape.shape = box
	ceiling.add_child(shape)
	world.add_child(ceiling)
	ceiling.global_position = player.global_position + Vector3.UP * 1.5
	# Новое тело попадает в пространство запросов со следующего шага физики.
	await physics_frame
	await physics_frame
	Input.action_release("crouch")
	for i in 5:
		await physics_frame
	_check(player.is_crouching, "Игрок встаёт сквозь потолок")
	ceiling.free()
	for i in 5:
		await physics_frame
	_check(not player.is_crouching and is_equal_approx(player.collision_shape.shape.height, player.STAND_HEIGHT), "Игрок не встаёт без потолка")


func _check_pause() -> void:
	pause_menu.toggle()
	await process_frame
	_check(pause_menu.visible and not paused, "Пауза останавливает сетевую игру")
	_check(player.input_blocked, "Меню не блокирует ввод игрока")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "В меню не виден курсор")
	var direction: Vector3 = player.get_aim_direction()
	player._mouse_aim = true
	await _mouse_to(_player_on_screen() + Vector2(0, 200))
	_check(player.get_aim_direction().is_equal_approx(direction), "Прицел крутится при открытом меню")
	await _hold("move_forward", 20)
	_check(_horizontal_speed() < 0.01, "Игрок ходит при открытом меню")
	Input.action_release("move_forward")
	pause_menu.toggle()
	await process_frame
	_check(not player.input_blocked and Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN)
	# Меню открывается и во время смерти.
	player.health_component.take_damage(9999.0)
	await process_frame
	var e := InputEventAction.new()
	e.action = "pause"
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await process_frame
	_check(pause_menu.visible, "Меню не открывается во время смерти")
	pause_menu.toggle()
	await create_timer(2.3).timeout
	_check(player.health_component.is_alive)
	await _wait_landed()


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await process_frame


func _drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = relative
	e.screen_relative = relative
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await process_frame


func _move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _check_touch() -> void:
	var size := root.get_visible_rect().size
	# Плавающий стик движения появляется под пальцем, касание не стреляет.
	var start := Vector2(300, size.y - 250)
	await _touch(0, start, true)
	_check(ui._stick_origin == start, "Стик движения не появляется под пальцем")
	_check(not Input.is_action_pressed("shoot"), "Касание экрана нажимает «огонь»")
	await _drag(0, start + Vector2(0, -60), Vector2(0, -60))
	var move := _move_vector()
	_check(move.y < -0.5 and move.length() < 1.0, "Аналоговое движение стика не передаётся")
	await _drag(0, start + Vector2(200, -200), Vector2(200, -140))
	_check(_move_vector().length() <= 1.0001, "Ограничение стика не круглое")
	await _drag(0, start + Vector2(0, -200), Vector2(-200, 0))
	_check(Input.is_action_pressed("sprint"), "Стик до упора не включает спринт")
	# Второй палец — стик прицела справа, схема Foxhole: держишь — целишься, отпустил — выстрел.
	var aim_start := Vector2(size.x * 0.8, size.y * 0.75)
	var rifle: Node = player.weapon_manager.get_current_weapon()
	rifle.current_ammo = rifle.magazine_size
	rifle.can_fire = true
	await _touch(1, aim_start, true)
	_check(ui._aim_origin == aim_start, "Стик прицела не появляется под пальцем")
	await _drag(1, aim_start + Vector2(30, 0), Vector2(30, 0))
	await create_timer(0.5).timeout
	_check(player.is_aiming, "Стик прицела не держит прицел")
	_check(not Input.is_action_pressed("shoot"), "Стик прицела стреляет, пока его держат")
	_check(player.get_aim_direction().dot(Vector3.RIGHT) > 0.95, "Стик прицела не поворачивает прицел")
	var near: float = player._aim_distance
	await _drag(1, aim_start + Vector2(0, -80), Vector2(-30, -80))
	# В прицеле поворот стиком ограничен STICK_TURN_SPEED_ADS: 90° — около 0.35 с.
	await create_timer(1.0).timeout
	_check(player.get_aim_direction().dot(Vector3.FORWARD) > 0.95, "Стик прицела вверх не целится вперёд")
	_check(player._aim_distance > near + 3.0, "Отклонение стика не задаёт дальность")
	_check(player.aim_progress > 0.4, "Прицел не сводится, пока держишь стик")
	var ammo: int = rifle.current_ammo
	await _touch(1, aim_start, false)
	await create_timer(0.3).timeout
	_check(rifle.current_ammo == ammo - 1, "Отпускание стика прицела не стреляет")
	_check(not Input.is_action_pressed("shoot") and not Input.is_action_pressed("aim"), "Стрельба или прицел залипают после выстрела")
	_check(Input.get_vector("look_left", "look_right", "look_up", "look_down") == Vector2.ZERO, "Прицел залипает после отпускания")
	_check(player.get_aim_direction().dot(Vector3.FORWARD) > 0.95, "Направление сбрасывается при отпускании стика")
	await _touch(0, start, false)
	_check(_move_vector() == Vector2.ZERO and not Input.is_action_pressed("sprint"), "Движение залипает после отпускания")
	# Вернул палец в центр и отпустил — выстрела нет.
	await create_timer(1.2).timeout  # затвор
	ammo = rifle.current_ammo
	await _touch(2, aim_start, true)
	await _drag(2, aim_start + Vector2(70, 0), Vector2(70, 0))
	await _drag(2, aim_start + Vector2(5, 0), Vector2(-65, 0))
	await _touch(2, aim_start + Vector2(5, 0), false)
	await create_timer(0.3).timeout
	_check(rifle.current_ammo == ammo and not Input.is_action_pressed("aim"), "Отмена в центре стика всё равно стреляет")
	# FIRE слева стреляет; выстрел стиком прицела не отпускает её огонь.
	var fire_left: Vector2 = ui._buttons.fire_left.center
	await _touch(3, fire_left, true)
	await _touch(4, aim_start, true)
	await _drag(4, aim_start + Vector2(80, 0), Vector2(80, 0))
	await _touch(4, aim_start, false)
	await create_timer(1.4).timeout
	_check(Input.is_action_pressed("shoot"), "Выстрел стиком прицела отпускает FIRE слева")
	await _touch(3, fire_left, false)
	_check(not Input.is_action_pressed("shoot"))
	_check(not ui._buttons.has("aim"), "Кнопка AIM на таче лишняя: прицел держит стик")
	_check(ui._buttons.has("vault") and not ui._buttons.has("jump"), "На таче нет VAULT или остался JUMP")
	_check(not player.vault_available, "VAULT активна в чистом поле")
	# Смерть с зажатым стиком прицела: отпускание во время смерти не залипает.
	await _touch(5, aim_start, true)
	await _drag(5, aim_start + Vector2(80, 0), Vector2(80, 0))
	player.health_component.take_damage(9999.0)
	await process_frame
	await _touch(5, aim_start, false)
	await create_timer(2.3).timeout
	_check(player.health_component.is_alive and not Input.is_action_pressed("shoot") and not Input.is_action_pressed("aim"),
			"Стрельба залипает после смерти")
	# Кнопка паузы: меню открыто, сенсорный UI выключен и всё отпущено.
	await _touch(6, start, true)
	await _drag(6, start + Vector2(0, -60), Vector2(0, -60))
	await _touch(7, ui._buttons.pause.center, true)
	_check(pause_menu.visible and not ui.visible, "Кнопка паузы не открывает меню")
	_check(_move_vector() == Vector2.ZERO, "Меню не отпускает зажатые действия")
	await _touch(6, start, false)
	await _touch(7, ui._buttons.pause.center, false)
	# «Выйти» с первого касания не выходит, а просит подтверждения; кнопки разнесены.
	var exit_button: Button = pause_menu.get_node("%ExitMenuButton")
	var resume_rect: Rect2 = pause_menu.get_node("%ResumeButton").get_global_rect()
	_check(exit_button.get_global_rect().position.y - resume_rect.end.y > 100.0, "«Выйти» и «Продолжить» стоят рядом")
	var exit_center := exit_button.get_global_rect().get_center()
	await _touch(0, exit_center, true)
	await _touch(0, exit_center, false)
	_check(current_scene == world and pause_menu._exit_armed, "Выход из матча с первого нажатия")
	var resume: Button = pause_menu.get_node("%ResumeButton")
	var center := resume.get_global_rect().get_center()
	await _touch(0, center, true)
	await _touch(0, center, false)
	_check(not pause_menu.visible and ui.visible, "Кнопки меню не нажимаются касанием")
	_check(not pause_menu._exit_armed and pause_menu.exit_button.text == pause_menu.EXIT_TEXT, "Подтверждение выхода остаётся после закрытия меню")
	_check_touch_layout(size)


## Сенсорный UI поверх HUD, кнопки не перекрываются, в пределах экрана, не закрывают
## патроны и не лежат на стиках (свайп, начатый на кнопке, нажимает её).
func _check_touch_layout(size: Vector2) -> void:
	var hud: CanvasLayer = player.get_node("WeaponHUD")
	_check((ui.get_parent() as CanvasLayer).layer > hud.layer, "Сенсорные кнопки рисуются под HUD")
	var screen := Rect2(Vector2.ZERO, size)
	var names: Array = ui._buttons.keys()
	var ammo: Rect2 = hud.get_node("UILayer/BottomRight").get_global_rect()
	for i in names.size():
		var a: Dictionary = ui._buttons[names[i]]
		_check(screen.grow(-a.radius).has_point(a.center), "Кнопка %s выходит за экран" % names[i])
		for j in range(i + 1, names.size()):
			var b: Dictionary = ui._buttons[names[j]]
			_check(a.center.distance_to(b.center) > a.radius + b.radius, "Кнопки %s и %s перекрываются" % [names[i], names[j]])
		var closest: Vector2 = (a.center as Vector2).clamp(ammo.position, ammo.end)
		_check(closest.distance_to(a.center) > a.radius, "Кнопка %s закрывает патроны" % names[i])
		for stick: Vector2 in [ui._default_stick_origin(), ui._default_aim_origin()]:
			_check(stick.distance_to(a.center) > a.radius + ui.STICK_RADIUS, "Кнопка %s лежит на стике" % names[i])


## Поле ввода в главном меню фокусируется касанием: без эмуляции мыши из касаний
## на Android поля ввода не работали (кнопки — да, поэтому это не сразу заметили).
func _check_menu_touch() -> void:
	world.queue_free()
	await process_frame
	var menu: Node = load("res://scenes/main/main_menu.tscn").instantiate()
	root.add_child(menu)
	for i in 5:
		await process_frame
	var edit: LineEdit = menu.find_child("NameInput", true, false)
	var center := edit.get_global_rect().get_center()
	await _touch(0, center, true)
	await _touch(0, center, false)
	await process_frame
	_check(edit.has_focus(), "Поле ввода не фокусируется касанием")
	menu.queue_free()
	await process_frame


func _check(condition: bool, message: String = "Нарушено условие управления") -> void:
	if not condition:
		_failed = true
		push_error(message)
