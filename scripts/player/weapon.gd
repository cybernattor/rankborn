extends Node3D

signal fired
signal reloaded

@export var damage: float = 25.0
@export var fire_rate: float = 0.15
@export var magazine_size: int = 30
@export var reload_time: float = 2.0

var current_ammo: int
var can_fire: bool = true
var is_reloading: bool = false

@onready var raycast: RayCast3D = $RayCast3D
@onready var muzzle_flash: GPUParticles3D = $MuzzleFlash
@onready var muzzle_light: OmniLight3D = $MuzzleLight
@onready var reload_timer: Timer = $ReloadTimer
var rifle_mesh: MeshInstance3D

var _base_transform: Transform3D
var _recoil_recovery_speed := 12.0


func _ready() -> void:
	_build_lowpoly_rifle()
	current_ammo = magazine_size
	reload_timer.wait_time = reload_time
	reload_timer.one_shot = true
	reload_timer.timeout.connect(_on_reload_finished)
	raycast.enabled = true
	raycast.collision_mask = 1 | 2
	muzzle_light.light_energy = 0.0
	_base_transform = transform


func _build_lowpoly_rifle() -> void:
	rifle_mesh = MeshInstance3D.new()
	rifle_mesh.mesh = MeshUtils.make_rifle()
	rifle_mesh.set_surface_override_material(0, MeshUtils.flat_material(Color(0.15, 0.15, 0.18)))
	rifle_mesh.position = Vector3(0, 0, -0.25)
	add_child(rifle_mesh)


func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var player := _get_player()
	if player and player.get("is_dead"):
		return

	var shoot_pressed := Input.is_action_pressed("shoot")
	if player and player.get("mobile_shoot_pressed"):
		shoot_pressed = true
	if shoot_pressed and can_fire and not is_reloading:
		shoot()

	var reload_pressed := Input.is_action_just_pressed("reload")
	if player and player.get("mobile_reload_triggered"):
		reload_pressed = true
		player.mobile_reload_triggered = false
	if reload_pressed and not is_reloading and current_ammo < magazine_size:
		reload()

	# Smooth recoil recovery
	transform = transform.interpolate_with(_base_transform, _recoil_recovery_speed * delta)


func shoot() -> void:
	if current_ammo <= 0:
		SFXManager.play_empty()
		return
	current_ammo -= 1
	can_fire = false
	SFXManager.play_shoot()
	_shoot_effects.rpc()
	# Recoil kick
	_base_transform = transform
	translate(Vector3(0, 0, 0.06))
	rotate_x(-0.02)
	# View recoil — pull aim up
	var player := _get_player()
	if player and player.has_method("apply_recoil"):
		player.apply_recoil(randf_range(0.015, 0.03))
	# Muzzle light flash
	muzzle_light.light_energy = 2.5
	get_tree().create_timer(0.06).timeout.connect(func():
		muzzle_light.light_energy = 0.0
	)
	if raycast.is_colliding():
		var collider := raycast.get_collider()
		if collider and collider.has_method("take_damage"):
			collider.take_damage.rpc_id(collider.get_multiplayer_authority(), damage)
	fired.emit()
	await get_tree().create_timer(fire_rate).timeout
	can_fire = true


func reload() -> void:
	is_reloading = true
	reload_timer.start()


func _on_reload_finished() -> void:
	current_ammo = magazine_size
	is_reloading = false
	reloaded.emit()


@rpc("call_local", "reliable")
func _shoot_effects() -> void:
	if muzzle_flash:
		muzzle_flash.restart()


func _get_player() -> Node:
	var node: Node = self
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null
