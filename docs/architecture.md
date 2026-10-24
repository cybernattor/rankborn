# Rankborn — План и Архитектура

## Статус проекта
- **Движок**: Godot 4.6+ (проект создан)
- **Бэкенд**: Не реализован (планируется)
- **Текущее состояние**: LAN-прототип — меню/лобби, ENet P2P, спавн, sync позиций, стрельба, респавн. Нужен ручной тест 2–6 игроков.

---

## Концепция игры

**Rankborn** — масштабный кроссплатформенный РП-шутер с элементами военной стратегии.
Живой фронт, где действия каждого игрока влияют на исход войны.

### Референс
Мета-игра основана на **Foxhole** (фронт, логистика, строительство, иерархия). Наше отличие — FPS-бой, конструктор оружия и кроссплатформа ПК + мобилки. См. [README](../README.md#референс-foxhole).

### Ключевые фичи
- **Военная иерархия**: Главнокомандующий → Офицеры → Солдаты
- **Физическая логистика**: Оружие производят на заводах, везут грузовиками на фронт
- **Конструктор оружия**: Модульная сборка (ствол + приклад + коробка)
- **Инженеры**: Траншеи (деформация меша), фортификации, дороги
- **Кроссплатформа**: ПК + Мобилки, одна версия
- **Бесшовный мир**: Хексагональные сектора, стриминг без загрузок
- **Low-Poly** стиль

### Масштаб
- **2-6 игроков** (LAN для тестов)
- P2P архитектура, потом dedicated server

---

## Технологический стек

| Компонент | Технология | Почему |
|---|---|---|
| Движок | **Godot 4.6** | Кроссплатформа, встроенный мультиплеер |
| Язык клиента | **GDScript** | Быстрая разработка |
| Тяжёлая логика | **GDExtension (Rust/C++)** | Воксели, деформация меша |
| Сеть (LAN) | **ENet (UDP)** | Встроен в Godot, P2P из коробки |
| Сеть (prod) | **ENet + dedicated server** | Тот же код, другой запуск |
| Persistence (LAN) | **SQLite** | Файл рядом с игрой |
| Persistence (prod) | **PostgreSQL** | Тот же SQL-диалект |
| Кэш (prod) | **Redis** | Сессии, позиции, Pub/Sub |
| Управление (мобилки) | **Virtual joysticks** | Стандарт для мобильных FPS |

---

## Архитектура

### Phase 1: LAN (P2P)

```
┌──────────┐     ENet      ┌──────────┐
│ Player 1 │ ◄───────────► │ Player 2 │  (2-6 игроков)
│  (host)  │               │ (client) │
└─────┬────┘               └──────────┘
      │
  SQLite (local)
      │
  Game State
```

### Phase 2: Production (Dedicated Server)

```
┌──────────┐     ENet      ┌─────────────────┐
│ Player 1 │ ◄───────────► │ Dedicated Server│
│ Player 2 │ ◄───────────► │ (Godot headless)│
│ Player 3 │ ◄───────────► │                 │
└──────────┘               └────────┬────────┘
                                    │
                              PostgreSQL + Redis
```

**Ключевая фича**: Код P2P и dedicated server один и тот же. Разница только в запуске.

---

## Структура проекта

Целевая структура (часть папок ещё не создана: `resources/`, `data/`, `scripts/network/`, `scripts/mobile/`).
Фактически сейчас: игрок — `scenes/shared/player.tscn`, игровая сцена — `scenes/game/game_scene.tscn`,
стейты игрока — `scripts/player/states/` (общая база `PlayerState`), шейдеры — `shaders/`, проверки — `tests/`.

```
rankborn/
├── project.godot
├── scenes/
│   ├── main/                  # Главное меню, лобби
│   ├── game/                  # Игровая сцена
│   │   ├── world.tscn         # Мир (сектора)
│   │   ├── player.tscn        # Игрок (FPS контроллер)
│   │   └── ui/                # HUD, инвентарь, карта
│   ├── mobile/                # Мобильный UI (джойстики)
│   └── shared/                # Общие компоненты
├── scripts/
│   ├── autoload/              # NetworkManager, GameManager
│   ├── player/                # FPS контроллер, оружие
│   ├── world/                 # Сектора, воксели, деформация
│   ├── network/               # Сетевая логика (RPC)
│   ├── ui/                    # UI скрипты
│   └── mobile/                # Виртуальные джойстики
├── resources/
│   ├── weapons/               # Конструктор оружия
│   ├── maps/                  # Конфигурация карт
│   └── config/                # Настройки
├── addons/                    # GDExtension
├── data/                      # SQLite база
└── export/                    # Экспорт для платформ
```

---

## Ключевые модули

### NetworkManager (Autoload)
- Управляет P2P / dedicated подключением
- Host: `create_server()`
- Клиент: `create_client()`
- При переключении на prod — тот же код, другой IP

### GameManager (Autoload)
- Управление игровым состоянием
- Синхронизация через MultiplayerSynchronizer
- Сектора, ресурсы, логистика

### Player (CharacterBody3D)
- FPS контроллер (WASD + мышь)
- На мобилках — виртуальные джойстики
- Синхронизация позиции через MultiplayerSynchronizer

### WeaponSystem
- Модульный конструктор оружия
- Ствол + приклад + коробка = готовое оружие
- Серверная валидация (anti-cheat)

### MapManager
- Хексагональные сектора
- Конфигурация через ресурсы (.tres)
- Стриминг при движении игрока

---

## Управление на мобилках

```
Экран мобилки:
┌─────────────────────────────┐
│  [HP] [Аmmo]     [Карта]   │  ← HUD
│                             │
│                             │
│  (○)                 (○)   │  ← Виртуальные джойстики
│  Move                 Look  │
│                             │
│  [Стрелять] [Взаимодействие]│  ← Кнопки
└─────────────────────────────┘
```

- `DisplayServer.is_touchscreen_available()` — определение платформы
- `Input.set_emulate_mouse_from_touch(true)` — тач = мышь

---

## Миграция LAN → Production

| Шаг | Что делать | Сложность |
|---|---|---|
| 1 | Запуск dedicated server на VPS | Низкая |
| 2 | PostgreSQL вместо SQLite | Средняя |
| 3 | Redis для кэша | Средняя |
| 4 | Матчмейкинг (лобби) | Высокая |
| 5 | Античит | Высокая |

Шаги 1-2 — буквально запустить тот же Godot проект на сервере.

---

## План действий (Roadmap)

### Phase 1: Foundation
- [x] NetworkManager — P2P подключение через ENet
- [x] FPS контроллер — CharacterBody3D + WASD + мышь
- [x] Синхронизация — MultiplayerSynchronizer (position/rotation/head)
- [x] Mobile UI — виртуальные джойстики
- [x] Один сектор — базовая карта для теста
- [x] Лобби — Start у хоста + показ LAN IP
- [x] Спавн всех peer’ов + меш игрока + коллизия земли
- [x] Оружие (rifle) + респавн
- [ ] Тест на LAN — 2-6 игроков (прогнать руками)

### Phase 2: Core Gameplay
- [x] Стрельба и оружие
- [ ] Конструктор оружия (модули)
- [ ] Инвентарь и логистика
- [ ] Система рангов и иерархии

### Phase 3: World
- [ ] Хексагональные сектора
- [ ] Стриминг чанков
- [ ] Деформация меша (траншеи)
- [ ] Фортификации и строительство

### Phase 4: Production
- [ ] Dedicated server
- [ ] PostgreSQL + Redis
- [ ] Матчмейкинг
- [ ] Экспорт на мобильные платформы

---

## Технологии (ссылки)
- [Godot 4.6 Multiplayer](https://docs.godotengine.org/en/4.6/tutorials/networking/high_level_multiplayer.html)
- [ENetMultiplayerPeer](https://docs.godotengine.org/en/4.6/classes/class_enetmultiplayerpeer.html)
- [MeshDataTool (деформация)](https://docs.godotengine.org/en/4.6/tutorials/3d/procedural_geometry/meshdatatool.html)
- [GDExtension](https://docs.godotengine.org/en/4.6/tutorials/scripting/gdextension/)
