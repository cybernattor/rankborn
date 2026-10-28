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
## Металл (щелчки, гильзы) строится только из шума: чистый синус на 3–5 кГц звучит как
## нота маримбы или звонок, а не как латунь о землю. Проверка — tools/check_tonal.py.
##
## Основная энергия — в середине (200–1000 Гц), а не в басу: динамики планшетов и
## телефонов почти не воспроизводят частоты ниже ~250 Гц, и выстрел «в басах» на них
## звучал бы тихо и глухо.

const RATE := 44100
const SHOT_PATH := "res://assets/audio/rifle_shot.wav"
const BOLT_PATH := "res://assets/audio/rifle_bolt.wav"
const RELOAD_PATH := "res://assets/audio/rifle_reload.wav"
const STEP_PATH := "res://assets/audio/step.wav"
const EMPTY_PATH := "res://assets/audio/empty.wav"
const HIT_FLESH_PATH := "res://assets/audio/hit_flesh.wav"
const HIT_DIRT_PATH := "res://assets/audio/hit_dirt.wav"
const HIT_HARD_PATH := "res://assets/audio/hit_hard.wav"
const WHIZ_PATH := "res://assets/audio/bullet_whiz.wav"

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 1915  # одинаковый результат при каждом запуске
	_save(_make_shot(), SHOT_PATH, 0.95)
	_save(_make_bolt(), BOLT_PATH, 0.8)
	_save(_make_reload(), RELOAD_PATH, 0.8)
	_save(_make_step(), STEP_PATH, 0.7)
	_save(_make_empty(), EMPTY_PATH, 0.6)
	_save(_make_hit_flesh(), HIT_FLESH_PATH, 0.8)
	_save(_make_hit_dirt(), HIT_DIRT_PATH, 0.7)
	_save(_make_hit_hard(), HIT_HARD_PATH, 0.8)
	_save(_make_whiz(), WHIZ_PATH, 0.7)
	print("Звуки записаны в assets/audio")
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
	_metal_tick(out, 0.12, 3400.0, 0.5)
	_metal_tick(out, 0.25, 3900.0, 0.28)
	_metal_tick(out, 0.32, 4300.0, 0.16)
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
	_metal_tick(out, 1.68, 4100.0, 0.5)
	_metal_tick(out, 1.80, 4700.0, 0.22)
	# Затвор вперёд и запирается.
	_scrape(out, 1.95, 0.14, 0.24)
	_clack(out, 2.10, 1750.0, 1.0, 550.0)
	_clack(out, 2.22, 1400.0, 0.7, 450.0)
	return out


## Металлический щелчок: шум выше 1,5 кГц, шумовая полоса вокруг tone (вместо синуса),
## «тело» в середине (400–1000 Гц, чтобы слышно было на динамиках планшетов) и глухой удар.
func _clack(out: PackedFloat32Array, at: float, tone: float, gain: float, body_hz: float) -> void:
	var start := int(RATE * at)
	var length := int(RATE * 0.09)
	var hiss := _highpass(_noise(length), 1500.0)
	var ring := _highpass(_lowpass(_noise(length), tone * 1.4), tone * 0.7)
	var body := _highpass(_lowpass(_noise(length), body_hz * 1.6), body_hz * 0.5)
	var thunk := _lowpass(_noise(length), 450.0)
	for j in length:
		if start + j >= out.size():
			break
		var t := float(j) / RATE
		var v: float = hiss[j] * exp(-t / 0.004)
		v += ring[j] * exp(-t / 0.008) * 1.2
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


## Стук латуни о землю или пустой обоймы: короткий сухой «тик» — полоса шума вокруг freq
## с быстрым спадом, без звенящего тона.
func _metal_tick(out: PackedFloat32Array, at: float, freq: float, gain: float) -> void:
	var start := int(RATE * at)
	var length := int(RATE * 0.05)
	var band := _highpass(_lowpass(_noise(length), freq * 1.3), freq * 0.6)
	var low := _highpass(_lowpass(_noise(length), 1400.0), 500.0)
	for j in length:
		if start + j >= out.size():
			break
		var t := float(j) / RATE
		out[start + j] += (band[j] * exp(-t / 0.005) * 2.5 + low[j] * exp(-t / 0.01) * 1.5) * gain * 0.5


