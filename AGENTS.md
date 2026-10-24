# AGENTS.md

## What this is

Godot 4.6+ multiplayer FPS/strategy game. GDScript only. No C#, no build system outside Godot.

## Running the project

- **Open and run**: Open `project.godot` in Godot Editor → F5
- **No CLI build**: There is no `npm`, `cargo`, or equivalent. All compilation is Godot-side.
- **Export**: Windows x86_64 via `export_presets.cfg` → `export/windows/Rankborn.exe`

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

**Scene flow**: `main_menu.tscn` → (host or join) → `game_scene.tscn` (spawns players, builds terrain)

**Key scenes**:
- `scenes/shared/player.tscn` → CharacterBody3D with FPS controller
- `scenes/game/game_scene.tscn` → World with terrain, spawn points, players node
- `scenes/weapons/rifle.tscn` → First weapon

**Key scripts**:
- `scripts/player/player_controller.gd` → Movement, aiming, recoil, death/respawn, mobile input
- `scripts/world/game_scene.gd` → Player spawning, terrain generation, mobile UI wiring
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
- Procedural low-poly terrain via `MeshUtils.make_terrain()` with `FastNoiseLite` (seed 42)

## Mobile support

Touch input is routed through `MobileUI` → `game_scene.gd` → `player_controller.gd`'s `_on_mobile_input()`. Virtual joysticks handle movement and look. The `MobileUI` scene is toggled based on `DisplayServer.is_touchscreen_available()`.

## Gotchas

- Player mesh is built procedurally in `_build_lowpoly_body()` — no external 3D models for players
- Spawn positions are deterministic: `absi(peer_id) % spawn_count`
- Local player body is rendered shadows-only (`cast_shadow = SHADOWS_ONLY`), fully visible for remote players
- `data/` and `resources/` do not exist yet — SQLite persistence is not implemented
- The `addons/godot_mcp` plugin is enabled (Godot MCP integration for AI tools)
- There is no CI, linting, or typecheck pipeline. Headless check: `godot --headless --path . --script tests/spatial_check.gd` (network: run two processes with `-- host` and `-- client`)
- Movement states (Idle/Walk/Jump) extend `PlayerState`; shooting/reload input is polled only there via `WeaponManager`, not in the weapon
- Lighting, fog and sun live in `game_scene.tscn`, not in code; `GroundBody` has no shape in the scene — its only collision is the terrain trimesh built at runtime

## Design reference

The meta-game (front line, logistics, trenches, hierarchy) is based on **Foxhole**; Rankborn's difference is FPS combat, a modular weapon designer and PC + mobile crossplay. See `README.md`.

## Reference

- Architecture doc: `docs/architecture.md`
- Project description: `README.md` (Russian)
