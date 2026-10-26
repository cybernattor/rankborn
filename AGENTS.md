# AGENTS.md

## What this is

Godot 4.7 multiplayer shooter/strategy game. The current build is first-person, but the camera is decided: isometric top-down like Foxhole (roadmap phase 1.5 replaces the first-person code — don't invest in first-person-only features). GDScript only. No C#, no build system outside Godot.

## Running the project

- **Open and run**: Open `project.godot` in Godot Editor → F5
- **No CLI build**: There is no `npm`, `cargo`, or equivalent. All compilation is Godot-side.
- **Export**: Windows x86_64 and Android presets in `export_presets.cfg`; output goes to `export/` (git-ignored)

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
- `SFXManager` → Audio (`scripts/audio/sfx_manager.gd`)
- `GameSettings` → Controls settings and nickname, saved to `user://settings.cfg`; `is_touch_device()` (`scripts/autoload/game_settings.gd`)

**Scene flow**: `main_menu.tscn` → (host or join) → `game_scene.tscn` (spawns players, builds terrain)

**Key scenes**:
- `scenes/shared/player.tscn` → CharacterBody3D player (camera, sync, state machine)
- `scenes/game/game_scene.tscn` → World with terrain, spawn points, players node
- `scenes/weapons/rifle.tscn` → First weapon

**Key scripts**:
- `scripts/player/player_controller.gd` → Look (mouse/gamepad/swipe), aiming, recoil, crouch, input blocking, death; movement lives in `scripts/player/states/` (`PlayerState` base)
- `scripts/world/game_scene.gd` → Player spawning, terrain generation, swipe/pause wiring, host-left handling
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
- Procedural low-poly terrain via `MeshUtils.make_terrain()` with `FastNoiseLite` (seed 42): 60×60 grid, per-vertex colors, flat-shaded faces (`smooth` parameter exists but is off)

## Mobile support

All input goes through Input actions (`move_*`, `shoot`, `aim`, `jump`, `crouch`, `sprint`, `reload`, `pause`, `look_*`). `MobileUI` (`scripts/ui/mobile_ui.gd`) presses the same actions via `Input.action_press`, so states read one input path for keyboard, gamepad and touch. Only the camera swipe (`look_drag` → `player.apply_touch_look`) and the pause button go through signals.

- Layout: floating stick in the bottom-left half (full forward = sprint), big FIRE in the bottom-right corner with DUCK/R/AIM/JUMP on an arc around it (`ARC_BUTTONS`), swipe anywhere free to look, right FIRE also looks while dragged, left FIRE duplicate, AIM/DUCK are toggles on touch. Keep the middle of the right half free: a swipe that starts on a button presses it instead of looking.
- `MobileUI` and `PauseMenu` live in the `UILayer` CanvasLayer (layer 10), above the weapon HUD: otherwise the scope overlay hid the buttons while they stayed tappable.
- `MobileUI` is active when `GameSettings.is_touch_device()` (mobile/web-mobile features, or `force_touch` for testing on PC).
- `input_devices/pointing/emulate_mouse_from_touch=true`: without it LineEdit and sliders ignore touches on Android (buttons work natively, which hid the bug). Then every touch is also a left click, so on touch devices `GameSettings` removes mouse-button events from game actions (`_apply_touch_input_map`); shooting/aiming there come only from `MobileUI`. Mouse is emulated from one finger only — the first one down when no other touch is active.
- Graphics quality presets (`GameSettings.QUALITY_PRESETS`, Low/Medium/High, pause menu, saved): 3D resolution scale, MSAA, sun shadows on/off, soft-shadow filter, shadow splits, dynamic lights from shots. Default choice is Auto (`QUALITY_AUTO`): starts at Medium on touch devices, High on PC, and `AutoQuality` (`scripts/world/auto_quality.gd`, created by `game_scene`) lowers it one step when the average FPS over a 5 s window is below 45 — down only, the reached level is saved as `auto_quality_level`; re-selecting Auto restarts from the default. Applied by `game_scene._apply_graphics()` at start and on `GameSettings.changed` — don't put render-quality overrides in `project.godot`. Tablet measurements: looking at the ground costs ~3× looking at the sky, i.e. the frame is fill-bound on terrain pixels (shadows, MSAA, resolution). Terrain shader is Lambert without specular for the same reason. Sun `directional_shadow_max_distance = 50`. Debug builds show an FPS counter in the HUD.
- Match start fades in from black while `Rifle.prewarm_effects()` draws every shot effect once (first-draw shader compile used to hitch the first shot).
- `application/config/quit_on_go_back=false`: Android Back toggles the pause menu in a match.

## Gotchas

- Player mesh is built procedurally in `_build_lowpoly_body()` — no external 3D models for players
- Spawn slots are assigned by the host (`players[id].spawn_index`, first free marker). Markers give only x/z: spawn height comes from `MeshUtils.terrain_height_at()` (same formula as the terrain mesh, no physics query — new collision is not queryable until the next physics step). Players spawn and respawn on the ground, facing the map centre
- Local player body is rendered shadows-only (`cast_shadow = SHADOWS_ONLY`), fully visible for remote players
- `data/` and `resources/` do not exist yet — SQLite persistence is not implemented
- The `addons/godot_mcp` plugin is enabled (Godot MCP integration for AI tools)
- There is no CI, linting, or typecheck pipeline. Headless check: `godot --headless --path . --script tests/spatial_check.gd` (network: run two processes with `-- host` and `-- client`)
- Input check needs a real display (GUI gets no events in `--headless`): `xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/input_check.gd`
- Mouse look lives in `_input`, not `_unhandled_input`: with a captured cursor it sits at screen centre, and any HUD control there would swallow motion. HUD controls must stay `mouse_filter = IGNORE`
- `NetworkManager.server_disconnected` fires on the client when the host leaves: the menu goes back to browsing, a running match returns to the main menu
- Nicknames: `GameSettings.player_name` (saved), host stores it in `players[id].name`; clients send theirs via `_register_name` RPC right after connecting. Always pass names through `NetworkManager.sanitize_name`
- LAN announces carry a per-session `host_id`; the browser keys lobbies by it so one host reachable via LAN and loopback shows once
- Death (local player only): `DeathScreen` (`scripts/ui/death_screen.gd`, CanvasLayer 5 — above the weapon HUD, below `UILayer`) shows the killer's nick and the respawn countdown; the weapon HUD is hidden; the camera drops to `DEATH_HEAD_Y` and rolls in `_process`, `face_map_center()` resets it on respawn
- The lobby list shows nicknames with «хост»/«вы» tags, never peer ids (host is always 1, clients get random ENet ids)
- Pause never sets `get_tree().paused` (network game keeps running); the menu sets `player.input_blocked`
- Player collision shape is duplicated per instance in `_ready` — crouch changes its height
- Movement states (Idle/Walk/Jump) extend `PlayerState`; shooting/reload input is polled only there via `WeaponManager`, not in the weapon
- Lighting, fog and sun live in `game_scene.tscn`, not in code; `GroundBody` has no shape in the scene — its only collision is the terrain trimesh built at runtime

## Design reference

The meta-game (front line, logistics, trenches, player-driven leadership via ranks and regiments — no single commander) is based on **Foxhole**; Rankborn's difference is 3D shooter combat (not isometric), a modular weapon designer and PC + mobile crossplay. Rationale, open questions and the crossplay fairness rules (no aim assist for mouse; slowdown/friction only, never snap, for touch/gamepad; fairness via combat design first) are in `docs/design.md`.

## Reference

- Architecture doc (actual code structure, network flow): `docs/architecture.md`
- Shooting parameters and ideas: `docs/shooting.md`
- Design decisions (Foxhole, crossplay fairness, leadership, era/factions/logistics floor; camera — decided: isometric top-down like Foxhole, fixed angle, twin-stick aiming, fog of war decided by the host; prototype criteria in section 3; scale assumption up to 64 players per sector): `docs/design.md`
- Fix plan by phase, with acceptance criteria: `docs/roadmap.md`
- Project description: `README.md` (Russian)
