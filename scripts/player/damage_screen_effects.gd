extends CanvasLayer

# ============================================================
# Экранные эффекты при попаданиях/убийствах.
# - Лёгкая виньетка при попадании по врагу
# - Красная вспышка при убийстве + slow-mo
# ============================================================

@onready var hit_vignette: ColorRect = $HitVignette
@onready var kill_flash: ColorRect = $KillFlash

# Параметры виньетки
const VIGNETTE_DURATION := 0.15
const VIGNETTE_MAX_ALPHA := 0.35

# Параметры вспышки убийства
const KILL_FLASH_DURATION := 0.6
const KILL_FLASH_MAX_ALPHA := 0.6
const KILL_SLOWMO_DURATION := 0.5
const KILL_SLOWMO_SCALE := 0.2

var _vignette_tween: Tween
var _kill_tween: Tween
var _slowmo_active := false


func _ready() -> void:
	if hit_vignette:
		hit_vignette.visible = false
	if kill_flash:
		kill_flash.visible = false


func on_hit(is_headshot: bool, is_kill: bool) -> void:
	_show_hit_vignette()
	
	if is_kill:
		_show_kill_flash()
		_start_slowmo()


func _show_hit_vignette() -> void:
	if not hit_vignette:
		return
	
	if _vignette_tween and _vignette_tween.is_valid():
		_vignette_tween.kill()
	
	hit_vignette.visible = true
	hit_vignette.modulate = Color(1.0, 1.0, 1.0, VIGNETTE_MAX_ALPHA)
	
	_vignette_tween = hit_vignette.create_tween()
	_vignette_tween.tween_property(hit_vignette, "modulate:a", 0.0, VIGNETTE_DURATION)
	_vignette_tween.tween_callback(func(): hit_vignette.visible = false)


func _show_kill_flash() -> void:
	if not kill_flash:
		return
	
	if _kill_tween and _kill_tween.is_valid():
		_kill_tween.kill()
	
	kill_flash.visible = true
	kill_flash.modulate = Color(1.0, 0.05, 0.05, KILL_FLASH_MAX_ALPHA)
	
	_kill_tween = kill_flash.create_tween()
	_kill_tween.tween_property(kill_flash, "modulate:a", 0.0, KILL_FLASH_DURATION)
	_kill_tween.tween_callback(func(): kill_flash.visible = false)


func _start_slowmo() -> void:
	if _slowmo_active:
		# Если slow-mo уже активен, сбрасываем таймер
		if Engine.time_scale > 0.5:
			return
		Engine.time_scale = KILL_SLOWMO_SCALE
	else:
		_slowmo_active = true
		Engine.time_scale = KILL_SLOWMO_SCALE
	
	# Восстанавливаем время через KILL_SLOWMO_DURATION
	await get_tree().create_timer(KILL_SLOWMO_DURATION, true, false, true).timeout
	
	# Плавное восстановление
	var tw := create_tween()
	tw.tween_property(self, "_restore_time_scale", 1.0, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# Ждём окончания восстановления
	await tw.finished
	_slowmo_active = false


# Хелпер для tween — Engine.time_scale не анимируется напрямую
func _restore_time_scale(val: float) -> void:
	Engine.time_scale = val
