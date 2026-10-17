# TASK-016b: Continuous terrain mesh, water plane, grid lines, surface picking

- **Status**: done
- **Layers**: presentation (pure colour function tested) + core (pure surface raycast tested)
- **Depends on**: **TASK-016a** (elevation, `TerrainSurface`). Soft: TASK-013 (judge colours under the final light), TASK-015 (default framing). Reference: `docs/design/README.md` ("Terrain colours"), `docs/design/game_screen.scene.js` lines 278–330 (terrain mesh, colours, water, grid lines) and 519–529 (`pickGround`).
- **Model**: opus

## Goal

The hex prisms are replaced by one continuous, softly lit landscape coloured like the mock-up – deep water to shoal to sand, grass, dark forest, ochre hills, grey rock and snow on the highest peaks – with a faint hex grid drawn on the ground and a translucent water surface. Units stand on the ground, and the mouse picks the tile actually under the cursor on slopes.

## Design values

- Mesh: a regular grid covering the map bounds (`CameraMath.map_bounds` if TASK-015 is done, else the same formula) **plus 6 units** on every side (`EXTENT = 6`), `RESOLUTION = 5` vertices per world unit (the mock-up uses 9 and 6; 5 keeps the GDScript build fast – raise if the build time allows). Vertex height = `TerrainSurface.height_at` (not clamped: lake beds go below the water plane).
- Material: `StandardMaterial3D`, `vertex_color_use_as_albedo = true`, roughness 0.95, metallic 0, receives and casts shadows. Colours are mixed in **linear** space like three.js (convert the sRGB palette with `srgb_to_linear()` once), `vertex_color_is_srgb = false`.
- Palette (sRGB): deep `#17323b`, shoal `#5d8778`, sand `#c6b78a`, grass `#627c33` / `#87974b`, forest `#46672f` / `#587a38` (lightened from the mock-up's `#2f4a26` / `#3f5a2d`, see implementation notes), hill `#837b50`, rock `#756e5e` / `#a29c8f`, snow `#eef0ef`.
- Colour per vertex (port of the mock-up, `k = fbm(x·0.35, z·0.35, 61, 3)`, `ny` = normal Y):
  - `y < 0.03`: `deep → shoal` by `smooth(−0.7, −0.05, y)`, then `→ sand` by `smooth(−0.06, 0.03, y)`;
  - else: `grass1 → grass2` by `smooth(0.35, 0.7, k)`; if the tile at the **jittered** position (`x + (fbm(x·0.8, z·0.8, 71, 2) − 0.5)·0.55`, `z + (fbm(x·0.8 + 9, z·0.8, 72, 2) − 0.5)·0.55`) is FOREST: lerp to `forest1 → forest2 (by k)` by 0.85; then `→ sand` by `smooth(0.16, 0.04, y)`; `→ hill` by `smooth(0.6, 1.1, y)·0.6`; `→ rock1/rock2 (by k)` by `min(1, smooth(0.18, 0.42, 1 − ny) + smooth(1.3, 1.8, y)·0.85)`; `→ snow` by `smooth(1.85, 2.15, y + (k − 0.5)·0.35) · smooth(0.55, 0.8, ny)`;
  - finally `× (0.88 + k·0.24)`, and `× 0.6` when the vertex is not on a map tile (darkened border).
  - Field stripes and urban colouring from the mock-up are not ported (no such terrain).
- Water plane: at `y = 0`, size = mesh size + 80, colour `#2c5866`, roughness 0.12, metallic 0.25, alpha **0.84**, receives shadows.
- Grid lines: every tile's 6 edges, each split into 5 segments, vertices at `ground_height + 0.025`, colour `#0d120c` at alpha **0.2**, unshaded, no depth write; one `ArrayMesh` with `PRIMITIVE_LINES` for the whole map.

## Acceptance criteria (testable)

- [ ] Pure colour function `src/presentation/terrain_colors.gd` (`class_name TerrainColors`, `extends RefCounted`): `static func color_at(y: float, normal_y: float, k: float, jittered_type: int, on_map: bool) -> Color` (linear colour; `jittered_type` is a `Terrain.Type` or `-1` off the map). Tests `tests/unit/test_terrain_colors.gd` (tolerance 0.002, compare in linear space):
  - `(−1.0, 1, 0.5, WATER, true)` == deep (multiplier `0.88 + 0.5·0.24 = 1.0`);
  - `(−1.0, 1, 0.5, WATER, false)` == deep × 0.6;
  - `(2.5, 1, 0.5, PLAINS, true)` == snow;
  - `(0.3, 1, 0.5, PLAINS, true)` == `grass1.lerp(grass2, smooth(0.35, 0.7, 0.5))`;
  - `(0.3, 1, 0.5, FOREST, true)` == the grass colour above `.lerp(forest1.lerp(forest2, 0.5), 0.85)`;
  - `(0.3, 0.5, 0.5, PLAINS, true)` (steep slope, `1 − ny = 0.5`) == fully rock: `rock1.lerp(rock2, 0.5)`.
- [ ] Pure picking in core: `TerrainSurface.raycast(origin: Vector3, direction: Vector3) -> Variant` (port of `pickGround`: returns `null` when `direction.y >= 0`; starts where the ray is at `y = 3.0` (or at the origin if lower), steps 0.25 for up to 120 units, then 8 bisection steps against `ground_height`; returns the hit `Vector3`). Tests in `tests/unit/test_terrain_surface.gd`, flat `Fixtures.plains_grid(3)` (ground 0.2):
  - origin `(0, 10, 0)`, direction down → hit within 0.01 of `(0, 0.2, 0)`;
  - origin `(−5, 5.2, 0)`, direction `normalize(1, −1, 0)` → hit `x` within 0.01 of 0;
  - direction `(0, 1, 0)` and `(1, 0, 0)` → `null`;
  - a ray that lands far off the map hits the water surface (`y ≈ 0.0`).
- [ ] `MapView.build(grid)` builds the terrain mesh, water plane and grid lines as described (prism tiles and the per-tile tree cones are removed; trees come back in TASK-018). `MapView` owns one `TerrainSurface` for the grid and exposes `surface() -> TerrainSurface`.
- [ ] `MapView.tile_top_position(c)` returns `(center.x, surface.ground_height(center), center.z)`; units, the TASK-004 path markers/label and movement highlights use it (highlights may still be flat discs until TASK-017). `PICK_HEIGHT`, `TERRAIN_COLORS` and `TERRAIN_HEIGHTS` are removed from `MapView`.
- [ ] `BattleController._pick_hex` uses `TerrainSurface.raycast` + `Hex.from_world`; off-map hits still return `null`.
- [ ] If TASK-002 is done: the `height` presentation field (and `color`, if nothing reads it any more) is removed from `TerrainDefinition` and `data/terrain/*.tres`, and its ADR gets an "Amended by TASK-016b" note. If TASK-002 is not done yet, add a note to its task file that the presentation group is no longer needed.
- [ ] Build time: `MapView.build` for the 12×10 battle map takes < 1.5 s (measure with `Time.get_ticks_msec()`, write the number in the implementation notes; lower `RESOLUTION` or cache noise if slower).
- [ ] Headless smoke run (scene driven until `game_over`) still has no script errors.
- [ ] Agent visual check: take a screenshot with `tools/screenshot.sh` (use `--frames=30` if the first frames are still building) and compare with `docs/design/reference.png` / the palette above: continuous terrain, no visible hex prisms, sandy shores around lakes, translucent blue-green water, dark forest patches, ochre-to-grey hills, faint dark hex lines, darker border outside the map; units stand on the ground (no floating or sunk capsules).

## Playtest (for the human)

1. `tools/run.sh` – the map is a continuous landscape; hex outlines are faint but visible on grass.
2. Zoom in on a lake shore – sand fades into shallow then deep water under a translucent surface.
3. Look at high hills – steep sides are grey rock; if any peak is very high it has white snow.
4. Hover and click tiles on a slope – the selected/highlighted tile is the one under the cursor (not one shifted up/down the slope).
5. Units stand on the surface at every height; moving a unit up a hill doesn't leave it floating or buried at the end of the move.
6. Startup time feels about the same as before (no multi-second freeze).

## Out of scope

- Draped overlays (reach/hover/path) – TASK-017; trees and rocks – TASK-018; unit models – TASK-019.
- Roads, rivers, cities, field stripes (no such terrain), water shader/waves, LOD/chunking.

## Implementation notes

Logic part:

- `TerrainSurface.raycast(origin, direction)` ports `pickGround`: it normalises the direction, returns null when it points up or sideways, starts at `y = 3`, marches in 0.25 steps up to 120 units and then bisects 8 times against `ground_height`. Tests cover a flat grid, the water, and a hill on a generated map (seed 6).
- `TerrainColors` (pure, presentation): `color_at` returns a linear colour; the palette is converted from sRGB once. `noise_k` and `jitter` are helpers for the per-vertex inputs, with the noise seeds as named constants.

Visual part (presentation):

- `MapView.build(grid)` creates one `TerrainSurface` (`surface()`), then three nodes under the tiles root: `Terrain` (an `ArrayMesh` built from packed arrays over `CameraMath.map_bounds` grown by `EXTENT = 6`), `Water` (`PlaneMesh` at `y = 0`, mesh size + 80) and `GridLines` (one `PRIMITIVE_LINES` `ArrayMesh`, 6 edges × 5 segments per tile). Hex prisms and tree cones are gone.
- Normals come from central differences on the height grid (computed before colouring, as `color_at` needs `normal_y`); colours from `TerrainColors.color_at` with `noise_k`, the tile type at `jitter(x, z)` and `on_map` of the vertex itself.
- **`RESOLUTION = 3`, not 5.** `TerrainField.height` costs ~75 µs per call in GDScript (`noise_k` ~9 µs, `jitter` ~15 µs, `color_at` ~4.5 µs), so at 5 vertices/unit (~23.5k vertices) the build took ~3.5 s. At 3 (~10.5k vertices) `MapView.build` takes **~1.0 s** for the 12×10 battle map (headless, 3 runs: 1039/1035/987 ms).
- Grid line heights are interpolated on the terrain mesh triangles (same diagonal split as the mesh, clamped to the water surface) instead of calling `ground_height` 7,200 times (~0.6 s). The lines sit exactly on the drawn mesh.
- `tile_top_position(c)` = tile centre at `surface.ground_height`; units, highlights, attack markers, path markers and the path label use it. `PICK_HEIGHT` was removed; `BattleController._pick_hex` uses `surface().raycast` + `Hex.from_world` (null on miss or off the map).
- TASK-002 presentation fields `color`/`height` were removed from `TerrainDefinition` and `data/terrain/*.tres` (nothing read them any more); ADR 0002 got an "Amended by TASK-016b" note.

Known limitations:

- The mesh is coarser than the design (3 vs 6 vertices/unit), so it can differ from `TerrainSurface.ground_height` by a few centimetres between vertices: units/markers (exact surface) may sit slightly above or below the drawn mesh on rough slopes. Raising the resolution needs a faster `TerrainField.height` (e.g. caching or a C++/shader port) or building the mesh on worker threads.
- Vertex colours are stored as 8-bit, so in linear space the darkest water colours may band slightly.
- **Deviation – lighter forest palette** (after playtest feedback "looks like fog of war"): the mock-up's forest `#2f4a26`/`#3f5a2d` is ~3× darker than grass in linear light and ACES crushes it to near-black; the mock-up hides that under trees. Now `#46672f`/`#587a38`. Raising the TASK-013 light (ambient 0.55, sun 1.1) was tried first and barely helped the forest, so the light was left as it was. Re-check after TASK-018 adds trees (the ground under trees may then be darkened again).

