extends Node

var _shoot: AudioStream
var _reload: AudioStream
var _hit: AudioStream
var _step: AudioStream
var _empty: AudioStream


func _ready() -> void:
	_shoot = load("res://assets/audio/shoot.wav")
	_reload = load("res://assets/audio/reload.wav")
	_hit = load("res://assets/audio/hit.wav")
	_step = load("res://assets/audio/step.wav")
	_empty = load("res://assets/audio/empty.wav")


func _play(stream: AudioStream, volume_db: float = 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = "Master"
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func play_shoot() -> void:
	_play(_shoot, -2.0)


func play_reload() -> void:
	_play(_reload)


func play_hit() -> void:
	_play(_hit, -3.0)


func play_step() -> void:
	_play(_step, -6.0)


func play_empty() -> void:
	_play(_empty, -4.0)
