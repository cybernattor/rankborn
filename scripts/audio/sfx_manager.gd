extends Node

var _shoot_player: AudioStreamGeneratorPlayback
var _reload_player: AudioStreamGeneratorPlayback
var _hit_player: AudioStreamGeneratorPlayback
var _step_player: AudioStreamGeneratorPlayback
var _empty_player: AudioStreamGeneratorPlayback

var _shoot_stream: AudioStreamGenerator
var _reload_stream: AudioStreamGenerator
var _hit_stream: AudioStreamGenerator
var _step_stream: AudioStreamGenerator
var _empty_stream: AudioStreamGenerator

var _base_mix_rate: float = AudioServer.get_mix_rate()


func _ready() -> void:
	_shoot_stream = _make_stream(0.08)
	_reload_stream = _make_stream(0.3)
	_hit_stream = _make_stream(0.06)
	_step_stream = _make_stream(0.05)
	_empty_stream = _make_stream(0.04)


func _make_stream(duration: float) -> AudioStreamGenerator:
	var s := AudioStreamGenerator.new()
	s.mix_rate = _base_mix_rate
	s.buffer_length = duration
	return s


func _get_playback(stream: AudioStreamGenerator) -> AudioStreamGeneratorPlayback:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Master"
	add_child(player)
	player.play()
	return player.get_stream_playback() as AudioStreamGeneratorPlayback


func play_shoot() -> void:
	var p := _get_playback(_shoot_stream)
	if not p:
		return
	var frames := int(0.08 * _base_mix_rate)
	for i in range(frames):
		var t := float(i) / float(frames)
		# Sharp crack + noise
		var env := exp(-t * 40.0)
		var noise := randf_range(-1.0, 1.0) * 0.3
		var crack := sin(t * 800.0 * exp(-t * 15.0)) * 0.7
		var sample := (crack + noise) * env
		p.push_frame(Vector2(sample, sample))


func play_reload() -> void:
	var p := _get_playback(_reload_stream)
	if not p:
		return
	var frames := int(0.3 * _base_mix_rate)
	for i in range(frames):
		var t := float(i) / float(frames)
		# Metallic click-clack
		var click1 := sin(t * 1200.0) * exp(-t * 20.0) * 0.4 if t < 0.1 else 0.0
		var click2 := sin((t - 0.15) * 800.0) * exp(-(t - 0.15) * 25.0) * 0.5 if t > 0.12 and t < 0.25 else 0.0
		var slide := sin(t * 200.0) * 0.15 * (1.0 - smoothstep(0.0, 0.05, abs(t - 0.08)))
		var noise := randf_range(-0.05, 0.05) if t > 0.05 and t < 0.2 else 0.0
		var sample := click1 + click2 + slide + noise
		p.push_frame(Vector2(sample, sample))


func play_hit() -> void:
	var p := _get_playback(_hit_stream)
	if not p:
		return
	var frames := int(0.06 * _base_mix_rate)
	for i in range(frames):
		var t := float(i) / float(frames)
		# Thud
		var thud := sin(t * 150.0 * exp(-t * 10.0)) * exp(-t * 25.0) * 0.6
		var crack := randf_range(-0.3, 0.3) * exp(-t * 30.0)
		var sample := thud + crack
		p.push_frame(Vector2(sample, sample))


func play_step() -> void:
	var p := _get_playback(_step_stream)
	if not p:
		return
	var frames := int(0.05 * _base_mix_rate)
	for i in range(frames):
		var t := float(i) / float(frames)
		# Soft thump
		var thump := sin(t * 100.0 * exp(-t * 15.0)) * exp(-t * 20.0) * 0.25
		var noise := randf_range(-0.1, 0.1) * exp(-t * 25.0)
		var sample := thump + noise
		p.push_frame(Vector2(sample, sample))


func play_empty() -> void:
	var p := _get_playback(_empty_stream)
	if not p:
		return
	var frames := int(0.04 * _base_mix_rate)
	for i in range(frames):
		var t := float(i) / float(frames)
		# Metallic click
		var click := sin(t * 2000.0) * exp(-t * 60.0) * 0.35
		p.push_frame(Vector2(click, click))
