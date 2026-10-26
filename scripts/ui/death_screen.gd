class_name DeathScreen
extends CanvasLayer

## Экран смерти локального игрока: кто убил и через сколько возрождение.
## Без него смерть выглядела как зависание: оружие пропадало, управление
## переставало отвечать, и было непонятно, что произошло.

const TINT_COLOR := Color(0.35, 0.0, 0.0, 0.45)
const FADE_TIME := 0.25

var _root: Control
var _title: Label
var _killer: Label
var _timer: Label
var _respawn_left: float = 0.0


func _ready() -> void:
	layer = 5  # над HUD оружия, под меню паузы (UILayer, слой 10)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var tint := ColorRect.new()
	tint.color = TINT_COLOR
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tint)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_title = _make_label(box, 44)
	_killer = _make_label(box, 26)
	_timer = _make_label(box, 22)
	_title.text = "ВЫ УБИТЫ"
	_root.visible = false


func _make_label(parent: Control, font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	return label


## killer_name пустой — погиб сам (зона смерти, падение).
func show_death(killer_name: String, respawn_time: float) -> void:
	_killer.text = "Вас убил: %s" % killer_name if killer_name != "" else "Вы погибли"
	_respawn_left = respawn_time
	_update_timer()
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, FADE_TIME)


func hide_death() -> void:
	_root.visible = false


func is_shown() -> bool:
	return _root.visible


func get_killer_text() -> String:
	return _killer.text


func _process(delta: float) -> void:
	if not _root.visible:
		return
	_respawn_left = maxf(_respawn_left - delta, 0.0)
	_update_timer()


func _update_timer() -> void:
	_timer.text = "Возрождение через %d" % ceili(_respawn_left)
