# Rankborn — Архитектура

Как устроен код **сейчас** и куда он должен прийти. Дизайн и решения — в [design.md](design.md),
план работ — в [roadmap.md](roadmap.md), стрельба — в [shooting.md](shooting.md).

## Статус
- **Движок:** Godot 4.7 (физика Jolt).
- **Сейчас:** LAN-прототип на 2–6 игроков. Есть меню с поиском лобби, ники, ENet P2P,
  спавн, синхронизация, стрельба, смерть и респавн, присед и спринт, управление
  с ПК, геймпада и тача. Проверено живым плейтестом двух клиентов по сети.
- **Нет:** сервера, базы данных, мета-игры (логистика, стройка, ранги), обратной связи
  боя (здоровье, килфид) — см. roadmap.

## Технологический стек

| Компонент | Сейчас | Планируется |
|---|---|---|
| Движок | Godot 4.7, GDScript | GDExtension (Rust/C++) — только если упрёмся в производительность (деформация земли) |
| Сеть | ENet, P2P: хост — peer `1` | Dedicated server (Godot headless), тот же код |
| Сохранения | Настройки в `user://settings.cfg` | SQLite (LAN), PostgreSQL + Redis (прод) |
| Управление | Input-действия: клавиатура/мышь, геймпад, тач | — |

## Схема сети

```
Сейчас (LAN, P2P)                       Потом (dedicated)
┌──────────┐  ENet  ┌──────────┐        ┌──────────┐  ENet  ┌──────────────────┐
│  Хост    │◄──────►│  Клиент  │        │ Игроки   │◄──────►│ Dedicated server │
│ peer = 1 │        │          │        └──────────┘        └────────┬─────────┘
└──────────┘        └──────────┘                                     │
  UDP 7000 — игра, UDP 7001 — поиск лобби                     PostgreSQL + Redis
```

- Каждый игрок — authority своего узла `Player` (имя узла = peer id). Позицию, поворот,
  `is_alive` и `is_crouching` синхронизирует `MultiplayerSynchronizer`.
- Туман войны: хост (`VisibilityManager`) считает, кто кого видит (дальность + прямая
  видимость), и рассылает каждому список. Пир прячет остальных и шлёт свою позицию только
  тем, кто его видит, и всегда хосту — скрытого противника нет и в трафике.
- Урон: стрелок шлёт `take_damage` владельцу жертвы; смерть жертва сама сообщает хосту
  (`GameMode.report_death`), хост рассылает счёт всем.
- Эффекты стрельбы — `unreliable` RPC (косметика).
- Ники: клиент после подключения шлёт хосту `_register_name`, хост рассылает список.
- Уход хоста: `NetworkManager.server_disconnected` — клиент возвращается в меню.

## Структура проекта (фактическая)

```
rankborn/
├── project.godot
├── scenes/
│   ├── main/main_menu.tscn      # Меню: ник, создать лобби, поиск игр, вход по IP
│   ├── game/game_scene.tscn     # Мир: свет, туман, спавны, границы, зона смерти, режим
│   ├── shared/player.tscn       # Игрок: капсула, голова с оружием, камера сверху, синхронизация, FSM
│   ├── weapons/rifle.tscn       # Винтовка
│   ├── effects/blood_splash.tscn
│   └── ui/                      # HUD оружия, мобильный UI, пауза, эффекты урона*
├── scripts/
│   ├── autoload/                # NetworkManager, LanDiscovery, GameSettings
│   ├── audio/sfx_manager.gd     # SFXManager (autoload)
│   ├── player/                  # Контроллер игрока, стейты (база PlayerState)
│   ├── weapons/                 # WeaponBase, Rifle, WeaponManager
│   ├── components/              # HealthComponent
│   ├── game_modes/              # GameMode, DeathmatchMode
│   ├── patterns/                # State, StateMachine
│   ├── ui/                      # Меню, HUD, мобильный UI, пауза
│   ├── world/                   # Сцена игры, границы, зона смерти
│   └── mesh_utils.gd            # Процедурные меши: земля, человечек, винтовка
├── shaders/                     # toon, outline, terrain, water*
├── tests/                       # spatial_check.gd, input_check.gd
├── addons/godot_mcp/            # Плагин редактора для AI-инструментов
└── docs/
```
\* Пока не используются: `damage_screen_effects.tscn` (подключается в фазе 2 roadmap), `water.gdshader`.

