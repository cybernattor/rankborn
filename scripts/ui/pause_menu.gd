extends Control

@onready var resume_button: Button = %ResumeButton
@onready var exit_button: Button = %ExitMenuButton


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(_on_resume)
	exit_button.pressed.connect(_on_exit_menu)


func toggle() -> void:
	visible = not visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = true
	else:
		_resume_game()


func _resume_game() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false


func _on_resume() -> void:
	_resume_game()


func _on_exit_menu() -> void:
	get_tree().paused = false
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
