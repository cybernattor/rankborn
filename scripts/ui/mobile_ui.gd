extends Control

@onready var left_joystick: TextureRect = $LeftJoystick
@onready var left_stick: TextureRect = $LeftJoystick/LeftStick
@onready var right_joystick: TextureRect = $RightJoystick
@onready var right_stick: TextureRect = $RightJoystick/RightStick
@onready var shoot_button: TextureButton = $ShootButton
@onready var reload_button: TextureButton = $ReloadButton
@onready var interact_button: TextureButton = $InteractButton

var left_drag_id: int = -1
var right_drag_id: int = -1
var move_vec: Vector2 = Vector2.ZERO
var look_vec: Vector2 = Vector2.ZERO
var shoot_pressed: bool = false
var reload_pressed: bool = false
var interact_pressed: bool = false

signal move_input(vec: Vector2)
signal look_input(vec: Vector2)
signal shoot_input(pressed: bool)
signal reload_input
signal interact_input

func _ready() -> void:
	if not DisplayServer.is_touchscreen_available():
		hide()
		return
	
	shoot_button.pressed.connect(_on_shoot_pressed)
	shoot_button.button_up.connect(_on_shoot_released)
	reload_button.pressed.connect(_on_reload_pressed)
	interact_button.pressed.connect(_on_interact_pressed)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _point_in_rect(event.position, left_joystick.get_rect()):
			left_drag_id = event.index
		elif _point_in_rect(event.position, right_joystick.get_rect()):
			right_drag_id = event.index
	else:
		if event.index == left_drag_id:
			left_drag_id = -1
			move_vec = Vector2.ZERO
			_animate_stick_to_center(left_stick)
			move_input.emit(Vector2.ZERO)
		elif event.index == right_drag_id:
			right_drag_id = -1
			look_vec = Vector2.ZERO
			_animate_stick_to_center(right_stick)
			look_input.emit(Vector2.ZERO)

func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == left_drag_id:
		var center = left_joystick.get_rect().position + left_joystick.get_rect().size / 2
		var offset = event.position - center
		var radius = left_joystick.get_rect().size.x / 2
		offset = offset.clamp(Vector2(-radius, -radius), Vector2(radius, radius))
		left_stick.position = offset
		move_vec = offset / radius
		move_input.emit(move_vec)
	elif event.index == right_drag_id:
		var center = right_joystick.get_rect().position + right_joystick.get_rect().size / 2
		var offset = event.position - center
		var radius = right_joystick.get_rect().size.x / 2
		offset = offset.clamp(Vector2(-radius, -radius), Vector2(radius, radius))
		right_stick.position = offset
		look_vec = offset / radius
		look_input.emit(look_vec)

func _point_in_rect(point: Vector2, rect: Rect2) -> bool:
	return point.x >= rect.position.x and point.x <= rect.position.x + rect.size.x and \
		   point.y >= rect.position.y and point.y <= rect.position.y + rect.size.y

func _animate_stick_to_center(stick: TextureRect) -> void:
	var tween = create_tween()
	tween.tween_property(stick, "position", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_shoot_pressed() -> void:
	shoot_pressed = true
	shoot_input.emit(true)

func _on_shoot_released() -> void:
	shoot_pressed = false
	shoot_input.emit(false)

func _on_reload_pressed() -> void:
	reload_pressed = true
	reload_input.emit()

func _on_interact_pressed() -> void:
	interact_pressed = true
	interact_input.emit()