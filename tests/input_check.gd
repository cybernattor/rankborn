extends SceneTree

## Проверка управления ПК и сенсорного UI.
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
	settings.mouse_sensitivity = 0.002
	settings.touch_sensitivity = 0.004
	settings.invert_y = false
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
	await _check_mouse_look(settings)
	await _check_movement()
	await _check_crouch()
	await _check_pause()
	settings.force_touch = true
	ui.set_active(true)
	await _check_touch()
	if _failed:
		quit(1)
		return
	print("PASS: мышь, геймпад-ось, движение, присед, пауза, сенсорное управление")
	quit(0)


func _wait_landed() -> void:
	for i in 240:
		await physics_frame
		if player.is_on_floor():
			return
	_check(false, "Игрок не приземлился после спавна")


func _mouse(screen_relative: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = root.get_visible_rect().size * 0.5
	e.global_position = e.position
	e.relative = Vector2.ZERO
	e.screen_relative = screen_relative
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await process_frame


func _check_mouse_look(settings: Node) -> void:
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Мышь не захвачена в игре")
	var yaw := player.rotation.y
	var pitch: float = player.head.rotation.x
	await _mouse(Vector2(100, 50))
	_check(is_equal_approx(_turned_right(yaw), 0.2), "Мышь в центре экрана не поворачивает камеру (HUD съедает движение?)")
	_check(is_equal_approx(pitch - player.head.rotation.x, 0.1), "Мышь не наклоняет голову")
	# В прицеле поворот медленнее пропорционально tan(fov/2).
	player.camera.fov = player.AIM_FOV
	player.set_process(false)
	yaw = player.rotation.y
	await _mouse(Vector2(100, 0))
	var expected := 0.2 * tan(deg_to_rad(player.AIM_FOV) * 0.5) / tan(deg_to_rad(player.DEFAULT_FOV) * 0.5)
	_check(is_equal_approx(_turned_right(yaw), expected), "Чувствительность в прицеле не масштабируется по FOV")
	player.camera.fov = player.DEFAULT_FOV
	player.set_process(true)
	settings.invert_y = true
	pitch = player.head.rotation.x
	await _mouse(Vector2(0, 50))
	_check(player.head.rotation.x > pitch, "Инверсия Y не работает")
	settings.invert_y = false
	player.head.rotation.x = 0.0
	# Правый стик геймпада крутит камеру непрерывно, пока отклонён.
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_RIGHT_X
	stick.axis_value = 1.0
	Input.parse_input_event(stick)
	Input.flush_buffered_events()
	yaw = player.rotation.y
	await create_timer(0.3).timeout
	_check(_turned_right(yaw) > 0.5, "Правый стик геймпада не поворачивает камеру")
	stick.axis_value = 0.0
	Input.parse_input_event(stick)
	Input.flush_buffered_events()
	await process_frame


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	for i in frames:
		await physics_frame


func _horizontal_speed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func _check_movement() -> void:
	await _hold("move_forward", 2)
	_check(_horizontal_speed() < PlayerState.SPEED, "Нет разгона: скорость выставляется мгновенно")
	await _hold("move_forward", 30)
	_check(is_equal_approx(_horizontal_speed(), PlayerState.SPEED), "Ходьба не выходит на скорость")
	await _hold("sprint", 30)
	_check(is_equal_approx(_horizontal_speed(), PlayerState.SPRINT_SPEED), "Спринт не работает")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await physics_frame
	await physics_frame
	_check(_horizontal_speed() > 0.0, "Нет торможения по инерции")
	for i in 30:
		await physics_frame
	_check(is_zero_approx(_horizontal_speed()), "Игрок не останавливается")
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	_check(player.velocity.y > 0.0, "Прыжок по действию jump не работает")
	await _wait_landed()


func _check_crouch() -> void:
	await _hold("crouch", 20)
	_check(player.is_crouching and is_equal_approx(player.collision_shape.shape.height, player.CROUCH_HEIGHT), "Присед не уменьшает капсулу")
	_check(player.head.position.y < player.STAND_HEAD_Y - 0.3, "Голова не опускается при приседе")
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
	var yaw := player.rotation.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _mouse(Vector2(100, 0))
	_check(is_equal_approx(yaw, player.rotation.y), "Камера крутится при открытом меню")
	await _hold("move_forward", 20)
	_check(_horizontal_speed() < 0.01, "Игрок ходит при открытом меню")
	Input.action_release("move_forward")
	pause_menu.toggle()
	await process_frame
	_check(not player.input_blocked and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
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


func _check_touch() -> void:
	var size := root.get_visible_rect().size
	# Плавающий джойстик появляется под пальцем, касание не стреляет.
	var start := Vector2(300, size.y - 250)
	await _touch(0, start, true)
	_check(ui._stick_origin == start, "Джойстик не появляется под пальцем")
	_check(not Input.is_action_pressed("shoot"), "Касание экрана нажимает «огонь»")
	await _drag(0, start + Vector2(0, -60), Vector2(0, -60))
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_check(move.y < -0.5 and move.length() < 1.0, "Аналоговое движение джойстика не передаётся")
	await _drag(0, start + Vector2(200, -200), Vector2(200, -140))
	move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_check(move.length() <= 1.0001, "Ограничение джойстика не круглое")
	await _drag(0, start + Vector2(0, -200), Vector2(-200, 0))
	_check(Input.is_action_pressed("sprint"), "Джойстик до упора вперёд не включает спринт")
	# Второй палец на FIRE стреляет, перетаскивание по FIRE крутит камеру.
	var fire: Vector2 = ui._buttons.fire.center
	await _touch(1, fire, true)
	_check(Input.is_action_pressed("shoot"), "FIRE вторым пальцем не стреляет")
	var yaw := player.rotation.y
	await _drag(1, fire + Vector2(40, 0), Vector2(40, 0))
	_check(_turned_right(yaw) > 0.0, "Перетаскивание по FIRE не крутит камеру")
	await _touch(1, fire, false)
	_check(not Input.is_action_pressed("shoot"))
	await _touch(0, start, false)
	_check(Input.get_vector("move_left", "move_right", "move_forward", "move_back") == Vector2.ZERO and not Input.is_action_pressed("sprint"), "Движение залипает после отпускания")
	# Свайп по свободному месту — обзор.
	yaw = player.rotation.y
	var pitch: float = player.head.rotation.x
	var free_spot := Vector2(size.x * 0.6, size.y * 0.3)
	await _touch(2, free_spot, true)
	await _drag(2, free_spot + Vector2(50, 25), Vector2(50, 25))
	_check(is_equal_approx(_turned_right(yaw), 0.2) and player.head.rotation.x < pitch, "Свайп не поворачивает камеру")
	await _touch(2, free_spot, false)
	# AIM на тач-экране — переключатель.
	var aim: Vector2 = ui._buttons.aim.center
	await _touch(3, aim, true)
	await _touch(3, aim, false)
	await process_frame
	_check(player.is_aiming, "AIM на тач-экране не включает прицел")
	await _touch(3, aim, true)
	await _touch(3, aim, false)
	await process_frame
	_check(not player.is_aiming, "AIM на тач-экране не выключает прицел")
	# Смерть с зажатым FIRE: отпускание во время смерти не теряется.
	await _touch(4, fire, true)
	player.health_component.take_damage(9999.0)
	await process_frame
	await _touch(4, fire, false)
	await create_timer(2.3).timeout
	_check(player.health_component.is_alive and not Input.is_action_pressed("shoot"), "Стрельба залипает после смерти")
	# Кнопка паузы: меню открыто, сенсорный UI выключен и всё отпущено.
	await _touch(5, start, true)
	await _drag(5, start + Vector2(0, -60), Vector2(0, -60))
	await _touch(6, ui._buttons.pause.center, true)
	_check(pause_menu.visible and not ui.visible, "Кнопка паузы не открывает меню")
	_check(Input.get_vector("move_left", "move_right", "move_forward", "move_back") == Vector2.ZERO, "Меню не отпускает зажатые действия")
	await _touch(5, start, false)
	await _touch(6, ui._buttons.pause.center, false)
	# Слайдер тянется касанием: без эмуляции мыши из касаний поля ввода и слайдеры
	# на Android не реагировали (кнопки — да, поэтому это не сразу заметили).
	var slider: HSlider = pause_menu.get_node("VBoxContainer/TouchSensSlider")
	var before := slider.value
	var rect := slider.get_global_rect()
	var target := Vector2(rect.position.x + rect.size.x * 0.9, rect.get_center().y)
	# Мышь эмулируется от первого пальца, коснувшегося, когда других нет.
	await _touch(0, target, true)
	await _touch(0, target, false)
	_check(slider.value != before, "Слайдер в меню не реагирует на касание")
	slider.value = before
	# Кнопки меню нажимаются касанием.
	var resume: Button = pause_menu.get_node("%ResumeButton")
	var center := resume.get_global_rect().get_center()
	await _touch(7, center, true)
	await _touch(7, center, false)
	_check(not pause_menu.visible and ui.visible, "Кнопки меню не нажимаются касанием")
	_check_touch_layout(size)


## Сенсорный UI поверх HUD (прицел закрывал кнопки, но они нажимались), кнопки
## не перекрываются, в пределах экрана и не закрывают патроны.
func _check_touch_layout(size: Vector2) -> void:
	var hud: CanvasLayer = player.get_node("WeaponHUD")
	_check((ui.get_parent() as CanvasLayer).layer > hud.layer, "Сенсорные кнопки рисуются под HUD")
	var screen := Rect2(Vector2.ZERO, size)
	var names: Array = ui._buttons.keys()
	for i in names.size():
		var a: Dictionary = ui._buttons[names[i]]
		_check(screen.grow(-a.radius).has_point(a.center), "Кнопка %s выходит за экран" % names[i])
		for j in range(i + 1, names.size()):
			var b: Dictionary = ui._buttons[names[j]]
			_check(a.center.distance_to(b.center) > a.radius + b.radius, "Кнопки %s и %s перекрываются" % [names[i], names[j]])
	var ammo: Rect2 = hud.get_node("UILayer/BottomRight").get_global_rect()
	for name in names:
		var b: Dictionary = ui._buttons[name]
		var closest: Vector2 = (b.center as Vector2).clamp(ammo.position, ammo.end)
		_check(closest.distance_to(b.center) > b.radius, "Кнопка %s закрывает патроны" % name)


## Поворот вправо с момента yaw_before, с учётом перехода угла через ±PI.
func _turned_right(yaw_before: float) -> float:
	return angle_difference(player.rotation.y, yaw_before)


func _check(condition: bool, message: String = "Нарушено условие управления") -> void:
	if not condition:
		_failed = true
		push_error(message)
