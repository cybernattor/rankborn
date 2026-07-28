extends Node

var _shoot: AudioStream
var _empty: AudioStream


func _ready() -> void:
	_shoot = load("res://assets/audio/shoot.wav")
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
	_play(_shoot)


func play_empty() -> void:
	_play(_empty)
