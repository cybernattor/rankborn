# AGENTS.md

## What this is

Godot 4.7 multiplayer shooter/strategy game with a top-down camera like Foxhole (fixed angle, twin-stick aiming, fog of war decided by the host). GDScript only. No C#, no build system outside Godot.

## Running the project

- **Open and run**: Open `project.godot` in Godot Editor → F5
- **No CLI build**: There is no `npm`, `cargo`, or equivalent. All compilation is Godot-side.
- **Export**: Windows x86_64 and Android presets in `export_presets.cfg`; output goes to `export/` (git-ignored). `tools/export.sh` builds the Android release APK and the Windows debug build (`GODOT=/path/to/godot tools/export.sh` if Godot is not in PATH); it needs the export templates and a real Android SDK set in the editor settings (`export/android/android_sdk_path`) — Godot signs the APK itself via `apksigner`.
- **Signing**: every build is signed with the project's debug key `tools/debug.keystore` (alias `androiddebugkey`, password `android`), passed via `GODOT_ANDROID_KEYSTORE_{DEBUG,RELEASE}_*` env vars, so a new APK installs over the previous one. It is a test key, not a secret; `tools/` is excluded from exports. A Google Play release key must never be committed

## Network testing (critical)

This is a P2P LAN game. Testing requires multiple instances:

1. Godot Editor → Debug → **Run Multiple Instances** = 2
2. One instance creates a lobby, the other discovers and joins it
3. Firewall must allow **UDP 7000** (game) and **UDP 7001** (LAN discovery)

LAN discovery is broadcast-based (port 7001). Instances on the same machine discover each other via loopback fallback.

## Architecture

