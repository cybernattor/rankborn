extends Control

## Сенсорное управление. Не шлёт своих сигналов движения/стрельбы, а нажимает
## те же Input-действия, что клавиатура и геймпад (Input.action_press), — у игрока
## один путь ввода. Отдельно наружу идут только свайп камеры и кнопка паузы.
##
## Раскладка:
## - левая нижняя часть экрана — плавающий джойстик (появляется под пальцем);
##   отклонение до края вперёд включает спринт;
## - свайп по любому свободному месту — обзор;
## - FIRE справа: удержание стреляет, а перетаскивание пальца по ней крутит камеру,
##   поэтому можно целиться и стрелять одним пальцем;
## - FIRE слева — дубль для второй руки.
##
## Каждый палец отслеживается по event.index, поэтому мультитач работает полностью.

signal look_drag(delta: Vector2)
signal pause_pressed

const STICK_RADIUS := 80.0
const SPRINT_THRESHOLD := 0.95
const MOVE_ZONE_WIDTH := 0.4
const MOVE_ZONE_TOP := 0.5
const MOVE_ACTIONS := ["move_left", "move_right", "move_forward", "move_back"]

const COLOR_FILL := Color(0.1, 0.12, 0.15, 0.35)
const COLOR_FILL_ACTIVE := Color(0.95, 0.75, 0.3, 0.45)
const COLOR_RING := Color(1, 1, 1, 0.55)
const COLOR_TEXT := Color(1, 1, 1, 0.85)

## Игрок, чьи состояния (прицел, присед) подсвечиваются на кнопках.
var player: Node

var _active: bool = false
var _buttons: Dictionary = {}  # имя → {center, radius, label, action, look}
var _touches: Dictionary = {}  # индекс пальца → {role, button}
var _stick_origin := Vector2.ZERO
var _stick_vector := Vector2.ZERO
var _stick_index: int = -1


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
		"fire": {"center": Vector2(w - 130, h - 170), "radius": 64.0, "label": "FIRE", "action": "shoot", "look": true},
		"fire_left": {"center": Vector2(110, h * 0.36), "radius": 42.0, "label": "FIRE", "action": "shoot", "look": false},
		"aim": {"center": Vector2(w - 120, h - 330), "radius": 44.0, "label": "AIM", "action": "aim", "look": false},
		"reload": {"center": Vector2(w - 270, h - 250), "radius": 40.0, "label": "R", "action": "reload", "look": false},
		"jump": {"center": Vector2(w - 270, h - 110), "radius": 46.0, "label": "JUMP", "action": "jump", "look": false},
		"crouch": {"center": Vector2(w - 390, h - 80), "radius": 40.0, "label": "DUCK", "action": "crouch", "look": false},
		"pause": {"center": Vector2(w - 56, 56), "radius": 32.0, "label": "II", "action": "", "look": false},
	}
	_stick_origin = _default_stick_origin()
	queue_redraw()


func _default_stick_origin() -> Vector2:
	return Vector2(170, size.y - 170)


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
		_on_drag(event.index, event.position, event.relative)
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
	else:
		_touches[index] = {"role": "look"}
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
	queue_redraw()


func _on_drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if not _touches.has(index):
		return
	var touch: Dictionary = _touches[index]
	match touch.role:
		"move":
			_set_stick((pos - _stick_origin).limit_length(STICK_RADIUS) / STICK_RADIUS)
		"look":
			look_drag.emit(relative)
		"button":
			if _buttons[touch.button].look:
				look_drag.emit(relative)


func _set_stick(vec: Vector2) -> void:
	_stick_vector = vec
	# Мёртвую зону с перенормировкой применяет Input.get_vector (deadzone действий).
	_set_action_strength("move_left", maxf(-vec.x, 0.0))
	_set_action_strength("move_right", maxf(vec.x, 0.0))
	_set_action_strength("move_forward", maxf(-vec.y, 0.0))
	_set_action_strength("move_back", maxf(vec.y, 0.0))
	# Стик до упора вперёд — спринт (отдельной кнопки нет).
	if vec.length() >= SPRINT_THRESHOLD and vec.y < -0.7:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")
	queue_redraw()


func _set_action_strength(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _is_action_held_by_other(action: String) -> bool:
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
	_stick_origin = _default_stick_origin()
	for action in MOVE_ACTIONS:
		Input.action_release(action)
	Input.action_release("sprint")
	_stick_vector = Vector2.ZERO
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
	# Джойстик
	draw_circle(_stick_origin, STICK_RADIUS, COLOR_FILL)
	draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 48, COLOR_RING, 2.0, true)
	draw_circle(_stick_origin + _stick_vector * STICK_RADIUS, 32.0, COLOR_RING)
	# Кнопки
	for name in _buttons:
		var b: Dictionary = _buttons[name]
		draw_circle(b.center, b.radius, COLOR_FILL_ACTIVE if _is_button_lit(name) else COLOR_FILL)
		draw_arc(b.center, b.radius, 0.0, TAU, 40, COLOR_RING, 2.0, true)
		var font_size := 18 if b.radius < 45.0 else 22
		var text_size := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, b.center + Vector2(-text_size.x * 0.5, text_size.y * 0.3), b.label,
				HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COLOR_TEXT)
