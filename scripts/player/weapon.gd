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
@onready var reload_timer: Timer = $ReloadTimer
var rifle_mesh: MeshInstance3D


func _ready() -> void:
	_build_lowpoly_rifle()
	current_ammo = magazine_size
	reload_timer.wait_time = reload_time
	reload_timer.one_shot = true
	reload_timer.timeout.connect(_on_reload_finished)
	raycast.enabled = true
	raycast.collision_mask = 1 | 2


func _build_lowpoly_rifle() -> void:
	rifle_mesh = MeshInstance3D.new()
	rifle_mesh.mesh = MeshUtils.make_rifle()
	rifle_mesh.set_surface_override_material(0, MeshUtils.flat_material(Color(0.15, 0.15, 0.18)))
	rifle_mesh.position = Vector3(0, 0, -0.25)
	add_child(rifle_mesh)


func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var player := _get_player()
	if player and player.get("is_dead"):
		return
	if Input.is_action_pressed("shoot") and can_fire and not is_reloading:
		shoot()
	if Input.is_action_just_pressed("reload") and not is_reloading and current_ammo < magazine_size:
		reload()


func shoot() -> void:
	if current_ammo <= 0:
		return
	current_ammo -= 1
	can_fire = false
	_shoot_effects.rpc()
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
