extends Control

## Меню паузы. В сетевой игре мир не останавливается: меню только блокирует
## ввод игрока (см. game_scene._on_pause_visibility_changed).
##
## «Продолжить» — сразу под заголовком, «Выйти в меню» — в самом низу через отступ
## и только со второго нажатия: рядом стоящие кнопки на планшете путали, и из матча
## выходили случайно.

const EXIT_TEXT := "Выйти в меню"
const EXIT_CONFIRM_TEXT := "Точно выйти? Нажми ещё раз"
## Сколько секунд ждём второго нажатия.
const EXIT_CONFIRM_TIME := 3.0

var _exit_armed: bool = false
var _exit_timer: SceneTreeTimer

@onready var resume_button: Button = %ResumeButton
@onready var exit_button: Button = %ExitMenuButton
@onready var aim_toggle_check: CheckBox = %AimToggleCheck
@onready var crouch_toggle_check: CheckBox = %CrouchToggleCheck
@onready var quality_option: OptionButton = %QualityOption
@onready var show_fps_check: CheckBox = %ShowFpsCheck


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(_on_resume)
	exit_button.pressed.connect(_on_exit_menu)
	quality_option.add_item("Авто", GameSettings.QUALITY_AUTO)
	for i in GameSettings.QUALITY_NAMES.size():
		quality_option.add_item(GameSettings.QUALITY_NAMES[i], i)
	GameSettings.changed.connect(_update_auto_label)
	_load_settings_into_ui()
	quality_option.item_selected.connect(_on_setting_changed.unbind(1))
	aim_toggle_check.toggled.connect(_on_setting_changed.unbind(1))
	crouch_toggle_check.toggled.connect(_on_setting_changed.unbind(1))
	show_fps_check.toggled.connect(_on_setting_changed.unbind(1))
	# На тач-экранах прицел и присед всегда переключаются нажатием.
	aim_toggle_check.visible = not GameSettings.is_touch_device()
	crouch_toggle_check.visible = not GameSettings.is_touch_device()


func toggle() -> void:
	if visible:
		_resume_game()
	else:
		_disarm_exit()
		visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_load_settings_into_ui()


func _resume_game() -> void:
	_disarm_exit()
	visible = false
	if not GameSettings.is_touch_device():
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN


func _load_settings_into_ui() -> void:
	aim_toggle_check.set_pressed_no_signal(GameSettings.aim_toggle)
	crouch_toggle_check.set_pressed_no_signal(GameSettings.crouch_toggle)
	show_fps_check.set_pressed_no_signal(GameSettings.show_fps)
	var choice := GameSettings.QUALITY_AUTO if GameSettings.is_auto_quality() else GameSettings.graphics_quality
	quality_option.select(quality_option.get_item_index(choice))
	_update_auto_label()


func _on_setting_changed() -> void:
	GameSettings.aim_toggle = aim_toggle_check.button_pressed
	GameSettings.crouch_toggle = crouch_toggle_check.button_pressed
	GameSettings.show_fps = show_fps_check.button_pressed
	GameSettings.set_quality_choice(quality_option.get_selected_id())
	GameSettings.save_settings()


func _on_resume() -> void:
	_resume_game()


func _on_exit_menu() -> void:
	if not _exit_armed:
		_exit_armed = true
		exit_button.text = EXIT_CONFIRM_TEXT
		exit_button.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		_exit_timer = get_tree().create_timer(EXIT_CONFIRM_TIME)
		var timer := _exit_timer
		timer.timeout.connect(func():
			if _exit_timer == timer:
				_disarm_exit()
		)
		return
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


# В пункте «Авто» видно, на каком уровне сейчас автонастройка.
func _update_auto_label() -> void:
	var index := quality_option.get_item_index(GameSettings.QUALITY_AUTO)
	quality_option.set_item_text(index, "Авто (%s)" % GameSettings.QUALITY_NAMES[GameSettings.get_quality()].to_lower())


func _disarm_exit() -> void:
	_exit_armed = false
	_exit_timer = null
	exit_button.text = EXIT_TEXT
	exit_button.remove_theme_color_override("font_color")
