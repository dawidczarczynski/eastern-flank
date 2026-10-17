# ADR 0003: Terrain elevation is core data; the noise is ported; the 3D surface is a pure query

- **Status**: accepted
- **Date**: 2026-10-17

## Context

Random per-tile terrain gave salt-and-pepper maps. The visual design (`docs/design/game_screen.scene.js`) builds a continuous landscape from noise and derives terrain types from height and moisture. The 3D view (TASK-016b) needs a continuous surface to put the mesh, units and overlays on, and replays (TASK-005) must regenerate the same map from the seed.

## Decision

- **Elevation is core data.** `HexGrid` stores a per-tile elevation (`set_elevation` / `elevation`); tiles without one fall back to `TerrainDefinition.default_elevation` (a gameplay-group property, not the presentation `height`). The grid also keeps the `TerrainField` it was generated from (`field`, null for hand-made grids).
- **The noise is ported, not `FastNoiseLite`.** `TerrainNoise` is an exact port of the design's `hash`/`vnoise`/`fbm`/`ridged`/`smooth`, so the output matches the design and cannot change between Godot versions. The seed enters only as a world-space offset drawn from the generator's RNG.
- **Terrain types are classified from elevation and moisture** (`MapGenerator.classify`); all generator numbers live in `data/map/terrain_generation.tres` (`TerrainGenerationSettings`).
- **Forcing a tile's terrain clamps its elevation** into the type's band (`MapGenerator.force_terrain`), so a spawn tile forced to plains never shows water under it.
- **The 3D surface is a pure query in core** (`TerrainSurface.height_at` / `ground_height`): the continuous field, plus a correction that fades from full (≤ 0.35 from a tile centre) to none (≥ 0.8, below the hex inradius) where a tile's elevation differs from the field. The view layer samples it; it does not compute heights itself.
- Generation assumes hex size 1.0 (`TerrainField.HEX_SIZE`), the size `MapView` uses.

## Consequences

- (+) Maps form regions (lakes, forests, hill clusters) and are identical for a seed on every run and Godot version.
- (+) Height queries are testable headless; the view and future rules (vision, defense from elevation) share one source of truth.
- (+) Terrain mix is tuned in a resource, not in code.
- (−) A GDScript noise port is slower than `FastNoiseLite`; fine for 120 tiles, `TerrainSurface` caches per-tile centre heights, but dense mesh sampling (TASK-016b) should be measured.
- (−) Changing the noise or the settings changes every generated map (and invalidates the regression pin in `test_terrain_generation.gd`) – that is intentional and must be a deliberate change.
- (−) Anything that changes terrain after generation must use `force_terrain`, not `set_terrain`, or the surface may disagree with the tile type (note for TASK-011's `Scenario`).