## Сухой щелчок бойка по пустому патроннику: тот же металл, но один и тише.
func _make_empty() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(RATE * 0.12))
	_clack(out, 0.005, 2000.0, 0.8, 800.0)
	return out


## Попадание в тело: глухой шлепок (середина, чтобы слышно было на динамиках) и короткий
## влажный всплеск выше.
func _make_hit_flesh() -> PackedFloat32Array:
	var n := int(RATE * 0.25)
	var thud := _highpass(_lowpass(_lowpass(_noise(n), 600.0), 600.0), 130.0)
	var slap := _highpass(_lowpass(_noise(n), 3000.0), 900.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var attack := minf(t / 0.0015, 1.0)
		out[i] = thud[i] * attack * exp(-t / 0.05) * 6.0 + slap[i] * attack * exp(-t / 0.012) * 1.6
	return out


## Пуля в землю: комок грунта — глухой удар и крошка выше.
func _make_hit_dirt() -> PackedFloat32Array:
	var n := int(RATE * 0.3)
	var thump := _highpass(_lowpass(_lowpass(_noise(n), 900.0), 900.0), 150.0)
	var grit := _highpass(_lowpass(_noise(n), 5000.0), 1500.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var attack := minf(t / 0.001, 1.0)
		out[i] = thump[i] * attack * exp(-t / 0.06) * 5.0 + grit[i] * attack * exp(-t / 0.035) * 1.0
	return out


## Пуля в камень, стену, мешок: резкий щелчок и срикошетивший «зинь» — полоса шума,
## уходящая вниз по частоте (шум, а не синус: тон звучал бы нотой).
func _make_hit_hard() -> PackedFloat32Array:
	var n := int(RATE * 0.45)
	var crack := _highpass(_noise(n), 2000.0)
	var body := _highpass(_lowpass(_lowpass(_noise(n), 1800.0), 1800.0), 400.0)
	var zing := _sweep_band(_noise(n), 3800.0, 1400.0, 0.35, 3.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var attack := minf(t / 0.0008, 1.0)
		out[i] = crack[i] * exp(-t / 0.003) * 3.0 + body[i] * attack * exp(-t / 0.03) * 4.0
		out[i] += zing[i] * minf(t / 0.01, 1.0) * exp(-t / 0.12) * 1.2
	return out


## Свист пули рядом: «ш-ш-ших» — полоса шума падает по частоте (приближение, пролёт,
## удаление) и резкий хлопок звуковой волны в момент пролёта.
func _make_whiz() -> PackedFloat32Array:
	var n := int(RATE * 0.35)
	var sweep := _sweep_band(_noise(n), 5200.0, 1800.0, 0.26, 2.0)
	var snap := _highpass(_noise(n), 1800.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var peak := 0.11
	for i in n:
		var t := float(i) / RATE
		var env := exp(-pow((t - peak) / 0.07, 2.0))
		out[i] = sweep[i] * env * 4.0
		var dt := t - peak
		if dt >= 0.0:
			out[i] += snap[i] * exp(-dt / 0.004) * 2.0
	return out


## Полосовой фильтр с плывущей частотой (фильтр с переменным состоянием): шум проходит
## через узкую полосу, которая за duration секунд уходит с from_hz на to_hz.
func _sweep_band(x: PackedFloat32Array, from_hz: float, to_hz: float, duration: float, q: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(x.size())
	var low := 0.0
	var band := 0.0
	for i in x.size():
		var t := float(i) / RATE
		var hz := lerpf(from_hz, to_hz, clampf(t / duration, 0.0, 1.0))
		var f := 2.0 * sin(PI * hz / RATE)
		low += f * band
		var high := x[i] - low - band / q
		band += f * high
		out[i] = band
	return out


# Шаг по земле: глухой удар подошвы (середина, не бас — динамики телефонов) и короткий
# хруст грунта поверх.
func _make_step() -> PackedFloat32Array:
	var n := int(RATE * 0.2)
	var thud := _highpass(_lowpass(_lowpass(_noise(n), 700.0), 700.0), 160.0)
	var grit := _highpass(_lowpass(_noise(n), 4000.0), 1400.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var attack := minf(t / 0.004, 1.0)
		out[i] = thud[i] * attack * exp(-t / 0.03) * 6.0 + grit[i] * attack * exp(-t / 0.045) * 0.8
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
