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

## Качество графики. Замеры на планшетах: взгляд в землю стоил втрое дороже взгляда
## в небо — почти всё время кадра уходит на пиксели земли (тени, MSAA, разрешение).
enum Quality { LOW, MEDIUM, HIGH }
const QUALITY_NAMES := ["Низкая", "Средняя", "Высокая"]
## scale — доля разрешения 3D; splits — каскады теней солнца;
## lights — вспышки света от выстрелов и попаданий (на мобильном рендере каждый
## источник света пересчитывается для всей земли — это один большой меш).
const QUALITY_PRESETS := {
	Quality.LOW: {"scale": 0.6, "msaa": Viewport.MSAA_DISABLED, "shadows": false,
			"soft": RenderingServer.SHADOW_QUALITY_HARD, "splits": 2, "lights": false},
	Quality.MEDIUM: {"scale": 0.75, "msaa": Viewport.MSAA_2X, "shadows": true,
			"soft": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "splits": 2, "lights": false},
	Quality.HIGH: {"scale": 1.0, "msaa": Viewport.MSAA_2X, "shadows": true,
			"soft": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "splits": 4, "lights": true},
}
## Выбор игрока: пресет или QUALITY_AUTO (по умолчанию).
const QUALITY_AUTO := 3
var graphics_quality: int = QUALITY_AUTO
## Уровень, до которого дошла автонастройка (AutoQuality); с него начинается следующий матч.
var auto_quality_level: int = -1


func _ready() -> void:
	load_settings()
	_apply_touch_input_map()


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
	graphics_quality = cfg.get_value("graphics", "quality", graphics_quality)
	auto_quality_level = cfg.get_value("graphics", "auto_level", auto_quality_level)
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
	cfg.set_value("graphics", "quality", graphics_quality)
	cfg.set_value("graphics", "auto_level", auto_quality_level)
	cfg.save(SETTINGS_PATH)
	changed.emit()


## Включить сенсорный режим на ПК (тесты, отладка без телефона). Не сохраняется.
var force_touch: bool = false:
	set(value):
		force_touch = value
		_apply_touch_input_map()

## Кнопки мыши, снятые с игровых действий на тач-экране (действие → события).
var _removed_mouse_events: Dictionary = {}


## Мобильный сенсорный интерфейс нужен на телефонах/планшетах (нативно и в вебе).
func is_touch_device() -> bool:
	return force_touch or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


# На тач-экране удерживать кнопку и одновременно целиться свайпом неудобно,
# поэтому там прицел и присед всегда переключаются нажатием.
func uses_aim_toggle() -> bool:
	return aim_toggle or is_touch_device()


func uses_crouch_toggle() -> bool:
	return crouch_toggle or is_touch_device()


# Касания эмулируют мышь (input_devices/pointing/emulate_mouse_from_touch): без этого
# на Android не фокусируются поля ввода и не тянутся слайдеры. Но тогда любое касание —
# ещё и клик левой кнопкой, то есть выстрел. Поэтому на тач-экране снимаем кнопки мыши
# с игровых действий; стрельбу и прицел там нажимает MobileUI.
func _apply_touch_input_map() -> void:
	if is_touch_device():
		for action in InputMap.get_actions():
			if String(action).begins_with("ui_"):
				continue
			for event in InputMap.action_get_events(action):
				if event is InputEventMouseButton:
					InputMap.action_erase_event(action, event)
					_removed_mouse_events.get_or_add(action, []).append(event)
	else:
		for action in _removed_mouse_events:
			for event in _removed_mouse_events[action]:
				InputMap.action_add_event(action, event)
		_removed_mouse_events.clear()


## Действующий пресет: выбранный игроком или текущий уровень автонастройки.
func get_quality() -> int:
	if graphics_quality in QUALITY_PRESETS:
		return graphics_quality
	if auto_quality_level in QUALITY_PRESETS:
		return auto_quality_level
	return default_quality()


func is_auto_quality() -> bool:
	return not graphics_quality in QUALITY_PRESETS


## Выбор в меню. Повторное включение «Авто» начинает подбор заново, с уровня по умолчанию:
## иначе один неудачный замер навсегда оставил бы низкую графику.
func set_quality_choice(choice: int) -> void:
	if choice == QUALITY_AUTO and not is_auto_quality():
		auto_quality_level = default_quality()
	graphics_quality = choice


## Автонастройка: на ступень ниже. false — ниже некуда.
func lower_auto_quality() -> bool:
	var level := get_quality()
	if level <= Quality.LOW:
		return false
	auto_quality_level = level - 1
	save_settings()
	return true


func default_quality() -> int:
	return Quality.MEDIUM if is_touch_device() else Quality.HIGH


## Вспышки света от выстрелов и попаданий.
func dynamic_lights_enabled() -> bool:
	return QUALITY_PRESETS[get_quality()].lights


## Применить пресет к окну и солнцу сцены (вызывает game_scene при старте и смене настроек).
func apply_graphics(viewport: Viewport, sun: DirectionalLight3D) -> void:
	var preset: Dictionary = QUALITY_PRESETS[get_quality()]
	viewport.scaling_3d_scale = preset.scale
	viewport.msaa_3d = preset.msaa
	RenderingServer.directional_soft_shadow_filter_set_quality(preset.soft)
	sun.shadow_enabled = preset.shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if preset.splits == 2 \
			else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
