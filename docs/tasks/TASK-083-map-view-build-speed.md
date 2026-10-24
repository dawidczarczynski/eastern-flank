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

_Filled in by the agent when done._
