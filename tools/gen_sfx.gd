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
## Затвор — отпирание, скольжение, звон гильзы и запирание; перезарядка — отдельный
## длинный звук (обойма, патроны, затвор).
##
## Основная энергия — в середине (200–1000 Гц), а не в басу: динамики планшетов и
## телефонов почти не воспроизводят частоты ниже ~250 Гц, и выстрел «в басах» на них
## звучал бы тихо и глухо.

const RATE := 44100
const SHOT_PATH := "res://assets/audio/rifle_shot.wav"
const BOLT_PATH := "res://assets/audio/rifle_bolt.wav"
const RELOAD_PATH := "res://assets/audio/rifle_reload.wav"

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 1915  # одинаковый результат при каждом запуске
	_save(_make_shot(), SHOT_PATH, 0.95)
	_save(_make_bolt(), BOLT_PATH, 0.8)
	_save(_make_reload(), RELOAD_PATH, 0.8)
	print("Звуки записаны: %s, %s, %s" % [SHOT_PATH, BOLT_PATH, RELOAD_PATH])
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


## Затвор после выстрела: отпер (щелчок), скольжение назад, гильза вылетает и
## звенит по земле, скольжение вперёд, заперт (тяжёлый щелчок).
func _make_bolt() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(RATE * 0.62))
	_clack(out, 0.0, 2300.0, 0.6, 700.0)
	_scrape(out, 0.02, 0.14, 0.22)
	_shell_ping(out, 0.12, 3400.0, 0.5)
	_shell_ping(out, 0.25, 3900.0, 0.28)
	_shell_ping(out, 0.32, 4300.0, 0.16)
	_scrape(out, 0.20, 0.10, 0.2)
	_clack(out, 0.30, 1750.0, 1.0, 550.0)
	return out


## Перезарядка (обойма Foxhole-стиля): затвор открыт, обойма вставлена, патроны
## вдавлены один за другим, пустая обойма выпала, затвор закрыт. Длина = reload_time.
func _make_reload() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(RATE * 2.5))
	# Затвор открыт.
	_clack(out, 0.10, 2300.0, 0.6, 700.0)
	_scrape(out, 0.12, 0.14, 0.22)
	# Обойма встаёт в пазы.
	_clack(out, 0.60, 1200.0, 0.9, 500.0)
	_scrape(out, 0.66, 0.08, 0.15)
	# Пять патронов вдавливаются большим пальцем: чуть разные щелчки.
	for k in 5:
		_clack(out, 1.00 + k * 0.115, 3000.0 - k * 120.0, 0.38, 900.0 - k * 40.0)
	# Пустая обойма выскакивает и звенит.
	_shell_ping(out, 1.68, 4100.0, 0.5)
	_shell_ping(out, 1.80, 4700.0, 0.22)
	# Затвор вперёд и запирается.
	_scrape(out, 1.95, 0.14, 0.24)
	_clack(out, 2.10, 1750.0, 1.0, 550.0)
	_clack(out, 2.22, 1400.0, 0.7, 450.0)
	return out


## Металлический щелчок: шум выше 1,5 кГц, короткий тон, «тело» в середине (400–1000 Гц,
## чтобы слышно было на динамиках планшетов) и глухой удар.
func _clack(out: PackedFloat32Array, at: float, tone: float, gain: float, body_hz: float) -> void:
	var start := int(RATE * at)
	var length := int(RATE * 0.09)
	var hiss := _highpass(_noise(length), 1500.0)
	var body := _highpass(_lowpass(_noise(length), body_hz * 1.6), body_hz * 0.5)
	var thunk := _lowpass(_noise(length), 450.0)
	for j in length:
		if start + j >= out.size():
			break
		var t := float(j) / RATE
		var v: float = hiss[j] * exp(-t / 0.004)
		v += sin(TAU * tone * t) * exp(-t / 0.012) * 0.35
		v += body[j] * exp(-t / 0.014) * 3.0
		v += thunk[j] * exp(-t / 0.02) * 1.4
		out[start + j] += v * gain


## Скольжение металла по металлу: полосовой шум с дрожанием, огибающая «горбом».
func _scrape(out: PackedFloat32Array, at: float, duration: float, gain: float) -> void:
	var start := int(RATE * at)
	var length := int(RATE * duration)
	var grit := _lowpass(_highpass(_noise(length), 900.0), 3500.0)
	for j in length:
		if start + j >= out.size():
			break
		var t := float(j) / RATE
		var env := sin(PI * float(j) / length)
		var ripple := 0.6 + 0.4 * sin(TAU * 55.0 * t)
		out[start + j] += grit[j] * env * ripple * gain * 2.0


## Звон гильзы или пустой обоймы о землю: тон и неточный обертон, быстрое затухание.
func _shell_ping(out: PackedFloat32Array, at: float, freq: float, gain: float) -> void:
	var start := int(RATE * at)
	var length := int(RATE * 0.12)
	for j in length:
		if start + j >= out.size():
			break
		var t := float(j) / RATE
		var v := sin(TAU * freq * t) * exp(-t / 0.03)
		v += sin(TAU * freq * 2.76 * t) * exp(-t / 0.015) * 0.4
		out[start + j] += v * gain * 0.5


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
