extends Node3D
class_name WeaponBase

## Базовый класс для всех видов оружия.
## Определяет общий интерфейс и сигналы для системы оружия.

signal fired
signal reloaded
signal hit_confirmed(is_headshot: bool, is_kill: bool)

## Основные параметры оружия
@export var damage: float = 25.0
@export var fire_rate: float = 0.15
@export var magazine_size: int = 30
@export var reload_time: float = 2.0
@export var headshot_multiplier: float = 2.0

## Текущее состояние
var current_ammo: int
var can_fire: bool = true
var is_reloading: bool = false
var is_firing: bool = false

## Виртуальные методы — переопределяются в наследниках
func shoot() -> void:
	pass

func reload() -> void:
	pass

func can_shoot() -> bool:
	return can_fire and not is_reloading and current_ammo > 0

func get_current_ammo() -> int:
	return current_ammo

func get_max_ammo() -> int:
	return magazine_size

## Вызывается менеджером при экипировке/снятии оружия
func on_equip() -> void:
	visible = true

func on_unequip() -> void:
	visible = false

func _ready() -> void:
	current_ammo = magazine_size
