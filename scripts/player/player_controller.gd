extends CharacterBody3D

const SPEED := 5.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.002
const RESPAWN_DELAY := 2.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var body_mesh: MeshInstance3D = $MeshInstance3D
@onready var left_arm: MeshInstance3D = $Head/LeftArm
@onready var right_arm: MeshInstance3D = $Head/RightArm

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var health: float = 100.0
var spawn_position: Vector3 = Vector3.ZERO
var is_dead: bool = false

var mobile_move_input: Vector2 = Vector2.ZERO
var mobile_look_input: Vector2 = Vector2.ZERO
var mobile_shoot_pressed: bool = false
var mobile_reload_triggered: bool = false
var mobile_interact_triggered: bool = false


func _ready() -> void:
	if is_multiplayer_authority():
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if body_mesh:
			body_mesh.visible = false
		if left_arm:
			left_arm.visible = true
		if right_arm:
			right_arm.visible = true
	else:
		camera.current = false
		if left_arm:
			left_arm.visible = false
		if right_arm:
			right_arm.visible = false


func setup_spawn(pos: Vector3) -> void:
	spawn_position = pos
	global_position = pos


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or is_dead:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, -PI / 2, PI / 2)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or is_dead:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := _get_input_vector()
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	move_and_slide()


func _get_input_vector() -> Vector2:
	if mobile_move_input != Vector2.ZERO:
		return mobile_move_input
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _on_mobile_input(action: String, value) -> void:
	if not is_multiplayer_authority() or is_dead:
		return
	match action:
		"mobile_move":
			mobile_move_input = value
		"mobile_look":
			mobile_look_input = value
			rotate_y(-value.x * MOUSE_SENSITIVITY * 8.0)
			head.rotate_x(-value.y * MOUSE_SENSITIVITY * 8.0)
			head.rotation.x = clamp(head.rotation.x, -PI / 2, PI / 2)
		"mobile_shoot":
			mobile_shoot_pressed = value
		"mobile_reload":
			mobile_reload_triggered = value
		"mobile_interact":
			mobile_interact_triggered = value


@rpc("any_peer", "reliable")
func take_damage(amount: float) -> void:
	if not is_multiplayer_authority() or is_dead:
		return
	health -= amount
	if health <= 0.0:
		die()


func die() -> void:
	_death.rpc()


@rpc("call_local", "reliable")
func _death() -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0
	velocity = Vector3.ZERO
	visible = false
	if is_multiplayer_authority():
		_respawn_after_delay()


func _respawn_after_delay() -> void:
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	_respawn.rpc()


@rpc("call_local", "reliable")
func _respawn() -> void:
	is_dead = false
	health = 100.0
	velocity = Vector3.ZERO
	global_position = spawn_position
	visible = true
	if is_multiplayer_authority():
		if body_mesh:
			body_mesh.visible = false
		if left_arm:
			left_arm.visible = true
		if right_arm:
			right_arm.visible = true
