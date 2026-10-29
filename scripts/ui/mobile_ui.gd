extends Control

## Сенсорное управление для камеры сверху: два стика, как в twin-stick шутерах.
## Не шлёт своих сигналов движения/стрельбы, а нажимает те же Input-действия,
## что клавиатура и геймпад (Input.action_press), — у игрока один путь ввода.
## Наружу идёт только кнопка паузы.
##
## Раскладка:
## - левая нижняя часть экрана — плавающий стик движения (появляется под пальцем);
##   отклонение до края включает спринт;
## - правая нижняя часть — плавающий стик прицела, схема Foxhole на тач:
##   взял стик — целишься (зажато действие aim: конус сводится, солдат идёт медленно),
##   направление и дальность — куда и насколько отклонил (look_*, как правый стик
##   геймпада), отпустил — выстрел. Вернул палец в центр (внутреннее кольцо) и отпустил —
##   выстрела нет. Целиться и стрелять — два разных решения, как ПКМ и ЛКМ у Foxhole:
##   раньше стик стрелял при сильном отклонении, и точно навестись, не выстрелив, было нельзя;
## - над стиком прицела — ряд DUCK, R, VAULT (перелезть через низкое укрытие; тусклая,
##   когда перелезать не через что);
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
## Отпускание стика прицела ближе этого к центру (доля радиуса) — отмена выстрела.
const AIM_CANCEL_RADIUS := 0.3
## Сколько держим «огонь» после отпускания стика: стейты опрашивают ввод в физике,
## мгновенное нажатие-отпускание они бы пропустили. Если винтовка ещё передёргивает
## затвор, ждём выстрела, но не дольше SHOT_MAX_WAIT.
const SHOT_HOLD := 0.1
const SHOT_MAX_WAIT := 1.3

## Кнопки — рядом над зоной стика прицела, справа налево.
const ROW_BUTTON_RADIUS := 42.0
const ROW_SPACING := 104.0
const ROW_BUTTONS := [
	{"name": "vault", "label": "VAULT", "action": "vault"},
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
## Выстрел после отпускания стика ещё не случился (держим «огонь»).
var _pending_shot: bool = false
var _pending_time: float = 0.0
var _pending_ammo: int = 0


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


# Выход из матча (меню, смена сцены) освобождает нажатые действия: Input.action_press живёт
# в синглтоне и без этого перешёл бы в следующий матч (идёшь/стреляешь сам по себе).
func _exit_tree() -> void:
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


func _process(delta: float) -> void:
	if not _active:
		return
	if _pending_shot:
		_update_pending_shot(delta)
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
		_freeze_aim(false)
		Input.action_press("aim")
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
			var fire := _aim_vector.length() >= AIM_CANCEL_RADIUS
			_aim_index = -1
			_aim_origin = _default_aim_origin()
			_set_aim(Vector2.ZERO)
			if fire:
				_start_pending_shot()
			else:
				Input.action_release("aim")
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
	queue_redraw()


# Прицел держим зажатым до выстрела: иначе в момент выстрела разброс уже снова от бедра.
# Но сведение при этом замораживаем: пока выстрел ждёт затвор (до SHOT_MAX_WAIT), конус
# не должен сужаться после того, как палец уже убран.
func _start_pending_shot() -> void:
	_freeze_aim(true)
	_pending_shot = true
	_pending_time = 0.0
	_pending_ammo = _current_ammo()
	Input.action_press("shoot")


func _update_pending_shot(delta: float) -> void:
	_pending_time += delta
	var fired := _current_ammo() < _pending_ammo
	var weapon := _current_weapon()
	var cannot := weapon == null or weapon.is_reloading or weapon.current_ammo <= 0
	if (_pending_time >= SHOT_HOLD and (fired or cannot)) or _pending_time >= SHOT_MAX_WAIT:
		_finish_pending_shot()


func _freeze_aim(frozen: bool) -> void:
	if player:
		player.aim_frozen = frozen


func _finish_pending_shot() -> void:
	_pending_shot = false
	if not _is_action_held_by_other("shoot"):
		Input.action_release("shoot")
	# Новое касание стика прицела уже снова держит прицел — не отпускаем его.
	if _aim_index == -1:
		Input.action_release("aim")


func _current_weapon() -> WeaponBase:
	if player and player.weapon_manager:
		return player.weapon_manager.get_current_weapon()
	return null


func _current_ammo() -> int:
	var weapon := _current_weapon()
	return weapon.current_ammo if weapon else 0


func _set_action_strength(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _is_action_held_by_other(action: String) -> bool:
	if action == "shoot" and _pending_shot:
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
	Input.action_release("aim")
	_pending_shot = false
	_freeze_aim(false)
	_stick_vector = Vector2.ZERO
	_aim_vector = Vector2.ZERO
	queue_redraw()


func _is_button_lit(name: String) -> bool:
	for touch in _touches.values():
		if touch.role == "button" and touch.button == name:
			return true
	if player:
		if name == "crouch":
			return player.is_crouching
	return false


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Стик движения
	draw_circle(_stick_origin, STICK_RADIUS, COLOR_FILL)
	draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 48, COLOR_RING, 2.0, true)
	draw_circle(_stick_origin + _stick_vector * STICK_RADIUS, 32.0, COLOR_RING)
	# Стик прицела: пока держишь — подсвечен (целишься), внутри кольца отмены — красный
	# (отпустишь здесь — выстрела не будет)
	var aiming := _aim_index != -1
	var cancel := aiming and _aim_vector.length() < AIM_CANCEL_RADIUS
	draw_circle(_aim_origin, STICK_RADIUS, COLOR_FIRE if cancel else (COLOR_FILL_ACTIVE if aiming else COLOR_FILL))
	draw_arc(_aim_origin, STICK_RADIUS, 0.0, TAU, 48, COLOR_RING, 2.0, true)
	draw_arc(_aim_origin, STICK_RADIUS * AIM_CANCEL_RADIUS, 0.0, TAU, 32, COLOR_RING * Color(1, 1, 1, 0.5), 1.5, true)
	draw_circle(_aim_origin + _aim_vector * STICK_RADIUS, 32.0, COLOR_RING)
	# Кнопки
	for name in _buttons:
		var b: Dictionary = _buttons[name]
		var dim: bool = name == "vault" and player != null and not player.vault_available
		var tint := Color(1, 1, 1, 0.35) if dim else Color.WHITE
		draw_circle(b.center, b.radius, (COLOR_FILL_ACTIVE if _is_button_lit(name) else COLOR_FILL) * tint)
		draw_arc(b.center, b.radius, 0.0, TAU, 40, COLOR_RING * tint, 2.0, true)
		var font_size := 18 if b.radius < 45.0 else 22
		var text_size := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, b.center + Vector2(-text_size.x * 0.5, text_size.y * 0.3), b.label,
				HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COLOR_TEXT * tint)
