# TASK-135: Vegetation at real scale – real density, impostors / canopy shells, distance budgets

- **Status**: ready
- **Layers**: presentation (`TreeField`, `ScatterPlanner`, `BackdropCanopy`, grass / bush layers, `VisualScale`)
- **Depends on**: – (soft: TASK-072, TASK-134, TASK-110)
- **Sections**: GDD "Visual direction", "Open questions" (Realistic scale); ADR 0021
- **Model**: opus (performance budgets, LOD, determinism of scatter)

## Goal

With trees at real size (`true` preset) forests still read as forests: real density (~2 000 trees per forest hex) through impostors and canopy shells, with distance budgets so Suwałki keeps its frame time. Overlaps TASK-072 (distance budgets for large maps): reuse its benchmark and budgets if it lands first, otherwise this task introduces the vegetation part and TASK-072 builds on it.

## Acceptance criteria (testable)

- [ ] Forest hex density at the `true` preset ≈ 2 000 trees (± 10 %) as a *visual* count (full trees + impostors + shell), derived from `MapScale`; `balanced` is unchanged.
- [ ] Full 3D trees only within a range given in metres (default 250 m), impostors to ~1 km, beyond that canopy shell; ranges scale with tree size (a test with two tree sizes).
- [ ] Per-frame budget: full-tree instance count ≤ a data-driven cap (`LookPreset`); exceeding it drops the farthest first (test with a synthetic camera).
- [ ] Scatter stays deterministic: same seed → same tree positions (no new RNG outside the existing streams); the `true` preset adds no extra simulation draws.
- [ ] Grass and ground cover at real size (0.3–1.5 m) and real density only within ~100 m of the camera.
- [ ] Frame time on Suwałki at distances 46 / 24 / 7 with `SCREENSHOT_SCALE_PRESET=true` ≤ 16.7 ms avg on the RX 580 (or the shortfall is recorded for the human); numbers in the implementation notes.
- [ ] Screenshots Read by the agent: a forest hex at 46, 24, 7 and 1.2 reads as a closed forest, no visible pop between levels.

## Playtest (for the human)

1. Suwałki at all zoom levels with the `true` preset: forests look dense, no flicker when zooming.
2. Frame rate stays smooth while panning across forests.

## Player manual

None (look only).

## Out of scope

- Terrain mesh and textures (TASK-134); making `true` the default (TASK-138).

## Implementation notes

_Filled in by the agent when done._
