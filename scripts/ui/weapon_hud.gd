extends CanvasLayer

## HUD оружия: прицел, патроны, индикатор перезарядки, scope, hit marker.
## Подключается к WeaponManager, а не напрямую к оружию.

@onready var crosshair: Control = $UILayer/Crosshair
@onready var cross_top: ColorRect = $UILayer/Crosshair/CrossTop
@onready var cross_bottom: ColorRect = $UILayer/Crosshair/CrossBottom
@onready var cross_left: ColorRect = $UILayer/Crosshair/CrossLeft
@onready var cross_right: ColorRect = $UILayer/Crosshair/CrossRight
@onready var dot: Panel = $UILayer/Crosshair/Dot
@onready var ammo_label: Label = $UILayer/BottomRight/AmmoLabel
@onready var reload_bar: ProgressBar = $UILayer/BottomRight/ReloadBar
@onready var scope_overlay: ColorRect = $UILayer/ScopeOverlay
@onready var scope_ring: Panel = $UILayer/ScopeRing
@onready var scope_dot: ColorRect = $UILayer/ScopeDot
@onready var scope_cross_v: ColorRect = $UILayer/ScopeCrossV
@onready var scope_cross_h: ColorRect = $UILayer/ScopeCrossH
@onready var hit_marker: Control = $UILayer/HitMarker

var _weapon_manager: WeaponManager
var _player: Node3D

# Crosshair spread
const BASE_GAP := 3.0
const ARM_LENGTH := 4.0
var _current_spread := 0.0
var _target_spread := 0.0
const SPREAD_SPEED := 16.0

# Hit marker
var _hit_marker_tween: Tween


func _ready() -> void:
	visible = false
	if reload_bar:
		reload_bar.visible = false
	if hit_marker:
		hit_marker.visible = false


func setup(weapon_mgr: WeaponManager) -> void:
	_weapon_manager = weapon_mgr
	visible = true
	_player = _find_player()

	# Подключаемся к текущему оружию
	_connect_weapon_signals()

	# Следим за сменой оружия
	_weapon_manager.weapon_changed.connect(_on_weapon_changed)


func _on_weapon_changed(_weapon: WeaponBase) -> void:
	_connect_weapon_signals()


func _connect_weapon_signals() -> void:
	var weapon := _get_weapon()
	if not weapon:
		return
	# Отключаем старые, подключаем новые
	if weapon.fired.is_connected(_on_fired):
		return  # уже подключены
	weapon.fired.connect(_on_fired)
	weapon.reloaded.connect(_on_reloaded)
	weapon.hit_confirmed.connect(_on_hit_confirmed)


func _get_weapon() -> WeaponBase:
	if _weapon_manager:
		return _weapon_manager.get_current_weapon()
	return null


func _process(delta: float) -> void:
	var weapon := _get_weapon()
	if not weapon:
		return

	_update_ammo()

	if weapon.is_reloading and reload_bar:
		reload_bar.visible = true
		var elapsed: float = weapon.reload_time - weapon.reload_timer.time_left
		reload_bar.value = (elapsed / weapon.reload_time) * 100.0
	elif reload_bar:
		reload_bar.visible = false

	# Scope overlay
	var aiming := false
	if _player and "is_aiming" in _player:
		aiming = _player.is_aiming
	_set_scope_visible(aiming)

	# Динамический прицел
	_update_crosshair_spread(delta)


func _update_crosshair_spread(delta: float) -> void:
	if not _player or not cross_top:
		return

	_target_spread = _calculate_spread()

	_current_spread = lerp(_current_spread, _target_spread, SPREAD_SPEED * delta)
	if abs(_current_spread - _target_spread) < 0.01:
		_current_spread = _target_spread

	var gap := BASE_GAP + _current_spread

	cross_top.offset_top = -gap - ARM_LENGTH
	cross_top.offset_bottom = -gap

	cross_bottom.offset_top = gap
	cross_bottom.offset_bottom = gap + ARM_LENGTH

	cross_left.offset_left = -gap - ARM_LENGTH
	cross_left.offset_right = -gap

	cross_right.offset_left = gap
	cross_right.offset_right = gap + ARM_LENGTH


func _calculate_spread() -> float:
	if not _player:
		return 0.0

	var weapon := _get_weapon()
	if not weapon:
		return 0.0

	if not weapon is Rifle:
		return 0.0
	var camera: Camera3D = _player.get_node("Head/Camera3D")
	var half_height := get_viewport().get_visible_rect().size.y * 0.5
	var focal_length := half_height / tan(deg_to_rad(camera.fov) * 0.5)
	return maxf(0.0, tan(weapon.get_spread_angle()) * focal_length - BASE_GAP)


func _set_scope_visible(show_scope: bool) -> void:
	if crosshair:
		crosshair.visible = not show_scope
	if scope_overlay:
		scope_overlay.visible = show_scope
	if scope_ring:
		scope_ring.visible = show_scope
	if scope_dot:
		scope_dot.visible = show_scope
	if scope_cross_v:
		scope_cross_v.visible = show_scope
	if scope_cross_h:
		scope_cross_h.visible = show_scope


func _update_ammo() -> void:
	var weapon := _get_weapon()
	if not weapon or not ammo_label:
		return
	ammo_label.text = "%d / %d" % [weapon.current_ammo, weapon.magazine_size]


func _on_fired() -> void:
	if ammo_label:
		ammo_label.modulate = Color(1, 0.8, 0.3)
		var tw := ammo_label.create_tween()
		tw.tween_property(ammo_label, "modulate", Color.WHITE, 0.15)


func _on_reloaded() -> void:
	if ammo_label:
		ammo_label.modulate = Color(0.3, 1, 0.3)
		var tw := ammo_label.create_tween()
		tw.tween_property(ammo_label, "modulate", Color.WHITE, 0.3)


func _on_hit_confirmed(is_headshot: bool, is_kill: bool) -> void:
	if not hit_marker:
		return
	if _hit_marker_tween and _hit_marker_tween.is_valid():
		_hit_marker_tween.kill()

	var color: Color
	var duration: float

	if is_kill:
		color = Color(1.0, 0.2, 0.2, 1.0)
		duration = 0.25
	elif is_headshot:
		color = Color(1.0, 0.2, 0.2, 0.9)
		duration = 0.2
	else:
		color = Color(1.0, 1.0, 1.0, 0.9)
		duration = 0.15

	for child in hit_marker.get_children():
		if child is ColorRect:
			child.color = color

	hit_marker.visible = true
	hit_marker.modulate = Color.WHITE

	_hit_marker_tween = hit_marker.create_tween()
	_hit_marker_tween.tween_interval(duration)
	_hit_marker_tween.tween_property(hit_marker, "modulate:a", 0.0, 0.05)
	_hit_marker_tween.tween_callback(func(): hit_marker.visible = false)


func _find_player() -> Node3D:
	var node: Node = self
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null
