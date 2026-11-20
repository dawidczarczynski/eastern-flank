# TASK-072c: `TerrainSurface.prime()` fills the neighbour offsets (thread-safe planning)

- **Status**: done
- **Layers**: core (`TerrainSurface`), presentation (remove workaround)
- **Depends on**: TASK-072b
- **Model**: sonnet

## Goal

`TerrainSurface.prime()` fills the neighbour-offset static array that imported (authored-elevation) maps use, so chunk planners on several worker threads never fill it lazily at the same time.

## Acceptance criteria (testable)

- [x] After `prime()`, an imported-elevation surface can be queried from several threads without mutating shared state (test: threaded plans equal single-thread plans on an imported map).
- [x] The workaround in `MapView.prime_surface` (TASK-072b) is removed.
- [x] `tools/check.sh` passes.

## Player manual

None.

## Implementation notes

`TerrainSurface.prime()` now calls the new static `_fill_neighbour_offsets()` (also used by `_authored_height`). `MapView.prime_surface` is removed; `MapView`, `GrassField` and `FoliageChunks` call `surface.prime()`. Test `test_prime_fills_neighbour_offsets_and_threaded_queries_match` (4 threads on an authored-elevation grid). check.sh: only load-sensitive timing tests flaked once (pass alone).
