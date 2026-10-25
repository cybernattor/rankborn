extends Node

## Пользовательские настройки управления. Хранятся в user://settings.cfg.

signal changed

const SETTINGS_PATH := "user://settings.cfg"

## Радиан поворота на один физический пиксель мыши (screen_relative).
var mouse_sensitivity: float = 0.002
## Радиан поворота на один пиксель свайпа по экрану.
var touch_sensitivity: float = 0.004
## Скорость поворота правым стиком геймпада, рад/с при полном отклонении.
var gamepad_look_speed: float = 3.0
var invert_y: bool = false
## true — прицеливание переключается нажатием, false — пока кнопка зажата.
var aim_toggle: bool = false
## true — присед переключается нажатием, false — пока кнопка зажата.
var crouch_toggle: bool = false
## Ник в лобби и в игре (пустой — «Игрок_NNNN»).
var player_name: String = ""


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	touch_sensitivity = cfg.get_value("controls", "touch_sensitivity", touch_sensitivity)
	gamepad_look_speed = cfg.get_value("controls", "gamepad_look_speed", gamepad_look_speed)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	aim_toggle = cfg.get_value("controls", "aim_toggle", aim_toggle)
	crouch_toggle = cfg.get_value("controls", "crouch_toggle", crouch_toggle)
	player_name = cfg.get_value("profile", "player_name", player_name)
	changed.emit()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "touch_sensitivity", touch_sensitivity)
	cfg.set_value("controls", "gamepad_look_speed", gamepad_look_speed)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "aim_toggle", aim_toggle)
	cfg.set_value("controls", "crouch_toggle", crouch_toggle)
	cfg.set_value("profile", "player_name", player_name)
	cfg.save(SETTINGS_PATH)
	changed.emit()


## Включить сенсорный режим на ПК (тесты, отладка без телефона). Не сохраняется.
var force_touch: bool = false


## Мобильный сенсорный интерфейс нужен на телефонах/планшетах (нативно и в вебе).
func is_touch_device() -> bool:
	return force_touch or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


# На тач-экране удерживать кнопку и одновременно целиться свайпом неудобно,
# поэтому там прицел и присед всегда переключаются нажатием.
func uses_aim_toggle() -> bool:
	return aim_toggle or is_touch_device()


func uses_crouch_toggle() -> bool:
	return crouch_toggle or is_touch_device()
