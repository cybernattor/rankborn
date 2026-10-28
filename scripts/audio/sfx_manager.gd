extends Node

## Звуки. Выстрелы, затвор и перезарядка — объёмные (AudioStreamPlayer3D в мире): их слышат все
## игроки с той стороны, откуда стреляли, в том числе из-за укрытия и из тумана войны
## (выстрел выдаёт стрелка, как в Foxhole). Слушатель стоит у своего солдата, а не у
## камеры в 20 м над ним (Player, узел Ears).
## Звуки синтезируются: tools/gen_sfx.gd.

## Громкость без затухания до UNIT_SIZE метров, дальше спадает; дальше MAX_DISTANCE не слышно.
const UNIT_SIZE := 10.0
const MAX_DISTANCE := 120.0

var _shot: AudioStream
var _bolt: AudioStream
var _reload: AudioStream
var _empty: AudioStream
var _step: AudioStream


func _ready() -> void:
	_shot = load("res://assets/audio/rifle_shot.wav")
	_bolt = load("res://assets/audio/rifle_bolt.wav")
	_reload = load("res://assets/audio/rifle_reload.wav")
	_empty = load("res://assets/audio/empty.wav")
	_step = load("res://assets/audio/step.wav")


func _play(stream: AudioStream, volume_db: float = 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = "Master"
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


## follow — узел, за которым звук едет (затвор и перезарядка длятся секунды: убежал —
## звук не должен остаться позади). Без него звук стоит в точке position.
func _play_at(stream: AudioStream, position: Vector3, volume_db: float = 0.0, follow: Node3D = null) -> void:
	var scene := get_tree().current_scene
	if not scene is Node3D:
		return
	var parent: Node3D = follow if follow and follow.is_inside_tree() else scene
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.bus = "Master"
	parent.add_child(player)
	if parent == scene:
		player.global_position = position
	# Небольшой разброс высоты тона — очередь выстрелов не звучит как одна копия.
	player.pitch_scale = randf_range(0.94, 1.06)
	player.play()
	player.finished.connect(player.queue_free)


func play_shot_at(position: Vector3) -> void:
	_play_at(_shot, position)


func play_bolt_at(position: Vector3, follow: Node3D = null) -> void:
	_play_at(_bolt, position, -3.0, follow)


func play_reload_at(position: Vector3, follow: Node3D = null) -> void:
	_play_at(_reload, position, -2.0, follow)


## Шаг: свои — тише, чужие — громче (по ним слышно, что кто-то рядом).
func play_step_at(position: Vector3, own: bool) -> void:
	_play_at(_step, position, -12.0 if own else -3.0)


func play_empty() -> void:
	_play(_empty)
