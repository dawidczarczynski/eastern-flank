# ADR 0002: Terrain definitions as resources with a presentation group

- **Status**: accepted
- **Date**: 2026-10-17

## Context

Terrain numbers lived in code (`src/core/terrain.gd`, colour/height constants in `MapView`). Designers need one place to add and tune a terrain type, and terrain now affects combat (defense bonus).

## Decision

- Each terrain type is a `TerrainDefinition` resource (`src/core/data/terrain_definition.gd`) in `data/terrain/*.tres`.
- Gameplay properties (`move_cost`, `impassable`, `defense_bonus`) and visual ones (`color`, `height`, in `@export_group("Presentation")`) live in the same file: one file per terrain is the single place to tune it. `Color` and `float` add no dependency on nodes, so `src/core` stays pure.
- Rule: core and AI never read the Presentation group; the view layer may read the whole definition.
- `Terrain.Type` stays as the key stored in `HexGrid`; `Terrain.definition(type)` maps it to the resource via a path table (`_PATHS`) and `load()` (cached by Godot). `preload()` is not used: with `Terrain` and `TerrainDefinition` referencing each other, the preloaded constant resolved to a plain `Resource` and the typed return failed. Adding a terrain still needs an enum value.
- The defense bonus is a flat number added to the defender's defense (`AttackCommand.compute_damage`).

## Consequences

- (+) Tuning terrain needs no code changes.
- (+) A single damage function reusable by counterattacks.
- (−) The enum and the `_PATHS` table must be kept in sync when adding a terrain.
- (−) Presentation data sits in a core class, kept harmless by the read rule above.

## Amended by TASK-016b

The Presentation group (`color`, `height`) was removed from `TerrainDefinition` and `data/terrain/*.tres`. The view no longer draws per-tile prisms: one continuous terrain mesh takes its heights from `TerrainSurface` (core elevation) and its colours from `TerrainColors` (`src/presentation/terrain_colors.gd`), which ports the design palette and depends on the terrain type and height. `TerrainDefinition` now holds gameplay data only (`default_elevation` is gameplay data: it drives the surface height on hand-made grids). The read rule above still applies if presentation fields are ever added again.
