extends Node
class_name State

## Базовый класс состояния для конечного автомата (FSM).
## Каждое состояние — отдельный узел-потомок StateMachine.

signal transitioned(target_state_name: String, msg: Dictionary)

## Ссылка на владельца (CharacterBody3D). Устанавливается StateMachine при входе.
var player: CharacterBody3D


func enter(_msg: Dictionary = {}) -> void:
	pass


func exit() -> void:
	pass


func update(_delta: float) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func handle_input(_event: InputEvent) -> void:
	pass
