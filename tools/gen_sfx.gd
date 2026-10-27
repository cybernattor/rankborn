extends SceneTree

## Генератор звуков оружия: godot --headless --path . --script tools/gen_sfx.gd
## Звуки синтезируются, а не берутся из библиотек — без лицензий и чужих ассетов.
## Прежний shoot.wav был 0.18 с белого шума без низов и звучал как «тсссс» хай-хэта.
##
## Выстрел винтовки складывается из:
## - щелчка (сверхзвуковой хлопок, пара миллисекунд высоких частот);
## - хлопка у дула (шум через фильтр низких частот, быстрый спад) и удара (синус,
##   падающий по тону, — «тело» выстрела);
## - хвоста и двух отражений (эхо местности), уже без высоких частот.
## Затвор — два металлических щелчка: открыл и дослал.
##
## Основная энергия — в середине (200–1000 Гц), а не в басу: динамики планшетов и
## телефонов почти не воспроизводят частоты ниже ~250 Гц, и выстрел «в басах» на них
## звучал бы тихо и глухо.

const RATE := 44100
const SHOT_PATH := "res://assets/audio/rifle_shot.wav"
const BOLT_PATH := "res://assets/audio/rifle_bolt.wav"

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 1915  # одинаковый результат при каждом запуске
	_save(_make_shot(), SHOT_PATH, 0.95)
	_save(_make_bolt(), BOLT_PATH, 0.6)
	print("Звуки записаны: %s, %s" % [SHOT_PATH, BOLT_PATH])
	quit()


func _make_shot() -> PackedFloat32Array:
	var n := int(RATE * 1.2)
	var noise := _noise(n)
	var crack := _highpass(noise, 2500.0)
	var blast := _highpass(_lowpass(_lowpass(noise, 1600.0), 1600.0), 180.0)
	var tail := _highpass(_lowpass(_lowpass(noise, 600.0), 600.0), 150.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var attack := minf(t / 0.0006, 1.0)
		phase += TAU * lerpf(260.0, 110.0, minf(t / 0.1, 1.0)) / RATE
		var v := 0.0
		v += crack[i] * exp(-t / 0.003) * 3.5
		v += blast[i] * attack * exp(-t / 0.06) * 5.0
		v += sin(phase) * attack * exp(-t / 0.07) * 0.7
		v += tail[i] * minf(t / 0.03, 1.0) * exp(-t / 0.35) * 2.2
		out[i] = v
	# Отражения: сам хлопок без высоких частот, позже и тише.
	var echo := _lowpass(out, 1500.0)
	for delay_gain in [[0.13, 0.28], [0.29, 0.14]]:
		var offset := int(RATE * delay_gain[0])
		for i in range(offset, n):
			out[i] += echo[i - offset] * delay_gain[1]
	for i in n:
		out[i] = tanh(out[i] * 1.4)  # мягкое насыщение — плотнее удар
	return out


func _make_bolt() -> PackedFloat32Array:
	var n := int(RATE * 0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	for click in [[0.0, 2300.0, 0.5], [0.22, 1750.0, 0.8]]:
		var start := int(RATE * click[0])
		var length := int(RATE * 0.08)
		var noise := _highpass(_noise(length), 1500.0)
		var thunk := _lowpass(_noise(length), 450.0)
		for j in length:
			if start + j >= n:
				break
			var t := float(j) / RATE
			var v: float = noise[j] * exp(-t / 0.004)
			v += sin(TAU * click[1] * t) * exp(-t / 0.012) * 0.35
			v += thunk[j] * exp(-t / 0.02) * 2.0 * click[2]
			out[start + j] += v
	return out


func _noise(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = _rng.randf_range(-1.0, 1.0)
	return out


# Однополюсный фильтр низких частот.
func _lowpass(x: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	var out := PackedFloat32Array()
	out.resize(x.size())
	for i in x.size():
		y += a * (x[i] - y)
		out[i] = y
	return out


func _highpass(x: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var low := _lowpass(x, cutoff)
	var out := PackedFloat32Array()
	out.resize(x.size())
	for i in x.size():
		out[i] = x[i] - low[i]
	return out


func _save(samples: PackedFloat32Array, path: String, peak: float) -> void:
	var top := 0.0
	for v in samples:
		top = maxf(top, absf(v))
	var gain := peak / top if top > 0.0 else 1.0
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.save_to_wav(ProjectSettings.globalize_path(path))
