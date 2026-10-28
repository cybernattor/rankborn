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
var _hit_flesh: AudioStream
var _hit_dirt: AudioStream
var _hit_hard: AudioStream
var _whiz: AudioStream


func _ready() -> void:
	_shot = load("res://assets/audio/rifle_shot.wav")
	_bolt = load("res://assets/audio/rifle_bolt.wav")
	_reload = load("res://assets/audio/rifle_reload.wav")
	_empty = load("res://assets/audio/empty.wav")
	_step = load("res://assets/audio/step.wav")
	_hit_flesh = load("res://assets/audio/hit_flesh.wav")
	_hit_dirt = load("res://assets/audio/hit_dirt.wav")
	_hit_hard = load("res://assets/audio/hit_hard.wav")
	_whiz = load("res://assets/audio/bullet_whiz.wav")


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


## Пуля попала в тело: слышат все рядом (стрелок и жертва тоже — это подтверждение попадания).
func play_hit_flesh_at(position: Vector3) -> void:
	_play_at(_hit_flesh, position, -2.0)


## Пуля в землю (ground) или в твёрдое — камень, стену, мешок.
func play_impact_at(position: Vector3, ground: bool) -> void:
	if ground:
		_play_at(_hit_dirt, position, -5.0)
	else:
		_play_at(_hit_hard, position, -3.0)


## Пуля пролетела рядом со слушателем.
func play_whiz_at(position: Vector3) -> void:
	_play_at(_whiz, position, -2.0)


func play_empty() -> void:
	_play(_empty)
