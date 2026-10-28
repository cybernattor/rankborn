class_name VisibilityManager
extends Node

## Туман войны (docs/design.md, раздел 3). Камера сверху показывает всё вокруг,
## поэтому без ограничения видимости укрытия бессмысленны.
##
## Решает хост: он получает позиции всех игроков, считает, кто кого видит (дальность +
## прямая видимость, укрытия и рельеф её перекрывают), и рассылает каждому пиру список
## видимых ему игроков. Пир по списку:
## - прячет остальных (Player.fog_hidden: не рисуются и не ловят пули);
## - отправляет свою позицию только тем, кто его видит (видимость своего
##   MultiplayerSynchronizer). Хосту — всегда, иначе он не сможет считать.
## Так скрытого противника нет и в сетевом трафике: «волхак» из клиента не вытащить.
## Сам хост видит всех — это предел P2P, его снимет dedicated server (roadmap, фаза 5).
##
## Видимость симметрична (нет конуса обзора): один список отвечает и на «кого вижу я»,
## и на «кто видит меня». Пир сообщает о ней сигналом seen_changed (индикатор в HUD).
##
## Шаги тоже решает хост: он знает позиции всех, в том числе скрытых туманом, и шлёт
## «шаг здесь» каждому, кто в радиусе слышимости — из-за стены слышно, что кто-то идёт.
## Пригнувшись или с прицелом (медленнее QUIET_SPEED) идут бесшумно — ради этого и
## нужен присед.

signal seen_changed(seen: bool)

## Дальность обзора, м. Камера сверху показывает примерно ±20 м — дальше видно в прицеле.
const VIEW_RANGE := 32.0
const UPDATE_INTERVAL := 0.15
## Повтор списка без изменений: пир мог ещё грузить сцену и пропустить прошлую рассылку.
const RESEND_INTERVAL := 1.0
## Доли роста: откуда смотрим (глаза) и куда (голова, пояс) — присевшего за мешками
## не видно, стоящего видно поверх них.
const EYE_SHARE := 0.85
const TARGET_SHARES := [0.85, 0.5]
## Слой мира: земля и укрытия. Игроки (слой 2) взгляд не перекрывают.
const BLOCKING_MASK := 1
## Шаги: слышно в этом радиусе; тише этой скорости (присед 2.5, прицел 2.2 м/с) — беззвучно.
const HEARING_RANGE := 22.0
const QUIET_SPEED := 3.0
const STEP_LENGTH := 1.6
## Скорость сглаживается: позиции приходят по сети пачками, по одному кадру она скачет.
const SPEED_SMOOTHING_TIME := 0.2
## Перенос дальше этого за кадр (респавн) — не шаги.
const TELEPORT_DISTANCE := 3.0

## Видит ли кто-нибудь нашего игрока (последний список от хоста).
var is_seen: bool = false
var _last_position: Dictionary = {}  # id → Vector3
var _speed: Dictionary = {}  # id → м/с, сглаженная
var _step_left: Dictionary = {}  # id → м до следующего шага

var _update_left: float = 0.0
var _resend_left: float = 0.0
var _last_sent: Dictionary = {}  # peer id → Array[int]

@onready var players_node: Node3D = get_parent().get_node("Players")


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_update_steps(delta)
	_update_left -= delta
	_resend_left -= delta
	if _update_left > 0.0:
		return
	_update_left = UPDATE_INTERVAL
	var resend := _resend_left <= 0.0
	if resend:
		_resend_left = RESEND_INTERVAL
	var visibility := compute_visibility()
	var my_id := multiplayer.get_unique_id()
	for peer_id: int in visibility:
		var ids: Array = visibility[peer_id]
		if not resend and _last_sent.get(peer_id) == ids:
			continue
		_last_sent[peer_id] = ids
		if peer_id == my_id:
			apply_visibility(ids)
		elif peer_id in multiplayer.get_peers():
			apply_visibility.rpc_id(peer_id, ids)


