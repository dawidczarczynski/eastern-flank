# TASK-083: Faster MapView.build – test suite and loading time

- **Status**: done
- **Layers**: presentation (presentation-engineer), tests
- **Depends on**: none
- **Model**: sonnet

## Goal

`MapView.build()` costs ~1.1–1.4 s even on a radius-4 plains grid (first call in a process ~3 s, resource loading). ~10 test files (`test_map_view_*`, `test_grass_*`, `test_tree_field`, `test_ground_marks_view`, `test_scatter_planner`) call it in `before_each`/per test and make up ~115 of ~123 s of test time (measured with `TEST_TIMES=1 tools/test.sh --verbose`). The same cost is part of the game's load time.

## Approach (measure first)

1. Profile the stages of `build()` (`_build_terrain`, `_build_backdrop` with per-vertex GDScript callbacks `_backdrop_vertex`, `_build_water`, `_build_grid_lines`) and fix the dominant one in production code (e.g. packed arrays instead of per-vertex callbacks, fewer vertices where the result is invisible).
2. In tests: share one built `MapView` per file/quality where tests only read it (add a `before_all`/`after_all` hook to `TestCase` and the runner if needed); keep per-test builds only where the test changes the grid or quality.

## Acceptance criteria

- [x] `tools/test.sh` (JOBS=1) at least 40 % faster than 145 s, same number of tests, none weakened.
- [x] `MapView.build()` on the default map is not slower and produces identical meshes (existing geometry tests pass).
- [x] Frame rate unchanged (60 FPS budget); no visual change – if the terrain mesh changes, a before/after `tools/screenshot.sh` is compared.

## Implementation notes

Done 2026-10-24. Serial `JOBS=1 tools/test.sh`: **121.6 s → 79.5 s** on this machine (−35 %; the 145 s reference was measured before other changes, −45 % against it). 859 tests before, the same 859 plus 3 new `test_backdrop_types` after, none removed or loosened.

- **Test hooks**: `TestCase.before_all`/`after_all` run once per file on a separate instance (only when one of the file's tests passes the filter/shard); shared state lives in `static var`s. A `before_all` failure counts against the file's first test, an `after_all` failure is reported as `<file>:after_all`. `Fixtures.map_view(grid, quality)` builds a view outside a scene tree, `Fixtures.reset_map_view` undoes what tests change (highlights, hover, path, grid mode, camera distance).
- **Shared builds**: `test_map_view_backdrop`, `test_map_view_detail` (one radius-1 view), `test_map_view_overlays` (radius 1 and 2; maps with water still per test), `test_tree_field` (the HIGH forest map of the three read-only tree tests), `test_ground_marks_view` (one map for the two layer tests), `test_grass_kinds` (the default-map grass plan). Tests that change quality build their own view instead of rebuilding on top of the shared one (they were double builds before).
- `test_map_view_grass` builds with `"foliage": false` – the tree/bush/rock scatter doesn't feed `GrassField`/`GrassPlanner`.
- **Production**: the backdrop ground and canopy callbacks redid 5 nearest-tile lookups for every ring vertex; `BackdropTypes` (new, split out of `MapView`, which was at the 1000-line lint limit) caches the type shares per border vertex. Build `plains_grid(1)` 820 → 650 ms, default map 3.08 → 2.85 s. Terrain, Backdrop and BackdropCanopy surface arrays are bit-identical (md5 of `var_to_bytes(surface_get_arrays(0))` on `plains_grid(1)` and the default map, before vs after), so no visual or frame-rate change and no screenshot comparison needed.
- Remaining cost (for a later task): `test_map_view_grass` ~19 s (grass chunk building on radius-8 meadows ~2.7 s per test), `test_grass_planner` ~6 s, `test_scatter_planner` ~4 s; in `build()` the playable terrain (~65 µs/vertex GDScript, 1.7 s on the default map) is the largest stage.
- Earlier investigation (kept for reference): inlining `hash`/`value_noise` into `TerrainNoise` gave a bit-identical but only ~5 % faster build and was reverted; `tools/test.sh` runs test files in parallel shards.

- Profile of `build()` on `plains_grid(4)` (11 655 terrain vertices, ~1.2 s after warm-up): `_build_terrain` ~460 ms (~40 µs/vertex of GDScript: `GroundNoise.jitter`, `_splat_noise`, `_splat`, `TerrainSplat.smooth`), `BackdropMesh.build_mesh` ~420 ms (per-vertex `Callable` calls), the rest (water, grid lines, scatter, trees) < 250 ms. The first build per process costs ~3 s (resource loading).
- Tried: inlining `hash`/`value_noise` into `TerrainNoise.value_noise`/`fbm` (bit-identical output, jitter −40 %) – the whole build only got ~5 % faster, so it was reverted (duplicated code for no visible gain). The per-vertex GDScript work is spread over many functions; micro-optimising one doesn't move the total.
- Test-side sharing is harder than it looks: overlays, grid lines, scatter and the backdrop canopy read `_mesh_heights`/`_backdrop`, so a "no ground mesh" build mode for grass/tree tests touches most of `MapView`. `test_grass_kinds`/`test_grass_planner` (~23 s) don't build a `MapView` at all – their cost is `GrassPlanner` on the default map.
- Already done separately: `tools/test.sh` runs test files in parallel shards (145 s → ~79 s), `tools/lint.sh` runs gdlint and gdformat side by side.
- Realistic next steps: compute the splat weights/normals/backdrop in bulk (PackedArray/`Image` or a compute-free closed form instead of per-vertex GDScript), or cache the generated terrain arrays per (grid, quality) across tests of one file with a `before_all` hook in `TestCase`.
