class_name AutoQuality
extends Node

## Автонастройка графики (режим «Авто»): меряет средний FPS в матче и, если он ниже
## MIN_FPS, снижает пресет на ступень. Только вниз: при вертикальной синхронизации FPS
## упирается в частоту экрана, и запас для повышения по нему не виден. Начать подбор
## заново — снова выбрать «Авто» в меню.
##
## Замер — среднее за окно в несколько секунд, а не мгновенный FPS: взгляд в небо и
## в землю отличается втрое, решать по одному кадру нельзя.

## Пропуск после старта и после смены пресета: затемнение, компиляция шейдеров.
const WARMUP_TIME := 3.0
const WINDOW_TIME := 5.0
const MIN_FPS := 45.0
## Кадры длиннее этого не считаем: приложение сворачивали или грузилась сцена.
const MAX_FRAME_TIME := 0.5

var _warmup: float = WARMUP_TIME
var _window: float = 0.0
var _frames: int = 0


func _process(delta: float) -> void:
	add_frame(delta)


## Учесть кадр длительностью delta. Отдельно от _process, чтобы проверять в тестах.
func add_frame(delta: float) -> void:
	if not GameSettings.is_auto_quality() or delta > MAX_FRAME_TIME:
		return
	if _warmup > 0.0:
		_warmup -= delta
		return
	_window += delta
	_frames += 1
	if _window < WINDOW_TIME:
		return
	var fps := _frames / _window
	_window = 0.0
	_frames = 0
	if fps < MIN_FPS and GameSettings.lower_auto_quality():
		_warmup = WARMUP_TIME
