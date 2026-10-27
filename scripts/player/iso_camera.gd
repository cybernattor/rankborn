class_name IsoCamera
extends Camera3D

## Камера сверху, как у Foxhole (docs/design.md, раздел 3): фиксированный угол без
## вращения — у всех игроков одинаковая картинка, «вверх по экрану» всегда −Z мира.
## Следует за игроком и сдвигается в сторону прицеливания: при прицеливании (ADS)
## сильнее — так видно дальше туда, куда смотришь, а не во все стороны сразу.
##
## Узел top_level: стоит в мире сам, а не крутится вместе с игроком.

## Наклон вниз от горизонта и расстояние до точки, на которую смотрим.
## Подбираются в прототипе (фаза 1.5 roadmap).
const PITCH_DEG := 55.0
const DISTANCE := 21.0
const CAMERA_FOV := 40.0
## Сдвиг к точке прицеливания: доля расстояния до неё и предел в метрах.
## По вертикали камера видит примерно ±8 м от центра: при большем сдвиге в прицеле
## свой солдат уходил за край экрана (было 13 м). При 6.5 м и дальности прицела
## стиком 15 м на экране остаются и солдат, и точка прицела.
const LOOK_AHEAD := 0.35
const LOOK_AHEAD_MAX := 6.0
const LOOK_AHEAD_ADS_MAX := 6.5
const FOLLOW_SPEED := 8.0

var target: Node3D
var _focus := Vector3.ZERO


func _ready() -> void:
	top_level = true
	fov = CAMERA_FOV
	rotation = Vector3(deg_to_rad(-PITCH_DEG), 0.0, 0.0)


## Сразу поставить камеру над игроком (спавн, респавн) — без проезда через карту.
func snap() -> void:
	if target:
		_focus = _desired_focus()
		_apply_focus()


func _process(delta: float) -> void:
	if not target or not current:
		return
	_focus = _focus.lerp(_desired_focus(), 1.0 - exp(-FOLLOW_SPEED * delta))
	_apply_focus()


func _desired_focus() -> Vector3:
	var focus := target.global_position
	if "aim_point" in target:
		var to_aim: Vector3 = (target.aim_point - focus) * Vector3(1, 0, 1)
		# Камера уходит вперёд по мере сведения прицела, а не скачком.
		# С мышью от бедра камера стоит на месте, как у Foxhole: иначе это петля —
		# курсор у солдата → прицел ближе → камера едет → мир под курсором сдвигается →
		# прицел снова меняется; прицел «застревал», проходя через солдата.
		var progress: float = target.aim_progress
		var hip_share := 0.0 if target.uses_mouse_aim() else LOOK_AHEAD
		var limit := lerpf(LOOK_AHEAD_MAX, LOOK_AHEAD_ADS_MAX, progress)
		var share := lerpf(hip_share, 1.0, progress)
		focus += (to_aim * share).limit_length(limit)
	return focus


func _apply_focus() -> void:
	global_position = _focus + global_basis.z * DISTANCE


## Точка на горизонтальной плоскости высоты plane_y под экранной точкой.
func screen_to_plane(screen_pos: Vector2, plane_y: float) -> Vector3:
	var origin := project_ray_origin(screen_pos)
	var normal := project_ray_normal(screen_pos)
	if absf(normal.y) < 0.0001:
		return origin
	return origin + normal * ((plane_y - origin.y) / normal.y)