## Модули

### Есть
- **NetworkManager** (autoload) — хост/клиент ENet, список игроков и слоты спавна,
  ники, старт матча, уход хоста, LAN-адрес для показа.
- **LanDiscovery** (autoload) — поиск лобби по UDP broadcast + loopback; анонс несёт
  id сессии хоста, дубли схлопываются.
- **GameSettings** (autoload) — чувствительность, инверсия Y, режимы прицела/приседа, ник,
  пресеты графики (авто/низкая/средняя/высокая: разрешение 3D, MSAA, тени, вспышки света;
  «Авто» снижает пресет по замеру FPS — `scripts/world/auto_quality.gd`);
  `is_touch_device()` решает, включать ли сенсорный UI.
- **SFXManager** (autoload) — звуки: выстрел и затвор объёмные, в мире; слушатель — у своего
  солдата. Звуки синтезирует `tools/gen_sfx.gd`.
- **Player** — `CharacterBody3D`: направление прицеливания и `aim_point` (курсор мыши
  или правый стик), прицеливание, присед со своей капсулой, видимость в тумане войны,
  блокировка ввода меню. Камера — `IsoCamera` (сверху, фиксированный угол, сдвиг к прицелу).
  Движение — стейты `Idle/Walk/Jump` (база `PlayerState`, оси мира), смерть — `Dead/Respawn`.
- **Оружие** — `WeaponManager` → `Rifle` (hitscan, разброс, отдача, эффекты).
- **GameMode / DeathmatchMode** — счёт, смерти, сигнал килфида (UI пока нет).
- **MobileUI** — два плавающих стика (движение; прицел со стрельбой при сильном отклонении)
  и кнопки; нажимает те же Input-действия, что клавиатура и геймпад.
- **Мир** — земля из `MeshUtils.make_terrain()` (60×60, пологие холмы до 4 м, цвет в вершинах,
  плоские грани), trimesh-коллизия, укрытия (стены, камни, мешки), невидимые стены на ±50 м,
  зона смерти внизу.
- **VisibilityManager** — туман войны на хосте (см. «Схема сети»).

### Планируется
- **Тактическая карта** — отдельный вид сверху для меток и операций (design.md, раздел 4).
- **Земля на чанках + `HeightMapShape3D`** с сетевым состоянием — под траншеи (фаза 5).
- **Конструктор оружия** — модули (ствол, коробка, приклад, магазин, прицел), заказы заводам.
- **Логистика** — склады, грузовики, производство.
- **Ранги и полки** — см. design.md, раздел 4.
- **Dedicated server и сохранения** — см. ниже.

## Управление

Весь ввод — Input-действия (`move_*`, `shoot`, `aim`, `crouch`, `sprint`, `reload`,
`pause`, `look_*`, `weapon_next/prev`). Клавиатура, геймпад и тач идут одним путём:
`MobileUI` нажимает действия через `Input.action_press`; правый стик на таче нажимает
`look_*` так же, как правый стик геймпада. Наружу из `MobileUI` идёт только кнопка паузы. Эмуляция мыши из тача **включена**
(`input_devices/pointing/emulate_mouse_from_touch=true`): без неё на Android не работали
поля ввода и слайдеры. Чтобы касание не стреляло как клик, на тач-устройствах
`GameSettings` снимает кнопки мыши с игровых действий. Сенсорный UI и пауза — в
`CanvasLayer` выше HUD оружия.
Раскладки — в README, раздел «Управление».

## Миграция LAN → прод

| Шаг | Что делать | Сложность |
|---|---|---|
| 1 | Dedicated server на VPS (тот же проект в headless) | Низкая |
| 2 | Сохранения: SQLite → PostgreSQL | Средняя |
| 3 | Redis для сессий и кэша | Средняя |
| 4 | Матчмейкинг | Высокая |
| 5 | Античит: серверная проверка попаданий (сейчас стрелок решает сам) | Высокая |

## Проверки
- `godot --headless --path . --script tests/spatial_check.gd` (+ сеть: два процесса `-- host` / `-- client`)
- `xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/input_check.gd`

## Ссылки
- [High-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
- [ENetMultiplayerPeer](https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html)
- [HeightMapShape3D](https://docs.godotengine.org/en/stable/classes/class_heightmapshape3d.html)
- [GDExtension](https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/)
