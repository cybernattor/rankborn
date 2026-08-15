extends Node
class_name StateMachine

## Конечный автомат (FSM).
## Управляет состояниями-потомками, переключает по сигналу State.transitioned.

@export var initial_state: State

var current_state: State
var _states: Dictionary = {}  # name → State


func _ready() -> void:
	var owner_player: CharacterBody3D = get_parent() as CharacterBody3D

	for child in get_children():
		if child is State:
			_states[child.name] = child
			child.player = owner_player
			child.transitioned.connect(_on_child_transitioned)

	if not initial_state:
		for child in get_children():
			if child is State:
				initial_state = child
				break

	if initial_state:
		change_state(initial_state.name)


func change_state(target_name: String, msg: Dictionary = {}) -> void:
	var target: State = _states.get(target_name)
	if not target:
		push_warning("StateMachine: состояние '%s' не найдено" % target_name)
		return

	if current_state:
		current_state.exit()

	current_state = target
	current_state.enter(msg)


func _on_child_transitioned(target_name: String, msg: Dictionary = {}) -> void:
	change_state(target_name, msg)


func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)


func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)


func handle_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)
