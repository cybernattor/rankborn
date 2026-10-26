extends Control

## Сенсорное управление для камеры сверху: два стика, как в twin-stick шутерах.
## Не шлёт своих сигналов движения/стрельбы, а нажимает те же Input-действия,
## что клавиатура и геймпад (Input.action_press), — у игрока один путь ввода.
## Наружу идёт только кнопка паузы.
##
## Раскладка:
## - левая нижняя часть экрана — плавающий стик движения (появляется под пальцем);
##   отклонение до края включает спринт;
## - правая нижняя часть — плавающий стик прицела: направление задаёт, куда смотрит
##   и стреляет персонаж (действия look_*, как правый стик геймпада); отклонение
##   дальше FIRE_THRESHOLD — огонь. Так двигаться, целиться и стрелять можно двумя
##   пальцами, без «третьей руки»;
## - над стиком прицела — ряд DUCK, R, AIM, JUMP;
## - FIRE слева — стрельба без смены направления (стоя на месте, второй рукой).
##
## Каждый палец отслеживается по event.index, поэтому мультитач работает полностью.

signal pause_pressed

const STICK_RADIUS := 80.0
const SPRINT_THRESHOLD := 0.95
const MOVE_ZONE_WIDTH := 0.4
const MOVE_ZONE_TOP := 0.5
const MOVE_ACTIONS := ["move_left", "move_right", "move_forward", "move_back"]
const LOOK_ACTIONS := ["look_left", "look_right", "look_up", "look_down"]

## Стик прицела: зона справа снизу, точка по умолчанию — от правого нижнего угла.
const AIM_ZONE_LEFT := 0.55
const AIM_ZONE_TOP := 0.45
const AIM_STICK_MARGIN := Vector2(200, 180)
## Отклонение стика прицела, с которого он стреляет (доля радиуса).
const FIRE_THRESHOLD := 0.7

## Кнопки — рядом над зоной стика прицела, справа налево.
const ROW_BUTTON_RADIUS := 42.0
const ROW_SPACING := 104.0
const ROW_BUTTONS := [
	{"name": "jump", "label": "JUMP", "action": "jump"},
	{"name": "aim", "label": "AIM", "action": "aim"},
	{"name": "reload", "label": "R", "action": "reload"},
	{"name": "crouch", "label": "DUCK", "action": "crouch"},
]

const COLOR_FILL := Color(0.1, 0.12, 0.15, 0.35)
const COLOR_FILL_ACTIVE := Color(0.95, 0.75, 0.3, 0.45)
const COLOR_FIRE := Color(0.9, 0.3, 0.2, 0.45)
const COLOR_RING := Color(1, 1, 1, 0.55)
const COLOR_TEXT := Color(1, 1, 1, 0.85)

## Игрок, чьи состояния (прицел, присед) подсвечиваются на кнопках.
var player: Node

var _active: bool = false
var _buttons: Dictionary = {}  # имя → {center, radius, label, action}
var _touches: Dictionary = {}  # индекс пальца → {role, button}
var _stick_origin := Vector2.ZERO
var _stick_vector := Vector2.ZERO
var _stick_index: int = -1
var _aim_origin := Vector2.ZERO
var _aim_vector := Vector2.ZERO
var _aim_index: int = -1
## Стик прицела сейчас держит «огонь» нажатым.
var _aim_firing: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()
	set_active(GameSettings.is_touch_device())


func set_active(active: bool) -> void:
	_active = active
	visible = active
	if not active:
		_release_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_all()


func _layout() -> void:
	var w := size.x
	var h := size.y
	_buttons = {
		"fire_left": {"center": Vector2(110, h * 0.36), "radius": 42.0, "label": "FIRE", "action": "shoot"},
		"pause": {"center": Vector2(w - 56, 56), "radius": 32.0, "label": "II", "action": ""},
	}
	var row_y := h * AIM_ZONE_TOP - ROW_BUTTON_RADIUS - 12.0
	for i in ROW_BUTTONS.size():
		var spec: Dictionary = ROW_BUTTONS[i]
		_buttons[spec.name] = {
			"center": Vector2(w - 70.0 - i * ROW_SPACING, row_y),
			"radius": ROW_BUTTON_RADIUS, "label": spec.label, "action": spec.action,
		}
	_stick_origin = _default_stick_origin()
	_aim_origin = _default_aim_origin()
	queue_redraw()


func _default_stick_origin() -> Vector2:
	return Vector2(170, size.y - 170)


func _default_aim_origin() -> Vector2:
	return size - AIM_STICK_MARGIN


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_touch_down(event.index, event.position)
		else:
			_on_touch_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _active:
		queue_redraw()  # подсветка прицела/приседа зависит от состояния игрока


func _on_touch_down(index: int, pos: Vector2) -> void:
	var button := _button_at(pos)
	if button != "":
		_touches[index] = {"role": "button", "button": button}
		if button == "pause":
			pause_pressed.emit()
		else:
			Input.action_press(_buttons[button].action)
	elif _stick_index == -1 and pos.x < size.x * MOVE_ZONE_WIDTH and pos.y > size.y * MOVE_ZONE_TOP:
		_touches[index] = {"role": "move"}
		_stick_index = index
		_stick_origin = pos
		_set_stick(Vector2.ZERO)
	elif _aim_index == -1 and pos.x > size.x * AIM_ZONE_LEFT and pos.y > size.y * AIM_ZONE_TOP:
		_touches[index] = {"role": "aim"}
		_aim_index = index
		_aim_origin = pos
		_set_aim(Vector2.ZERO)
	queue_redraw()


