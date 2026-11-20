# TASK-072c: `TerrainSurface.prime()` fills the neighbour offsets (thread-safe planning)

- **Status**: ready
- **Layers**: core (`TerrainSurface`), presentation (remove workaround)
- **Depends on**: TASK-072b
- **Model**: sonnet

## Goal

`TerrainSurface.prime()` fills the neighbour-offset static array that imported (authored-elevation) maps use, so chunk planners on several worker threads never fill it lazily at the same time.

## Acceptance criteria (testable)

- [ ] After `prime()`, an imported-elevation surface can be queried from several threads without mutating shared state (test: threaded plans equal single-thread plans on an imported map).
- [ ] The workaround in `MapView.prime_surface` (TASK-072b) is removed.
- [ ] `tools/check.sh` passes.

## Player manual

None.

## Implementation notes

_Filled in by the agent when done._