## Для каждого игрока — отсортированный список id игроков, которых он видит.
func compute_visibility() -> Dictionary:
	var players: Array[Node] = players_node.get_children()
	var result := {}
	for p in players:
		result[int(str(p.name))] = []
	for i in players.size():
		for j in range(i + 1, players.size()):
			if can_see(players[i], players[j]):
				result[int(str(players[i].name))].append(int(str(players[j].name)))
				result[int(str(players[j].name))].append(int(str(players[i].name)))
	for id in result:
		result[id].sort()
	return result


## Видят ли игроки друг друга: в пределах дальности и хотя бы один луч от глаз
## одного до головы или пояса другого не упирается в землю или укрытие.
func can_see(a: Node3D, b: Node3D) -> bool:
	var flat := (b.global_position - a.global_position) * Vector3(1, 0, 1)
	if flat.length() > VIEW_RANGE:
		return false
	return _has_line_of_sight(a, b) or _has_line_of_sight(b, a)


func _has_line_of_sight(from: Node3D, to: Node3D) -> bool:
	var space := from.get_world_3d().direct_space_state
	var eye: Vector3 = from.global_position + Vector3.UP * from.get_body_height() * EYE_SHARE
	for share: float in TARGET_SHARES:
		var point: Vector3 = to.global_position + Vector3.UP * to.get_body_height() * share
		var query := PhysicsRayQueryParameters3D.create(eye, point, BLOCKING_MASK)
		if space.intersect_ray(query).is_empty():
			return true
	return false


func _update_steps(delta: float) -> void:
	for p: Node3D in players_node.get_children():
		var id := int(str(p.name))
		var pos := p.global_position
		var last: Vector3 = _last_position.get(id, pos)
		_last_position[id] = pos
		var moved := ((pos - last) * Vector3(1, 0, 1)).length()
		if moved > TELEPORT_DISTANCE or not p.health_component.is_alive:
			_speed[id] = 0.0
			continue
		var speed := lerpf(_speed.get(id, 0.0), moved / delta, 1.0 - exp(-delta / SPEED_SMOOTHING_TIME))
		_speed[id] = speed
		if speed < QUIET_SPEED:
			continue
		var left: float = _step_left.get(id, STEP_LENGTH * 0.5) - moved
		if left <= 0.0:
			left += STEP_LENGTH
			_send_step(id, pos)
		_step_left[id] = left


func _send_step(walker_id: int, pos: Vector3) -> void:
	var my_id := multiplayer.get_unique_id()
	for p: Node3D in players_node.get_children():
		var listener_id := int(str(p.name))
		if (p.global_position - pos).length() > HEARING_RANGE:
			continue
		if listener_id == my_id:
			play_step(pos, walker_id == my_id)
		elif listener_id in multiplayer.get_peers():
			play_step.rpc_id(listener_id, pos, walker_id == listener_id)


## Хост → пир: шаг в этой точке (own — свой, тише).
@rpc("authority", "unreliable")
func play_step(pos: Vector3, own: bool) -> void:
	SFXManager.play_step_at(pos, own)


## Хост → пир: кого этот пир видит.
@rpc("authority", "reliable")
func apply_visibility(visible_ids: Array) -> void:
	var seen := not visible_ids.is_empty()
	if seen != is_seen:
		is_seen = seen
		seen_changed.emit(seen)
	var my_id := multiplayer.get_unique_id()
	for p in players_node.get_children():
		var id := int(str(p.name))
		if id == my_id:
			_limit_own_sync(p, visible_ids)
		else:
			p.fog_hidden = not (id in visible_ids)


# Свою позицию шлём только тем, кто нас видит, и всегда — хосту.
func _limit_own_sync(own: Node, visible_ids: Array) -> void:
	var sync: MultiplayerSynchronizer = own.get_node("MultiplayerSynchronizer")
	for peer_id in multiplayer.get_peers():
		sync.set_visibility_for(peer_id, peer_id == 1 or peer_id in visible_ids)