func _on_touch_up(index: int) -> void:
	if not _touches.has(index):
		return
	var touch: Dictionary = _touches[index]
	_touches.erase(index)
	match touch.role:
		"button":
			var action: String = _buttons[touch.button].action
			if action != "" and not _is_action_held_by_other(action):
				Input.action_release(action)
		"move":
			_stick_index = -1
			_stick_origin = _default_stick_origin()
			_set_stick(Vector2.ZERO)
		"aim":
			_aim_index = -1
			_aim_origin = _default_aim_origin()
			_set_aim(Vector2.ZERO)
	queue_redraw()


func _on_drag(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	match _touches[index].role:
		"move":
			_set_stick((pos - _stick_origin).limit_length(STICK_RADIUS) / STICK_RADIUS)
		"aim":
			_set_aim((pos - _aim_origin).limit_length(STICK_RADIUS) / STICK_RADIUS)


func _set_stick(vec: Vector2) -> void:
	_stick_vector = vec
	# Мёртвую зону с перенормировкой применяет Input.get_vector (deadzone действий).
	_set_action_strength("move_left", maxf(-vec.x, 0.0))
	_set_action_strength("move_right", maxf(vec.x, 0.0))
	_set_action_strength("move_forward", maxf(-vec.y, 0.0))
	_set_action_strength("move_back", maxf(vec.y, 0.0))
	# Стик до упора — спринт (отдельной кнопки нет); бежать можно только
	# туда, куда смотришь, — это проверяет PlayerState.
	if vec.length() >= SPRINT_THRESHOLD:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")
	queue_redraw()


func _set_aim(vec: Vector2) -> void:
	_aim_vector = vec
	_set_action_strength("look_left", maxf(-vec.x, 0.0))
	_set_action_strength("look_right", maxf(vec.x, 0.0))
	_set_action_strength("look_up", maxf(-vec.y, 0.0))
	_set_action_strength("look_down", maxf(vec.y, 0.0))
	var firing := vec.length() >= FIRE_THRESHOLD
	if firing != _aim_firing:
		_aim_firing = firing
		if firing:
			Input.action_press("shoot")
		elif not _is_action_held_by_other("shoot"):
			Input.action_release("shoot")
	queue_redraw()


func _set_action_strength(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _is_action_held_by_other(action: String) -> bool:
	if action == "shoot" and _aim_firing:
		return true
	for touch in _touches.values():
		if touch.role == "button" and _buttons[touch.button].action == action:
			return true
	return false


func _button_at(pos: Vector2) -> String:
	for name in _buttons:
		var b: Dictionary = _buttons[name]
		if pos.distance_to(b.center) <= b.radius:
			return name
	return ""


func _release_all() -> void:
	for touch in _touches.values():
		if touch.role == "button" and _buttons[touch.button].action != "":
			Input.action_release(_buttons[touch.button].action)
	_touches.clear()
	_stick_index = -1
	_aim_index = -1
	_stick_origin = _default_stick_origin()
	_aim_origin = _default_aim_origin()
	for action in MOVE_ACTIONS + LOOK_ACTIONS:
		Input.action_release(action)
	Input.action_release("sprint")
	Input.action_release("shoot")
	_aim_firing = false
	_stick_vector = Vector2.ZERO
	_aim_vector = Vector2.ZERO
	queue_redraw()


func _is_button_lit(name: String) -> bool:
	for touch in _touches.values():
		if touch.role == "button" and touch.button == name:
			return true
	if player:
		if name == "aim":
			return player.is_aiming
		if name == "crouch":
			return player.is_crouching
	return false


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Стик движения
	draw_circle(_stick_origin, STICK_RADIUS, COLOR_FILL)
	draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 48, COLOR_RING, 2.0, true)
	draw_circle(_stick_origin + _stick_vector * STICK_RADIUS, 32.0, COLOR_RING)
	# Стик прицела: внутреннее кольцо — порог огня, при стрельбе заливка красная
	draw_circle(_aim_origin, STICK_RADIUS, COLOR_FIRE if _aim_firing else COLOR_FILL)
	draw_arc(_aim_origin, STICK_RADIUS, 0.0, TAU, 48, COLOR_RING, 2.0, true)
	draw_arc(_aim_origin, STICK_RADIUS * FIRE_THRESHOLD, 0.0, TAU, 48, COLOR_RING * Color(1, 1, 1, 0.5), 1.5, true)
	draw_circle(_aim_origin + _aim_vector * STICK_RADIUS, 32.0, COLOR_RING)
	# Кнопки
	for name in _buttons:
		var b: Dictionary = _buttons[name]
		draw_circle(b.center, b.radius, COLOR_FILL_ACTIVE if _is_button_lit(name) else COLOR_FILL)
		draw_arc(b.center, b.radius, 0.0, TAU, 40, COLOR_RING, 2.0, true)
		var font_size := 18 if b.radius < 45.0 else 22
		var text_size := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, b.center + Vector2(-text_size.x * 0.5, text_size.y * 0.3), b.label,
				HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COLOR_TEXT)