**Autoloads** (singletons, always available):
- `NetworkManager` → ENet P2P, player registry, host/client logic (`scripts/autoload/network_manager.gd`)
- `LanDiscovery` → UDP broadcast lobby browser (`scripts/autoload/lan_discovery.gd`)
- `SFXManager` → Audio (`scripts/audio/sfx_manager.gd`): shots and bolt are positional `AudioStreamPlayer3D` in the world; the listener is the local soldier's `Ears` (top_level `AudioListener3D` with the camera's basis), not the camera 20 m above. Hits (flesh/dirt/hard), bullet whiz (within 4 m of the listener's head, never your own shots) and reload are positional too. Metal sounds are noise only — a pure sine at 3–5 kHz sounds like a marimba note; `python3 tools/check_tonal.py assets/audio/*.wav` flags pure tones. Sounds are synthesized by `tools/gen_sfx.gd` (`godot --headless --path . --script tools/gen_sfx.gd`), energy in the mids — tablet speakers drop everything below ~250 Hz
- `GameSettings` → Controls settings and nickname, saved to `user://settings.cfg`; `is_touch_device()` (`scripts/autoload/game_settings.gd`)

**Scene flow**: `main_menu.tscn` → (host or join) → `game_scene.tscn` (spawns players, builds terrain)

**Key scenes**:
- `scenes/shared/player.tscn` → CharacterBody3D player (camera, sync, state machine)
- `scenes/game/game_scene.tscn` → World with terrain, spawn points, players node
- `scenes/weapons/rifle.tscn` → First weapon

**Key scripts**:
- `scripts/player/player_controller.gd` → Aim direction and `aim_point` (mouse cursor or right stick), ADS, crouch, fog-of-war presence, input blocking, death; movement lives in `scripts/player/states/` (`PlayerState` base)
- `scripts/player/iso_camera.gd` → `IsoCamera`: fixed-angle top-down camera (top_level), follows the player and looks ahead towards the aim point (further in ADS)
- `scripts/world/visibility_manager.gd` → Fog of war: host computes who sees whom, peers hide others and limit their own sync
- `scripts/world/game_scene.gd` → Player spawning, terrain and covers, `ground_height_at()`, pause wiring, host-left handling
- `scripts/mesh_utils.gd` → Procedural mesh generation (humanoid, terrain, boxes)

## Networking conventions

- RPCs use Godot's multiplayer API: `@rpc("authority", "reliable")`, `@rpc("call_local", "reliable")`, `@rpc("any_peer", "reliable")`
- Player nodes are named by peer ID (e.g., `"1"` for host, `"2418539201"` for client)
- `set_multiplayer_authority()` is called on player root and propagated to all children
- Host is always peer ID `1`

## Code conventions

- Comments and documentation are in **Russian** — keep them in Russian
- Constants are `UPPER_SNAKE_CASE`, variables/functions are `snake_case`
- Type hints on function signatures and `const`/`var` declarations (GDScript style)
- Physics engine: **Jolt Physics** (not Godot's default)
- Renderer: D3D12 on Windows (`rendering/rendering_device/driver.windows="d3d12"`)
- Procedural low-poly terrain via `MeshUtils.make_terrain()` with `FastNoiseLite` (seed 42): 60×60 grid, per-vertex colors, flat-shaded faces (`smooth` parameter exists but is off). Hill amplitude `TERRAIN_HEIGHT = 4` m — gentle on purpose: with a top-down camera steep slopes make covers useless (whoever stands uphill sees over a wall)

## Mobile support

All input goes through Input actions (`move_*`, `shoot`, `aim`, `crouch`, `vault`, `sprint`, `reload`, `pause`, `look_*`). No free jump, like Foxhole; instead `vault` (Space / gamepad A / touch VAULT) climbs over low cover: `Player.find_vault()` probes for an obstacle at knee height, free space above `VAULT_MAX_HEIGHT` (measured from the ground underfoot — sandbags on a slope reach ~1.55 m, walls are ≥2.2 m) and a free landing behind it; `VaultState` moves along an arc in 0.6 s with collision off and no shooting. Holding the key retries, like Foxhole. `JumpState` is only falling. `MobileUI` (`scripts/ui/mobile_ui.gd`) presses the same actions via `Input.action_press`, so states read one input path for keyboard, gamepad and touch. Only the pause button goes through a signal.

- Layout (twin-stick, Foxhole aiming): floating move stick in the bottom-left (full deflection = sprint); floating aim stick in the bottom-right — holding it presses `aim`, its direction and deflection (= aim distance) go through `look_*` like a gamepad right stick, releasing it fires one shot (`shoot` is held until the rifle fires, `aim` until then too); releasing inside `AIM_CANCEL_RADIUS` cancels. A row DUCK/R/VAULT above the aim stick zone (VAULT is dimmed unless `player.vault_available`), FIRE on the left (shoot without turning). No AIM button on touch; DUCK is a toggle. Buttons must stay off the stick zones: a touch that starts on a button presses it instead of steering.
- `MobileUI` and `PauseMenu` live in the `UILayer` CanvasLayer (layer 10), above the weapon HUD: otherwise the scope overlay hid the buttons while they stayed tappable.
- `MobileUI` is active when `GameSettings.is_touch_device()` (mobile/web-mobile features, or `force_touch` for testing on PC).
- `input_devices/pointing/emulate_mouse_from_touch=true`: without it LineEdit and sliders ignore touches on Android (buttons work natively, which hid the bug). Then every touch is also a left click, so on touch devices `GameSettings` removes mouse-button events from game actions (`_apply_touch_input_map`); shooting/aiming there come only from `MobileUI`. Mouse is emulated from one finger only — the first one down when no other touch is active.
- Graphics quality presets (`GameSettings.QUALITY_PRESETS`, Low/Medium/High, pause menu, saved): 3D resolution scale, MSAA, sun shadows on/off, soft-shadow filter, shadow splits, dynamic lights from shots. Default choice is Auto (`QUALITY_AUTO`): starts at Medium on touch devices, High on PC, and `AutoQuality` (`scripts/world/auto_quality.gd`, created by `game_scene`) lowers it one step when the average FPS over a 5 s window is below 45 — down only, the reached level is saved as `auto_quality_level`; re-selecting Auto restarts from the default. Applied by `game_scene._apply_graphics()` at start and on `GameSettings.changed` — don't put render-quality overrides in `project.godot`. Tablet measurements: looking at the ground costs ~3× looking at the sky, i.e. the frame is fill-bound on terrain pixels (shadows, MSAA, resolution). Terrain shader is Lambert without specular for the same reason. Sun `directional_shadow_max_distance = 50`. The HUD FPS counter (pause menu «Показывать FPS», on by default during the prototype, also in release) shows FPS, preset, renderer and 3D resolution. Renderer stays Vulkan Mobile on Android: release builds measured faster than Compatibility on both test devices (Adreno 710 and Mali-G57) — see roadmap. Measure FPS on release builds only (debug is ~20 % slower).
- Match start fades in from black while `Rifle.prewarm_effects()` draws every shot effect once (first-draw shader compile used to hitch the first shot).
- `application/config/quit_on_go_back=false`: Android Back toggles the pause menu in a match.

## Gotchas

- Player mesh is built procedurally in `_build_lowpoly_body()` — no external 3D models for players
- Spawn slots are assigned by the host (`players[id].spawn_index`, first free marker). Markers give only x/z: spawn height comes from `MeshUtils.terrain_height_at()` (same formula as the terrain mesh, no physics query — new collision is not queryable until the next physics step). Players spawn and respawn on the ground, facing the map centre
- Camera: `IsoCamera` is a top_level child of the player, current only for the authority; it never rotates (screen up = −Z), so movement is in world axes, not relative to the character. `PITCH_DEG`/`DISTANCE`/`CAMERA_FOV` are prototype values
- Aiming like Foxhole: while `aim` is held, `aim_progress` goes 0 → 1 over `AIM_TIME` (slower on the move), the spread blends from hip to aimed (`Rifle.get_spread_angle`), the camera looks further ahead, walking drops to `PlayerState.AIM_SPEED`; a shot multiplies progress by `AIM_SHOT_KEEP`. `AimCone` draws the spread cone on the ground for the local player. `aim_point` is at `SHOT_HEIGHT` above the ground under the cursor or along the stick at a distance set by deflection (`STICK_AIM_MIN_DISTANCE`…`STICK_AIM_DISTANCE[_ADS]`); stick turning is smoothed and speed-capped (slower in ADS), the mouse is not. The shot ray goes from `get_shot_origin()` (chest, lower when crouched) to `aim_point`; `sight_point` is `aim_point` clipped by the first wall or slope on layer 1 — the HUD crosshair and `AimCone` use it, so the aim never shows through walls. The first deflection of the stick sets the aim direction at once (no crawling from the old direction); while it is held, turning stays smoothed against finger tremor. On touch the `AimCone` and the HUD crosshair are drawn only while the aim stick is held (`Player.show_aim_indicators()`), on PC always. With the stick released (touch, gamepad) the soldier turns to face his walking direction (`_face_movement`, so sprint and the FIRE button follow where he runs), except while a shot is queued behind the bolt (`aim` still held, `aim_frozen`: the cone no longer narrows after the finger is lifted), and the camera only looks ahead while the stick is held (`has_aim_input()`); the mouse is unchanged. Mouse wins after any mouse motion, the stick after any deflection. The mouse dead zone around the soldier is a few screen pixels (`MOUSE_AIM_DEADZONE_PX`), and with the mouse the camera does not look ahead from the hip (only while aiming) — otherwise cursor and camera fed back into each other and the aim stuck when the cursor crossed the soldier. Sprint only within 60° of the aim direction and not while aiming
- Rifle is Foxhole-like (overrides in `rifle.tscn`): 40 damage (3 hits), 5-round clip, 1.1 s bolt cycle, 2.5 s reload. `_shoot_effects(origin)` RPC plays the shot and, after `BOLT_SOUND_DELAY`, the bolt for every peer at the position passed in the call (a fog-hidden shooter has no synced position, but his gunfire is still heard from the right place). Long sounds (bolt, reload via `_reload_effects`) follow the rifle (`Rifle._sound_anchor()`, `SFXManager._play_at(..., follow)`) so they don't stay behind when you run — except for a fog-hidden shooter, whose sound stays at the start point
- Fog of war: remote players start `fog_hidden`; the host's `VisibilityManager` (range `VIEW_RANGE` + line of sight on layer 1 — terrain and covers) sends each peer its visible list. A hidden player is not drawn and has no collision (no shooting at a stale ghost); each authority sends its own sync only to peers that see it and always to the host (`public_visibility = false`). The host itself sees everyone — a P2P limit until a dedicated server. Peers know whether anyone sees them (`VisibilityManager.is_seen`, HUD «ТЕБЯ ВИДЯТ» / «СКРЫТ»)
- Footsteps are decided by the host too (`VisibilityManager._update_steps`): from everyone's positions (incl. fog-hidden) it sends `play_step` to every peer within `HEARING_RANGE`, so walking behind a wall is heard; slower than `QUIET_SPEED` (crouching, aiming) is silent — that is what crouch is for
- Covers (`game_scene.COVERS`) are StaticBody3D on layer 1, built at runtime; their height counts from the highest ground corner, the box extends down below the lowest one
- `data/` and `resources/` do not exist yet — SQLite persistence is not implemented
- The `addons/godot_mcp` plugin is enabled (Godot MCP integration for AI tools)
- There is no CI, linting, or typecheck pipeline. Headless check: `godot --headless --path . --script tests/spatial_check.gd` (network: run two processes with `-- host` and `-- client`)
- Input check needs a real display (GUI gets no events in `--headless`): `xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/input_check.gd`
- In a match the PC cursor is `MOUSE_MODE_CONFINED_HIDDEN` (the HUD crosshair is drawn at the aim point instead); the pause menu shows it. HUD controls must stay `mouse_filter = IGNORE`
- `NetworkManager.server_disconnected` fires on the client when the host leaves: the menu goes back to browsing, a running match returns to the main menu
- Nicknames: `GameSettings.player_name` (saved), host stores it in `players[id].name`; clients send theirs via `_register_name` RPC right after connecting. Always pass names through `NetworkManager.sanitize_name`
- LAN announces carry a per-session `host_id`; the browser keys lobbies by it so one host reachable via LAN and loopback shows once
- Death (local player only): `DeathScreen` (`scripts/ui/death_screen.gd`, CanvasLayer 5 — above the weapon HUD, below `UILayer`) shows the killer's nick and the respawn countdown; the weapon HUD is hidden
- The lobby list shows nicknames with «хост»/«вы» tags, never peer ids (host is always 1, clients get random ENet ids)
- Match scene is preloaded in a background thread while players sit in the lobby (`MainMenu._preload_game_scene`), and the menu shows «Загрузка матча...» before the switch; the log prints how long the scene took (`Сцена матча получена`, `Мир собран`) — read these when someone reports slow match entry
- Pause menu: «Продолжить» right under the title, «Выйти в меню» at the bottom after a spacer and only on a second press within 3 s (players left matches by accident)
- Pause never sets `get_tree().paused` (network game keeps running); the menu sets `player.input_blocked`
- Player collision shape is duplicated per instance in `_ready` — crouch changes its height
- Movement states (Idle/Walk/Jump) extend `PlayerState`; shooting/reload input is polled only there via `WeaponManager`, not in the weapon
- Lighting, fog and sun live in `game_scene.tscn`, not in code; `GroundBody` has no shape in the scene — its only collision is the terrain trimesh built at runtime

## Design reference

The meta-game (front line, logistics, trenches, player-driven leadership via ranks and regiments — no single commander) is based on **Foxhole**; the camera is top-down like Foxhole too, so Rankborn's difference is a modular weapon designer, PC + mobile crossplay, training-gated ranks and its own faction visuals. Rationale, open questions and the crossplay fairness rules (no aim assist for mouse; slowdown/friction only, never snap, for touch/gamepad; fairness via combat design first) are in `docs/design.md`.

## Reference

- Architecture doc (actual code structure, network flow): `docs/architecture.md`
- Shooting parameters and ideas: `docs/shooting.md`
- Design decisions (Foxhole, crossplay fairness, leadership, era/factions/logistics floor; camera — top-down like Foxhole, prototype criteria in section 3; scale assumption up to 64 players per sector): `docs/design.md`
- Fix plan by phase, with acceptance criteria: `docs/roadmap.md`
- Project description: `README.md` (Russian)
