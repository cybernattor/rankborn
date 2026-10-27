class_name AimCone
extends MeshInstance3D

## Конус разброса на земле, как у Foxhole: видно, куда может уйти пуля, и как он
## сужается, пока сводишь прицел. Только у локального игрока. Рисуется поверх всего
## (без теста глубины) — на склоне или за укрытием конус не должен пропадать.

const FILL_COLOR := Color(1.0, 1.0, 1.0, 0.12)
const EDGE_COLOR := Color(1.0, 1.0, 1.0, 0.55)
## Полностью сведённый прицел — край конуса становится жёлтым.
const AIMED_COLOR := Color(1.0, 0.85, 0.3, 0.8)
## Начинается чуть впереди персонажа, а не из его центра, и висит над землёй.
const START_OFFSET := 0.6
const GROUND_LIFT := 0.12

var player: Node3D
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material


func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	if not player or not player.can_control():
		return
	var weapon: Node = player.weapon_manager.get_current_weapon()
	if not weapon or not weapon.has_method("get_spread_angle"):
		return
	var direction: Vector3 = player.get_aim_direction()
	# Края конуса считаем от самого солдата, как летит пуля: на дальности прицела
	# они ровно там, где пуля ложится на землю при крайнем отклонении.
	var origin: Vector3 = player.global_position
	var length: float = maxf(((player.aim_point - origin) * Vector3(1, 0, 1)).length(), 1.0)
	var spread: float = weapon.get_spread_angle()
	var left := _on_ground(origin + direction.rotated(Vector3.UP, spread) * length)
	var right := _on_ground(origin + direction.rotated(Vector3.UP, -spread) * length)
	var start := _on_ground(origin + direction * START_OFFSET)
	var edge := EDGE_COLOR.lerp(AIMED_COLOR, player.aim_progress)

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [start, left, right]:
		_mesh.surface_set_color(FILL_COLOR)
		_mesh.surface_add_vertex(point)
	_mesh.surface_end()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for point in [start, left, start, right, left, right]:
		_mesh.surface_set_color(edge)
		_mesh.surface_add_vertex(point)
	_mesh.surface_end()


func _on_ground(point: Vector3) -> Vector3:
	point.y = player.ground_height_at(point) + GROUND_LIFT
	return point
