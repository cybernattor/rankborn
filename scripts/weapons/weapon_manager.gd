extends Node
class_name WeaponManager

## Менеджер оружия игрока.
## Ссылается на узлы оружия через @export NodePath (оружие остаётся под камерой).

signal weapon_changed(weapon: WeaponBase)

## Пути к узлам оружия в сцене (заполняется в редакторе).
@export var weapon_slots: Array[NodePath] = []

## Индекс текущего оружия
var current_index: int = 0

## Список всего оружия
var weapons: Array[WeaponBase] = []


func _ready() -> void:
	# Разрешаем NodePath → WeaponBase
	for path in weapon_slots:
		var node := get_node_or_null(path)
		if node and node is WeaponBase:
			weapons.append(node)
			node.visible = false  # скрываем всё до выбора

	# Показываем первое оружие
	if weapons.size() > 0:
		_select_weapon(0)


## Вернуть текущее оружие (или null)
func get_current_weapon() -> WeaponBase:
	if current_index >= 0 and current_index < weapons.size():
		return weapons[current_index]
	return null


## Переключиться на следующее оружие
func next_weapon() -> void:
	if weapons.size() <= 1:
		return
	var new_index := (current_index + 1) % weapons.size()
	_select_weapon(new_index)


## Переключиться на предыдущее оружие
func prev_weapon() -> void:
	if weapons.size() <= 1:
		return
	var new_index := (current_index - 1 + weapons.size()) % weapons.size()
	_select_weapon(new_index)


## Выстрел из текущего оружия
func shoot() -> void:
	var weapon := get_current_weapon()
	if weapon:
		weapon.shoot()


## Перезарядка текущего оружия
func reload() -> void:
	var weapon := get_current_weapon()
	if weapon:
		weapon.reload()


func can_shoot() -> bool:
	var weapon := get_current_weapon()
	return weapon != null and weapon.can_shoot()


func is_reloading() -> bool:
	var weapon := get_current_weapon()
	return weapon != null and weapon.is_reloading


func _select_weapon(index: int) -> void:
	var current := get_current_weapon()
	if current:
		current.on_unequip()

	current_index = index
	var next := get_current_weapon()
	if next:
		next.on_equip()
		weapon_changed.emit(next)
