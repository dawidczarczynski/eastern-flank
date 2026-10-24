# TASK-083: Faster MapView.build – test suite and loading time

- **Status**: ready
- **Layers**: presentation (presentation-engineer), tests
- **Depends on**: none
- **Model**: sonnet

## Goal

`MapView.build()` costs ~1.1–1.4 s even on a radius-4 plains grid (first call in a process ~3 s, resource loading). ~10 test files (`test_map_view_*`, `test_grass_*`, `test_tree_field`, `test_ground_marks_view`, `test_scatter_planner`) call it in `before_each`/per test and make up ~115 of ~123 s of test time (measured with `TEST_TIMES=1 tools/test.sh --verbose`). The same cost is part of the game's load time.

## Approach (measure first)

1. Profile the stages of `build()` (`_build_terrain`, `_build_backdrop` with per-vertex GDScript callbacks `_backdrop_vertex`, `_build_water`, `_build_grid_lines`) and fix the dominant one in production code (e.g. packed arrays instead of per-vertex callbacks, fewer vertices where the result is invisible).
2. In tests: share one built `MapView` per file/quality where tests only read it (add a `before_all`/`after_all` hook to `TestCase` and the runner if needed); keep per-test builds only where the test changes the grid or quality.

## Acceptance criteria

- [ ] `tools/test.sh` (JOBS=1) at least 40 % faster than 145 s, same number of tests, none weakened.
- [ ] `MapView.build()` on the default map is not slower and produces identical meshes (existing geometry tests pass).
- [ ] Frame rate unchanged (60 FPS budget); no visual change – if the terrain mesh changes, a before/after `tools/screenshot.sh` is compared.

## Implementation notes

Investigated 2026-10-24, **no production change kept** – the status stays `ready` for a deeper attempt.

- Profile of `build()` on `plains_grid(4)` (11 655 terrain vertices, ~1.2 s after warm-up): `_build_terrain` ~460 ms (~40 µs/vertex of GDScript: `GroundNoise.jitter`, `_splat_noise`, `_splat`, `TerrainSplat.smooth`), `BackdropMesh.build_mesh` ~420 ms (per-vertex `Callable` calls), the rest (water, grid lines, scatter, trees) < 250 ms. The first build per process costs ~3 s (resource loading).
- Tried: inlining `hash`/`value_noise` into `TerrainNoise.value_noise`/`fbm` (bit-identical output, jitter −40 %) – the whole build only got ~5 % faster, so it was reverted (duplicated code for no visible gain). The per-vertex GDScript work is spread over many functions; micro-optimising one doesn't move the total.
- Test-side sharing is harder than it looks: overlays, grid lines, scatter and the backdrop canopy read `_mesh_heights`/`_backdrop`, so a "no ground mesh" build mode for grass/tree tests touches most of `MapView`. `test_grass_kinds`/`test_grass_planner` (~23 s) don't build a `MapView` at all – their cost is `GrassPlanner` on the default map.
- Already done separately: `tools/test.sh` runs test files in parallel shards (145 s → ~79 s), `tools/lint.sh` runs gdlint and gdformat side by side.
- Realistic next steps: compute the splat weights/normals/backdrop in bulk (PackedArray/`Image` or a compute-free closed form instead of per-vertex GDScript), or cache the generated terrain arrays per (grid, quality) across tests of one file with a `before_all` hook in `TestCase`.
