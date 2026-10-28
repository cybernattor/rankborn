class_name KillFeed
extends CanvasLayer

## Лента убийств в правом верхнем углу: «убийца ▸ жертва». Подписана на сигнал режима,
## который приходит на каждую машину (хост рассылает смерть всем), поэтому лента у всех одна.

const MAX_ENTRIES := 5
const ENTRY_LIFETIME := 6.0
const FADE_TIME := 0.6
const MARGIN := 16

var _list: VBoxContainer


func _ready() -> void:
	layer = 4
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.alignment = BoxContainer.ALIGNMENT_BEGIN
	_list.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, MARGIN)
	_list.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_list)


## killer_name пустой — погиб сам (зона смерти, падение).
func add_entry(killer_name: String, victim_name: String) -> void:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.text = "%s ▸ %s" % [killer_name, victim_name] if killer_name != "" else "%s погиб" % victim_name
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	_list.add_child(label)
	while _list.get_child_count() > MAX_ENTRIES:
		_list.get_child(0).queue_free()
		_list.remove_child(_list.get_child(0))
	var tween := label.create_tween()
	tween.tween_interval(ENTRY_LIFETIME)
	tween.tween_property(label, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(label.queue_free)
