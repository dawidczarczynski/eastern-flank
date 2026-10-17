# TASK-018: Scatter – trees and rocks

- **Status**: ready
- **Layers**: presentation (pure placement planner tested in `tests/unit/`)
- **Depends on**: **TASK-016b** (surface heights). Reference: `docs/design/game_screen.scene.js` lines 351–392.
- **Model**: sonnet

## Goal

Forests read as forests – dense clumps of small conifers and leafy trees – a few lone trees dot the open plains, and hills are strewn with rocks. Purely cosmetic; it must not hide units or change any rule.

## Design values

- **Forest tile**: 30 candidate trees; **plains tile**: with probability 0.5 → 4 candidates, else 0; candidates uniformly inside a circle of radius **0.95** around the tile centre (rejection sampling in the square). A candidate is dropped when `ground_height < 0.05` (shore/water) **or within 0.3 of the tile centre** (deviation from the mock-up: keeps a clearing where the unit stands, so infantry stays visible – confirm in playtest).
- Tree: scale `s = 0.7 + r·0.6`, vertical scale `s·(0.9 + k·0.3)`, yaw `k·6`, base at `ground_height − 0.02`; conifer with probability **0.8** if `ground_height > 0.6`, else **0.35**.
- Meshes (shared, low-poly): conifer = cone (`CylinderMesh`, top 0, bottom radius 0.075, height 0.3, 7 radial segments, centre 0.19 above the base); deciduous = sphere radius 0.085 (8 radial segments, 4 rings, centre 0.14 above the base); trunk = cylinder radii 0.01/0.014, height 0.1, centre 0.05, colour `#4a3b2a`, for every tree.
- Instance colours: conifer `#2c4626 → #3d5a30` by `k`; deciduous `#41602c → #6b7f36` by `k`; material roughness 0.9, metallic 0, `vertex_color_use_as_albedo` (MultiMesh `use_colors`).
- **Hills tile**: 3 rocks, or **8** when the tile elevation is > 1.45 (mock-up "mountain"); positions in radius 0.9; scale `s = 0.5 + r·1.2` → `(s, 0.7·s, s)`, rotation `(s, 3·s, 0)`, base radius 0.05, low-poly sphere (6 radial segments, 3 rings), colour `#7d776a`, roughness 0.95.
- All scatter casts and receives shadows.
- **Randomness**: a *view-local* `RandomNumberGenerator` seeded from the map (e.g. `hash(grid.field offset)` or a constant), **never `GameState.rng`** – consuming the simulation RNG in the view would break determinism (CLAUDE.md rule 4). Same map → same scatter on every run.

## Acceptance criteria (testable)

- [ ] Pure planner `src/presentation/scatter_planner.gd` (`class_name ScatterPlanner`, `extends RefCounted`): `static func plan(grid: HexGrid, surface: TerrainSurface, seed_value: int) -> Dictionary` returning `{"trees": Array[Dictionary], "rocks": Array[Dictionary]}`; a tree is `{position: Vector3, scale: float, height_scale: float, yaw: float, conifer: bool, k: float}`, a rock `{position, scale, rotation: Vector3}`.
- [ ] Tests `tests/unit/test_scatter_planner.gd` on a generated 12×10 map (seed 12345) and on hand-made grids:
  - Determinism: two `plan` calls with the same inputs return equal arrays; a different `seed_value` changes at least one position.
  - Per tile (tile = `Hex.from_world(position)`): FOREST ≤ 30 trees, PLAINS 0 or ≤ 4, HILLS and WATER 0 trees; every tree is ≥ 0.3 and ≤ 0.95 from its tile centre and has `ground_height ≥ 0.05` at its position.
  - Rocks only on HILLS tiles: exactly 3 per tile, or 8 when `grid.elevation(c) > 1.45` (test with a hand-made grid where one HILLS tile has elevation 1.6); all within 0.9 of the centre; `scale` in `[0.5, 1.7]`.
  - Tree `scale` in `[0.7, 1.3]`; on a hand-made map whose forest tiles all have elevation 1.0, ≥ 60 % of trees are conifers (expected 80 %); at elevation 0.3, ≤ 55 % (expected 35 %).
  - Position `y == ground_height(x, z) − 0.02` for trees, `== ground_height` for rocks.
- [ ] `MapView` builds 4 `MultiMeshInstance3D`s (conifer crowns, deciduous crowns, trunks, rocks) from the plan after the terrain mesh; nothing is created per tree as a node.
- [ ] `MapView.build` total time stays < 2 s for the battle map (note the measured number).
- [ ] Agent visual check: take a screenshot with `tools/screenshot.sh` and compare with `docs/design/reference.png`: forest tiles are dense dark-green clumps of cones and blobs, a few trees on plains, grey rocks on hills; units on forest tiles are still visible.

## Playtest (for the human)

1. `tools/run.sh` – forest tiles are covered with small trees; you can still see which hexes are forest.
2. Move infantry into a forest – the soldiers stand in a small clearing and are visible from the default camera.
3. Hills have a few rocks; very high hills have more.
4. Run again – trees and rocks are in exactly the same places.
5. Rotate/zoom around – no noticeable frame-rate drop.

## Out of scope

- Buildings and city scatter: there is no urban terrain yet (follow-up once an urban type exists – GDD "Ideas from the visual design").
- Wind animation, LOD/impostors, trees reacting to units, scatter avoiding roads (no roads).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
