# ADR 0029: Continuous tactical space; hexes stay on the operational layer for now

- **Status**: accepted (tactical layer); operational layer open (see TASK-214)
- **Date**: 2026-11-22
- **Task**: TASK-205 … TASK-213, TASK-214 (builds on ADR 0018 maps from real geography, ADR 0028 hexes are mechanics only)

## Context

Hexes limit the player's decisions in a tactical battle: units stand only on tile centres, move along tile-to-tile paths, ranges are counted in tiles. The human's decision (2026-11-22): the battle stays turn-based (orders are given, then executed), but positions, movement and ranges become continuous – units are placed freely, move along smooth paths and every unit's range is drawn as a smooth shape.

A survey of the code showed that the tactical rules depend on the hex grid through a narrow core: `Hex` (78 lines), `HexGrid` (205, terrain + Dijkstra), `LineOfSight` (62), `MoveUnitCommand`, `AttackCommand` / `CombatForecast` (`Hex.distance` in 5 places), `Unit.coord`, `GameState` (occupancy, smoke, objectives), `BattleRules` and `AiPlayer`. The terrain data is already metric (`elevation_m`, `metres_per_world_unit()`, `LandCover` raster at 16 m, `TerrainSurface` height at any point), and the operational layer (`src/core/operational/`, 5 km hexes) also uses `HexGrid` / `Hex`, with hex-defined rules (control, contact, front line, objectives).

## Decision

1. **Tactical positions are continuous**: `Unit.position` is a `Vector2` in metres on the battle map plus a facing. Every write goes through `TacticalSpace.snap` (1 cm grid) so replays and comparisons are exact; costs and budgets stay integers (fixed-point). Same determinism rule as today (rule 4, `GameState.rng` only).
2. **`TacticalMap` replaces `HexGrid` in the battle.** A pure core type: terrain / land cover / height / roads / rivers queried at a point, built from the same imported data. `GameState.grid` becomes `GameState.map`. `Hex` and `HexGrid` are **not deleted**: the operational layer keeps using them.
3. **Movement**: path = A* over a hidden fine navigation grid derived from the terrain (cell ~ 8-16 m, step cost from terrain, road and river), then smoothed (string pulling). The budget is spent per metre of path times the cost along it. The reachable area (isochrone) is computed by the same search and is what the player sees.
4. **Range and fire**: ranges are metres in `UnitDefinition` (`data/**/*.tres` converted from hexes with the tactical tile pitch); distance is Euclidean; LOS is a ray over the height and obstacle data (the logic of `LineOfSight` already works in metres).
5. **Occupancy** is by circles (footprint radius per unit definition, minimum spacing), not by one unit per tile. Objectives, smoke and dig-in cover are circles / areas.
6. **Orders stay turn-based**; execution becomes stepped: a move is simulated in fixed steps so a move can be interrupted when an enemy enters range or sight (the interrupt rules are part of TASK-208).
7. **Cutover in one line of commits, not a long dual mode**: TASK-205 … 207 add the new types beside the old ones (nothing switches); TASK-208 switches the core, TASK-209 the AI, TASK-210 … 212 the presentation, TASK-213 removes the tactical hex code and updates the docs.
8. **Operational layer: decided later (TASK-214).** Direction (not yet a commitment): one world for both scales – formations with positions in metres in the same projection as the tactical maps, contact = distance, control as an influence raster. Open questions are listed in TASK-214. Until then the tactical battle must not block that: positions are in the shared UTM-based metre frame of the imported maps.

## Consequences

- (+) Free placement, smooth movement tracks, honest range shapes; no tile-shaped artefacts under the real-scale look.
- (+) Terrain data and `LandCover` are already metric, so the look code (scatter, grass, ribbons) can read terrain at a point instead of through hexes.
- (−) Big change: ~10 core files, `AiPlayer`, a large part of `src/presentation/`, and the tactical tests (operational tests stay). The AI must pick positions from sampled candidates instead of tiles.
- (−) Balance data in hexes (ranges, movement points, unit stats, scenario placement) must be converted; matches (`tools/simulate.sh`) are re-balanced afterwards.
- (−) Pathfinding and raycasts are more expensive than hex Dijkstra; budgets and caching are part of TASK-206 (the AI loop must stay fast, `tools/check.sh --full` time must not grow noticeably).
- (−) Replays and saves from before the cutover stop loading (the command format changes, see TASK-208).
