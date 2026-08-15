# Crosshair & Shooting System Improvements

## Текущее состояние

### Прицел
- Статичный: 2 линии (верх + левая) + центральная точка
- Нет динамического spread
- Нет hit-маркера
- Scope: shader-виньетка + ретикаль с красной точкой

### Стрельба
- Hitscan (RayCast3D, 100м)
- Урон: 25 (4 выстрела до убийства)
- Разброс: нет (raycast всегда в центр)
- Отдача: рандомный vertical pull (0.86-1.72°)
- Fire rate: 0.15с (6.67 RPS)
- Магазин: 30, перезарядка: 2.0с

---

## 1. Динамический spread прицела

Линии прицела разъезжаются в зависимости от состояния игрока.

| Состояние | Множитель spread |
|---|---|
| Idle, standing | 1.0 (базовый) |
| Walking | 3.0 |
| Running / Sprinting | 6.0 |
| Firing (мгновенно) | 5.0 |
| Firing (после нескольких выстрелов) | +0.5 за каждый выстрел (накопление) |
| ADS (прицеливание) | 0.4 |
| ADS + firing | 0.6 |

Реализация: Tween на offset'ах каждой линии. При停止 стрельбе — decay к базовому spread за 0.2-0.3с.

---

## 2. Все 4 линии прицела

Сейчас есть только верхняя и левая. Стандарт FPS — 4 линии + центральная точка.

```
      |
   ---+---
      |
```

- **Top / Bottom** — вертикальные линии (зеркально)
- **Left / Right** — горизонтальные линии (зеркально)
- **Dot** — центральная точка (3x3px, alpha=0.7)

Offset каждой линии от центра = `base_gap + spread_offset`.

---

## 3. Динамический контраст прицела

Прицел должен быть виден на любом фоне.

- **Outline / Drop shadow**: обводка тёмным или тень вокруг линий прицела
- **Inverted crosshair** (опционально): цвет инвертируется относительно фона за точкой попадания

Реализация: добавить `Outline` node или shader на прицеле с `modulate` по цвету пикселя под ним.

---

## 4. Hit marker

При попадании по врагу — X-образный маркер вокруг точки попадания.

| Тип попадания | Цвет | Длительность |
|---|---|---|
| Обычный hit | Белый | 0.15с |
| Headshot | Красный | 0.2с |
| Убийца | Красный + thicker lines | 0.25с |

Реализация: 4 линии (Diagonal) через Control节点, Tween fade-out.

---

## 5. Bullet spread (пулевой разброс)

Raycast летит не в точку, а в конус вокруг центра.

```gdscript
var spread = _get_current_spread()
var offset = Vector2(
    randf_range(-spread, spread),
    randf_range(-spread, spread)
)
raycast.target_position = Vector3(offset.x, offset.y, -100)
```

| Состояние | Spread |
|---|---|
| Idle, standing | 0.005 |
| Walking | 0.015 |
| Running | 0.04 |
| Hipfire + shooting | 0.02 + 0.005/shot (accumulates) |
| ADS | 0.002 |
| ADS + shooting | 0.005 + 0.002/shot |

---

## 6. Damage falloff

Урон снижается с расстояния.

| Дистанция | Множитель урона | Урон |
|---|---|---|
| 0-30м | 100% | 25 |
| 30-60м | 70% | 17.5 |
| 60-100м | 50% | 12.5 |

```gdscript
func _get_damage_falloff(distance: float) -> float:
    if distance <= 30.0:
        return 1.0
    elif distance <= 60.0:
        return 0.7
    else:
        return 0.5
```

---

## 7. Headshot multiplier

Попадание в голову = x2 урон (50, 2 выстрела до убийбы).

Реализация:
- При raycast hit: проверить骨 collider
- Если collider — CharacterBody3D, получить позицию попадания
- Если позиция выше collider.global_position.y + capsule_height * 0.8 → headshot
- Или: использовать `bone_name` если скелет анимирован

---

## 8. Multi-step recoil pattern

Вместо рандомного vertical pull — фиксированный паттерн с learning curve.

```
Выстрел  1-3:  vertical pull вверх (сильный)
Выстрел  4-6:  horizontal drift вправо
Выстрел  7-9:  vertical + horizontal chaos
Выстрел 10+:   случайный spread в cone
```

Реализация: массив паттерна offsets, индекс сбрасывается при停止 стрельбе на 0.3с.

---

## 9. Bloom accumulation (накопление разброса)

Каждый выстрел добавляет `_recoil_amount`:
- `_recoil_amount += 0.01` per shot
- При停止 стрельбе: decay к 0 за 0.5с
- `_recoil_amount` влияет на spread и camera recoil

Создаёт惩罚 за prolonged spray, rewards burst fire.

---

## 10. Weapon sway (покачивание оружия)

При movement — лёгкое покачивание rifle.

```gdscript
# В _process:
var move_factor = velocity.length() / MAX_SPEED
var sway_x = sin(Time.get_ticks_msec() * 0.004) * move_factor * 0.003
var sway_y = cos(Time.get_ticks_msec() * 0.006) * move_factor * 0.002
weapon_pivot.position.x = base_x + sway_x
weapon_pivot.position.y = base_y + sway_y
```

---

## 11. Scope improvements

- **Scope sway**: ретикаль слегка движется при movement (дыхание)
- **Scope glint**: для других игроков видна вспышка на scope (balancing mechanic, Rimworld-style)

---

## 12. Penetration / Wallbang

- При попадании в thin wall (thickness < 0.3m) — дамаг с 50-70% reduction
- Реализация: 두 raycast (front hit + back hit), расстояние = wall thickness

---

## Приоритеты

| Приоритет | Улучшение | Сложность |
|---|---|---|
| 🔴 High | Динамический spread прицела | Средняя |
| 🔴 High | Bullet spread (hipfire vs ADS) | Низкая |
| 🔴 High | Hit marker | Низкая |
| 🟡 Medium | 4 линии прицела вместо 2 | Низкая |
| 🟡 Medium | Headshot multiplier | Низкая |
| 🟡 Medium | Damage falloff | Низкая |
| 🟡 Medium | Bloom accumulation | Средняя |
| 🟢 Low | Scope sway | Низкая |
| 🟢 Low | Weapon sway | Низкая |
| 🟢 Low | Recoil pattern | Высокая |
| 🟢 Low | Penetration / Wallbang | Средняя |
