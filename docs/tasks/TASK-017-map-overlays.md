# TASK-017: Map overlays like the design (reach, hover ring, path dots)

- **Status**: ready
- **Layers**: presentation (pure geometry/curve helpers tested in `tests/unit/`)
- **Depends on**: **TASK-016b** (overlays drape over `TerrainSurface`). Soft: TASK-009 (its attack-target markers are restyled here if it is done), TASK-004 (replaces its path markers). Reference: `docs/design/game_screen.scene.js` lines 131–159 (`patchGeo`, `ringGeo`, `overlayMat`), 430–474 (reach, path dots), 530–541 and 630 (hover ring pulse).
- **Model**: sonnet

## Goal

Selection feedback matches the mock-up and hugs the terrain: the reachable area is a soft wash in the player's colour with thin outlines, the tile under the cursor has a gently pulsing white ring, and the planned route is a line of small white dots ending in a bigger one.

## Design values

| Overlay | Geometry | Colour / opacity | Lift above `ground_height` |
|---|---|---|---|
| Reach fill (each reachable tile, excl. the unit's own) | hex patch, scale **0.9** | faction colour, **0.2** | 0.03 |
| Reach ring | hex ring, radii **0.86–0.92** | faction colour, **0.55** | 0.035 |
| Hover fill (any map tile under the cursor) | patch, scale **0.92** | white, **0.1** | 0.035 |
| Hover ring | ring **0.9–0.98** | white, `0.6 + 0.25·sin(t_ms / 260)` (0.35–0.85, period ≈ 1.63 s) | 0.04 |
| Path dots | spheres r **0.05** (last one ×**1.8**) | white, opaque | 0.1 |
| Attack targets (only if TASK-009 is done) | ring **0.86–0.98** + patch 0.9 | `#e07c5e`, ring 0.9 / fill 0.25 | 0.04 / 0.035 |

- Faction colours: `UiPalette.FACTION` (TASK-014): `#5b93d6`, `#d76a52`.
- Patch: each of the 6 hex triangles subdivided `n = 4`; ring: 6 sides × 5 segments. Corner angles `60°·i − 30°` (pointy-top, same as `Hex.to_world`). Every vertex `y = ground_height(x, z) + lift`, so overlays follow slopes.
- Material: unshaded, transparent, depth test on, **no depth write**, double-sided, not shadow-casting. Godot has no polygon offset: rely on the lifts; if overlays clip into hills on screenshots, raise lifts (≤ 0.06) and note it.
- Path dots: Catmull-Rom curve through the tile centres `[unit tile] + path`, resampled at equal arc length into `n + 1` points with `n = min(80, (tiles − 1)·5)`; the first 2 points (under the unit) are skipped.
- **Path cost label decision**: the TASK-004 `Label3D` (`"2/3"`) stays for now, restyled (white text, Mono font from TASK-014, placed 0.6 above the last dot); it moves into the HUD terrain panel in **TASK-024**, which removes the `Label3D`.

## Acceptance criteria (testable)

- [ ] Pure helper `src/presentation/overlay_geometry.gd` (`class_name OverlayGeometry`, `extends RefCounted`, static):
  - `hex_patch(center: Vector2, scale: float, n: int) -> PackedVector2Array` (triangle list, XZ) and `hex_ring(center: Vector2, r0: float, r1: float, segments: int) -> PackedVector2Array` (triangle list);
  - `drape(points: PackedVector2Array, surface: TerrainSurface, lift: float) -> PackedVector3Array`;
  - `curve_points(centers: PackedVector2Array, count: int) -> PackedVector2Array` – uniform Catmull-Rom (end points duplicated as phantom controls) resampled to `count + 1` points at equal arc length (dense sampling + linear resampling is fine).
  - `path_dot_count(tiles: int) -> int` = `max(0, min(80, (tiles − 1)·5) − 1)` (points after skipping 2).
  - `static func hover_alpha(time_ms: float) -> float`.
- [ ] Tests `tests/unit/test_overlay_geometry.gd` (tolerance 0.001):
  - `hex_patch(c, s, 4)` has `6·16·3 = 288` vertices, all within `s` of `c`; the six corner points `c + s·(cos(60°i − 30°), sin(…))` are among them.
  - `hex_ring(c, 0.86, 0.92, 5)` has `6·5·6 = 180` vertices; every vertex lies on the inner or the outer hexagon outline.
  - `drape` on `Fixtures.plains_grid(2)` with lift 0.03 → every `y == 0.23`.
  - `curve_points([(0,0), (2,0), (4,0)], 10)` → 11 points, first `(0,0)`, last `(4,0)`, all `y == 0`, consecutive distances all `0.4 ± 0.01`.
  - `path_dot_count(3) == 9` (2-tile path: 11 points − 2), `path_dot_count(1) == 0`, `path_dot_count(20) == 79`.
  - `hover_alpha(0) == 0.6`; max over a 2 s sweep ≤ 0.85 and min ≥ 0.35.
- [ ] `MapView` replaces the yellow disc highlight with the reach fill + ring (one merged `ArrayMesh` for all fills and one for all rings – 2 draw calls, rebuilt on change), coloured by the selected unit's owner (`show_reach(coords, player_id)`), and replaces the TASK-004 path markers with the dots (one `MultiMeshInstance3D`, max 80 instances). `clear_highlights()` / `clear_path()` keep their meaning.
- [ ] Hover ring + fill are shown on whatever map tile is hovered (also without a selection, also during the AI turn), hidden off the map; geometry is rebuilt only when the hovered tile changes; the alpha is animated every frame with `hover_alpha(Time.get_ticks_msec())`.
- [ ] No game rules in the view: reach comes from `HexGrid.reachable`, path from `HexGrid.path_to` (as in TASK-004), attack targets from `AttackCommand.valid_targets` (TASK-009).
- [ ] Agent visual check: the default screenshot has no selection, so check what is visible (no leftover yellow discs, no overlay artefacts). If practical, add an optional debug path in the screenshot run (e.g. env var `SCREENSHOT_SELECT_UNIT=1` read by `tools/screenshot.gd` to select unit 1) and compare the reach wash/rings with `docs/design/reference.png`; otherwise leave the comparison to the human.

## Playtest (for the human)

1. Move the mouse over the map – a white hex ring follows the cursor and slowly pulses (about 1.6 s per pulse); it sits on hills without disappearing into them.
2. Select your infantry – reachable tiles get a light blue wash with thin blue outlines (enemy-red would be wrong for your units).
3. Hover a reachable tile – white dots lead from the unit to the tile along a smooth curve, the last dot bigger; the `cost/moves` label is still above it.
4. Hover a tile behind a forest – the dots follow the cheaper route, as before.
5. (If TASK-009 is done) Enemies in range get an orange-red ring.
6. Deselect / move / end turn – all overlays disappear except the hover ring.

## Out of scope

- Unit markers under units (TASK-019), terrain panel and moving the cost label (TASK-024).
- Attack-move previews, threat ranges, animated dots.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
