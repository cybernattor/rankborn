extends Control

## Меню паузы. В сетевой игре мир не останавливается: меню только блокирует
## ввод игрока (см. game_scene._on_pause_visibility_changed).

@onready var resume_button: Button = %ResumeButton
@onready var exit_button: Button = %ExitMenuButton
@onready var mouse_sens_slider: HSlider = %MouseSensSlider
@onready var touch_sens_slider: HSlider = %TouchSensSlider
@onready var invert_y_check: CheckBox = %InvertYCheck
@onready var aim_toggle_check: CheckBox = %AimToggleCheck
@onready var crouch_toggle_check: CheckBox = %CrouchToggleCheck


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(_on_resume)
	exit_button.pressed.connect(_on_exit_menu)
	_load_settings_into_ui()
	mouse_sens_slider.value_changed.connect(_on_setting_changed.unbind(1))
	touch_sens_slider.value_changed.connect(_on_setting_changed.unbind(1))
	invert_y_check.toggled.connect(_on_setting_changed.unbind(1))
	aim_toggle_check.toggled.connect(_on_setting_changed.unbind(1))
	crouch_toggle_check.toggled.connect(_on_setting_changed.unbind(1))
	# На тач-экранах прицел и присед всегда переключаются нажатием.
	aim_toggle_check.visible = not GameSettings.is_touch_device()
	crouch_toggle_check.visible = not GameSettings.is_touch_device()


func toggle() -> void:
	if visible:
		_resume_game()
	else:
		visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_load_settings_into_ui()


func _resume_game() -> void:
	visible = false
	if not GameSettings.is_touch_device():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _load_settings_into_ui() -> void:
	mouse_sens_slider.set_value_no_signal(GameSettings.mouse_sensitivity)
	touch_sens_slider.set_value_no_signal(GameSettings.touch_sensitivity)
	invert_y_check.set_pressed_no_signal(GameSettings.invert_y)
	aim_toggle_check.set_pressed_no_signal(GameSettings.aim_toggle)
	crouch_toggle_check.set_pressed_no_signal(GameSettings.crouch_toggle)


func _on_setting_changed() -> void:
	GameSettings.mouse_sensitivity = mouse_sens_slider.value
	GameSettings.touch_sensitivity = touch_sens_slider.value
	GameSettings.invert_y = invert_y_check.button_pressed
	GameSettings.aim_toggle = aim_toggle_check.button_pressed
	GameSettings.crouch_toggle = crouch_toggle_check.button_pressed
	GameSettings.save_settings()


func _on_resume() -> void:
	_resume_game()


func _on_exit_menu() -> void:
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
