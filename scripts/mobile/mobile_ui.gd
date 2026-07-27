extends CanvasLayer

@onready var move_stick: TouchScreenButton = %MoveStick
@onready var look_stick: TouchScreenButton = %LookStick

var move_input := Vector2.ZERO
var look_input := Vector2.ZERO

func _ready() -> void:
	if not DisplayServer.is_touchscreen_available():
		hide()
		return
	move_stick.released.connect(_on_move_released)
	look_stick.released.connect(_on_look_released)

func _on_move_released() -> void:
	move_input = Vector2.ZERO

func _on_look_released() -> void:
	look_input = Vector2.ZERO

func get_move_input() -> Vector2:
	if move_stick and move_stick.is_pressed():
		return move_stick.position.normalized()
	return Vector2.ZERO

func get_look_input() -> Vector2:
	if look_stick and look_stick.is_pressed():
		return look_stick.position.normalized()
	return Vector2.ZERO
