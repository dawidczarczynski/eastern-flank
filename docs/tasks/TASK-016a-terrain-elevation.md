# TASK-016a: Deterministic terrain elevation in core

- **Status**: ready
- **Layers**: core (+ data; one-line change in `BattleController` spawns)
- **Depends on**: nothing hard. Recommended after TASK-002 (both touch terrain; no code conflict expected). Required by TASK-016b, -017, -018, -019, -022, -024. Reference: `docs/design/game_screen.scene.js` lines 7–16 (noise), 41–59 (`terr`), 81–95 (`buildHexes`).
- **Model**: opus

## Goal

The map stops being random tiles and becomes a landscape: lakes, rolling lowlands, forests where it is wet, hills where the ground rises – generated from the map seed, identical on every run, and exposed as a pure "height at any world point" query so the 3D view (TASK-016b) can build a continuous surface and put units and overlays on it.

## Why split from TASK-016b

Porting the noise, generation and surface query with tests is a full session on its own; the mesh/visual half (TASK-016b) can then be judged against a stable, tested height function.

## Design decisions

- **Port the mock-up's noise** (`hash`/`vnoise`/`fbm`/`ridged`/`smooth`) instead of using `FastNoiseLite`: the output then matches the design's look, and it can't change between Godot versions (replays / TASK-005 must regenerate the same map from the seed).
- **Only the current 4 terrain types.** The mock-up's `mountain` maps to HILLS (it still *looks* rocky/snowy because the colouring is height-based, TASK-016b); `field` maps to PLAINS; `urban`, rivers, roads and the coast mask are not ported (GDD "Ideas from the visual design").
- **No coast on a map edge** (the mock-up's `land` mask puts sea on the west edge, where our player 0 spawns). Water comes from a separate "lake" noise instead.
- The seed enters as a world-space **offset** drawn from the generator's `rng`; the noise functions themselves are fixed.
- Terrain is generated with **hex size 1.0** (the size `MapView` uses); all world coordinates in this task assume it (`TerrainField.HEX_SIZE = 1.0`).
- Every number of the generator lives in a resource (`data/map/terrain_generation.tres`) – it decides the terrain mix, i.e. it is balance data.

## Acceptance criteria (testable)

- [ ] `src/core/terrain_noise.gd` – `class_name TerrainNoise`, `extends RefCounted`, static, exact ports of the mock-up:
  - `hash(x, y, s) = frac(sin(x·127.1 + y·311.7 + s·74.7) · 43758.5453)` with `frac(h) = h − floor(h)`;
  - `value_noise(x, y, s)` (smoothstep-interpolated lattice of `hash`), `fbm(x, y, s = 0.0, octaves = 5)` (amplitude 0.5 halving, frequency × 2.03, seed `s + i·13`, normalised by the amplitude sum), `ridged(x, y, s)` (4 octaves, `1 − |2n − 1|`, frequency × 2.1, seed `s + i·7`), `smooth(a, b, x)` (clamped smoothstep, works with `a > b`).
- [ ] `src/core/data/terrain_generation_settings.gd` – `class_name TerrainGenerationSettings`, `extends Resource`, and `data/map/terrain_generation.tres` with these starting values (to be tuned until the distribution tests pass; final values go into the GDD "Map" section):

  | group | export | value |
  |---|---|---|
  | height | `base_height` | 0.2 |
  | | `hills_frequency`, `hills_gain`, `hills_weight` | 0.11, 2.4, 0.85 |
  | | `mountain_mask_frequency`, `mountain_mask_from`, `mountain_mask_to` | 0.05, 0.62, 0.85 |
  | | `mountain_frequency`, `mountain_gain` | 0.17, 2.1 |
  | | `lake_frequency`, `lake_from`, `lake_to`, `lake_depth` | 0.09, 0.6, 0.75, 1.0 |
  | | `detail_frequency`, `detail_amplitude` | 0.7, 0.07 |
  | moisture | `moisture_frequency` | 0.13 |
  | classification | `water_level`, `hills_level`, `forest_moisture`, `highland_forest_moisture` | 0.02, 0.7, 0.61, 0.66 |
  | forcing bands | `land_min`, `land_max`, `hills_min`, `hills_max`, `water_min`, `water_max` | 0.12, 0.7, 0.71, 2.2, −0.75, −0.05 |

- [ ] `src/core/terrain_field.gd` – `class_name TerrainField`, `extends RefCounted`, `_init(settings: TerrainGenerationSettings, offset: Vector2)`. With `X = x + offset.x`, `Z = z + offset.y`:
  - `height(x, z) = base + hills·hills_weight + mount + detail − lake`, where `hills = max(0, fbm(X·hf + 11, Z·hf − 4, 5) − 0.5) · hills_gain`, `mz = smooth(mm_from, mm_to, fbm(X·mmf, Z·mmf, 9))`, `mount = mz · (0.35 + ridged(X·mf, Z·mf, 21)) · mountain_gain`, `lake = smooth(lake_from, lake_to, fbm(X·lf + 40, Z·lf, 3)) · lake_depth`, `detail = (fbm(X·df, Z·df, 33, 3) − 0.5) · detail_amplitude`;
  - `moisture(x, z) = fbm(X·moisture_frequency + 50, Z·moisture_frequency + 20, 77)`.
- [ ] `HexGrid` gains `var field: TerrainField` (null for hand-made/test grids), `set_elevation(c, e)` and `elevation(c) -> float` (stored value; if never set, a per-type default from `Terrain.default_elevation(t)`: PLAINS 0.2, FOREST 0.25, HILLS 0.9, WATER −0.3; off the map 0.0). Existing behaviour of `HexGrid` is unchanged (all current tests pass).
- [ ] `MapGenerator`:
  - `generate(width, height, rng, settings := <preloaded default .tres>)` keeps its signature for existing callers; it draws the offset as `Vector2(rng.randf_range(-1000, 1000), rng.randf_range(-1000, 1000))`, creates the `TerrainField`, and for every tile sets `elevation = field.height(center)` and `terrain = classify(elevation, field.moisture(center), settings)` (`center = Hex.to_world(c, 1.0)`).
  - `static func classify(h, moisture, settings) -> Terrain.Type`: `h < water_level` → WATER; `h > hills_level` → FOREST if `moisture > highland_forest_moisture` else HILLS; `moisture > forest_moisture` → FOREST; else PLAINS.
  - `static func force_terrain(grid, c, t, settings := default)` sets the terrain **and** clamps the tile's elevation into the type's band (PLAINS/FOREST → `[land_min, land_max]`, HILLS → `[hills_min, hills_max]`, WATER → `[water_min, water_max]`), so the 3D surface never shows water under a land tile.
  - `BattleController._spawn_start_units` uses `force_terrain(..., Terrain.Type.PLAINS)` instead of `set_terrain`.
- [ ] `src/core/terrain_surface.gd` – `class_name TerrainSurface`, `extends RefCounted`, `_init(grid: HexGrid)`:
  - `height_at(x, z) -> float`: let `c = Hex.from_world((x, 0, z), 1.0)`. If `grid.field == null`: `grid.elevation(c)` on the map, `0.0` off it. Otherwise `raw = field.height(x, z)`; off the map → `raw`; on the map → `raw + w · (grid.elevation(c) − field.height(center_c))` with `w = smooth(0.8, 0.35, distance(p, center_c))` (full correction within 0.35 of the centre, none beyond 0.8 – below the hex inradius 0.866, so the surface stays continuous across hex edges). Per-hex `field.height(center)` is cached.
  - `ground_height(x, z) = max(height_at(x, z), WATER_SURFACE)` with `const WATER_SURFACE := 0.0` (what units, overlays and picking sit on).
- [ ] Tests `tests/unit/test_terrain_noise.gd`:
  - `hash(0, 0, 0) == 0.0`; 1000 hashes of integer triples are all in `[0, 1)`; `value_noise(3, 5, 1) == hash(3, 5, 1)` (lattice point); 500 `fbm` samples are in `[0, 1]`; `smooth(0, 1, 0.5) == 0.5`, `smooth(0, 1, -1) == 0`, `smooth(0, 1, 2) == 1`, `smooth(1, 0, 0.25) == 0.84375`.
- [ ] Tests `tests/unit/test_terrain_generation.gd`:
  - `classify` boundaries (default settings): (0.0, 0.5) WATER; (0.019, 0.9) WATER; (0.02, 0.5) PLAINS; (0.3, 0.61) PLAINS; (0.3, 0.62) FOREST; (0.7, 0.5) PLAINS; (0.71, 0.5) HILLS; (0.71, 0.67) FOREST; (2.0, 0.1) HILLS.
  - Determinism: two `generate(12, 10, rng(12345))` → identical terrain and elevation on all 120 tiles; seeds 1 and 2 differ in terrain on ≥ 12 tiles.
  - Consistency: on a generated map every tile satisfies `elevation(c) == field.height(center)` and `classify(elevation(c), field.moisture(center)) == get_terrain(c)`.
  - `force_terrain`: elevation −0.4 → PLAINS gives 0.12; 0.35 → PLAINS stays 0.35; 1.2 → PLAINS gives 0.7; 0.3 → WATER gives −0.05; 0.3 → HILLS gives 0.71.
  - Distribution over seeds 1–50 (12×10, default settings): water 3–15 % of all tiles, forest 10–30 %, hills 5–25 %, plains ≥ 40 %; in ≥ 45 of the 50 maps the largest connected group of non-water tiles holds ≥ 90 % of the non-water tiles (no armies cut off by lakes).
  - Regression pin: terrain + elevation (3 decimals) of tiles `(0,0)`, `(5,4)`, `(10,9)` (offset coords) for seed 12345, captured once after tuning.
- [ ] Tests `tests/unit/test_terrain_surface.gd`:
  - Generated map (seed 12345): `height_at(center) == elevation(c)` for all tiles (tolerance 1e-6); for 50 points from a seeded RNG inside the map `height_at == field.height` (no forced tiles → no correction).
  - After `force_terrain` of a tile with elevation < 0 to PLAINS: `height_at(center) == 0.12`; at 0.3 from the centre the full correction applies; at 0.82 from the centre `height_at == field.height` exactly.
  - `Fixtures.plains_grid(2)` (no field): `height_at` at the centre of `(0, 0)` == 0.2; `ground_height` far off the map == 0.0; a point over a WATER tile with default elevation −0.3 → `height_at == -0.3`, `ground_height == 0.0`.
- [ ] GDD "Map" section describes the elevation-based generation and the final settings; an ADR (next free number in `docs/adr/`) records "terrain elevation is core data; the noise is ported, not `FastNoiseLite`; the 3D surface is a pure query in core".
- [ ] No visual change yet except that the tile layout/types differ (the old prisms are still used; their heights stay per-type until TASK-016b). Agent visual check: take a screenshot with `tools/screenshot.sh` – expect contiguous lakes/forest/hill regions instead of salt-and-pepper tiles; spawn tiles are plains.

## Playtest (for the human)

1. `tools/run.sh` – terrain forms regions (a lake or two, forest patches, hill clusters) instead of random noise; all six units stand on plains.
2. Run again – exactly the same map.
3. Play a turn – movement costs behave as before (forest/hills 2, water impassable).

## Out of scope

- The heightmap mesh, water plane, grid lines, picking on the surface (TASK-016b).
- Rivers, roads, urban/mountain/field terrain types, map size change (GDD "Ideas from the visual design").
- Elevation affecting rules (defense, vision) – open question.
- TASK-011's `Scenario` must use `force_terrain` for spawn tiles when it moves the spawns into core (note for that task).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
