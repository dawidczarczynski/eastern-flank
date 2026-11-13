# ADR 0022: Battle loading – threaded scene load, worker threads for pure builders, disk cache

- **Status**: accepted
- **Date**: 2026-11-13
- **Task**: none (performance pass asked for by the human)

## Context

Opening the tactical battle took about 37 s for the default battle (120 hexes) and over 50 s for the Suwałki battle (720 hexes) on the development machine (RX 580, 4 cores, Windows Godot started from WSL, HIGH, 1920×1080). Measured per stage:

| Stage | Default | Cause |
|---|---|---|
| `battle.tscn` load (367 scripts) | ~18 s | Windows reading `\\wsl.localhost`; 2.8 s from a native disk; no loading screen yet, the old scene is frozen |
| `MapView.build` | ~5 s | `TerrainSurface.height_at` = 87 µs per query on a generated map (22 noise octaves in GDScript); ground textures packed from 35 JPGs at every start (~2.5 s) |
| Unit views | ~3.9 s | first model of each kind 0.5–1 s |
| Grass around the camera | ~4.8 s (17 s on Suwałki) | ~1 440 candidates per chunk; `FeatureRibbonPlanner.is_clear` 68 µs per candidate on maps with roads |
| Warm-up | 4.1 s | a fixed 25 ms "calm frame" threshold the scene (27 ms a frame at 1080p) never met, so it always ran into its 4 s limit |

## Decision

1. **The battle scene loads on a ResourceLoader thread behind the loading screen** (`SceneLoader`, used by `Session.change_scene`, the main menu and the contact debug panel). The screen is the same `LoadingScreen` the battle shows while it builds, so the two read as one. The load is not faster, but the window never freezes without a notice.
2. **Pure builders run on the `WorkerThreadPool`**: the terrain mesh rows (`TerrainRows`) and the grass chunk plans of the prebuild (`GrassField.begin_prebuild` / `prebuild_step`). Rule: a task only reads shared state and writes its own slot of a pre-sized `Array`; lazy caches are filled first (`TerrainSurface.prime`, one `is_clear` call). Tests compare the threaded result with the single-thread one. Nodes and MultiMeshes are still made on the main thread.
3. **Nothing that calls the RenderingServer runs on a worker thread while the main thread waits.** Building the unit models on a thread during the map build was tried and **deadlocked** on the D3D12 renderer (headless tests passed): the thread waits for the main thread to flush server calls, the main thread waits for the task. Unit models stay on the main thread.
4. **The grass stands on the drawn mesh.** `GrassField` gets a `BackdropSurface` over `MapView.mesh_height_at` (a lookup in the mesh's height grid) instead of the `TerrainSurface`: cheaper per clump and read-only for the threads.
5. **Packed ground textures are cached on disk** (`TerrainTextures`, `user://cache/terrain_textures_<size>.bin`, ~90 MB at 1024): keyed by the cache version, the look's layer tints and every source file's modification time; read on a worker thread; a stale or damaged file is packed again. Off in the test runner and when the sources are not on disk (exported build).
6. **Warm-up ends when the frame time is steady** (`WarmUp`: a frame is calm when it is fast or within 20 % of the previous one; 8 calm frames), not only when it is under a fixed threshold.
7. **`tools/run_windows.sh --local`** mirrors the game files to `%LOCALAPPDATA%\eastern-flank\run-copy` (a manifest makes repeat starts copy only changed files) and runs from there. Opt-in; the editor always uses the repository.

## Consequences

Measured after the change (same machine, build time after the scene load in brackets):

| Battle | Before | From the WSL path | With `--local` |
|---|---|---|---|
| Default | ~37 s (19 s) | ~27 s (9.2 s) | ~11.5 s (7.1 s) |
| Suwałki | over 50 s (~35 s, partly estimated) | ~34 s (16.1 s) | ~18 s (13.7 s) |

- The terrain mesh is bit-identical to the single-thread build; grass clumps moved by the difference between the surface and the mesh (they now sit exactly on the drawn ground).
- The first start after a texture change still packs the textures and writes the cache.
- Still open: unit models (~3.9 s, main thread), `ScatterPlanner` / `TreeField` / backdrop on Suwałki (~4 s together, serial), and the frame time after loading – 27 ms (37 FPS) at 1920×1080 against the 60 FPS budget (17 ms at 1280×720), not profiled yet.
