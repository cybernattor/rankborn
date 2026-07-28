extends CanvasLayer

@onready var crosshair: Control = $Crosshair
@onready var ammo_label: Label = $BottomRight/AmmoLabel
@onready var reload_bar: ProgressBar = $BottomRight/ReloadBar

var _weapon: Node3D


func _ready() -> void:
	visible = false
	if reload_bar:
		reload_bar.visible = false


func setup(weapon: Node3D) -> void:
	_weapon = weapon
	visible = true
	_update_ammo()
	_weapon.fired.connect(_on_fired)
	_weapon.reloaded.connect(_on_reloaded)


func _process(_delta: float) -> void:
	if not _weapon:
		return
	_update_ammo()
	if _weapon.is_reloading and reload_bar:
		reload_bar.visible = true
		var elapsed: float = _weapon.reload_time - _weapon.reload_timer.time_left
		reload_bar.value = (elapsed / _weapon.reload_time) * 100.0
	elif reload_bar:
		reload_bar.visible = false


func _update_ammo() -> void:
	if not _weapon or not ammo_label:
		return
	ammo_label.text = "%d / %d" % [_weapon.current_ammo, _weapon.magazine_size]


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
