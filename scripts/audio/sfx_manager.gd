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
	var mix_rate := _base_mix_rate
	for i in range(frames):
		var t := float(i) / mix_rate
		# Layer 1: Low-end thump (barrel pressure)
		var thump := sin(t * 120.0) * exp(-t * 50.0) * 0.8
		# Layer 2: Mid-range crack (bullet supersonic snap)
		var crack := sin(t * 600.0) * exp(-t * 80.0) * 0.5
		# Layer 3: High-end hiss (expanding gas)
		var hiss := randf_range(-1.0, 1.0) * exp(-t * 100.0) * 0.25
		# Layer 4: Mechanical bolt clank (delayed)
		var bolt := sin((t - 0.012) * 1500.0) * exp(-(t - 0.012) * 120.0) * 0.2 if t > 0.01 else 0.0
		var sample := (thump + crack + hiss + bolt) * 1.2
		sample = clampf(sample, -1.0, 1.0)
		p.push_frame(Vector2(sample, sample))


func play_reload() -> void:
	var p := _get_playback(_reload_stream)
	if not p:
		return
	var frames := int(0.3 * _base_mix_rate)
	var mix_rate := _base_mix_rate
	for i in range(frames):
		var t := float(i) / mix_rate
		# Phase 1: Mag eject (0-0.08s) — slide + light click
		var eject := 0.0
		if t < 0.08:
			eject = sin(t * 2000.0) * exp(-t * 40.0) * 0.25
		# Phase 2: Mag insert (0.1-0.2s) — solid thunk
		var insert := 0.0
		if t > 0.1 and t < 0.2:
			var lt := t - 0.1
			insert = sin(lt * 600.0) * exp(-lt * 30.0) * 0.4
		# Phase 3: Bolt release (0.22-0.28s) — sharp snap
		var bolt := 0.0
		if t > 0.22 and t < 0.28:
			var lt := t - 0.22
			bolt = sin(lt * 2500.0) * exp(-lt * 80.0) * 0.35
		var sample := eject + insert + bolt
		p.push_frame(Vector2(sample, sample))


func play_hit() -> void:
	var p := _get_playback(_hit_stream)
	if not p:
		return
	var frames := int(0.06 * _base_mix_rate)
	var mix_rate := _base_mix_rate
	for i in range(frames):
		var t := float(i) / mix_rate
		# Impact thud (flesh/body hit)
		var thud := sin(t * 80.0) * exp(-t * 30.0) * 0.5
		# Surface crack
		var crack := randf_range(-0.4, 0.4) * exp(-t * 50.0)
		var sample := thud + crack
		p.push_frame(Vector2(sample, sample))


func play_step() -> void:
	var p := _get_playback(_step_stream)
	if not p:
		return
	var frames := int(0.05 * _base_mix_rate)
	var mix_rate := _base_mix_rate
	for i in range(frames):
		var t := float(i) / mix_rate
		# Boot on ground — low thump + slight gravel
		var thump := sin(t * 80.0) * exp(-t * 30.0) * 0.2
		var gravel := randf_range(-0.08, 0.08) * exp(-t * 40.0)
		var sample := thump + gravel
		p.push_frame(Vector2(sample, sample))


func play_empty() -> void:
	var p := _get_playback(_empty_stream)
	if not p:
		return
	var frames := int(0.04 * _base_mix_rate)
	var mix_rate := _base_mix_rate
	for i in range(frames):
		var t := float(i) / mix_rate
		# Dry bolt click — short metallic snap
		var click := sin(t * 3000.0) * exp(-t * 200.0) * 0.4
		var rattle := sin(t * 1800.0) * exp(-t * 150.0) * 0.15
		var sample := click + rattle
		p.push_frame(Vector2(sample, sample))
