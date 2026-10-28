class_name DamageHud
extends CanvasLayer

## Обратная связь о собственном здоровье локального игрока: полоска, красная вспышка
## при уроне и дуга в сторону стрелка. Без неё не видно, что в тебя попали и откуда.
## Старая DamageScreenEffects не подошла: её замедление времени (Engine.time_scale)
## в сетевой игре растягивало бы время только у одной машины.

const BAR_POSITION := Vector2(16, 72)
const BAR_SIZE := Vector2(200, 14)
const BAR_BACK := Color(0, 0, 0, 0.55)
const BAR_FULL := Color(0.45, 0.9, 0.45)
const BAR_LOW := Color(0.95, 0.25, 0.2)
## Ниже этой доли полоска краснеет.
const LOW_FRACTION := 0.4

const FLASH_COLOR := Color(0.9, 0.05, 0.05)
const FLASH_TIME := 0.35
## Вспышка тем сильнее, чем больше урон (доля от максимума), но не глуше этих границ.
const FLASH_MIN_ALPHA := 0.18
const FLASH_MAX_ALPHA := 0.5

const ARC_TIME := 0.9
const ARC_RADIUS_PX := 90.0
const ARC_HALF_ANGLE := 0.45
const ARC_WIDTH := 8.0

var _player: CharacterBody3D
var _health: HealthComponent
var _bar_fill: ColorRect
var _flash: ColorRect
var _flash_tween: Tween
var _arc_layer: Control
## Направления на стрелков в мире (горизонтальные, единичные) и сколько им осталось жить.
var _arcs: Array[Dictionary] = []


func _ready() -> void:
	layer = 4  # над HUD оружия, под экраном смерти (5) и меню (10)
	_flash = ColorRect.new()
	_flash.color = FLASH_COLOR
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	add_child(_flash)

	_arc_layer = Control.new()
	_arc_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arc_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arc_layer.draw.connect(_draw_arcs)
	add_child(_arc_layer)

	var back := ColorRect.new()
	back.color = BAR_BACK
	back.position = BAR_POSITION
	back.size = BAR_SIZE
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_bar_fill = ColorRect.new()
	_bar_fill.position = Vector2(2, 2)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(_bar_fill)


func setup(player: CharacterBody3D, health: HealthComponent) -> void:
	_player = player
	_health = health
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_damaged)
	_on_health_changed(health.current_health)


func _on_health_changed(value: float) -> void:
	var fraction := clampf(value / _health.max_health, 0.0, 1.0)
	_bar_fill.size = Vector2((BAR_SIZE.x - 4.0) * fraction, BAR_SIZE.y - 4.0)
	_bar_fill.color = BAR_LOW if fraction <= LOW_FRACTION else BAR_FULL


func _on_damaged(amount: float, attacker_id: int) -> void:
	var strength := clampf(amount / _health.max_health, 0.0, 1.0)
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash.modulate.a = lerpf(FLASH_MIN_ALPHA, FLASH_MAX_ALPHA, strength)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, FLASH_TIME)

	var dir := _direction_to(attacker_id)
	if dir != Vector3.ZERO:
		_arcs.append({"dir": dir, "left": ARC_TIME})


## Горизонтальное направление на стрелка; нулевое — стрелка нет (зона смерти, вышел).
## Позиция стрелка может быть устаревшей, если он скрыт туманом войны, — для дуги этого хватает.
func _direction_to(attacker_id: int) -> Vector3:
	if attacker_id <= 0 or attacker_id == _player.get_multiplayer_authority():
		return Vector3.ZERO
	var attacker := _player.get_parent().get_node_or_null(str(attacker_id)) as Node3D
	if attacker == null:
		return Vector3.ZERO
	var delta := attacker.global_position - _player.global_position
	delta.y = 0.0
	return delta.normalized() if delta.length_squared() > 0.01 else Vector3.ZERO


func _process(delta: float) -> void:
	if _arcs.is_empty():
		return
	for arc in _arcs:
		arc.left -= delta
	_arcs = _arcs.filter(func(a: Dictionary) -> bool: return a.left > 0.0)
	_arc_layer.queue_redraw()


func _draw_arcs() -> void:
	var camera := _player.camera as Camera3D
	if camera == null or not camera.current:
		return
	var origin := camera.unproject_position(_player.global_position + Vector3.UP)
	for arc in _arcs:
		# Дугу строим по экранному направлению: камера под углом, мировой угол не годится.
		var world_dir: Vector3 = arc.dir
		var on_screen := camera.unproject_position(_player.global_position + Vector3.UP + world_dir) - origin
		if on_screen.length_squared() < 0.0001:
			continue
		var angle := on_screen.angle()
		var alpha: float = clampf(arc.left / ARC_TIME, 0.0, 1.0)
		_arc_layer.draw_arc(origin, ARC_RADIUS_PX, angle - ARC_HALF_ANGLE, angle + ARC_HALF_ANGLE,
				16, Color(1.0, 0.15, 0.1, alpha), ARC_WIDTH, true)
